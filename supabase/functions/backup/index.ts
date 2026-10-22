// backup: nächtliche verschlüsselte Datensicherung nach Backblaze B2 (Migration 0017, ADR 0009).
//
// Aufruf nur durch pg_cron (private.start_backup / check_backup) mit Einmal-Token im Header
// „x-familiar-cron-token“; eingelöst über die RPC backup_begin (nur service_role).
// Modi (Body „mode“):
//   run       – Etappe 0: Datenbank (backup_export) packen, verschlüsseln, als db/JJJJ-MM-TT.fam
//               hochladen; danach Bilder inkrementell. Reicht die Zeit nicht, startet
//               backup_finish die nächste Etappe (höchstens MAX_CHAIN).
//   alert     – Wächter: seit 30 Stunden keine erfolgreiche Sicherung → Warn-E-Mail.
//   selftest  – Verschlüsselung mit Wegwerf-Schlüssel hin und zurück, B2-Anmeldung prüfen.
// Secrets: B2_KEY_ID, B2_APPLICATION_KEY (Write Only, ein Bucket), BACKUP_PUBLIC_KEY (SPKI-PEM),
// RESEND_API_KEY (Warn-E-Mails), optional BACKUP_ALERT_TO.
import { createClient } from "npm:@supabase/supabase-js@2";
import * as b2 from "./b2.ts";
import { gunzip, gzip, importPublicKey, open, seal } from "./fam.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

const BUDGET_MS = 100_000;
const MAX_CHAIN = 20;
const PLAN_BATCH = 25;
const DB_WARN_BYTES = 25 * 1024 * 1024;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sendAlert(subject: string, text: string): Promise<void> {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) {
    console.error(`Warn-E-Mail nicht möglich (RESEND_API_KEY fehlt): ${subject}`);
    return;
  }
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: "Familiar <familiar@mail.familiar-app.de>",
      to: [Deno.env.get("BACKUP_ALERT_TO") ?? "info@familiar-app.de"],
      subject,
      text,
    }),
  });
  if (!response.ok) console.error(`Resend: ${response.status} ${await response.text()}`);
}

function b2Login(): Promise<b2.B2> {
  // Beim Einfügen ins Dashboard rutschen leicht Leerzeichen oder Zeilenumbrüche mit.
  const keyId = Deno.env.get("B2_KEY_ID")?.trim();
  const appKey = Deno.env.get("B2_APPLICATION_KEY")?.trim();
  if (!keyId || !appKey) throw new Error("B2_KEY_ID oder B2_APPLICATION_KEY fehlt.");
  return b2.authorize(keyId, appKey);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = req.headers.get("x-familiar-cron-token");
  if (!token) return json({ error: "unauthorized" }, 401);

  // Neuer Secret-Key (Standard), sonst der Legacy-Service-Role-Key.
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  if (!key || !url) return json({ error: "misconfigured" }, 500);

  const body = await req.json().catch(() => ({}));
  const mode: string = body.mode ?? "run";
  const chain: number = Number(body.chain ?? 0);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: begin, error } = await admin.rpc("backup_begin", {
    p_token: token,
    p_mode: mode,
    p_run_id: body.run_id ?? null,
  });
  if (error) return json({ error: "unauthorized" }, 401);

  if (mode === "alert") {
    await sendAlert(
      "Familiar: Datensicherung fehlt",
      `Seit über 30 Stunden gab es keine erfolgreiche Datensicherung.\n` +
        `Letzte erfolgreiche Sicherung: ${begin.last_ok ?? "noch nie"}.\n` +
        `Projekt: ${url}\nDetails stehen in private.backup_runs.`,
    );
    return json({ alerted: true });
  }

  if (mode === "selftest") {
    return json(await selftest().catch((e) => ({ error: e instanceof Error ? e.stack ?? e.message : String(e) })));
  }

  if (mode !== "run") return json({ error: "unknown_mode" }, 400);

  const runId: number = begin.run_id;
  // Die Arbeit läuft im Hintergrund weiter; pg_net wartet nur 30 Sekunden auf die Antwort.
  EdgeRuntime.waitUntil(run(admin, url, key, runId, chain));
  return json({ accepted: true, run_id: runId, chain }, 202);
});

