// account-delete: Konto endgültig löschen (App-Store-Richtlinie 5.1.1(v), Plan Phase 9).
//
// Aufruf aus der App mit dem Nutzer-JWT (verify_jwt = true). Ablauf:
//   1. Nutzer aus dem JWT bestimmen (auth.getUser) – nie aus dem Request-Body.
//   2. Mit Apple angemeldet: Die App schickt einen frischen Autorisierungscode (erneute Bestätigung).
//      Code gegen Tokens tauschen und das Refresh-Token widerrufen (Apple TN3194, REST-API
//      /auth/token und /auth/revoke). Familiar speichert keine Apple-Tokens.
//   3. RPC prepare_account_deletion (nur service_role, Migration 0010): Familien ohne weitere
//      Mitglieder löschen, Admin-Rolle weitergeben, Besitz an Aufgabenbildern lösen,
//      Pfade der Profilbilder liefern.
//   4. Profilbilder über die Storage-API löschen (nie per SQL).
//   5. Auth-Nutzer löschen; Profil, Mitgliedschaften und Zuweisungen folgen per Cascade.
//
// Apple-Secrets: ein Schlüssel mit „Sign in with Apple“ (gern derselbe wie für APNs):
// APPLE_SIGNIN_KEY_P8 / APPLE_SIGNIN_KEY_ID, sonst APNS_KEY_P8 / APNS_KEY_ID; Team APNS_TEAM_ID;
// client_id = Bundle-ID APNS_TOPIC.
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let s = "";
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// Client-Secret für die Apple-REST-API (ES256-JWT, Apple „Creating a client secret“).
async function appleClientSecret(keyP8: string, keyID: string, teamID: string, clientID: string): Promise<string> {
  const body = keyP8.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64url(JSON.stringify({
    iss: teamID, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: clientID,
  }));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  return `${header}.${claims}.${base64url(signature)}`;
}

/// Autorisierungscode (5 Minuten gültig, einmalig) → Tokens → Widerruf. Liefert einen Fehlertext oder null.
async function revokeAppleSignIn(code: string): Promise<string | null> {
  const keyP8 = Deno.env.get("APPLE_SIGNIN_KEY_P8") ?? Deno.env.get("APNS_KEY_P8");
  const keyID = Deno.env.get("APPLE_SIGNIN_KEY_ID") ?? Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const clientID = Deno.env.get("APNS_TOPIC");
  if (!keyP8 || !keyID || !teamID || !clientID) return "apple_not_configured";

  const secret = await appleClientSecret(keyP8, keyID, teamID, clientID);
  const form = { "Content-Type": "application/x-www-form-urlencoded" };
  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: form,
    body: new URLSearchParams({ client_id: clientID, client_secret: secret, code, grant_type: "authorization_code" }),
  });
  if (!tokenResponse.ok) return `token ${tokenResponse.status} ${await tokenResponse.text()}`;
  const tokens = await tokenResponse.json();
  const [token, hint] = tokens.refresh_token
    ? [tokens.refresh_token, "refresh_token"]
    : [tokens.access_token, "access_token"];
  if (!token) return "no_token";

  const revokeResponse = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: form,
    body: new URLSearchParams({ client_id: clientID, client_secret: secret, token, token_type_hint: hint }),
  });
  return revokeResponse.ok ? null : `revoke ${revokeResponse.status} ${await revokeResponse.text()}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "unauthorized" }, 401);

  // Neuer Secret-Key (Standard), sonst der Legacy-Service-Role-Key.
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  if (!key || !url) return json({ error: "misconfigured" }, 500);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  const userId = userData?.user?.id;
  if (userError || !userId) return json({ error: "unauthorized" }, 401);

  // Apple-Anmeldung widerrufen. Ein Fehlschlag blockiert die Löschung nicht (das Recht auf
  // Löschung geht vor); er wird protokolliert, damit er behoben werden kann.
  const body = await req.json().catch(() => ({}));
  const appleCode = typeof body?.apple_authorization_code === "string" ? body.apple_authorization_code : null;
  let appleRevoked: boolean | null = null;
  if (appleCode) {
    const problem = await revokeAppleSignIn(appleCode).catch((e) => String(e));
    appleRevoked = problem === null;
    if (problem) console.error("apple revoke failed", problem);
  }

  const { data, error } = await admin.rpc("prepare_account_deletion", { p_user_id: userId });
  if (error) return json({ error: "prepare_failed", message: error.message }, 500);

  const avatarPaths: string[] = data?.avatar_paths ?? [];
  if (avatarPaths.length > 0) {
    const { error: storageError } = await admin.storage.from("avatars").remove(avatarPaths);
    if (storageError) return json({ error: "storage", message: storageError.message }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) return json({ error: "delete_failed", message: deleteError.message }, 500);

  return json({ deleted: true, apple_revoked: appleRevoked });
});
