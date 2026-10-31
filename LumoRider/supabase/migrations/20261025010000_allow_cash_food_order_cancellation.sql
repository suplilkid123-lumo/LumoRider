-- A placed cash order must be able to move its unpaid payment state to cancelled
-- when cancel_rider_food_order_v1 cancels the order. All other payment state and
-- order snapshot changes remain protected.
create or replace function public.food_protect_order_snapshots()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
    if new.client_request_id is distinct from old.client_request_id
        or new.rider_firebase_uid is distinct from old.rider_firebase_uid
        or new.market_id is distinct from old.market_id
        or new.market_country_code is distinct from old.market_country_code
        or new.market_city is distinct from old.market_city
        or new.restaurant_id is distinct from old.restaurant_id
        or new.restaurant_name is distinct from old.restaurant_name
        or new.currency is distinct from old.currency
        or new.subtotal_minor is distinct from old.subtotal_minor
        or new.delivery_fee_minor is distinct from old.delivery_fee_minor
        or new.service_fee_minor is distinct from old.service_fee_minor
        or new.applied_tax_rate is distinct from old.applied_tax_rate
        or new.tax_minor is distinct from old.tax_minor
        or new.total_minor is distinct from old.total_minor
        or new.payment_method is distinct from old.payment_method
        or (
            new.payment_status is distinct from old.payment_status
            and not (
                old.order_status = 'placed'
                and new.order_status = 'cancelled'
                and old.payment_method = 'cash'
                and new.payment_method = 'cash'
                and old.payment_status = 'pending'
                and new.payment_status = 'cancelled'
            )
        )
        or new.payment_checkout_id is distinct from old.payment_checkout_id
        or new.stripe_payment_intent_id is distinct from old.stripe_payment_intent_id
        or new.stripe_charged_amount_minor is distinct from old.stripe_charged_amount_minor
        or new.stripe_charged_currency is distinct from old.stripe_charged_currency
        or new.display_total_minor is distinct from old.display_total_minor
        or new.display_currency is distinct from old.display_currency
        or new.conversion_rate is distinct from old.conversion_rate
        or new.conversion_timestamp is distinct from old.conversion_timestamp
        or new.paid_at is distinct from old.paid_at
        or new.stripe_receipt_url is distinct from old.stripe_receipt_url
        or new.delivery_latitude is distinct from old.delivery_latitude
        or new.delivery_longitude is distinct from old.delivery_longitude
        or new.formatted_address is distinct from old.formatted_address
        or new.district is distinct from old.district
        or new.landmark is distinct from old.landmark
        or new.building is distinct from old.building
        or new.floor is distinct from old.floor
        or new.apartment is distinct from old.apartment
        or new.delivery_instructions is distinct from old.delivery_instructions
        or new.recipient_name is distinct from old.recipient_name
        or new.recipient_phone is distinct from old.recipient_phone then
        raise exception 'Food order snapshots, totals, and payment state are immutable.'
            using errcode = '55000';
    end if;
    return new;
end;
$$;

-- Only the Firebase-verifying Cloud Function may supply a rider UID to this
-- SECURITY DEFINER RPC. The existing direct grants allow callers to choose
-- another UID when invoking it through PostgREST.
revoke all on function public.cancel_rider_food_order_v1(text, uuid)
from public, anon, authenticated;
grant execute on function public.cancel_rider_food_order_v1(text, uuid)
to service_role;
