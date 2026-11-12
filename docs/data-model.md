# Datenmodell (Stand Phase 5 „Wiederholungen“)

Dieses Dokument beschreibt die Tabellen, Funktionen und RPCs aus den Migrationen
`supabase/migrations/0001`–`0008`. Rechte und Policies im Detail: [rls-matrix.md](rls-matrix.md).
Serien, Geräte und Kalender kommen ab Phase 5 dazu. Regeln für Aufgaben: [ADR 0007](decisions/0007-task-rules.md).

## Migrationsstand (Projekt `ldeouecoaqyfvubhrjei`)

| Migration | Angewendet | Weg |
|---|---|---|
| `0001_extensions_and_schemas` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0002_profiles_families` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0003_rls_helpers_policies` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0004_family_rpcs` | 2026-10-20 | **manuell im Supabase-SQL-Editor** (die MCP-Bestätigung für Statements mit `delete` wurde in der App automatisch abgelehnt). Eintrag in `supabase_migrations.schema_migrations` (Version `20261020182858`) nachträglich ergänzt; Inhalt per SHA-256 gegen die Datei geprüft. |
| `0005_invite_attempts_deny_policy` | 2026-10-20 | Supabase-MCP `apply_migration` |
| `0006_avatars_storage` | 2026-10-20 | Supabase-MCP `apply_migration` (Phase 2) |
| `0007_tasks` | 2026-10-21 | **manuell im Supabase-SQL-Editor** (MCP-Bestätigung abgelehnt). Der Eintrag `20261020205741` in `schema_migrations` wurde vorher versehentlich mit dem Inhalt `select 1;` angelegt (ohne Wirkung); das Korrigieren des gespeicherten Texts wurde ebenfalls automatisch abgelehnt. Maßgeblich ist die Datei (SHA-256 `47e10558a612314b…`). |
| `0008_history_purge` | 2026-10-21 | **manuell im Supabase-SQL-Editor**. Auch hier wurde der Eintrag `20261021044920` vorher versehentlich mit einer wirkungslosen Platzhalter-Abfrage angelegt; maßgeblich ist die Datei (SHA-256 `3d7a39442fb049e3…`). |
| `0009_recurrence` | 2026-10-21 | **manuell im Supabase-SQL-Editor** (enthält `delete`-Anweisungen; vorher kein Platzhalter-Eintrag). Inhalt per SHA-256 `86cf70d71478f91b…` gegen die Zwischenablage geprüft; Tests `supabase/tests/0006_recurrence.sql`: 42/42 grün. |
| `0010_family_permissions` | 2026-10-21 | **manuell im Supabase-SQL-Editor** (SHA-256 `3fa201b6d20879ca…`). Tests `supabase/tests/0007_family_permissions.sql`: 23/23 grün. |
| `0011_outlook` | 2026-10-21 | **manuell im Supabase-SQL-Editor**. Tests `supabase/tests/0008_outlook.sql`: 21/21 grün. Eintrag in `schema_migrations` (wie 0009, 0010) am 2026-10-21 nachgetragen. |
| `0012_notifications` | 2026-10-21 | Supabase-MCP `apply_migration` (bewusst ohne `delete`). Tests `supabase/tests/0009_notifications.sql`: 29/29 grün. |
| `0013_notification_dedupe` | 2026-10-21 | Supabase-MCP `apply_migration` |
| `0014_push_claim_starts_at` | 2026-10-21 | Supabase-MCP `apply_migration` |
| `0015_notification_cleanup` | 2026-10-21 | **manuell im Supabase-SQL-Editor** (enthält `delete`); trägt sich selbst in `schema_migrations` ein. Täglich 03:45 UTC: Aufträge, beendete Live Activities und abgemeldete Geräte nach 30 Tagen, Cron-Tokens nach 1 Tag. |
| `0016_oauth_states_user_index` | 2026-10-22 | Supabase-MCP `apply_migration` (Advisor: Index für Fremdschlüssel) |
| `0017_backup` | 2026-10-22 | Supabase-MCP `apply_migration` (bewusst ohne Löschbefehle). Datensicherung, siehe unten und [ADR 0009](decisions/0009-backups.md). |
| `0018_rotation_and_nudges` | `20261024120000` | eingespielt am 2026-10-29 über den SQL-Editor (enthält `drop function`, `delete`). Tests `supabase/tests/0010_rotation_nudges.sql` (47/47). |
| `0019_clear_history` | `20261029100000` | eingespielt am 2026-10-29 über den SQL-Editor (enthält `delete`). `clear_history()`: Admins leeren den Verlauf ihrer Familien endgültig. Tests `supabase/tests/0011_clear_history.sql`. |
| `0020_activity_end_race` | – | eingespielt am 2026-10-30 über `apply_migration` (reiner Funktionsersatz). `push_claim_jobs`: Ein Live-Activity-Ende nach Terminänderung beendet nur Activities, die schon vor dem Auftrag liefen. Tests P8/P9 in `supabase/tests/0009_notifications.sql`. |
| `0021_private_tasks` | `20261111120000` | Private Aufgaben und Serien (`is_private`), ADR [0012](decisions/0012-private-aufgaben-und-letzte-familie.md). Eingespielt am 2026-11-12 über den SQL-Editor (enthält `drop function`, `delete`); Eintrag in `schema_migrations` vorhanden, neue Signaturen von `create_task`/`create_recurring_task` (mit `p_private`) auf dem Server geprüft, Advisors ohne neue Funde. Tests `supabase/tests/0012_private_tasks.sql` (48/48 grün, Entwicklungs-DB, Rollback; auf der Produktion im SQL-Editor ausführen; Altbestand 0003–0007, 0010, 0011 danach weiter grün). |
| `0022_purge_history_entry` | `20261112120000` | **noch nicht eingespielt** (Datei vorhanden; enthält `delete` → im SQL-Editor ausführen). `purge_history_entry(p_kind, p_id)`: einen einzelnen Verlaufseintrag (`'task'` oder `'series'`) endgültig löschen – Wischen nach links im Verlauf; Recht „Aufgaben löschen“, bei privaten Aufgaben der Ersteller. Tests `supabase/tests/0013_purge_history_entry.sql` (noch nicht gelaufen). |

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

## Aufgaben (0007)

### `public.tasks`

| Spalte | Typ | Regeln |
|---|---|---|
| `id` | uuid PK | |
| `family_id` | uuid | → `families` `on delete cascade` |
| `series_id`, `occurrence_date` | uuid, date | für Serien (Phase 5); beide null oder beide gesetzt; `unique (series_id, occurrence_date)` |
| `created_by` | uuid null | → `profiles` |
| `title` | text | 1–200 Zeichen (getrimmt) |
| `description` | text null | höchstens 4000 Zeichen; leer → null |
| `start_date`, `start_time`, `timezone` | date null, time null, text | Uhrzeit nur mit Datum; Zeitzone IANA (geprüft gegen `pg_timezone_names`) |
| `starts_at`, `sort_at` | timestamptz | per Trigger `compute_task_times`: Datum + Uhrzeit (sonst 00:00) in `timezone`; `sort_at = coalesce(starts_at, created_at)` |
| `completion_mode` | `completion_mode` | `any_one` \| `each` |
| `completed_at`, `completed_by`, `completion_source` | | komplett erledigt; Quelle `assignee` \| `creator` |
| `deleted_at`, `deleted_by`, `deleted_by_series_op` | | weiches Löschen; Serien-Löschung ab Phase 5 |
| `version` | integer | +1 bei jeder Änderung über die RPCs (Konfliktschutz) |

### `public.task_assignees`, `public.images`, `public.task_image_links`

- `task_assignees(task_id, user_id, assigned_by, assigned_at, completed_at)` – Status pro Person.
- `images(id, family_id, path, thumb_path, width, height, created_by)` – Pfade `{family_id}/{id}.jpg` und `…_thumb.jpg`.
- `task_image_links(task_id, image_id, position)` – Reihenfolge der Bilder.

### Sichtbarkeit

`private.can_view_task(task)`: Mitglied der Familie **und** (Sichtbarkeit `all` **oder** Ersteller **oder** zugewiesen) – Entscheidung F1. Gilt gleich für Aufgaben, Zuweisungen, Bilder (Tabelle und Storage) und später den Verlauf. Die Policy auf `tasks` nutzt Mengenfunktionen (`my_family_ids`, `my_all_tasks_family_ids`, `my_assigned_task_ids`).

### RPCs

| RPC | Wer | Hinweise |
|---|---|---|
| `create_task(p_family_id, p_title, p_completion_mode, p_assignee_ids, p_description?, p_start_date?, p_start_time?, p_timezone?, p_images?)` | Mitglied | ≥ 1 Person, alle Mitglieder; Bilder vorher hochladen |
| `update_task(p_task_id, p_expected_version, …gleiche Felder)` | Mitglied mit Sicht, offene Aufgabe | vollständiger Stand; null entfernt Beschreibung/Datum |
| `complete_task(p_task_id, p_scope 'self'\|'all')` | siehe ADR 0007 | idempotent |
| `uncomplete_task(p_task_id, p_scope)` | `self`: zugewiesene Person; `all`: Mitglied mit Sicht | |
| `delete_task(p_task_id)`, `restore_task(p_task_id)` | Mitglied mit Sicht | weich, idempotent |

Neue Fehlerschlüssel: `invalid_task_title`, `invalid_task_description`, `invalid_start`, `invalid_timezone`, `invalid_completion_mode`, `assignees_required`, `assignee_not_member`, `too_many_images`, `invalid_image`, `task_not_found`, `task_conflict`, `task_closed`, `completion_mode_locked`, `not_allowed_to_complete`, `invalid_scope`.

### Storage `task-images` und Realtime

- Privater Bucket, 5 MB, nur JPEG. Hochladen in den Ordner einer eigenen Familie mit Dateinamen `{uuid}.jpg`/`{uuid}_thumb.jpg`; Lesen nur, wenn das Bild an eine sichtbare Aufgabe angehängt ist.
- Trigger `tasks_broadcast_change` → `realtime.send('task_changed', topic 'user:<uid>', privat)` an alle Familienmitglieder. Policy `realtime_receive_own_user_channel`: Empfang nur auf dem eigenen Kanal.

Tests: `supabase/tests/0003_tasks.sql` (49 Prüfungen) und `0004_tasks_papierkorb.sql` (7), grün am 2026-10-21. I1 (Realtime-Nachrichten in der Datenbank) wird übersprungen, solange der Realtime-Dienst keine Tagespartition angelegt hat.

## Verlauf und 30-Tage-Bereinigung (0008)

- **Verlauf** = Aufgaben mit `completed_at` oder `deleted_at` in den letzten 30 Tagen; die App fragt `tasks` direkt ab (gleiche RLS wie überall). Gelöscht hat Vorrang vor erledigt. Wiederherstellen: gelöschte per `restore_task`, erledigte per `uncomplete_task(…, 'all')` – jedes Mitglied mit Sicht.
- **Bereinigung** täglich 03:15 UTC (`cron.job` `familiar-purge-history`):
  1. `private.start_history_purge()` erzeugt ein Einmal-Token (gespeichert nur als SHA-256 in `private.cron_tokens`) und ruft per `pg_net` die Edge Function `purge-history` auf (`verify_jwt = false`, eigene Prüfung über das Token).
  2. Die Function löst das Token mit dem Secret-Key über `public.purge_expired_history(p_token)` ein (nur `service_role`; Token 15 Minuten gültig, nur einmal).
  3. Die RPC löscht Aufgaben, die seit mehr als 30 Tagen erledigt oder gelöscht sind, und Bildzeilen ohne Verknüpfung (älter als 1 Tag), und liefert alle Dateien in `task-images` ohne Bildzeile (älter als 1 Tag). Die Function löscht diese über die Storage-API.
- `private.app_settings`: `functions_base_url` je Umgebung (Dev: `https://ldeouecoaqyfvubhrjei.supabase.co/functions/v1`).
- Tests: `supabase/tests/0005_history_purge.sql` (7/7); End-to-End am 2026-10-21: HTTP 200, Token eingelöst.

