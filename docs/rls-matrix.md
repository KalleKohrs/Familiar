# RLS-Matrix (Stand Phase 1 „Backend-Basis“)

Wer darf was – durchgesetzt in der Datenbank, nicht in der App. Grundlage: Migrationen
`supabase/migrations/0001`–`0005`; Tabellen und RPCs im Detail: [data-model.md](data-model.md).
Tests: `supabase/tests/0001_rls_families.sql`.

## Rollen

| Rolle | Wer |
|---|---|
| `anon` | Anfrage ohne Anmeldung (nur Publishable Key) |
| `authenticated` | angemeldeter Nutzer; `auth.uid()` = `sub` aus dem JWT |
| `service_role` | Secret Key (nur Edge Functions, später); umgeht RLS |

Fachliche Rollen innerhalb einer Familie: **Nicht-Mitglied**, **Mitglied** (`member`), **Admin** (`admin`).

## Tabellenrechte (GRANTs)

| Tabelle | `anon` | `authenticated` | `service_role` |
|---|---|---|---|
| `public.profiles` | – | `select` | alle |
| `public.families` | – | `select` | alle |
| `public.family_members` | – | `select` | alle |
| `public.family_invites` | – | `select` | alle |
| `private.invite_attempts` | – (kein Schema-Zugriff) | – (kein Schema-Zugriff) | – |

RLS ist auf allen fünf Tabellen aktiv. Es gibt **keine** `insert`/`update`/`delete`-Policies und keine
entsprechenden GRANTs für Client-Rollen: Schreiben geht nur über die RPCs.

## Lese-Policies

Alle Policies auf `public`-Tabellen: `for select to authenticated`.

| Tabelle | Policy | Bedingung |
|---|---|---|
| `profiles` | `profiles_select_self_or_co_member` | `id = (select auth.uid())` oder `id = any(array(select private.co_member_ids()))` |
| `families` | `families_select_member` | `id = any(array(select private.my_family_ids()))` |
| `family_members` | `family_members_select_member` | `family_id = any(array(select private.my_family_ids()))` |
| `family_invites` | `family_invites_select_inviter` | `family_id = any(array(select private.my_family_ids_with_permission('invite')))` |
| `private.invite_attempts` | `invite_attempts_deny_all` (`for all`, alle Rollen) | `false` – ausdrückliche Sperre (Advisor 0008); nur `join_family` nutzt die Tabelle als Eigentümer |

## Lese-Matrix

| Daten | Nicht-Mitglied | Mitglied | Admin |
|---|---|---|---|
| Familie (Name, Farbe, Schalter) | nein | ja | ja |
| Mitgliederliste der Familie | nein | ja | ja |
| Profil einer Person | nur eigenes | eigenes + alle aus gemeinsamen Familien | eigenes + alle aus gemeinsamen Familien |
| Einladungen der Familie | nein | ja, wenn `members_can_invite` | ja |
| Fehlversuche (`private.invite_attempts`) | nein | nein | nein |
| `anon` | nichts (42501) | | |

## Schreib-Matrix (RPCs)

„Schalter“ = Familieneinstellung für Mitglieder (Standard: an). Admins haben immer alle Rechte.

| RPC | Nicht-Mitglied | Mitglied | Admin |
|---|---|---|---|
| `create_family` | ja (eigene neue Familie) | ja | ja |
| `create_invite` | `family_not_found` | wenn `members_can_invite`, sonst `permission_denied_invite` | ja |
| `revoke_invite` | `invite_not_found` | wenn `members_can_invite`, sonst `permission_denied_invite` | ja |
| `join_family` | ja, mit gültigem Code (Rate-Limit) | idempotent (`already_member`) | idempotent |
| `update_family` | `family_not_found` | wenn `members_can_manage_family`, sonst `permission_denied_manage_family` | ja |
| `set_family_permissions` | `family_not_found` | `admin_required` | ja |
| `set_member_role` | `family_not_found` | `admin_required` | ja; letzter Admin → `last_admin` |
| `remove_member` (andere) | `family_not_found` | wenn `members_can_remove_members`, sonst `permission_denied_remove_members`; Admin entfernen → `admin_required_to_remove_admin` | ja |
| `remove_member` (sich selbst) | `family_not_found` | wie `leave_family` | wie `leave_family` |
| `leave_family` | `family_not_found` | ja | ja, außer letzter Admin bei weiteren Mitgliedern → `last_admin`; als letzte Person → Familie gelöscht |
| `update_profile` | nur eigenes Profil | nur eigenes Profil | nur eigenes Profil |
| alle RPCs als `anon` | 42501 | | |

Direkte Schreibzugriffe (`insert`/`update`/`delete` auf alle vier `public`-Tabellen) liefern für jede
Client-Rolle `42501 permission denied`.

## Testmatrix (`supabase/tests/0001_rls_families.sql`)

Testnutzer (nur innerhalb der Transaktion in `auth.users` angelegt): Anna (Admin), Max (Mitglied),
Otto (Nicht-Mitglied mit eigener Familie), Jana (Beitritt, Fehlversuche), Rita (Rate-Limit).

