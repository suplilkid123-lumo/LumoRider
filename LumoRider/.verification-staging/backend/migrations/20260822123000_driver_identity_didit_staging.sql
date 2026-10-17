begin;

-- Firebase driver subjects are not required to be UUIDs. Admin checks must
-- return false for those subjects instead of failing while RLS policies run.
create or replace function public.is_lumo_admin() returns boolean
language plpgsql stable security definer set search_path=pg_catalog,auth,public as $$
declare v_uid uuid;
begin
  begin v_uid:=auth.uid();
  exception when invalid_text_representation then return false;
  end;
  return v_uid is not null and exists(select 1 from public.admins where user_id=v_uid);
end; $$;

alter table public.driver_identity_challenges
  add column provider_session_creation_token uuid,
  add column provider_session_creation_expires_at timestamptz;

create unique index driver_identity_provider_session_unique_idx
  on public.driver_identity_challenges(provider,provider_session_reference)
  where provider is not null and provider_session_reference is not null;

create table public.driver_identity_provider_session_secrets (
  challenge_id uuid primary key references public.driver_identity_challenges(id) on delete cascade,
  provider text not null check (provider='didit'),
  provider_session_reference text not null unique,
  verification_url text not null check (verification_url ~ '^https://'),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.driver_identity_provider_events (
  provider text not null,
  event_reference text not null,
  provider_session_reference text not null,
  challenge_id uuid not null references public.driver_identity_challenges(id) on delete cascade,
  normalized_outcome text not null check (normalized_outcome in ('pending','passed','failed','expired','cancelled')),
  received_at timestamptz not null default now(),
  primary key(provider,event_reference)
);

alter table public.driver_identity_provider_session_secrets enable row level security;
alter table public.driver_identity_provider_events enable row level security;

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
  select * into v_challenge from public.driver_identity_challenges where id=p_challenge_id and driver_firebase_uid=v_uid for update;
  if not found then raise exception 'Challenge not found.' using errcode='P0002'; end if;
  if v_challenge.installation_hash<>v_hash then raise exception 'Challenge installation mismatch.' using errcode='42501'; end if;
  if v_challenge.expires_at<=v_now then
    if v_challenge.status in ('pending','in_progress') then
      update public.driver_identity_challenges set status='expired',completed_at=v_now,result_category='expired',updated_at=v_now where id=p_challenge_id;
    end if;
    raise exception 'Challenge has expired.' using errcode='55000';
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

drop function public.attach_driver_identity_provider_session_v1(uuid,text,text);

create function public.attach_driver_identity_provider_session_v1(
  p_challenge_id uuid,p_creation_token uuid,p_provider text,p_provider_session_reference text,p_verification_url text
) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_challenge public.driver_identity_challenges%rowtype;
begin
  select * into v_challenge from public.driver_identity_challenges where id=p_challenge_id for update;
  if not found or v_challenge.status<>'pending' or v_challenge.expires_at<=statement_timestamp()
    or v_challenge.provider_session_creation_token is distinct from p_creation_token
    or v_challenge.provider_session_creation_expires_at<=statement_timestamp()
  then raise exception 'Challenge cannot start.' using errcode='55000'; end if;
  if btrim(p_provider)<>'didit' or length(btrim(coalesce(p_provider_session_reference,''))) not between 36 and 64
    or length(coalesce(p_verification_url,'')) not between 20 and 2048 or p_verification_url !~ '^https://[A-Za-z0-9.-]+/'
  then raise exception 'Provider session is invalid.' using errcode='22023'; end if;
  update public.driver_identity_challenges set status='in_progress',provider='didit',
    provider_session_reference=btrim(p_provider_session_reference),started_at=coalesce(started_at,statement_timestamp()),
    attempt_count=attempt_count+1,provider_session_creation_token=null,provider_session_creation_expires_at=null,
    updated_at=statement_timestamp() where id=p_challenge_id;
  insert into public.driver_identity_provider_session_secrets(challenge_id,provider,provider_session_reference,verification_url,expires_at)
  values(p_challenge_id,'didit',btrim(p_provider_session_reference),p_verification_url,v_challenge.expires_at)
  on conflict(challenge_id) do update set provider_session_reference=excluded.provider_session_reference,
    verification_url=excluded.verification_url,expires_at=excluded.expires_at,created_at=statement_timestamp();
  insert into public.driver_identity_challenge_events(challenge_id,event_type,actor_type)
  values(p_challenge_id,'provider_session_started','system');
end; $$;

create or replace function public.release_driver_identity_provider_session_creation_v1(p_challenge_id uuid,p_creation_token uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  update public.driver_identity_challenges set provider_session_creation_token=null,
    provider_session_creation_expires_at=null,updated_at=statement_timestamp()
  where id=p_challenge_id and status='pending' and provider_session_creation_token=p_creation_token;
end; $$;

create or replace function public.get_driver_identity_provider_session_secret_v1(p_challenge_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_result jsonb;
begin
  select jsonb_build_object('provider',secret.provider,'verification_url',secret.verification_url,
    'expires_at',least(secret.expires_at,challenge.expires_at)) into v_result
  from public.driver_identity_provider_session_secrets secret
  join public.driver_identity_challenges challenge on challenge.id=secret.challenge_id
  where secret.challenge_id=p_challenge_id and challenge.status='in_progress'
    and secret.expires_at>statement_timestamp() and challenge.expires_at>statement_timestamp();
  if v_result is null then raise exception 'Provider session is unavailable.' using errcode='P0002'; end if;
  return v_result;
end; $$;

create or replace function public.complete_driver_identity_challenge_provider_v1(
  p_challenge_id uuid,p_provider_session_reference text,p_provider_event_reference text,
  p_outcome text,p_failure_category text default null,p_safe_risk_metadata jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_challenge public.driver_identity_challenges%rowtype; v_settings public.driver_verification_settings%rowtype; v_now timestamptz:=statement_timestamp();
begin
  if p_outcome not in ('passed','failed','expired','cancelled') then raise exception 'Unsupported provider outcome.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_safe_risk_metadata,'{}'::jsonb))<>'object' then raise exception 'Risk metadata must be an object.' using errcode='22023'; end if;
  select * into v_challenge from public.driver_identity_challenges where id=p_challenge_id for update;
  if not found or v_challenge.status<>'in_progress' or v_challenge.provider_session_reference<>p_provider_session_reference
  then raise exception 'Provider challenge mismatch.' using errcode='42501'; end if;
  if v_challenge.expires_at<=v_now then
    update public.driver_identity_challenges set status='expired',completed_at=v_now,result_category='expired',
      failure_category='challenge_expired',provider_event_reference=p_provider_event_reference,updated_at=v_now where id=p_challenge_id;
    delete from public.driver_identity_provider_session_secrets where challenge_id=p_challenge_id;
    insert into public.driver_identity_challenge_events(challenge_id,event_type,actor_type,provider_event_reference)
    values(p_challenge_id,'provider_result_after_expiration','provider',p_provider_event_reference);
    return;
  end if;
  select * into v_settings from public.driver_verification_settings where singleton;
  if p_outcome='passed' then
    update public.driver_identity_challenges set status='passed',completed_at=v_now,result_category='identity_confirmed',
      provider_event_reference=p_provider_event_reference,risk_metadata=coalesce(p_safe_risk_metadata,'{}'::jsonb),updated_at=v_now where id=p_challenge_id;
    insert into public.driver_identity_trusted_installations(driver_firebase_uid,installation_hash)
      values(v_challenge.driver_firebase_uid,v_challenge.installation_hash)
      on conflict(driver_firebase_uid,installation_hash) do update set last_verified_at=v_now;
    insert into public.driver_identity_online_authorizations(driver_firebase_uid,challenge_id,installation_hash,expires_at)
      values(v_challenge.driver_firebase_uid,p_challenge_id,v_challenge.installation_hash,v_now+make_interval(hours=>v_settings.online_authorization_hours));
    update public.driver_identity_recheck_state set force_next_check=false,force_reason=null,forced_at=null,forced_by=null,
      last_success_at=v_now,last_challenge_id=p_challenge_id,updated_at=v_now where driver_firebase_uid=v_challenge.driver_firebase_uid;
  elsif p_outcome='failed' then
    update public.driver_identity_challenges set status=case when attempt_count>=max_attempts then 'failed'::public.driver_identity_challenge_status else 'pending'::public.driver_identity_challenge_status end,
      provider_session_reference=case when attempt_count>=max_attempts then provider_session_reference else null end,
      completed_at=case when attempt_count>=max_attempts then v_now else null end,
      result_category=case when attempt_count>=max_attempts then 'attempts_exhausted' else 'retry_available' end,
      failure_category=coalesce(nullif(btrim(p_failure_category),''),'not_verified'),provider_event_reference=p_provider_event_reference,
      cooldown_until=v_now+make_interval(mins=>v_settings.identity_cooldown_minutes),risk_metadata=coalesce(p_safe_risk_metadata,'{}'::jsonb),updated_at=v_now where id=p_challenge_id;
  else
    update public.driver_identity_challenges set status=p_outcome::public.driver_identity_challenge_status,completed_at=v_now,
      result_category=p_outcome,failure_category=coalesce(nullif(btrim(p_failure_category),''),'provider_'||p_outcome),
      provider_event_reference=p_provider_event_reference,risk_metadata=coalesce(p_safe_risk_metadata,'{}'::jsonb),updated_at=v_now where id=p_challenge_id;
  end if;
  delete from public.driver_identity_provider_session_secrets where challenge_id=p_challenge_id;
  insert into public.driver_identity_challenge_events(challenge_id,event_type,actor_type,provider_event_reference)
  values(p_challenge_id,'provider_'||p_outcome,'provider',p_provider_event_reference);
end; $$;

create or replace function public.process_driver_identity_provider_event_v1(
  p_provider text,p_provider_session_reference text,p_provider_event_reference text,p_challenge_reference text,
  p_outcome text,p_failure_category text default null,p_safe_risk_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_challenge public.driver_identity_challenges%rowtype; v_existing public.driver_identity_provider_events%rowtype;
begin
  if p_provider<>'didit' or p_outcome not in ('pending','passed','failed','expired','cancelled') then
    raise exception 'Unsupported provider event.' using errcode='22023';
  end if;
  select * into v_existing from public.driver_identity_provider_events where provider=p_provider and event_reference=p_provider_event_reference;
  if found then
    if v_existing.provider_session_reference<>p_provider_session_reference or v_existing.challenge_id::text<>p_challenge_reference
    then raise exception 'Provider event replay mismatch.' using errcode='42501'; end if;
    return jsonb_build_object('duplicate',true,'challenge_id',v_existing.challenge_id,'outcome',v_existing.normalized_outcome);
  end if;
  select * into v_challenge from public.driver_identity_challenges
  where provider=p_provider and provider_session_reference=p_provider_session_reference for update;
  if not found then raise exception 'Unknown provider session.' using errcode='P0002'; end if;
  if v_challenge.id::text<>p_challenge_reference then raise exception 'Provider challenge mapping mismatch.' using errcode='42501'; end if;
  insert into public.driver_identity_provider_events(provider,event_reference,provider_session_reference,challenge_id,normalized_outcome)
  values(p_provider,p_provider_event_reference,p_provider_session_reference,v_challenge.id,p_outcome);
  if p_outcome='pending' then
    if v_challenge.status<>'in_progress' then return jsonb_build_object('duplicate',false,'already_final',true,'challenge_id',v_challenge.id); end if;
    insert into public.driver_identity_challenge_events(challenge_id,event_type,actor_type,provider_event_reference)
    values(v_challenge.id,'provider_status_pending','provider',p_provider_event_reference);
    return jsonb_build_object('duplicate',false,'challenge_id',v_challenge.id,'outcome','pending');
  end if;
  if v_challenge.status<>'in_progress' then
    if (v_challenge.status='passed' and p_outcome='passed') or (v_challenge.status::text=p_outcome) then
      return jsonb_build_object('duplicate',false,'already_final',true,'challenge_id',v_challenge.id,'outcome',p_outcome);
    end if;
    raise exception 'Challenge is already final.' using errcode='55000';
  end if;
  perform public.complete_driver_identity_challenge_provider_v1(v_challenge.id,p_provider_session_reference,
    p_provider_event_reference,p_outcome,p_failure_category,p_safe_risk_metadata);
  return jsonb_build_object('duplicate',false,'challenge_id',v_challenge.id,'outcome',p_outcome);
end; $$;

create or replace function public.guard_driver_identity_on_passenger_assignment_v1() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if old.driver_id is null and new.driver_id is not null
    and (not public.driver_verification_online_allowed(new.driver_id) or not public.driver_identity_recheck_online_allowed(new.driver_id))
  then raise exception 'Driver verification authorization is required before accepting a ride.' using errcode='42501'; end if;
  return new;
end; $$;
create trigger guard_driver_identity_on_passenger_assignment before update of driver_id on public.rides
for each row execute function public.guard_driver_identity_on_passenger_assignment_v1();

create or replace function public.guard_driver_identity_on_food_assignment_v1() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if old.assigned_driver_firebase_uid is null and new.assigned_driver_firebase_uid is not null
    and (not public.driver_verification_online_allowed(new.assigned_driver_firebase_uid) or not public.driver_identity_recheck_online_allowed(new.assigned_driver_firebase_uid))
  then raise exception 'Driver verification authorization is required before accepting a delivery.' using errcode='42501'; end if;
  return new;
end; $$;
create trigger guard_driver_identity_on_food_assignment before update of assigned_driver_firebase_uid on public.food_delivery_jobs
for each row execute function public.guard_driver_identity_on_food_assignment_v1();

create or replace function public.record_driver_identity_ride_activity_v1() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if new.driver_id is not null and public.driver_identity_recheck_enabled_for(new.driver_id)
    and ((old.driver_id is null and new.driver_id is not null) or
      (old.status is distinct from new.status and new.status in ('accepted','arrived_at_pickup','in_progress','completed')))
  then
    insert into public.driver_identity_recheck_state(driver_firebase_uid,last_online_authorized_at)
    values(new.driver_id,statement_timestamp()) on conflict(driver_firebase_uid) do update
      set last_online_authorized_at=excluded.last_online_authorized_at,updated_at=statement_timestamp();
  end if;
  return new;
end; $$;
create trigger record_driver_identity_ride_activity after update of driver_id,status on public.rides
for each row execute function public.record_driver_identity_ride_activity_v1();

revoke all on public.driver_identity_provider_session_secrets,public.driver_identity_provider_events from public,anon,authenticated;
revoke insert,update,delete,truncate,references,trigger on public.driver_identity_recheck_state,public.driver_identity_challenges,
  public.driver_identity_trusted_installations,public.driver_identity_online_authorizations,public.driver_identity_challenge_events,
  public.driver_identity_admin_actions from authenticated;
revoke all on function public.attach_driver_identity_provider_session_v1(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.release_driver_identity_provider_session_creation_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function public.get_driver_identity_provider_session_secret_v1(uuid) from public,anon,authenticated;
revoke all on function public.process_driver_identity_provider_event_v1(text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.attach_driver_identity_provider_session_v1(uuid,uuid,text,text,text) to service_role;
grant execute on function public.release_driver_identity_provider_session_creation_v1(uuid,uuid) to service_role;
grant execute on function public.get_driver_identity_provider_session_secret_v1(uuid) to service_role;
grant execute on function public.process_driver_identity_provider_event_v1(text,text,text,text,text,text,jsonb) to service_role;

commit;
