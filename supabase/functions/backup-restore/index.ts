// backup-restore: Wiederherstellung aus der Datensicherung (Migration 0017, ADR 0009).
//
// Start nur von Hand im SQL-Editor über private.start_restore(mode, datum, …) mit Einmal-Token im
// Header „x-familiar-cron-token“. Ergebnis und Bericht stehen in private.restore_runs.
// Modi:
//   probe    – Datenbank vollständig wiederherstellen, zählen, dann ROLLBACK (nichts ändert sich);
//              Stichprobe von bis zu drei Bildern: entschlüsseln und mit dem Original vergleichen.
//   restore  – Datenbank wiederherstellen (nicht leeres Projekt nur mit confirm „ÜBERSCHREIBEN“),
//              danach startet der Modus images.
//   images   – alle Bilder aus B2 in die Buckets zurückschreiben, in Etappen (cursor).
// Secrets (nur für die Dauer der Wiederherstellung): BACKUP_PRIVATE_KEY (PKCS#8-PEM),
// B2_READ_KEY_ID, B2_READ_APPLICATION_KEY (Read Only, ein Bucket).
// Die Datenbank-Arbeit läuft über eine direkte Verbindung (SUPABASE_DB_URL, Rolle postgres) in einer
// Transaktion mit session_replication_role = replica: Fremdschlüssel-Reihenfolge und Trigger spielen
// beim Einfügen keine Rolle (wie bei pg_dump-Wiederherstellungen laut Supabase-Doku).
import { createClient } from "npm:@supabase/supabase-js@2";
import postgres from "npm:postgres@3.4.5";
import * as b2 from "./b2.ts";
import { gunzip, importPrivateKey, open } from "./fam.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

const BUDGET_MS = 100_000;
const IMAGE_PAGE = 200;

type Sql = ReturnType<typeof postgres>;
type Report = Record<string, unknown>;

class ProbeRollback extends Error {
  constructor(readonly report: Report) {
    super("probe");
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = req.headers.get("x-familiar-cron-token");
  const dbUrl = Deno.env.get("SUPABASE_DB_URL");
  if (!token) return json({ error: "unauthorized" }, 401);
  if (!dbUrl) return json({ error: "misconfigured" }, 500);

  const body = await req.json().catch(() => ({}));
  const sql = postgres(dbUrl, { prepare: false, max: 1 });

  const redeemed = await sql`
    update private.cron_tokens t
       set used_at = now()
     where t.token_hash = encode(sha256(convert_to(${token}, 'UTF8')), 'hex')
       and t.purpose = 'restore'
       and t.used_at is null
       and t.created_at > now() - interval '15 minutes'
    returning t.token_hash`;
  if (redeemed.length === 0) {
    await sql.end();
    return json({ error: "unauthorized" }, 401);
  }

  EdgeRuntime.waitUntil(work(sql, body).finally(() => sql.end()));
  return json({ accepted: true, run_id: body.run_id }, 202);
});

