# Datensicherung einrichten (GitHub, kostenlos)

Stand 2026-10-21. Grundlage: Supabase-Doku [Automated backups using GitHub Actions](https://supabase.com/docs/guides/deployment/ci/backups); Entscheidung in [ADR 0009](../decisions/0009-backups.md). Dauer: etwa 30 Minuten. **Wann:** sobald das Produktionsprojekt bei Supabase existiert (Launch-Liste Punkt 2) – den GitHub-Teil (Schritte 1–3) kannst du schon vorher machen; er sichert sofort auch den Quellcode.

**Geheim** sind: der private Sicherungsschlüssel, das Datenbank-Passwort und der Supabase-Secret-Key. Sie kommen nie in den Chat.

## Schritt 1 – GitHub-Konto

1. <https://github.com/signup> → Konto anlegen (kostenlos), Zwei-Faktor-Anmeldung einschalten, wenn GitHub danach fragt.

## Schritt 2 – GitHub Desktop

1. <https://desktop.github.com> → **Download for macOS** → installieren → mit dem GitHub-Konto anmelden.

## Schritt 3 – Quellcode sichern (privat!)

1. GitHub Desktop → **File › Add Local Repository…** → Ordner `Developer/Familiar` wählen → **Add Repository**.
2. Oben **Publish repository** → Name `familiar` → Haken bei **Keep this code private** gesetzt lassen → **Publish Repository**.

Ab jetzt liegt der Code zusätzlich bei GitHub. (Ich übertrage künftige Änderungen mit „Push“, wenn du das möchtest.)

## Schritt 4 – Backup-Repository (privat!)

Ich bereite den Ordner `Developer/familiar-backups` mit Workflow, Skripten und dem **öffentlichen** Schlüssel vor und lege dir den **privaten** Schlüssel in die Zwischenablage:

1. Einen neuen Eintrag im Passwort-Manager (z. B. Apple Passwörter › Neue Notiz) „Familiar Sicherungsschlüssel“ anlegen und den Inhalt einfügen. **Ohne diesen Schlüssel lassen sich die Sicherungen nicht öffnen.**
2. GitHub Desktop → **File › Add Local Repository…** → `Developer/familiar-backups` → **Publish repository** → privat lassen → **Publish**.

## Schritt 5 – Secrets in GitHub

Auf github.com → Repository `familiar-backups` → **Settings › Secrets and variables › Actions › New repository secret**, drei Einträge:

| Name | Wert (aus dem Supabase-Dashboard des Produktionsprojekts) |
|---|---|
| `SUPABASE_DB_URL` | **Connect** (oben) → **Session pooler** → Verbindungs-URL kopieren, `[YOUR-PASSWORD]` durch das Datenbank-Passwort ersetzen |
| `SUPABASE_URL` | `https://<projekt>.supabase.co` |
| `SUPABASE_SERVICE_KEY` | **Project Settings › API Keys** → Secret key |

## Schritt 6 – Erster Lauf

Repository → **Actions** → **Datensicherung** → **Run workflow**. Nach 1–2 Minuten steht dort ein grüner Haken; im Ordner `db/` liegt die erste verschlüsselte Sicherung. Dann spielen wir einmal die Wiederherstellung durch.
