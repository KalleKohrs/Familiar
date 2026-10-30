# AGENTS.md – Arbeitsanleitung für KI-Assistenten (und Menschen)

Familiar ist ein deutschsprachiger Familienplaner für iOS: Aufgaben anlegen, zuweisen (auch reihum), abhaken, erinnern, Bilder, Wiederholungen, Kalender, Verlauf, mehrere Familien, Widgets, Siri, Live Activities, optional Outlook-Termine. Backend: Supabase. Stand: 2026-10-30, Version 0.1.0 (Build 5) bei Apple zur Prüfung eingereicht.

**Lies zuerst:** [docs/architecture.md](docs/architecture.md) (Aufbau), [docs/LAUNCH-TODO.md](docs/LAUNCH-TODO.md) (was offen ist), die ADRs in [docs/decisions/](docs/decisions/) für das Thema, an dem du arbeitest.

## Zusammenarbeit

- **Sprache:** Oberfläche, Texte, Doku und Code-Kommentare auf **Deutsch** (du/dein, ruhig, ohne Fachjargon). Der Projektinhaber ist kein Entwickler: Antworten einfach erklären, Schritte für ihn als nummerierte Anleitung.
- **Offizielle Doku zuerst.** Vor jeder Integration die Apple-/Supabase-/Microsoft-/Google-Doku prüfen; keine erfundenen APIs, Werte oder Schlüssel.
- **Nur kostenlose Dienste** (Supabase Free, Netlify, Resend, Backblaze B2). Keine Analyse-, Werbe- oder Tracking-SDKs.
- **Keine Übergangslösungen:** so bauen, wie es zum App-Store-Start sein muss. Was der Inhaber selbst tun muss, kommt auf [docs/LAUNCH-TODO.md](docs/LAUNCH-TODO.md).
- **Keine Geheimnisse** in Repo, Chat oder Logs. `ios/Config/Local.xcconfig`, `Secrets.xcconfig`, `*.p8`, `.env` sind ignoriert. Server-Secrets nur als Supabase-Edge-Function-Secrets. Der App-Client nutzt nur den Publishable Key.
- Nach außen wirkende Schritte (Deploy, Migration auf dem Server, E-Mails, Veröffentlichungen) vorher mit dem Inhaber abstimmen.

## Projekt starten

1. `ios/Config/Local.example.xcconfig` → `ios/Config/Local.xcconfig` (Team-ID, Bundle-ID; siehe [docs/setup/apple.md](docs/setup/apple.md)).
2. `ios/Familiar.xcodeproj` in Xcode 27 öffnen, Scheme **Familiar**, iPhone-Simulator mit iOS 27.
3. Ohne Server testen: Startargumente (Scheme › Run › Arguments) – siehe unten.

### Startargumente (nur Debug)

| Argument | Wirkung |
|---|---|
| `-FamiliarInMemoryBackend` | Backend ohne Netz (`ios/Familiar/Debug/InMemoryBackend.swift`) |
| `-FamiliarInMemoryScenario signedOut \| ready \| showcase` | Startzustand: abgemeldet / „Familie Kohrs“ mit Testaufgaben / Vorführdaten „Familie Berger“ für App-Store-Bilder |
| `-FamiliarOpenURL <url>` | Universal Link simulieren (z. B. `https://familiar-app.de/join/TEST-2345`) |
| `-appearance light \| dark \| system` | Darstellung erzwingen (`@AppStorage("appearance")`) |

## Befehle

```bash
# App bauen und alle App-/UI-Tests (17 UI-Tests, ca. 8–10 min)
xcodebuild test -project ios/Familiar.xcodeproj -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'

# Unit-Tests des Pakets (Kernlogik, ca. 100 Tests)
cd ios/Packages/FamiliarKit && xcodebuild test -scheme FamiliarKit-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'

# Nur die Barrierefreiheits-Prüfung (Apple performAccessibilityAudit, hell + dunkel)
xcodebuild test -project ios/Familiar.xcodeproj -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -only-testing:FamiliarUITests/AccessibilityAuditUITests

# Website-Textseiten aus docs/legal/*.md erzeugen (danach Ordner website/ bei Netlify hochladen)
python3 tools/build-website.py

# Open-Source-Lizenzen für die App neu erzeugen (nach Paket-Updates; braucht einen Build)
python3 tools/generate-licenses.py <DerivedData>/SourcePackages/checkouts

# App-Icon neu rendern (Varianten Standard/Dunkel/Getönt)
swiftc -O tools/render-app-icon.swift -o /tmp/render && /tmp/render ios/Familiar/Resources/Assets.xcassets/AppIcon.appiconset
```

`swift test` im Paket funktioniert **nicht** (supabase-swift verlangt macOS 13) – Paket-Tests immer über `xcodebuild` im Simulator.

