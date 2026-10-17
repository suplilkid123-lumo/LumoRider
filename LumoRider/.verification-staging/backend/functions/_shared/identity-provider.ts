export type ProviderSessionRequest = {
  challengeId: string;
  driverId: string;
  referenceStoragePath: string;
  referencePortraitBase64: string;
  expiresAt: string;
  attemptNumber: number;
};

export type ProviderSession = {
  provider: "didit";
  sessionReference: string;
  verificationUrl: string;
};
export type ProviderOutcome =
  | "pending"
  | "passed"
  | "failed"
  | "expired"
  | "cancelled";
export type NormalizedProviderResult = {
  provider: "didit";
  eventReference: string;
  sessionReference: string;
  challengeReference: string;
  workflowReference: string;
  eventType: "status.updated";
  outcome: ProviderOutcome;
  failureCategory: string | null;
  safeRiskMetadata: Record<string, unknown>;
};

export class IdentityProviderNotConfiguredError extends Error {}
export class IdentityProviderConfigurationError extends Error {}
export class IdentityProviderRequestError extends Error {}
export class IdentityProviderPayloadError extends Error {}

const DIDIT_PROVIDER = "didit" as const;
const DIDIT_API_ORIGIN = "https://verification.didit.me";

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new IdentityProviderNotConfiguredError(`${name} is not configured.`);
  }
  return value;
}

function configuredProvider(): "didit" {
  const value = requiredEnvironment("IDENTITY_PROVIDER").toLowerCase();
  if (value !== DIDIT_PROVIDER) {
    throw new IdentityProviderConfigurationError(
      `Unsupported identity provider '${value}'.`,
    );
  }
  return DIDIT_PROVIDER;
}

function configuredEnvironment(): "sandbox" | "live" {
  const value = requiredEnvironment("DIDIT_ENVIRONMENT").toLowerCase();
  if (value !== "sandbox" && value !== "live") {
    throw new IdentityProviderConfigurationError(
      "DIDIT_ENVIRONMENT must be sandbox or live.",
    );
  }
  return value;
}

function hostAllowlist(name: string, defaults: string[] = []): Set<string> {
  const configured = (Deno.env.get(name) ?? "").split(",").map((host) =>
    host.trim().toLowerCase()
  ).filter(Boolean);
  return new Set([...defaults, ...configured]);
}

export function validateProviderHostedUrl(rawUrl: string): URL {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new IdentityProviderPayloadError(
      "Provider returned an invalid verification URL.",
    );
  }
  const allowed = hostAllowlist("DIDIT_ALLOWED_HOSTS", ["verify.didit.me"]);
  if (
    url.protocol !== "https:" || !allowed.has(url.hostname.toLowerCase()) ||
    url.username || url.password
  ) {
    throw new IdentityProviderPayloadError(
      "Provider returned a verification URL outside the allowlist.",
    );
  }
  return url;
}

export function validatedProviderCallbackUrl(): string | undefined {
  const raw = Deno.env.get("DIDIT_CALLBACK_URL")?.trim();
  if (!raw) return undefined;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new IdentityProviderConfigurationError(
      "DIDIT_CALLBACK_URL is invalid.",
    );
  }
  const allowed = hostAllowlist("IDENTITY_CALLBACK_ALLOWED_HOSTS");
  if (
    url.protocol !== "https:" || url.username || url.password ||
    !allowed.has(url.hostname.toLowerCase())
  ) {
    throw new IdentityProviderConfigurationError(
      "DIDIT_CALLBACK_URL is outside IDENTITY_CALLBACK_ALLOWED_HOSTS.",
    );
  }
  return url.toString();
}

function validReference(
  value: unknown,
  minimum = 3,
  maximum = 500,
): value is string {
  return typeof value === "string" && value.length >= minimum &&
    value.length <= maximum && /^[A-Za-z0-9._:-]+$/.test(value);
}

async function diditRequest(
  path: string,
  init: RequestInit,
): Promise<Response> {
  configuredProvider();
  const apiKey = requiredEnvironment("DIDIT_API_KEY");
  return fetch(`${DIDIT_API_ORIGIN}${path}`, {
    ...init,
    headers: { "x-api-key": apiKey, ...(init.headers ?? {}) },
  });
}

