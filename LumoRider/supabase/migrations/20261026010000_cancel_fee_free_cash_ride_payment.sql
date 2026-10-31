-- A fee-free cancellation does not leave the uncollected cash fare due.
-- The original quote remains as a snapshot; no provider payment or refund is created.
alter table public.passenger_payments
  drop constraint passenger_payments_status_check;
alter table public.passenger_payments
  add constraint passenger_payments_status_check check (status in (
    'payment_method_required', 'intent_created', 'authorization_pending',
    'authorized', 'capture_pending', 'paid', 'payment_failed',
    'refund_pending', 'partially_refunded', 'refunded', 'cash_due',
    'cash_collected', 'cancelled'
  ));

create or replace function public.queue_passenger_payment_cancel_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_payment public.passenger_payments%rowtype;
begin
  if not public.passenger_ride_cancellation_terminal_v1(new.status) then
    return new;
  end if;

  select * into v_payment
  from public.passenger_payments
  where ride_id = new.id
  for update;

  if found and v_payment.payment_method = 'cash'
      and v_payment.status = 'cash_due'
      and new.payment_status = 'cash_due'
      and coalesce(new.cancellation_fee_eligible, false) = false
      and coalesce(new.cancellation_fee_amount, 0) = 0
      and new.cancellation_fee_status = 'not_applicable'
      and v_payment.captured_amount = 0 then
    update public.passenger_payments
    set status = 'cancelled', revision = revision + 1,
        updated_at = statement_timestamp()
    where id = v_payment.id;
    update public.rides
    set payment_status = 'cancelled', updated_at = statement_timestamp()
    where id = new.id and payment_status = 'cash_due';
  elsif found and v_payment.payment_method <> 'cash'
      and v_payment.captured_amount = 0
      and v_payment.stripe_payment_intent_id is not null then
    insert into public.passenger_payment_actions(payment_id, request_id, action_type)
    values (v_payment.id, v_payment.id, 'cancel') on conflict do nothing;
  end if;
  return new;
end;
$$;
