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

Vorschlag Reihenfolge, je mit kurzer Überschrift:
1. Startseite mit Aufgaben – „Alles, was ansteht. Eine Liste.“
2. Live Activity auf dem Sperrbildschirm – „Abhaken, ohne zu suchen.“
3. Aufgabe anlegen mit Zuweisung – „Wer macht's? Kurz zugewiesen.“
4. Kalender – „Der Monat im Blick.“
5. Familien und Rechte – „Für jede Familie die passenden Regeln.“
6. Verlauf – „Aus Versehen gelöscht? Zurückholen.“

Ich erstelle sie aus dem Simulator, sobald der Design-Durchgang abgeschlossen ist.

## Prüfhinweise für Apple (App Review)

- Anmeldung per E-Mail-Code: Für das Review ein Demo-Konto bereitstellen ([Vorgehen klären, z. B. eigenes Review-Postfach]).
- Konto löschen: Profil › Konto löschen.
- Outlook ist optional und nur lesend.