## Wiederholungen (0009)

Regeln und Begründungen: [ADR 0008](decisions/0008-recurrence.md).

| Tabelle | Inhalt |
|---|---|
| `public.task_series` | Regel (`freq` daily/weekly/monthly, `weekdays` ISO 1–7, `month_days` 1–31, Check-Constraint), Vorlage (Titel, Beschreibung, Erledigungsart, Startdatum, Uhrzeit, Zeitzone), `generated_until` (Wasserstandsmarke), `resume_from`, `deleted_at/by`, `version` |
| `public.series_assignees` | Zuweisungen der Vorlage |
| `public.series_image_links` | Bilder der Vorlage (gleiche `images`-Zeilen wie die Vorkommen) |
| `public.series_deletions` | ein Verlaufseintrag pro Serien-Löschung (`restored_at/by`) |
| `public.tasks` (geändert) | `series_id` → `task_series` `on delete set null`; `deleted_by_series_op` → `series_deletions`; Check `series_id is null or occurrence_date is not null` |

Lesen per RLS (`can_view_series`), Schreiben nur über die RPCs `create_recurring_task`, `update_series_from`,
`delete_series`, `restore_series_deletion`; `update_task` koppelt Vorkommen ab, `restore_task` lehnt mit der Serie
gelöschte Vorkommen ab. Projektion für den Kalender: `project_series_occurrences(from, to)`. Erzeugung:
`private.generate_series_occurrences` (pro Serie) und Cron-Job `familiar-generate-occurrences` (`*/5 * * * *`).
Realtime: Änderungen an `task_series` (außer reinem Fortschreiben der Wasserstandsmarke) senden ebenfalls
`task_changed` (Inhalt `series_id`, `family_id`). Neue Fehlerschlüssel: `invalid_recurrence`,
`recurrence_requires_date`, `not_an_occurrence`, `series_not_found`, `series_deleted`, `restore_series_instead`,
`series_deletion_not_found`, `invalid_range`.

