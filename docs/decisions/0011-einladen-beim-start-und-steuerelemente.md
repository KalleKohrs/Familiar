# ADR 0011: Einladen gleich beim Start und Steuerelemente

- **Status:** umgesetzt auf Branch `claude/neue-funktionen-e0e9e4` (2026-11-11), noch nicht in `main`.
- **Kontext:** Die Roadmap ([roadmap/vorschlaege.md](../roadmap/vorschlaege.md)) nennt zwei Lücken: Wer eine Familie anlegt, bleibt oft allein (Einladen war tief im Profil versteckt), und die App ist im Alltag mehrere Handgriffe entfernt. Der Inhaber hat Funktion 1 („Einladen gleich beim Start“) und 6 („Steuerelemente“) gewählt. Beide brauchen **kein Backend** (keine Migration, keine Edge Function) und speichern **keine neuen Daten**.

## 1. Einladen gleich beim Start

- **Nach dem Anlegen der ersten Familie** öffnet die App einmal das Blatt „Wen holst du dazu?“ (`InviteFamilySheet`). „Einladung teilen“ erzeugt erst dann den Code (`create_invite`, 7 Tage gültig) und öffnet das System-Teilen-Blatt; „Später“ überspringt. Kein Code „auf Vorrat“. Bei weiteren Familien (aus der laufenden App) gibt es das Blatt nicht – dort bleibt „Einladen“ in den Familiendetails.
- **Hinweiskarte auf der Startseite** (`InviteHintSection`), solange man in einer Familie allein ist und einladen darf (`FamilyMembership.suggestsInvite`): „Hol deine Familie dazu“ mit „Einladen“ und „Später“. „Später“ blendet sie für diese Familie dauerhaft aus; gemerkt wird nur lokal auf dem Gerät (`UserDefaults`, kein Server).
- **Text:** `InviteMessage.text` (Link `familiar-app.de/join/<Code>`, Code, Gültigkeit, Hinweis auf den kostenlosen Download). Der Link öffnet die App oder die Ausweichseite mit dem Weg in den App Store. `FamilyDetailView` nutzt denselben Text.
- Umsetzung ohne neue Phase im `OnboardingFlow`: `SessionStore.invitePromptFamilyID` wird beim Anlegen der ersten Familie gesetzt und im Hauptbildschirm als Blatt gezeigt. Ein vorgemerkter Beitrittslink hat Vorrang (kein zweites Blatt).

## 6. Steuerelemente (iOS „Controls“)

- **„Neue Aufgabe“** (`NewTaskControl`) öffnet Familiar mit dem Formular. **„Heute offen“** (`OpenTodayControl`) zeigt die Anzahl der heute offenen, dir zugewiesenen Aufgaben (nur die Zahl, keine Titel) und öffnet die App. Beide sind im Kontrollzentrum, als Sperrbildschirm-Taste und für den Action-Button wählbar.
- **Daten:** Wie die Heute-Widgets nur der Schnappschuss im App-Group-Container (`WidgetSnapshotStore`) – kein Konto, kein Netz in der Extension. Die App lädt das Steuerelement neu, wenn sich der Schnappschuss ändert (`ControlCenter.reloadControls`), und beim Abmelden.
- **Intents** (`OpenNewTaskIntent`, `OpenTodayIntent`) liegen in `ios/Shared/ControlIntents.swift` – **nicht** in einem Swift-Paket (siehe Stolperstein in `AGENTS.md`). `supportedModes = .foreground`: Das System bringt die App nach vorn, `perform()` läuft im Prozess der App (Apple, App Intents, `IntentModes`). Der Intent meldet „Neue Aufgabe“ bei `AppLaunchRequests` (Paket `FamiliarActivity`, analog zur `TaskCompletionBridge`); `RootTabView` öffnet das Formular. Beim Kaltstart merkt sich die Brücke die Anfrage 60 Sekunden lang.
- **Grenzen:** Die Zahl ist so aktuell wie der letzte Schnappschuss (die App schreibt ihn nach jedem Laden); nach Mitternacht stimmt sie, sobald das System das Steuerelement neu lädt. Ist niemand angemeldet, zeigt das Steuerelement nur „Familiar“.
- **Prüfen vor Veröffentlichung:** Archive-Build; `Metadata.appintents/extract.actionsdata` der App muss beide Intents mit Modulnamen `Familiar` enthalten; Steuerelemente auf einem echten iPhone hinzufügen (der Simulator zeigt Controls nicht zuverlässig).

## Datenschutz

Keine neuen gespeicherten oder gesendeten Daten: Einladungen gab es schon; die Steuerelemente lesen nur den bestehenden, vom Backup ausgenommenen Schnappschuss. Datenschutzerklärung, Verarbeitungsverzeichnis und `PrivacyInfo.xcprivacy` bleiben unverändert.

## Nicht gemacht

- Keine eigene Onboarding-Phase und kein Pflichtschritt: Einladen bleibt freiwillig.
- Kein Steuerelement, das direkt abhakt (Abhaken bleibt Live Activity, Widget und Siri).
