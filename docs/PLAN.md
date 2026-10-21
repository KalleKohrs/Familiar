# Familiar – Technischer Plan (V1)

## Context

**Warum:** Für Familien soll eine ruhige, hochwertige iOS-App entstehen, in der Aufgaben der zentrale Produktbereich sind: Aufgaben anlegen, Personen zuweisen, Bilder anhängen, Wiederholungen festlegen und den Status pro Person sehen. Dazu kommen ein Kalender mit persönlichen Outlook-Terminen (nur lesend), Push-Mitteilungen und Live Activities.
**Fachliche Grundlage:** `Guide.txt`.

**Ausgangslage (geprüft am 2026-10-20):**
- **Projektordner:** enthält nur `Guide.txt`, `.mcp.json` (Supabase-MCP, Projekt `ldeouecoaqyfvubhrjei`) und `.claude/settings.local.json`. Es gibt kein Xcode-Projekt und kein Git-Repository.
- **Supabase-Projekt** `https://ldeouecoaqyfvubhrjei.supabase.co`: leer. Keine `public`-Tabellen, keine Migrationen, keine Edge Functions, keine Buckets.
  - Installiert: `supabase_vault`, `pgcrypto`, `uuid-ossp`, `pg_stat_statements`.
  - Verfügbar, aber nicht installiert: `pg_cron`, `pg_net`, `pgmq`, `pgtap`.
- **Toolchain:** Xcode 27.1, Swift 6.4. Simulatoren: iOS 27.0/27.1 (iPhone 17, 17e, 18 Pro, Air …). Das passt zum Deployment Target iOS 27.
  - Es gibt keine Supabase-CLI, kein Node/Deno, kein Homebrew, kein xcodegen.
  - Folge: Migrationen und Edge Functions gehen über das Supabase-MCP (`apply_migration`, `deploy_edge_function`). Zusätzlich liegen sie versioniert als Dateien im Repo.

**Ergebnis:** Eine native SwiftUI-App mit Supabase-Backend, die in kleinen, testbaren Phasen entsteht. Die Datenbank ist immer maßgeblich. Push-Mitteilungen und Live Activities sind nur Hinweise.

---

## 1. Architekturentscheidungen (mit Doku-Belegen)

| Thema | Entscheidung | Begründung / Quelle |
|---|---|---|
| Backend | **Supabase ist geeignet**: Postgres+RLS, Auth (OTP, Apple, Google nativ), private Storage-Buckets, Realtime, Edge Functions, `pg_cron`/`pg_net`, Vault | Supabase-Doku: Auth-Guides, Storage Access Control, Scheduling Edge Functions |
| API-Keys | Client nur mit **Publishable Key** (`sb_publishable_…`). Server-Code mit **Secret Key** aus `SUPABASE_SECRET_KEYS`. Legacy `anon`/`service_role` nicht nutzen. | Supabase „Migrating to publishable and secret API keys“: Legacy-Keys laufen Ende 2026 aus |
| Edge Functions | `@supabase/server` mit `withSupabase({auth:'user'\|'secret'})` und `verify_jwt=false` | ebenda (empfohlen für neue Functions) |
| Schreibzugriffe | **Lesen** über RLS-geschützte `select`s. **Schreiben** nur über `security definer`-RPCs mit expliziten Prüfungen; `insert/update/delete` für `authenticated` entzogen. | Mehrtabellen-Invarianten (Zuweisung, Abhak-Rechte, Serien) lassen sich nicht sauber per Spalten-Policy abbilden |
| Realtime | **Private Broadcast** pro Nutzer (`user:<uid>`), Payload nur IDs → Client lädt RLS-geschützt nach | Supabase empfiehlt Broadcast statt Postgres Changes. Minimaler Payload verhindert Datenlecks bei „nur zugewiesene“. |
| Min. iOS | **iOS 27.0** (entschieden). Keine Versionsweichen nötig, Tests auf den installierten iOS-27-Simulatoren. | `glassEffect`, `GlassEffectContainer`, `TabRole.prominent` (iOS 27), `swipeActions` in beliebigen Containern (iOS 27) |
| Tab-Bar + Plus | Native `TabView` mit 3 Tabs + `Tab(role: .prominent)` mit Plus-Symbol, das laut Doku abgesetzt und hervorgehoben dargestellt wird. Auswahl des Plus-Tabs wird abgefangen (Binding lässt die Auswahl nicht wechseln) → Sheet „Neue Aufgabe“ + Haptik. **Fallback**, falls Spike S1 scheitert: eigene Leiste mit `GlassEffectContainer` + `glassEffect(.regular.interactive())`. | Apple-Doku `TabRole.prominent`; „Applying Liquid Glass to custom views“ |
| Live Activities | Server startet per **Push-to-Start** (`event:start`, `input-push-token:1`). Updates/Ende per Token-Push. Beim Vordergrund gleicht die App lokal ab (fehlende starten, veraltete beenden). Abhaken über `LiveActivityIntent` (läuft im App-Prozess). | ActivityKit-Doku: max. 8 h aktiv + bis 4 h Sperrbildschirm, 4 KB Datenlimit, Anzahl gleichzeitiger Activities nicht dokumentiert, Fehler behandeln |
| APNs | Token-Auth (.p8, ES256-JWT, alle 20–60 min erneuert), **HTTP/2 Pflicht**. 410/400-Fälle invalidieren Tokens. | Apple „Establishing a token-based connection“, „Sending notification requests“ |
| Outlook | Vertraulicher Client (Entra Web-Plattform), Auth-Code-Flow mit PKCE. Redirect auf Edge Function, die per 302 auf `familiar://outlook/done` umleitet (`ASWebAuthenticationSession`). Refresh-Token nur in **Supabase Vault**. | Microsoft identity platform „auth code flow“ (PKCE auch für vertrauliche Clients empfohlen; neuestes Refresh-Token speichern) |
| Graph-Scopes | `Calendars.ReadBasic offline_access openid email` (minimal). **Kein Delta**: v1.0-Delta funktioniert nur für den Primärkalender und verlangt `Calendars.Read`. Stattdessen `GET /me/calendars/{id}/calendarView` über ein Zeitfenster mit Abgleich. | Graph-Doku: `calendar-list-calendarview` und `user-list-calendars` → ReadBasic ist least privileged; `event-delta` → nur Primärkalender |

