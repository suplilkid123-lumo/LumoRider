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
 r:=public.create_passenger_ride_for_payment_v1(gen_random_uuid(),(q->>'quote_id')::uuid,41.878,-87.6298,41.885,-87.62,'Pickup','Destination','STANDARD',1,'apple_pay',null);
 if r->>'status' is distinct from 'payment_pending' then raise exception 'Electronic ride dispatched before authorization'; end if;
 perform set_config('test.ride',r->>'id',true);
 perform set_config('test.payment',r->>'payment_id',true);
 perform public.prepare_passenger_payment_intent_v1((r->>'id')::uuid,gen_random_uuid(),'apple_pay');
end $$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare c jsonb; e jsonb; begin
 c:=public.get_passenger_payment_provider_command_v1(current_setting('test.payment')::uuid);
 perform public.attach_passenger_payment_intent_v1(current_setting('test.payment')::uuid,'pi_local_fixture','requires_capture');
 perform public.record_passenger_payment_provider_event_v1('evt_local_fixture','payment_intent.amount_capturable_updated','pi_local_fixture',(c->>'amount_minor')::bigint,'USD','requires_capture',current_setting('test.payment')::uuid,current_setting('test.ride')::uuid);
 e:=public.record_passenger_payment_provider_event_v1('evt_local_fixture','payment_intent.amount_capturable_updated','pi_local_fixture',(c->>'amount_minor')::bigint,'USD','requires_capture',current_setting('test.payment')::uuid,current_setting('test.ride')::uuid);
 if e->>'duplicate' is distinct from 'true' then raise exception 'Provider event retry not idempotent'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"audit-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
do $$ declare offer jsonb; begin
 offer:=public.get_passenger_ride_offer_v1();
 if offer->>'ride_id' is distinct from current_setting('test.ride') then raise exception 'Authorized electronic ride was not dispatched'; end if;
end $$;
rollback;
