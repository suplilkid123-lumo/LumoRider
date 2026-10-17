begin;

-- Security decisions use backend-observed ride/delivery lifecycle activity.
-- The legacy last_online_authorized_at remains for compatibility and display only.
alter table public.driver_identity_recheck_state
  add column if not exists last_trusted_driver_activity_at timestamptz;

-- Any required challenge immediately invalidates older online grants. This also
-- closes assignment paths that do not originate from the iOS Go Online control.
create or replace function public.revoke_identity_authorizations_for_challenge_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if new.status in ('pending','in_progress') then
    update public.driver_identity_online_authorizations
    set revoked_at=statement_timestamp()
    where driver_firebase_uid=new.driver_firebase_uid and revoked_at is null;
  end if;
  return new;
end; $$;

drop trigger if exists revoke_identity_authorizations_for_challenge on public.driver_identity_challenges;
create trigger revoke_identity_authorizations_for_challenge
after insert on public.driver_identity_challenges
for each row execute function public.revoke_identity_authorizations_for_challenge_v1();

update public.driver_identity_online_authorizations authz
set revoked_at=statement_timestamp()
where authz.revoked_at is null and exists(
  select 1 from public.driver_identity_challenges challenge
  where challenge.driver_firebase_uid=authz.driver_firebase_uid
    and challenge.status in ('pending','in_progress')
);

-- Keep exactly one unrevoked authorization per driver. Expired rows are retained
-- as audit history but cannot coexist as an apparently current grant.
create or replace function public.revoke_previous_identity_authorizations_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  update public.driver_identity_online_authorizations
  set revoked_at=statement_timestamp()
  where driver_firebase_uid=new.driver_firebase_uid and revoked_at is null;
  return new;
end; $$;

drop trigger if exists revoke_previous_identity_authorizations on public.driver_identity_online_authorizations;
create trigger revoke_previous_identity_authorizations
before insert on public.driver_identity_online_authorizations
for each row execute function public.revoke_previous_identity_authorizations_v1();

update public.driver_identity_online_authorizations
set revoked_at=coalesce(revoked_at,statement_timestamp())
where expires_at<=authorized_at;

alter table public.driver_identity_online_authorizations
  drop constraint if exists driver_identity_authorization_time_check;
alter table public.driver_identity_online_authorizations
  add constraint driver_identity_authorization_time_check check (expires_at>authorized_at) not valid;
alter table public.driver_identity_online_authorizations
  validate constraint driver_identity_authorization_time_check;

create or replace function public.driver_identity_recheck_online_allowed(p_driver_uid text)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select case
    when not public.driver_identity_recheck_enabled_for(p_driver_uid) then true
    when coalesce((select force_next_check from public.driver_identity_recheck_state where driver_firebase_uid=p_driver_uid),false) then false
    when exists(
      select 1 from public.driver_identity_challenges challenge
      where challenge.driver_firebase_uid=p_driver_uid and challenge.status in ('pending','in_progress')
    ) then false
    else exists(
      select 1 from public.driver_identity_online_authorizations authz
      where authz.driver_firebase_uid=p_driver_uid
        and authz.revoked_at is null
        and authz.expires_at>statement_timestamp()
    )
  end;
$$;