**Offene technische Risiken → frühe Spikes:**
- **S1:** Plus-Tab (`.prominent`) abfangen: Sheet öffnen, ohne dass der Tab wechselt; VoiceOver-Label „Neue Aufgabe“.
- **S2:** APNs über HTTP/2 aus der Supabase-Edge-Runtime (`fetch` handelt h2 per ALPN aus?).
  - Ausweichweg 1: `node:http2`.
  - Ausweichweg 2: kleiner externer Sender (eigene Entscheidung nötig).
- **S3:** Liefert `Calendars.ReadBasic` Organisator und Teilnehmer? Prüfung mit realem Testtermin in Phase 8.
  - Wenn nicht: auf `Calendars.Read` wechseln. Das bleibt read-only, wird dokumentiert und begründet.

---

## 2. Repository-Struktur

```
Familiar/
  Guide.txt  README.md  .gitignore
  docs/  PLAN.md  architecture.md  data-model.md  rls-matrix.md  design-system.md
         decisions/ (ADRs)  setup-secrets.md (nur Anleitung, nie Werte)
  ios/
    Familiar.xcodeproj            (Xcode-16+-Format mit synchronisierten Ordnern)
    Config/ Base.xcconfig  Secrets.example.xcconfig  (Secrets.xcconfig gitignored: SUPABASE_URL, Publishable Key, Google-Client-ID)
    Familiar/        App/ Features/{Onboarding,Tasks,TaskEditor,Gallery,Calendar,History,Families,Profile}
                     Services/{Push,LiveActivity,DeepLink}  Resources/Assets.xcassets  Info.plist  Familiar.entitlements  PrivacyInfo.xcprivacy
    FamiliarWidgets/ Live-Activity-Extension (Lock Screen, Dynamic Island compact/minimal/expanded)
    FamiliarTests/  FamiliarUITests/
    Packages/FamiliarKit/  (SPM, lokal)
      FamiliarCore   – Modelle (Codable/Sendable), Sortierung, Statuslogik, Farbabstand-Algorithmus
      FamiliarDesign – Tokens, Komponenten (Card, AvatarStack, FamilyBadge, StatusDot, PrimaryButton …)
      FamiliarData   – Repositories (Supabase), ImagePipeline, Realtime-Client
      FamiliarActivity – TaskActivityAttributes + CompleteTaskIntent (App und Extension nutzen sie gemeinsam)
  supabase/
    config.toml  migrations/NNNN_*.sql  tests/*.sql (RLS-/Logiktests, laufen in Transaktion mit rollback)
    functions/ _shared/{apns.ts, calendar/provider.ts, calendar/outlook.ts, cors.ts}
               push-dispatch/  outlook-oauth-start/  outlook-oauth-callback/  outlook-sync/
               outlook-people/  storage-purge/  account-delete/
```

**Abhängigkeiten (SPM):**
- `supabase-swift` (offiziell)
- `GoogleSignIn-iOS` (von Supabase für nativen Google-Login empfohlen)

**Sonst nur Apple-Frameworks:** ActivityKit, AppIntents, PhotosUI, AuthenticationServices, UserNotifications.

---

## 3. Datenmodell (Postgres)

Schemas:
- `public`: exponiert, RLS überall.
- `private`: nicht exponiert. Enthält Hilfsfunktionen, Job-Status, OAuth-States und Credentials-Metadaten.
- `vault`: Tokens.

**Familien & Profile**
- `profiles(id → auth.users, display_name, avatar_path, timestamps)`: Trigger legt das Profil bei Registrierung an.
- `families(id, name, color_hex, task_visibility enum('all','assigned_only'), members_can_invite, members_can_manage_family, members_can_remove_members, created_by, timestamps)`
- `family_members(family_id, user_id, role enum('admin','member'), joined_at)`: Schutz für den letzten Admin.
- `family_invites(id, family_id, code (8 Zeichen, Crockford-Base32), created_by, expires_at, revoked_at, use_count)`
  - Beitritt nur über RPC `join_family(code)`.
  - Gegen Brute Force: Rate-Limit in `private.invite_attempts`.

