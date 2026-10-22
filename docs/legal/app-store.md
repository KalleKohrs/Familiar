# App-Store-Eintrag – Familiar (Entwurf)

> **Entwurf, Stand 2026-10-21.** Längen laut App Store Connect: Name ≤ 30, Untertitel ≤ 30, Werbetext ≤ 170, Beschreibung ≤ 4000, Schlüsselwörter ≤ 100 Zeichen. Alle Texte beschreiben nur, was die App heute kann.

## Basis

| Feld | Vorschlag |
|---|---|
| **Name** | Familiar – Familienplaner |
| **Untertitel** | Aufgaben teilen, ruhig planen |
| **Kategorie** | Produktivität (zweite: Lifestyle) |
| **Altersfreigabe** | 4+ (keine Inhalte aus den Fragebogen-Kategorien; Nutzer erstellen Inhalte nur innerhalb ihrer Familie) |
| **Preis** | [kostenlos?] |
| **Support-URL** | https://familiar-app.de/support [Seite anlegen] |
| **Datenschutz-URL** | https://familiar-app.de/datenschutz |

## Werbetext (170)

Wer macht was – und bis wann? Familiar bringt die Aufgaben deiner Familie an einen ruhigen Ort, erinnert rechtzeitig und lässt dich direkt vom Sperrbildschirm abhaken.

## Beschreibung

Familiar ist der Planer für alles, was in einer Familie zu tun ist – vom Müll rausbringen bis zum Arzttermin.

AUFGABEN, DIE ANKOMMEN
• Aufgaben anlegen, Personen zuweisen, Fotos anhängen
• Erledigungsart wählen: eine Person für alle oder jede Person einzeln
• Wiederholungen täglich, wöchentlich oder monatlich
• Rückgängig und Verlauf: Erledigtes und Gelöschtes 30 Tage wiederherstellen

ZUR RICHTIGEN ZEIT
• Mitteilung, wenn dir etwas zugewiesen wird und wenn es losgeht
• Live-Anzeige auf dem Sperrbildschirm und in der Dynamic Island – mit Abhaken ohne die App zu öffnen
• Erinnerungen, solange etwas offen ist

MEHRERE FAMILIEN, EINE LISTE
• Familie, WG, Großeltern: Familiar zeigt alle Aufgaben in einer Liste, jede Familie in ihrer Farbe
• Einladen per Code
• Admins legen fest, was Mitglieder dürfen

DEIN KALENDER
• Monatsansicht mit allen Aufgaben und geplanten Wiederholungen
• Optional: eigene Outlook-Termine nur lesend einblenden – sichtbar nur für dich

EINFACH ANMELDEN
• Mit E-Mail-Code, Apple oder Google – kein Passwort

PRIVAT
Keine Werbung, kein Tracking. Deine Daten liegen auf Servern in der EU und werden nur für Familiar genutzt.

## Schlüsselwörter (100)

familie,aufgaben,todo,haushalt,planer,erinnerung,kalender,putzplan,wg,eltern,kinder,teilen,liste

## Neuigkeiten (Version 1.0)

Die erste Version von Familiar.

## App-Datenschutz („Nutrition Label“)

Abgeleitet aus `ios/Familiar/Resources/PrivacyInfo.xcprivacy`. Alle Daten: **mit der Identität verknüpft**, **nicht zum Tracking**, Zweck **App-Funktionalität**.

| Kategorie (App Store Connect) | Datentyp | Herkunft in Familiar |
|---|---|---|
| Kontaktinformationen | E-Mail-Adresse | Anmeldung |
| Kontaktinformationen | Name | Anzeigename |
| Nutzerinhalte | Fotos oder Videos | Profilbild, Aufgabenbilder |
| Nutzerinhalte | Andere Nutzerinhalte | Aufgaben, Familien, Outlook-Termine |
| Kennungen | Nutzer-ID | Konto-ID |
| Kennungen | Geräte-ID | APNs-Token für Mitteilungen |

Nicht erhoben: Standort, Kontakte, Gesundheit, Finanzen, Browserverlauf, Suchverlauf, Nutzungs- und Diagnosedaten (keine Analyse-Tools).

## Screenshots (6,9″ Pflicht)

Fertig in `docs/app-store/screenshots/` (1320 × 2868, iPhone 18 Pro Max, dunkles Design, Statusleiste 9:41), je mit Vorschlag für die Überschrift:
1. `1-aufgaben.png` – Startseite: „Alles, was ansteht. Eine Liste.“
2. `2-detail.png` – Aufgabe mit „Jede Person einzeln“: „Jeder hakt seinen Teil ab.“
3. `3-zuweisen.png` – Neue Aufgabe mit Zuweisung: „Wer macht's? Kurz zugewiesen.“
4. `4-kalender.png` – Kalender: „Der Monat im Blick.“
5. `5-familien.png` – Familie mit Rollen und Rechten: „Für jede Familie die passenden Regeln.“
6. `6-verlauf.png` – Verlauf mit gelöschter Aufgabe: „Aus Versehen gelöscht? Zurückholen.“

Erstellt mit `-FamiliarInMemoryBackend -FamiliarInMemoryScenario showcase` (Vorführdaten „Familie Berger“, „Oma & Opa“). Die Live Activity auf dem Sperrbildschirm lässt sich im Simulator nicht aufnehmen; ein Bild davon kann nach dem Apple-Developer-Programm vom echten iPhone ergänzt werden (Screenshot dort ist ebenfalls 1320 × 2868 auf einem 6,9″-Gerät, sonst in App Store Connect als zusätzliche Größe hochladen).

## Prüfhinweise für Apple (App Review)

- Anmeldung: Prüf-Adresse (`REVIEW_EMAIL`) eingeben, „Code senden“, dann statt des E-Mail-Codes den 10-stelligen Prüf-Code (`REVIEW_CODE`) eingeben. Das Prüf-Konto vorher mit einer Beispiel-Familie und Aufgaben füllen.
- Konto löschen: Profil › Konto löschen (bei „Mit Apple anmelden“ inklusive Widerruf bei Apple).
- „Mit Apple anmelden“ wird angeboten, weil auch „Mit Google anmelden“ angeboten wird (Richtlinie 4.8).
- Outlook ist optional und nur lesend.
