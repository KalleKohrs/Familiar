# ADR 0008: Wiederholungen (Phase 5)

- **Status:** angenommen (2026-10-21)
- **Kontext:** Guide, Abschnitt 4: Wiederholungsregel plus eigenständige Vorkommen; Geltungsbereich beim Bearbeiten und Löschen; Serien-Löschung als ein Verlaufseintrag. Umsetzung: Migration `0009_recurrence`, Spiegelung in `FamiliarCore/Models/Recurrence.swift`.

## Entscheidungen

| Thema | Regel |
|---|---|
| Modell | `task_series` hält Regel und Vorlage (Titel, Beschreibung, Erledigungsart, Uhrzeit, Zeitzone, Zuweisungen, Bilder). Jedes Vorkommen ist eine eigene `tasks`-Zeile mit `series_id` und `occurrence_date`; Abhaken, Status pro Person und Verlauf funktionieren wie bei Einzelaufgaben. |
| Regeln | täglich · an Wochentagen (ISO 1 = Montag … 7 = Sonntag) · an Monatstagen (1–31). Ein Algorithmus: `private.series_dates` (Server) bzw. `RecurrenceRule` (App), mit gleichen Testfällen. |
| E2 – fehlender Monatstag | Letzter Tag des Monats; fallen mehrere Tage auf denselben (30. + 31. im Februar), entsteht **ein** Vorkommen. |
| Erzeugung | Alle Vorkommen bis heute (verpasste bleiben überfällig) **plus das nächste künftige**. `pg_cron` alle 5 Minuten und sofort in den Serien-RPCs. Idempotent über `unique (series_id, occurrence_date)` und die Wasserstandsmarke `generated_until`: Tage bis dahin werden nie wieder erzeugt – auch nicht nach Löschen oder Bereinigen eines Vorkommens. |
| Startdatum | Pflicht. Liegt es in der Vergangenheit, wird nichts nachgeholt; das erste Vorkommen ist das erste passende ab heute. |
| Bearbeiten „Nur dieses Vorkommen“ | `update_task`; das Vorkommen wird abgekoppelt (`is_detached`), spätere Serienänderungen lassen es in Ruhe. Die Regel lässt sich so nicht ändern (Dialog bietet dann nur „Dieses und zukünftige“). |
| Bearbeiten „Dieses und alle zukünftigen“ | `update_series_from`: Die Serie bekommt den neuen Stand. Das gewählte Vorkommen wird angepasst (auch Datum/Uhrzeit). Spätere offene, nicht abgekoppelte und noch **unberührte** Vorkommen (niemand hat abgehakt) bekommen den neuen Inhalt; bei geänderter Regel werden künftige davon entfernt und nach der neuen Regel ab dem gewählten Vorkommen bzw. ab morgen neu erzeugt. Erledigte, angefangene und abgekoppelte Vorkommen bleiben unverändert. |
| Löschen „Nur dieses Vorkommen“ | `delete_task`; landet einzeln im Verlauf. |
| Löschen „Gesamte Serie“ | `delete_series`: ein Eintrag in `series_deletions`; offene Vorkommen (auch überfällige und angefangene) werden mit `deleted_by_series_op` markiert und erscheinen **nicht** einzeln im Verlauf. Erledigte bleiben. |
| Serie wiederherstellen | `restore_series_deletion`, jedes Mitglied mit Sicht auf die Serie. Markierte Vorkommen werden wieder aktiv (Haken bleiben erhalten); die Erzeugung läuft ab heute weiter (`resume_from`), Termine aus der Löschphase werden nicht nachgeholt. Einzelnes Wiederherstellen solcher Vorkommen ist gesperrt (`restore_series_instead`). |
| Sichtbarkeit | Wie bei Aufgaben: Mitglied UND (alle sichtbar ODER Ersteller ODER zugewiesen), `private.can_view_series`. Bilder sind über sichtbare Aufgaben oder Serien lesbar. |
| 30 Tage | Täglicher Job entfernt zusätzlich seit 30 Tagen gelöschte Serien (erledigte Vorkommen bleiben als Einzelaufgaben mit `series_id = null`) und abgelaufene Löscheinträge; Bilder bleiben, solange eine Aufgabe oder Serie sie nutzt. |
| Kalender | `project_series_occurrences(from, to)` liefert künftige, noch nicht erzeugte Termine sichtbarer Serien (höchstens 400 Tage) für Phase 6. |

## Bekannte Grenzen

- Wird eine Person aus der Familie entfernt, bekommt sie in neuen Vorkommen keine Zuweisung mehr; die Serie selbst behält den Eintrag bis zur nächsten Bearbeitung (Aufräumen folgt mit Phase 9).
- Eine Regeländerung ab einem überfälligen Vorkommen gilt ab morgen; für heute bleibt das bereits erzeugte Vorkommen der alten Regel bestehen.
