# Driver Identity Recheck Phase 2 — Didit deployment runbook

This runbook deploys Lumo Driver Phase 2 with selected-driver rollout only. Deployment must not enable global Phase 2. Didit Biometric Authentication supplies hosted liveness and face matching against the approved Phase 1 Profile Selfie; only an authenticated backend result can create online authorization.

## Operator-provided values

Do not invent or commit these values:

- `STAGING_PROJECT_REF`: confirmed Supabase staging project reference.
- `STAGING_DATABASE_URL`: staging database connection string, if remote regression tests are authorized.
- `TEST_DRIVER_UID`: selected staging driver's Firebase UID.
- `DIDIT_API_KEY_VALUE`: sandbox application API key.
- `DIDIT_WORKFLOW_ID_VALUE`: published sandbox workflow UUID.
- `DIDIT_WEBHOOK_SECRET_VALUE`: staging webhook shared secret.
- `DIDIT_ALLOWED_HOSTS_VALUE`: reviewed comma-separated hosted verification hosts; normally `verify.didit.me`.

Production needs a separately confirmed project ref and separate live Didit key, workflow, webhook secret, and host list. Never reuse sandbox credentials.

## 1. Preflight and migration order

From `/Users/alyaaalzarkani/LumoBackend`, confirm the target before any remote command:

```sh
supabase projects list
supabase link --project-ref STAGING_PROJECT_REF
supabase migration list --linked
supabase db push --dry-run
```

Expected order:

1. existing production schema;
2. `20260822090000_driver_verification_phase1.sql`;
3. `20260822110000_driver_identity_recheck_phase2.sql`;
4. `20260822123000_driver_identity_didit_staging.sql`;
5. `20260822130000_driver_identity_phase2_hardening.sql`.

After the dry run names the intended staging target:

```sh
supabase db push
supabase migration list --linked
```

All rollout defaults remain false. No migration enrolls existing drivers.

## 2. Didit sandbox workflow and webhook

1. Create a separate sandbox application in Didit Business Console.
2. Publish a **Biometric Authentication** workflow containing Liveness Detection and Face Match.
3. Configure Face Match to use the `portrait_image` supplied by Lumo.
4. Keep its timeout no longer than Lumo's `challenge_expiration_minutes` (15 minutes by default).
5. Keep sandbox keys/workflows separate from live.
6. Select the shortest available provider retention, expected to be one month. Lumo also requests final-session and challenge-scoped user deletion.

Subscribe the webhook destination to the required event `status.updated`:

```text
https://STAGING_PROJECT_REF.supabase.co/functions/v1/driver-identity-webhook
```

The webhook intentionally does not use Supabase user JWT authentication. It authenticates Didit using HMAC-SHA256 over the raw body, timestamp freshness, replay-resistant event IDs, and provider/session/challenge/workflow/environment binding.

## 3. Staging secrets

Each `_VALUE` must be supplied by the operator:

```sh
supabase secrets set --project-ref STAGING_PROJECT_REF \
  IDENTITY_PROVIDER=didit \
  DIDIT_API_KEY='DIDIT_API_KEY_VALUE' \
  DIDIT_WORKFLOW_ID='DIDIT_WORKFLOW_ID_VALUE' \
  DIDIT_WEBHOOK_SECRET='DIDIT_WEBHOOK_SECRET_VALUE' \
  DIDIT_ENVIRONMENT=sandbox \
  DIDIT_ALLOWED_HOSTS='DIDIT_ALLOWED_HOSTS_VALUE'

supabase secrets list --project-ref STAGING_PROJECT_REF
```

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to deployed functions. Provider keys, webhook secrets, and service-role keys must never enter Swift, Info.plist, React/admin code, SQL migrations, logs, or committed environment files.

`DIDIT_CALLBACK_URL` is optional because iOS polls backend state. If enabled later, supply and allowlist one exact HTTPS host:

```sh
supabase secrets set --project-ref STAGING_PROJECT_REF \
  DIDIT_CALLBACK_URL='OPERATOR_PROVIDED_HTTPS_CALLBACK_URL' \
  IDENTITY_CALLBACK_ALLOWED_HOSTS='OPERATOR_PROVIDED_CALLBACK_HOST'
```

## 4. Deploy Edge Functions

```sh
supabase functions deploy driver-identity-session --project-ref STAGING_PROJECT_REF --no-verify-jwt
supabase functions deploy driver-identity-webhook --project-ref STAGING_PROJECT_REF --no-verify-jwt
```

The session function performs its own driver authorization through authenticated RPCs. The webhook stays `--no-verify-jwt` so Didit can call it; provider signature validation remains mandatory and occurs before parsing or writing.

## 5. Keep global enforcement disabled

Run before and after selected-driver enrollment:

```sql
update public.driver_verification_settings
set global_enforcement_enabled=false,
    identity_recheck_enabled=false,
    identity_provider='didit',
    updated_at=now()
where singleton;

select global_enforcement_enabled,identity_recheck_enabled,identity_provider
from public.driver_verification_settings where singleton;
```

Both Boolean values must be `false`.

## 6. Selected-driver rollout and force action

