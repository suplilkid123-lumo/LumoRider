import {
  createIdentityProviderSession,
  IdentityProviderConfigurationError,
  IdentityProviderNotConfiguredError,
  IdentityProviderPayloadError,
  IdentityProviderRequestError,
  purgeIdentityProviderSession,
  validateProviderHostedUrl,
} from "../_shared/identity-provider.ts";

const json = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json", "cache-control": "no-store", "x-content-type-options": "nosniff" },
});

const rpc = async (supabaseUrl: string, serviceKey: string, name: string, body: Record<string, unknown>) => {
  return fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { authorization: `Bearer ${serviceKey}`, apikey: serviceKey, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
};

function encodedObjectPath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(offset + 0x8000, bytes.length)));
  }
  return btoa(binary);
}

async function approvedReferencePortrait(
  supabaseUrl: string,
  serviceKey: string,
  driverId: string,
  storagePath: string,
): Promise<string> {
  const expectedPrefix = `${driverId}/profile_selfie/`;
  if (!storagePath.startsWith(expectedPrefix) || storagePath.includes("..") || storagePath.length > 1024) {
    throw new IdentityProviderRequestError("Approved reference path is invalid.");
  }
  const signResponse = await fetch(
    `${supabaseUrl}/storage/v1/object/sign/driver-verification/${encodedObjectPath(storagePath)}`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${serviceKey}`, apikey: serviceKey, "content-type": "application/json" },
      body: JSON.stringify({ expiresIn: 60 }),
    },
  );
  if (!signResponse.ok) throw new IdentityProviderRequestError("Approved reference could not be signed.");
  const signed = await signResponse.json() as { signedURL?: string };
  if (!signed.signedURL) throw new IdentityProviderPayloadError("Storage returned no signed reference URL.");
  const signedUrl = new URL(signed.signedURL, supabaseUrl);
  if (signedUrl.origin !== new URL(supabaseUrl).origin) throw new IdentityProviderPayloadError("Storage signed URL origin mismatch.");
  const imageResponse = await fetch(signedUrl);
  if (!imageResponse.ok) throw new IdentityProviderRequestError("Approved reference could not be read.");
  const contentType = imageResponse.headers.get("content-type")?.split(";", 1)[0].toLowerCase();
  if (contentType !== "image/jpeg" && contentType !== "image/png") {
    throw new IdentityProviderRequestError("Profile Selfie must be a JPEG or PNG image for liveness comparison.");
  }
  const bytes = new Uint8Array(await imageResponse.arrayBuffer());
  if (bytes.length < 100 || bytes.length > 2 * 1024 * 1024) {
    throw new IdentityProviderRequestError("Profile Selfie must be smaller than 2 MB for liveness comparison.");
  }
  return base64(bytes);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  const authorization = request.headers.get("authorization");
  if (!supabaseUrl || !anonKey || !serviceKey || !authorization?.startsWith("Bearer ")) {
    return json(401, { error: "authentication_required" });
  }

  let input: { challenge_id?: string; installation_id?: string };
  try { input = await request.json(); } catch { return json(400, { error: "invalid_request" }); }
  if (!input.challenge_id || !/^[0-9a-f-]{36}$/i.test(input.challenge_id) ||
      !input.installation_id || !/^[A-Za-z0-9._-]{16,128}$/.test(input.installation_id)) {
    return json(400, { error: "invalid_request" });
  }

  const preparedResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/prepare_driver_identity_provider_session_v1`, {
    method: "POST",
    headers: { authorization, apikey: anonKey, "content-type": "application/json" },
    body: JSON.stringify({ p_challenge_id: input.challenge_id, p_installation_id: input.installation_id }),
  });
  if (!preparedResponse.ok) {
    return json(preparedResponse.status === 401 || preparedResponse.status === 403 ? 403 : 409, {
      error: "challenge_unavailable",
      message: "This identity check is expired, cooling down, already finished, or belongs to another account.",
    });
  }
  const prepared = await preparedResponse.json() as Record<string, unknown>;

  if (prepared.resume_session === true) {
    const resumeResponse = await rpc(supabaseUrl, serviceKey, "get_driver_identity_provider_session_secret_v1", {
      p_challenge_id: input.challenge_id,
    });
    if (!resumeResponse.ok) return json(409, { error: "provider_session_unavailable", message: "This verification session can no longer be resumed." });
    const resumed = await resumeResponse.json() as Record<string, unknown>;
    if (typeof resumed.verification_url !== "string") return json(502, { error: "provider_session_invalid" });
    const url = validateProviderHostedUrl(resumed.verification_url);
    return json(200, { challenge_id: input.challenge_id, provider: resumed.provider, verification_url: url.toString(), expires_at: resumed.expires_at, resumed: true });
  }

  const creationToken = typeof prepared.creation_token === "string" ? prepared.creation_token : null;
  let providerSession: Awaited<ReturnType<typeof createIdentityProviderSession>> | undefined;
  try {
    if (!creationToken || typeof prepared.driver_firebase_uid !== "string" || typeof prepared.reference_storage_path !== "string") {
      throw new IdentityProviderPayloadError("Challenge preparation was incomplete.");
    }
    const portrait = await approvedReferencePortrait(supabaseUrl, serviceKey, prepared.driver_firebase_uid, prepared.reference_storage_path);
    providerSession = await createIdentityProviderSession({
      challengeId: String(prepared.challenge_id),
      driverId: prepared.driver_firebase_uid,
      referenceStoragePath: prepared.reference_storage_path,
      referencePortraitBase64: portrait,
      expiresAt: String(prepared.expires_at),
      attemptNumber: Number(prepared.attempt_number),
    });
    const attachResponse = await rpc(supabaseUrl, serviceKey, "attach_driver_identity_provider_session_v1", {
      p_challenge_id: input.challenge_id,
      p_creation_token: creationToken,
      p_provider: providerSession.provider,
      p_provider_session_reference: providerSession.sessionReference,
      p_verification_url: providerSession.verificationUrl,
    });
    if (!attachResponse.ok) throw new IdentityProviderRequestError("Provider session could not be attached.");
    return json(200, {
      challenge_id: input.challenge_id,
      provider: providerSession.provider,
      verification_url: providerSession.verificationUrl,
      expires_at: prepared.expires_at,
      resumed: false,
    });
  } catch (error) {
    if (providerSession) {
      try { await purgeIdentityProviderSession(providerSession.sessionReference, input.challenge_id); } catch { /* best-effort orphan cleanup */ }
    }
    if (creationToken) {
      await rpc(supabaseUrl, serviceKey, "release_driver_identity_provider_session_creation_v1", {
        p_challenge_id: input.challenge_id,
        p_creation_token: creationToken,
      });
    }
    if (error instanceof IdentityProviderNotConfiguredError || error instanceof IdentityProviderConfigurationError) {
      return json(503, { error: "provider_not_configured", message: "Didit staging is not configured. Jiylo has not accepted a verification result." });
    }
    if (error instanceof IdentityProviderRequestError && error.message.includes("Profile Selfie")) {
      return json(422, { error: "reference_selfie_incompatible", message: error.message });
    }
    return json(502, { error: "provider_session_failed", message: "The secure liveness session could not be started. No verification result was recorded." });
  }
});