## Familienrechte und Konto (0010)

- `families`: neue Schalter `members_can_create_tasks`, `members_can_edit_tasks`, `members_can_delete_tasks` (Standard `true`); `has_family_permission` kennt `create_tasks`, `edit_tasks`, `delete_tasks`.
- Alle Aufgaben-RPCs prüfen das passende Recht (`private.require_task_permission`): anlegen (`create_task`, `create_recurring_task`), bearbeiten (`update_task`, `update_series_from`), löschen/wiederherstellen (`delete_task`, `delete_series`, `restore_task`, `restore_series_deletion`). Abhaken/Rückgängig unverändert für alle.
- `set_family_permissions` mit sechs Schaltern (null = unverändert), `delete_family` (nur Admin).
- `prepare_account_deletion(user)` nur für `service_role`: Familien ohne weitere Mitglieder löschen, Admin-Rolle an das am längsten dabei befindliche Mitglied weitergeben, Besitz an Aufgabenbildern lösen (Supabase: Nutzer mit eigenen Storage-Objekten lassen sich nicht löschen), Profilbild-Pfade liefern. Die Edge Function `account-delete` (verify_jwt) ermittelt den Nutzer aus dem JWT, löscht die Profilbilder über die Storage-API und danach den Auth-Nutzer.
- Neue Fehlerschlüssel: `permission_denied_create_tasks`, `permission_denied_edit_tasks`, `permission_denied_delete_tasks`.