export async function createIdentityProviderSession(
  request: ProviderSessionRequest,
): Promise<ProviderSession> {
  const workflowId = requiredEnvironment("DIDIT_WORKFLOW_ID");
  const environment = configuredEnvironment();
  if (
    !validReference(request.challengeId, 36, 36) ||
    !request.referencePortraitBase64
  ) {
    throw new IdentityProviderRequestError(
      "The liveness session request is incomplete.",
    );
  }
  const callback = validatedProviderCallbackUrl();
  const payload: Record<string, unknown> = {
    workflow_id: workflowId,
    vendor_data: request.challengeId,
    portrait_image: request.referencePortraitBase64,
    language: "en",
    metadata: {
      lumo_challenge_id: request.challengeId,
      attempt_number: request.attemptNumber,
      lumo_environment: environment,
    },
  };
  if (callback) {
    payload.callback = callback;
    payload.callback_method = "both";
  }
  const response = await diditRequest("/v3/session/", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "accept": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    throw new IdentityProviderRequestError(
      `Didit session creation failed with HTTP ${response.status}.`,
    );
  }
  const result = await response.json() as Record<string, unknown>;
  if (
    !validReference(result.session_id, 36, 64) || typeof result.url !== "string"
  ) {
    throw new IdentityProviderPayloadError(
      "Didit returned a malformed session.",
    );
  }
  return {
    provider: DIDIT_PROVIDER,
    sessionReference: result.session_id,
    verificationUrl: validateProviderHostedUrl(result.url).toString(),
  };
}

function statusOutcome(status: unknown): ProviderOutcome {
  switch (status) {
    case "Not Started":
    case "In Progress":
    case "In Review":
    case "Resubmitted":
    case "Awaiting User":
      return "pending";
    case "Approved":
      return "passed";
    case "Declined":
      return "failed";
    case "Expired":
    case "Kyc Expired":
      return "expired";
    case "Abandoned":
      return "cancelled";
    default:
      throw new IdentityProviderPayloadError(
        "Didit returned an unknown status.",
      );
  }
}

function resultArray(
  decision: Record<string, unknown>,
  key: string,
): Record<string, unknown>[] {
  const value = decision[key];
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is Record<string, unknown> =>
    item !== null && typeof item === "object" && !Array.isArray(item)
  );
}

function finiteScore(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.round(Math.max(0, Math.min(100, value)) * 10) / 10;
}

function safeWarningCodes(items: Record<string, unknown>[]): string[] {
  const output = new Set<string>();
  for (const item of items) {
    for (const warning of Array.isArray(item.warnings) ? item.warnings : []) {
      const raw = typeof warning === "string"
        ? warning
        : warning && typeof warning === "object"
        ? (warning as Record<string, unknown>).code
        : undefined;
      if (typeof raw !== "string") continue;
      const normalized = raw.toLowerCase().replace(/[^a-z0-9_-]/g, "_").slice(
        0,
        64,
      );
      if (normalized) output.add(normalized);
      if (output.size === 10) return [...output];
    }
  }
  return [...output];
}

function normalizeDecision(
  status: unknown,
  value: unknown,
  environment: unknown,
  workflowVersion: unknown,
) {
  const outcome = statusOutcome(status);
  const decision = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
  const liveness = resultArray(decision, "liveness_checks");
  const faceMatches = resultArray(decision, "face_matches");
  const everyLivenessApproved = liveness.length > 0 &&
    liveness.every((item) => item.status === "Approved");
  const everyFaceMatchApproved = faceMatches.length > 0 &&
    faceMatches.every((item) => item.status === "Approved");
  if (outcome === "passed" &&
    (!everyLivenessApproved || !everyFaceMatchApproved)) {
    throw new IdentityProviderPayloadError(
      "Approved Didit result omitted required liveness or face-match approval.",
    );
  }
  let failureCategory: string | null = null;
  if (outcome === "failed") {
    failureCategory = liveness.some((item) => item.status === "Declined")
      ? "liveness_not_verified"
      : faceMatches.some((item) => item.status === "Declined")
      ? "reference_face_mismatch"
      : "provider_declined";
  } else if (outcome === "expired") {
    failureCategory = "provider_session_expired";
  } else if (outcome === "cancelled") {
    failureCategory = "provider_session_cancelled";
  }

  const safeRiskMetadata: Record<string, unknown> = {};
  const livenessApproved = liveness.find((item) => item.status === "Approved");
  const faceApproved = faceMatches.find((item) => item.status === "Approved");
  const livenessScore = finiteScore(livenessApproved?.score);
  const faceMatchScore = finiteScore(faceApproved?.score);
  if (livenessScore !== undefined) {
    safeRiskMetadata.liveness_score = livenessScore;
  }
  if (faceMatchScore !== undefined) {
    safeRiskMetadata.face_match_score = faceMatchScore;
  }
  if (typeof livenessApproved?.method === "string") {
    safeRiskMetadata.liveness_method = livenessApproved.method.replace(
      /[^A-Za-z0-9_-]/g,
      "",
    ).slice(0, 32);
  }
  if (environment === "sandbox" || environment === "live") {
    safeRiskMetadata.provider_environment = environment;
  }
  if (Number.isInteger(workflowVersion) && Number(workflowVersion) > 0) {
    safeRiskMetadata.workflow_version = workflowVersion;
  }
  const warnings = safeWarningCodes([...liveness, ...faceMatches]);
  if (warnings.length) safeRiskMetadata.warning_codes = warnings;
  return { outcome, failureCategory, safeRiskMetadata };
}

