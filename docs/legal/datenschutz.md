# Datenschutzerklärung – Familiar (Entwurf)

> **Entwurf, Stand 2026-10-24.** Von mir aus dem tatsächlichen Datenfluss der App abgeleitet (Datenbank-Schema, Edge Functions, Privacy Manifest). Ich bin kein Anwalt: Bitte vor Veröffentlichung prüfen lassen (z. B. Anwalt oder seriöser Generator wie eRecht24) und die Platzhalter `[…]` ergänzen. Veröffentlichung unter `https://familiar-app.de/datenschutz`.

## 1. Verantwortlicher

Familiar wird von einer Privatperson entwickelt und betrieben:

Sven Olaf Kohrs
Claus-von-Stauffenberg-Weg 1
21684 Stade
E-Mail: [info@familiar-app.de](mailto:info@familiar-app.de)

## 2. Grundsätze

Familiar ist ein Familienplaner. Wir verarbeiten nur die Daten, die für die Funktionen der App nötig sind. Es gibt **keine Werbung, kein Tracking, keine Analyse-Tools** und keinen Verkauf von Daten.

## 3. Welche Daten wir verarbeiten und warum

| Daten | Zweck | Rechtsgrundlage |
|---|---|---|
| **E-Mail-Adresse** | Anmeldung per Einmal-Code; Zuordnung deines Kontos | Art. 6 Abs. 1 lit. b DSGVO (Vertrag) |
| **„Mit Apple anmelden“** (freiwillig): Apple-Kennung, E-Mail-Adresse (ggf. Apples Weiterleitungsadresse), beim ersten Mal dein Name | Anmeldung; der Name dient nur als Vorschlag für dein Profil | Art. 6 Abs. 1 lit. b DSGVO |
| **„Mit Google anmelden“** (freiwillig): Google-Kennung, E-Mail-Adresse, Name und Profilbild-Adresse aus deinem Google-Konto | Anmeldung | Art. 6 Abs. 1 lit. b DSGVO |
| **Anzeigename, Profilbild** (freiwillig) | Damit deine Familie sieht, wer Aufgaben übernimmt | Art. 6 Abs. 1 lit. b DSGVO |
| **Familien** (Name, Farbe, Mitglieder, Rollen, Einladungscodes) | Gemeinsame Planung | Art. 6 Abs. 1 lit. b DSGVO |
| **Aufgaben** (Titel, Beschreibung, Datum/Uhrzeit, Wiederholung inkl. „Reihum“-Reihenfolge, Zuweisungen, Erledigt-Status, Bilder) | Kernfunktion | Art. 6 Abs. 1 lit. b DSGVO |
| **Erinnerungen („Erinnern“)**: wer wen an welche Aufgabe erinnert hat, mit Zeitpunkt | Zustellung der Erinnerung; Schutz vor zu vielen Erinnerungen (höchstens eine pro Stunde) | Art. 6 Abs. 1 lit. b DSGVO |
| **Geräte-Kennung für Mitteilungen** (APNs-Token, App-Version, Zeitzone) und **Push-Token der Live-Anzeigen** (zum Starten, Aktualisieren und Beenden) | Mitteilungen und Live-Anzeigen auf dem Sperrbildschirm | Art. 6 Abs. 1 lit. b DSGVO; die Mitteilungen selbst nur mit deiner Einwilligung in iOS |
| **Outlook-Termine** (nur wenn du Outlook verbindest: Titel, Zeit, Ort, Organisator, Absage-Status der gewählten Kalender) | Anzeige im Familiar-Kalender – **nur für dich**, nicht für deine Familie | Art. 6 Abs. 1 lit. a DSGVO (Einwilligung durch Verbinden) |
| **Server-Protokolle** (IP-Adresse, Zeitpunkt, Anfrage) – App-Server und Website | Betrieb und Sicherheit | Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an einem sicheren Betrieb) |
| **Kontaktformular** auf familiar-app.de (Name, E-Mail-Adresse, Nachricht) | Beantwortung deiner Anfrage | Art. 6 Abs. 1 lit. b bzw. f DSGVO |
| **Meldungen rechtswidriger Inhalte** (Name, E-Mail-Adresse, Begründung, betroffene Aufgabe) – über familiar-app.de/melden oder aus der App | Prüfung und Bearbeitung der Meldung nach dem Digital Services Act; Information der meldenden und der betroffenen Person | Art. 6 Abs. 1 lit. c DSGVO (Art. 16, 17 DSA) |