Confirm the driver has every required Phase 1 item approved, including a verified JPEG/PNG Profile Selfie under 2 MB in private storage. Replace `TEST_DRIVER_UID`:

```sql
insert into public.driver_verification_rollout
  (driver_firebase_uid,enforcement_enabled,identity_recheck_enabled,note)
values ('TEST_DRIVER_UID',true,true,'Selected Didit staging driver')
on conflict(driver_firebase_uid) do update
set enforcement_enabled=true,identity_recheck_enabled=true,note=excluded.note;

select driver_firebase_uid,enforcement_enabled,identity_recheck_enabled,note
from public.driver_verification_rollout where identity_recheck_enabled;
```

Use **Require Verification on Next Go Online** in Admin → Verification and enter an auditable reason. It revokes current authorization immediately. Admin has no pass, skip, biometric approval, or permanent bypass action.

An authorized SQL operator can use the same audited RPC under a real existing admin session:

```sql
select public.admin_set_driver_identity_force_v1(
  'TEST_DRIVER_UID',true,'Selected-driver staging verification test'
);
```

## 7. Regression and post-deployment checklist

Use a disposable/local database first. If remote staging SQL testing is explicitly authorized, replace `STAGING_DATABASE_URL`:

```sh
psql 'STAGING_DATABASE_URL' -v ON_ERROR_STOP=1 \
  -f supabase/tests/driver_verification_phase1.sql \
  -f supabase/tests/driver_identity_recheck_phase2.sql \
  -f supabase/tests/driver_identity_didit_staging.sql \
  -f supabase/tests/driver_identity_phase2_hardening.sql
```

Verify:

- Global Phase 1 and Phase 2 flags are still false.
- Only `TEST_DRIVER_UID` has selected Phase 2 enrollment.
- Both functions are deployed and all provider secret names exist.
- Didit points to staging and sends `status.updated`.
- Sandbox key, workflow, webhook secret, environment, and allowed host agree.
- Client roles cannot read provider session secrets or provider events.
- Pending, forced, malformed, and expired states have no usable authorization.
- Ride and food assignment reject missing/expired authorization.
- Admin shows Phase 1, rollout, challenge, attempts, expiry, cooldown, authorization, and trusted activity.
- Lumo retains no live capture, video, biometric template, raw webhook body, or raw provider payload.

Real Didit camera, signed-webhook end-to-end, and physical-device checks can remain deferred for this preparation task, but must be completed before broader production rollout.

## 8. Reference selfie and privacy

The session function authenticates ownership, requests a 60-second signed URL for the approved private Phase 1 Profile Selfie, downloads and validates JPEG/PNG data server-side, and sends it over TLS as `portrait_image`. The signed URL and bytes never return to iOS or admin.

Lumo stores provider/session/event references, normalized result, bounded scores, sanitized warning codes, timestamps, authorization history, and audit events. It does not store the live selfie, liveness video, biometric template, raw face image, raw webhook body, or unnecessary payloads. Terminal challenges remove the stored hosted-session URL. Complete DPA, consent, regional-processing, deletion, and biometric-law review before production.

## 9. Emergency disable and rollback

Emergency global and selected-driver Phase 2 disable, without changing Phase 1:

```sql
update public.driver_verification_settings
set identity_recheck_enabled=false,updated_at=now() where singleton;

update public.driver_verification_rollout
set identity_recheck_enabled=false where identity_recheck_enabled;
```

Disable one driver while retaining history:

```sql
update public.driver_verification_rollout
set identity_recheck_enabled=false,note='Phase 2 rollout disabled'
where driver_firebase_uid='TEST_DRIVER_UID';
```

Then disable the Didit webhook and rotate/revoke sandbox credentials. Never manufacture passes or fallback authorizations. Retain audit history according to approved policy. Roll application code back by redeploying known-good iOS/admin/functions while all Phase 2 flags stay false; additive database migrations should normally be forward-fixed.

## 10. Production procedure

1. Complete deferred sandbox camera/device/webhook testing and privacy/security review.
2. Obtain explicit `PRODUCTION_PROJECT_REF`; never infer it from a local link.
3. Review `supabase migration list --linked` and `supabase db push --dry-run` against production.
4. Apply migrations in the documented order.
5. Configure a separate live Didit application, workflow, webhook, key, and secret.
6. Set `DIDIT_ENVIRONMENT=live` with reviewed live hosts.
7. Deploy both functions and verify signature rejection behavior.
8. Keep global `identity_recheck_enabled=false`.
9. Enroll only named internal production drivers and monitor audit/error rates.
10. Require a separate explicit decision before broader rollout.

Production secrets checklist: server-only `IDENTITY_PROVIDER=didit`, live `DIDIT_API_KEY`, published live `DIDIT_WORKFLOW_ID`, live `DIDIT_WEBHOOK_SECRET`, `DIDIT_ENVIRONMENT=live`, exact `DIDIT_ALLOWED_HOSTS`, and any optional exact callback/host pair. Confirm no secret appears in an app bundle, admin build, migration, repository, or log.

Global Phase 2 must remain off.
