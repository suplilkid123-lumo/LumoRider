# Driver Identity Recheck Phase 2 — Didit setup

Phase 2 uses a Didit **Biometric Authentication** hosted workflow. Didit was selected because its hosted flow supports camera-based liveness/anti-spoofing, face matching against a supplied portrait, sandbox/live separation, server-side decisions, and raw-body HMAC-SHA256 webhooks. The iOS app never receives an API key and never decides whether a check passed.

Global Phase 2 enforcement remains disabled. Enroll only named staging drivers through `driver_verification_rollout` until security, privacy, and operational review is complete.

## Didit staging application

1. Create a separate sandbox application in the Didit Business Console.
2. Create and publish a **Biometric Authentication** workflow containing both Liveness Detection and Face Match. Configure Face Match to use the `portrait_image` supplied when the session is created.
3. Set the session timeout no longer than Lumo's `challenge_expiration_minutes` (15 minutes by default).
4. Add a v3 webhook destination subscribed to `status.updated`:

   `https://YOUR_PROJECT_REF.supabase.co/functions/v1/driver-identity-webhook`

5. Store the destination's `secret_shared_key`; this is `DIDIT_WEBHOOK_SECRET`.
6. Under App Settings → Data, select the shortest available retention, **1 month**. Lumo additionally requests deletion of the final session and its challenge-scoped Didit user after the signed final webhook is committed. The one-month setting is the fallback if immediate purge fails.
7. Confirm the application environment is `sandbox`. Use a separate application, key, workflow, and webhook secret for production.

Required Edge Function secrets:

```sh
supabase secrets set \
  IDENTITY_PROVIDER=didit \
  DIDIT_API_KEY='REPLACE_WITH_SANDBOX_KEY' \
  DIDIT_WORKFLOW_ID='REPLACE_WITH_PUBLISHED_WORKFLOW_UUID' \
  DIDIT_WEBHOOK_SECRET='REPLACE_WITH_DESTINATION_SECRET' \
  DIDIT_ENVIRONMENT=sandbox \
  DIDIT_ALLOWED_HOSTS=verify.didit.me
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are supplied by Supabase to deployed Edge Functions. Never copy any of these provider/service secrets into iOS, Info.plist, the admin app, or a public environment variable.

`DIDIT_CALLBACK_URL` is optional. The iOS flow works by closing the hosted page and polling trusted backend state. If a callback is later added, set an exact HTTPS host allowlist too:

```sh
supabase secrets set DIDIT_CALLBACK_URL='https://identity-staging.example.com/complete' \
  IDENTITY_CALLBACK_ALLOWED_HOSTS=identity-staging.example.com
```

The provider response URL is accepted only from `verify.didit.me` (plus explicitly reviewed `DIDIT_ALLOWED_HOSTS` entries). Callback URLs require HTTPS, an exact allowed hostname, and no embedded credentials.

## Reference selfie and data handling

The reference is the currently approved Phase 1 `profile_selfie` object in the private `driver-verification` bucket. The session function:

1. authenticates the Driver Lumo user and verifies challenge ownership/installation;
2. asks Supabase Storage for a 60-second signed URL using the service role;
3. downloads the image inside the Edge Function, validates JPEG/PNG and Didit's 2 MB limit;
4. sends it to Didit as `portrait_image` over TLS; and
5. never returns the signed URL or portrait bytes to the app.

Lumo retains the approved Phase 1 selfie under its existing private-storage policy. Lumo does **not** store the live liveness capture, biometric template, or raw provider webhook. Lumo stores only challenge/session references, normalized outcome/failure category, bounded scores/method/warning codes, event identifiers, timestamps, and authorization audit records. Didit processes the supplied reference and live capture; after a final signed event Lumo calls Didit's session and challenge-scoped user deletion endpoints. Didit's configured one-month policy is the cleanup fallback. Confirm contractual deletion behavior, DPA, regional processing, biometric consent/disclosure, and applicable retention law before production use.

## Database and deployment

From `/Users/alyaaalzarkani/LumoBackend` with the intended staging project linked:

```sh
supabase db push --dry-run
supabase db push
supabase functions deploy driver-identity-session --no-verify-jwt
supabase functions deploy driver-identity-webhook --no-verify-jwt
```

The session function performs its own Firebase/Supabase JWT authorization through the existing authenticated RPC. The webhook must use `--no-verify-jwt` because Didit authenticates with its HMAC signature; the function rejects missing, forged, or stale signatures before parsing or writing an event.

Run the disposable SQL regression suite against staging only:

```sh
psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/driver_verification_phase1.sql \
  -f supabase/tests/driver_identity_recheck_phase2.sql \
  -f supabase/tests/driver_identity_didit_staging.sql
```

## Enroll one staging driver

First verify that the driver has all required Phase 1 documents approved, including a JPEG/PNG Profile Selfie under 2 MB. Keep both global flags off, set the provider name, and enable only the test driver:

```sql
update public.driver_verification_settings
set global_enforcement_enabled=false,
    identity_recheck_enabled=false,
    identity_provider='didit',
    updated_at=now()
where singleton;

insert into public.driver_verification_rollout
  (driver_firebase_uid,enforcement_enabled,identity_recheck_enabled,note)
values ('REPLACE_TEST_DRIVER_UID',true,true,'Didit staging test driver')
on conflict(driver_firebase_uid) do update
set enforcement_enabled=true,identity_recheck_enabled=true,note=excluded.note;
```

Use **Require Verification on Next Go Online** in the existing admin Verification section to revoke any active authorization and force the next check. Admins cannot mark a biometric challenge passed.

## Production promotion

Create a separate live Didit application and workflow, complete privacy/legal review and consent copy, configure a separate live webhook destination/secret, use the shortest approved retention, set `DIDIT_ENVIRONMENT=live`, and validate with selected internal drivers. Do not turn on `driver_verification_settings.identity_recheck_enabled` globally during this process.

## Rollback

1. Disable the selected driver's `identity_recheck_enabled` rollout flag (or remove that rollout row if Phase 1 enforcement does not depend on it).
2. Keep global `identity_recheck_enabled=false`.
3. Disable the Didit webhook destination and rotate/delete its credentials.
4. Existing non-enrolled drivers remain unaffected; no client-side bypass or fabricated authorization is needed.
