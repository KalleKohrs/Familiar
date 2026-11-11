# ADR 0012: Private Aufgaben und zuletzt genutzte Familie

- **Status:** umgesetzt auf Branch `claude/private-aufgaben-856bd5` (2026-11-11), Migration `0021_private_tasks.sql` **noch nicht eingespielt**.
- **Kontext:** Das Formular „Neue Aufgabe“ ist schon voll. Der Inhaber wünscht (1) Aufgaben, die nur man selbst sieht, und (2) dass bei mehreren Familien die zuletzt benutzte vorausgewählt ist – beides ohne zusätzliche Zeilen, Schalter oder Hinweise.

## 1. Private Aufgaben

**Begriff.** Eine private Aufgabe liegt in einer Familie, ist aber nur für ihren **Ersteller** sichtbar – auch nicht für Admins, auch nicht bei „Sichtbarkeit: alle“. Sie ist ausschließlich dem Ersteller zugewiesen.

**Entscheidungen**

| Frage | Entscheidung | Warum |
|---|---|---|
| Wo steht „privat“? | `tasks.is_private` und `task_series.is_private` (Standard `false`), nur beim Anlegen setzbar, später nicht umschaltbar | Umschalten hieße: Sichtbarkeit, Zuweisungen und Mitteilungen nachträglich ändern. „Duplizieren“ reicht als Umweg. |
| Wer sieht sie? | Nur `created_by = auth.uid()` und noch Mitglied der Familie. Gilt in RLS (`tasks`, `task_series`), `can_view_task`, `can_view_series` – damit automatisch für Zuweisungen, Bilder, Storage, Verlauf, Kalender-Projektion, Anstupsen, Live Activities | eine einzige Stelle je Objekt, keine Sonderfälle in der App |
| Zuweisung | Immer nur der Ersteller. Die RPCs setzen das selbst (übergebene Personen werden ignoriert); Trigger `*_enforce_private_*` weisen alles andere in der Datenbank ab | Eine Aufgabe mit Fremden wäre nicht mehr privat. |
| Wiederholung | Private Serie, nie „Reihum“ (`check`); Termine erben „privat“ per Trigger `tasks_inherit_privacy` – die Erzeugungsfunktion bleibt unverändert | Reihum braucht mehrere Personen. |
| Familienrechte (Schalter „Mitglieder dürfen anlegen/bearbeiten/löschen“) | Gelten **nicht** für private Aufgaben (`require_task_permission(…, p_private)`) | Sie schützen die gemeinsame Liste; eine private Aufgabe betrifft nur ihren Ersteller. Sonst könnte jemand seine eigene Aufgabe nicht mehr löschen. |
| Admin | Hat keinerlei Zugriff – nicht sehen, bearbeiten, löschen, abhaken, anstupsen. „Verlauf leeren“ (`clear_history`) löscht private Aufgaben anderer nicht (die eigenen als Admin schon) | „Für niemanden sonst sichtbar“ gilt auch für Admins. |
| Mitteilungen, Live Activity, Widgets | Nur für den Ersteller (er ist der einzige Zugewiesene; er löst selbst aus, also keine „zugewiesen/geändert/erledigt“-Mitteilung). Erinnerungen, „Jetzt“, Live Activity, Widgets, Siri laufen wie bisher. Realtime-Hinweise („Aufgabe geändert“) gehen nur an den Ersteller | Kein Hinweis darf verraten, dass es eine private Aufgabe gibt. |
| Austritt / Entfernen | `handle_member_departure` löscht private Aufgaben und Serien der Person (Zuweisungen, Bilder-Verknüpfungen, Verlaufseinträge per Cascade) | Sie gehören ihr allein; bei Rückkehr in dieselbe Familie sind sie weg. Der Ersteller kann nicht mehr zugreifen. |
| Kontolöschung | Zusätzlich löscht ein `BEFORE DELETE`-Trigger auf `profiles` (`delete_private_tasks_of_profile`) sie vor den Cascade-Aktionen | Sonst würde `created_by` auf `null` gesetzt (`on delete set null`) und die Aufgaben blieben unerreichbar liegen – die Reihenfolge der Cascade-Aktionen ist nicht garantiert. |
| Bilder | Dateien liegen wie bisher im Ordner der Familie; Sichtbarkeit über `can_view_task` (Storage-Policy, `images`, `task_image_links`). Verwaiste Dateien räumt die tägliche Bereinigung auf | keine neue Speicherstruktur |
| Alte App-Versionen | `create_task`/`create_recurring_task` bekommen `p_private boolean default false` – Aufrufe ohne Parameter legen normale Aufgaben an. Alte Versionen zeigen private Aufgaben nur als normale Aufgabe ohne Schloss | Die Alt-App kann dem Ersteller nichts falsch zeigen, anderen auch nichts. |
| Datensicherung | `backup_export` sichert alle Tabellen; die neue Spalte ist automatisch dabei | – |

## 2. Zuletzt genutzte Familie

- Rein lokal, pro Konto: `UserDefaults`, Schlüssel je Benutzer-ID (`LastTaskFamily`). Gemerkt wird die Familie, in der zuletzt **eine Aufgabe erstellt** wurde. Fehlt der Eintrag oder gibt es die Familie nicht mehr, gilt die erste Familie der Liste.
- Keine neuen Daten auf dem Server; die Familien-ID bleibt auf dem Gerät.

## 3. Oberfläche („ein Chip statt Abschnitt“)

Ein einziges kleines Menü-Element am Kopf des Formulars („In Familie Berger ▾“, bzw. „Nur für mich 🔒 ▾“). Das Menü bietet die Familien (Häkchen) und, abgetrennt, „Nur für mich (privat)“. Kein Schalter, keine Zeile, kein Hinweis. Beim Wechsel auf „privat“ entfällt der Abschnitt „Wer?“ (der Ersteller ist festgelegt) und die Reihum-Wahl; in der Liste und den Details erscheint ein kleines Schloss (VoiceOver: „Privat“).
Beim Bearbeiten ist der Chip nur Anzeige (Familie und Privat lassen sich nicht ändern).

## Datenschutz

Keine neuen Datenarten, keine neuen Empfänger. Privatsphäre wird *erhöht* (weniger Sichtbarkeit). Datenschutzerklärung und Verarbeitungsverzeichnis bleiben inhaltlich richtig; im Verarbeitungsverzeichnis genügt ein Satz bei „Aufgaben“ (siehe dort).

## Offene Punkte

- „Duplizieren“ (Branch `komfort-suche`) muss `isPrivate` der Vorlage übernehmen.
- Private Aufgaben lassen sich nicht nachträglich in gemeinsame verwandeln (und umgekehrt).
