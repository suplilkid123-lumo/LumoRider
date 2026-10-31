-- Additional local-only acceptance checks; the original flow suite is not rerun.
begin;
set local row_security=on;
insert into public.driver_verification_settings(singleton,global_enforcement_enabled,identity_recheck_enabled) values(true,false,false);
insert into public.passenger_dispatch_config(singleton,offer_duration_seconds) values(true,60);
insert into public.food_delivery_driver_accounts(driver_firebase_uid,display_name,approved,active,food_delivery_enabled,application_review_status) values('audit-driver','Audit Driver',true,true,true,'approved');
insert into public.driver_vehicles(driver_firebase_uid,client_request_id,make,model,model_year,color,license_plate,passenger_capacity,approval_status,is_active) values('audit-driver',gen_random_uuid(),'Test','Test',2024,'Blue','AUDIT',4,'approved',true);
insert into public.driver_vehicle_ride_type_eligibility(vehicle_id,ride_type) select id,'STANDARD' from public.driver_vehicles where driver_firebase_uid='audit-driver';
insert into public.passenger_payment_currency_configs(currency,minor_unit_exponent,is_enabled) values('USD',2,true) on conflict(currency) do nothing;
insert into public.passenger_pricing_configs(market_code,ride_type,currency,revision,base_fare,per_kilometer_rate,per_minute_rate,minimum_fare,rounding_increment,effective_at,is_enabled,minimum_latitude,maximum_latitude,minimum_longitude,maximum_longitude,estimated_speed_kph) values('AUDIT','STANDARD','USD',1,10,1,0.25,10,0.01,statement_timestamp()-interval '1 minute',true,41.5,42.2,-88.5,-87.4,30);
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
select public.set_passenger_driver_online_v1(true,41.8781,-87.6298,10,0);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-rider","iss":"https://securetoken.google.com/lumorider-18350","aud":"lumorider-18350"}',true);
do $$ declare q jsonb; r jsonb; begin
q:=public.create_passenger_fare_quote_v1(gen_random_uuid(),41.878,-87.6298,41.885,-87.62,'STANDARD',1);
r:=public.create_passenger_ride_for_payment_v1(gen_random_uuid(),(q->>'quote_id')::uuid,41.878,-87.6298,41.885,-87.62,'Audit pickup','Audit destination','STANDARD',1,'cash',null);
perform set_config('test.ride',r->>'id',true);
end $$;

reset role;
select set_config('test.offer',(select id::text from public.passenger_ride_offers where ride_id=current_setting('test.ride')::uuid and state='offered'),true);
savepoint offered_fixture;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-other-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
-- Check an actually live, known offer ID, rather than querying after acceptance.
do $$ begin
if public.get_passenger_ride_offer_v1(current_setting('test.offer')::uuid) is not null then
  raise exception 'Another Driver could read the live offer';
end if;
begin
  perform public.accept_passenger_offer_v1(current_setting('test.offer')::uuid);
  raise exception 'Another Driver accepted the live offer';
exception when sqlstate 'P0002' then null;
end;
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
do $$ declare first_result jsonb; retry_result jsonb; begin
first_result:=public.accept_passenger_offer_v1(current_setting('test.offer')::uuid);
retry_result:=public.accept_passenger_offer_v1(current_setting('test.offer')::uuid);
if first_result->>'idempotent' is distinct from 'false'
   or retry_result->>'idempotent' is distinct from 'true'
   or retry_result->>'driver_id' is distinct from 'audit-driver'
   or retry_result->>'ride_id' is distinct from current_setting('test.ride')
   or retry_result->>'status' is distinct from 'accepted' then
  raise exception 'Acceptance retry did not preserve the original assignment';
end if;
end $$;
-- Rewind only this synthetic in-memory fixture, then test a genuinely expired offer.
rollback to savepoint offered_fixture;
reset role;
update public.passenger_ride_offers set created_at=statement_timestamp()-interval '2 minutes',expires_at=statement_timestamp()-interval '1 minute'
where id=current_setting('test.offer')::uuid;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
do $$ begin
begin
  perform public.accept_passenger_offer_v1(current_setting('test.offer')::uuid);
  raise exception 'Expired offer was accepted';
exception when sqlstate '55000' then null;
end;
end $$;
reset role;
do $$ begin
if not exists(select 1 from public.rides where id=current_setting('test.ride')::uuid and status='requested' and driver_id is null) then
  raise exception 'Rejected expired acceptance changed the fixture ride';
end if;
end $$;
rollback;