**Letzter Lauf:** 2026-10-20 gegen `ldeouecoaqyfvubhrjei` nach Migration 0005 – **136 von 136 bestanden**.
Danach geprüft: kein Schema `tests`, keine Testnutzer, alle Tabellen leer (Rollback vollständig).

| Bereich | Tests | Prüft |
|---|---|---|
| A Profil-Trigger | A1–A5 | Name aus `full_name`, `name`, E-Mail-Lokalteil, Fallback „Mitglied“, leerer `full_name` |
| B `create_family` | B1–B10 | Anlage, Trim/Normalisierung, Ersteller = Admin, Standard-Schalter, ungültiger Name/Farbe, ohne `sub`, `anon` |
| C `create_invite` | C1–C5 | Codeformat, Ablauf 7 Tage, Nicht-Mitglied, 200 Codes eindeutig, Normalisierung |
| D `join_family` | D1–D5 | Beitritt mit klein geschriebenem Code und Bindestrich, Rolle, `use_count`, Idempotenz |
| E Lesen | E1–E18 | Matrix Nicht-Mitglied/Mitglied/Admin für alle Tabellen, Familien-Isolation, `anon` |
| F Direktes Schreiben | F1–F14 | insert/update/delete auf alle Tabellen verweigert, `private` nicht erreichbar, `anon`-RPC |
| G `update_family` | G1–G6 | Mitglied mit Schalter, Farbe/Sichtbarkeit, `updated_at`, Nicht-Mitglied, Validierung |
| H Schalter | H1–H12 | nur Admin ändert Schalter; Wirkung auf `update_family`, `create_invite`, Einladungen lesen, `revoke_invite`; `null` = unverändert; unbekanntes Recht |
| I `revoke_invite` | I1–I4 | Nicht-Mitglied, Admin, Idempotenz, unbekannte ID |
| J `join_family` Fehler | J1–J9 | widerrufen, Format, null, unbekannt, abgelaufen, Protokollierung, kein Beitritt, Meldung, Erfolg |
| K Rate-Limit | K1–K8 | 10 Fehlversuche, 11. Versuch auch mit gültigem Code gesperrt, `retry_after_seconds`, kein Hochzählen, Fenster abgelaufen → Beitritt, Aufräumen, nutzerbezogen |
| L `set_member_role` | L1–L11 | Mitglied/Nicht-Mitglied, letzter Admin, Ziel kein Mitglied, Admin-Wechsel hin und zurück, No-op |
| M `remove_member` | M1–M10 | Schalter aus/an, Nicht-Mitglied, Admin nur durch Admin, Ziel kein Mitglied, Entfernte verliert Lesezugriff, sich selbst entfernen |
| N `update_profile` | N1–N12 | Trim, Sichtbarkeit für Mitglieder, nur eigenes Profil, Validierung, fremder Ordner, Pfad-Traversal, Bild setzen/entfernen, ohne `sub`, `anon` |
| O `leave_family` | O1–O7 | Nicht-Mitglied, letzter Admin, Mitglied geht, Profil-Sichtbarkeit endet, letzte Person löscht Familie samt Mitgliedern/Einladungen, andere Familie unberührt |

### Ausführen

Die Datei komplett per `execute_sql` (Supabase-MCP) oder `psql` ausführen. Sie läuft in `begin … rollback`,
legt ein temporäres Schema `tests` an und liefert als letzte Abfrage `gesamt`, `bestanden`,
`fehlgeschlagen`, `fehler` und ein Protokoll aller Tests. Danach ist die Datenbank unverändert.

Simulierte Nutzer: `set_config('role', 'authenticated', true)` und `set_config('request.jwt.claims', '{"sub": …}', true)`.
Fehler werden als `ERROR:<hint>` (App-Fehlerschlüssel) bzw. `ERROR:<SQLSTATE>` verglichen. Ein Hint zählt nur,
wenn er wie ein App-Schlüssel aussieht (`^[a-z][a-z_]*$`); Supabases eigener Hint bei Rechtefehlern
(„Grant the required privileges …“) wird ignoriert, dann gilt der SQLSTATE (42501).

## Advisors (Stand 2026-10-20, nach 0005)

| Advisor | Befund | Bewertung |
|---|---|---|
| Security WARN [0029](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) | 10 RPCs `security definer` + für `authenticated` ausführbar | **Gewollt.** Die RPCs sind die einzige Schreib-API; jede prüft `auth.uid()`, Mitgliedschaft und Rechte selbst, `search_path = ''`, kein `EXECUTE` für `anon`/`public`. Abgedeckt durch die Tests B–O. |
| Security INFO [0008](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) | `private.invite_attempts` ohne Policy | Behoben in 0005 (Ablehnungs-Policy). |
| Performance INFO [0005](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) | `families_created_by_idx`, `family_invites_created_by_idx` ungenutzt | **Behalten.** Stützen `on delete set null` beim Löschen eines Profils (sonst Seq-Scan). Leere DB → noch keine Nutzung. |
