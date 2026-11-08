# Launch-Liste: Was deine Zeit braucht

Alles, was ich ohne dich nicht starttauglich machen kann – Konten, Zahlungen, Portal-Klicks, Freigaben. Wenn du Zeit hast, gehen wir das gemeinsam Punkt für Punkt durch; jeder Punkt bekommt dann eine Klick-für-Klick-Anleitung nach aktueller offizieller Doku. Geheime Werte kommen nie in den Chat.

Grundsatz (2026-10-21): Familiar wird von Anfang an so gebaut, wie es zum App-Store-Start sein muss – keine Zwischenlösungen.

| # | Punkt | Warum | Kosten | Dauer (ca.) |
|---|---|---|---|---|
| 1 | **Apple Developer Program** (Privatperson **Sven Olaf Kohrs** mit eigener neuer Apple-ID – er ist Anbieter im App Store und steht im Impressum; Anmeldung jetzt über die App „Apple Developer“, nicht erst am 3.12.). Team-ID `28RWK74DGY` ist eingetragen (`ios/Config/Local.xcconfig`, `website/apple-app-site-association` und `.well-known/…`); **offen:** Website neu hochladen. Beim ersten Signieren in Xcode prüfen, ob Bundle-ID `de.kohrs.familiar` und App Group `group.de.kohrs.familiar` frei sind – meldet Xcode „bereits vergeben“, nehmen wir eine neue Bundle-ID | Ohne geht nichts davon: TestFlight, App Store, Mitteilungen & Live Activities (Phase 7 – Server ist fertig und wartet nur auf den APNs-Schlüssel: Secrets `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, Anleitung [setup/apple.md](setup/apple.md) Abschnitt 4; App-ID braucht die Capability „Push Notifications“), „Mit Apple anmelden“, Einladungslinks (Universal Links) | 99 €/Jahr | 30 min + Prüfung durch Apple (1–2 Tage) |
| 2 | **Produktions-Projekt bei Supabase** im **Free-Tarif** (Entscheidung 2026-10-21: kostenlos), Region **EU (Irland, eu-west-1)** (angelegt 2026-10-29 als `familiar-prod`, Ref `fhyfjxzctemxqewedqiy`; Datenschutzerklärung nennt Irland) – getrennt vom Entwicklungsprojekt (Free erlaubt 2 aktive Projekte). Folgen: Pause nach 7 Tagen ohne Nutzer-Aktivität (Warn-Mail vorher), keine automatischen Backups (eigene nächtliche Sicherung folgt), 500 MB DB / 1 GB Dateien / 5 GB ungecachter Traffic | Echte Nutzerdaten getrennt von Tests | kostenlos | 30 min, Migrationen spiele ich ein |
| 3 | ~~**Microsoft: Herausgeber verifizieren**~~ – entfällt (Privatperson, 2026-10-21); stattdessen IT-Freigabe pro Firma, in der App eingebaut | Ohne Verifizierung blockieren viele Firmen die Outlook-Anbindung (wie bei dir) | kostenlos (Microsoft AI Cloud Partner Program) | 1 h + Prüfung |
| 4 | ✅ **Microsoft: Zertifikat statt Client Secret** (eingerichtet 2026-10-21; altes Client Secret gelöscht, Code nutzt seit 2026-10-22 nur noch das Zertifikat) | Von Microsoft für den Produktivbetrieb empfohlen; läuft nicht nach 6 Monaten ab | kostenlos | 15 min – ich erzeuge das Zertifikat, du lädst es hoch |
| 5 | ✅ **Google-Anmeldung** (Phase 2b, eingerichtet und getestet 2026-10-21; Anleitung [setup/google.md](setup/google.md)) | „Mit Google anmelden“ | kostenlos | 30 min |
| 6 | ✅ **Website familiar-app.de veröffentlichen** (online seit 2026-10-21; nach Textänderungen Ordner `website` erneut hochladen) (Ordner `website/`, Netlify – kostenlos, Anleitung [setup/website.md](setup/website.md)) mit Einladungslinks, Datenschutzerklärung, Impressum, Hilfe, IT-Infoseite | Pflicht für App Store und DSGVO; Entwürfe: [legal/datenschutz.md](legal/datenschutz.md), [legal/impressum.md](legal/impressum.md) – du ergänzt Angaben zu dir, am besten rechtlich prüfen lassen | – | 1 h |
| 7 | **App-Store-Eintrag**: Name, Beschreibung, Screenshots, Datenschutz-Angaben („Nutrition Label“) | Veröffentlichung; Entwurf: [legal/app-store.md](legal/app-store.md) | – | 1–2 h |
| 8 | **Firmen-IT**: Familiar für deinen Outlook-Kalender freigeben | Nur für dich persönlich; Vorlage: [setup/outlook-it-freigabe.md](setup/outlook-it-freigabe.md). Entfällt für andere nach Punkt 3 | – | Mail schreiben |
| 9 | **Zugang für Apples App-Prüfung** | Prüfer können keinen E-Mail-Code empfangen. Fertig gebaut (Edge Function `review-sign-in`): du legst in Supabase die Secrets `REVIEW_EMAIL` (eigene, **nicht erratbare** Adresse nur für die Prüfung, z. B. `pruefung-7k3q@familiar-app.de` – sie muss keine echten E-Mails empfangen; wer sie kennt, könnte den Zugang mit Fehlversuchen für eine Stunde sperren) und `REVIEW_CODE` (10 Ziffern, nur für Apple) an und trägst beides in App Store Connect unter „Anmeldedaten für die Prüfung“ ein. Nach der Freigabe kann `REVIEW_CODE` gelöscht werden | – | 10 min |
| 10 | ✅ **Datensicherung Dev-Projekt** eingerichtet und geprüft (2026-10-22: Backblaze B2 EU Central, Object Lock 30 Tage, erster Lauf und Probe-Wiederherstellung bestanden; Entscheidung [ADR 0009](decisions/0009-backups.md)). **Offen:** beim Produktionsprojekt eigener Bucket, eigener Schreib-Schlüssel und Secrets (Anleitung [setup/backup.md](setup/backup.md), Schritte 2–6), dann einmal vollständige Wiederherstellung ins frische Produktionsprojekt üben; Website-Datenschutzerklärung (Backblaze, 30 Tage) neu hochladen. Unabhängig davon: Quellcode privat bei GitHub sichern Unabhängig davon: Quellcode privat bei GitHub sichern, Anleitung [setup/github.md](setup/github.md). | Supabase Free hat keine Backups | kostenlos | 15 min |
| 11 | **Website auf „im App Store“ umstellen** (am Tag der Veröffentlichung) | Alle „Laden im App Store“-Knöpfe der Website führen über `familiar-app.de/app`; bis zum Start zeigt diese Adresse „Bald im App Store“. Zum Start in `website/_redirects` die letzte Zeile einkommentieren (`#` weg), `idXXXXXXXXXX` durch die Apple-ID der App ersetzen (App Store Connect › App-Informationen › Apple-ID) und den Ordner `website` erneut bei Netlify hochladen | – | 5 min |
| 12 | ~~Migration 0018 einspielen~~ erledigt am 2026-10-29 (eingespielt, Tests grün, Funktionen deployt). Ursprünglich: **Migration 0018 einspielen** (Reihum, Erinnern, Austritt aus Familien, Sichtbarkeit bei Reihum, sichere Kontolöschung, Sperre für den Prüf-Zugang); danach deploye ich `review-sign-in` (Sperre) und `push-dispatch` (Text fürs Erinnern, keine Mitteilungen an Ausgetretene) neu und lasse `supabase/tests/0010_rotation_nudges.sql` laufen: Datei `supabase/migrations/0018_rotation_and_nudges.sql` im Supabase-SQL-Editor ausführen; ich lege sie dir in die Zwischenablage und prüfe danach mit den Tests | Ohne sie kann die neue App-Version keine Aufgaben laden (neue Spalten) | – | 2 min |
| 13 | **Auftragsverarbeitungsverträge** (Art. 28 DSGVO) mit Supabase, Resend, Netlify und Backblaze abschließen – meist ein Klick im jeweiligen Konto; Stand in [legal/intern/verarbeitungsverzeichnis.md](legal/intern/verarbeitungsverzeichnis.md) | Pflicht, sobald echte Nutzerdaten verarbeitet werden | kostenlos | 20 min |
| 14 | **Markenrecherche „Familiar“** bei [DPMA](https://register.dpma.de) und [EUIPO](https://euipo.europa.eu/eSearch/) (Klassen 9 und 42) | Vermeidet Abmahnungen wegen des Namens | kostenlos | 15 min |
| 15 | **Netlify: Formular „meldung“ prüfen** – nach dem Hochladen in Netlify unter Forms sichtbar? E-Mail-Benachrichtigung an info@ einschalten | Meldungen rechtswidriger Inhalte müssen ankommen und zeitnah beantwortet werden (DSA) | – | 5 min |
| 16 | **App Store Connect: Händlerstatus** „Kein Händler“ erklären, Datenschutz-URL und Support-URL eintragen ([legal/app-store.md](legal/app-store.md)) | Pflicht für die EU-Veröffentlichung | – | 10 min |
| 17 | **Anwaltliche Kurzprüfung** von Datenschutzerklärung, Nutzungsbedingungen und Impressum (Prüfbericht: [legal/rechtscheck.md](legal/rechtscheck.md)) | Empfohlen vor dem Start | je nach Anwalt | – |

## Was ich bis dahin selbstständig weiterbaue

- Feinschliff und Design-Durchgang (Leucht-Effekte, Karten nur wo sinnvoll, Barrierefreiheit, große Schrift, „Bewegung reduzieren“).
- Phase 10: Qualität (VoiceOver, Dynamic Type bis zur größten Stufe, kleine Displays, Leistung), Privacy Manifest.
- Hinweis zu Punkt 1: Widgets nutzen eine App Group (`group.<Bundle-ID>`); Xcode legt sie mit automatischer Signierung im Developer-Portal an. Vorbereitung Phase 7 (Mitteilungen & Live Activities) so weit, wie es ohne Apple-Schlüssel geht: Datenmodell, Versand-Warteschlange, Live-Activity-Oberfläche, Tests.
- Texte für Datenschutzerklärung, Impressum und App-Store-Eintrag als Entwürfe (erledigt, siehe `docs/legal/`); Screenshots nach dem Design-Durchgang.


## Stand 2026-10-30: bei Apple zur Prüfung

Version 0.1.0 (Build 5) ist eingereicht. Nach der Freigabe:

1. **Secret `REVIEW_CODE` löschen** (Supabase › Edge Functions › Secrets, Projekt „Familiar“), damit der Prüf-Zugang aus ist.
2. **Website** (`website/`) bei Netlify neu hochladen (Irland-Text) und `website/_redirects` auf die Apple-ID der App umstellen (Punkt 11).
3. **Prüf-Konto** und seine Beispiel-Familie bleiben nur, solange Apple sie braucht; danach löschen.
4. Offen bleiben die Punkte 13 (Auftragsverarbeitungsverträge), 14 (Markenrecherche), 15 (Netlify-Formular), 17 (Anwaltsprüfung) und der Backup-Bucket für die Produktion (Punkt 10).
5. Bekannte Einschränkung: Live-Activity-Updates laufen im Minutentakt des Servers; das Abhaken auf dem Sperrbildschirm beendet die Activity sofort in der App.

## Stand 2026-11-08: im App Store

Die App ist veröffentlicht (Apple-ID `6828540894`, <https://apps.apple.com/de/app/id6828540894>). `website/_redirects` leitet `/app` dorthin (Punkt 11 erledigt, Ordner `website` noch bei Netlify hochladen). Offen: `REVIEW_CODE` löschen, Punkte 13, 14, 15, 17 und der Backup-Bucket (Punkt 10).