## Mitteilungen und Live Activities (0012–0014)

| Objekt | Zweck |
|---|---|
| `devices` | APNs-Geräte-Token je Konto (`apns_environment` sandbox/production), Push-to-Start-Token, `invalidated_at` statt Löschen (Abmelden, 410/BadDeviceToken). Lesen nur eigene; Schreiben nur per RPC. |
| `live_activities` | Laufende Activities je Gerät mit Update-Token; `state` active/ended. |
| `notification_jobs` | Outbox; kein Client-Zugriff. `dedupe_key` eindeutig → keine Doppelten. Status pending → sending (`claim_id`, `FOR UPDATE SKIP LOCKED`) → sent/failed/skipped; bis zu 3 Versuche. |
| Trigger | Zuweisung (nicht an sich selbst, nicht bei Serien-Vorkommen), erledigt (Ersteller + Zugewiesene außer wer selbst abgehakt hat), gelöscht, relevante Änderung (E6: Titel, Startzeit, Erledigungsart), Activity-Update/-Ende. |
| `private.enqueue_due_notifications()` | Jede Minute zustandslos aus dem aktuellen Stand: Activity-Start 5 min vor Start (Nur-Datum: 08:00 Ortszeit bzw. ab Zuweisung, E3), „Jetzt“ zum Start, Erinnerung 1 h danach und dann alle 24 h (ohne Uhrzeit: alle 24 h); nur frisch fällige Slots, keine Nachholflut. |
| Cron `familiar-push-dispatch` (`* * * * *`) | Legt Fälliges an und ruft `push-dispatch` nur auf, wenn Aufträge warten (Einmal-Token). |
| RPCs (App) | `register_device`, `unregister_device` (vor dem Abmelden), `register_live_activity`, `end_live_activity`. |
| RPCs (nur service_role) | `push_claim_jobs(token)` liefert Inhalt, ContentState-Felder (`starts_at_unix` nur mit Uhrzeit, `is_open`, `can_complete`, Initialen), Geräte und Activities; `push_report_results(results)`. |

