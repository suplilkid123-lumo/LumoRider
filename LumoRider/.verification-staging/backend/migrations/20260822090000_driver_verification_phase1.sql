begin;

create type public.driver_verification_review_status as enum (
  'under_review', 'verified', 'rejected'
);

create table public.driver_verification_requirements (
  requirement_key text primary key,
  display_name text not null,
  description text not null default '',
  icon_name text not null default 'checkmark.shield',
  is_required boolean not null default true,
  requires_document boolean not null default true,
  requires_expiration boolean not null default false,
  requires_vehicle boolean not null default false,
  document_slots text[] not null default array['document']::text[],
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint driver_verification_requirement_key_check
    check (requirement_key = btrim(requirement_key) and requirement_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  constraint driver_verification_document_slots_check
    check (not requires_document or cardinality(document_slots) > 0)
);

insert into public.driver_verification_requirements
  (requirement_key, display_name, description, icon_name, requires_document,
   requires_expiration, requires_vehicle, document_slots, sort_order)
values
  ('identity_profile', 'Identity / Profile', 'Confirm the profile information shown to Lumo riders.', 'person.text.rectangle', false, false, false, array[]::text[], 10),
  ('drivers_license', 'Driver''s License', 'Upload clear photos of the front and back of your current license.', 'idcard', true, true, false, array['front','back'], 20),
  ('vehicle_registration', 'Vehicle Registration', 'Upload the current registration for the vehicle you drive.', 'car', true, true, true, array['document'], 30),
  ('vehicle_insurance', 'Vehicle Insurance', 'Upload current proof of insurance for the vehicle you drive.', 'shield.lefthalf.filled', true, true, true, array['document'], 40),
  ('profile_selfie', 'Profile Selfie', 'Take a clear front-camera photo for manual Lumo review.', 'person.crop.circle.badge.checkmark', true, false, false, array['selfie'], 50);

create table public.driver_verification_settings (
  singleton boolean primary key default true check (singleton),
  global_enforcement_enabled boolean not null default false,
  expiring_soon_days integer not null default 30 check (expiring_soon_days between 1 and 180),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.driver_verification_settings(singleton) values (true);

create table public.driver_verification_rollout (
  driver_firebase_uid text primary key,
  enforcement_enabled boolean not null default true,
  note text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  constraint driver_verification_rollout_uid_check
    check (driver_firebase_uid = btrim(driver_firebase_uid) and length(driver_firebase_uid) between 1 and 256)
);

create table public.driver_verification_submissions (
  id uuid primary key default gen_random_uuid(),
  driver_firebase_uid text not null,
  requirement_key text not null references public.driver_verification_requirements(requirement_key),
  associated_vehicle_id text,
  status public.driver_verification_review_status not null default 'under_review',
  document_paths jsonb not null default '{}'::jsonb,
  issuing_jurisdiction text,
  expiration_date date,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  rejection_reason text,
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint driver_verification_submission_uid_check
    check (driver_firebase_uid = btrim(driver_firebase_uid) and length(driver_firebase_uid) between 1 and 256),
  constraint driver_verification_vehicle_check
    check (associated_vehicle_id is null or length(btrim(associated_vehicle_id)) between 1 and 256),
  constraint driver_verification_rejection_check
    check (status <> 'rejected' or length(btrim(coalesce(rejection_reason, ''))) between 3 and 1000),
  constraint driver_verification_documents_object_check check (jsonb_typeof(document_paths) = 'object')
);

create unique index driver_verification_one_current_idx
  on public.driver_verification_submissions
  (driver_firebase_uid, requirement_key, coalesce(associated_vehicle_id, ''));
create index driver_verification_admin_queue_idx
  on public.driver_verification_submissions(status, submitted_at desc);

create table public.driver_verification_reviews (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.driver_verification_submissions(id) on delete cascade,
  action text not null check (action in ('approve','reject','request_new_document')),
  reason text,
  reviewer_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint driver_verification_review_reason_check
    check (action = 'approve' or length(btrim(coalesce(reason, ''))) between 3 and 1000)
);

create or replace function public.is_lumo_admin() returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, auth, public
as $$
declare v_uid uuid;
begin
  begin
    v_uid := auth.uid();
  exception when invalid_text_representation then
    return false;
  end;
  return v_uid is not null and exists(select 1 from public.admins a where a.user_id=v_uid);
end;
$$;

-- The existing admin table remains the authorization source, but self-enrollment is closed.
alter table public.admins enable row level security;
drop policy if exists admins_read_self on public.admins;
create policy admins_read_self on public.admins for select to authenticated using (user_id = auth.uid());
revoke all on public.admins from anon;
revoke insert, update, delete, truncate, references, trigger on public.admins from authenticated;
grant select on public.admins to authenticated;

create or replace function public.driver_verification_enforcement_enabled(p_driver_uid text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (select r.enforcement_enabled from public.driver_verification_rollout r where r.driver_firebase_uid = p_driver_uid),
    (select s.global_enforcement_enabled from public.driver_verification_settings s where s.singleton),
    false
  );
$$;

create or replace function public.driver_verification_effective_status(
  p_status public.driver_verification_review_status,
  p_expiration_date date,
  p_expiring_days integer
) returns text language sql stable
set search_path = pg_catalog
as $$
  select case
    when p_status is null then 'not_submitted'
    when p_status = 'verified' and p_expiration_date is not null and p_expiration_date < current_date then 'expired'
    when p_status = 'verified' and p_expiration_date is not null and p_expiration_date <= current_date + greatest(p_expiring_days, 1) then 'expiring_soon'
    else p_status::text
  end;
$$;

create or replace function public.driver_verification_online_allowed(p_driver_uid text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select case
    when not public.driver_verification_enforcement_enabled(p_driver_uid) then true
    else not exists (
      select 1
      from public.driver_verification_requirements req
      left join public.driver_verification_submissions sub
        on sub.driver_firebase_uid = p_driver_uid
       and sub.requirement_key = req.requirement_key
       and (not req.requires_vehicle or sub.associated_vehicle_id is not null)
      cross join public.driver_verification_settings settings
      where req.active and req.is_required and settings.singleton
        and public.driver_verification_effective_status(sub.status, sub.expiration_date, settings.expiring_soon_days)
          not in ('verified', 'expiring_soon')
    )
  end;
$$;

create or replace function public.get_driver_verification_center_v1() returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid text := public.passenger_authenticated_user_id();
  v_days integer;
  v_enforced boolean;
  v_items jsonb;
  v_required integer;
  v_verified integer;
begin
  if not public.passenger_is_driver_jwt() then
    raise exception 'Driver authentication is required.' using errcode = '42501';
  end if;
  select expiring_soon_days into v_days from public.driver_verification_settings where singleton;
  v_enforced := public.driver_verification_enforcement_enabled(v_uid);

  select jsonb_agg(jsonb_build_object(
    'requirement_key', req.requirement_key,
    'display_name', req.display_name,
    'description', req.description,
    'icon_name', req.icon_name,
    'is_required', req.is_required,
    'requires_document', req.requires_document,
    'requires_expiration', req.requires_expiration,
    'requires_vehicle', req.requires_vehicle,
    'document_slots', to_jsonb(req.document_slots),
    'status', public.driver_verification_effective_status(sub.status, sub.expiration_date, v_days),
    'submission_id', sub.id,
    'document_paths', coalesce(sub.document_paths, '{}'::jsonb),
    'associated_vehicle_id', sub.associated_vehicle_id,
    'issuing_jurisdiction', sub.issuing_jurisdiction,
    'submitted_at', sub.submitted_at,
    'reviewed_at', sub.reviewed_at,
    'expiration_date', sub.expiration_date,
    'rejection_reason', sub.rejection_reason
  ) order by req.sort_order),
  count(*) filter (where req.is_required),
  count(*) filter (where req.is_required and public.driver_verification_effective_status(sub.status, sub.expiration_date, v_days) in ('verified','expiring_soon'))
  into v_items, v_required, v_verified
  from public.driver_verification_requirements req
  left join public.driver_verification_submissions sub
    on sub.driver_firebase_uid = v_uid and sub.requirement_key = req.requirement_key
  where req.active;

  return jsonb_build_object(
    'server_time', statement_timestamp(),
    'enforcement_enabled', v_enforced,
    'eligible_to_go_online', public.driver_verification_online_allowed(v_uid),
    'verified_required_count', v_verified,
    'required_count', v_required,
    'expiring_soon_days', v_days,
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

create or replace function public.submit_driver_verification_v1(
  p_requirement_key text,
  p_document_paths jsonb default '{}'::jsonb,
  p_expiration_date date default null,
  p_associated_vehicle_id text default null,
  p_issuing_jurisdiction text default null
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid text := public.passenger_authenticated_user_id();
  v_req public.driver_verification_requirements%rowtype;
  v_slot text;
  v_path text;
  v_id uuid;
begin
  if not public.passenger_is_driver_jwt() then raise exception 'Driver authentication is required.' using errcode='42501'; end if;
  select * into v_req from public.driver_verification_requirements where requirement_key=p_requirement_key and active;
  if not found then raise exception 'Unknown verification requirement.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_document_paths,'{}'::jsonb)) <> 'object' then raise exception 'Document paths must be an object.' using errcode='22023'; end if;
  if v_req.requires_document then
    foreach v_slot in array v_req.document_slots loop
      v_path := p_document_paths ->> v_slot;
      if v_path is null or v_path !~ ('^' || regexp_replace(v_uid, '([\\.\\+\\*\\?\\[\\^\\]\\$\\(\\)\\{\\}=!<>|:\\-])', '\\\1', 'g') || '/' || p_requirement_key || '/[A-Za-z0-9._-]+$') then
        raise exception 'A valid private upload is required for slot %.', v_slot using errcode='22023';
      end if;
    end loop;
  end if;
  if v_req.requires_expiration and p_expiration_date is null then raise exception 'Expiration date is required.' using errcode='22023'; end if;
  if v_req.requires_vehicle and length(btrim(coalesce(p_associated_vehicle_id,'')))=0 then raise exception 'Associated vehicle is required.' using errcode='22023'; end if;

  insert into public.driver_verification_submissions as sub
    (driver_firebase_uid, requirement_key, associated_vehicle_id, status, document_paths,
     issuing_jurisdiction, expiration_date, submitted_at, reviewed_at, reviewed_by, rejection_reason)
  values
    (v_uid, p_requirement_key, nullif(btrim(p_associated_vehicle_id),''), 'under_review', coalesce(p_document_paths,'{}'::jsonb),
     nullif(btrim(p_issuing_jurisdiction),''), p_expiration_date, statement_timestamp(), null, null, null)
  on conflict (driver_firebase_uid, requirement_key, (coalesce(associated_vehicle_id,''))) do update
    set status='under_review', document_paths=excluded.document_paths,
        issuing_jurisdiction=excluded.issuing_jurisdiction, expiration_date=excluded.expiration_date,
        submitted_at=excluded.submitted_at, reviewed_at=null, reviewed_by=null, rejection_reason=null,
        revision=sub.revision+1, updated_at=statement_timestamp()
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.review_driver_verification_v1(
  p_submission_id uuid, p_action text, p_reason text default null
) returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_status public.driver_verification_review_status;
begin
  if not public.is_lumo_admin() then raise exception 'Admin authorization is required.' using errcode='42501'; end if;
  if p_action not in ('approve','reject','request_new_document') then raise exception 'Unknown review action.' using errcode='22023'; end if;
  if p_action <> 'approve' and length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'A reason is required.' using errcode='22023'; end if;
  v_status := case when p_action='approve' then 'verified'::public.driver_verification_review_status else 'rejected'::public.driver_verification_review_status end;
  update public.driver_verification_submissions set
    status=v_status, reviewed_at=statement_timestamp(), reviewed_by=auth.uid(),
    rejection_reason=case when p_action='approve' then null else btrim(p_reason) end,
    updated_at=statement_timestamp()
  where id=p_submission_id;
  if not found then raise exception 'Submission not found.' using errcode='P0002'; end if;
  insert into public.driver_verification_reviews(submission_id,action,reason,reviewer_user_id)
  values(p_submission_id,p_action,nullif(btrim(p_reason),''),auth.uid());
end;
$$;

alter table public.driver_verification_requirements enable row level security;
alter table public.driver_verification_settings enable row level security;
alter table public.driver_verification_rollout enable row level security;
alter table public.driver_verification_submissions enable row level security;
alter table public.driver_verification_reviews enable row level security;

create policy driver_verification_requirements_read on public.driver_verification_requirements for select to authenticated using (active or public.is_lumo_admin());
create policy driver_verification_settings_admin on public.driver_verification_settings for all to authenticated using (public.is_lumo_admin()) with check (public.is_lumo_admin());
create policy driver_verification_rollout_admin on public.driver_verification_rollout for all to authenticated using (public.is_lumo_admin()) with check (public.is_lumo_admin());
create policy driver_verification_submissions_owner_read on public.driver_verification_submissions for select to authenticated using (public.passenger_is_driver_jwt() and driver_firebase_uid=public.passenger_authenticated_user_id());
create policy driver_verification_submissions_admin_read on public.driver_verification_submissions for select to authenticated using (public.is_lumo_admin());
create policy driver_verification_reviews_admin_read on public.driver_verification_reviews for select to authenticated using (public.is_lumo_admin());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('driver-verification','driver-verification',false,12582912,array['image/jpeg','image/png','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy driver_verification_storage_owner_select on storage.objects for select to authenticated
using (bucket_id='driver-verification' and public.passenger_is_driver_jwt() and (storage.foldername(name))[1]=public.passenger_authenticated_user_id());
create policy driver_verification_storage_owner_insert on storage.objects for insert to authenticated
with check (bucket_id='driver-verification' and public.passenger_is_driver_jwt() and (storage.foldername(name))[1]=public.passenger_authenticated_user_id());
create policy driver_verification_storage_owner_update on storage.objects for update to authenticated
using (bucket_id='driver-verification' and public.passenger_is_driver_jwt() and (storage.foldername(name))[1]=public.passenger_authenticated_user_id())
with check (bucket_id='driver-verification' and public.passenger_is_driver_jwt() and (storage.foldername(name))[1]=public.passenger_authenticated_user_id());
create policy driver_verification_storage_owner_delete on storage.objects for delete to authenticated
using (bucket_id='driver-verification' and public.passenger_is_driver_jwt() and (storage.foldername(name))[1]=public.passenger_authenticated_user_id());
create policy driver_verification_storage_admin_select on storage.objects for select to authenticated
using (bucket_id='driver-verification' and public.is_lumo_admin());

drop policy if exists passenger_rides_driver_select_available on public.rides;
create policy passenger_rides_driver_select_available on public.rides for select to authenticated
using (public.passenger_is_driver_jwt()
  and public.driver_verification_online_allowed(public.passenger_authenticated_user_id())
  and status='requested' and driver_id is null and (ride_mode <> 'SHARE' or share_position=1));

create or replace function public.set_food_delivery_online_v1(p_verified_driver_firebase_uid text,p_is_online boolean) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid text:=btrim(coalesce(p_verified_driver_firebase_uid,'')); v_now timestamptz:=statement_timestamp(); v_previous_write timestamptz;
begin
  perform public.food_delivery_assert_driver_eligible(v_uid);
  if coalesce(p_is_online,false) and not public.driver_verification_online_allowed(v_uid) then
    raise exception 'Driver verification is required before going online.' using errcode='42501';
  end if;
  select presence.last_presence_write_at into v_previous_write from public.food_delivery_driver_presence presence where presence.driver_firebase_uid=v_uid for update;
  if found and v_previous_write > v_now-interval '750 milliseconds' then raise exception 'Presence updates are too frequent.' using errcode='P0001'; end if;
  insert into public.food_delivery_driver_presence(driver_firebase_uid,is_online,online_updated_at,last_presence_write_at)
  values(v_uid,coalesce(p_is_online,false),v_now,v_now)
  on conflict(driver_firebase_uid) do update set is_online=excluded.is_online,online_updated_at=excluded.online_updated_at,last_presence_write_at=excluded.last_presence_write_at;
  return jsonb_build_object('is_online',coalesce(p_is_online,false),'server_updated_at',v_now);
end; $$;

revoke all on public.driver_verification_requirements, public.driver_verification_settings, public.driver_verification_rollout, public.driver_verification_submissions, public.driver_verification_reviews from anon;
grant select on public.driver_verification_requirements to authenticated;
grant select on public.driver_verification_submissions to authenticated;
revoke all on function public.is_lumo_admin() from public,anon;
revoke all on function public.get_driver_verification_center_v1() from public,anon;
revoke all on function public.submit_driver_verification_v1(text,jsonb,date,text,text) from public,anon;
revoke all on function public.review_driver_verification_v1(uuid,text,text) from public,anon;
grant execute on function public.is_lumo_admin() to authenticated;
grant execute on function public.get_driver_verification_center_v1() to authenticated;
grant execute on function public.submit_driver_verification_v1(text,jsonb,date,text,text) to authenticated;
grant execute on function public.review_driver_verification_v1(uuid,text,text) to authenticated;

commit;