**Pflicht zur Angabe:** Ohne E-Mail-Adresse bzw. Apple- oder Google-Anmeldung kannst du kein Konto anlegen und Familiar nicht nutzen. Alle anderen Angaben (Profilbild, Bilder, Outlook, Mitteilungen) sind freiwillig.

**Daten von anderen:** Mitglieder deiner Familie können dich Aufgaben zuweisen, dich erinnern oder dich in Beschreibungen erwähnen; dein Name und Profilbild stammen aus deinem eigenen Profil.

**Keine automatisierten Entscheidungen:** Es gibt kein Profiling und keine automatisierten Einzelentscheidungen im Sinne von Art. 22 DSGVO.

**Speicherung auf deinem Gerät (§ 25 TDDDG):** Die App speichert auf deinem Gerät nur, was für die von dir genutzten Funktionen unbedingt erforderlich ist: die Anmeldung (im Schlüsselbund; bei „Mit Google anmelden“ zusätzlich der Anmeldestand von Google), das Geräte-Token für Mitteilungen, die Liste für die Widgets, einen noch nicht eingelösten Einladungscode, kleine Vermerke zum Ablauf (ob du dein Profil bestätigt und die Mitteilungs-Erklärung gesehen hast), deine Darstellungs-Einstellung und vorübergehend zwischengespeicherte Bilder. Dafür ist keine Einwilligung nötig (§ 25 Abs. 2 Nr. 2 TDDDG). Es gibt keine Analyse- oder Werbekennungen.

**Wer sieht was:** Aufgaben, Bilder und Status sehen die Mitglieder der jeweiligen Familie; ist eine Familie auf „nur Zugewiesene“ gestellt, sehen nur zugewiesene Personen und die Erstellerin bzw. der Ersteller die Aufgabe. Bei Aufgaben „Reihum“ sehen alle, die bei der Reihe mitmachen, alle Termine dieser Reihe (damit ihr tauschen und euch erinnern könnt). Verlässt jemand eine Familie oder wird entfernt, enden dort seine offenen Zuweisungen, und er bekommt keine Mitteilungen mehr zu Aufgaben dieser Familie. Deine Outlook-Termine sieht niemand außer dir.

**Widgets und Siri:** Für die Widgets „Heute“ legt die App eine Liste deiner offenen Aufgaben (Titel, Datum und Uhrzeit, Familie, Initialen der Zugewiesenen) **nur auf deinem Gerät** ab, damit das Widget auch ohne geöffnete App zum nächsten Tag weiterschalten kann. Die Liste ist von iCloud- und Computer-Backups ausgenommen, verlässt das Gerät nicht und wird bei jeder Abmeldung gelöscht. Auf dem Sperrbildschirm blendet iOS die Titel aus, wenn du dort keinen Zugriff im gesperrten Zustand erlaubst. Damit Siri und Kurzbefehle deine Aufgaben beim Namen erkennen (z. B. „Müll rausbringen in Familiar erledigen“), übergibt die App die Titel deiner offenen Aufgaben an iOS auf deinem Gerät. Deine Spracheingabe verarbeitet Apple nach den Siri-Bedingungen; Familiar erhält davon nur die erkannte Aufgabe bzw. den Titel. Siri nennt, erledigt oder legt Aufgaben nur bei entsperrtem iPhone an.

