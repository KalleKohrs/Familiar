// push-dispatch: fällige Mitteilungen und Live-Activity-Pushes an APNs senden (Phase 7, Migration 0012).
//
// Aufruf nur per pg_cron (private.start_push_dispatch, jede Minute, nur wenn etwas wartet) mit
// Einmal-Token im Header „x-familiar-cron-token“ (verify_jwt = false).
//   1. push_claim_jobs: bis zu 200 fällige Aufträge übernehmen – samt Inhalt, Geräten und Activities.
//   2. Je Auftrag an APNs senden (HTTP/2, Token-Auth mit ES256-JWT).
//   3. push_report_results: gesendet / fehlgeschlagen (wird bis zu 3× wiederholt) / übersprungen;
//      410 bzw. BadDeviceToken → Gerät ungültig; abgelaufene Activity-Tokens → Activity beendet.
// Ohne APNs-Schlüssel (Secrets APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC) werden Aufträge
// übersprungen und nur eine Verbindungsprobe gegen die APNs-Sandbox gemacht (Spike S2).
//
// Quellen: Apple „Sending notification requests to APNs“, „Establishing a token-based connection
// to APNs“, „Handling notification responses from APNs“, „Starting and updating Live Activities
// with ActivityKit push notifications“.
import { createClient } from "npm:@supabase/supabase-js@2";

type Device = { id: string; token: string; environment: "sandbox" | "production"; push_to_start_token: string | null };
type Activity = { id: string; update_token: string; environment: "sandbox" | "production" };
type Job = {
  id: number;
  kind: string;
  task_id: string | null;
  actor_name: string | null;
  title: string | null;
  family_name: string | null;
  family_color: string | null;
  starts_at_unix: number | null;
  completion_mode: string | null;
  is_open: boolean;
  is_member: boolean;
  can_complete: boolean;
  assignees: { initials: string; isDone: boolean }[];
  devices: Device[];
  activities: Activity[];
};
type Result = {
  id: number;
  status: "sent" | "failed" | "skipped";
  error?: string;
  invalid_device_ids?: string[];
  ended_activity_ids?: string[];
};
type Send = { status: number; reason?: string };

const HOSTS = { sandbox: "https://api.sandbox.push.apple.com", production: "https://api.push.apple.com" };
const ATTRIBUTES_TYPE = "TaskActivityAttributes";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// --- Token-Auth (ES256) -----------------------------------------------------

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let s = "";
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importKey(p8: string): Promise<CryptoKey> {
  const body = p8.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

// Apple: Token höchstens alle 20 Minuten erneuern, nach 60 Minuten ungültig.
let cachedJWT: { token: string; issuedAt: number } | null = null;

async function providerToken(keyP8: string, keyID: string, teamID: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.issuedAt < 40 * 60) return cachedJWT.token;
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64url(JSON.stringify({ iss: teamID, iat: now }));
  const key = await importKey(keyP8);
  // WebCrypto liefert die Signatur bereits im JWS-Format (r||s, je 32 Byte).
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  cachedJWT = { token: `${header}.${claims}.${base64url(signature)}`, issuedAt: now };
  return cachedJWT.token;
}

// --- Senden -------------------------------------------------------------------

async function send(
  jwt: string,
  environment: "sandbox" | "production",
  deviceToken: string,
  headers: Record<string, string>,
  payload: unknown,
): Promise<Send> {
  try {
    const response = await fetch(`${HOSTS[environment]}/3/device/${deviceToken}`, {
      method: "POST",
      headers: { authorization: `bearer ${jwt}`, "content-type": "application/json", ...headers },
      body: JSON.stringify(payload),
    });
    if (response.status === 200) {
      await response.body?.cancel();
      return { status: 200 };
    }
    const body = await response.json().catch(() => ({}));
    return { status: response.status, reason: body.reason ?? `HTTP ${response.status}` };
  } catch (error) {
    return { status: 0, reason: `network: ${error instanceof Error ? error.message : String(error)}` };
  }
}

/// Token gehört nicht (mehr) zu einer App-Installation → nicht erneut verwenden.
function isDeadToken(result: Send): boolean {
  return result.status === 410 ||
    (result.status === 400 && (result.reason === "BadDeviceToken" || result.reason === "DeviceTokenNotForTopic"));
}

/// Nur Fehler, bei denen ein späterer Versuch helfen kann.
function isRetryable(result: Send): boolean {
  return result.status === 0 || result.status === 429 || result.status >= 500 ||
    (result.status === 403 && result.reason === "ExpiredProviderToken");
}

