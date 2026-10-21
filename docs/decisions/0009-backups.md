# ADR 0009: Nächtliche Datensicherung ohne Kosten

- **Status:** vorgeschlagen (2026-10-21), wartet auf GitHub-Konto des Nutzers
- **Kontext:** Familiar läuft auch in Produktion im Supabase-Free-Tarif (Entscheidung 2026-10-21: nur kostenlose Dienste). Free enthält keine automatischen Sicherungen. Gesichert werden müssen die Datenbank (Familien, Aufgaben, Zuweisungen, Profile, Auth-Konten) und möglichst die Bilder (`task-images`, `avatars`). Die Sicherung muss außerhalb von Supabase liegen und darf die Familiendaten dem Speicheranbieter nicht offenlegen.

## Geprüfte Wege

| Weg | Bewertung |
|---|---|
| **Edge Function → Objektspeicher** (z. B. Backblaze B2, 10 GB frei) | Supabase-Doku „Edge Functions Limits“: 2 s CPU-Zeit pro Aufruf, 150 s Laufzeit im Free-Tarif – für Export, Packen und Verschlüsseln zu knapp. Zusätzliches Konto nötig. **Verworfen.** |
| **GitHub Actions** (Supabase-Doku „Automated backups using GitHub Actions“) | Offizieller Weg: `supabase db dump` (Rollen, Schema, Daten mit `--use-copy`) jede Nacht in ein **privates** Repository. Kostenlos (private Repos: 2.000 Actions-Minuten/Monat; eine Sicherung dauert ~1–2 Minuten). **Gewählt.** |

## Entscheidung

1. **Privates GitHub-Repository** `familiar` für den Quellcode (bisher nur auf einem Rechner – eigenes Risiko) und ein **zweites privates Repository** `familiar-backups` nur für Sicherungen.
2. **Workflow** (läuft im Backup-Repository, täglich 03:30 UTC und manuell):
   - `supabase db dump` für Rollen, Schema und Daten (wie in der Supabase-Doku).
   - Bilder: alle Objekte aus `task-images` und `avatars` über die Storage-API laden (Service-Key nur als GitHub-Secret).
   - Alles in ein Archiv packen und mit **age** (moderne Dateiverschlüsselung) **für einen öffentlichen Schlüssel verschlüsseln**. Der private Schlüssel liegt nur beim Nutzer (Passwort-Manager + Ausdruck), nie bei GitHub oder Supabase.
   - Datenbank-Archiv als Commit ins Backup-Repository (klein, Verlauf = Versionen), Bilder-Archiv als Actions-Artefakt mit 30 Tagen Aufbewahrung.
3. **Secrets in GitHub** (nie im Chat): `SUPABASE_DB_URL` (Verbindungs-URL des Produktionsprojekts), `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`; der öffentliche age-Schlüssel steht offen im Workflow.

## Grenzen

- Sicherung einmal pro Nacht: Im schlimmsten Fall gehen die Änderungen eines Tages verloren.
- GitHub-Artefakte zählen gegen 500 MB Speicher im kostenlosen Konto – bei vielen Bildern wird die Bildsicherung später auf einen eigenen Objektspeicher umgestellt.
- Die Datenbank-Verbindung: Supabase-Direktverbindungen sind IPv6; GitHub-Runner haben IPv4 – deshalb die **Session-Pooler**-Verbindung aus dem Supabase-Dashboard verwenden (beim Einrichten prüfen).

## Wiederherstellung (Kurzfassung)

1. Archiv herunterladen und mit dem privaten age-Schlüssel entschlüsseln.
2. Neues Supabase-Projekt anlegen, `roles.sql`, `schema.sql`, `data.sql` laut Supabase-Doku „Backup and Restore using the CLI“ einspielen.
3. Bilder mit dem mitgelieferten Skript in die Buckets hochladen; Edge Functions neu deployen, Secrets setzen.

Die Probe-Wiederherstellung wird nach dem Einrichten einmal durchgespielt.
