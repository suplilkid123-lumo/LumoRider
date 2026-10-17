-- Run after Phase 1, Phase 2, and Didit staging migrations in a disposable project. Always rolls back.
begin;

do $$
declare
  v_uid text:='didit-regression-driver';
  v_other text:='didit-regression-other';
  v_hash text;
  v_reference uuid;
  v_challenge uuid;
  v_other_challenge uuid;
  v_result jsonb;
  v_failed boolean;
begin
  update public.driver_verification_settings set global_enforcement_enabled=false,identity_recheck_enabled=false,
    identity_provider='didit',random_check_probability=0,identity_cooldown_minutes=60;
  insert into public.driver_verification_rollout(driver_firebase_uid,enforcement_enabled,identity_recheck_enabled)
    values(v_uid,true,true),(v_other,true,true);
  insert into public.driver_verification_submissions(driver_firebase_uid,requirement_key,status,document_paths)
    values(v_uid,'profile_selfie','verified',jsonb_build_object('selfie',v_uid||'/profile_selfie/reference.jpg'))
    returning id into v_reference;
  v_hash:=public.driver_identity_installation_hash(v_uid,'didit-test-install-0001');

  -- Selected-driver rollout is active while the global Phase 2 switch remains off.
  if (select identity_recheck_enabled from public.driver_verification_settings where singleton) then raise exception 'global Phase 2 must remain disabled'; end if;
  if not public.driver_identity_recheck_enabled_for(v_uid) then raise exception 'selected rollout must be enabled'; end if;
  if public.driver_identity_recheck_enabled_for('not-selected-driver') then raise exception 'non-selected driver must remain unaffected'; end if;

  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,
    max_attempts,expires_at,status,provider,provider_session_reference,attempt_count)
  values(v_uid,v_reference,array['admin_forced'],v_hash,3,now()+interval '15 minutes','in_progress','didit',
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',1) returning id into v_challenge;
  v_result:=public.process_driver_identity_provider_event_v1('didit','aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    'event-pass-0001',v_challenge::text,'passed',null,'{"liveness_score":95,"face_match_score":96}'::jsonb);
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'passed' then raise exception 'trusted provider success must pass'; end if;
  if not public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'trusted provider success must create authorization'; end if;
  v_result:=public.process_driver_identity_provider_event_v1('didit','aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    'event-pass-0001',v_challenge::text,'passed',null,'{}'::jsonb);
  if not coalesce((v_result->>'duplicate')::boolean,false) then raise exception 'duplicate webhook event must be idempotent'; end if;
  if (select count(*) from public.driver_identity_provider_events where provider='didit' and event_reference='event-pass-0001')<>1
  then raise exception 'duplicate provider event must be stored once'; end if;

  v_failed:=false;
  begin
    perform public.process_driver_identity_provider_event_v1('didit','aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      'event-pass-0001',gen_random_uuid()::text,'passed',null,'{}'::jsonb);
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'replayed event with changed challenge must be rejected'; end if;

  insert into public.driver_verification_submissions(driver_firebase_uid,requirement_key,status,document_paths)
    values(v_other,'profile_selfie','verified',jsonb_build_object('selfie',v_other||'/profile_selfie/reference.jpg')) returning id into v_reference;
  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,
    max_attempts,expires_at,status,provider,provider_session_reference,attempt_count)
  values(v_other,v_reference,array['new_installation'],public.driver_identity_installation_hash(v_other,'didit-test-install-0002'),
    3,now()+interval '15 minutes','in_progress','didit','bbbbbbbb-cccc-4ddd-8eee-ffffffffffff',1) returning id into v_other_challenge;
  v_failed:=false;
  begin
    perform public.process_driver_identity_provider_event_v1('didit','bbbbbbbb-cccc-4ddd-8eee-ffffffffffff',
      'event-cross-0001',v_challenge::text,'passed',null,'{}'::jsonb);
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'cross-driver provider mapping must be rejected'; end if;

  v_failed:=false;
  begin
    perform public.process_driver_identity_provider_event_v1('didit','cccccccc-dddd-4eee-8fff-000000000000',
      'event-unknown-0001',gen_random_uuid()::text,'passed',null,'{}'::jsonb);
  exception when no_data_found then v_failed:=true; end;
  if not v_failed then raise exception 'unknown provider session must be rejected'; end if;

  -- A provider pass after Lumo challenge expiration never authorizes.
  update public.driver_identity_online_authorizations set revoked_at=now() where driver_firebase_uid=v_uid and revoked_at is null;
  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,
    max_attempts,expires_at,status,provider,provider_session_reference,attempt_count)
  values(v_uid,(select id from public.driver_verification_submissions where driver_firebase_uid=v_uid and requirement_key='profile_selfie'),
    array['periodic'],v_hash,3,now()-interval '1 second','in_progress','didit','dddddddd-eeee-4fff-8000-111111111111',1) returning id into v_challenge;
  perform public.process_driver_identity_provider_event_v1('didit','dddddddd-eeee-4fff-8000-111111111111',
    'event-expired-0001',v_challenge::text,'passed',null,'{}'::jsonb);
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'expired' then raise exception 'late pass must expire'; end if;
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'late pass must not authorize'; end if;

  -- Failure below the limit creates a bounded cooldown; final failure locks.
  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,
    max_attempts,expires_at,status,provider,provider_session_reference,attempt_count)
  values(v_uid,(select id from public.driver_verification_submissions where driver_firebase_uid=v_uid and requirement_key='profile_selfie'),
    array['periodic'],v_hash,2,now()+interval '15 minutes','in_progress','didit','eeeeeeee-ffff-4000-8111-222222222222',1) returning id into v_challenge;
  perform public.process_driver_identity_provider_event_v1('didit','eeeeeeee-ffff-4000-8111-222222222222',
    'event-fail-0001',v_challenge::text,'failed','liveness_not_verified','{}'::jsonb);
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'pending' then raise exception 'first failure must permit retry'; end if;
  if (select cooldown_until<=now() from public.driver_identity_challenges where id=v_challenge) then raise exception 'retry cooldown must be future'; end if;
  update public.driver_identity_challenges set cooldown_until=now()-interval '1 second',status='in_progress',
    provider_session_reference='ffffffff-0000-4111-8222-333333333333',attempt_count=2 where id=v_challenge;
  perform public.process_driver_identity_provider_event_v1('didit','ffffffff-0000-4111-8222-333333333333',
    'event-fail-0002',v_challenge::text,'failed','reference_face_mismatch','{}'::jsonb);
  if (select status from public.driver_identity_challenges where id=v_challenge)<>'failed' then raise exception 'maximum attempts must lock'; end if;

  -- Expired authorization blocks immediately.
  insert into public.driver_identity_online_authorizations(driver_firebase_uid,installation_hash,expires_at)
    values(v_uid,v_hash,now()-interval '1 second');
  if public.driver_identity_recheck_online_allowed(v_uid) then raise exception 'expired authorization must block'; end if;

  -- Unique partial index prevents duplicate active challenges.
  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,max_attempts,expires_at)
  values(v_uid,(select id from public.driver_verification_submissions where driver_firebase_uid=v_uid and requirement_key='profile_selfie'),
    array['periodic'],v_hash,3,now()+interval '15 minutes') returning id into v_challenge;
  v_failed:=false;
  begin
    insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,installation_hash,max_attempts,expires_at)
    values(v_uid,(select id from public.driver_verification_submissions where driver_firebase_uid=v_uid and requirement_key='profile_selfie'),
      array['periodic'],v_hash,3,now()+interval '15 minutes');
  exception when unique_violation then v_failed:=true; end;
  if not v_failed then raise exception 'duplicate active challenge must be prevented'; end if;
end $$;

-- Authenticated clients cannot manufacture a pass, authorization, trusted installation, or provider attachment.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"didit-regression-driver","iss":"https://securetoken.google.com/driverlumo","aud":"driverlumo"}',true);
do $$
declare v_failed boolean;
begin
  v_failed:=false;
  begin update public.driver_identity_challenges set status='passed' where driver_firebase_uid='didit-regression-driver';
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'client challenge pass write must be denied'; end if;
  v_failed:=false;
  begin insert into public.driver_identity_online_authorizations(driver_firebase_uid,installation_hash,expires_at)
    values('didit-regression-driver',repeat('a',64),now()+interval '1 hour');
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'client authorization write must be denied'; end if;
  v_failed:=false;
  begin insert into public.driver_identity_trusted_installations(driver_firebase_uid,installation_hash)
    values('didit-regression-driver',repeat('a',64));
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'client trusted-installation write must be denied'; end if;
  v_failed:=false;
  begin perform public.attach_driver_identity_provider_session_v1(gen_random_uuid(),gen_random_uuid(),'didit',
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee','https://verify.didit.me/session/token');
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'client provider attachment must be denied'; end if;
end $$;
reset role;

rollback;