Spike S2 (2026-10-21): Die Edge Function erreicht APNs per `fetch` über HTTP/2 – die Sandbox antwortet ohne Schlüssel mit `403 {"reason":"MissingProviderToken"}`. Kein externer Sender nötig.

## Reihum und Anstupsen (0018)

Entscheidung: [ADR 0010](decisions/0010-reihum-widgets-anstupsen-siri.md).

| Objekt | Zweck |
|---|---|
| `task_series.assignment_mode` | `together` (alle Zugewiesenen, Standard) \| `rotate` (reihum, pro Termin eine Person) |
| `task_series.rotation_unit`, `rotation_start` | Wechsel pro Termin (`occurrence`) oder pro Kalenderwoche (`week`); `rotation_start` ist ein echter Termin mit Index 0 (beim Anlegen der erste Termin ab `max(Start, heute)`, beim Ändern ab einem Termin dieser Termin) |
| `series_assignees.position` | Reihenfolge |
| `private.rotation_index`, `rotation_assignee`, `occurrence_assignees` | Wer dran ist: `liste[k mod n]`, `k` = Termine in `(rotation_start, Termin]` bzw. Wochen; nur aktuelle Mitglieder; gleiche Regel in Swift (`RotationRules`) |
| `create_recurring_task`, `update_series_from` | neue Parameter `p_assignment_mode`, `p_rotation_unit`; Reihum erzwingt `any_one` und ≥ 2 Personen (`rotation_needs_two`) |
| `private.handle_member_departure()` (Trigger `family_members_departure`) | Austritt: Serienplätze und offene Zuweisungen der Person in der Familie löschen, Reihum-Termine ohne Person neu besetzen, „jede Person einzeln“ ggf. abschließen, Version erhöhen (Realtime). Einmalige Bereinigung alter Zuweisungen von Nicht-Mitgliedern |
| `private.my_rotation_series_ids()`, `can_view_task`, Policy `tasks_select_visible` | Reihum-Beteiligte sehen alle Termine ihrer Serie (auch bei „nur Zugewiesene“) |
| `nudge_task(p_task_id, p_user_id)` | Anstupsen: nur offene Aufgaben, nur aktuelle Mitglieder (`member_not_found`), nur offene Zuweisungen, nicht sich selbst, 1 × pro Stunde und Person (`private.task_nudges`, Löschung nach 1 Tag), 21–7 Uhr gebündelte Zustellung um 7 Uhr; Auftrag `nudge` |
| Mitteilungen | Sammeländerungen setzen `familiar.bulk_change = 'on'` (Erzeugung, Ändern ab Termin, Austritt): keine Einzelmitteilungen „zugewiesen“/„geändert“. `update_series_from` meldet danach je Person einmal („zugewiesen“, wenn ihr nächster Termin neu ist, sonst „geändert“). Neue Serie: einmal an die Personen des ersten Termins. Tauschen: neue Person bekommt „zugewiesen“, bei der alten endet die Live Activity (`task_assignees_notify_removal`) |
| `private.enqueue_notification` | legt Aufträge nur für bestehende Profile an (Kontolöschung) |
| `private.enqueue_due_notifications`, `push_claim_jobs` (`is_member`) | Zeitgesteuertes und alle Inhalte nur an aktuelle Mitglieder; das Ende einer Live Activity geht trotzdem raus |
| `private.enqueue_activity_end` | nur Live Activities auf angemeldeten Geräten |
| `review_sign_in_begin()` / `review_sign_in_succeeded(id)` | Prüf-Zugang: jeder Versuch zählt zunächst als Fehlversuch (Advisory Lock), höchstens 10 pro Stunde; nur `service_role` |
| `private.purge_notifications()` | wie 0015, zusätzlich `task_nudges` und `review_sign_in_attempts` nach 1 Tag |