**Outlook:** Familiar erhält von Microsoft nur das Recht, deine Kalender zu **lesen** (`Calendars.ReadBasic` – ohne Termin-Text und Anhänge). Familiar schreibt nie in deinen Kalender. Das Zugriffs-Token liegt verschlüsselt auf dem Server. Du kannst die Verbindung jederzeit in der App trennen; dann werden Token und gespeicherte Termine gelöscht.

## 4. Empfänger und Auftragsverarbeiter

| Dienst | Zweck | Sitz / Übermittlung |
|---|---|---|
| **Supabase Inc.** | Datenbank, Anmeldung, Dateispeicher, Server-Funktionen | Server in der EU (Frankfurt am Main); Unternehmen in den USA – Auftragsverarbeitungsvertrag und EU-Standardvertragsklauseln |
| **Netlify, Inc.** | Hosting der Website familiar-app.de und Empfang von Kontaktformular und Meldungen | USA – Auftragsverarbeitungsvertrag und EU-Standardvertragsklauseln |
| **Resend, Inc.** | Versand der Anmelde-Codes per E-Mail | USA – Auftragsverarbeitungsvertrag und EU-Standardvertragsklauseln |
| **Backblaze, Inc.** | Speicherort der nächtlichen Datensicherung; erhält nur Daten, die vorher bei Supabase verschlüsselt wurden und die Backblaze nicht lesen kann | Server in der EU (Amsterdam); Unternehmen in den USA – Auftragsverarbeitungsvertrag und EU-Standardvertragsklauseln |
| **Apple Inc.** (Apple Push Notification service) | Zustellung von Mitteilungen und Live-Anzeigen; erhält Geräte-Token und Mitteilungsinhalt (z. B. Aufgabentitel) | USA bzw. Apple Distribution International (Irland) |
| **Microsoft** | Nur bei verbundenem Outlook: Abruf deiner Termine | nach den Bedingungen deines Microsoft-Kontos |
| **Google** – nur bei „Mit Google anmelden“ | Anmeldung (Google Ireland Limited); beim Löschen deines Kontos widerrufen wir die Verbindung zu deinem Google-Konto | Irland, ggf. USA – EU-US Data Privacy Framework bzw. EU-Standardvertragsklauseln |
| **Apple** – nur bei „Mit Apple anmelden“ | Anmeldung; beim Löschen deines Kontos widerrufen wir die Verknüpfung bei Apple | USA bzw. Apple Distribution International (Irland) |

Supabase, Netlify, Resend und Backblaze verarbeiten Daten nur in unserem Auftrag (Art. 28 DSGVO) und sind vertraglich verpflichtet, sie mindestens so zu schützen wie in dieser Erklärung beschrieben. Bei Übermittlungen in die USA stützen wir uns auf das EU-US Data Privacy Framework, soweit der Anbieter zertifiziert ist, und ergänzend auf die EU-Standardvertragsklauseln. Apple, Google und Microsoft handeln bei der Anmeldung bzw. dem Kalenderzugriff in eigener Verantwortung nach ihren Datenschutzbestimmungen. Wir verkaufen keine Daten und geben sie an niemanden sonst weiter, außer wir sind gesetzlich dazu verpflichtet.

## 5. Speicherdauer

- **Konto, Familien, offene Aufgaben:** bis du sie löschst bzw. dein Konto löschst.
- **Erledigte und gelöschte Aufgaben:** 30 Tage im Verlauf (zum Wiederherstellen), danach automatisch endgültig gelöscht – einschließlich Bildern. Admins können den Verlauf ihrer Familie auch früher endgültig leeren.
- **Mitteilungs-Aufträge, beendete Live-Anzeigen, abgemeldete Geräte:** 30 Tage, danach automatisch gelöscht.
- **Erinnerungen („Erinnern“):** der Vermerk, wer wen erinnert hat, nach 1 Tag; der Mitteilungs-Auftrag wie oben nach 30 Tagen.
- **Outlook-Termine:** nur ein Fenster von 7 Tagen zurück bis 120 Tage voraus; ältere fallen beim Abgleich weg; beim Trennen sofort gelöscht.
- **Datensicherung:** jede Nacht eine verschlüsselte Kopie; jeder Stand wird nach 30 Tagen automatisch gelöscht. Was du löschst, verschwindet so spätestens nach etwa 31 Tagen auch aus der Sicherung.
- **Server-Protokolle:** bis zu 1 Tag (Aufbewahrung durch Supabase); Website-Protokolle nach den Vorgaben von Netlify.
- **Kontaktanfragen:** bis die Anfrage erledigt ist, danach löschen wir sie (spätestens nach 6 Monaten), sofern keine gesetzliche Aufbewahrungspflicht besteht.
- **Meldungen rechtswidriger Inhalte:** 6 Monate nach Abschluss des Verfahrens, länger nur, wenn sie für ein Rechtsverfahren gebraucht werden.

