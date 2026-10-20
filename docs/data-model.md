# Datenmodell (Stand Phase 2 „Auth & Onboarding“)

Dieses Dokument beschreibt die Tabellen, Funktionen und RPCs aus den Migrationen
`supabase/migrations/0001`–`0006`. Rechte und Policies im Detail: [rls-matrix.md](rls-matrix.md).
Aufgaben, Bilder, Serien, Geräte und Kalender kommen ab Phase 3 dazu.

## Migrationsstand (Projekt `ldeouecoaqyfvubhrjei`)

| Migration | Angewendet | Weg |
|---|---|---|
| `0001_extensions_and_schemas` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0002_profiles_families` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0003_rls_helpers_policies` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0004_family_rpcs` | 2026-10-20 | **manuell im Supabase-SQL-Editor** (die MCP-Bestätigung für Statements mit `delete` wurde in der App automatisch abgelehnt). Eintrag in `supabase_migrations.schema_migrations` (Version `20261020182858`) nachträglich ergänzt; Inhalt per SHA-256 gegen die Datei geprüft. |
| `0005_invite_attempts_deny_policy` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0006_avatars_storage` | 2026-10-20 | Supabase-MCP `apply_migration` (Phase 2) |

Hinweis für spätere Migrationen: Enthält eine Migration `delete`/`drop`/`truncate` (auch nur in
Funktionskörpern), fragt der Supabase-MCP nach einer Bestätigung, die in dieser App derzeit nicht ankommt.
Dann die Datei im SQL-Editor ausführen und den Eintrag in `schema_migrations` ergänzen.

## Grundsätze

- **Lesen** über RLS-geschützte `select`s (PostgREST).
- **Schreiben** nur über RPCs (`security definer`, `set search_path = ''`, explizite Prüfungen).
  `insert`/`update`/`delete` sind für `anon` und `authenticated` entzogen.
- **Schema `private`** ist nicht über die Data API erreichbar. Dort liegen RLS-Hilfsfunktionen,
  Trigger-Funktionen, der Fehlerkatalog und interne Tabellen.
- Jede Funktion bekommt ihre Rechte **explizit** (`revoke … from public, anon …` und gezieltes `grant`).
  Grund: Postgres vergibt `EXECUTE` global an `PUBLIC`, Supabase zusätzlich per Default-Privileges an
  `anon`/`authenticated`; ein schema-spezifisches `alter default privileges … revoke` hebt das nicht auf.
- RPC-Parameter haben das Präfix `p_` (z. B. `p_family_id`). Optionale Parameter haben `default null`
  und bedeuten „unverändert“.

## Extensions und Schemas (0001)

| Objekt | Zweck |
|---|---|
| `pg_cron` (Schema `pg_catalog`, eigenes Schema `cron`) | Zeitgesteuerte Jobs ab Phase 3/5 |
| `pg_net` (Schema `extensions`, Funktionen in `net`) | HTTP aus der DB (Cron → Edge Functions) |
| `pgcrypto` (Schema `extensions`, vorinstalliert) | `gen_random_bytes` für Einladungscodes |
| Schema `private` | intern; keine Rechte für `public`, `anon`, `authenticated` |
| Enum `public.family_role` | `'admin'`, `'member'` |
| Enum `public.task_visibility` | `'all'`, `'assigned_only'` |

## Tabellen (0002)

### `public.profiles`

| Spalte | Typ | Regeln |
|---|---|---|
| `id` | uuid PK | → `auth.users(id)` `on delete cascade` |
| `display_name` | text not null | 1–80 Zeichen (getrimmt) |
| `avatar_path` | text null | Pfad im späteren Bucket `avatars`: `{user_id}/{datei}` |
| `created_at`, `updated_at` | timestamptz | `updated_at` per Trigger |

- Trigger `on_auth_user_created` auf `auth.users` → `private.handle_new_user()` legt das Profil an.
  Name: `user_metadata.full_name` → `user_metadata.name` → E-Mail-Lokalteil → „Mitglied“ (auf 80 Zeichen gekürzt).
  Die Funktion kann nicht fehlschlagen (sonst wäre die Registrierung blockiert); `on conflict do nothing`.

