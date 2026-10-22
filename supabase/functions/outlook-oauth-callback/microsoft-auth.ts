// Anmeldung der App selbst bei Microsoft (Client-Authentifizierung für /token).
// Identische Kopie in outlook-oauth-callback/ und outlook-sync/ (je Function ein eigenes Paket).
//
// Zertifikat (Microsoft: „certificate credentials“, private_key_jwt, PS256):
//   MS_CERT_PRIVATE_KEY   – privater RSA-Schlüssel (PKCS#8, PEM), nur in Supabase-Secrets
//   MS_CERT_THUMBPRINT    – Base64url-SHA-256 des Zertifikats (DER), kein Geheimnis

export const TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token";

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let s = "";
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedKey: CryptoKey | null = null;

async function signingKey(pem: string): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  cachedKey = await crypto.subtle.importKey("pkcs8", der, { name: "RSA-PSS", hash: "SHA-256" }, false, ["sign"]);
  return cachedKey;
}

/// Formularfelder für die Client-Authentifizierung; null, wenn nichts eingerichtet ist.
export async function clientAuthentication(clientId: string): Promise<Record<string, string> | null> {
  const keyPem = Deno.env.get("MS_CERT_PRIVATE_KEY");
  const thumbprint = Deno.env.get("MS_CERT_THUMBPRINT");
  if (!keyPem || !thumbprint) return null;
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "PS256", typ: "JWT", "x5t#S256": thumbprint }));
  const claims = base64url(JSON.stringify({
    aud: TOKEN_URL, iss: clientId, sub: clientId, jti: crypto.randomUUID(), nbf: now, iat: now, exp: now + 300,
  }));
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "RSA-PSS", saltLength: 32 }, await signingKey(keyPem), new TextEncoder().encode(`${header}.${claims}`),
  ));
  return {
    client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    client_assertion: `${header}.${claims}.${base64url(signature)}`,
  };
}
