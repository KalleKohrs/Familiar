# Launch-Liste: Was deine Zeit braucht

Alles, was ich ohne dich nicht starttauglich machen kann – Konten, Zahlungen, Portal-Klicks, Freigaben. Wenn du Zeit hast, gehen wir das gemeinsam Punkt für Punkt durch; jeder Punkt bekommt dann eine Klick-für-Klick-Anleitung nach aktueller offizieller Doku. Geheime Werte kommen nie in den Chat.

Grundsatz (2026-10-21): Familiar wird von Anfang an so gebaut, wie es zum App-Store-Start sein muss – keine Zwischenlösungen.

| # | Punkt | Warum | Kosten | Dauer (ca.) |
|---|---|---|---|---|
| 1 | **Apple Developer Program** (als Privatperson; Bezahlung am **3.12.2026**; danach Team-ID in `Local.xcconfig` und `website/apple-app-site-association` prüfen) | Ohne geht nichts davon: TestFlight, App Store, Mitteilungen & Live Activities (Phase 7 – Server ist fertig und wartet nur auf den APNs-Schlüssel: Secrets `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, Anleitung [setup/apple.md](setup/apple.md) Abschnitt 4; App-ID braucht die Capability „Push Notifications“), „Mit Apple anmelden“, Einladungslinks (Universal Links) | 99 €/Jahr | 30 min + Prüfung durch Apple (1–2 Tage) |
| 2 | **Produktions-Projekt bei Supabase** im **Free-Tarif** (Entscheidung 2026-10-21: kostenlos), Region **EU (Frankfurt)** – getrennt vom Entwicklungsprojekt (Free erlaubt 2 aktive Projekte). Folgen: Pause nach 7 Tagen ohne Nutzer-Aktivität (Warn-Mail vorher), keine automatischen Backups (eigene nächtliche Sicherung folgt), 500 MB DB / 1 GB Dateien / 5 GB ungecachter Traffic | Echte Nutzerdaten getrennt von Tests | kostenlos | 30 min, Migrationen spiele ich ein |
| 3 | ~~**Microsoft: Herausgeber verifizieren**~~ – entfällt (Privatperson, 2026-10-21); stattdessen IT-Freigabe pro Firma, in der App eingebaut | Ohne Verifizierung blockieren viele Firmen die Outlook-Anbindung (wie bei dir) | kostenlos (Microsoft AI Cloud Partner Program) | 1 h + Prüfung |
| 4 | ✅ **Microsoft: Zertifikat statt Client Secret** (eingerichtet 2026-10-21; altes Client Secret gelöscht, Code nutzt seit 2026-10-22 nur noch das Zertifikat) | Von Microsoft für den Produktivbetrieb empfohlen; läuft nicht nach 6 Monaten ab | kostenlos | 15 min – ich erzeuge das Zertifikat, du lädst es hoch |
| 5 | ✅ **Google-Anmeldung** (Phase 2b, eingerichtet und getestet 2026-10-21; Anleitung [setup/google.md](setup/google.md)) | „Mit Google anmelden“ | kostenlos | 30 min |
| 6 | ✅ **Website familiar-app.de veröffentlichen** (online seit 2026-10-21; nach Textänderungen Ordner `website` erneut hochladen) (Ordner `website/`, Netlify – kostenlos, Anleitung [setup/website.md](setup/website.md)) mit Einladungslinks, Datenschutzerklärung, Impressum, Hilfe, IT-Infoseite | Pflicht für App Store und DSGVO; Entwürfe: [legal/datenschutz.md](legal/datenschutz.md), [legal/impressum.md](legal/impressum.md) – du ergänzt Angaben zu dir, am besten rechtlich prüfen lassen | – | 1 h |
| 7 | **App-Store-Eintrag**: Name, Beschreibung, Screenshots, Datenschutz-Angaben („Nutrition Label“) | Veröffentlichung; Entwurf: [legal/app-store.md](legal/app-store.md) | – | 1–2 h |
| 8 | **Firmen-IT**: Familiar für deinen Outlook-Kalender freigeben | Nur für dich persönlich; Vorlage: [setup/outlook-it-freigabe.md](setup/outlook-it-freigabe.md). Entfällt für andere nach Punkt 3 | – | Mail schreiben |
| 9 | **Zugang für Apples App-Prüfung** | Prüfer können keinen E-Mail-Code empfangen. Fertig gebaut (Edge Function `review-sign-in`): du legst in Supabase die Secrets `REVIEW_EMAIL` (eigene Adresse nur für die Prüfung) und `REVIEW_CODE` (10 Ziffern, nur für Apple) an und trägst beides in App Store Connect unter „Anmeldedaten für die Prüfung“ ein. Nach der Freigabe kann `REVIEW_CODE` gelöscht werden | – | 10 min |
| 10 | **Datensicherung** (GitHub, kostenlos): Code-Sicherung + nächtliche verschlüsselte Datenbank- und Bildersicherung | Supabase Free hat keine Backups; Code liegt bisher nur auf einem Mac | kostenlos | 30 min, Anleitung [setup/backup.md](setup/backup.md) |
| 11 | **Website auf „im App Store“ umstellen** (am Tag der Veröffentlichung) | Alle „Laden im App Store“-Knöpfe der Website führen über `familiar-app.de/app`; bis zum Start zeigt diese Adresse „Bald im App Store“. Zum Start in `website/_redirects` die letzte Zeile einkommentieren (`#` weg), `idXXXXXXXXXX` durch die Apple-ID der App ersetzen (App Store Connect › App-Informationen › Apple-ID) und den Ordner `website` erneut bei Netlify hochladen | – | 5 min |

## Was ich bis dahin selbstständig weiterbaue

- Feinschliff und Design-Durchgang (Leucht-Effekte, Karten nur wo sinnvoll, Barrierefreiheit, große Schrift, „Bewegung reduzieren“).
- Phase 10: Qualität (VoiceOver, Dynamic Type bis zur größten Stufe, kleine Displays, Leistung), Privacy Manifest.
- Vorbereitung Phase 7 (Mitteilungen & Live Activities) so weit, wie es ohne Apple-Schlüssel geht: Datenmodell, Versand-Warteschlange, Live-Activity-Oberfläche, Tests.
- Texte für Datenschutzerklärung, Impressum und App-Store-Eintrag als Entwürfe (erledigt, siehe `docs/legal/`); Screenshots nach dem Design-Durchgang.