**Aufgaben** (Einzelaufgabe = `tasks`-Zeile ohne `series_id`; Vorkommen = `tasks`-Zeile mit `series_id`)
- `task_series(id, family_id, created_by, title, description, completion_mode enum('any_one','each'), freq enum('daily','weekly','monthly'), weekdays smallint[] (ISO 1–7), month_days smallint[] (1–31), start_date, start_time null, timezone (IANA), resume_from date, timestamps)` + `series_assignees` + `series_image_links`
- `tasks(id, family_id, series_id null, occurrence_date null, created_by, title, description, start_date null, start_time null, timezone, starts_at timestamptz (Trigger berechnet), sort_at, completion_mode, is_detached, completed_at, completed_by, completion_source enum('assignee','creator'), deleted_at, deleted_by, deleted_by_series_op null, version, timestamps)`
  - `unique(series_id, occurrence_date)` sorgt für idempotente Erzeugung.
- `task_assignees(task_id, user_id, assigned_by, assigned_at, completed_at)`: Status pro Person.
- `images(id, family_id, path, thumb_path, width, height, created_by)` + `task_image_links(task_id, image_id, position)`
- `series_deletions(id, series_id, family_id, deleted_by, deleted_at, restored_at, restored_by)`: ein Verlaufseintrag pro Serien-Löschung.
- View `history_entries` (`security_invoker`): erledigte Aufgaben, einzeln gelöschte Aufgaben und Serien-Löschungen der letzten 30 Tage.

**Geräte & Mitteilungen**
- `devices(id, user_id, apns_token, apns_env, push_to_start_token, app_version, timezone, last_seen_at, invalidated_at)`
- `live_activities(id, task_id, user_id, device_id, activity_id, update_token, state, started_at, ended_at)`
- `notification_jobs(id, kind, task_id, user_id, scheduled_for, payload, status, attempts, last_error, sent_at, dedupe_key unique)`: Outbox. Ein Job wird mit `FOR UPDATE SKIP LOCKED` übernommen. `dedupe_key` enthält z. B. `starts_at`, so entstehen keine Doppelversände.

**Externe Kalender (strikt pro Nutzer, `user_id = auth.uid()`)**
- `calendar_connections(id, user_id, provider enum('outlook'), account_email, status, last_sync_at, last_error)`: keine Tokens.
- `private.calendar_credentials(connection_id, vault_secret_id, access_expires_at, scopes)` und `private.oauth_states`
- `external_calendars(id, connection_id, user_id, provider_calendar_id, name, color, is_selected, filter jsonb)`
- `external_events(id, user_id, calendar_id, provider, provider_event_id, title, starts_at, ends_at, is_all_day, location_name, organizer_name, organizer_email, is_cancelled, synced_at)`
  - Gespeichert wird nur, was den Filter passiert. Teilnehmerlisten werden nicht gespeichert (Datensparsamkeit).

**RLS-Hilfsfunktionen** (`private`, `security definer`, `stable`, `search_path=''`, `(select auth.uid())`):
- `is_family_member(fid)`
- `has_family_permission(fid, perm)`
- `can_view_task(tid)`: Mitglied UND (Sichtbarkeit `all` ODER zugewiesen ODER **Ersteller**). Entscheidung F1: Der Ersteller sieht eigene Aufgaben immer und kann sie deshalb direkt abhaken.
- `can_view_series(sid)`

Sichtbarkeit gilt identisch für Details, Bilder (Storage-Policy über `task_image_links` → `can_view_task`) und Verlauf. Indizes: `family_members(user_id)`, `task_assignees(user_id)`, `tasks(family_id, sort_at)` mit Teilindex auf offene Aufgaben.

**Storage:** private Buckets mit Dateigrößen- und MIME-Limit. Clients nutzen signierte URLs; der Cache-Schlüssel ist der Pfad, nicht die URL.
- `task-images`: Pfad `{family_id}/{uuid}.jpg` und `_thumb.jpg`.
- `avatars`: Pfad `{user_id}/…`. Lesbar für den Nutzer selbst und für Mitglieder gemeinsamer Familien.
- Löschen nur über die Storage-API (Edge Function `storage-purge`), nie per SQL.

---

## 4. Fachlogik

**Abhaken (`complete_task`), Rückgängig (`uncomplete_task`), Wiederherstellen (`restore_history_entry`)**
- *Eine Person für alle:* Eine zugewiesene Person setzt `tasks.completed_*`. Die Aufgabe verschwindet für alle, und alle Live Activities der Aufgabe enden.
- *Jede Person einzeln:* Jede Person setzt ihren eigenen Status in `task_assignees.completed_at`. Haben alle erledigt, ist die Aufgabe komplett. Die Live Activity endet nur für die Person, die erledigt hat (auf allen ihren Geräten).
- *Ersteller:* darf die Aufgabe direkt komplett erledigen (`completion_source='creator'`). Ist der Ersteller selbst zugewiesen und gilt „einzeln“, zeigt die UI „Für mich erledigt“ und „Für alle erledigt“.
- *Rückgängig:*
  - Direkt nach dem Abhaken erscheint ein Undo-Banner.
  - Danach ist Rückgängig über den Verlauf möglich, für jedes Mitglied mit Zugriff.
  - In „einzeln“ kann jede Person ihren eigenen Status zurücknehmen.

