// account-delete: Konto endgültig löschen (App-Store-Richtlinie 5.1.1(v), Plan Phase 9).
//
// Aufruf aus der App mit dem Nutzer-JWT (verify_jwt = true). Ablauf:
//   1. Nutzer aus dem JWT bestimmen (auth.getUser) – nie aus dem Request-Body.
//   2. RPC prepare_account_deletion (nur service_role, Migration 0010): Familien ohne weitere
//      Mitglieder löschen, Admin-Rolle weitergeben, Besitz an Aufgabenbildern lösen,
//      Pfade der Profilbilder liefern.
//   3. Profilbilder über die Storage-API löschen (nie per SQL).
//   4. Auth-Nutzer löschen; Profil, Mitgliedschaften und Zuweisungen folgen per Cascade.
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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

  const { data, error } = await admin.rpc("prepare_account_deletion", { p_user_id: userId });
  if (error) return json({ error: "prepare_failed", message: error.message }, 500);

  const avatarPaths: string[] = data?.avatar_paths ?? [];
  if (avatarPaths.length > 0) {
    const { error: storageError } = await admin.storage.from("avatars").remove(avatarPaths);
    if (storageError) return json({ error: "storage", message: storageError.message }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) return json({ error: "delete_failed", message: deleteError.message }, 500);

  return json({ deleted: true });
});
