# Arbeitsstand und Übergabe (2026-11-12)

Dieses Dokument ist die Einstiegsstelle, wenn eine Sitzung (oder ein Mensch) die Arbeit nach einer Unterbrechung (z. B. Token-Limit) weiterführt. Zuerst lesen, dann `git log --oneline --graph --all -30` und `git status`.

## Rahmen

- App im App Store seit 2026-11-08 (Version 1.0, Build 5). Version 1.0.1 (Build 6, nur neuer Store-Auftritt) war bei Apple zur Prüfung eingereicht; Stand dort in App Store Connect nachsehen.
- Regeln: [AGENTS.md](../../AGENTS.md). Nichts pushen (der Inhaber pusht per GitHub Desktop), keine Migration auf dem Server einspielen und keine Edge Function deployen ohne Zustimmung des Inhabers, keine Geheimnisse.
- Der Mac hat wenig Speicherplatz und ist stark ausgelastet: immer nur **ein** `xcodebuild` gleichzeitig, Build-Ordner (`-derivedDataPath`) im Scratch-Ordner anlegen und danach löschen, vor jedem Bau `df -h /System/Volumes/Data` prüfen (unter 1,5 GB frei: nicht bauen). UI-Tests bei „kAXErrorServerNotFound“ oder „Audit failed to complete in time“ einzeln mit `-only-testing:` wiederholen, bevor sie als Fehler gelten.

## Was in `main` ist (lokal, nicht gepusht)

1. Feinschliff `3cbab7d`: „Zuletzt verwendet“ bei der Anmeldung, Bewertungs-Bitte nach 10 erledigten Aufgaben (`ReviewPrompt`), Kalender-Übergänge, Heute-Knopf, Tab-Hülle.
2. Merge `85f500f` (Branch `claude/animationen-74f490`): einheitliche Bewegung (`docs/design/motion.md`), Tab-Leiste wie die Systemleiste (Maße als Konstanten in `FloatingTabBar`), Tastatur beim Schließen von „Neue Aufgabe“, Start lädt Profil/Familien/Aufgaben gleichzeitig (`ConcurrentLoad`), Debug-Hilfen (`-FamiliarInMemoryLatency`, `-FamiliarSystemTabBarReference`).
3. Merge `0eb80df` (Branch `claude/neue-funktionen-e0e9e4`): Einladen beim Start (`InviteFamilySheet`, Hinweiskarte), Steuerelemente „Neue Aufgabe“ und „Heute offen“ (`ios/Shared/ControlIntents.swift`, `FamiliarControls.swift`, ADR 0011).
   Der Release-Build des zusammengeführten Stands war erfolgreich. Der vollständige Testlauf auf diesem Stand steht noch aus.

## Nachtrag 23:25

- Komfort und Suche ist in `main` zusammengeführt (Merge `bd5d460`; vorher `main` in den Branch eingearbeitet, Paket-Tests 107 grün, TaskUITests 10 grün, PlusTab grün, Audit hell/dunkel grün nach Einzelwiederholung, Release-Build erfolgreich).
- Offen ist nur noch **Private Aufgaben** (Branch `claude/private-aufgaben-856bd5`): Der Branch muss `main` (bd5d460) einarbeiten (Konflikte im Erstellen-Blatt wahrscheinlich), gezielt testen, dann in `main` zusammenführen; danach die Gesamtprüfung (Schritt 3 unten).

## Nachtrag 00:55 – alles in main, Gesamtprüfung grün

- Alle vier Pakete sind in `main` (Merge `58c0b58`; Version 1.1.0, Build 7 in `98c097e`). Nichts gepusht.
- Gesamtprüfung auf diesem Stand: Paket-Tests 118 (+7) grün, **alle 28 UI-Tests grün** (inkl. Barrierefreiheit hell/dunkel/Suche, Private Aufgaben, Komfort, Wiederholung), Release-Build und Archive erfolgreich, `Metadata.appintents` der App enthält `CompleteTaskIntent`, `OpenNewTaskIntent`, `OpenTodayIntent` mit Modulname `Familiar`.
- **Offen:** (1) Migration `0021_private_tasks.sql` ist **nicht** auf dem Server eingespielt; sie muss vor dem Testen/Veröffentlichen von Build 7 eingespielt werden (neue Parameter in `create_task`/Serien-RPCs; SQL-Tests 48/48 grün in Rollback). (2) Push in GitHub Desktop, Archive und Upload in Xcode, TestFlight, Prüfung auf dem iPhone. (3) Neu und nur durch Code-Lesen geprüft: Der Plus-Knopf öffnet das Formular immer; ohne Anlegerecht in irgendeiner Familie bietet es nur „Nur für mich“ an.

## Nachtrag 2026-11-12 – Feinschliff nach den ersten TestFlight-Tests (Build 8)