**Wiederholungen** (eine Regel plus eigenständige Vorkommen)
- **Ein Algorithmus:** `private.series_dates(series, from, to)` in SQL. Er wird für die Erzeugung und für die Kalender-Projektion (RPC `project_series_occurrences`) genutzt und mit pgTAP-artigen SQL-Tests geprüft.
- **Erzeugung:** Alle Vorkommen bis heute sind materialisiert (verpasste bleiben überfällig), dazu das nächste künftige Vorkommen.
  - Der Generator läuft per `pg_cron` alle 5 min und sofort in den Serien-RPCs.
  - Idempotent über `ON CONFLICT (series_id, occurrence_date) DO NOTHING`.
- **Bearbeiten/„Fertig“** (Interpretation: der Fertig-Button im Bearbeiten-Formular) → Dialog „Nur dieses Vorkommen“ / „Dieses und zukünftige“.
  - Eine Regeländerung gibt es nur bei „Dieses und zukünftige“. Der Dialog erklärt: *„Die neue Regel gilt für die Serie ab diesem Vorkommen. Erledigte Vorkommen bleiben unverändert; spätere offene Vorkommen werden neu geplant.“*
- **Löschen:**
  - **Nur dieses Vorkommen:** Das Vorkommen landet als Eintrag im Verlauf.
  - **Gesamte Serie:** Ein `series_deletions`-Eintrag entsteht. Offene Vorkommen (auch überfällige) werden mit `deleted_by_series_op` markiert, statt einzelne Verlaufseinträge zu erzeugen. Erledigte Vorkommen bleiben unverändert.
  - **Wiederherstellen der Serie:** Die markierten Vorkommen werden wieder aktiv. Die Erzeugung läuft ab heute weiter (`resume_from`); Termine aus der Löschphase werden nicht nachgeholt.
- **30-Tage-Löschung:** täglicher `pg_cron`-Job (Zeilen) plus `storage-purge` für verwaiste Bilder.

**Startseite:**
- Aufgaben aller Familien in einer Liste. Abschnitte Überfällig · Heute · Morgen · Später; Aufgaben ohne Datum stehen in „Heute“ ganz oben (neueste oben), datierte chronologisch nach `sort_at` (Wunsch vom 2026-10-21); nur-Datum zählt als Tagesbeginn.
- Überfällige Aufgaben sind markiert. Keine Filter.

**Familienfarben:**
- Gespeichert wird immer die Originalfarbe.
- Liegen Farben für einen Nutzer zu nah beieinander (OKLab-ΔE unter Schwelle), verschiebt `FamilyColorResolver` die Anzeige leicht in Helligkeit/Farbton. Das geschieht nur lokal und deterministisch.
- Zusätzlich gibt es immer einen Familien-Namenskürzel bzw. ein Badge, damit die Zuordnung nie allein über Farbe läuft.

---

## 5. Mitteilungen & Live Activities

- **Fluss:** DB-Trigger → `notification_jobs`. `pg_cron` ruft jede Minute `push-dispatch` auf (per `pg_net`). Das Cron-Secret wird in der DB erzeugt, liegt im Vault und ist nie sichtbar. `push-dispatch` sendet an APNs und schreibt das Ergebnis zurück.
- **Regeln:**
  - **Zuweisung:** Push an neu zugewiesene Personen, nicht an den Auslöser.
  - **Mit Uhrzeit:**
    - Push-to-Start der Live Activity 5 min vor Start.
    - Push zum Startzeitpunkt.
    - Erinnerung nach 1 h, danach alle 24 h, solange die Person bzw. Aufgabe offen ist. Die Erinnerungs-Slots werden berechnet, `dedupe_key` verhindert Doppelte.
  - **Ohne Uhrzeit:** Push und Live Activity sofort bei Erstellung/Zuweisung. Erste Erinnerung → offene Entscheidung E3.
  - **Komplett erledigt:** Ersteller + Zugewiesene erhalten eine Mitteilung, außer allen, die selbst abgehakt haben.
  - **Relevante Änderung** (Vorschlag: Titel, Startzeit, Erledigungsart, Zuweisung hinzugefügt/entfernt, Löschung): Push an Zugewiesene außer dem Auslöser.
  - **Live Activity aktualisieren:** bei Änderungen am Inhalt.
  - **Startzeit geändert:** Live Activity beenden, ausstehende Jobs stornieren, neu planen.
- **Live Activity Inhalt:**
  - *Statisch:* `taskId`, Familienfarbe.
  - *ContentState:* Titel, `startsAt`, Erledigungsart, kompakter Personenstatus (Initialen + erledigt), `canComplete`, überfällig. Gesamtgröße unter 4 KB.
  - `staleDate = Start + 1 h` → Zustand „überfällig“. `relevanceScore` nach Startzeit.
  - Abhak-Button nur, wenn die Person laut Modus berechtigt ist.