### `public.families`

| Spalte | Typ | Regeln |
|---|---|---|
| `id` | uuid PK | `gen_random_uuid()` |
| `name` | text not null | 1–60 Zeichen (getrimmt) |
| `color_hex` | text not null | `^#[0-9A-Fa-f]{6}$`; RPCs speichern in Großbuchstaben |
| `task_visibility` | `task_visibility` | Standard `'all'` |
| `members_can_invite` | boolean | Standard `true` |
| `members_can_manage_family` | boolean | Standard `true` (Name, Farbe, Sichtbarkeit) |
| `members_can_remove_members` | boolean | Standard `true` |
| `created_by` | uuid null | → `profiles(id)` `on delete set null` |
| `created_at`, `updated_at` | timestamptz | `updated_at` per Trigger |

Index: `families_created_by_idx`.

### `public.family_members`

| Spalte | Typ | Regeln |
|---|---|---|
| `family_id` | uuid | → `families(id)` `on delete cascade` |
| `user_id` | uuid | → `profiles(id)` `on delete cascade` |
| `role` | `family_role` | Standard `'member'` |
| `joined_at` | timestamptz | |

PK `(family_id, user_id)`; Index `family_members_user_id_idx (user_id)` für alle „meine Familien“-Abfragen.
Die FK auf `profiles` erlaubt PostgREST-Embedding (`family_members?select=*,profiles(*)`).

### `public.family_invites`

| Spalte | Typ | Regeln |
|---|---|---|
| `id` | uuid PK | |
| `family_id` | uuid | → `families(id)` `on delete cascade` |
| `code` | text unique | 8 Zeichen Crockford-Base32 `^[0-9A-HJKMNP-TV-Z]{8}$` (40 Bit) |
| `created_by` | uuid null | → `profiles(id)` `on delete set null` |
| `created_at` | timestamptz | |
| `expires_at` | timestamptz | Standard `now() + 7 Tage`; `> created_at` |
| `revoked_at` | timestamptz null | gesetzt durch `revoke_invite` |
| `use_count` | integer | ≥ 0; zählt erfolgreiche Beitritte |

Indizes: `family_invites_family_id_idx`, `family_invites_created_by_idx`, Unique auf `code`.

- `private.generate_invite_code()`: 5 Byte aus `extensions.gen_random_bytes` → 8 × 5 Bit → Alphabet
  `0123456789ABCDEFGHJKMNPQRSTVWXYZ`.
- `private.normalize_invite_code(text)`: Großschreibung, Leerzeichen/Bindestriche entfernen, `O→0`, `I/L→1`
  (Crockford-Regeln). So funktionieren auch Eingaben wie `abcd-efgh`.

### `private.invite_attempts`

| Spalte | Typ | Regeln |
|---|---|---|
| `id` | bigint identity PK | |
| `user_id` | uuid | → `auth.users(id)` `on delete cascade` |
| `attempted_at` | timestamptz | |
| `reason` | text | `invalid_code` \| `expired` \| `revoked` |

Index `(user_id, attempted_at desc)`. RLS aktiv mit Ablehnungs-Policy `invite_attempts_deny_all`
(`using (false)`, Migration 0005), keine Rechte für Client-Rollen.
`join_family` löscht beim Aufruf die Einträge des Nutzers, die älter als eine Stunde sind.

## Storage: Profilbilder (0006)

Privater Bucket `avatars` (Limit 1 MB, nur `image/jpeg`). Genau ein Bild pro Person unter
`{user_id}/avatar.jpg`; die App lädt mit `upsert` hoch und überschreibt so das alte Bild.

| Policy auf `storage.objects` | Aktion | Regel |
|---|---|---|
| `avatars_select_own_and_co_members` | SELECT | eigener Ordner oder Ordner einer Person aus einer gemeinsamen Familie (`private.co_member_ids()`) |
| `avatars_insert_own` | INSERT | nur `name = '{eigene user_id}/avatar.jpg'` |
| `avatars_update_own` | UPDATE | nur das eigene `avatar.jpg`, kein Umbenennen |