async function work(
  sql: Sql,
  body: { mode: string; date: string; confirm?: string; cursor?: string; run_id: number },
): Promise<void> {
  const started = Date.now();
  const runId = body.run_id;
  try {
    const pem = Deno.env.get("BACKUP_PRIVATE_KEY");
    // Beim Einfügen ins Dashboard rutschen leicht Leerzeichen oder Zeilenumbrüche mit.
    const keyId = Deno.env.get("B2_READ_KEY_ID")?.trim();
    const appKey = Deno.env.get("B2_READ_APPLICATION_KEY")?.trim();
    if (!pem || !keyId || !appKey) {
      throw new Error("BACKUP_PRIVATE_KEY, B2_READ_KEY_ID oder B2_READ_APPLICATION_KEY fehlt.");
    }
    const privateKey = await importPrivateKey(pem);
    const bucket = await b2.authorize(keyId, appKey);

    if (body.mode === "images") {
      const result = await restoreImages(bucket, privateKey, body.cursor ?? null, started);
      await merge(sql, runId, { images_restored: result.restored }, result.next ? "running" : "ok");
      if (result.next) {
        await sql`select private.start_restore('images', ${body.date}::date, null, ${result.next}, ${runId})`;
      }
      return;
    }

    const file = await b2.download(bucket, `db/${body.date}.fam`);
    const doc = new TextDecoder().decode(await gunzip(await open(file, privateKey)));

    if (body.mode === "probe") {
      let report: Report = {};
      try {
        await restoreDatabase(sql, doc, true, null);
      } catch (e) {
        if (!(e instanceof ProbeRollback)) throw e;
        report = e.report;
      }
      report.images = await probeImages(bucket, privateKey);
      await merge(sql, runId, report, "ok");
      return;
    }

    if (body.mode === "restore") {
      const report = await restoreDatabase(sql, doc, false, body.confirm ?? null);
      await merge(sql, runId, report, "running");
      await sql`select private.start_restore('images', ${body.date}::date, null, null, ${runId})`;
      return;
    }

    throw new Error(`Unbekannter Modus ${body.mode}`);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`Wiederherstellung ${runId}: ${message}`);
    await merge(sql, runId, { error: message }, "failed").catch((f) => console.error(f));
  }
}

async function merge(sql: Sql, runId: number, report: Report, status: string): Promise<void> {
  await sql`
    update private.restore_runs r
       set report = r.report || ${sql.json(report)}::jsonb,
           status = ${status},
           finished_at = case when ${status} = 'running' then null else now() end
     where r.id = ${runId}`;
}

// Stellt alle Tabellen der Sicherung in einer Transaktion wieder her. probe = true: am Ende
// ROLLBACK über ProbeRollback (mit Bericht).
async function restoreDatabase(sql: Sql, doc: string, probe: boolean, confirm: string | null): Promise<Report> {
  return await sql.begin(async (tx) => {
    const report: Report = { tables: {}, skipped: [] as string[], mismatches: [] as string[] };

    const [state] = await tx`
      select (select count(*) from public.families)::int as families,
             (select count(*) from auth.users)::int as users`;
    const empty = state.families === 0 && state.users === 0;
    report.target_was_empty = empty;
    if (!empty && !probe && confirm !== "ÜBERSCHREIBEN") {
      throw new Error(
        `Projekt ist nicht leer (${state.families} Familien, ${state.users} Konten). ` +
          `Überschreiben nur mit confirm = 'ÜBERSCHREIBEN'.`,
      );
    }

    // Bisherige Zeilenzahlen (für die Probe: Vergleich mit dem Live-Stand).
    const before: Record<string, number> = {};

    await tx`create temp table _restore (doc jsonb) on commit drop`;
    await tx`insert into _restore values (${doc}::jsonb)`;
    const keys = await tx`
      select k, to_regclass(format('%I.%I', split_part(k, '.', 1), split_part(k, '.', 2)))::text as reg
        from _restore, jsonb_object_keys(doc -> 'tables') k
       where k not like 'supabase_migrations.%'
       order by k`;

    for (const { k, reg } of keys) {
      if (reg) {
        const [{ n }] = await tx.unsafe(`select count(*)::int as n from ${reg}`);
        before[k] = n;
      }
    }

    if (!empty) {
      // Konten zuerst (normale Trigger und Cascades, z. B. Vault-Geheimnisse der Outlook-Verbindung),
      // dann alle Tabellen in public.
      await tx`delete from auth.users`;
      const tables = await tx`select format('%I.%I', schemaname, tablename) as t from pg_tables where schemaname = 'public'`;
      if (tables.length > 0) await tx.unsafe(`truncate ${tables.map((r) => r.t).join(", ")} cascade`);
    }

    await tx`select set_config('session_replication_role', 'replica', true)`;

    const counts: Record<string, { backup: number; restored: number; before?: number }> = {};
    for (const { k, reg } of keys) {
      if (!reg) {
        (report.skipped as string[]).push(k);
        continue;
      }
      // Nur Spalten, die es im Ziel gibt, die einfügbar sind und die in der Sicherung vorkommen;
      // neuere Spalten bekommen so ihren Standardwert.
      const columns = await tx`
        select quote_ident(a.attname) as c
          from pg_attribute a
         where a.attrelid = ${reg}::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
           and (select (doc -> 'tables' -> ${k} -> 0) ? a.attname from _restore)
         order by a.attnum`;
      const [{ n: expected }] = await tx`select jsonb_array_length(doc -> 'tables' -> ${k})::int as n from _restore`;
      let restored = 0;
      if (expected > 0) {
        const list = columns.map((c) => c.c).join(", ");
        const result = await tx.unsafe(
          `insert into ${reg} (${list}) overriding system value
           select ${list} from jsonb_populate_recordset(null::${reg}, (select doc -> 'tables' -> $1 from _restore))`,
          [k],
        );
        restored = result.count;
      }
      counts[k] = { backup: expected, restored, before: before[k] };
      if (restored !== expected) (report.mismatches as string[]).push(k);
    }
    report.tables = counts;

    // Sequenzen hinter die höchsten wiederhergestellten Werte setzen.
    const sequences = await tx`
      select pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) as seq,
             format('%I.%I', n.nspname, c.relname) as reg, quote_ident(a.attname) as col
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
       where n.nspname = 'public' and c.relkind = 'r'
         and pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) is not null`;
    for (const s of sequences) {
      await tx.unsafe(`select setval($1, coalesce((select max(${s.col}) from ${s.reg}), 0) + 1, false)`, [s.seq]);
    }

    await tx`select set_config('session_replication_role', 'origin', true)`;

    if (probe) throw new ProbeRollback(report);
    return report;
  });
}

