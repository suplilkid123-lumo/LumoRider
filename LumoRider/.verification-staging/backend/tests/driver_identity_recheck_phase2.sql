-- Run after both verification migrations in a disposable Supabase project. Always rolls back.
begin;
do $$
declare v_uid text:='identity-regression-driver'; v_hash text; v_reference uuid; v_challenge uuid;
begin
  update public.driver_verification_settings set identity_recheck_enabled=false,random_check_probability=0;
  if not public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'disabled policy must allow existing drivers'; end if;
  insert into public.driver_verification_rollout(driver_firebase_uid,enforcement_enabled,identity_recheck_enabled)
    values(v_uid,true,true);
  insert into public.driver_verification_submissions(driver_firebase_uid,requirement_key,status,document_paths)
    values(v_uid,'profile_selfie','verified',jsonb_build_object('selfie',v_uid||'/profile_selfie/reference.jpg')) returning id into v_reference;
  insert into public.driver_verification_submissions(driver_firebase_uid,requirement_key,status,document_paths,expiration_date,associated_vehicle_id)
    select v_uid,requirement_key,'verified',case when requires_document then
      (select jsonb_object_agg(slot,to_jsonb(v_uid||'/'||requirement_key||'/fixture-'||slot||'.jpg')) from unnest(document_slots) slot)
      else '{}'::jsonb end,current_date+365,case when requires_vehicle then 'primary' end
    from public.driver_verification_requirements where requirement_key<>'profile_selfie';
  v_hash:=public.driver_identity_installation_hash(v_uid,'test-installation-0001');
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'enabled driver without authorization must be blocked'; end if;
  insert into public.driver_identity_recheck_state(driver_firebase_uid,force_next_check) values(v_uid,true);
  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,max_attempts,expires_at)
    values(v_uid,v_reference,array['admin_forced'],v_hash,3,now()+interval '15 minutes') returning id into v_challenge;
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'pending challenge must block'; end if;
  update public.driver_identity_challenges set status='in_progress',provider='fixture',provider_session_reference='fixture-session',attempt_count=1 where id=v_challenge;
  perform public.complete_driver_identity_challenge_provider_v1(v_challenge,'fixture-session','fixture-event-pass','passed');
  if not public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'trusted provider pass must authorize online'; end if;
  update public.driver_identity_recheck_state set force_next_check=true,force_reason='Regression forced check' where driver_firebase_uid=v_uid;
  update public.driver_identity_online_authorizations set revoked_at=now() where driver_firebase_uid=v_uid and revoked_at is null;
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'admin force must revoke authorization'; end if;

  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,max_attempts,expires_at,status,provider,provider_session_reference,attempt_count)
    values(v_uid,v_reference,array['admin_forced'],v_hash,2,now()+interval '15 minutes','in_progress','fixture','fixture-fail-1',1) returning id into v_challenge;
  perform public.complete_driver_identity_challenge_provider_v1(v_challenge,'fixture-fail-1','fixture-event-fail-1','failed','not_verified');
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'pending' then raise exception 'first failure must permit bounded retry'; end if;
  update public.driver_identity_challenges set cooldown_until=now()-interval '1 second' where id=v_challenge;
  update public.driver_identity_challenges set status='in_progress',provider_session_reference='fixture-fail-2',
    attempt_count=attempt_count+1 where id=v_challenge;
  perform public.complete_driver_identity_challenge_provider_v1(v_challenge,'fixture-fail-2','fixture-event-fail-2','failed','not_verified');
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'failed' then raise exception 'maximum attempts must lock challenge'; end if;

  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,max_attempts,expires_at,status,provider,provider_session_reference,attempt_count)
    values(v_uid,v_reference,array['periodic'],v_hash,3,now()-interval '1 second','in_progress','fixture','fixture-expired',1) returning id into v_challenge;
  perform public.complete_driver_identity_challenge_provider_v1(v_challenge,'fixture-expired','fixture-event-expired','passed');
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'expired' then raise exception 'expired provider session must never pass'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"different-driver","iss":"https://securetoken.google.com/driverlumo","aud":"driverlumo"}',true);
do $$ begin
  if exists(select 1 from public.driver_identity_challenges where driver_firebase_uid='identity-regression-driver')
  then raise exception 'cross-driver challenge read must be denied'; end if;
end $$;
reset role;
rollback;
