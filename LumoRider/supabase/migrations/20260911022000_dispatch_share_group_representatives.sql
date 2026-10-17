-- Share matching designates one position-1 ride as the dispatchable group
-- representative. Enqueue that representative after the matching trigger has
-- populated the share fields, while keeping position 2 group-assigned only.

create or replace function public.passenger_dispatch_run_ride_v1(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare v_ride public.rides%rowtype; v_state public.passenger_dispatch_state%rowtype; c public.passenger_dispatch_config%rowtype; n integer:=0; wave integer; radius integer; nowv timestamptz:=statement_timestamp();
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('passenger-dispatch:'||p_ride_id::text,0));
 select * into v_ride from public.rides where id=p_ride_id for update; if not found then return jsonb_build_object('ride_id',p_ride_id,'state','missing'); end if;
 insert into public.passenger_dispatch_state(ride_id,next_dispatch_at) values(p_ride_id,nowv) on conflict do nothing;
 select * into v_state from public.passenger_dispatch_state where ride_id=p_ride_id for update; select * into c from public.passenger_dispatch_config where singleton;
if v_ride.status<>'requested' or v_ride.driver_id is not null
   or v_ride.ride_mode not in ('STANDARD','SHARE')
   or (v_ride.ride_mode='SHARE' and v_ride.share_position is distinct from 1) then
 update public.passenger_ride_offers set state='cancelled',responded_at=coalesce(responded_at,nowv) where ride_id=p_ride_id and state='offered';
 update public.passenger_dispatch_state set state=case when v_ride.driver_id is null then 'cancelled' else 'assigned' end,next_dispatch_at=null,finished_at=coalesce(finished_at,nowv),updated_at=nowv where ride_id=p_ride_id;
 return jsonb_build_object('ride_id',p_ride_id,'state','cancelled');
end if;
 update public.passenger_ride_offers set state='expired',responded_at=coalesce(responded_at,nowv) where ride_id=p_ride_id and state='offered' and expires_at<=nowv;
 if exists(select 1 from public.passenger_ride_offers where ride_id=p_ride_id and state='offered') then return jsonb_build_object('ride_id',p_ride_id,'state','offering','created',0); end if;
 if v_state.current_wave>=c.maximum_waves then update public.passenger_dispatch_state set state='exhausted',next_dispatch_at=null,finished_at=coalesce(finished_at,nowv),updated_at=nowv where ride_id=p_ride_id; return jsonb_build_object('ride_id',p_ride_id,'state','exhausted','created',0); end if;
 wave:=v_state.current_wave+1; radius:=least(c.maximum_radius_meters,c.initial_radius_meters+((wave-1)*c.radius_step_meters));
with candidates as (select p.driver_firebase_uid,public.passenger_dispatch_distance_meters_v1(p.latitude::double precision,p.longitude::double precision,v_ride.pickup_lat,v_ride.pickup_lng) d from public.passenger_driver_presence p where p.is_online and p.latitude between -90 and 90 and p.longitude between -180 and 180 and p.location_received_at>=nowv-make_interval(secs=>c.location_freshness_seconds) and p.location_received_at<=nowv and exists (
      -- lifecycle_capacity_guard: selected vehicle must fit the whole party.
      select 1 from public.driver_vehicles capacity_vehicle
      where capacity_vehicle.driver_firebase_uid=p.driver_firebase_uid
        and capacity_vehicle.is_active and capacity_vehicle.removed_at is null
        and capacity_vehicle.passenger_capacity >= public.passenger_ride_required_seats_v1(p_ride_id)
    ) and public.passenger_dispatch_driver_eligible_v1(p.driver_firebase_uid,nowv-make_interval(secs=>c.location_freshness_seconds)) and not exists(select 1 from public.passenger_ride_offers x where x.ride_id=p_ride_id and x.driver_firebase_uid=p.driver_firebase_uid) and public.passenger_dispatch_distance_meters_v1(p.latitude::double precision,p.longitude::double precision,v_ride.pickup_lat,v_ride.pickup_lng)<=radius order by d,p.driver_firebase_uid limit c.drivers_per_wave) insert into public.passenger_ride_offers(ride_id,driver_firebase_uid,wave,distance_to_pickup_meters,created_at,expires_at) select p_ride_id,driver_firebase_uid,wave,d,nowv,nowv+make_interval(secs=>c.offer_duration_seconds) from candidates on conflict do nothing;
get diagnostics n=row_count; update public.passenger_dispatch_state set current_wave=wave,state=case when n>0 then 'offering' when wave>=c.maximum_waves then 'exhausted' else 'searching' end,next_dispatch_at=case when n>0 then nowv+make_interval(secs=>c.offer_duration_seconds) when wave<c.maximum_waves then nowv+make_interval(secs=>c.offer_duration_seconds) else null end,updated_at=nowv where ride_id=p_ride_id;
 return jsonb_build_object('ride_id',p_ride_id,'state',case when n>0 then 'offering' else 'searching' end,'wave',wave,'radius_meters',radius,'created',n);
end;
$function$;

revoke all on function public.passenger_dispatch_run_ride_v1(uuid) from public, anon, authenticated;
grant execute on function public.passenger_dispatch_run_ride_v1(uuid) to service_role;

create or replace function public.enqueue_share_passenger_dispatch_after_insert_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if exists (
    select 1
    from public.rides ride
    where ride.id = new.id
      and ride.status = 'requested'
      and ride.driver_id is null
      and ride.ride_mode = 'SHARE'
      and ride.share_position = 1
  ) then
    perform public.passenger_dispatch_run_ride_v1(new.id);
  end if;
  return new;
end;
$function$;

revoke all on function public.enqueue_share_passenger_dispatch_after_insert_v1() from public, anon, authenticated;

drop trigger if exists zz_enqueue_share_passenger_dispatch_after_insert on public.rides;
create trigger zz_enqueue_share_passenger_dispatch_after_insert
after insert on public.rides
for each row
when (new.ride_mode = 'SHARE' and new.status = 'requested')
execute function public.enqueue_share_passenger_dispatch_after_insert_v1();
