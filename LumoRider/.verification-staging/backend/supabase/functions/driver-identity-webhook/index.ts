import {
  IdentityProviderNotConfiguredError,
  IdentityProviderPayloadError,
  normalizeDiditWebhook,
  purgeIdentityProviderSession,
  verifyDiditRawWebhookSignature,
} from "../_shared/identity-provider.ts";

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (declaredLength > 1024 * 1024) {
    return json(413, { error: "payload_too_large" });
  }

  const rawBody = await request.text();
  if (!rawBody || new TextEncoder().encode(rawBody).length > 1024 * 1024) {
    return json(413, { error: "payload_too_large" });
  }

  try {
    const signatureValid = await verifyDiditRawWebhookSignature(
      rawBody,
      request.headers.get("x-signature"),
      request.headers.get("x-timestamp"),
    );
    if (!signatureValid) {
      return json(401, { error: "invalid_webhook_signature" });
    }
  } catch (error) {
    if (error instanceof IdentityProviderNotConfiguredError) {
      return json(503, { error: "provider_not_configured" });
    }
    return json(401, { error: "invalid_webhook_signature" });
  }

  let result;
  try {
    result = normalizeDiditWebhook(rawBody);
  } catch (error) {
    if (error instanceof IdentityProviderPayloadError) {
      return json(400, { error: "invalid_provider_payload" });
    }
    return json(503, { error: "provider_not_configured" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !serviceKey) {
    return json(503, { error: "backend_not_configured" });
  }

  const completionResponse = await fetch(
    `${supabaseUrl}/rest/v1/rpc/process_driver_identity_provider_event_v1`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${serviceKey}`,
        apikey: serviceKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        p_provider: result.provider,
        p_provider_session_reference: result.sessionReference,
        p_provider_event_reference: result.eventReference,
        p_challenge_reference: result.challengeReference,
        p_outcome: result.outcome,
        p_failure_category: result.failureCategory,
        p_safe_risk_metadata: result.safeRiskMetadata,
      }),
    },
  );
  if (!completionResponse.ok) {
    // A 404 asks Didit to retry an event that may have raced the session attach.
    // Transient backend failures must also remain retryable; returning 409 for
    // those would acknowledge neither success nor a useful retry condition.
    const responseStatus = completionResponse.status === 404
      ? 404
      : completionResponse.status >= 500
      ? 503
      : 409;
    return json(responseStatus, {
      error: "provider_event_rejected",
    });
  }

  const processed = await completionResponse.json() as Record<string, unknown>;
  if (result.outcome !== "pending") {
    try {
      await purgeIdentityProviderSession(
        result.sessionReference,
        result.challengeReference,
      );
    } catch {
      // Completion is authoritative even if provider cleanup must fall back to its one-month retention policy.
    }
  }
  return json(200, { received: true, duplicate: processed.duplicate === true });
});
