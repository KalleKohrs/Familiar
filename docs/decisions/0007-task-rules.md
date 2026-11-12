# ADR 0007: Regeln für Aufgaben (Phase 3)

- **Status:** angenommen (2026-10-21)
- **Kontext:** Der Guide legt Erledigungsarten, Rechte und Sichtbarkeit fest, lässt aber Details offen, die Server und App gleich umsetzen müssen. Umsetzung: Migration `0007_tasks`, Spiegelung in `FamiliarCore/TaskRules.swift`.

## Entscheidungen

| Thema | Regel |
|---|---|
| Zuweisung | Mindestens eine Person; nur Mitglieder der Familie. Der Ersteller ist **nicht** automatisch zugewiesen (Guide, Abschnitt 2). |
| Erledigungsart | Muss beim Anlegen **bewusst gewählt** werden (kein Standardwert im Editor). Änderbar, solange noch niemand abgehakt hat (`completion_mode_locked`). |
| Abhaken „Eine für alle“ | Zugewiesene Person (`scope = self`) erledigt die ganze Aufgabe. Ersteller ohne Zuweisung erledigt sie mit `completion_source = creator`. |
| Abhaken „einzeln“ | Jede zugewiesene Person für sich (`self`); komplett, wenn alle erledigt haben. Ersteller kann zusätzlich „Für alle erledigt“ (`all`). Ist der Ersteller selbst zugewiesen, zeigt die App beide Aktionen. |
| Rückgängig | Eigener Haken: die Person selbst (`uncomplete self`); öffnet die Aufgabe wieder, falls sie dadurch komplett war. Komplett erledigte Aufgabe wieder öffnen: jedes Mitglied mit Sicht (`uncomplete all`, setzt alle Haken zurück) – Undo-Hinweis und später Verlauf. |
| Bearbeiten | Jedes Mitglied mit Sicht, nur offene Aufgaben (`task_closed`). Vollständiger Stand pro Speichern; `p_expected_version` verhindert, dass fremde Änderungen überschrieben werden (`task_conflict`). Entfernte Personen fallen weg, verbleibende behalten ihren Status; sind danach alle erledigt, ist die Aufgabe komplett. |
| Löschen | Weich (`deleted_at`), jedes Mitglied mit Sicht; Wiederherstellen per `restore_task` (Undo-Hinweis, Verlauf ab Phase 4). |
| Start | Optional Datum, optional Uhrzeit (nur mit Datum), Zeitzone der Aufgabe (IANA). `starts_at` berechnet der Server; nur Datum = Tagesbeginn. |
| Überfällig | Mit Uhrzeit: 1 h nach Start (wie `staleDate` der Live Activity). Nur Datum: ab dem Folgetag in der Zeitzone der Aufgabe. |
| Reihenfolge | Ohne Datum zuerst (neueste oben), dann datierte chronologisch (`TaskRules.homeOrder`). |
| Bilder | Höchstens 10; JPEG, 1600 px (Qualität 0,7; bis Build 9: 2048 px) plus 480-px-Miniatur, ohne Metadaten; Aufbereitung nicht auf dem Hauptthread, Upload je Bild mit Miniatur gleichzeitig und höchstens zwei Bilder parallel. Duplizieren übernimmt die Bilder ohne neuen Upload (dieselbe Bildzeile wird verknüpft; beim Wechsel der Familie entfallen sie). Hochladen nach `task-images/{family_id}/{id}.jpg`; die RPC prüft, dass beide Dateien vom Aufrufer existieren. Lesen nur über eine sichtbare Aufgabe. Kein Löschen durch Clients (Bereinigung in Phase 4). |
| Realtime | Jede Änderung über die RPCs löst `task_changed` an **alle Mitglieder der Familie** aus (privater Kanal `user:<uid>`, Inhalt nur Aufgaben- und Familien-ID). Die App lädt danach per RLS neu; wer die Aufgabe nicht sehen darf, erfährt nur, dass sich in seiner Familie etwas geändert hat. So erfahren auch Personen, die gerade aus einer Zuweisung entfernt wurden, davon. |

## Bekannte Grenzen

- `realtime.messages` ist nach Tagen partitioniert; die Partitionen legt der Realtime-Dienst an, sobald er für das Projekt aktiv ist. Ohne Partition verwirft `realtime.send` die Nachricht mit einer Warnung – das Speichern der Aufgabe ist davon nie betroffen. Die App lädt zusätzlich beim Öffnen und per Pull-to-Refresh.
- Der Undo-Hinweis verschwindet nach 6 Sekunden; danach erfolgt Rückgängig über den Verlauf (Phase 4).