- **Grenzen (dokumentiert und in der UI ehrlich):**
  - Eine Live Activity bleibt höchstens 8 h aktiv, danach bis zu 4 h auf dem Sperrbildschirm.
  - Die Systemgrenze für gleichzeitige Activities ist unbekannt.
  - Nutzer können Live Activities oder Mitteilungen abschalten.
  - Zustellung ist nie garantiert. Die App liest den Status immer aus der DB.

---

## 6. Auth, Onboarding, Familien

- **E-Mail:** 6-stelliger **Code** per `signInWithOTP` + `verifyOTP(type: .email)`. Funktioniert geräteübergreifend und braucht keine Universal Links. Das E-Mail-Template mit `{{ .Token }}` richtet der Nutzer im Dashboard ein.
- **Apple:** `SignInWithAppleButton` + Nonce → `signInWithIdToken(.apple)`. Bundle-ID unter „Client IDs“ eintragen.
- **Google:** GoogleSignIn-SDK → `signInWithIdToken(.google, idToken, accessToken)`. Web- und iOS-Client-ID im Dashboard; „Skip nonce check“ laut Supabase-Doku, Abwägung im ADR.
- **Session:** liegt im Keychain mit Auto-Refresh (beim Implementieren gegen die SDK-Doku verifizieren).
  - **Abmelden:** zuerst Gerätetoken serverseitig entfernen, dann `signOut(scope: .local)`.
  - **„Überall abmelden“:** `.global`.
  - Hinweis: Ein bereits ausgegebenes Access-JWT gilt bis zum Ablauf. Option: JWT-Laufzeit verkürzen.
- **Ablauf:** Login → Name/Profilbild → Familie erstellen oder Code/Link beitreten → Mitteilungs-Erklärung → App.
  - Ein Einladungslink, der vor dem Login geöffnet wurde, bleibt vorgemerkt. Nach dem Login folgt eine Bestätigung „Familie X beitreten?“.
- **Einladungslink** (Domain vorhanden): Universal Link `https://<deine-domain>/join/<code>`.
  - Auf der Domain liegen `/.well-known/apple-app-site-association` (`applinks` für `/join/*`) und eine kleine Fallback-Seite mit Code und App-Store-Hinweis.
  - In der App: Associated Domain `applinks:<deine-domain>`.
  - Der Code bleibt als zweiter Weg erhalten.
  - Den Domainnamen (kein Secret) fragt Phase 2 ab.
- **Familienname-Antippen (Vorschlag):**
  - Der Kopf zeigt „Familie X ⌄“ bzw. bei mehreren Familien „Alle Familien ⌄“ mit Farbpunkten.
  - Antippen öffnet das Sheet **„Familien“**: Liste mit Farbe und Mitgliedern; je Familie Einladen (ShareLink), Mitglieder, Einstellungen, Verlassen; dazu „Familie erstellen/beitreten“.
  - Das Sheet ist **kein Filter**, da V1 keine Filter hat.
- **Profilbild oben rechts:** Profil (Bild/Name), Kalender (Outlook), Mitteilungs-Status, Abmelden/Überall abmelden, **Konto löschen** (App-Store-Pflicht 5.1.1(v); Edge Function `account-delete`).
- **Rechte (Vorschlag E4, vor Phase 9 bestätigen):** Der Admin kann drei Schalter einschränken (Standard an):
  1. Mitglieder dürfen einladen.
  2. Mitglieder dürfen die Familie bearbeiten (Name, Farbe, Sichtbarkeit).
  3. Mitglieder dürfen andere Mitglieder entfernen.
  - Immer nur Admin: Rechte ändern, Admins ernennen, Familie löschen.
  - Immer für alle: Aufgaben erstellen, bearbeiten, löschen und wiederherstellen (laut Guide).

---

## 7. Kalender & Outlook

- **Monatsansicht:** eigenes `LazyVGrid`-Raster.
  - Aufgaben: gefüllte Punkte in Familienfarbe.
  - Outlook-Termine: Ring plus Kalender-Symbol, also nicht nur über Farbe unterschieden.
  - Tagesliste unten: Aufgaben-Cards und Termin-Zeilen mit Zeitspanne und „Outlook“-Badge, ohne Checkbox.
  - VoiceOver: „3. November, 2 Aufgaben, 1 Termin“.
- **Abstraktion:**
  - *Server:* `_shared/calendar/provider.ts` (`listCalendars`, `fetchEvents(window)`, `refresh`), nur `OutlookProvider`. Externe Termine werden in ein einheitliches Modell normalisiert und in `external_events.provider` abgelegt.
  - *Client:* `ExternalEventRepository`, unabhängig vom Anbieter.
  - Filter als JSON mit `type`-Registry. V1: `organizer_attendees {organizer_emails[], required_attendee_emails[], exclude_cancelled}`.
- **Setup:**
  - Outlook verbinden (`ASWebAuthenticationSession`) und Kalender auswählen.
  - Optional Filter: Organisator und Teilnehmer aus den Personen der letzten Termine auswählen (Edge Function `outlook-people`; liefert die Liste, speichert nichts). Die eigene Adresse ist vorbelegt.
  - Keine E-Mail-Adresse steht im Code.
