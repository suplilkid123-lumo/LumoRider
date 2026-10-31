-- Run against an isolated local database with psql -v ON_ERROR_STOP=1.
-- The transaction rolls back all fixture data.
begin;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"jiylo-cash-cancel-regression","iss":"https://securetoken.google.com/riderlumo","aud":"riderlumo"}', true);

do $$
declare
  v_quote jsonb;
  v_ride jsonb;
  v_result jsonb;
begin
  v_quote := public.create_passenger_fare_quote_v1(
    gen_random_uuid(), 41.8780, -87.6298, 41.8850, -87.6200, 'STANDARD', 1);
  v_ride := public.create_passenger_ride_for_payment_v1(
    gen_random_uuid(), (v_quote->>'quote_id')::uuid,
    41.8780, -87.6298, 41.8850, -87.6200,
    'TEST cash cancellation pickup', 'TEST cash cancellation destination',
    'STANDARD', 1, 'cash', null);
  if v_ride->>'payment_status' <> 'cash_due' then
    raise exception 'Cash ride did not begin with cash_due.';
  end if;

  v_result := public.cancel_passenger_ride_v1((v_ride->>'id')::uuid, 'changed_plans');
  if v_result->>'status' <> 'cancelled_by_rider'
      or (v_result->>'fee_amount')::numeric <> 0
      or v_result->>'fee_status' <> 'not_applicable' then
    raise exception 'Fee-free cancellation contract changed.';
  end if;
  perform set_config('test.jiylo_cash_cancel_ride', v_ride->>'id', true);
end;
$$;

reset role;

do $$
declare
  v_payment public.passenger_payments%rowtype;
  v_ride_row public.rides%rowtype;
begin
  select * into strict v_payment from public.passenger_payments
    where ride_id = current_setting('test.jiylo_cash_cancel_ride')::uuid;
  select * into strict v_ride_row from public.rides
    where id = current_setting('test.jiylo_cash_cancel_ride')::uuid;
  if v_payment.status <> 'cancelled' or v_ride_row.payment_status <> 'cancelled'
      or coalesce(v_payment.final_amount, 0) <> 0
      or v_payment.captured_amount <> 0
      or v_payment.stripe_payment_intent_id is not null
      or exists(select 1 from public.passenger_payment_actions
                where payment_id = v_payment.id)
      or exists(select 1 from public.driver_earnings
                where ride_id = v_ride_row.id) then
    raise exception 'Cancelled cash ride retained a payable fare or provider action.';
  end if;

  perform set_config('test.jiylo_cash_cancel_revision', v_payment.revision::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"jiylo-cash-cancel-regression","iss":"https://securetoken.google.com/riderlumo","aud":"riderlumo"}', true);
do $$
declare v_retry jsonb;
begin
  v_retry := public.cancel_passenger_ride_v1(
    current_setting('test.jiylo_cash_cancel_ride')::uuid, 'changed_plans');
  if not (v_retry->>'idempotent')::boolean then
    raise exception 'Cancellation replay was not idempotent.';
  end if;
end;
$$;
reset role;

do $$
begin
  if (select revision from public.passenger_payments
      where ride_id = current_setting('test.jiylo_cash_cancel_ride')::uuid)
      <> current_setting('test.jiylo_cash_cancel_revision')::integer then
    raise exception 'Cancellation replay changed payment state.';
  end if;
end;
$$;

rollback;
