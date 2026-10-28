# Rechtsprüfung Familiar – Stand 2026-10-24

**Intern, kein Rechtsrat.** Systematische Prüfung, was für eine kostenlose, private iOS-App mit geteilten Familieninhalten gilt, und was daraufhin umgesetzt wurde. Vor dem Start empfiehlt sich trotzdem eine kurze anwaltliche Durchsicht (Datenschutzerklärung, Nutzungsbedingungen, Impressum).

## Ergebnis auf einen Blick

| Bereich | Anforderung | Stand |
|---|---|---|
| Impressum (§ 5 DDG) | leicht erkennbar, unmittelbar erreichbar, ständig verfügbar – auch in der App und im Store | ✅ Website; **neu:** in der App (Profil › Hilfe & Rechtliches, Anmeldebildschirm). Verantwortlicher Sven Olaf Kohrs. Hinweis nach § 18 MStV entfernt (keine journalistisch-redaktionellen Inhalte) |
| Datenschutzerklärung (Art. 12–14 DSGVO) | alle Pflichtangaben, Widerspruch nach Art. 21 hervorgehoben | ✅ **ergänzt:** Pflicht zur Angabe, Daten von Dritten, keine automatisierten Entscheidungen, § 25 TDDDG, eigener Abschnitt Widerspruchsrecht, Meldungen (DSA), Schutzzusage für Empfänger (auch für Apple 5.1.1(i)) |
| Endgerätezugriff (§ 25 TDDDG) | Speichern auf dem Gerät nur mit Einwilligung oder wenn unbedingt erforderlich | ✅ nur Anmeldung (inkl. Google-Anmeldestand), Push-Token, Widget-Liste (nicht im Backup), offener Einladungscode, Ablauf-Vermerke, Darstellung, Bild-Zwischenspeicher → Ausnahme § 25 Abs. 2 Nr. 2; kein Tracking. Vollständige Liste in der Datenschutzerklärung (zweite Prüfung 2026-10-24) |
| Verzeichnis der Verarbeitungen (Art. 30) und TOM (Art. 32) | Pflicht auch für Kleine bei regelmäßiger Verarbeitung | ✅ **neu:** [intern/verarbeitungsverzeichnis.md](intern/verarbeitungsverzeichnis.md) |
| Auftragsverarbeitung (Art. 28) | Verträge mit Supabase, Resend, Netlify, Backblaze | ⚠️ **du:** AV-Verträge abschließen (Launch-Liste) |
| Aufsichtsbehörde | Beschwerderecht nennen | ✅ LfD Niedersachsen |
| Kinder (Art. 8 DSGVO, §§ 104 ff. BGB) | unter 16 nur mit Eltern | ✅ Datenschutz und Nutzungsbedingungen: ab 16, jünger mit Zustimmung der Eltern |
| Digital Services Act – Hostingdienst | Art. 11/12 Kontaktstellen, Art. 14 Bedingungen, Art. 16 Meldeverfahren (gilt auch für Kleinstanbieter), Art. 17 Begründung, Art. 18 Straftaten | ✅ **neu:** Nutzungsbedingungen, Meldeformular familiar-app.de/melden mit allen Pflichtfeldern, „Inhalt melden“ in der App, Kontaktstelle im Impressum. ⚠️ **du:** Meldungen binnen kurzer Zeit beantworten (Eingangsbestätigung + Entscheidung) |
| Apple 1.2 Nutzerinhalte | Filter, Melden, Sperren, Kontakt | ✅ Melden (App + Web), Mitglieder entfernen/Familie verlassen, Kontakt veröffentlicht; Inhalte nur privat in Familien (in den Prüfhinweisen erklärt) |
| Apple 5.1.1 | Datenschutz-Link in der App und in App Store Connect; Kontolöschung in der App; Widerruf sozialer Anmeldungen | ✅ **neu:** Links in der App; Kontolöschung vorhanden; **neu:** Google-Verbindung wird beim Löschen widerrufen (Apple-Widerruf war schon da) |
| Apple 4.8 | „Mit Apple anmelden“ neben Google | ✅ |
| EU-Händlerstatus (DSA, App Store Connect) | Erklärung Pflicht | ⚠️ **du:** „Kein Händler“ wählen (Privatperson ohne Einnahmen), siehe [app-store.md](app-store.md) |
| Open-Source-Lizenzen | MIT: Copyright-Hinweis mitliefern; Apache 2.0: Lizenz + NOTICE; SIL OFL: Lizenz mit der Schrift | ✅ **neu:** Profil › Open-Source-Lizenzen (17 Einträge, erzeugt mit `tools/generate-licenses.py`) |
| Barrierefreiheit (BFSG) | gilt für bestimmte Verbraucherdienste ab 28.06.2025 | ✅ voraussichtlich nicht anwendbar (keine Kaufvorgänge; Kleinstunternehmen bei Dienstleistungen ausgenommen). Trotzdem umgesetzt: VoiceOver, Dynamic Type, Kontraste, automatischer Barrierefreiheits-Test |
| Verbraucherstreitbeilegung (VSBG) | Hinweis nur für Unternehmer Pflicht | ✅ freiwilliger Hinweis vorhanden; kein Link zur abgeschalteten EU-OS-Plattform |
| Markenrecht | Name „Familiar“ nicht verwechselbar mit älteren Marken (Klassen 9/42) | ⚠️ **du:** kostenlose Recherche bei DPMA und EUIPO (Launch-Liste); bei Treffern Anwalt fragen |
| Website | keine externen Dienste/Schriften, keine Cookies | ✅ Schrift lokal, keine Skripte Dritter; **neu:** Sicherheits-Header |
| Fremdmarken/Logos | Google-Knopf nach Branding-Richtlinien, offizieller App-Store-Badge | ✅ |

