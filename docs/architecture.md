# Architektur

Überblick über Bausteine und Verantwortlichkeiten. Details und Begründungen: [PLAN.md](PLAN.md) und [decisions/](decisions/).

## Leitlinien

- **Die Datenbank ist maßgeblich.** Push-Mitteilungen, Live Activities und Realtime-Ereignisse sind nur Hinweise; die App liest den Status immer aus Supabase nach.
- **Autorisierung auf dem Server.** RLS auf allen exponierten Tabellen; Schreiben ausschließlich über geprüfte RPCs. UI-Verstecken ist keine Sicherheit.
- **Familien- und persönliche Daten getrennt.** Outlook-Verbindungen, Tokens und importierte Termine gehören genau einem Nutzer.
- **Kleine, testbare Schritte.** Jede Phase endet mit Tests, Advisor-Prüfung und Abnahme.

## iOS

```
Familiar (App, SwiftUI, iOS 27)
├── App/          Einstieg, Hauptnavigation (TabView ohne System-Leiste + eigene FloatingTabBar mit Plus-Button)
├── Features/     Aufgaben, Editor, Galerie, Kalender, Verlauf, Familien, Profil
└── Services/     Push, Live Activities, Deep Links (ab Phase 2/7)

FamiliarWidgets (Widget-Extension)
└── Live Activity: Sperrbildschirm + Dynamic Island

FamiliarKit (lokales Swift-Paket)
├── FamiliarCore      UI-freie Domänenlogik: Farben/OKLab, Familienfarb-Auflösung, Namen, Enums
├── FamiliarDesign    Tokens (Farben, Schrift, Abstände, Bewegung) und Komponenten
├── FamiliarActivity  TaskActivityAttributes (gemeinsam für App und Extension)
└── FamiliarData      Supabase-Implementierung der Repositories (supabase-swift 2.55.x)
```

- **FamiliarCore** enthält neben der Domänenlogik die Modelle (Profil, Familie, Mitglieder, Einladungen),
  die Repository-Protokolle (`AuthService`, `ProfileRepository`, `FamilyRepository`) und `FamiliarError`.
- **FamiliarData** setzt die Protokolle mit Supabase um (Auth, PostgREST-RPCs, Storage) und übersetzt
  SDK-Fehler; nur Schlüssel aus dem Fehlerkatalog der RPCs werden als App-Fehler ausgewertet.
- **App:** `SessionStore` (Anmeldestatus, Profil, Familien, Onboarding-Schritt) liegt im SwiftUI-Environment;
  `RootView` wählt danach Anmeldung, Onboarding oder Hauptansicht. In Debug-Builds ersetzt das Startargument
  `-FamiliarInMemoryBackend` Supabase durch ein Backend ohne Netzwerk (UI-Tests, Previews).

**Konventionen**

- Swift 6, strikte Nebenläufigkeit; App- und Extension-Targets mit `MainActor` als Standard-Isolation.
- Zustand in `@Observable`-Stores pro Feature; Abhängigkeiten über das SwiftUI-Environment.
- Nur dunkles Erscheinungsbild in V1; alle Farben und Schriften über `FamiliarDesign`-Tokens.
- Projektdatei nutzt synchronisierte Ordner: neue Dateien im jeweiligen Ordner werden automatisch Teil des Targets.

## Backend (Supabase)

| Baustein | Aufgabe |
|---|---|
| Postgres + RLS | Profile, Familien, Mitgliedschaften, Einladungen, Aufgaben, Zuweisungen, Serien/Vorkommen, Verlauf, Geräte, Outlook-Metadaten |
| RPCs (`security definer`) | Alle Schreibvorgänge mit expliziten Rechteprüfungen |
| Storage (privat) | Aufgabenbilder und Profilbilder; Zugriff über signierte URLs |
| Realtime (privater Broadcast) | Kanal `user:<uid>`, Payload nur IDs → Client lädt nach |
| `pg_cron` / `pg_net` | Vorkommen erzeugen, Erinnerungen planen, Push-Versand und Outlook-Sync anstoßen, 30-Tage-Bereinigung |
| Edge Functions | APNs-Versand, Outlook-OAuth und -Sync, Storage-Bereinigung, Konto löschen |
| Vault | Outlook-Refresh-Tokens, Cron-Secret |

## Externe Dienste

- **APNs** (Token-Auth, HTTP/2): Mitteilungen und Live-Activity-Pushes.
- **Microsoft Graph** (`Calendars.ReadBasic`, nur lesend): persönliche Outlook-Kalender.
- **Sign in with Apple / Google**: native Anmeldung, Token-Austausch über Supabase Auth.
