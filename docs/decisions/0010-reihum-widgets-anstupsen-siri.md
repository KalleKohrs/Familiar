# ADR 0010: Reihum-Aufgaben, Widgets, Anstupsen, Siri

- **Status:** angenommen (2026-10-22), in Umsetzung.
- **Kontext:** Nach dem Design-Durchgang wünscht der Nutzer vier Funktionen. Alle bleiben kostenlos, ohne neue Dienste und datensparsam.

## 1. Reihum-Aufgaben

**Ziel:** Bei einer Serie ist pro Termin genau eine Person dran, und es wechselt automatisch („Müll: diese Woche Paul, nächste Woche Mia“).

- **Serie** bekommt `assignment_mode` (`together` = wie bisher, alle Zugewiesenen; `rotate` = reihum), `rotation_unit` (`occurrence` = jeder Termin, `week` = jede Kalenderwoche) und `rotation_start` (Datum, ab dem gezählt wird). `series_assignees` bekommt `position` (Reihenfolge).
- **Wer ist dran:** `k` = Anzahl der Serientermine in `[rotation_start, Termin)` (bei `week`: Anzahl ganzer ISO-Wochen zwischen den Montagen). Von den Personen in Reihenfolge zählen nur aktuelle Mitglieder; dran ist `liste[k mod n]`. Verlässt jemand die Familie, rückt die Reihe einfach zusammen.
- **Reihum** braucht ≥ 2 Personen; Erledigungsart ist dann immer „eine Person“ (`any_one`).
- **Ändern ab einem Termin** (`update_series_from`): `rotation_start` = dieser Termin, die übergebene Reihenfolge beginnt dort. Die App zeigt die Reihenfolge immer so, dass oben steht, wer als Nächstes dran ist – Speichern ohne Änderung verschiebt also nichts.
- **Tauschen:** Ein einzelner Termin lässt sich wie jedes Vorkommen bearbeiten („Nur dieser Termin“) – damit ist Tauschen ohne neue Funktion möglich.
- **Anzeige:** Editor zeigt die nächsten Termine mit Person („Fr 24.10. Paul · Fr 31.10. Mia …“), Details und Kalender zeigen „Reihum“ und bei geplanten Terminen die Person. Die Berechnung gibt es identisch in SQL (Erzeugung) und Swift (`RotationRules`, Vorschau/Kalender), mit denselben Testfällen.

## 2. Widgets „Heute“ (Homescreen und Sperrbildschirm)

- **Größen:** Homescreen klein (Anzahl + nächste Aufgabe), mittel (bis 3 Aufgaben mit Abhaken), groß (bis 7); Sperrbildschirm rechteckig (nächste 2 Aufgaben), rund (Anzahl offen) und Zeile („3 Aufgaben heute“).
- **Inhalt:** offene Aufgaben für heute (überfällig, heute, ohne Datum) – einstellbar „Nur meine“ (Standard) oder „Alle“ und optional eine Familie (`AppIntentConfiguration`).
- **Daten:** Die App schreibt nach jedem Laden/Ändern einen kleinen Schnappschuss (nur Titel, Zeit, Familie/Farbe, Personen-Initialen, Abhak-Erlaubnis) in den gemeinsamen App-Group-Container und lädt die Widgets neu. Das Widget hat keinen Zugang zum Konto und keine Netzwerkzugriffe.
- **Abhaken:** derselbe `CompleteTaskIntent` wie in der Live Activity. Laut Apple („Adding interactivity to widgets and Live Activities“) läuft ein `LiveActivityIntent` im Prozess der App, auch aus einem Widget; danach lädt das System das Widget neu.
- **Datenschutz:** Titel sind `privacySensitive` – bei gesperrtem Gerät ohne „Zugriff im gesperrten Zustand“ blendet iOS sie aus. Beim Abmelden wird der Schnappschuss gelöscht.

## 3. Anstupsen

- In den Details neben jeder Person, die noch offen ist: „Erinnern“. Erlaubt für jedes Familienmitglied mit Sicht auf die Aufgabe, nicht an sich selbst, nur offene Aufgaben.
- **Grenzen:** pro Aufgabe und Person höchstens einmal pro Stunde (`private.task_nudges`, Fehler `nudge_too_soon` mit Wartezeit). **Ruhezeit** 21–7 Uhr (Zeitzone der Aufgabe): dann kommt die Erinnerung um 7 Uhr, die App sagt das.
- **Versand:** Auftrag `nudge` in `notification_jobs` (bestehende Warteschlange, Dedupe pro Stunde). Text: „Lena erinnert dich: Müll rausbringen“. Ankommen wird es erst mit dem Apple-Programm (APNs-Schlüssel); Warteschlange und App sind schon fertig.

## 4. Siri und Kurzbefehle

- **Abhaken:** „Hey Siri, Müll rausbringen in Familiar erledigen“ – Parameter ist eine Aufgabe (`AppEntity`, Suche über offene, sichtbare Aufgaben nach Titel).
- **Hinzufügen:** „Neue Aufgabe in Familiar“ – Titel, optional Familie und Tag; Zuweisung an sich selbst, Erledigungsart „eine Person“.
- **Was steht an:** „Was steht heute in Familiar an?“ – Siri liest die offenen Aufgaben für heute vor.
- Alle drei als App Shortcuts (ohne Einrichtung in Siri und der Kurzbefehle-App verfügbar), laufen im App-Prozess mit der angemeldeten Sitzung; ohne Anmeldung eine verständliche Meldung.

## Nicht gemacht

- Kein Tausch-Workflow mit Bestätigung der anderen Person (Bearbeiten genügt).
- Keine Widget-Daten über das Netz (kein Token im Widget).
- Anstupsen ohne Freitext (keine Nachrichtenfunktion, keine Moderation nötig).