- **Sync** (`outlook-sync`, alle 15 min per Cron, manuell und beim App-Start, wenn älter als 15 min):
  - Abruf `calendarView` über das Fenster −7 bis +120 Tage, mit Paging.
  - Filtern, Upsert, und Löschen von Terminen, die im Fenster fehlen. Dadurch werden Änderungen, Absagen und Löschungen erfasst.
  - Das neueste Refresh-Token wird im Vault gespeichert.
  - Bei `invalid_grant` gilt der Status `needs_reauth`.
- **Grenzen:**
  - Es wird nie nach Outlook geschrieben (ReadBasic ist read-only).
  - Kalendertermine erzeugen keine Aufgaben: Es gibt keinen Code-Pfad dafür, ein Test sichert das ab.
  - Ist `hideAttendees=true`, ist die Teilnehmerprüfung nicht möglich. Der Termin wird dann sicherheitshalber ausgeschlossen, mit Hinweis in der UI.

---

## 8. Design-System „Fluid Ambient“ (Phase 0, dokumentiert in `docs/design-system.md`)

> **Aktualisiert 2026-10-20:** Nach der Design-Referenz des Nutzers wurden Hintergrund (`#1E1519`, Ambient-Licht), Card-Fläche (leicht durchscheinend) und Akzent (`#FF8C42`) angepasst. Maßgeblich sind die Werte in [design-system.md](design-system.md).

**Farben:** nur dunkles Erscheinungsbild in V1, Varianten für „Kontrast erhöhen“ im Asset-Katalog.

| Token | Wert | Token | Wert |
|---|---|---|---|
| `bg.canvas` | #14100D | `text.primary` | #F6EEE6 |
| `bg.elevated` | #1C1713 | `text.secondary` | #BFB2A5 (≈7,8:1 auf Card) |
| `surface.card` | #241E19 | `text.tertiary` | #8F8378 (nur groß/dekorativ) |
| `surface.pressed` | #2C251F | `accent` | #FFA43A, `onAccent` #1B1006 |
| `surface.sunken` | #100C0A | `success` #7DD69B · `warning` #F5C451 · `danger` #FF6B5B | |
| `stroke.hairline` | #FFF3E6 @ 8 % | `stroke.lightEdge` | #FFF3E6 @ 14 % (obere Lichtkante) |

**Familienpalette:** Koralle #FF7F66, Sonne #F7C548, Salbei #8FD19E, Himmel #5EC2F2, Lavendel #B39DFF, Rose #F59AC0, Petrol #4CCFBF, Sand #D9B38C. Eigene Farbe per `ColorPicker`.

**Typografie:** Dynamic-Type-Textstile.
- Überschriften in New York (`design: .serif`, semibold): `largeTitle` 34, `title2` 22.
- Text in SF Pro: `headline` 17, `body` 17, `subheadline` 15, `footnote` 13, `caption` 12. Uhrzeiten mit `monospacedDigit`.

**Maße:** Abstände 4/8/12/16/20/24/32. Radien: Card 24 (continuous), Chip 12. Touch-Ziele mindestens 44 pt.

**Materialien:**
- Liquid Glass nur für schwebende Elemente: Tab-Bar, Plus, Toolbars.
- Cards sind opak mit feiner Verlaufs-Lichtkante; kein Blur über Listen.
- Perlmutt-Reflex nur statisch auf dem Plus und auf Hero-Elementen.

**Motion:**
- Standard `spring(response: 0.42, dampingFraction: 0.82)`.
- Bei „Bewegung reduzieren“ nur Opazität mit 0,2 s.
- Card→Detail über `matchedTransitionSource` + `.navigationTransition(.zoom)`; Miniatur→Galerie analog.

**Haptik** (`sensoryFeedback`): Plus (impact medium), Einrasten/Auswahl (selection), Abhaken erfolgreich (success). Sonst keine.

**Zustände:** Jeder Screen hat Laden (Skeleton ohne Shimmer bei „Bewegung reduzieren“), Leer, Fehler (mit Retry) und Erfolg.

---

## 9. Umsetzungsphasen

Jede Phase beginnt mit einem **Doku-Check**: aktuelle Apple-, Supabase- oder Microsoft-Seiten zu den genutzten APIs lesen. Jede Phase endet mit Tests, `get_advisors` (security/performance) und einer kurzen Abnahme durch dich.

0. **Fundament**
   - `git init` + `.gitignore` (Secrets, DerivedData). `docs/PLAN.md` (dieser Plan) und ADRs anlegen.
   - Xcode-Projekt anlegen (Deployment Target iOS 27.0, Swift 6): App, Widget-Extension, Tests, FamiliarKit. Build im Simulator (iPhone 17, iOS 27.1).
   - `docs/setup/apple.md`: Team-ID prüfen, App-ID + Capabilities, APNs-Key; Links auf die offizielle Apple-Doku.
   - Design-Tokens + Komponenten-Galerie (Debug-Screen).
   - **Spike S1** (Plus-Tab).