// --- Texte (Deutsch) ---------------------------------------------------------

function quoted(title: string | null): string {
  return `„${title ?? "Aufgabe"}“`;
}

function alertFor(job: Job): { title: string; body: string } | null {
  const who = job.actor_name ?? "Jemand";
  const family = job.family_name ?? "";
  switch (job.kind) {
    case "assigned":
      return { title: job.title ?? "Neue Aufgabe", body: `${who} hat dir eine Aufgabe zugewiesen · ${family}` };
    case "started":
      return { title: job.title ?? "Aufgabe", body: `Jetzt fällig · ${family}` };
    case "reminder":
      return { title: job.title ?? "Aufgabe", body: `Noch offen · ${family}` };
    case "completed":
      return { title: job.title ?? "Aufgabe", body: `${who} hat ${quoted(job.title)} erledigt` };
    case "changed":
      return { title: job.title ?? "Aufgabe", body: `${who} hat ${quoted(job.title)} geändert` };
    case "deleted":
      return { title: job.title ?? "Aufgabe", body: `${who} hat ${quoted(job.title)} gelöscht` };
    case "nudge":
      return { title: job.title ?? "Aufgabe", body: `${who} erinnert dich daran · ${family}` };
    default:
      return null;
  }
}

function contentState(job: Job) {
  return {
    title: job.title ?? "",
    startsAtUnix: job.starts_at_unix,
    completionMode: job.completion_mode ?? "any_one",
    assignees: job.assignees,
    canComplete: job.can_complete,
  };
}

function activityTiming(job: Job) {
  // Ab einer Stunde nach Start gilt die Activity als überfällig (Plan Abschnitt 5).
  return job.starts_at_unix != null ? { "stale-date": Math.floor(job.starts_at_unix + 3600) } : {};
}

// --- Aufträge -----------------------------------------------------------------

async function handle(job: Job, jwt: string, topic: string, startedActivity: Set<string>): Promise<Result> {
  const now = Math.floor(Date.now() / 1000);
  const invalid: string[] = [];
  const ended: string[] = [];
  const failures: Send[] = [];
  let delivered = 0;

  const record = (r: Send, onDead: () => void) => {
    if (r.status === 200) delivered++;
    else if (isDeadToken(r)) onDead();
    else failures.push(r);
  };

  // Wer die Familie verlassen hat, bekommt keine Inhalte mehr – nur das Ende einer Live Activity.
  // (is_member fehlt nur bei älteren Datenbankständen; dann wie bisher senden.)
  if (job.is_member === false && job.kind !== "activity_end") {
    return { id: job.id, status: "skipped", error: "not_member" };
  }

  // Erinnerungen und Anstupsen nur, solange die Person noch offen ist.
  const timely = ["started", "reminder", "activity_start", "nudge"].includes(job.kind);
  if (timely && !job.is_open) return { id: job.id, status: "skipped", error: "task_closed" };

  if (job.kind === "activity_start") {
    if (job.activities.length > 0) return { id: job.id, status: "skipped", error: "already_running" };
    const minutes = job.starts_at_unix != null ? Math.round((job.starts_at_unix - now) / 60) : 0;
    const payload = {
      aps: {
        timestamp: now,
        event: "start",
        "content-state": contentState(job),
        "attributes-type": ATTRIBUTES_TYPE,
        attributes: { taskID: job.task_id, familyColorHex: job.family_color ?? "#FFA43A" },
        // Apple: Push-to-Start braucht einen alert; input-push-token liefert das Update-Token.
        alert: { title: job.title ?? "Aufgabe", body: minutes > 0 ? `Beginnt in ${minutes} Min.` : "Jetzt fällig" },
        "input-push-token": 1,
        ...activityTiming(job),
      },
    };
    for (const device of job.devices) {
      if (!device.push_to_start_token) continue;
      const r = await send(jwt, device.environment, device.push_to_start_token, {
        "apns-push-type": "liveactivity",
        "apns-topic": `${topic}.push-type.liveactivity`,
        "apns-priority": "10",
      }, payload);
      record(r, () => {}); // Push-to-Start-Token erneuert die App beim nächsten Start selbst.
      if (r.status === 200) startedActivity.add(`${job.task_id}:${device.id}`);
    }
  } else if (job.kind === "activity_update" || job.kind === "activity_end") {
    const isEnd = job.kind === "activity_end";
    const payload = {
      aps: {
        timestamp: now,
        event: isEnd ? "end" : "update",
        "content-state": contentState(job),
        ...(isEnd ? { "dismissal-date": now } : activityTiming(job)),
      },
    };
    for (const activity of job.activities) {
      const r = await send(jwt, activity.environment, activity.update_token, {
        "apns-push-type": "liveactivity",
        "apns-topic": `${topic}.push-type.liveactivity`,
        // Ende sofort; Inhaltsänderungen mit niedriger Priorität (zählen nicht gegen das Budget).
        "apns-priority": isEnd ? "10" : "5",
      }, payload);
      record(r, () => ended.push(activity.id));
      if (isEnd && r.status === 200) ended.push(activity.id);
    }
  } else {
    const alert = alertFor(job);
    if (!alert) return { id: job.id, status: "skipped", error: "unknown_kind" };
    for (const device of job.devices) {
      // Bei Nur-Datum kommen Live Activity und „Jetzt“ gleichzeitig: nicht doppelt melden.
      if (job.kind === "started" && startedActivity.has(`${job.task_id}:${device.id}`)) continue;
      const r = await send(jwt, device.environment, device.token, {
        "apns-push-type": "alert",
        "apns-topic": topic,
        "apns-priority": "10",
        // Gleiche Aufgabe: neue Mitteilung ersetzt die alte in der Mitteilungszentrale.
        ...(job.task_id ? { "apns-collapse-id": job.task_id } : {}),
        "apns-expiration": String(now + 24 * 3600),
      }, {
        aps: { alert, sound: "default", "thread-id": job.task_id ?? "familiar" },
        task_id: job.task_id,
        kind: job.kind,
      });
      record(r, () => invalid.push(device.id));
    }
  }

  const base = { id: job.id, invalid_device_ids: invalid, ended_activity_ids: ended };
  if (failures.some(isRetryable) && delivered === 0) {
    return { ...base, status: "failed", error: failures.map((f) => f.reason).join(", ") };
  }
  if (delivered === 0) {
    return { ...base, status: "skipped", error: failures.length ? failures.map((f) => f.reason).join(", ") : "no_targets" };
  }
  return { ...base, status: "sent", error: failures.length ? failures.map((f) => f.reason).join(", ") : undefined };
}

