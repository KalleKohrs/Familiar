// purge-history: 30-Tage-Bereinigung des Verlaufs (Migration 0008).
//
// Aufruf nur durch pg_cron (private.start_history_purge) mit Einmal-Token im Header
// „x-familiar-cron-token“. Das Token wird über die RPC purge_expired_history eingelöst
// (nur service_role); ungültige Aufrufe enden dort mit einem Fehler.
// Die RPC liefert die Pfade verwaister Dateien, die hier über die Storage-API gelöscht werden.
import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET = "task-images";
const BATCH = 500;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data, error } = await admin.rpc("purge_expired_history", { p_token: token });
  if (error) return json({ error: "unauthorized" }, 401);

  const paths: string[] = data?.file_paths ?? [];
  let removedFiles = 0;
  for (let i = 0; i < paths.length; i += BATCH) {
    const { data: removed, error: storageError } = await admin.storage.from(BUCKET).remove(paths.slice(i, i + BATCH));
    if (storageError) {
      return json({ error: "storage", message: storageError.message, deleted_tasks: data?.deleted_tasks }, 500);
    }
    removedFiles += removed?.length ?? 0;
  }

  return json({
    deleted_tasks: data?.deleted_tasks ?? 0,
    deleted_images: data?.deleted_images ?? 0,
    removed_files: removedFiles,
  });
});