- Kein DELETE für Clients. „Bild entfernen“ setzt `profiles.avatar_path` per `update_profile(null, '')` auf null;
  die Datei bleibt liegen und wird bei der Kontolöschung (Phase 9) entfernt.
- Anzeige über signierte URLs (`createSignedURL`); Cache-Schlüssel in der App: Pfad + `profiles.updated_at`.
- Tests: `supabase/tests/0002_storage_avatars.sql` (16 Prüfungen, grün am 2026-10-20).

## RLS-Hilfsfunktionen (0003, Schema `private`)

Alle `security definer`, `stable`, `set search_path = ''`, nutzen `(select auth.uid())`.
`authenticated` hat `EXECUTE` (für die Auswertung der Policies), aber **kein** `USAGE` auf `private`:
Direkte Aufrufe per SQL/API sind damit nicht möglich (Test F13).

| Funktion | Ergebnis |
|---|---|
| `is_family_member(fid)` | boolean |
| `family_role(fid)` | `family_role` oder null |
| `has_family_permission(fid, perm)` | boolean; `perm` ∈ `invite`, `manage_family`, `remove_members`; Admin immer `true`; unbekanntes Recht → Fehler 22023 |
| `my_family_ids()` | setof uuid – Familien des Nutzers (für Policies) |
| `my_family_ids_with_permission(perm)` | setof uuid – Familien, in denen der Nutzer das Recht hat |
| `co_member_ids()` | setof uuid – Nutzer, mit denen man mindestens eine Familie teilt |

Policies nutzen das Muster `spalte = any (array (select private.…()))` (Supabase-Empfehlung: einmal pro
Statement auswerten statt pro Zeile).

## RPCs (0004, Schema `public`)

Alle: `security definer`, `set search_path = ''`, `EXECUTE` nur für `authenticated`
(entzogen für `public`, `anon`, `service_role`).

| RPC | Rückgabe | Prüfungen |
|---|---|---|
| `create_family(p_name, p_color_hex)` | `families`-Zeile | angemeldet; Name 1–60; Farbe `#RRGGBB`. Ersteller wird `admin`. |
| `create_invite(p_family_id)` | `family_invites`-Zeile | Mitglied; Recht `invite`. Code-Kollision → bis zu 5 neue Versuche. |
| `revoke_invite(p_invite_id)` | `family_invites`-Zeile | Mitglied der Familie der Einladung; Recht `invite`; idempotent. |
| `join_family(p_code)` | `jsonb` (siehe unten) | Rate-Limit; Code gültig, nicht widerrufen, nicht abgelaufen; idempotent. |
| `update_family(p_family_id, p_name?, p_color_hex?, p_task_visibility?)` | `families`-Zeile | Mitglied; Recht `manage_family`; Validierung wie oben. |
| `set_family_permissions(p_family_id, p_members_can_invite?, p_members_can_manage_family?, p_members_can_remove_members?)` | `families`-Zeile | nur Admin. |
| `set_member_role(p_family_id, p_user_id, p_role)` | `family_members`-Zeile | nur Admin; Ziel muss Mitglied sein; letzter Admin kann nicht herabgestuft werden. |
| `remove_member(p_family_id, p_user_id)` | `'removed'` \| `'left'` \| `'family_deleted'` | sich selbst → wie `leave_family`; sonst Recht `remove_members`; Admins nur durch Admins. |
| `leave_family(p_family_id)` | `'left'` \| `'family_deleted'` | Mitglied; letzter Admin darf nicht gehen, solange andere da sind; letzte Person → Familie wird gelöscht (Mitglieder/Einladungen per Cascade). |
| `update_profile(p_display_name?, p_avatar_path?)` | `profiles`-Zeile | nur eigenes Profil; Name 1–80; Avatar-Pfad `{eigene user_id}/{datei}`; `''` entfernt das Bild. |

Rollen- und Mitgliedschaftsänderungen sperren die Familienzeile (`select … for update`), damit parallele
Aufrufe den Schutz des letzten Admins nicht aushebeln.

### `join_family` – Rückgabe statt Fehler

