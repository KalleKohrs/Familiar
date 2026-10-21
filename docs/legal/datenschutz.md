# Datenschutzerklärung – Familiar (Entwurf)

> **Entwurf, Stand 2026-10-21.** Von mir aus dem tatsächlichen Datenfluss der App abgeleitet (Datenbank-Schema, Edge Functions, Privacy Manifest). Ich bin kein Anwalt: Bitte vor Veröffentlichung prüfen lassen (z. B. Anwalt oder seriöser Generator wie eRecht24) und die Platzhalter `[…]` ergänzen. Veröffentlichung unter `https://familiar-app.de/datenschutz`.

## 1. Verantwortlicher

[Vorname Nachname]
[Straße Hausnummer]
[PLZ Ort]
E-Mail: [datenschutz@familiar-app.de]

## 2. Grundsätze

Familiar ist ein Familienplaner. Wir verarbeiten nur die Daten, die für die Funktionen der App nötig sind. Es gibt **keine Werbung, kein Tracking, keine Analyse-Tools** und keinen Verkauf von Daten.

## 3. Welche Daten wir verarbeiten und warum

| Daten | Zweck | Rechtsgrundlage |
|---|---|---|
| **E-Mail-Adresse** | Anmeldung per Einmal-Code; Zuordnung deines Kontos | Art. 6 Abs. 1 lit. b DSGVO (Vertrag) |
| **Anzeigename, Profilbild** (freiwillig) | Damit deine Familie sieht, wer Aufgaben übernimmt | Art. 6 Abs. 1 lit. b DSGVO |
| **Familien** (Name, Farbe, Mitglieder, Rollen, Einladungscodes) | Gemeinsame Planung | Art. 6 Abs. 1 lit. b DSGVO |
| **Aufgaben** (Titel, Beschreibung, Datum/Uhrzeit, Wiederholung, Zuweisungen, Erledigt-Status, Bilder) | Kernfunktion | Art. 6 Abs. 1 lit. b DSGVO |
| **Geräte-Kennung für Mitteilungen** (APNs-Token, App-Version, Zeitzone) | Mitteilungen und Live-Anzeigen auf dem Sperrbildschirm | Art. 6 Abs. 1 lit. b DSGVO; die Mitteilungen selbst nur mit deiner Einwilligung in iOS |
| **Outlook-Termine** (nur wenn du Outlook verbindest: Titel, Zeit, Ort, Organisator, Absage-Status der gewählten Kalender) | Anzeige im Familiar-Kalender – **nur für dich**, nicht für deine Familie | Art. 6 Abs. 1 lit. a DSGVO (Einwilligung durch Verbinden) |
| **Server-Protokolle** (IP-Adresse, Zeitpunkt, Anfrage) | Betrieb und Sicherheit | Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an einem sicheren Betrieb) |

**Wer sieht was:** Aufgaben, Bilder und Status sehen die Mitglieder der jeweiligen Familie; ist eine Familie auf „nur Zugewiesene“ gestellt, sehen nur zugewiesene Personen und die Erstellerin bzw. der Ersteller die Aufgabe. Deine Outlook-Termine sieht niemand außer dir.

**Outlook:** Familiar erhält von Microsoft nur das Recht, deine Kalender zu **lesen** (`Calendars.ReadBasic` – ohne Termin-Text und Anhänge). Familiar schreibt nie in deinen Kalender. Das Zugriffs-Token liegt verschlüsselt auf dem Server. Du kannst die Verbindung jederzeit in der App trennen; dann werden Token und gespeicherte Termine gelöscht.

## 4. Empfänger und Auftragsverarbeiter

| Dienst | Zweck | Sitz / Übermittlung |
|---|---|---|
| **Supabase Inc.** | Datenbank, Anmeldung, Dateispeicher, Server-Funktionen | Server in der EU ([Region, z. B. Frankfurt]); Unternehmen in den USA – Auftragsverarbeitungsvertrag und EU-Standardvertragsklauseln |
| **Resend, Inc.** | Versand der Anmelde-Codes per E-Mail | USA – Auftragsverarbeitungsvertrag und EU-Standardvertragsklauseln [bzw. Angemessenheitsbeschluss/Data Privacy Framework, falls zertifiziert] |
| **Apple Inc.** (Apple Push Notification service) | Zustellung von Mitteilungen und Live-Anzeigen; erhält Geräte-Token und Mitteilungsinhalt (z. B. Aufgabentitel) | USA bzw. Apple Distribution International (Irland) |
| **Microsoft** | Nur bei verbundenem Outlook: Abruf deiner Termine | nach den Bedingungen deines Microsoft-Kontos |
| [**Apple / Google** – nur falls „Mit Apple/Google anmelden“ genutzt wird] | Anmeldung | [ergänzen, wenn freigeschaltet] |

## 5. Speicherdauer

- **Konto, Familien, offene Aufgaben:** bis du sie löschst bzw. dein Konto löschst.
- **Erledigte und gelöschte Aufgaben:** 30 Tage im Verlauf (zum Wiederherstellen), danach automatisch endgültig gelöscht – einschließlich Bildern.
- **Mitteilungs-Aufträge, beendete Live-Anzeigen, abgemeldete Geräte:** 30 Tage, danach automatisch gelöscht.
- **Outlook-Termine:** nur ein Fenster von 7 Tagen zurück bis 120 Tage voraus; ältere fallen beim Abgleich weg; beim Trennen sofort gelöscht.
- **Server-Protokolle:** [laut Supabase-Tarif, z. B. 7 Tage].

## 6. Konto löschen

In der App unter **Profil › Konto löschen**. Gelöscht werden dein Konto, Profil und Profilbild, deine Mitgliedschaften, Zuweisungen, Geräte und Outlook-Verbindung. Familien, in denen du allein bist, werden mit allen Aufgaben gelöscht. In Familien mit weiteren Mitgliedern bleiben von dir angelegte Aufgaben und Bilder für die Familie erhalten, aber ohne Bezug zu deiner Person; war niemand sonst Admin, wird das am längsten beteiligte Mitglied Admin.

## 7. Deine Rechte

Du hast das Recht auf Auskunft (Art. 15), Berichtigung (Art. 16), Löschung (Art. 17), Einschränkung (Art. 18), Datenübertragbarkeit (Art. 20) und Widerspruch (Art. 21 DSGVO) sowie auf Widerruf erteilter Einwilligungen mit Wirkung für die Zukunft (z. B. Outlook trennen, Mitteilungen in iOS abschalten). Schreib dazu an [datenschutz@familiar-app.de].

Du kannst dich bei einer Datenschutz-Aufsichtsbehörde beschweren, z. B. in deinem Bundesland: [zuständige Behörde des Verantwortlichen ergänzen].

## 8. Sicherheit

Verbindungen sind verschlüsselt (TLS). Zugriffsrechte werden in der Datenbank für jede Abfrage geprüft (Row Level Security). Bilder liegen in nicht öffentlichen Speichern und werden nur über kurzlebige, signierte Links angezeigt.

## 9. Kinder

[Klären: Mindestalter für ein eigenes Konto, z. B. 16 Jahre (Art. 8 DSGVO) bzw. Nutzung jüngerer Kinder nur mit Einwilligung der Eltern.]

## 10. Änderungen

Wir passen diese Erklärung an, wenn sich die App ändert. Es gilt die jeweils hier veröffentlichte Fassung.