function imagePath(name: string): { bucket: string; path: string } {
  const match = name.match(/^images\/([^/]+)\/(.+)\.fam$/);
  if (!match) throw new Error(`Unerwarteter Dateiname ${name}`);
  return { bucket: match[1], path: match[2] };
}

function storageAdmin() {
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  if (!key || !url) throw new Error("SUPABASE_URL oder Secret-Key fehlt.");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function restoreImages(
  bucket: b2.B2,
  privateKey: CryptoKey,
  cursor: string | null,
  started: number,
): Promise<{ restored: number; next: string | null }> {
  const admin = storageAdmin();
  const page = await b2.listNames(bucket, "images/", cursor, IMAGE_PAGE);
  let restored = 0;
  for (const name of page.names) {
    if (Date.now() - started > BUDGET_MS) return { restored, next: name };
    const { bucket: target, path } = imagePath(name);
    const data = await open(await b2.download(bucket, name), privateKey);
    const { error } = await admin.storage.from(target).upload(path, data, { upsert: true, contentType: "image/jpeg" });
    if (error) throw new Error(`Bild ${target}/${path}: ${error.message}`);
    restored++;
  }
  return { restored, next: page.next };
}

async function probeImages(bucket: b2.B2, privateKey: CryptoKey): Promise<Report> {
  const admin = storageAdmin();
  const page = await b2.listNames(bucket, "images/", null, 3);
  const checked: Report[] = [];
  for (const name of page.names) {
    const { bucket: target, path } = imagePath(name);
    const restored = await open(await b2.download(bucket, name), privateKey);
    const { data: blob, error } = await admin.storage.from(target).download(path);
    const original = blob ? new Uint8Array(await blob.arrayBuffer()) : null;
    const equal = !!original && original.length === restored.length && original.every((b, i) => b === restored[i]);
    checked.push({ bucket: target, equal, error: error?.message ?? null });
  }
  return { checked: checked.length, equal: checked.filter((c) => c.equal).length, details: checked };
}
