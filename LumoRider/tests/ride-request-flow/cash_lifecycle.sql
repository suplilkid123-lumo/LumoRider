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
if r->>'status' is distinct from 'requested' then raise exception 'Rider creation failed'; end if;
perform set_config('test.ride',r->>'id',true);
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
do $$ declare o jsonb; a jsonb; begin
 o:=public.get_passenger_ride_offer_v1();
 if o->>'ride_id' is distinct from current_setting('test.ride') then raise exception 'Driver did not receive created ride'; end if;
 a:=public.accept_passenger_offer_v1((o->>'offer_id')::uuid);
 if a->>'status' is distinct from 'accepted' then raise exception 'Driver acceptance failed'; end if;
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-rider","iss":"https://securetoken.google.com/lumorider-18350","aud":"lumorider-18350"}',true);
do $$ begin
if not exists(select 1 from public.rides where id=current_setting('test.ride')::uuid and status='accepted' and driver_id='audit-driver') then raise exception 'Rider cannot see acceptance through RLS'; end if;
end $$;

select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
do $$ declare r uuid:=current_setting('test.ride')::uuid; result jsonb; begin
 perform public.publish_passenger_trip_telemetry_v1(r,gen_random_uuid(),0,41.878,-87.6298,10,0,0);
 result:=public.mark_passenger_ride_arrived_v1(r);
 if result->>'status' is distinct from 'arrived_at_pickup' then raise exception 'Arrival failed'; end if;
 result:=public.start_passenger_ride_v1(r);
 if result->>'status' is distinct from 'in_progress' then raise exception 'Start failed'; end if;
 perform public.publish_passenger_trip_telemetry_v1(r,gen_random_uuid(),1,41.885,-87.62,10,0,0);
 result:=public.complete_passenger_ride_v1(r);
 if result->>'status' is distinct from 'completed' then raise exception 'Completion failed'; end if;
 result:=public.complete_passenger_ride_v1(r);
 if result->>'idempotent' is distinct from 'true' then raise exception 'Completion retry failed'; end if;
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-rider","iss":"https://securetoken.google.com/lumorider-18350","aud":"lumorider-18350"}',true);
do $$ begin
 if not exists(select 1 from public.rides where id=current_setting('test.ride')::uuid and status='completed' and payment_method='cash' and payment_status='cash_due') then raise exception 'Cash completion not visible to rider'; end if;
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.passenger_payment_actions) then raise exception 'Cash ride created provider action'; end if;
 if exists(select 1 from public.rides where stripe_payment_intent_id is not null) then raise exception 'Cash ride has Stripe intent'; end if;
end $$;
rollback;