Neue Fehlerschlüssel: `invalid_rotation`, `rotation_needs_two`, `nudge_self`, `nudge_not_open`, `nudge_too_soon`.

## Datensicherung (0017)

Begründung, Grenzen und Wiederherstellung: [ADR 0009](decisions/0009-backups.md); Einrichtung: [setup/backup.md](setup/backup.md).

| Objekt | Zweck |
|---|---|
| Cron `familiar-backup` (02:30 UTC) | `private.start_backup()` → Einmal-Token → Edge Function `backup` (Modus `run`). |
| Cron `familiar-backup-check` (08:00 UTC) | `private.check_backup()`: keine erfolgreiche Sicherung seit 30 h → `backup` im Modus `alert` (Warn-E-Mail über Resend). |
| `public.backup_export()` | STABLE, nur `service_role`: alle Tabellen in `public` (außer Geräte, Mitteilungs-Aufträge, Live Activities, Outlook) plus `auth.users`, `auth.identities`, `supabase_migrations.schema_migrations` als ein JSON-Dokument aus einem Snapshot. |
| `public.backup_image_plan(limit)` / `backup_image_saved` / `backup_image_hidden` | Inkrementelle Bildsicherung über `private.backup_objects` (Bucket, Name, ETag, `hidden_at`). |
| `public.backup_begin` / `backup_finish` | Token einlösen bzw. Ergebnis nach `private.backup_runs`; `backup_finish(..., p_continue => true)` startet die nächste Etappe (max. 20). |
| `private.start_restore(mode, date, confirm, cursor, run_id)` | Nur von Hand: Edge Function `backup-restore` (`probe` / `restore` / `images`), Bericht in `private.restore_runs`. |
| Selbsttest | `select private.start_backup('selftest');` – Antwort in `net._http_response`: Verschlüsselung hin und zurück, Secrets, B2-Rechte. |

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
