// outlook-oauth-callback: Rücksprung von Microsoft nach der Anmeldung (Phase 8, Migration 0011).
//
// Aufruf durch den Browser (verify_jwt = false). Löst den Einmal-State ein, tauscht Code + PKCE-
// Verifier mit dem Client Secret gegen Tokens, speichert das Refresh-Token nur im Vault, legt die
// Kalenderliste an und stößt den ersten Abgleich an. Antwortet immer mit einer Weiterleitung auf
// familiar://outlook?status=… – ASWebAuthenticationSession schließt sich dann.
import { createClient } from "npm:@supabase/supabase-js@2";

const SCOPES = "openid email offline_access https://graph.microsoft.com/Calendars.ReadBasic";

function backToApp(status: string, reason?: string): Response {
  const target = new URL("familiar://outlook");
  target.searchParams.set("status", status);
  if (reason) target.searchParams.set("reason", reason);
  return new Response(null, { status: 302, headers: { Location: target.toString() } });
}

async function sha256Hex(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

/// Liest die Claims des id_token. Es kommt direkt per TLS vom Token-Endpunkt und ist für unsere
/// App ausgestellt; laut Microsoft darf die App es zum Anzeigen dekodieren.
function idTokenClaims(idToken: string | undefined): Record<string, unknown> {
  if (!idToken) return {};
  try {
    const part = idToken.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(part.padEnd(part.length + (4 - (part.length % 4)) % 4, "=")));
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  const params = new URL(req.url).searchParams;
  if (params.get("error")) {
    // z. B. access_denied (abgebrochen) oder Firmen-Richtlinie (Zustimmung durch Admin nötig).
    return backToApp("error", params.get("error") ?? "unknown");
  }
  const code = params.get("code");
  const state = params.get("state");
  if (!code || !state) return backToApp("error", "invalid_request");

  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  const clientId = Deno.env.get("MS_CLIENT_ID");
  const clientSecret = Deno.env.get("MS_CLIENT_SECRET");
  if (!key || !url || !clientId || !clientSecret) return backToApp("error", "misconfigured");

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: stateRow } = await admin.rpc("outlook_consume_oauth_state", { p_state_hash: await sha256Hex(state) });
  if (!stateRow?.user_id) return backToApp("error", "expired");

  const tokenResponse = await fetch("https://login.microsoftonline.com/common/oauth2/v2.0/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      scope: SCOPES,
      code,
      redirect_uri: `${url}/functions/v1/outlook-oauth-callback`,
      grant_type: "authorization_code",
      code_verifier: stateRow.code_verifier,
    }),
  });
  const tokens = await tokenResponse.json();
  if (!tokenResponse.ok || !tokens.refresh_token || !tokens.access_token) {
    return backToApp("error", tokens.error ?? "token_failed");
  }

  const claims = idTokenClaims(tokens.id_token);
  const accountId = String(claims.oid ?? claims.sub ?? "");
  const email = String(claims.email ?? claims.preferred_username ?? "");
  if (!accountId) return backToApp("error", "no_account");

  const { data: connectionId, error: saveError } = await admin.rpc("outlook_save_connection", {
    p_user_id: stateRow.user_id,
    p_account_id: accountId,
    p_account_email: email || null,
    p_refresh_token: tokens.refresh_token,
    p_scopes: tokens.scope ?? SCOPES,
  });
  if (saveError || !connectionId) return backToApp("error", "save_failed");

  // Kalenderliste (Calendars.ReadBasic reicht laut Graph-Doku).
  const calendarsResponse = await fetch(
    "https://graph.microsoft.com/v1.0/me/calendars?$select=id,name,hexColor,isDefaultCalendar&$top=100",
    { headers: { Authorization: `Bearer ${tokens.access_token}` } },
  );
  if (calendarsResponse.ok) {
    const body = await calendarsResponse.json();
    const calendars = (body.value ?? []).map((c: Record<string, unknown>) => ({
      id: c.id,
      name: c.name,
      color: c.hexColor || null,
      is_default: c.isDefaultCalendar === true,
    }));
    await admin.rpc("outlook_upsert_calendars", { p_connection_id: connectionId, p_calendars: calendars });
  }

  await admin.rpc("outlook_request_sync_for", { p_user_id: stateRow.user_id });
  return backToApp("connected");
});