## Quellen

- Impressum in Apps: [eRecht24 – App-Impressum](https://www.e-recht24.de/impressum/10176-app-impressum.html), [IHK München – Impressum](https://www.ihk-muenchen.de/de/Service/Recht-und-Steuern/Internetrecht/Impressum-im-Internet/)
- DSA: [Art. 16 DSA (dejure)](https://dejure.org/gesetze/DSA/16.html), [Lausen – Melde- und Abhilfeverfahren](https://www.lausen.com/blog/melde-und-abhilfeverfahren-fuer-hostingdiensteanbieter-nach-dem-digital-services-act-dsa/), [IHK Nord Westfalen – DSA](https://www.ihk.de/nordwestfalen/wirtschaftsspiegel-online/praxis-und-ratgeber/digital-service-act-5799716)
- Apple: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app), [DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)
- § 25 TDDDG: [Gesetzestext](https://gesetze.legal/bund/tdddg/25), [Dr. Datenschutz](https://www.dr-datenschutz.de/cookies-und-datenschutz-zwischen-tdddg-und-dsgvo/)
- Kinder: [Dr. Datenschutz – Einwilligung von Kindern](https://www.dr-datenschutz.de/anforderungen-an-die-einwilligung-von-kindern-nach-der-dsgvo/)
- Aufsichtsbehörde: [LfD Niedersachsen – Beschwerde](https://www.lfd.niedersachsen.de/download/140049/Hinweise_fuer_die_Beschwerde.pdf)
- BFSG: [IHK Frankfurt – BFSG](https://www.frankfurt-main.ihk.de/recht/uebersicht-alle-rechtsthemen/barrierefreiheitsstaerkungsg-6282214)

## Zweite Prüfung (unabhängige Durchsicht, 2026-10-24)

Ein zweiter, unabhängiger Durchgang durch Code und Texte hat keine Lücke in den Zugriffsrechten gefunden, aber Abweichungen zwischen Text und tatsächlichem Verhalten. Behoben:

- **Recht auf Löschung (Art. 17 DSGVO, Apple 5.1.1(v)):** Die Kontolöschung konnte bei einer noch als aktiv geführten Live-Anzeige scheitern. Mitteilungs-Aufträge entstehen jetzt nur noch für bestehende Profile (Migration 0018, Test K1).
- **Ausgetretene Mitglieder:** bekamen weiter Erinnerungen mit Aufgabentiteln. Jetzt enden beim Austritt alle offenen Zuweisungen; Mitteilungen gehen nur an aktuelle Mitglieder.
- **Löschfrist „Erinnern“ (1 Tag):** wird jetzt täglich durchgesetzt, ebenso für die Fehlversuche des Prüf-Zugangs.
- **Texte:** Widget-Liste (alle offenen Aufgaben, nicht im Backup), vollständige Liste der Gerätespeicherung, Siri-Titel, Live-Anzeige-Token, Google-Widerruf beim Löschen, Hinweis auf Änderungen der Nutzungsbedingungen per E-Mail, App-Store-Text „Familiendaten in der EU“.

## Offene Restrisiken (bewusst)

- **Speicher-Missbrauch:** Ein Familienmitglied könnte viele Bilder hochladen und den kostenlosen Speicher (1 GB) füllen. Grenzen: 10 Bilder je Aufgabe, 5 MB je Bild, verwaiste Dateien werden nach einem Tag gelöscht. Bei Bedarf Kontingent je Familie nachrüsten.
- **Verfügbarkeit:** Supabase Free pausiert Projekte ohne Aktivität nach 7 Tagen; im Betrieb unkritisch, Nutzungsbedingungen sagen keine ständige Verfügbarkeit zu.
- **Änderungen der Nutzungsbedingungen:** Die Bedingungen versprechen eine Ankündigung per E-Mail. Bei wesentlichen Änderungen deshalb vorher allen Nutzern schreiben (über Resend; im kostenlosen Tarif höchstens 100 E-Mails am Tag – bei vielen Nutzern auf mehrere Tage verteilen).