// --- Einstieg -----------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const token = req.headers.get("x-familiar-cron-token");
  if (!token) return json({ error: "unauthorized" }, 401);

  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  if (!key || !url) return json({ error: "misconfigured" }, 500);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await admin.rpc("push_claim_jobs", { p_token: token });
  if (error) return json({ error: "unauthorized" }, 401);
  const jobs = (data ?? []) as Job[];

  const keyP8 = Deno.env.get("APNS_KEY_P8");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const topic = Deno.env.get("APNS_TOPIC");

  if (!keyP8 || !keyID || !teamID || !topic) {
    // Spike S2: Erreicht die Edge-Runtime APNs über HTTP/2? Ohne Schlüssel antwortet APNs mit
    // 403 und JSON-Grund (z. B. MissingProviderToken) – das beweist die Verbindung.
    const probe = await fetch(`${HOSTS.sandbox}/3/device/${"0".repeat(64)}`, {
      method: "POST",
      headers: { "apns-topic": "probe.familiar", "apns-push-type": "alert", "content-type": "application/json" },
      body: JSON.stringify({ aps: { alert: "probe" } }),
    }).then(async (r) => ({ status: r.status, body: await r.text() }))
      .catch((e) => ({ status: 0, body: e instanceof Error ? e.message : String(e) }));
    console.log("apns probe", JSON.stringify(probe));
    const results: Result[] = jobs.map((j) => ({ id: j.id, status: "skipped", error: "apns_not_configured" }));
    await admin.rpc("push_report_results", { p_results: results });
    return json({ processed: jobs.length, apns: "not_configured", probe });
  }

  const jwt = await providerToken(keyP8, keyID, teamID);
  const startedActivity = new Set<string>();
  const results: Result[] = [];
  // Activity-Starts zuerst, damit gleichzeitige „Jetzt“-Mitteilungen erkannt werden.
  const ordered = [...jobs].sort((a, b) => Number(b.kind === "activity_start") - Number(a.kind === "activity_start"));
  for (const job of ordered) {
    results.push(await handle(job, jwt, topic, startedActivity));
  }
  const { error: reportError } = await admin.rpc("push_report_results", { p_results: results });
  if (reportError) console.error("push_report_results", reportError.message);
  return json({
    processed: jobs.length,
    sent: results.filter((r) => r.status === "sent").length,
    failed: results.filter((r) => r.status === "failed").length,
  });
});