## Datenbank (Supabase, Projekt `ldeouecoaqyfvubhrjei`)

**Rollen der Projekte (seit 2026-10-29):** `ldeouecoaqyfvubhrjei` („Familiar“) ist die **Produktion** (App-Config `ios/Config/Supabase.xcconfig`, TestFlight, App Store; Prüf-Konto dort). `fhyfjxzctemxqewedqiy` („familiar-prod") ist trotz des Namens die **Entwicklung** (Schema und Functions, sonst unkonfiguriert). Der Supabase-MCP erreicht nur die Produktion – Tests nur in `begin … rollback`.

- **Migrationen** in `supabase/migrations/NNNN_name.sql`, fortlaufend nummeriert. Eingespielte Migrationen nie ändern – neue anlegen. Stand und Art der Einspielung: Tabelle oben in [docs/data-model.md](docs/data-model.md).
- **Einspielen:** Ohne `delete`/`drop` geht es über das Supabase-MCP-Werkzeug `apply_migration`. **Mit `delete` oder `drop`** (auch in Funktionsrümpfen) lehnt das Werkzeug ab: Dann legt der Inhaber die Datei im Supabase-SQL-Editor ein und führt sie aus; danach Zeile in `supabase_migrations.schema_migrations` nachtragen und in `docs/data-model.md` vermerken. Nie mit Platzhalter-SQL „ausprobieren“.
- **Stand:** Migrationen bis `0020_activity_end_race.sql` sind eingespielt (0020: Ende einer Live Activity nach Terminänderung trifft keine neuere Activity); davor `0019_clear_history.sql` (0019: „Verlauf löschen“ für Admins, `clear_history()`; Tests `supabase/tests/0011_clear_history.sql` grün). `review-sign-in` und `push-dispatch` sind neu deployt.
- **SQL-Tests** in `supabase/tests/*.sql` laufen in `begin … rollback` (nichts bleibt zurück) und geben eine Ergebniszeile „alle grün“ bzw. die Fehler aus – im SQL-Editor oder per MCP `execute_sql`.
- **Regeln:** RLS auf jeder Tabelle; Schreiben nur über RPCs mit `security definer`, `set search_path = ''`, `private.require_uid()` und Rechteprüfung; Fehler über `private.raise_app_error('<schluessel>')` – neue Schlüssel auch in `AppErrorKey` (`FamiliarCore/FamiliarError.swift`) eintragen. Nach Schemaänderungen die Supabase-Advisors (Sicherheit, Leistung) prüfen.
- **Mitteilungen:** Alle Aufträge laufen über `private.enqueue_notification` (legt nur für bestehende Profile an – wichtig für die Kontolöschung). Sammeländerungen (viele Zuweisungen auf einmal) setzen `set_config('familiar.bulk_change', 'on', true)`, stellen den vorherigen Wert danach wieder her und melden selbst gesammelt; die Trigger senden dann keine Einzelmitteilungen. Inhalte nur an aktuelle Mitglieder (`push_claim_jobs.is_member`).
- **Austritt** (Verlassen, Entfernen, Kontolöschung) räumt der Trigger `family_members_departure` auf; neue Tabellen mit Personenbezug in einer Familie dort mitdenken.
- **Gleiche Regel an zwei Stellen:** Wiederholung (`private.series_dates` ↔ `RecurrenceRule`) und Reihum (`private.rotation_index`/`rotation_assignee` ↔ `RotationRules`) müssen identisch bleiben – Tests in `supabase/tests/0006_recurrence.sql`, `0010_rotation_nudges.sql` und `FamiliarCoreTests`.
- **Edge Functions** in `supabase/functions/<name>/` (Deno). Deploy über MCP `deploy_edge_function` mit allen Dateien der Function. Cron-Functions (`verify_jwt = false`) prüfen Einmal-Tokens aus `private.cron_tokens`.

## Code-Konventionen (iOS)

- Swift 6, strikte Nebenläufigkeit, `MainActor` als Standard-Isolation in App und Extension.
- Domänenlogik UI-frei in `FamiliarCore` und dort testen; Views dünn halten.
- **Farben, Schriften, Abstände nur über `FamiliarDesign`-Tokens.** `FamiliarColor.accent` = orange **Schrift/Symbol**, `accentFill` = orange **Fläche** (mit `onAccent`). Jede Farbe hat hell/dunkel und „Kontrast erhöhen“. Neue Bildschirme: `familiarScreenBackground()`, Karten `familiarCard()`.
- Helle Schrift auf dunklen Schleiern über Bildern: `FamiliarColor.onScrim` auf `scrim` (nicht `textPrimary`, das ist im Hellen dunkel).
- **Widgets:** nur über `WidgetSync` schreiben; `activate(userID:)` bei Anmeldung, `clear()` bei jeder Abmeldung (verdrahtet über `SessionStore.onAccountChange`).
- **Barrierefreiheit ist Pflicht:** VoiceOver-Labels, Dynamic Type bis zur größten Stufe (bei Bedarf untereinander statt nebeneinander, siehe Verlauf/Kalender), 44-pt-Tippflächen, „Bewegung reduzieren“. Der UI-Test `AccessibilityAuditUITests` muss grün bleiben.
- Neue Daten, die die App speichert oder sendet → Datenschutzerklärung (`docs/legal/datenschutz.md`), Verarbeitungsverzeichnis (`docs/legal/intern/`), ggf. `PrivacyInfo.xcprivacy` und App-Store-Angaben (`docs/legal/app-store.md`) anpassen.
- Neue Schreibvorgänge: zuerst RPC + SQL-Test, dann Repository (`FamiliarData`), `InMemoryBackend` gleich verhalten lassen, dann UI.
- Rechtslinks in der App: `LegalLink` (`ios/Familiar/Features/Legal/LegalViews.swift`).

## Wo was steht

| Thema | Datei |
|---|---|
| Ursprüngliche fachliche Vorgaben | [docs/guide.txt](docs/guide.txt) |
| Datenmodell, Migrationsstand | [docs/data-model.md](docs/data-model.md), [docs/rls-matrix.md](docs/rls-matrix.md) |
| Entscheidungen | [docs/decisions/](docs/decisions/) (u. a. 0003 Schreiben per RPC, 0005 Push, 0007 Erledigungsregeln, 0008 Wiederholung, 0009 Sicherung, 0010 Reihum/Widgets/Erinnern/Siri) |
| Design | [docs/design-system.md](docs/design-system.md), [docs/design/light-mode.md](docs/design/light-mode.md) |
| Einrichtung externer Dienste | [docs/setup/](docs/setup/) |
| Rechtstexte und Prüfbericht | [docs/legal/](docs/legal/) (`rechtscheck.md`, `intern/verarbeitungsverzeichnis.md`) |
| App-Store-Texte, Bilder | [docs/legal/app-store.md](docs/legal/app-store.md), `docs/app-store/screenshots/` |
| Website | `website/` ([website/README.md](website/README.md)); Textseiten nie direkt ändern, sondern `docs/legal/*.md` + `tools/build-website.py` |

## Stolpersteine

- **App Intents nie in ein Swift-Paket legen:** `CompleteTaskIntent` liegt in `ios/Shared/` (gehört zu App **und** Widget-Extension). Liegt eine Aktion in einem Paket, meldet iOS in TestFlight/App Store „There is no metadata for … in de.kohrs.familiar“ und der Haken in der Live Activity tut nichts – in Xcode-Builds fällt das nicht auf. Gilt auch für neue Intents, die aus Widgets oder Live Activities aufgerufen werden. Prüfen mit Archive: `Metadata.appintents/extract.actionsdata` der App muss den Intent mit Modulnamen `Familiar` enthalten.
- **Diagnose:** Profil › „Diagnose (Testversion)“ (nur Xcode/TestFlight) zeigt das Protokoll `FamiliarDiagnostics` (Haken, Geräte-Anmeldung). iOS-Systemmeldungen zu Intents: Mac-App „Konsole“ › Gerät wählen › Suche „intent“.
- **Apple-Konto:** Das Developer-Programm läuft auf **Sven Olaf Kohrs** (neue Apple-ID). Nach der Freischaltung die neue Team-ID in `Local.xcconfig` und `website/.well-known/apple-app-site-association` eintragen; Bundle-ID `de.kohrs.familiar` und App Group `group.de.kohrs.familiar` beim ersten Signieren prüfen.
- **Simulator:** Taps und Screenshots hängen manchmal einige Sekunden hinterher – lieber kurz warten als doppelt tippen. Text per Zwischenablage einfügen kann Umlaute verfälschen.
- **Speicherplatz** auf dem Entwicklungs-Mac ist knapp: Build-Ordner und große Simulatoren nach Gebrauch löschen bzw. zurücksetzen.
- **Supabase Free** pausiert Projekte nach 7 Tagen ohne Aktivität.
- **Prüf-Zugang für Apple:** Edge Function `review-sign-in` mit Secrets `REVIEW_EMAIL` (nicht erratbar) und `REVIEW_CODE` (10 Stellen); höchstens 10 Fehlversuche pro Stunde (atomar gezählt); nach der Freigabe `REVIEW_CODE` löschen.
- **Prüfberichte:** Ergebnisse der Rechts- und Sicherheitsprüfung inkl. zweiter, unabhängiger Durchsicht stehen in [docs/legal/rechtscheck.md](docs/legal/rechtscheck.md).
