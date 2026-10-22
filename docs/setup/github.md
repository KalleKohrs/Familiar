# Quellcode bei GitHub sichern (privat, kostenlos)

Der Quellcode liegt bisher nur auf diesem Mac. Diese Sicherung ist unabhängig von der Datensicherung der Familiendaten (Backblaze, siehe [backup.md](backup.md)); hier geht es nur um den Code – keine Familiendaten. Dauer: etwa 10 Minuten.

## Schritt 1 – GitHub-Konto

1. <https://github.com/signup> → Konto anlegen (kostenlos), Zwei-Faktor-Anmeldung einschalten, wenn GitHub danach fragt.

## Schritt 2 – GitHub Desktop

1. <https://desktop.github.com> → **Download for macOS** → installieren → mit dem GitHub-Konto anmelden.

## Schritt 3 – Quellcode sichern (privat!)

1. GitHub Desktop → **File › Add Local Repository…** → Ordner `Developer/Familiar` wählen → **Add Repository**.
2. Oben **Publish repository** → Name `familiar` → Haken bei **Keep this code private** gesetzt lassen → **Publish Repository**.

Ab jetzt liegt der Code zusätzlich bei GitHub. Künftige Änderungen überträgt „Push“ (mache ich, wenn du das möchtest).

Geheimnisse liegen nicht im Repository: `ios/Config/Local.xcconfig`, `ios/Config/Secrets.xcconfig` und `*.p8` sind über `.gitignore` ausgeschlossen. `supabase/backup-public.pem` ist der **öffentliche** Sicherungsschlüssel und darf mit hinein.
