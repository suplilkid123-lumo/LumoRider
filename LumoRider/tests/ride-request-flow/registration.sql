begin;
set local row_security=on;
insert into auth.users(id) values('12345678-0000-4000-8000-000000000001');
insert into public.admins(user_id) values('12345678-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"registration-driver","iss":"https://securetoken.google.com/lumodriver-7fc04","aud":"lumodriver-7fc04"}',true);
do $$ declare result jsonb; begin
 result:=public.start_driver_application_v1('Registration Test');
 if result->>'status' is distinct from 'pending_approval' then raise exception 'Registration not pending'; end if;
 perform public.start_driver_application_v1('Do not overwrite existing name');
 begin perform public.set_passenger_driver_online_v1(true,41.878,-87.6298,10,0); raise exception 'Unapproved driver went online';
 exception when insufficient_privilege then null; end;
 begin perform public.admin_list_driver_applications_v1(0,200); raise exception 'Driver read admin list';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"12345678-0000-4000-8000-000000000001"}',true);
do $$ declare result jsonb; begin
 select value into result from public.admin_list_driver_applications_v1(0,200) value where value->>'driver_firebase_uid'='registration-driver';
 if result is null or result->>'display_name' is distinct from 'Registration Test' or result->>'approved' is distinct from 'false' or result->>'application_review_status' is distinct from 'pending' then raise exception 'Registration missing or changed in admin list'; end if;
 perform public.admin_review_driver_account_v1(gen_random_uuid(),'registration-driver','reject',1,'Incomplete identity documents');
end $$;
reset role;
do $$ begin
 if (select count(*) from public.food_delivery_driver_accounts where driver_firebase_uid='registration-driver') <> 1 then raise exception 'Registration retry duplicated account'; end if;
 if exists(select 1 from public.food_delivery_driver_accounts where driver_firebase_uid='registration-driver' and (approved or active)) then raise exception 'Rejected account activated'; end if;
end $$;
rollback;
