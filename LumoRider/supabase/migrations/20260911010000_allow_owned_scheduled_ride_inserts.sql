-- Allow Rider clients to create future STANDARD scheduled rides while retaining
-- every ownership, authentication, driver-state, and share-state restriction
-- from the existing immediate-request insert policy.
alter policy passenger_rides_rider_insert_request
on public.rides
with check (
    (select public.passenger_is_rider_jwt())
    and rider_id = (select public.passenger_authenticated_user_id())
    and (
        status = 'requested'
        or (
            status = 'scheduled'
            and scheduled_for > statement_timestamp()
            and ride_mode = 'STANDARD'
        )
    )
    and driver_id is null
    and driver_name is null
    and driver_photo_url is null
    and driver_snapshot is null
    and driver_lat is null
    and driver_lng is null
    and driver_heading is null
    and driver_updated_at is null
    and accepted_at is null
    and activated_at is null
    and arrived_at_pickup_at is null
    and started_at is null
    and completed_at is null
    and cancelled_at is null
    and cancelled_by is null
    and ride_mode = any (array['STANDARD'::text, 'SHARE'::text])
    and share_group_id is null
    and share_matched = false
    and share_position is null
    and share_dropoff_order is null
);