1. **Backend-Basis**
   - Migrationen: Extensions (`pg_cron`, `pg_net`), Enums, profiles, families, members, invites, RLS-Helfer, Policies.
   - RPCs `create_family`, `join_family`, `create_invite`.
   - SQL-Tests der RLS-Matrix.
2. **Auth & Onboarding (iOS)**
   - **Stand 2026-10-20:** aufgeteilt in **2a** (E-Mail-Code, Profil mit Bild, Familien erstellen/beitreten, Einladungscode teilen, Abmelden – umgesetzt), **2b** Google (sobald die Google-Cloud-Clients eingerichtet sind) und **2c** Sign in with Apple + Universal Links (brauchen das bezahlte Apple Developer Program).
   - Zuerst die Anleitungen `docs/setup/supabase-auth.md` (E-Mail-Template, Apple-Provider, Keys) und `docs/setup/google.md` (Google-Cloud-Clients Schritt für Schritt).
   - E-Mail-Code, Apple, Google, Profil + Avatar-Upload.
   - Familie erstellen/beitreten, Einladung teilen (Universal Link + Code), Sitzung halten, Abmelden.
   - `docs/setup/universal-links.md`: AASA-Datei für deine Domain.
3. **Aufgaben-Kern**
   - **Stand 2026-10-21:** umgesetzt (Migration 0007, Startliste, Details, Editor mit Fotos/Kamera, Bildansicht, Undo-Hinweis, Realtime-Hinweise). Regeln: [ADR 0007](decisions/0007-task-rules.md).
   - DB: tasks, assignees, images + Storage-Policies; RPCs create, update, complete, uncomplete, delete; Sichtbarkeit durchgesetzt.
   - UI: Startliste, Detail, Editor (klein-display-tauglich), PhotosPicker + Kamera (`UIImagePickerController`-Wrapper), Galerie.
   - Realtime-Broadcast.
4. **Verlauf**
   - **Stand 2026-10-21:** umgesetzt (Verlauf-Ansicht mit Wiederherstellen, Undo-Hinweis, tägliche 30-Tage-Bereinigung per `pg_cron` → Edge Function `purge-history` mit Einmal-Token).
   - View, Wiederherstellen, Undo-Banner, 30-Tage-Löschung (Cron + `storage-purge`).
5. **Wiederholungen**
   - **Stand 2026-10-21:** umgesetzt (Migration 0009, Wiederholung im Editor, Geltungsbereich beim Bearbeiten und Löschen, Serien-Eintrag im Verlauf, Erzeugung alle 5 Minuten per `pg_cron`, Projektion für den Kalender). Regeln: [ADR 0008](decisions/0008-recurrence.md).
   - Serien, Generator, Projektion, Scope-Dialoge, Serien-Löschen/-Wiederherstellen; Monatstag-Regel (E2).
6. **Kalender**
   - **Stand 2026-10-21:** umgesetzt (Monatsraster ab Montag mit Wischen und Pfeil-Knöpfen, Punkte in Familienfarbe – voll für Aufgaben, blass für geplante Serientermine aus `project_series_occurrences` –, Tagesliste mit Uhrzeit, Erledigt-Status und „Geplant“; `ExternalEventRepository` als anbieterunabhängige Schnittstelle, liefert bis Phase 8 nichts).
   - Monatsansicht mit Aufgaben + Projektionen.
   - Anbieter-Abstraktion im Client.
7. **Push & Live Activities**
   - **Spike S2** zuerst.
   - devices, Outbox, `push-dispatch`.
   - Widget-Extension, `CompleteTaskIntent`, Push-to-Start, Abgleich beim Vordergrund.
8. **Outlook**
   - Zuerst `docs/setup/microsoft.md`: Entra-App-Registrierung Schritt für Schritt mit Screens/Feldern laut Microsoft-Doku.
   - OAuth-Functions, Vault, Kalenderauswahl, Filter-Setup, `outlook-sync`.
   - **S3: realer Testtermin.**
9. **Familienrechte & Profil**
   - **Stand 2026-10-21:** umgesetzt (Migration 0010, Edge Function `account-delete`). E4 entschieden und erweitert: Admins schalten für Mitglieder ein/aus – einladen, Familie bearbeiten, Mitglieder entfernen **und** Aufgaben anlegen, bearbeiten, löschen/wiederherstellen (Abweichung vom Guide auf Wunsch des Nutzers); Abhaken und Rückgängig bleiben für alle erlaubt. Mitglieder zu Admins machen/entfernen, Familie bearbeiten/löschen, Konto löschen.
   - Admin-Schalter (E4), Mitglieder verwalten, Konto löschen.
10. **Qualität & Release-Vorbereitung**
    - VoiceOver, Dynamic Type bis AX5, „Bewegung reduzieren“/„Transparenz reduzieren“/„Kontrast erhöhen“.
    - Instruments (Hitches, SwiftUI), iPhone 17e/SE-Größen, Privacy Manifest.
    - Backups/PITR prüfen (Pro-Plan), Security-Advisors.
    - SIWA-Token-Widerruf bei Kontolöschung.

