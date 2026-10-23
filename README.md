# Familiar

Familienplaner für iOS: Aufgaben anlegen, Personen zuweisen, Bilder anhängen, Wiederholungen festlegen und den Erledigungsstatus pro Person sehen – über mehrere Familien hinweg. Persönliche Outlook-Termine erscheinen nur lesend und nur für die Person, die ihren Kalender verbunden hat.

- **Für Entwicklerinnen und KI-Assistenten: [AGENTS.md](AGENTS.md)** (Start, Befehle, Regeln, Stolpersteine)
- Fachliche Grundlage: [docs/guide.txt](docs/guide.txt)
- Ursprünglicher technischer Plan (historisch): [docs/PLAN.md](docs/PLAN.md)
- Was noch zu tun ist: [docs/LAUNCH-TODO.md](docs/LAUNCH-TODO.md)
- Rechtstexte und Prüfbericht: [docs/legal/](docs/legal/)
- Architektur: [docs/architecture.md](docs/architecture.md)
- Design-System „Fluid Ambient“: [docs/design-system.md](docs/design-system.md)
- Entscheidungen (ADRs): [docs/decisions/](docs/decisions/)
- Einrichtung externer Dienste: [docs/setup/](docs/setup/)

## Aufbau

| Ordner | Inhalt |
|---|---|
| `ios/Familiar.xcodeproj` | Xcode-Projekt (App, Live-Activity-Extension, Tests) – Deployment Target iOS 27 |
| `ios/Familiar/` | App-Code (SwiftUI) |
| `ios/FamiliarWidgets/` | Widget-Extension: Live Activities und Widgets „Heute“ |
| `ios/Packages/FamiliarKit/` | Lokales Swift-Paket: `FamiliarCore`, `FamiliarData`, `FamiliarDesign`, `FamiliarActivity` |
| `ios/Config/` | xcconfig-Dateien und Info.plists |
| `supabase/` | Migrationen, SQL-Tests, Edge Functions |
| `website/` | Website familiar-app.de (Netlify) |
| `tools/` | Website-, Lizenz- und Icon-Generatoren |

## Lokal starten

1. `ios/Config/Local.example.xcconfig` nach `ios/Config/Local.xcconfig` kopieren und Team-ID sowie Bundle-ID eintragen (siehe [docs/setup/apple.md](docs/setup/apple.md)). Ohne diese Datei baut das Projekt für den Simulator mit einer Platzhalter-Bundle-ID.
2. `ios/Familiar.xcodeproj` in Xcode 27 öffnen, Scheme **Familiar** wählen, iPhone-Simulator mit iOS 27 starten.

Tests auf der Kommandozeile:

```bash
xcodebuild test -project ios/Familiar.xcodeproj -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'
```

```bash
cd ios/Packages/FamiliarKit && xcodebuild test -scheme FamiliarKit-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'
```

## Sicherheit

Keine Geheimnisse ins Repository: `Local.xcconfig`, `Secrets.xcconfig`, `.p8`-Schlüssel und `.env`-Dateien stehen in `.gitignore`. Der App-Client verwendet ausschließlich den Supabase-Publishable-Key; Server-Geheimnisse liegen in den Edge-Function-Secrets bzw. im Supabase Vault.
