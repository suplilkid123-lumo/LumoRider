# Ride request failure investigation — October 28, 2026

**Live end-to-end operation is not verified or fixed. No production data was changed, no rides were cancelled, and nothing was deployed.**

## Confirmed findings

The current iOS Rider cash checkout in `AddPaymentView.swift` calls
`create_passenger_fare_quote_v1`, then `create_passenger_ride_for_payment_v1`.
The production schema snapshot captured October 26 at
`LumoBackend/deployment-backups/20261026-food-cancel-predeploy-schema.sql`
contains neither function. Restoring that snapshot without errors and executing
the quote call reproduces PostgreSQL `42883` (undefined function). The failure
occurs **before ride insertion and dispatch** for that client/schema combination.
This proves a release-contract mismatch against the snapshot, not that today's
live database is unchanged or that this explains a particular existing ride.

The matching pricing/payment migrations are under the backend's
`supabase/deferred_migrations/20260823-20260824`, outside its active migration
sequence. Pricing also requires party-size support, an idempotency column/index,
and explicitly configured markets; payment triggers require a cancellation
terminal helper. Simply copying the two migrations into a live release is not a
validated deployment plan.

The snapshot also lacks `passenger_ride_offer_notification_events` and
`claim_passenger_ride_offer_notification_v1`, which the local
`passenger-ride-offer-push` Edge Function needs. Therefore that snapshot cannot
support that push worker. FCM/APNs credentials and actual device delivery were
not verified.

## Flow traced

| Stage | Observed implementation and verification |
|---|---|
| Rider creation | Cash checkout uses the two authoritative RPCs above. Card/Apple Pay paths explicitly fail closed as unconfigured. Older direct INSERT helpers are not this checkout path. |
| Database | Immediate cash creation returns `requested`; scheduled rides return `scheduled`. New STANDARD requested rides trigger `enqueue_standard_passenger_dispatch_after_insert_v1`. |
| Availability/location | Driver uses `set_passenger_driver_online_v1` and `update_passenger_driver_location_v1`. Eligibility checks online state, fresh coordinates, vehicle approval/capacity, verification, outstanding offers, and conflicting rides/deliveries. No live Driver presence was accessible. |
| Dispatch | `passenger_dispatch_run_ride_v1` creates bounded per-Driver offers. Isolated test confirms automatic insertion-trigger dispatch, without manually invoking dispatch. Live cron/wave processing was not inspected. |
| Driver display | Foreground Driver polls `get_passenger_ride_offer_v1` every 1.5 seconds after availability confirmation. This path does not depend on Realtime or push. UI display itself was not run. |
| Acceptance | `accept_passenger_offer_v1` assigns the Driver; isolated test confirms `accepted`. |
| Rider confirmation | Rider status observer polls every 2 seconds. Test verifies the authenticated Rider can read the accepted row through actual snapshot RLS policies. Device navigation was not tested. |
| Authentication | Local app Firebase project IDs match the snapshot issuer/audience checks (`lumorider-18350`, `lumodriver-7fc04`). SQL tests inject claims; they do not verify Firebase token signatures or Supabase gateway configuration. |
| Realtime/push/logs | No current subscriptions, backend logs, device tokens, push receipt, or hosted records were accessible. A single read-only API probe returned HTTP 401 `Invalid API key`; repeated probes could not complete. Treat key rejection as unconfirmed until repeated with an authenticated project session. |

## Local change

`AddPaymentView.swift` now explains missing booking RPCs and API-key rejection,
retains the failing operation/error code, and validates the returned ride UUID
and expected state before showing a new-request confirmation. An idempotent
response for an accepted/terminal ride directs the user to Home to recover the
current trip. There is no insecure direct-insert fallback and no payment/RLS
bypass. This fixes misleading confirmation/error handling; it does **not**
install the missing backend services.

Existing changes in `LumoApp.swift` and the dependency tree were preserved.
Driver/backend source directories were inspected but not modified.

## Tests and results

