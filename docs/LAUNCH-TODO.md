# Launch-Liste: Was deine Zeit braucht

Alles, was ich ohne dich nicht starttauglich machen kann – Konten, Zahlungen, Portal-Klicks, Freigaben. Wenn du Zeit hast, gehen wir das gemeinsam Punkt für Punkt durch; jeder Punkt bekommt dann eine Klick-für-Klick-Anleitung nach aktueller offizieller Doku. Geheime Werte kommen nie in den Chat.

Grundsatz (2026-10-21): Familiar wird von Anfang an so gebaut, wie es zum App-Store-Start sein muss – keine Zwischenlösungen.

| # | Punkt | Warum | Kosten | Dauer (ca.) |
|---|---|---|---|---|
| 1 | **Apple Developer Program** | Ohne geht nichts davon: TestFlight, App Store, Mitteilungen & Live Activities (Phase 7 – Server ist fertig und wartet nur auf den APNs-Schlüssel: Secrets `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, Anleitung [setup/apple.md](setup/apple.md) Abschnitt 4; App-ID braucht die Capability „Push Notifications“), „Mit Apple anmelden“, Einladungslinks (Universal Links) | 99 €/Jahr | 30 min + Prüfung durch Apple (1–2 Tage) |
| 2 | **Produktions-Projekt bei Supabase** (getrennt vom Entwicklungsprojekt) mit **Pro-Tarif**, Region **EU (Frankfurt)** – die Datenschutzerklärung sagt „Server in der EU“ | Echte Nutzerdaten getrennt von Tests; tägliche Backups mit Wiederherstellung auf die Minute (PITR), kein Pausieren | ab ca. 25 $/Monat (+ PITR) | 30 min, Migrationen spiele ich ein |
| 3 | **Microsoft: Herausgeber verifizieren** (Publisher Verification) | Ohne Verifizierung blockieren viele Firmen die Outlook-Anbindung (wie bei dir) | kostenlos (Microsoft AI Cloud Partner Program) | 1 h + Prüfung |
| 4 | **Microsoft: Zertifikat statt Client Secret** | Von Microsoft für den Produktivbetrieb empfohlen; läuft nicht nach 6 Monaten ab | kostenlos | 15 min – ich erzeuge das Zertifikat, du lädst es hoch |
| 5 | **Google-Anmeldung** (Phase 2b) | „Mit Google anmelden“ | kostenlos | 30 min |
| 6 | **Website familiar-app.de veröffentlichen** (Ordner `website/`, z. B. Cloudflare Pages – kostenlos) mit Einladungslinks, Datenschutzerklärung, Impressum, Support-Seite | Pflicht für App Store und DSGVO; Entwürfe: [legal/datenschutz.md](legal/datenschutz.md), [legal/impressum.md](legal/impressum.md) – du ergänzt Angaben zu dir, am besten rechtlich prüfen lassen | – | 1 h |
| 7 | **App-Store-Eintrag**: Name, Beschreibung, Screenshots, Datenschutz-Angaben („Nutrition Label“) | Veröffentlichung; Entwurf: [legal/app-store.md](legal/app-store.md) | – | 1–2 h |
| 8 | **Firmen-IT**: Familiar für deinen Outlook-Kalender freigeben | Nur für dich persönlich; Vorlage: [setup/outlook-it-freigabe.md](setup/outlook-it-freigabe.md). Entfällt für andere nach Punkt 3 | – | Mail schreiben |
| 9 | **Zugang für Apples App-Prüfung** | Prüfer können keinen E-Mail-Code empfangen; wir brauchen ein Demo-Konto mit Postfach, auf das du schnell reagieren kannst, oder einen festen Prüf-Zugang (Lösung erarbeite ich nach aktueller Doku) | – | 15 min |

## Was ich bis dahin selbstständig weiterbaue

- Feinschliff und Design-Durchgang (Leucht-Effekte, Karten nur wo sinnvoll, Barrierefreiheit, große Schrift, „Bewegung reduzieren“).
- Phase 10: Qualität (VoiceOver, Dynamic Type bis zur größten Stufe, kleine Displays, Leistung), Privacy Manifest.
- Vorbereitung Phase 7 (Mitteilungen & Live Activities) so weit, wie es ohne Apple-Schlüssel geht: Datenmodell, Versand-Warteschlange, Live-Activity-Oberfläche, Tests.
- Texte für Datenschutzerklärung, Impressum und App-Store-Eintrag als Entwürfe (erledigt, siehe `docs/legal/`); Screenshots nach dem Design-Durchgang.
