-- Run after all Phase 1/Phase 2/Didit/hardening migrations. Always rolls back.
begin;

do $$
declare
  v_uid text:='phase2-hardening-driver';
  v_hash text:=public.driver_identity_installation_hash('phase2-hardening-driver','phase2-hardening-install');
  v_reference uuid;
  v_challenge uuid;
  v_first_authorization uuid;
begin
  update public.driver_verification_settings set global_enforcement_enabled=false,
    identity_recheck_enabled=false,identity_provider='didit';
  insert into public.driver_verification_rollout(driver_firebase_uid,enforcement_enabled,identity_recheck_enabled)
    values(v_uid,true,true);
  insert into public.driver_verification_submissions(driver_firebase_uid,requirement_key,status,document_paths)
    values(v_uid,'profile_selfie','verified',jsonb_build_object('selfie',v_uid||'/profile_selfie/reference.jpg'))
    returning id into v_reference;
  insert into public.driver_identity_recheck_state(driver_firebase_uid) values(v_uid);

  insert into public.driver_identity_online_authorizations(driver_firebase_uid,installation_hash,expires_at)
    values(v_uid,v_hash,now()+interval '1 hour') returning id into v_first_authorization;
  if not public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'valid authorization should allow before a challenge'; end if;

  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,
    installation_hash,max_attempts,expires_at)
  values(v_uid,v_reference,array['periodic'],v_hash,3,now()+interval '15 minutes') returning id into v_challenge;
  if (select revoked_at is null from public.driver_identity_online_authorizations where id=v_first_authorization)
  then raise exception 'new required challenge must revoke older authorization'; end if;
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'active challenge must fail closed'; end if;

  insert into public.driver_identity_provider_session_secrets(challenge_id,provider,provider_session_reference,verification_url,expires_at)
  values(v_challenge,'didit','hardening-session-0001','https://verify.didit.me/session/test',now()+interval '10 minutes');
  update public.driver_identity_challenges set status='expired',completed_at=now() where id=v_challenge;
  if exists(select 1 from public.driver_identity_provider_session_secrets where challenge_id=v_challenge)
  then raise exception 'terminal challenge must remove hosted session secret'; end if;

  insert into public.driver_identity_online_authorizations(driver_firebase_uid,installation_hash,expires_at)
    values(v_uid,v_hash,now()+interval '1 hour') returning id into v_first_authorization;
  insert into public.driver_identity_online_authorizations(driver_firebase_uid,installation_hash,expires_at)
    values(v_uid,v_hash,now()+interval '2 hours');
  if (select revoked_at is null from public.driver_identity_online_authorizations where id=v_first_authorization)
  then raise exception 'new authorization must revoke previous authorization'; end if;
  if (select count(*) from public.driver_identity_online_authorizations where driver_firebase_uid=v_uid and revoked_at is null)<>1
  then raise exception 'only one unrevoked authorization may remain'; end if;

  update public.driver_identity_recheck_state set force_next_check=true where driver_firebase_uid=v_uid;
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'forced check must fail closed despite valid authorization'; end if;
  update public.driver_identity_recheck_state set force_next_check=false where driver_firebase_uid=v_uid;
  update public.driver_identity_online_authorizations set expires_at=now()-interval '1 second',
    authorized_at=now()-interval '2 hours' where driver_firebase_uid=v_uid and revoked_at is null;
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'expired authorization must fail closed'; end if;

  if (select identity_recheck_enabled from public.driver_verification_settings where singleton)
  then raise exception 'global Phase 2 must stay off'; end if;

  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,
    installation_hash,max_attempts,expires_at)
  values(v_uid,v_reference,array['periodic'],v_hash,3,now()-interval '1 second') returning id into v_challenge;
  perform set_config('test.expired_identity_challenge',v_challenge::text,true);
end $$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"phase2-hardening-driver","iss":"https://securetoken.google.com/driverlumo","aud":"driverlumo"}',true);
do $$
declare v_failed boolean:=false; v_result jsonb; v_challenge uuid:=current_setting('test.expired_identity_challenge')::uuid;
begin
  v_result:=public.prepare_driver_identity_provider_session_v1(v_challenge,'phase2-hardening-install');
  if not coalesce((v_result->>'expired')::boolean,false) then raise exception 'expired prepare must return a terminal result'; end if;
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'expired'
  then raise exception 'expired prepare must persist challenge expiration'; end if;
  begin perform count(*) from public.driver_identity_provider_session_secrets;
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'authenticated client must not read hosted session secrets'; end if;
end $$;
reset role;

rollback;