- Snapshot restore: PASS, zero SQL restoration errors.
- Current checkout against snapshot: reproduced failure before INSERT (`42883`).
- With real deferred pricing/payment SQL and the documented prerequisite subset
  installed in the in-memory test database: PASS for Rider creation, automatic
  Driver offer delivery, Driver acceptance, and Rider acceptance visibility.
- Fresh Driver eligibility: PASS; offline and stale location exclusion: PASS.
  These assertions run before assignment, avoiding a busy-Driver false positive.
- Cross-Rider reads and cross-Driver offer access: PASS (denied/empty).
- Swift checkout contract: 15 PASS, including malformed responses, wrong states,
  missing RPCs, gateway rejection, and preservation of server business errors.
- `swiftc -frontend -parse AddPaymentView.swift`: PASS.
- `git diff --check`: PASS.
- Full iOS build: attempted during resume; BLOCKED before compilation by unavailable
  dependencies and GitHub DNS resolution failure (xcodebuild exit 74).
- HTTP integration, real JWT validation, push, Realtime, scheduler execution,
  concurrent acceptance races, SHARE trips, and physical device end-to-end
  tests: NOT RUN. Existing Pods deletions were not repaired.

PGlite runs actual PostgreSQL 18 SQL in memory. The harness supplies minimal
Supabase auth/schema scaffolding; it never accepts a database connection URL,
connects to production, sends pushes, or charges money. Fixture data is synthetic
and rolled back. The compatibility SQL is a test setup, not a reviewed release.

## Reproduce

From this directory, install the pinned test dependency with `npm install`, then:

```sh
node run.mjs /path/to/20261026-food-cancel-predeploy-schema.sql /path/to/LumoBackend
python3 test_checkout_contract.py
```

Alternatively set `PGLITE_MODULE` to the absolute path of an already installed
PGlite `dist/index.js`. Backend SQL remains in its existing project; no source
files or real data are copied into the fixture.

## Remaining blockers

1. Read-only access to the current hosted schema, failing request/ride ID, Driver
   presence/eligibility, dispatch state/offers, cron state, and backend logs is
   needed to establish the exact live incident cause.
2. Reconcile the app release with the backend contract. Missing migrations,
   approved market pricing, and push prerequisites need a separately reviewed
   release; deployment was explicitly prohibited for this task.
3. Re-run a two-device test against an authorized non-production environment,
   including receipt and acceptance with the app foregrounded and backgrounded.

## Resume checkpoint — completed

The previous tool calls had completed or returned explicit failures; none left a
pending execution session. OS-wide process inspection was denied (`ps: operation
not permitted`), and the app terminal reader was unavailable. Therefore no claim
is made about all unrelated system processes. No process was terminated: there
was no identified stuck diagnostic command. The previous native PostgreSQL
initialization had failed; no diagnostic PostgreSQL pid file exists.

The original flow suite and 15 Swift contract tests were **not rerun**. Their
recorded results and application fix were preserved. The runner now accepts
`--remaining-only`, which loads the same local test prerequisites and runs only
`acceptance_edges.sql`:

1. Another Driver cannot retrieve a known, still-live offer.
2. Another Driver cannot accept that live offer.
3. A retry by the accepting Driver returns the same assignment as idempotent.
4. An expired offer cannot be accepted, and the synthetic ride remains unassigned.

All four passed. These are sequential SQL checks, not a concurrent transaction
race test. Test identities, offers, and rides exist only in the in-memory engine.

The iOS Simulator build was attempted with signing disabled and a scratch derived
data directory. It exited with code 74 before compilation because package clones
failed with `Could not resolve host: github.com` (including Firebase dependencies
and Stripe). It was not stuck and required no termination. This does not establish
whether the app compiles once dependencies are available.

Resume changed only this report, `run.mjs`, the new `acceptance_edges.sql`, and the
new `resume-results.txt`. No further application or backend changes were made.

**Final status:** local diagnostic tests completed to the available environment's
limits. The snapshot contract mismatch is reproduced; a live incident root cause,
complete mobile flow, push delivery, and full app build remain unverified. Further
work requires the dependencies/build environment and an authorized non-production
integration environment; production changes and deployment remain prohibited.
