// review-sign-in: Anmeldung für Apples App-Prüfung (Prüfer können keinen E-Mail-Code empfangen).
//
// Nur für genau eine Adresse (Secret REVIEW_EMAIL) mit einem festen, 10-stelligen Prüf-Code
// (Secret REVIEW_CODE). Stimmt beides, erzeugt die Function über die Admin-API einen gültigen
// Einmal-Code (generateLink → email_otp), mit dem sich die App normal per verifyOTP anmeldet.
// Ohne die Secrets ist die Function wirkungslos (404). Für alle anderen Adressen ändert sich nichts.
// verify_jwt = false (vor der Anmeldung gibt es kein Nutzer-JWT).
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/// Vergleich ohne frühen Abbruch (keine Rückschlüsse über die Antwortzeit).
function sameText(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const reviewEmail = Deno.env.get("REVIEW_EMAIL")?.trim().toLowerCase();
  const reviewCode = Deno.env.get("REVIEW_CODE")?.trim();
  if (!reviewEmail || !reviewCode || reviewCode.length < 10) return json({ error: "not_found" }, 404);

  const body = await req.json().catch(() => ({}));
  const email = String(body?.email ?? "").trim().toLowerCase();
  const code = String(body?.code ?? "").trim();
  if (email !== reviewEmail || !sameText(code, reviewCode)) return json({ error: "invalid" }, 401);

  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  if (!key || !url) return json({ error: "misconfigured" }, 500);
  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  // Prüf-Konto anlegen, falls es noch nicht existiert (Fehler „existiert bereits“ ist erwartet).
  await admin.auth.admin.createUser({ email, email_confirm: true, user_metadata: { full_name: "App Review" } });

  const { data, error } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  const otp = data?.properties?.email_otp;
  if (error || !otp) return json({ error: "generate_failed" }, 500);
  return json({ email_otp: otp });
});