async function run(
  admin: ReturnType<typeof createClient>,
  url: string,
  key: string,
  runId: number,
  chain: number,
): Promise<void> {
  const started = Date.now();
  const stats: Record<string, number | string> = { images_uploaded: 0, images_hidden: 0 };
  try {
    const pem = Deno.env.get("BACKUP_PUBLIC_KEY");
    if (!pem) throw new Error("BACKUP_PUBLIC_KEY fehlt.");
    const publicKey = await importPublicKey(pem);
    const bucket = await b2Login();

    // Etappe 0: Datenbank. Der Text wird nicht geparst, sondern direkt gepackt (CPU-Grenze 2 s).
    if (chain === 0) {
      const response = await fetch(`${url}/rest/v1/rpc/backup_export`, {
        method: "POST",
        headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: "{}",
      });
      if (!response.ok) throw new Error(`backup_export: ${response.status} ${await response.text()}`);
      const raw = new Uint8Array(await response.arrayBuffer());
      const sealed = await seal(await gzip(raw), publicKey);
      const name = `db/${new Date().toISOString().slice(0, 10)}.fam`;
      await b2.upload(bucket, name, sealed);
      stats.db_file = name;
      stats.db_bytes = sealed.length;
      stats.db_raw_bytes = raw.length;
      if (raw.length > DB_WARN_BYTES) {
        await sendAlert(
          "Familiar: Datensicherung wird groß",
          `Die Datenbank-Sicherung umfasst ${(raw.length / 1048576).toFixed(1)} MB. ` +
            `Ab etwa 50 MB reicht der Speicher der Edge Function nicht mehr – Umstellung auf ` +
            `tabellenweise Teildateien einplanen (ADR 0009, Grenzen).`,
        );
      }
    }

    // Bilder: neue und geänderte hochladen, solange Zeit bleibt.
    let pending = 0;
    let removed: { bucket: string; name: string }[] = [];
    let guard: { source_total: number; backed_total: number; families: number } | null = null;
    while (true) {
      const { data: plan, error } = await admin.rpc("backup_image_plan", { p_limit: PLAN_BATCH });
      if (error) throw new Error(`backup_image_plan: ${error.message}`);
      removed = plan.removed;
      guard = plan;
      pending = plan.changed_total;
      if (plan.changed.length === 0 || Date.now() - started > BUDGET_MS) break;

      for (const item of plan.changed as { bucket: string; name: string; etag: string }[]) {
        if (Date.now() - started > BUDGET_MS) break;
        const { data: blob, error: downloadError } = await admin.storage.from(item.bucket).download(item.name);
        // Zwischen Plan und Download gelöscht: Die nächste Planung führt die Datei als verschwunden.
        if (downloadError && /not.?found/i.test(downloadError.message)) {
          pending--;
          continue;
        }
        if (downloadError || !blob) {
          throw new Error(`Bild ${item.bucket}/${item.name}: ${downloadError?.message ?? "leer"}`);
        }
        const sealed = await seal(new Uint8Array(await blob.arrayBuffer()), publicKey);
        await b2.upload(bucket, `images/${item.bucket}/${item.name}.fam`, sealed);
        const { error: savedError } = await admin.rpc("backup_image_saved", {
          p_bucket: item.bucket,
          p_name: item.name,
          p_etag: item.etag,
        });
        if (savedError) throw new Error(`backup_image_saved: ${savedError.message}`);
        stats.images_uploaded = Number(stats.images_uploaded) + 1;
        pending--;
      }
    }

    // Verschwundene Bilder verbergen – außer bei einer verdächtigen Löschwelle.
    if (removed.length > 0 && guard) {
      const wave = guard.families === 0 ||
        (guard.backed_total >= 10 && removed.length * 2 > guard.backed_total);
      if (wave) {
        throw new Error(
          `Schutz: ${removed.length} von ${guard.backed_total} gesicherten Bildern fehlen in Supabase ` +
            `(Familien: ${guard.families}). Nichts verborgen – bitte prüfen.`,
        );
      }
      for (const item of removed) {
        if (Date.now() - started > BUDGET_MS) break;
        await b2.hide(bucket, `images/${item.bucket}/${item.name}.fam`);
        const { error: hiddenError } = await admin.rpc("backup_image_hidden", {
          p_bucket: item.bucket,
          p_name: item.name,
        });
        if (hiddenError) throw new Error(`backup_image_hidden: ${hiddenError.message}`);
        stats.images_hidden = Number(stats.images_hidden) + 1;
      }
    }

    stats.images_pending = Math.max(pending, 0);
    const more = pending > 0 && chain < MAX_CHAIN;
    // Bleiben nach MAX_CHAIN Etappen Bilder übrig, folgen sie in der nächsten Nacht.
    await finish(admin, runId, more ? "running" : "ok", stats, null, more);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`Datensicherung ${runId} (Etappe ${chain}): ${message}`);
    await finish(admin, runId, "failed", stats, message, false).catch((f) => console.error(f));
    await sendAlert(
      "Familiar: Datensicherung fehlgeschlagen",
      `Die Datensicherung (Lauf ${runId}, Etappe ${chain}) ist fehlgeschlagen:\n\n${message}\n\n` +
        `Projekt: ${url}\nDetails stehen in private.backup_runs.`,
    );
  }
}

