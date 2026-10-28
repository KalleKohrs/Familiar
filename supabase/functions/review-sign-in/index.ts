// review-sign-in: Anmeldung für Apples App-Prüfung (Prüfer können keinen E-Mail-Code empfangen).
//
// Nur für genau eine Adresse (Secret REVIEW_EMAIL) mit einem festen, 10-stelligen Prüf-Code
// (Secret REVIEW_CODE). Stimmt beides, erzeugt die Function über die Admin-API einen gültigen
// Einmal-Code (generateLink → email_otp), mit dem sich die App normal per verifyOTP anmeldet.
// Ohne die Secrets ist die Function wirkungslos (404). Für alle anderen Adressen ändert sich nichts.
// Höchstens 10 Fehlversuche pro Stunde (Migration 0018, review_sign_in_begin/_succeeded; atomar,
// auch bei gleichzeitigen Anfragen). Ablehnungen dauern immer gleich lang (keine Rückschlüsse
// über die Antwortzeit, ob eine Adresse die Prüf-Adresse ist).
// verify_jwt = false (vor der Anmeldung gibt es kein Nutzer-JWT).
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/// Ablehnungen frühestens nach dieser Zeit beantworten (deckt die Datenbank-Abfragen ab).
const REJECT_AFTER_MS = 800;

async function reject(started: number, body: unknown, status: number): Promise<Response> {
  const wait = REJECT_AFTER_MS - (Date.now() - started);
  if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
  return json(body, status);
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
  const started = Date.now();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const reviewEmail = Deno.env.get("REVIEW_EMAIL")?.trim().toLowerCase();
  const reviewCode = Deno.env.get("REVIEW_CODE")?.trim();
  if (!reviewEmail || !reviewCode || reviewCode.length < 10) return json({ error: "not_found" }, 404);

  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  if (!key || !url) return json({ error: "misconfigured" }, 500);
  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const body = await req.json().catch(() => ({}));
  const email = String(body?.email ?? "").trim().toLowerCase();
  const code = String(body?.code ?? "").trim();
  // Andere Adressen (Tippfehler normaler Nutzer) zählen nicht als Angriff auf den Prüf-Zugang.
  if (email !== reviewEmail) return reject(started, { error: "invalid" }, 401);

  // Schutz gegen Durchprobieren: Jeder Versuch zählt erst einmal als Fehlversuch; nach 10 pro Stunde
  // ist der Zugang gesperrt (Migration 0018).
  const { data: attemptID, error: limitError } = await admin.rpc("review_sign_in_begin");
  if (limitError) return json({ error: "misconfigured" }, 500);
  if (attemptID == null) return reject(started, { error: "too_many_attempts" }, 429);

  if (!sameText(code, reviewCode)) return reject(started, { error: "invalid" }, 401);
  await admin.rpc("review_sign_in_succeeded", { p_attempt_id: attemptID });

  // Prüf-Konto anlegen, falls es noch nicht existiert (Fehler „existiert bereits“ ist erwartet).
  await admin.auth.admin.createUser({ email, email_confirm: true, user_metadata: { full_name: "App Review" } });

  const { data, error } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  const otp = data?.properties?.email_otp;
  if (error || !otp) return json({ error: "generate_failed" }, 500);
  return json({ email_otp: otp });
});
