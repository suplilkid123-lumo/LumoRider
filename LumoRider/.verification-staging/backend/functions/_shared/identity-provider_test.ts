import {
  IdentityProviderPayloadError,
  normalizeDiditWebhook,
  validateProviderHostedUrl,
  verifyDiditRawWebhookSignature,
} from "./identity-provider.ts";

const workflow = "22222222-3333-4444-5555-666666666666";
const challenge = "11111111-2222-4333-8444-555555555555";
const session = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function hmacHex(body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)),
  );
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function approvedPayload(overrides: Record<string, unknown> = {}) {
  return {
    event_id: "event-12345678",
    webhook_type: "status.updated",
    session_id: session,
    vendor_data: challenge,
    workflow_id: workflow,
    workflow_version: 3,
    environment: "sandbox",
    metadata: { lumo_environment: "sandbox" },
    status: "Approved",
    decision: {
      liveness_checks: [{
        status: "Approved",
        score: 94.26,
        method: "ACTIVE_3D",
        warnings: [],
      }],
      face_matches: [{ status: "Approved", score: 96.12, warnings: [] }],
    },
    ...overrides,
  };
}

Deno.test("Didit approved webhook requires liveness and face match", () => {
  Deno.env.set("IDENTITY_PROVIDER", "didit");
  Deno.env.set("DIDIT_WORKFLOW_ID", workflow);
  Deno.env.set("DIDIT_ENVIRONMENT", "sandbox");
  const result = normalizeDiditWebhook(JSON.stringify(approvedPayload()));
  assert(result.outcome === "passed", "approved result should pass");
  assert(
    result.safeRiskMetadata.face_match_score === 96.1,
    "score should be sanitized and rounded",
  );
  let rejected = false;
  try {
    normalizeDiditWebhook(
      JSON.stringify(
        approvedPayload({
          decision: {
            liveness_checks: [{ status: "Approved" }],
            face_matches: [],
          },
        }),
      ),
    );
  } catch (error) {
    rejected = error instanceof IdentityProviderPayloadError;
  }
  assert(rejected, "missing face match must fail closed");

  rejected = false;
  try {
    normalizeDiditWebhook(
      JSON.stringify(
        approvedPayload({
          decision: {
            liveness_checks: [
              { status: "Approved" },
              { status: "Declined" },
            ],
            face_matches: [{ status: "Approved" }],
          },
        }),
      ),
    );
  } catch (error) {
    rejected = error instanceof IdentityProviderPayloadError;
  }
  assert(rejected, "a declined biometric node must fail closed");
});

Deno.test("Didit webhook requires the bound Lumo environment", () => {
  Deno.env.set("IDENTITY_PROVIDER", "didit");
  Deno.env.set("DIDIT_WORKFLOW_ID", workflow);
  Deno.env.set("DIDIT_ENVIRONMENT", "sandbox");
  let rejected = false;
  try {
    normalizeDiditWebhook(JSON.stringify(approvedPayload({ metadata: {} })));
  } catch (error) {
    rejected = error instanceof IdentityProviderPayloadError;
  }
  assert(rejected, "missing environment binding must fail closed");
});

Deno.test("Didit unknown status and unsafe hosted URL fail closed", () => {
  Deno.env.set("IDENTITY_PROVIDER", "didit");
  Deno.env.set("DIDIT_WORKFLOW_ID", workflow);
  let rejectedStatus = false;
  try {
    normalizeDiditWebhook(
      JSON.stringify(approvedPayload({ status: "Unexpected" })),
    );
  } catch (error) {
    rejectedStatus = error instanceof IdentityProviderPayloadError;
  }
  assert(rejectedStatus, "unknown status must be rejected");
  let rejectedHost = false;
  try {
    validateProviderHostedUrl("https://evil.example/session/token");
  } catch (error) {
    rejectedHost = error instanceof IdentityProviderPayloadError;
  }
  assert(rejectedHost, "unknown provider host must be rejected");
});

Deno.test("Didit raw-body HMAC validates and rejects forged or stale events", async () => {
  const secret = "staging-webhook-secret-for-tests";
  const body = JSON.stringify(approvedPayload());
  const now = 1774970000;
  Deno.env.set("IDENTITY_PROVIDER", "didit");
  Deno.env.set("DIDIT_WEBHOOK_SECRET", secret);
  const signature = await hmacHex(body, secret);
  assert(
    await verifyDiditRawWebhookSignature(body, signature, String(now), now),
    "valid signature should pass",
  );
  assert(
    !await verifyDiditRawWebhookSignature(
      `${body} `,
      signature,
      String(now),
      now,
    ),
    "modified raw body must fail",
  );
  assert(
    !await verifyDiditRawWebhookSignature(
      body,
      signature,
      String(now - 301),
      now,
    ),
    "stale event must fail",
  );
});