async function finish(
  admin: ReturnType<typeof createClient>,
  runId: number,
  status: string,
  stats: Record<string, number | string>,
  message: string | null,
  more: boolean,
): Promise<void> {
  const { error } = await admin.rpc("backup_finish", {
    p_run_id: runId,
    p_status: status,
    p_stats: stats,
    p_error: message,
    p_continue: more,
  });
  if (error) throw new Error(`backup_finish: ${error.message}`);
}

// Prüft Format und Verschlüsselung mit einem Wegwerf-Schlüssel (der private Sicherungsschlüssel ist
// hier nie vorhanden) sowie die Secrets und die B2-Anmeldung.
async function selftest(): Promise<Record<string, unknown>> {
  const result: Record<string, unknown> = {};
  const pair = await crypto.subtle.generateKey(
    { name: "RSA-OAEP", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["encrypt", "decrypt"],
  );
  const sample = crypto.getRandomValues(new Uint8Array(65_536));
  const sealed = await seal(await gzip(sample), pair.publicKey);
  const back = await gunzip(await open(sealed, pair.privateKey));
  result.roundtrip = back.length === sample.length && back.every((b, i) => b === sample[i]);

  const tampered = sealed.slice();
  tampered[tampered.length - 1] ^= 1;
  result.tamper_detected = await open(tampered, pair.privateKey).then(() => false, () => true);

  const pem = Deno.env.get("BACKUP_PUBLIC_KEY");
  result.public_key = pem ? await importPublicKey(pem).then(() => "ok", (e) => `ungültig: ${e.message}`) : "fehlt";
  result.resend_key = Deno.env.get("RESEND_API_KEY") ? "vorhanden" : "fehlt";
  // Nur Längen, nie die Werte (üblich: keyID 25, applicationKey 31 Zeichen).
  result.b2_lengths = {
    key_id: Deno.env.get("B2_KEY_ID")?.trim().length ?? 0,
    application_key: Deno.env.get("B2_APPLICATION_KEY")?.trim().length ?? 0,
  };
  try {
    const login = await b2Login();
    result.b2 = { bucket: login.bucketName, capabilities: login.capabilities };
  } catch (e) {
    result.b2 = e instanceof Error ? e.message : String(e);
  }
  return result;
}