## 6. Konto löschen

In der App unter **Profil › Konto löschen**. Gelöscht werden dein Konto, Profil und Profilbild, deine Mitgliedschaften, Zuweisungen, Geräte und Outlook-Verbindung. Hast du dich mit Apple angemeldet, bestätigst du das Löschen kurz bei Apple; wir widerrufen dann die Verknüpfung mit deiner Apple-ID. Bei „Mit Google anmelden“ widerruft die App die Verbindung zu deinem Google-Konto. Bei „Reihum“ übernimmt die nächste Person deine offenen Termine. Familien, in denen du allein bist, werden mit allen Aufgaben gelöscht. In Familien mit weiteren Mitgliedern bleiben von dir angelegte Aufgaben und Bilder für die Familie erhalten, aber ohne Bezug zu deiner Person; war niemand sonst Admin, wird das am längsten beteiligte Mitglied Admin.

## 7. Widerspruchsrecht

**Soweit wir Daten auf Grundlage berechtigter Interessen verarbeiten (Art. 6 Abs. 1 lit. f DSGVO – Server-Protokolle und Kontaktanfragen), kannst du aus Gründen, die sich aus deiner besonderen Situation ergeben, jederzeit widersprechen (Art. 21 DSGVO).** Schreib dazu an [info@familiar-app.de](mailto:info@familiar-app.de). Wir verarbeiten die Daten dann nicht mehr, es sei denn, es gibt zwingende schutzwürdige Gründe, die deine Interessen überwiegen, oder die Verarbeitung dient der Geltendmachung, Ausübung oder Verteidigung von Rechtsansprüchen.

## 8. Deine Rechte

Du hast das Recht auf Auskunft (Art. 15), Berichtigung (Art. 16), Löschung (Art. 17), Einschränkung (Art. 18), Datenübertragbarkeit (Art. 20) und Widerspruch (Art. 21 DSGVO) sowie auf Widerruf erteilter Einwilligungen mit Wirkung für die Zukunft (z. B. Outlook trennen, Mitteilungen in iOS abschalten). Schreib dazu an [info@familiar-app.de](mailto:info@familiar-app.de).

Du kannst dich bei einer Datenschutz-Aufsichtsbehörde beschweren, z. B. bei der für uns zuständigen: Die Landesbeauftragte für den Datenschutz Niedersachsen, Prinzenstraße 5, 30159 Hannover, poststelle@lfd.niedersachsen.de.

## 9. Sicherheit

Verbindungen sind verschlüsselt (TLS). Zugriffsrechte werden in der Datenbank für jede Abfrage geprüft (Row Level Security). Bilder liegen in nicht öffentlichen Speichern und werden nur über kurzlebige, signierte Links angezeigt. Die nächtliche Datensicherung wird verschlüsselt (AES-256), bevor sie Supabase verlässt; den Schlüssel zum Öffnen hat nur der Verantwortliche.

## 10. Kinder

Familiar richtet sich an Personen ab 16 Jahren. Jüngere Kinder dürfen Familiar nur mit Einwilligung ihrer Eltern nutzen (Art. 8 DSGVO).

## 11. Änderungen

Wir passen diese Erklärung an, wenn sich die App ändert. Es gilt die jeweils hier veröffentlichte Fassung.
