# Jiylo coordinated investigation — October 29, 2026

The complete mobile incident is not resolved or verified. No production records
were modified, no payment provider was contacted, and nothing was deployed.

1. **Problems identified.** The saved October 26 schema lacks the fare-quote and
   ride-payment creation RPCs used by current Cash checkout. The Admin Drivers
   tab was a placeholder. Apple Pay used a legacy endpoint before a ride creation
   path that explicitly rejects electronic payments. The prior Test Payment test
   stopped at acceptance while printing a full-lifecycle success message.
2. **Root causes.** The pricing/payment migrations remain deferred. There was no
   admin listing path for protected account/vehicle tables. Apple Pay's callback
   contract (`paymentMethodId`, client amount, `clientSecret`, no auth header)
   differs from the available authenticated `passenger-payment-intent` function
   (`ride_id`, request ID, `payment_method_id`, server quote, `client_secret`).
   This is evidence from local source and a saved schema, not today's live service.
3. **Fixes completed.** Retained the prior admin listing/review fix. Prevented the
   legacy Apple Pay authorization from running before the known ride-creation
   rejection. Corrected isolated Test Payment auth to match the explicit
   `demo-jiylo-test` emulator project and require server-side role allowlisting.
   Expanded executable tests through completion and receipt; added registration,
   Cash lifecycle and synthetic electronic authorization/dispatch tests. Added
   reproducible checks without changing the active Xcode project.
4. **Rider results.** The Rider workspace simulator build succeeded (signing disabled); its active
   project is REALCOPY.xcodeproj. Fifteen compiled checkout-contract tests passed. Isolated
   SQL verifies creation and Rider visibility of acceptance/completion through
   RLS. Login, map selection, navigation, and real-device updates were not tested.
5. **Driver results.** SQL verifies automatic offers, acceptance, arrival, start,
   telemetry, completion and completion retry. Offline/stale-location exclusion,
   another Driver's offer denial and expired acceptance denial pass. Foreground
   polling already starts immediately and repeats at 1.5 seconds; there was no
   reproduced polling defect to justify rewriting it. Push and APNs/FCM untested.
6. **Admin results.** Build and lint pass. The existing complete account/vehicle
   approval SQL regression passes against the restored schema. Registration retry
   preserves the original account; the pending account appears through the new
   admin RPC; rejection does not activate it. Self-approval, nonadmin listing and
   unapproved online access are denied. No real driver was approved.
7. **Test Payment results.** Actual PostgreSQL SQL passes creation → dispatch →
   acceptance → arrival → start → GPS telemetry → completion → zero-dollar receipt.
   Unlisted account creation/receipt access is denied; no Stripe intent or provider
   action exists. All simulated financial records remain in an empty, isolated
   in-memory database, separate from production revenue. The native Driver and
   gateway/emulator integration are not verified; this is not a public feature.
8. **Apple Pay / Face ID results.** Merchant ID in source matches the entitlement.
   Signing entitlement, merchant certificate, Stripe account registration, Wallet
   sandbox cards and Face ID are unverified. Native Apple Pay is currently blocked
   before payment authorization; this is a safety correction, not working checkout.
   Synthetic normalized provider events verify backend authorization-to-dispatch
   and duplicate event idempotency. They do not validate Stripe webhooks or charges.
9. **Cash results.** The saved schema reproduces undefined-function error 42883
   before ride insertion. Loading the real deferred SQL plus documented prerequisite
   subset into the isolated engine passes the Cash lifecycle through completion,
   cash_due visibility and no provider actions. This test setup is not a validated
   deployment migration bundle and does not repair the hosted release.
10. **Remaining blockers.** Current hosted schema/incident records and an authorized
    nonproduction mobile environment are unavailable. Release reconciliation still
    needs approved pricing configuration and complete migration prerequisites.
    Apple Pay needs the ride-linked client integration and sandbox credentials.
    Physical devices are required to verify Wallet/Face ID, push and two-app GPS
    behavior. The Rider workspace build passed; no native Driver build or two-device
    end-to-end test was performed. The initial obsolete standalone Rider project
    failed; temporary edits to it were removed.

## Reproduction

From `tests/ride-request-flow`, install the pinned dependency with `npm install`,
then run `node run.mjs <schema-snapshot.sql> <backend-root>` with each mode:
`--remaining-only`, `--approval`, `--cash-lifecycle`, `--test-payment`,
`--payment-dispatch`. Also run `python3 test_checkout_contract.py`.
The fixtures use synthetic claims and records and roll back. They do not validate
JWT signatures, access an HTTP Supabase gateway, call Stripe, or send notifications.

Admin source: `/Users/alyaaalzarkani/lumo-admin`.
Admin migration: `/Users/alyaaalzarkani/LumoBackend/supabase/migrations/20261029010000_admin_list_driver_applications.sql`.
Native build log: `/tmp/jiylo-coordinated-build.log`.