---

## 10. Offene Entscheidungen (mit Vorschlag)

**Bereits entschieden (2026-10-20):**
- **F1:** Der Ersteller sieht eigene Aufgaben immer.
- **Mindestversion:** iOS 27.
- **Supabase-Projekt** `ldeouecoaqyfvubhrjei` = Dev-Umgebung. Vor dem Release kommt ein separates Produktionsprojekt.
- **Einladungen:** Universal Links über deine Domain.

**Noch offen, Vorschläge gelten, solange du nichts anderes sagst (Bestätigung vor der jeweiligen Phase):**
- **E2 – Fehlender Monatstag (z. B. 31.):** **entschieden 2026-10-21:** auf den letzten Tag des Monats verschieben; fallen mehrere Tage auf denselben Termin (30. + 31. im Februar), entsteht nur ein Vorkommen.
- **E3 – Erste Erinnerung ohne Uhrzeit:**
  - *Ohne Datum:* 24 h nach Zuweisung, dann alle 24 h.
  - *Nur Datum:* Benachrichtigung + Live Activity um 08:00 Ortszeit (Aufgaben-Zeitzone) am Tag selbst; liegt das Datum heute oder in der Vergangenheit, sofort. Erste Erinnerung 24 h später, dann alle 24 h.
- **E4 – Admin-Rechte:** drei Schalter, siehe Abschnitt 6.
- **E5 – Live Activity nach dem 8-h-Limit:** Vorschlag: kein automatischer Neustart, die Tageserinnerung per Push reicht.
- **E6 – „Relevante Änderungen“:** Vorschlag siehe Abschnitt 5. Änderungen an Beschreibung oder Bildern lösen keinen Push aus.

---

## 11. Was du selbst einrichten musst (Werte nie in den Chat)

Für jeden Dienst gibt es eine Schritt-für-Schritt-Anleitung in `docs/setup/` (apple, supabase-auth, google, microsoft, universal-links), jeweils mit Links zur offiziellen Doku. Sie wird in der Phase erstellt, in der sie gebraucht wird. Secrets werden nur im Supabase-Dashboard (Edge Functions → Secrets) bzw. in der gitignored `Secrets.xcconfig` eingetragen.

- **Apple Developer Program:**
  - Team-ID und Bundle-ID.
  - Capabilities: Push, Sign in with Apple, ggf. Associated Domains.
  - APNs-Key (.p8) → Secrets `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`.
- **Supabase-Dashboard:**
  - Neue API-Keys erzeugen.
  - E-Mail-OTP-Template, Apple-/Google-Provider.
  - Für Produktion eigener SMTP.
- **Google Cloud:** iOS- und Web-OAuth-Client.
- **Microsoft Entra:**
  - App-Registrierung (Konten in beliebigem Verzeichnis + persönliche Microsoft-Konten).
  - Redirect `https://ldeouecoaqyfvubhrjei.supabase.co/functions/v1/outlook-oauth-callback`.
  - Delegierte Rechte `Calendars.ReadBasic`, `offline_access`, `openid`, `email`.
  - Secrets `MS_CLIENT_ID`, `MS_CLIENT_SECRET` (später Zertifikat empfohlen).
- **Optional:** Domain für Universal Links (Einladungslinks).

---

## 12. Verifikation

- **Datenbank:**
  - Pro Migration SQL-Tests über `execute_sql` in `begin … rollback`, mit simulierten Nutzern (`set local role authenticated; set local request.jwt.claims`).
  - RLS-Matrix: Nicht-Mitglied, Mitglied, Zugewiesener, Ersteller × Sichtbarkeit all/assigned_only, für Tasks, Bilder, Verlauf, Outlook-Daten.
  - Generator zweimal laufen lassen ergibt identische Anzahl. Monatstag-Grenzfälle, Sommerzeitwechsel.
  - Danach `get_advisors`.
- **iOS:**
  - `xcodebuild test -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.1'`.
  - Unit-Tests in FamiliarKit: Sortierung, Statuslogik, Farbabstand, Payload-Decoding, ContentState unter 4 KB.
  - UI-Tests: Onboarding, Aufgabe anlegen/abhaken/rückgängig.
  - Sichtprüfung über das iOS-Simulator-Tool mit Screenshots, auch mit großer Schrift und „Bewegung reduzieren“.
- **Push/Live Activities:**
  - Simulator-Push (Sandbox) und `xcrun simctl push` für Payload-Formate.
  - Push-to-Start → Token-Registrierung → Update → Ende.
  - Szenarien: Abhaken in beiden Modi, Startzeit ändern, Löschen. Ergebnis immer gegen den DB-Zustand prüfen.
- **Outlook:**
  - Realer Testtermin (Organisator = Konto A, Teilnehmer = du + zweite Adresse).
  - Felder prüfen, Termin ändern und absagen, nächster Sync zeigt die Änderung.
  - Ergebnis dokumentieren.
- **End-to-End:** zwei Testnutzer in zwei Simulatoren, zwei Familien mit ähnlichen Farben. Prüfen: zusammengeführte Liste, Farbvariation, Sichtbarkeit „nur zugewiesene“.
