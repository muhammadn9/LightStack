// delete-account: permanently deletes the calling user's account and data.
//
// - The caller's JWT is verified with the anon client (auth.getUser()). ONLY that user's id is
//   used; the request body is never trusted for identity.
// - The service-role key (SUPABASE_SERVICE_ROLE_KEY) lives only here, never in the app.
// - Every user-owned table is cleared explicitly (children first), then auth.admin.deleteUser.
//   All user tables also have ON DELETE CASCADE to auth.users, so the explicit pass is
//   belt and braces; tables that do not exist (yet) are skipped.
// - Idempotent: a second call (e.g. a retry after a lost response) returns { ok: true }.
// - Sign in with Apple: if the app sends `apple_authorization_code` and the APPLE_* secrets are
//   set, the Apple refresh token is revoked (App Store guideline 5.1.1(v)). See docs/privacy.
//
// Request body (optional): { apple_authorization_code?: string }
// Response: { ok: true } or { ok: false, error: "<code>" }
//
// Secrets: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (provided by Supabase);
// optional APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (contents of the .p8), APPLE_CLIENT_ID
// (the app bundle id; the Services ID for web flows).

import { createClient } from "jsr:@supabase/supabase-js@2";

// Children before parents. Order only matters if a cascade is ever removed.
const USER_TABLES = [
  "food_entries",
  "water_entries",
  "day_notes",
  "meal_slots",
  "foods",
  "nutrition_plans",
  "nutrition_goal_settings",
  "nutrition_targets",
  "planned_sessions",
  "month_plans",
  "personal_records",
  "workouts", // exercises and sets cascade from workouts
  "ai_context_summaries",
  "rest_days",
  "sync_tombstones",
  "rate_limits",
  "profiles",
];

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function fail(code: string, status: number): Response {
  return json({ ok: false, error: code }, status);
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** ES256 client secret JWT for Apple's token endpoints (valid 5 minutes). */
async function appleClientSecret(teamId: string, keyId: string, pem: string, clientId: string): Promise<string> {
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: teamId,
    iat: now,
    exp: now + 300,
    aud: "https://appleid.apple.com",
    sub: clientId,
  }));
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${payload}`)),
  );
  return `${header}.${payload}.${b64url(sig)}`;
}

/** Exchanges the authorization code for a refresh token, then revokes it. Throws on failure. */
async function revokeApple(code: string): Promise<void> {
  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const pem = Deno.env.get("APPLE_PRIVATE_KEY") ?? "";
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? "";
  if (!teamId || !keyId || !pem || !clientId) throw new Error("apple_not_configured");
  const secret = await appleClientSecret(teamId, keyId, pem, clientId);
  const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: secret,
      code,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenRes.ok) throw new Error(`apple_token_${tokenRes.status}`);
  const { refresh_token } = await tokenRes.json();
  if (!refresh_token) throw new Error("apple_no_refresh_token");
  const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: secret,
      token: refresh_token,
      token_type_hint: "refresh_token",
    }),
  });
  if (!revokeRes.ok) throw new Error(`apple_revoke_${revokeRes.status}`);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return fail("method_not_allowed", 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey) return fail("not_configured", 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return fail("unauthorized", 401);

  // 1. Identify the caller from their JWT only.
  const anon = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await anon.auth.getUser();
  if (userError || !userData?.user) {
    // A valid token for a user that no longer exists means a previous call already finished.
    const code = (userError as { code?: string } | null)?.code;
    if (code === "user_not_found") return json({ ok: true, already_deleted: true });
    return fail("unauthorized", 401);
  }
  const userId = userData.user.id;
  const providers = (userData.user.identities ?? []).map((i) => i.provider);

  let appleCode = "";
  try {
    const body = await req.json();
    if (typeof body?.apple_authorization_code === "string") appleCode = body.apple_authorization_code;
  } catch {
    // no body is fine
  }

  // 2. Best-effort Apple revocation. Never blocks deletion; reported in the response.
  let appleRevoked: boolean | undefined;
  if (providers.includes("apple") && appleCode) {
    try {
      await revokeApple(appleCode);
      appleRevoked = true;
    } catch (e) {
      appleRevoked = false;
      console.error("apple revoke failed", (e as Error).message);
    }
  }

  // 3. Delete the user's rows, then the auth user.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  for (const table of USER_TABLES) {
    const { error } = await admin.from(table).delete().eq("user_id", userId);
    if (!error) continue;
    // Missing table / column on this deployment: nothing to delete there.
    if (["42P01", "42703", "PGRST205", "PGRST204"].includes(error.code ?? "")) continue;
    console.error("delete failed", table, error.code, error.message);
    return fail("data_delete_failed", 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError && (deleteError as { code?: string }).code !== "user_not_found") {
    console.error("deleteUser failed", deleteError.message);
    return fail("user_delete_failed", 500);
  }

  return json({ ok: true, ...(appleRevoked === undefined ? {} : { apple_revoked: appleRevoked }) });
});
