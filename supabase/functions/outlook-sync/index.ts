// outlook-sync: Outlook-Termine abgleichen (Phase 8, Migration 0011).
//
// Aufruf nur per pg_cron / RPC (private.start_outlook_sync) mit Einmal-Token im Header
// „x-familiar-cron-token“ (verify_jwt = false). Für jede aktive Verbindung:
//   1. Access-Token per Refresh-Token holen und das neue Refresh-Token sofort speichern
//      (Microsoft: altes verwerfen).
//   2. Für jeden ausgewählten Kalender calendarView über −7 … +120 Tage (mit Paging) laden.
//   3. Termine im Fenster ersetzen (outlook_apply_events) – so werden Änderungen, Absagen und
//      Löschungen erfasst.
// Abgelehnte Refresh-Tokens (invalid_grant / interaction_required) → Status needs_reauth.
// Es wird nie nach Outlook geschrieben.
import { createClient } from "npm:@supabase/supabase-js@2";

const SCOPES = "openid email offline_access https://graph.microsoft.com/Calendars.ReadBasic";
const DAY = 24 * 60 * 60 * 1000;
const SELECT = "id,subject,start,end,isAllDay,location,organizer,isCancelled";

type Job = { connection_id: string; refresh_token: string; calendars: { id: string; provider_calendar_id: string }[] };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/// Graph liefert mit `Prefer: outlook.timezone="UTC"` Zeiten ohne Offset, z. B. 2026-10-21T08:00:00.0000000.
function utc(dateTime: string): string {
  return dateTime.replace(/\.\d+$/, "") + "Z";
}

function mapEvent(e: Record<string, any>) {
  const isAllDay = e.isAllDay === true;
  const startDate = isAllDay ? String(e.start?.dateTime ?? "").slice(0, 10) : null;
  const endDate = isAllDay ? String(e.end?.dateTime ?? "").slice(0, 10) : null;
  return {
    id: e.id,
    title: e.subject ?? "",
    starts_at: isAllDay ? `${startDate}T00:00:00Z` : utc(e.start.dateTime),
    ends_at: isAllDay ? `${endDate}T00:00:00Z` : utc(e.end.dateTime),
    is_all_day: isAllDay,
    start_date: startDate,
    end_date: endDate,
    location: e.location?.displayName ?? null,
    organizer_name: e.organizer?.emailAddress?.name ?? null,
    organizer_email: e.organizer?.emailAddress?.address ?? null,
    is_cancelled: e.isCancelled === true,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const token = req.headers.get("x-familiar-cron-token");
  if (!token) return json({ error: "unauthorized" }, 401);

  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const key = secretKeys["default"] ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  const clientId = Deno.env.get("MS_CLIENT_ID");
  const clientSecret = Deno.env.get("MS_CLIENT_SECRET");
  if (!key || !url || !clientId || !clientSecret) return json({ error: "misconfigured" }, 500);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: jobs, error } = await admin.rpc("outlook_sync_jobs", { p_token: token });
  if (error) return json({ error: "unauthorized" }, 401);

  const windowStart = new Date(Date.now() - 7 * DAY);
  const windowEnd = new Date(Date.now() + 120 * DAY);
  const results: Record<string, unknown>[] = [];

  for (const job of (jobs ?? []) as Job[]) {
    // 1. Access-Token erneuern
    const tokenResponse = await fetch("https://login.microsoftonline.com/common/oauth2/v2.0/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: "refresh_token",
        refresh_token: job.refresh_token,
        scope: SCOPES,
      }),
    });
    const tokens = await tokenResponse.json();
    if (!tokenResponse.ok || !tokens.access_token) {
      const reauth = tokens.error === "invalid_grant" || tokens.error === "interaction_required";
      await admin.rpc("outlook_mark_connection", {
        p_connection_id: job.connection_id,
        p_status: reauth ? "needs_reauth" : "active",
        p_error: tokens.error ?? "token_failed",
      });
      results.push({ connection: job.connection_id, error: tokens.error ?? "token_failed" });
      continue;
    }
    if (tokens.refresh_token) {
      await admin.rpc("outlook_store_refresh_token", {
        p_connection_id: job.connection_id,
        p_refresh_token: tokens.refresh_token,
      });
    }

    // 2./3. Kalender abgleichen
    let failure: string | null = null;
    let eventCount = 0;
    for (const calendar of job.calendars) {
      const events: Record<string, unknown>[] = [];
      let next: string | null =
        `https://graph.microsoft.com/v1.0/me/calendars/${encodeURIComponent(calendar.provider_calendar_id)}/calendarView` +
        `?startDateTime=${windowStart.toISOString()}&endDateTime=${windowEnd.toISOString()}` +
        `&$select=${SELECT}&$top=200`;
      while (next) {
        const response = await fetch(next, {
          headers: { Authorization: `Bearer ${tokens.access_token}`, Prefer: 'outlook.timezone="UTC"' },
        });
        if (!response.ok) {
          failure = `graph_${response.status}`;
          break;
        }
        const body = await response.json();
        for (const e of body.value ?? []) events.push(mapEvent(e));
        next = body["@odata.nextLink"] ?? null;
      }
      if (failure) break;
      await admin.rpc("outlook_apply_events", {
        p_calendar_id: calendar.id,
        p_window_start: windowStart.toISOString(),
        p_window_end: windowEnd.toISOString(),
        p_events: events,
      });
      eventCount += events.length;
    }

    await admin.rpc("outlook_mark_connection", {
      p_connection_id: job.connection_id,
      p_status: "active",
      p_error: failure,
    });
    results.push({ connection: job.connection_id, events: eventCount, error: failure });
  }

  return json({ connections: results.length, results });
});