`join_family` wirft bei ungültigen Codes bewusst **keinen** Fehler: Ein Fehler rollt die Transaktion zurück,
damit auch den protokollierten Fehlversuch – das Rate-Limit wäre wirkungslos. Stattdessen:

```json
{ "status": "joined", "family_id": "…", "retry_after_seconds": null, "message": "Du bist der Familie beigetreten." }
```

| `status` | Bedeutung | zählt als Fehlversuch |
|---|---|---|
| `joined` | beigetreten, `use_count + 1` | – |
| `already_member` | schon Mitglied (idempotent), `family_id` gesetzt | nein |
| `invalid_format` | kein 8-stelliger Crockford-Code (nach Normalisierung) | nein |
| `invalid_code` | Code unbekannt | ja |
| `revoked` | Code widerrufen | ja |
| `expired` | Code abgelaufen | ja |
| `rate_limited` | ≥ 10 Fehlversuche in der letzten Stunde; `retry_after_seconds` gesetzt | – |

Parallele Aufrufe desselben Nutzers werden per `pg_advisory_xact_lock` serialisiert.

### Fehlerkatalog (`private.raise_app_error`)

Fehler aus den RPCs haben eine deutsche `message`, einen stabilen Schlüssel in `hint` und einen SQLSTATE,
aus dem PostgREST den HTTP-Status ableitet. Der Client wertet `hint` aus – aber **nur, wenn der Wert in
dieser Tabelle steht**: Supabase hängt an Postgres-Rechtefehler (42501) einen eigenen englischen Hint an
(„Grant the required privileges to the current role with: …“). Unbekannte Hints → allgemeine Fehlermeldung
anhand von SQLSTATE/HTTP-Status.

| `hint` | SQLSTATE | HTTP (PostgREST) | Meldung |
|---|---|---|---|
| `not_authenticated` | 42501 | 401/403 | Nicht angemeldet. |
| `invalid_family_name` | 22023 | 400 | Der Familienname muss 1 bis 60 Zeichen lang sein. |
| `invalid_color` | 22023 | 400 | Die Farbe muss im Format #RRGGBB angegeben werden. |
| `invalid_display_name` | 22023 | 400 | Der Anzeigename muss 1 bis 80 Zeichen lang sein. |
| `invalid_avatar_path` | 22023 | 400 | Der Bildpfad muss im eigenen Ordner liegen ({user_id}/{datei}). |
| `invalid_role` | 22023 | 400 | Unbekannte Rolle. |
| `family_not_found` | P0002 | 404 | Familie nicht gefunden oder du bist kein Mitglied. |
| `member_not_found` | P0002 | 404 | Diese Person ist kein Mitglied der Familie. |
| `invite_not_found` | P0002 | 404 | Einladung nicht gefunden. |
| `profile_not_found` | P0002 | 404 | Profil nicht gefunden. |
| `admin_required` | 42501 | 403 | Nur Admins dürfen das. |
| `permission_denied_invite` | 42501 | 403 | Du darfst in dieser Familie niemanden einladen. |
| `permission_denied_manage_family` | 42501 | 403 | Du darfst diese Familie nicht bearbeiten. |
| `permission_denied_remove_members` | 42501 | 403 | Du darfst in dieser Familie keine Mitglieder entfernen. |
| `admin_required_to_remove_admin` | 42501 | 403 | Nur Admins dürfen andere Admins entfernen. |
| `last_admin` | P0001 | 400 | Die Familie braucht mindestens einen Admin. Ernenne zuerst eine andere Person zum Admin. |
| `invite_code_generation_failed` | P0001 | 400 | Es konnte kein eindeutiger Einladungscode erzeugt werden. Bitte erneut versuchen. |

Nicht-Mitglieder bekommen bei Familien-RPCs immer `family_not_found` (bzw. `invite_not_found`), damit sie
nicht erfahren, ob eine Familie existiert.

## Interne Helfer (0004, Schema `private`, ohne Client-Rechte)

`raise_app_error(key)`, `require_uid()`, `require_member(fid)`, `join_family_result(status, fid, retry)`.
