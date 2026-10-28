# ADR 0010: Reihum-Aufgaben, Widgets, Anstupsen, Siri

- **Status:** angenommen (2026-10-22), umgesetzt; nach unabhängiger Prüfung ergänzt (2026-10-24: Startpunkt, Regeländerung, Austritt, Sichtbarkeit, gesammelte Mitteilungen).
- **Kontext:** Nach dem Design-Durchgang wünscht der Nutzer vier Funktionen. Alle bleiben kostenlos, ohne neue Dienste und datensparsam.

## 1. Reihum-Aufgaben

**Ziel:** Bei einer Serie ist pro Termin genau eine Person dran, und es wechselt automatisch („Müll: diese Woche Paul, nächste Woche Mia“).

- **Serie** bekommt `assignment_mode` (`together` = wie bisher, alle Zugewiesenen; `rotate` = reihum), `rotation_unit` (`occurrence` = jeder Termin, `week` = jede Kalenderwoche) und `rotation_start` (der Termin, ab dem gezählt wird). `series_assignees` bekommt `position` (Reihenfolge).
- **Startpunkt:** `rotation_start` ist immer ein echter Termin – beim Anlegen der erste Termin, der tatsächlich entsteht (erster Regeltermin ab `max(Startdatum, heute)`; Vergangenes wird nicht erzeugt), beim Ändern der bearbeitete Termin. So ist die erste Person der Liste wirklich als Erste dran.
- **Wer ist dran:** `rotation_start` hat `k = 0`, danach zählt `k` die Serientermine in `(rotation_start, Termin]` (bei `week`: Anzahl ganzer ISO-Wochen zwischen den Montagen). Von den Personen in Reihenfolge zählen nur aktuelle Mitglieder; dran ist `liste[k mod n]`. Weil der Start mitzählt, auch wenn er nach einer Regeländerung nicht auf die neue Regel fällt, bekommt niemand zwei Termine hintereinander.
- **Austritt** (Verlassen, Entfernen, Kontolöschung; Trigger auf `family_members`): Die Person verliert ihre Plätze in Serien und alle offenen Zuweisungen der Familie (eine laufende Live Activity endet). Reihum-Termine ohne Person gehen an die Person, die nach der Regel jetzt dran ist – ohne „zugewiesen“-Mitteilung. Bei „jede Person einzeln“ ist eine Aufgabe erledigt, wenn alle Übrigen fertig sind.
- **Ohne zuständige Person:** Bei einfachen Aufgaben, deren einzige zugewiesene Person austritt, bleibt die Aufgabe ohne Zuweisung zurück (sichtbar für die Familie bzw. die Erstellerin, aber ohne Erinnerungen); die Familie weist sie neu zu.
- **Sichtbarkeit:** Wer bei einer Reihum-Serie mitmacht, sieht alle ihre Termine – auch in Familien mit „nur Zugewiesene“. Sonst könnten sich die Beteiligten weder tauschen noch erinnern, und geplante Termine im Kalender verschwänden, sobald sie erzeugt werden. Abhaken darf weiterhin nur, wer dran ist (oder die Aufgabe angelegt hat).
- **Reihum** braucht ≥ 2 Personen; Erledigungsart ist dann immer „eine Person“ (`any_one`).
- **Ändern ab einem Termin** (`update_series_from`): `rotation_start` = dieser Termin, die übergebene Reihenfolge beginnt dort. Die App zeigt die Reihenfolge immer so, dass oben steht, wer als Nächstes dran ist – Speichern ohne Änderung verschiebt also nichts.
- **Tauschen:** Ein einzelner Termin lässt sich wie jedes Vorkommen bearbeiten („Nur dieser Termin“) – damit ist Tauschen ohne neue Funktion möglich. Die neue Person bekommt „zugewiesen“.
- **Mitteilungen bei Serienänderungen:** „Dieses und zukünftige“ meldet je Person höchstens einmal: „zugewiesen“, wenn sich ihr nächster offener Termin geändert hat, sonst „geändert“ bei relevanter Änderung – nicht einmal je Termin (Sammeländerung, `familiar.bulk_change`).
- **Anzeige:** Editor zeigt die nächsten Termine mit Person („Fr 24.10. Paul · Fr 31.10. Mia …“), Details und Kalender zeigen „Reihum“ und bei geplanten Terminen die Person. Die Berechnung gibt es identisch in SQL (Erzeugung) und Swift (`RotationRules`, Vorschau/Kalender), mit denselben Testfällen.

## 2. Widgets „Heute“ (Homescreen und Sperrbildschirm)

- **Größen:** Homescreen klein (Anzahl + nächste Aufgabe), mittel (bis 3 Aufgaben mit Abhaken), groß (bis 7); Sperrbildschirm rechteckig (nächste 2 Aufgaben), rund (Anzahl offen) und Zeile („3 Aufgaben heute“).
- **Inhalt:** offene Aufgaben für heute (überfällig, heute, ohne Datum) – einstellbar „Nur meine“ (Standard) oder „Alle“ und optional eine Familie (`AppIntentConfiguration`).
- **Daten:** Die App schreibt nach jedem Laden/Ändern einen kleinen Schnappschuss (nur Titel, Zeit, Familie/Farbe, Personen-Initialen, Abhak-Erlaubnis) in den gemeinsamen App-Group-Container und lädt die Widgets neu. Das Widget hat keinen Zugang zum Konto und keine Netzwerkzugriffe.
- **Abhaken:** derselbe `CompleteTaskIntent` wie in der Live Activity. Laut Apple („Adding interactivity to widgets and Live Activities“) läuft ein `LiveActivityIntent` im Prozess der App, auch aus einem Widget; danach lädt das System das Widget neu.
- **Datenschutz:** Titel sind `privacySensitive` – bei gesperrtem Gerät ohne „Zugriff im gesperrten Zustand“ blendet iOS sie aus. Die Datei ist vom Backup ausgenommen und wird bei jeder Abmeldung gelöscht, auch wenn die Sitzung von selbst endet; während des Abmeldens schreibt die App keinen neuen Schnappschuss (`WidgetSync.activate`/`clear`).

## 3. Anstupsen

- In den Details neben jeder Person, die noch offen ist: „Erinnern“. Erlaubt für jedes Familienmitglied mit Sicht auf die Aufgabe, nicht an sich selbst, nur offene Aufgaben.
- **Grenzen:** pro Aufgabe und Person höchstens einmal pro Stunde, egal von wem (`private.task_nudges`, Fehler `nudge_too_soon`; Einträge werden nach einem Tag gelöscht). Nur an aktuelle Mitglieder (`member_not_found`). **Ruhezeit** 21–7 Uhr (Zeitzone der Aufgabe): dann kommt die Erinnerung um 7 Uhr, mehrere aus derselben Nacht als eine; die App nennt die Uhrzeit („heute“ bzw. „morgen um 07:00 Uhr“).
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