export function normalizeDiditWebhook(
  rawBody: string,
): NormalizedProviderResult {
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(rawBody) as Record<string, unknown>;
  } catch {
    throw new IdentityProviderPayloadError("Webhook body is not valid JSON.");
  }
  if (payload.webhook_type !== "status.updated") {
    throw new IdentityProviderPayloadError(
      "Unsupported Didit webhook event type.",
    );
  }
  if (
    !validReference(payload.event_id, 8, 200) ||
    !validReference(payload.session_id, 36, 64) ||
    !validReference(payload.vendor_data, 36, 36) ||
    !validReference(payload.workflow_id, 36, 64)
  ) {
    throw new IdentityProviderPayloadError(
      "Didit webhook identifiers are malformed.",
    );
  }
  if (payload.workflow_id !== requiredEnvironment("DIDIT_WORKFLOW_ID")) {
    throw new IdentityProviderPayloadError("Didit workflow mismatch.");
  }
  const expectedEnvironment = configuredEnvironment();
  const metadata = payload.metadata && typeof payload.metadata === "object" &&
      !Array.isArray(payload.metadata)
    ? payload.metadata as Record<string, unknown>
    : {};
  if (
    metadata.lumo_environment !== expectedEnvironment ||
    (payload.environment !== undefined &&
      payload.environment !== expectedEnvironment)
  ) {
    throw new IdentityProviderPayloadError("Didit environment mismatch.");
  }
  return {
    provider: DIDIT_PROVIDER,
    eventReference: payload.event_id,
    sessionReference: payload.session_id,
    challengeReference: payload.vendor_data,
    workflowReference: payload.workflow_id,
    eventType: "status.updated",
    ...normalizeDecision(
      payload.status,
      payload.decision,
      expectedEnvironment,
      payload.workflow_version,
    ),
  };
}

function hexadecimalBytes(value: string): Uint8Array | null {
  if (!/^[a-fA-F0-9]{64}$/.test(value)) return null;
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < value.length; index += 2) {
    bytes[index / 2] = Number.parseInt(value.slice(index, index + 2), 16);
  }
  return bytes;
}

export async function verifyDiditRawWebhookSignature(
  rawBody: string,
  signature: string | null,
  timestamp: string | null,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  configuredProvider();
  const provided = signature ? hexadecimalBytes(signature.trim()) : null;
  const sentAt = timestamp && /^\d{10}$/.test(timestamp)
    ? Number(timestamp)
    : NaN;
  if (
    !provided || !Number.isFinite(sentAt) || Math.abs(nowSeconds - sentAt) > 300
  ) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(requiredEnvironment("DIDIT_WEBHOOK_SECRET")),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "HMAC",
    key,
    Uint8Array.from(provided).buffer,
    new TextEncoder().encode(rawBody),
  );
}

export async function getIdentityProviderSessionStatus(
  sessionReference: string,
): Promise<ProviderOutcome> {
  if (!validReference(sessionReference, 36, 64)) {
    throw new IdentityProviderRequestError(
      "Invalid provider session reference.",
    );
  }
  const response = await diditRequest(
    `/v3/session/${encodeURIComponent(sessionReference)}/decision/`,
    { method: "GET", headers: { "accept": "application/json" } },
  );
  if (!response.ok) {
    throw new IdentityProviderRequestError(
      `Didit decision lookup failed with HTTP ${response.status}.`,
    );
  }
  return statusOutcome(
    (await response.json() as Record<string, unknown>).status,
  );
}

export async function purgeIdentityProviderSession(
  sessionReference: string,
  challengeReference: string,
): Promise<void> {
  if (
    !validReference(sessionReference, 36, 64) ||
    !validReference(challengeReference, 36, 36)
  ) return;
  await diditRequest(
    `/v3/session/${encodeURIComponent(sessionReference)}/delete/`,
    { method: "DELETE" },
  );
  await diditRequest("/v3/users/delete/", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "accept": "application/json",
    },
    body: JSON.stringify({ vendor_data_list: [challengeReference] }),
  });
}
