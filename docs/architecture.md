# Architektur

Überblick über Bausteine und Verantwortlichkeiten (Stand 2026-10-23). Begründungen: [decisions/](decisions/) (ADRs), ursprünglicher Plan: [PLAN.md](PLAN.md) (historisch, teils überholt). Einstieg für neue Mitarbeitende und KI-Assistenten: [../AGENTS.md](../AGENTS.md).

## Leitlinien

- **Die Datenbank ist maßgeblich.** Push-Mitteilungen, Live Activities, Widgets und Realtime-Ereignisse sind nur Hinweise; die App liest den Status immer aus Supabase nach.
- **Autorisierung auf dem Server.** RLS auf allen Tabellen; Schreiben ausschließlich über geprüfte RPCs (`security definer`, `search_path = ''`, ADR 0003). UI-Verstecken ist keine Sicherheit.
- **Familien- und persönliche Daten getrennt.** Outlook-Verbindungen, Tokens und importierte Termine gehören genau einem Nutzer.
- **Datensparsam und kostenlos.** Keine Analyse-/Werbe-SDKs; nur kostenlose Tarife (Supabase Free, Netlify, Resend, Backblaze B2); einzige Kosten: Apple-Programm und Domain.
- **Kleine, testbare Schritte.** Unit-, UI- und SQL-Tests; Supabase-Advisors nach Schemaänderungen.

## iOS

```
Familiar (App, SwiftUI, iOS 27, Swift 6, MainActor als Standard-Isolation)
├── App/          Einstieg (FamiliarApp), RootView/RootTabView, eigene Glas-Tab-Leiste, Stores
│                 SessionStore (Anmeldung, Profil, Familien), TaskStore (Aufgaben, Verlauf, Rückgängig,
│                 Erinnern), OutlookStore, Appearance (System/Hell/Dunkel)
├── Features/     Auth, Onboarding, Tasks, TaskEditor, Calendar, History, Families, Profile,
│                 Notifications, Legal (Rechtslinks, Lizenzen), Siri (App Intents / App Shortcuts)
├── Services/     NotificationStore (APNs, Live Activities), WidgetSync, AvatarImages, TaskImages
├── Debug/        InMemoryBackend (ohne Netz, Szenarien für UI-Tests und App-Store-Bilder)
└── Resources/    Assets, PrivacyInfo.xcprivacy, Licenses.json (erzeugt)

FamiliarWidgets (Widget-Extension)
├── TaskLiveActivityWidget   Live Activity (Sperrbildschirm, Dynamic Island), Abhaken per Intent
└── TodayWidget              „Heute“ (Homescreen S/M/L, Sperrbildschirm), liest App-Group-Schnappschuss

FamiliarKit (lokales Swift-Paket)
├── FamiliarCore      UI-freie Domänenlogik und Modelle: Aufgaben-/Serien-/Reihum-Regeln, Kalender,
│                     Verlauf, Entwurf (TaskDraft), Widget-Schnappschuss, Repository-Protokolle, FamiliarError
├── FamiliarData      Supabase-Implementierung (supabase-swift 2.x), Google-Anmeldung
├── FamiliarDesign    Tokens (Farben hell/dunkel + Kontrast, Schrift, Abstände, Bewegung), Komponenten, Galerie
└── FamiliarActivity  Live-Activity-Attribute, CompleteTaskIntent (läuft im App-Prozess)
```

- **Daten in der App:** Stores (`@Observable`) im SwiftUI-Environment; Repositories über `AppDependencies` (Supabase oder `-FamiliarInMemoryBackend`).
- **Widgets:** Die App schreibt nach jedem Laden einen kleinen Schnappschuss in die App Group (`group.<Bundle-ID>`), das Widget liest nur. Abhaken über `CompleteTaskIntent` (`LiveActivityIntent` → App-Prozess).
- **Siri:** App Intents im App-Target (`FamiliarShortcuts.swift`), Zugriff über `IntentEnvironment`, nur bei entsperrtem Gerät.
- **Erscheinungsbild:** hell und dunkel; Farben nur über `FamiliarColor`-Tokens (`accent` = orange Schrift, `accentFill` = orange Fläche).
- **Projektdatei:** synchronisierte Ordner – neue Dateien im Ordner gehören automatisch zum Target.

## Backend (Supabase, Projekt `ldeouecoaqyfvubhrjei`, Region Frankfurt)

| Baustein | Aufgabe |
|---|---|
| Postgres + RLS | Profile, Familien, Mitgliedschaften, Einladungen, Aufgaben, Zuweisungen, Serien (inkl. Reihum), Verlauf, Geräte, Mitteilungs-Aufträge, Outlook-Metadaten. Schema: [data-model.md](data-model.md), Rechte: [rls-matrix.md](rls-matrix.md) |
| RPCs (`security definer`) | Alle Schreibvorgänge mit Rechteprüfung und Fehlerkatalog (`private.raise_app_error`, Schlüssel im `hint`) |
| Storage (privat) | Aufgaben- und Profilbilder, signierte URLs |
| Realtime (privater Broadcast) | Kanal `user:<uid>`, nur IDs → Client lädt nach |
| `pg_cron` / `pg_net` | Serien-Vorkommen erzeugen, Mitteilungen planen/versenden, Outlook-Sync, 30-Tage-Bereinigung, nächtliche Sicherung |
| Edge Functions | `push-dispatch` (APNs), `outlook-oauth-start`/`-callback`/`outlook-sync`, `purge-history`, `account-delete`, `review-sign-in` (Apple-Prüfung), `backup`/`backup-restore` |
| Vault | Outlook-Refresh-Tokens |

## Externe Dienste

- **APNs** (Token-Auth, HTTP/2 direkt aus der Edge Function): Mitteilungen und Live-Activity-Pushes.
- **Microsoft Graph** (`Calendars.ReadBasic`, nur lesend, Zertifikat statt Secret): Outlook-Kalender.
- **Sign in with Apple / Google**: native Anmeldung, Token-Austausch über Supabase Auth; Widerruf beim Löschen.
- **Resend**: E-Mail-Versand der Anmelde-Codes (SMTP für Supabase Auth).
- **Backblaze B2** (EU): verschlüsselte nächtliche Sicherung (ADR 0009).
- **Netlify**: Website familiar-app.de inkl. Formulare Kontakt und Meldung (DSA).