- Migration `0021` ist auf der Produktion eingespielt (SQL-Tests dort 48/48 grün). Build 7 (1.1.0) liegt bei Apple; die folgenden Korrekturen stecken in **Build 8** (`CURRENT_PROJECT_VERSION = 8`).
- Behoben: (1) Start: Startansicht bleibt über der Hauptansicht, bis die erste Liste da ist, dann eine Überblendung (`RootView`). (2) „Nur für mich“ ↔ Familie wechselt jetzt sauber (Häkchen immer bei genau einem Eintrag). (3) Abbrechen von „Neue Aufgabe“: Tab-Leiste saß 34 pt zu hoch, weil SwiftUI bei eingeblendetem Blatt die Safe Area wieder einrechnete → `ScreenBottomAnchored` in `RootTabView`. (4) Suchfeld liegt im Inhalt, ist beim Start weggescrollt, Herunterziehen oder Lupe holt es hervor (`SearchRevealScrollView`). (5) Verlauf springt nicht mehr (war die verspätet einspringende System-Suchleiste). (6) Titelfeld heißt „Was ist zu tun?“ und schaltet Kontaktvorschläge ab (nur am Gerät prüfbar).
- Tests: alle UI-Tests grün (28; Such-Tests auf `textFields["search.field"]` umgestellt, neuer Schritt „zurück von privat“ in `PrivateTaskUITests`).
- Offen am iPhone prüfen: Telefonnummern-Vorschläge verschwunden? Start flüssig? Suchfeld per Herunterziehen? Abbrechen ohne Sprung der Leiste?

## Nachtrag 2026-11-12 (später) – zweite Rückmeldung aus TestFlight (Build 9)

- Behoben bzw. neu: (1) Start: **eine** durchgehende Startansicht-Ebene (vorher zwei, die sich ineinander blendeten und flackerten), Zeichen ohne eigene Animation, Ausblenden erst eine Atempause nach dem Laden. (2) **Suchfeld sichtbar bei kurzem Inhalt** (leere Familie mit Einladungskarte): SwiftUI scrollt bei zu kurzem Inhalt gar nicht → Mindesthöhe aus der gemessenen Containerhöhe, `settle()` hält das Feld jederzeit verborgen; Test-Szenario `empty`. (3) Suche abbrechen: sanftes Einfahren (`isSliding` hält `settle()` heraus). (4) Kalender: Monat schiebt seitlich herein (Richtung wie Blättern), „weiße Box“ war der Platzhalter der Tagesliste (`pending` statt Skeleton). (5) **Verlauf: Wischen** – nach rechts wiederherstellen, nach links endgültig löschen (mit Rückfrage; `swipeActionsContainer`, iOS 27). (6) Live Activity: Abstände in der erweiterten Dynamic Island (links/unten) – ob das die abgeschnittene Ecke war, am Gerät prüfen. (7) Details: Knopf „Alle offenen erinnern“ (ab zwei offenen Personen; pro Person gab es „Erinnern“ schon).
- Migration `0022_purge_history_entry.sql` ist auf der Produktion eingespielt, SQL-Tests `0013` 10/10 grün. **Offen für den Inhaber:** Push, Archive/Upload von Build 9, iPhone-Prüfung (Start, Suche, Kalender, Verlauf-Wischen, Live Activity).

## Nachtrag 2026-11-12 (abends) – Build 10

- Bilder-Fehler beim Anlegen (4 Bilder): Server-Protokoll zeigt, dass der Supabase-Speicher ca. 1 Minute lang **alles** mit 429/544 abgelehnt hat (auch Avatare), danach wieder 200 – kein Fehler der App oder der Richtlinien (Policies geprüft). Trotzdem: klare Meldung `serviceBusy` und „409 Duplicate = Erfolg“, damit der zweite Versuch nicht an schon hochgeladenen Bildern scheitert.
- Such-Symbol oben rechts entfernt (Suche per Herunterziehen; VoiceOver-Knopf bleibt). Kalender: kein Platzhalter-Kasten mehr beim ersten Öffnen, „Nichts geplant“ ruhiger (Symbol, mittig, feste Höhe).
- Tests: UI (Suche, Aufgaben, Kalender, Audit) grün, Paket-Tests 118 + 19 grün.
- Bilder: 1600 px/Qualität 0,7 statt 2048 px/0,8, Aufbereitung im Hintergrund, Upload parallel (2 Bilder, Bild+Miniatur gleichzeitig); **Duplizieren übernimmt jetzt die Bilder** (ohne Upload; bei anderer Familie entfallen sie). Neue Tests `ImageProcessorTests`, Duplikat-Test angepasst.
- Editor: Familien-Auswahl als ruhige Zeile „Familie“ **über den Bildern** (nicht mehr als Menü am Kopf); „Kohrs“ aus Platzhalter und Testdaten entfernt (jetzt „Familie Lindner“). Server-Test für Bild-Kopien in `supabase/tests/0003_tasks.sql` (H5b–H5e; einzeln gegen die Produktion in `begin … rollback` 6/6 grün).
- Navigation: Jeder Bereich (Aufgaben, Kalender, Verlauf) steht nach einem Tab-Wechsel wieder auf der Startseite (`popsToRootOnTabChange`, UI-Test `testTabChangeReturnsToStartPage`).
- Verlauf: „Noch X Tage im Verlauf“ nur noch in den letzten 7 Tagen (sonst auf jeder Karte Rauschen).
- Abschlussprüfung vor dem Dauerstand: Kontraste aller Farb-Tokens nachgerechnet (Text ≥ 4,5 : 1 in Hell, Dunkel und „Kontrast erhöhen“; `textTertiary` nur für Dekoration), Bildschirme hell/dunkel gesichtet, Supabase-Advisors (nur erwartete Hinweise: RPCs für angemeldete Nutzer absichtlich ausführbar, kein Passwort-Login).

