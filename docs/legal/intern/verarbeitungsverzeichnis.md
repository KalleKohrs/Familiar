# Verzeichnis von Verarbeitungstätigkeiten (Art. 30 DSGVO) – Familiar

**Intern, nicht veröffentlichen.** Stand 2026-10-24. Verantwortlicher: Sven Olaf Kohrs, Claus-von-Stauffenberg-Weg 1, 21684 Stade, info@familiar-app.de. Kein Datenschutzbeauftragter (keine Pflicht nach § 38 BDSG). Bei Änderungen der App mitpflegen; die öffentliche Fassung ist [datenschutz.md](../datenschutz.md).

| Nr. | Tätigkeit | Zweck | Betroffene | Daten | Rechtsgrundlage | Empfänger | Drittland | Löschfrist |
|---|---|---|---|---|---|---|---|---|
| 1 | Konto und Anmeldung | Zugang zur App | Nutzer | E-Mail, Apple-/Google-Kennung, Name (Apple/Google), Anmeldezeitpunkte | Art. 6 Abs. 1 lit. b | Supabase (AV), Resend (AV), Apple, Google | USA (SCC/DPF) | bis Kontolöschung |
| 2 | Profil | Anzeige in der Familie | Nutzer | Anzeigename, Profilbild | Art. 6 Abs. 1 lit. b | Supabase (AV) | USA (Unternehmen; Server EU) | bis Löschung/Kontolöschung |
| 3 | Familien und Einladungen | gemeinsame Planung | Nutzer | Familienname, Farbe, Mitgliedschaft, Rolle, Einladungscodes, Fehlversuche (Rate-Limit) | Art. 6 Abs. 1 lit. b | Supabase (AV) | wie 2 | bis Löschung; Einladungen nach Ablauf |
| 4 | Aufgaben, Serien, Bilder, Verlauf | Kernfunktion | Nutzer, ggf. in Inhalten genannte Dritte | Titel, Beschreibung, Zeiten, Wiederholung/Reihum, Zuweisungen, Status, Bilder | Art. 6 Abs. 1 lit. b | Supabase (AV) | wie 2 | offen bis Löschung; erledigt/gelöscht 30 Tage |
| 5 | Mitteilungen, Live Activities, Erinnern | Hinweise zu Aufgaben (nur an aktuelle Mitglieder der Familie) | Nutzer | APNs-Token, Live-Activity-Token, App-Version, Zeitzone, Aufträge, Erinnern (wer/wen/wann) | Art. 6 Abs. 1 lit. b; Mitteilungen nur mit iOS-Einwilligung | Supabase (AV), Apple APNs | USA | Aufträge/Geräte 30 Tage; Erinnern 1 Tag |
| 6 | Outlook-Kalender (optional) | eigene Termine anzeigen | Nutzer | Refresh-Token (Vault), Termine (Titel, Zeit, Ort, Organisator) | Art. 6 Abs. 1 lit. a | Supabase (AV), Microsoft | USA | Fenster −7/+120 Tage; beim Trennen sofort |
| 7 | Datensicherung | Wiederherstellung nach Verlust | alle oben | alle oben, verschlüsselt (AES-256-GCM, RSA-4096) | Art. 6 Abs. 1 lit. f (Datensicherheit), Art. 32 | Backblaze (AV, nur Chiffrat) | Server EU; Unternehmen USA | 30 Tage (Object Lock) |
| 8 | Website und Kontaktformular | Information, Anfragen | Besucher | IP-Protokolle (Netlify), Name, E-Mail, Nachricht | Art. 6 Abs. 1 lit. f bzw. b | Netlify (AV) | USA | Anfragen ≤ 6 Monate |
| 9 | Meldungen (DSA) | rechtswidrige Inhalte bearbeiten | Meldende, Betroffene | Name, E-Mail, Begründung, Aufgaben-Kennung | Art. 6 Abs. 1 lit. c (Art. 16, 17 DSA) | Netlify (AV) | USA | 6 Monate nach Abschluss |
| 10 | Server-Protokolle | Betrieb, Sicherheit | Nutzer | IP, Zeitpunkt, Anfrage | Art. 6 Abs. 1 lit. f | Supabase (AV) | wie 2 | ≤ 1 Tag |

## Technische und organisatorische Maßnahmen (Art. 32 DSGVO)

- **Zugriffskontrolle:** Row Level Security auf allen Tabellen; Schreiben nur über geprüfte RPCs (ADR 0003); Storage-Buckets privat, nur kurzlebige signierte Links; Service-Schlüssel nur in Supabase-Secrets.
- **Verschlüsselung:** TLS für alle Verbindungen; Outlook-Token im Supabase Vault; Sicherung vor dem Verlassen von Supabase verschlüsselt, privater Schlüssel nur beim Verantwortlichen (Passwort-Manager + Offline-Kopie).
- **Datensparsamkeit:** keine Analyse-, Werbe- oder Tracking-Werkzeuge; Widget-Schnappschuss nur auf dem Gerät (vom Backup ausgenommen, bei jeder Abmeldung gelöscht); Outlook nur `Calendars.ReadBasic`; beim Austritt aus einer Familie enden offene Zuweisungen und Mitteilungen.
- **Missbrauchsschutz:** Rate-Limits für Einladungscodes, Erinnern (1/h, nachts gebündelt) und den Prüf-Zugang (10 Fehlversuche/h, atomar gezählt, gleich lange Ablehnungen); Einmal-Tokens für Cron-Funktionen.
- **Löschkonzept:** automatische Bereinigung (Verlauf 30 Tage, Aufträge 30 Tage, Sicherungen 30 Tage, Erinnern und Prüf-Zugang 1 Tag – täglich `private.purge_notifications`); Kontolöschung in der App inkl. Widerruf von Apple/Google.
- **Wiederherstellbarkeit:** nächtliche Sicherung, Probe-Wiederherstellung dokumentiert ([ADR 0009](../../decisions/0009-backups.md)).

## Auftragsverarbeitungsverträge (Art. 28 DSGVO) – Stand

| Anbieter | AV-Vertrag | Erledigt |
|---|---|---|
| Supabase | DPA im Dashboard anfordern/unterzeichnen (Organization › Legal Documents) | offen |
| Resend | DPA in den Resend-Einstellungen bzw. per Anfrage | offen |
| Netlify | DPA (Teil der Bedingungen, ggf. gesondert anfordern) | offen |
| Backblaze | DPA im Konto akzeptieren | offen |
