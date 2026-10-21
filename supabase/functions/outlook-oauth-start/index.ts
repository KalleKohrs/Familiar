// outlook-oauth-start: Anmelde-URL für „Outlook verbinden“ (Phase 8, Migration 0011).
//
// Aufruf aus der App mit Nutzer-JWT (verify_jwt = true). Erzeugt State und PKCE-Verifier,
// speichert den Verifier und nur den SHA-256 des States (outlook_create_oauth_state) und liefert
// die Microsoft-Anmelde-URL. Die App öffnet sie in ASWebAuthenticationSession.
// Microsoft-Doku: Authorization Code Flow mit PKCE (v2-oauth2-auth-code-flow).
import { createClient } from "npm:@supabase/supabase-js@2";

const SCOPES = "openid email offline_access https://graph.microsoft.com/Calendars.ReadBasic";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256(text: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "unauthorized" }, 401);

  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  const clientId = Deno.env.get("MS_CLIENT_ID");
  if (!key || !url || !clientId) return json({ error: "misconfigured" }, 500);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  const userId = userData?.user?.id;
  if (userError || !userId) return json({ error: "unauthorized" }, 401);

  const state = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(48)));
  const challenge = base64url(await sha256(verifier));

  const { error } = await admin.rpc("outlook_create_oauth_state", {
    p_user_id: userId,
    p_state_hash: hex(await sha256(state)),
    p_code_verifier: verifier,
  });
  if (error) return json({ error: "state_failed" }, 500);

  const authorize = new URL("https://login.microsoftonline.com/common/oauth2/v2.0/authorize");
  authorize.search = new URLSearchParams({
    client_id: clientId,
    response_type: "code",
    redirect_uri: `${url}/functions/v1/outlook-oauth-callback`,
    response_mode: "query",
    scope: SCOPES,
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
    prompt: "select_account",
  }).toString();

  return json({ url: authorize.toString() });
});