## Offene Pakete (Stand davor, erledigt) (jeweils eigener Branch/Worktree unter `.claude/worktrees/`)

| Paket | Branch | Stand | Nächster Schritt |
|---|---|---|---|
| Komfort und Suche (Verschieben „Tag/Woche später“, Duplizieren, Weiterempfehlen/Bewerten, Suche in Aufgaben und Verlauf) | `claude/komfort-suche-042637` | zwei Commits (`6f48ce0`, `0de9a68`), gezielte Tests laufen | Bericht „Bauen und Testen abgeschlossen“ abwarten, dann in `main` zusammenführen (`git merge --no-ff`), Konflikte prüfen: TaskEditorView, TasksHomeView, TaskDetailView, TaskStore, ProfileSheet |
| Private Aufgaben + zuletzt genutzte Familie (ein dezentes Chip-Menü im Erstellen-Blatt: Familien und „Nur für mich 🔒“) | `claude/private-aufgaben-856bd5` | in Arbeit (Server zuerst) | Migration `0021_private_tasks.sql` + SQL-Tests + ADR, Client, UI, gezielte Tests; Migration **nicht** einspielen, bis der Inhaber zustimmt |

## Reihenfolge bis zum prüfbaren Build

1. Komfort und Suche zusammenführen.
2. Private Aufgaben fertigstellen und zusammenführen (danach Konflikte mit den Komfort-Funktionen im Erstellen-Blatt prüfen).
3. Einmal auf dem zusammengeführten `main`: alle Paket-Tests, **alle 17 UI-Tests** (inkl. `AccessibilityAuditUITests` hell/dunkel), Release-Build, Archive ohne Signierung (`CODE_SIGNING_ALLOWED=NO`) und `Metadata.appintents` prüfen: `CompleteTaskIntent`, `OpenNewTaskIntent`, `OpenTodayIntent` müssen mit Modulnamen `Familiar` in der App stehen.
4. Mit Zustimmung des Inhabers: Migration `0021` einspielen (`apply_migration`), SQL-Tests (nur in `begin … rollback`), danach `docs/data-model.md` und `AGENTS.md` (Migrationsstand) nachtragen.
5. Der Inhaber: GitHub Desktop → Push origin; Xcode → Archive → Upload (neue Build-Nummer in `ios/Config/Base.xcconfig`, `CURRENT_PROJECT_VERSION`); TestFlight; Prüfliste fürs iPhone (siehe Berichte der Sitzungen: Steuerelemente, Einladen, Tab-Leiste, Start, Suche, Private Aufgaben, Live Activity).

## Wunsch des Inhabers (Auswahl, nicht vergessen)

- Arbeiten mit höchster Effizienz, aber ohne Pfusch; regelmäßig kurze Updates geben.
- Antworten auf Deutsch (du/dein), einfache Sprache, Schritte nummeriert.
- Nicht ändern (entschieden): Altersfreigabe 16+, iOS 27 als Mindestversion, nur iPhone.
- Offene Prüfungen nur auf einem echten iPhone: Bewegungsgefühl, Startzeit, Steuerelemente im Kontrollzentrum, Live Activity.

## Nachtrag 2026-11-13 – Version 1.1.0 eingereicht

- **Version 1.1.0 (Build 13) ist zur App-Prüfung eingereicht** (2026-11-13, „Warten auf Prüfung“). Veröffentlichung automatisch nach der Freigabe, sofort für alle, Bewertung bleibt.
- Die Builds 12 und 13 wurden vom Inhaber hochgeladen; im Quellcode steht als letzter Stand Build 11 (`022bae3`). Eine Build-Nummer allein ändert den Code nicht, ein Commit dazu fehlt aber. Wer den Stand sauber festhalten will: `CURRENT_PROJECT_VERSION` in `ios/Config/Base.xcconfig` auf 13 setzen.
- „Neues in dieser Version“ und Werbetext sind in App Store Connect eingetragen (Werbetext aus `docs/app-store/v2/konzept.md`).
- Nach der Freigabe: `REVIEW_CODE` in Supabase löschen und `REVIEW_EMAIL` neu setzen.