-- Persist expiration instead of raising from the same transaction (a raised
-- exception would roll the expiration update back).
create or replace function public.prepare_driver_identity_provider_session_v1(p_challenge_id uuid,p_installation_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_uid text:=public.passenger_authenticated_user_id();
  v_hash text;
  v_challenge public.driver_identity_challenges%rowtype;
  v_path text;
  v_creation_token uuid;
  v_now timestamptz:=statement_timestamp();
begin
  if not public.passenger_is_driver_jwt() then raise exception 'Driver authentication is required.' using errcode='42501'; end if;
  v_hash:=public.driver_identity_installation_hash(v_uid,p_installation_id);
  select * into v_challenge from public.driver_identity_challenges
  where id=p_challenge_id and driver_firebase_uid=v_uid for update;
  if not found then raise exception 'Challenge not found.' using errcode='P0002'; end if;
  if v_challenge.installation_hash<>v_hash then raise exception 'Challenge installation mismatch.' using errcode='42501'; end if;
  if v_challenge.expires_at<=v_now then
    if v_challenge.status in ('pending','in_progress') then
      update public.driver_identity_challenges set status='expired',completed_at=v_now,result_category='expired',
        failure_category=coalesce(failure_category,'challenge_expired'),updated_at=v_now where id=p_challenge_id;
      insert into public.driver_identity_challenge_events(challenge_id,event_type,actor_type)
      values(p_challenge_id,'challenge_expired','system');
    end if;
    return jsonb_build_object('challenge_id',v_challenge.id,'expired',true,'expires_at',v_challenge.expires_at);
  end if;
  if v_challenge.status='in_progress' then
    return jsonb_build_object('challenge_id',v_challenge.id,'driver_firebase_uid',v_uid,'resume_session',true,
      'expires_at',v_challenge.expires_at,'attempt_number',v_challenge.attempt_count);
  end if;
  if v_challenge.status<>'pending' then raise exception 'Challenge is not available.' using errcode='55000'; end if;
  if v_challenge.attempt_count>=v_challenge.max_attempts then raise exception 'Maximum attempts reached.' using errcode='55000'; end if;
  if v_challenge.cooldown_until is not null and v_challenge.cooldown_until>v_now then raise exception 'Retry cooldown is active.' using errcode='55000'; end if;
  if v_challenge.provider_session_creation_expires_at is not null and v_challenge.provider_session_creation_expires_at>v_now then
    raise exception 'A provider session is already being created.' using errcode='55000';
  end if;
  select document_paths->>'selfie' into v_path from public.driver_verification_submissions
  where id=v_challenge.reference_submission_id and driver_firebase_uid=v_uid and status='verified' and requirement_key='profile_selfie';
  if v_path is null then raise exception 'Approved reference selfie is unavailable.' using errcode='55000'; end if;
  v_creation_token:=gen_random_uuid();
  update public.driver_identity_challenges set provider_session_creation_token=v_creation_token,
    provider_session_creation_expires_at=v_now+interval '2 minutes',updated_at=v_now where id=p_challenge_id;
  return jsonb_build_object('challenge_id',v_challenge.id,'driver_firebase_uid',v_uid,'resume_session',false,
    'reference_storage_path',v_path,'expires_at',v_challenge.expires_at,'attempt_number',v_challenge.attempt_count+1,
    'creation_token',v_creation_token);
end; $$;

-- Replace policy evaluation so long-absence checks never trust a timestamp
-- written by the driver's availability toggle.
create or replace function public.evaluate_driver_identity_recheck_v1(p_installation_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,auth,public as $$
declare
  v_uid text:=public.passenger_authenticated_user_id();
  v_hash text;
  v_settings public.driver_verification_settings%rowtype;
  v_state public.driver_identity_recheck_state%rowtype;
  v_reference uuid;
  v_challenge public.driver_identity_challenges%rowtype;
  v_reasons text[]:=array[]::text[];
  v_enabled boolean;
  v_now timestamptz:=statement_timestamp();
begin
  if not public.passenger_is_driver_jwt() then raise exception 'Driver authentication is required.' using errcode='42501'; end if;
  v_hash:=public.driver_identity_installation_hash(v_uid,p_installation_id);
  select * into v_settings from public.driver_verification_settings where singleton;
  if not found then raise exception 'Identity policy is unavailable.' using errcode='55000'; end if;
  v_enabled:=public.driver_identity_recheck_enabled_for(v_uid);
  if not v_enabled then return jsonb_build_object('policy_enabled',false,'required',false,'allowed_to_go_online',true); end if;
  if not public.driver_verification_online_allowed(v_uid) then
    return jsonb_build_object('policy_enabled',true,'required',false,'allowed_to_go_online',false,'reason','phase1_verification_required');
  end if;
  v_reference:=public.driver_identity_has_approved_reference(v_uid);
  if v_reference is null then
    return jsonb_build_object('policy_enabled',true,'required',true,'allowed_to_go_online',false,'reason','approved_reference_required');
  end if;

  insert into public.driver_identity_recheck_state(driver_firebase_uid) values(v_uid)
  on conflict(driver_firebase_uid) do nothing;
  select * into v_state from public.driver_identity_recheck_state where driver_firebase_uid=v_uid for update;

  update public.driver_identity_challenges set status='expired',completed_at=v_now,result_category='expired',
    failure_category=coalesce(failure_category,'challenge_expired'),updated_at=v_now
  where driver_firebase_uid=v_uid and status in ('pending','in_progress') and expires_at<=v_now;
  insert into public.driver_identity_challenge_events(challenge_id,event_type,actor_type)
  select id,'challenge_expired','system' from public.driver_identity_challenges
  where driver_firebase_uid=v_uid and status='expired' and completed_at=v_now
  on conflict do nothing;

  select * into v_challenge from public.driver_identity_challenges
  where driver_firebase_uid=v_uid and status in ('pending','in_progress') order by created_at desc limit 1;
  if found then
    return jsonb_build_object('policy_enabled',true,'required',true,'allowed_to_go_online',false,
      'reason','active_challenge','challenge',jsonb_build_object('id',v_challenge.id,'status',v_challenge.status,
      'trigger_reasons',v_challenge.trigger_reasons,'attempt_count',v_challenge.attempt_count,'max_attempts',v_challenge.max_attempts,
      'expires_at',v_challenge.expires_at,'cooldown_until',v_challenge.cooldown_until,'provider',v_challenge.provider));
  end if;

  if not v_state.force_next_check and exists(
    select 1 from public.driver_identity_online_authorizations
    where driver_firebase_uid=v_uid and installation_hash=v_hash and revoked_at is null and expires_at>v_now
  ) then return jsonb_build_object('policy_enabled',true,'required',false,'allowed_to_go_online',true); end if;

  select * into v_challenge from public.driver_identity_challenges
  where driver_firebase_uid=v_uid and status='failed' and cooldown_until>v_now order by created_at desc limit 1;
  if found then
    return jsonb_build_object('policy_enabled',true,'required',true,'allowed_to_go_online',false,'reason','cooldown_locked',
      'challenge',jsonb_build_object('id',v_challenge.id,'status',v_challenge.status,'trigger_reasons',v_challenge.trigger_reasons,
      'attempt_count',v_challenge.attempt_count,'max_attempts',v_challenge.max_attempts,'expires_at',v_challenge.expires_at,
      'cooldown_until',v_challenge.cooldown_until,'provider',v_challenge.provider));
  end if;

  if v_state.force_next_check then v_reasons:=array_append(v_reasons,'admin_forced'); end if;
  if v_settings.new_device_requires_check and not exists(
    select 1 from public.driver_identity_trusted_installations where driver_firebase_uid=v_uid and installation_hash=v_hash
  ) then v_reasons:=array_append(v_reasons,'new_installation'); end if;
  if v_state.last_trusted_driver_activity_at is not null
    and v_state.last_trusted_driver_activity_at<v_now-make_interval(days=>v_settings.absence_trigger_days)
  then v_reasons:=array_append(v_reasons,'long_absence'); end if;
  if v_state.last_success_at is not null and v_state.last_success_at<v_now-make_interval(days=>v_settings.recheck_interval_days)
  then v_reasons:=array_append(v_reasons,'periodic'); end if;
  if v_settings.random_check_probability>0
    and (v_state.last_success_at is null or v_state.last_success_at<v_now-interval '1 day')
    and random()<v_settings.random_check_probability
  then v_reasons:=array_append(v_reasons,'controlled_random'); end if;

  if cardinality(v_reasons)=0 then
    insert into public.driver_identity_online_authorizations(driver_firebase_uid,installation_hash,expires_at)
    values(v_uid,v_hash,v_now+make_interval(hours=>v_settings.online_authorization_hours));
    return jsonb_build_object('policy_enabled',true,'required',false,'allowed_to_go_online',true);
  end if;

  insert into public.driver_identity_challenges(driver_firebase_uid,reference_submission_id,trigger_reasons,provider,
    installation_hash,max_attempts,expires_at)
  values(v_uid,v_reference,v_reasons,v_settings.identity_provider,v_hash,v_settings.identity_max_attempts,
    v_now+make_interval(mins=>v_settings.challenge_expiration_minutes)) returning * into v_challenge;
  update public.driver_identity_recheck_state set last_challenge_id=v_challenge.id,updated_at=v_now where driver_firebase_uid=v_uid;
  insert into public.driver_identity_challenge_events(challenge_id,event_type,actor_type,safe_metadata)
  values(v_challenge.id,'challenge_created','system',jsonb_build_object('triggers',v_reasons));
  return jsonb_build_object('policy_enabled',true,'required',true,'allowed_to_go_online',false,'reason','challenge_required',
    'challenge',jsonb_build_object('id',v_challenge.id,'status',v_challenge.status,'trigger_reasons',v_challenge.trigger_reasons,
    'attempt_count',0,'max_attempts',v_challenge.max_attempts,'expires_at',v_challenge.expires_at,'provider',v_challenge.provider));
end; $$;

-- Provider session URLs are bearer-like secrets. Remove them whenever a
-- challenge becomes terminal, including expiry outside webhook processing.
create or replace function public.cleanup_driver_identity_provider_secret_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if new.status in ('passed','failed','expired','cancelled') and old.status is distinct from new.status then
    delete from public.driver_identity_provider_session_secrets where challenge_id=new.id;
    new.provider_session_creation_token:=null;
    new.provider_session_creation_expires_at:=null;
  end if;
  return new;
end; $$;

drop trigger if exists cleanup_driver_identity_provider_secret on public.driver_identity_challenges;
create trigger cleanup_driver_identity_provider_secret
before update of status on public.driver_identity_challenges
for each row execute function public.cleanup_driver_identity_provider_secret_v1();

create or replace function public.record_driver_identity_ride_activity_v1() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if new.driver_id is not null and public.driver_identity_recheck_enabled_for(new.driver_id)
    and ((old.driver_id is null and new.driver_id is not null) or
      (old.status is distinct from new.status and new.status in ('accepted','arrived_at_pickup','in_progress','completed')))
  then
    insert into public.driver_identity_recheck_state(driver_firebase_uid,last_trusted_driver_activity_at)
    values(new.driver_id,statement_timestamp()) on conflict(driver_firebase_uid) do update
      set last_trusted_driver_activity_at=excluded.last_trusted_driver_activity_at,updated_at=statement_timestamp();
  end if;
  return new;
end; $$;

create or replace function public.record_driver_identity_food_activity_v1() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if new.assigned_driver_firebase_uid is not null
    and public.driver_identity_recheck_enabled_for(new.assigned_driver_firebase_uid)
    and ((old.assigned_driver_firebase_uid is null and new.assigned_driver_firebase_uid is not null)
      or (old.dispatch_status is distinct from new.dispatch_status
        and new.dispatch_status in ('assigned','at_restaurant','picked_up','on_the_way','delivered')))
  then
    insert into public.driver_identity_recheck_state(driver_firebase_uid,last_trusted_driver_activity_at)
    values(new.assigned_driver_firebase_uid,statement_timestamp()) on conflict(driver_firebase_uid) do update
      set last_trusted_driver_activity_at=excluded.last_trusted_driver_activity_at,updated_at=statement_timestamp();
  end if;
  return new;
end; $$;

drop trigger if exists record_driver_identity_food_activity on public.food_delivery_jobs;
create trigger record_driver_identity_food_activity
after update of assigned_driver_firebase_uid,dispatch_status on public.food_delivery_jobs
for each row execute function public.record_driver_identity_food_activity_v1();

-- Admin visibility combines rollout, actual Phase 1 completion, current/last
-- challenge, authorization, and authoritative activity without exposing images.
create or replace function public.admin_list_driver_identity_rechecks_v1() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_result jsonb;
begin
  if not public.is_lumo_admin() then raise exception 'Admin authorization is required.' using errcode='42501'; end if;
  with driver_ids as (
    select driver_firebase_uid from public.driver_identity_recheck_state
    union select driver_firebase_uid from public.driver_verification_rollout where identity_recheck_enabled
    union select driver_firebase_uid from public.driver_identity_challenges
  ), phase1 as (
    select d.driver_firebase_uid,
      count(*) filter(where req.is_required)::integer as required_count,
      count(*) filter(where req.is_required and public.driver_verification_effective_status(
        sub.status,sub.expiration_date,settings.expiring_soon_days) in ('verified','expiring_soon'))::integer as verified_count
    from driver_ids d cross join public.driver_verification_settings settings
    join public.driver_verification_requirements req on req.active
    left join public.driver_verification_submissions sub on sub.driver_firebase_uid=d.driver_firebase_uid
      and sub.requirement_key=req.requirement_key
    where settings.singleton group by d.driver_firebase_uid
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'driver_firebase_uid',ids.driver_firebase_uid,
    'phase1_enforcement_enabled',public.driver_verification_enforcement_enabled(ids.driver_firebase_uid),
    'phase1_required_count',coalesce(phase1.required_count,0),
    'phase1_verified_required_count',coalesce(phase1.verified_count,0),
    'phase1_verification_complete',coalesce(phase1.required_count,0)>0 and phase1.required_count=phase1.verified_count,
    'phase2_rollout_enabled',coalesce(rollout.identity_recheck_enabled,false),
    'phase2_effective_enabled',public.driver_identity_recheck_enabled_for(ids.driver_firebase_uid),
    'force_next_check',coalesce(state.force_next_check,false),'force_reason',state.force_reason,
    'last_success_at',state.last_success_at,
    'last_trusted_driver_activity_at',state.last_trusted_driver_activity_at,
    'challenge_id',challenge.id,'challenge_status',challenge.status,'trigger_reasons',challenge.trigger_reasons,
    'attempt_count',challenge.attempt_count,'max_attempts',challenge.max_attempts,'created_at',challenge.created_at,
    'completed_at',challenge.completed_at,'challenge_expires_at',challenge.expires_at,
    'cooldown_until',challenge.cooldown_until,'failure_category',challenge.failure_category,'provider',challenge.provider,
    'online_authorization_expires_at',current_auth.expires_at
  ) order by coalesce(challenge.created_at,state.updated_at) desc),'[]'::jsonb) into v_result
  from driver_ids ids
  left join public.driver_identity_recheck_state state on state.driver_firebase_uid=ids.driver_firebase_uid
  left join public.driver_verification_rollout rollout on rollout.driver_firebase_uid=ids.driver_firebase_uid
  left join phase1 on phase1.driver_firebase_uid=ids.driver_firebase_uid
  left join lateral (
    select candidate.* from public.driver_identity_challenges candidate
    where candidate.driver_firebase_uid=ids.driver_firebase_uid
    order by (candidate.status in ('pending','in_progress')) desc,candidate.created_at desc limit 1
  ) challenge on true
  left join lateral (
    select candidate.expires_at from public.driver_identity_online_authorizations candidate
    where candidate.driver_firebase_uid=ids.driver_firebase_uid and candidate.revoked_at is null
      and candidate.expires_at>statement_timestamp()
    order by candidate.expires_at desc limit 1
  ) current_auth on true;
  return v_result;
end; $$;

revoke all on function public.revoke_identity_authorizations_for_challenge_v1() from public,anon,authenticated;
revoke all on function public.revoke_previous_identity_authorizations_v1() from public,anon,authenticated;
revoke all on function public.cleanup_driver_identity_provider_secret_v1() from public,anon,authenticated;
revoke all on function public.record_driver_identity_ride_activity_v1() from public,anon,authenticated;
revoke all on function public.record_driver_identity_food_activity_v1() from public,anon,authenticated;
revoke all on function public.admin_list_driver_identity_rechecks_v1() from public,anon;
grant execute on function public.admin_list_driver_identity_rechecks_v1() to authenticated;

commit;
