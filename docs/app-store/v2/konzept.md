# App-Store-Auftritt v2 – Konzept (Stand 2026-11-08)

**Status (2026-11-08, Nacht):** Endfassung fertig, noch **nicht hochgeladen** – siehe Abschnitt „Endfassung“ direkt hier unten. Die Abschnitte 1–7 sind das ursprüngliche Konzept; die Bilder unter `entwuerfe/` sind die Skizzen-Runden (A–F) dorthin.

## Endfassung

Entscheidungen des Inhabers: Texte und zweifarbige Schlagzeilen aus Richtung A, Orange-/Papier-Design aus D, jedes Bild mit eigenem Layout (Serie F), **keine** komplett dunklen Seiten, **keine** Pastellfarben (Gelb, Grün, Rosa) – nur Orange, Papier und Aprikose.

**Bilder:** `docs/app-store/v2/final/` – 7 × PNG, 1320 × 2868, ohne Alpha-Kanal (geprüft mit `sips`), Reihenfolge = Dateiname. Überblick: `final/ueberblick.png`. Neu bauen: `python3 docs/app-store/v2/quelle/store.py <render-html>` (Werkzeug: `docs/app-store/v2/tools/render-html.swift`).

| # | Datei | Schlagzeile | Unterzeile | Layout · Hintergrund | Inhalt (echte Aufnahme) |
|---|---|---|---|---|---|
| 1 | `01-wer-macht-was.png` | Wer macht was / *und bis wann?* | Alle Aufgaben der Familie an einem Ort. | Handy, eine Karte hebt sich vergrößert heraus · Orange | Aufgabenliste, hell |
| 2 | `02-jeder-sein-teil.png` | Jeder hakt / *seinen Teil* ab. | „Erinnern“ für alle, die noch offen sind. (unten) | Drei exakte Bauteile untereinander · Papier | Details „Jede Person einzeln“, dunkel |
| 3 | `03-reihum.png` | Mal Paul, / *mal Mia.* | Reihum verteilt Aufgaben von selbst. | Bildschirm-Ausschnitt ab „Zugewiesen“, läuft unten aus · Aprikose | Editor mit Reihum, hell |
| 4 | `04-kalender.png` | Der Monat / im Blick. | Aufgaben und Wiederholungen im Kalender. | Poster, Schlagzeile unten · Orange | Kalender, hell |
| 5 | `05-familien.png` | Familie, WG, / Oma & Opa. | Mehrere Familien in einer App – jede mit eigenen Regeln. | Familien-Karten + Rechte-Karte, Schlagzeile darunter · Papier | Familien + Rechte, hell |
| 6 | `06-verlauf.png` | Gelöscht? / Zurückholen. | Erledigtes und Gelöschtes bleibt 30 Tage im Verlauf. (unten) | Kartenstapel, gelöschte Karte vorn · Orange | Verlauf, dunkel |
| 7 | `07-ohne-werbung.png` | Ohne Werbung. / Ohne Tracking. | Kostenlos. Daten in der EU. | Abschluss mit App-Icon · Papier | Aufgabenliste, hell |

Zweifarbige Schlagzeile nur bei den Bildern 1–3 (der „Haken“ im Store), danach einfarbig.

**Feinschliff (Runde 2):** Jedes App-Bauteil ist exakt an seiner eigenen Kante ausgeschnitten (Kanten gemessen mit `tools/probe.swift`, 2 px nach innen, Rundung des Bauteils: Karten 72 px, Knöpfe halbe Höhe, Display 165 px) – kein App-Hintergrund mehr um Karten, also kein „Rahmen im Rahmen“. Einheitliches Raster: Rand 48, Spalte 564, Schlagzeile bei 104, einheitliche Schatten und eine feine Lichtkante je Bauteil. Für Bild 3 und 5 neu aufgenommen, damit keine Karte angeschnitten ist (`hell-reihum-editor.png`, `hell-regeln-unten.png`). Kontrolle in 1:1-Ausschnitten an allen Kanten.

**Rohmaterial:** `docs/app-store/v2/rohmaterial/` – aufgenommen am 2026-11-08 mit dem aktuellen Stand (Debug-Build), iPhone 18 Pro Max (Simulator, iOS 27), `-FamiliarInMemoryBackend -FamiliarInMemoryScenario showcase -appearance light|dark`, Statusleiste 9:41, volle Balken, Akku voll ohne Ladesymbol (`simctl status_bar … --batteryState discharging --batteryLevel 100`). Die Reihum-Aufgabe „Altpapier“ (Paul, Mia; dienstags) wurde dafür in der laufenden App über den normalen Editor angelegt – kein App-Code geändert.

**Bewusst weggelassen:**
- **Widget:** Das Widget „Heute“ zeigt mit den Vorführdaten nur eine Aufgabe (nur Lenas eigene) und wirkt leer. Für ein gutes Widget-Bild müssten die Vorführdaten erweitert werden (App-Code, eigener Auftrag).
- **Live Activity / Sperrbildschirm:** im Simulator nicht zuverlässig. Wenn der Inhaber ein Sperrbildschirm-Foto vom eigenen iPhone liefert, wird es Bild 2 („Abhaken direkt vom Sperrbildschirm“); die übrigen rücken nach.

**Texte für App Store Connect** (Vorschläge, Längen geprüft):
- Untertitel (30): `Aufgaben teilen, reihum planen`
- Werbetext (149 von 170): „Wer macht was – und bis wann? Aufgaben zuweisen, reihum verteilen, rechtzeitig erinnern und vom Sperrbildschirm abhaken. Ohne Werbung, ohne Tracking.“
- Schlüsselwörter (94 von 100): `familie,todo,haushalt,putzplan,wg,erinnerung,kalender,eltern,kinder,reihum,widget,siri,outlook`
- Beschreibung: unverändert aus `docs/legal/app-store.md`, nur den ersten Satz durch „Wer macht was – und bis wann? Familiar bringt die Aufgaben deiner Familie an einen ruhigen Ort.“ ersetzen.

**Hochladen (Inhaber):**
1. App Store Connect › Familiar › neue Version anlegen (z. B. 1.0.1) oder die nächste geplante Version öffnen.
2. Unter „iPhone-Bildschirmfotos“ (6,9″-Anzeige) die alten sechs Bilder löschen und die sieben Dateien aus `docs/app-store/v2/final/` in der Reihenfolge 01–07 hineinziehen.
3. Untertitel, Werbetext, Schlüsselwörter und den ersten Satz der Beschreibung übernehmen (siehe oben).
4. Mit der Version zur Prüfung einreichen. Der Werbetext lässt sich auch ohne neue Version jederzeit ändern.

## 1. Analyse

### Was am heutigen Eintrag billig wirkt

Quelle: [echter Eintrag](https://apps.apple.com/de/app/familiar-familienplaner/id6828540894), die sechs Bilder in `docs/app-store/screenshots/` und `docs/legal/app-store.md`.

1. **Keine Schlagzeilen.** Die sechs Bilder sind rohe Simulator-Aufnahmen. Wer durch den Store wischt, sieht Bildschirme, aber nie einen Nutzen. Die Überschriften aus `app-store.md` („Alles, was ansteht. Eine Liste.“ usw.) stehen nur im Dokument und sind nie auf den Bildern gelandet.
2. **Alles sieht gleich aus.** Sechs dunkle Hochkant-Bilder in gleicher Farbe, kein Rhythmus, kein Blickfang. Im Store sieht man nur die ersten zwei bis drei Bilder, und die wirken wie ein einziger dunkler Block.
3. **Schwächste Bilder an starken Stellen.** Bild 3 („Neue Aufgabe“) ist ein trockenes Formular (Schalter, Auswahlfelder), das zum Ausprobieren nicht einlädt. Bild 2 ist zur Hälfte leere Fläche. Das ist der Eindruck „Entwurf“.
4. **Die besten Argumente fehlen.** Sperrbildschirm-Abhaken, Reihum, Widgets, Siri, „ohne Werbung/Tracking“ kommen in keinem Bild vor. Gezeigt werden Formulare und Einstellungen (Rechte-Schalter).
5. **Zu viel Kleintext.** Auf den Rohbildern ist alles winzig (Uhrzeit, Chips, „Erstellt von Lena“). Auf einer Store-Karte, die nur etwa 2 cm breit ist, ist nichts lesbar.
6. **Statusleiste und Ränder.** Die Statusleiste sitzt nackt am oberen Rand, die Bilder laufen unten in die Tab-Leiste und enden mit einer halb abgeschnittenen Karte. Nichts ist bewusst angeschnitten, es sieht zufällig aus.
7. **Texte.** Name und Untertitel im Store (Name „Familiar Familienplaner“; unter dem Namen steht nur „Produktivität“, ein Untertitel scheint nicht gesetzt zu sein – bitte in App Store Connect prüfen) verschenken die wertvollste Zeile. Die Beschreibung ist gut und ehrlich, beginnt aber mit einem Satz ohne Reiz („Familiar ist der Planer für alles …“). Zu sehen sind nur die ersten drei Zeilen. Der Werbetext (170 Zeichen) ist zu lang für eine schnelle Entscheidung.
8. **Keine Bewertungen** (noch keine Zahl). Das lässt sich nicht beheben, deshalb müssen Bilder und Text mehr überzeugen.

### Vergleich: vier Apps im deutschen App Store

Daten über Apples öffentliche Such-Schnittstelle (iTunes Search/Lookup, Land DE, abgerufen 2026-11-08) und die Vorschaubilder der Einträge. Die Bilder habe ich nur zum Ansehen heruntergeladen (je ca. 30 KB, nur im Scratch-Ordner, nichts davon wird verwendet).

| App | Bewertung (DE) | Bildaufbau | Lernen / bewusst anders |
|---|---|---|---|
| **[Cozi](https://apps.apple.com/de/app/id407108860)** | 4,6 (1.370) | 8 Bilder, blauer Verlauf, **englische Schlagzeilen im deutschen Store** („Everyone’s plans. One calendar.“), schräges Gerät, Foto einer Familie | Lernen: eine Idee pro Bild, ein Satz. Anders: nicht auf Englisch, keine Stockfotos, kein Schrägbild. |
| **[Todoist](https://apps.apple.com/de/app/id572688855)** | 4,7 (27.380) | 7 Bilder, helle Pastelltöne, deutsche Schlagzeilen („Erfasse Aufgaben in Gedankenschnelle“), Auszeichnungs-Lorbeer | Lernen: kurze, klare Nutzen-Sätze, ruhiger Hintergrund, sparsame Schrift. Anders: keine Auszeichnungen anzeigen, die wir nicht haben. |
| **[FamilyWall](https://apps.apple.com/de/app/id496889629)** | 4,7 (25.341) | 10 Bilder, kräftiges Blau, Illustrationen, Gerät beschnitten, förmliches „Sie“ („Vereinfachen Sie Ihr Familienleben“) | Lernen: Mut zu großer Schrift und Anschnitt. Anders: du statt Sie, keine Cartoons, kein Blau-Einheitsbrei. |
| **[TimeTree](https://apps.apple.com/de/app/id952578473)** | 4,7 (100.421) | 10 Bilder, Grün, „Über 75 Mio. Nutzer“ als Beleg, Gerät mit Rahmen und Foto-Blasen | Lernen: ein Vertrauenssignal pro Bild. Anders: unser Beleg ist nicht Zahl, sondern „keine Werbung, kein Tracking, Daten in der EU“. |

(Zusätzlich gesehen: Structured, „Dein Plan für jeden Tag“, rosa Pastell, Apple-Design-Award-Lorbeer.)

**Gemeinsamer Nenner der Konkurrenz:** helle, bunte, laute Karten mit Illustrationen, Fotos und Auszeichnungen. **Chance für Familiar:** ruhiger, erwachsener, ohne Stockfotos. Dazu die Fähigkeiten, die kaum jemand zeigt (Reihum, Sperrbildschirm, „ohne Tracking“).

## 2. Positionierung

**Ein Satz:** Familiar ist der ruhige Planer für Familien, WGs und Großeltern, in dem klar ist, wer was bis wann macht – mit Erinnerungen, die ankommen, Abhaken vom Sperrbildschirm und ohne Werbung oder Tracking.

**Die drei wichtigsten Verkaufsargumente** (in dieser Reihenfolge, daran hängt die Bilderreihe):

1. **Klar, wer was macht** – zuweisen, Jede-Person-einzeln, Reihum („diese Woche Paul, nächste Mia“).
2. **Erinnert und lässt sich abhaken, ohne die App zu öffnen** – Mitteilungen, Live-Anzeige, Widgets, Siri.
3. **Ruhig und privat** – keine Werbung, kein Tracking, Daten in der EU, 30 Tage zurückholen, Familien-Regeln.

## 3. Vier Stilrichtungen

Alle drei sind **ohne Gerätrahmen**: Apples Marketing-Richtlinien verlangen bei Gerätedarstellungen die unveränderten Apple-Vorlagen; selbstgezeichnete Rahmen sind eine Grauzone. Wir zeigen nur den Bildschirm mit abgerundeten Ecken. Das ist sicher und wirkt moderner.

**Entwürfe** (660 × 1434 für schnelle Ansicht, in `entwuerfe/`):

- Überblick: `docs/app-store/v2/entwuerfe/ueberblick.png`
- A: `A1-nacht.png`, `A2-nacht.png`
- B: `B1-papier.png`, `B2-papier.png`
- C: `C1-mutig.png`, `C2-mutig.png`
- D: `D1-orange-weiss.png`, `D2-orange-weiss.png`
- Quelle (Neubau jederzeit): `entwuerfe/quelle/bauen.py`, Render-Werkzeug `tools/render-html.swift`

### A · „Nacht“ (dunkel, edel)

- **Farben:** Aubergine-Graphit `#1E1519` mit warmem Schein oben rechts und Pflaume unten links, Schrift warmes Weiß `#F6EEE6`, **ein** Schlüsselwort je Schlagzeile in Orange `#FF8C42`.
- **Schrift:** Bricolage Grotesque, kräftig, eng gesetzt (die Schrift der App und der Website).
- **Gerät:** nur Bildschirm, Rundung, feine Lichtkante, tiefer weicher Schatten mit leichtem Orange-Schein; unten bewusst angeschnitten.
- **Wirkung:** hochwertig, ruhig, erwachsen; passt zu App, Icon (dunkle Variante) und Marke. Hebt sich von allen hellen, bunten Mitbewerbern ab.
- **Risiko:** Dunkle Bilder wirken im hellen Store-Modus als dunkle Blöcke, das ist gewollt (sie stechen heraus), braucht aber starke Schlagzeilen.

### B · „Papier“ (hell, warm)

- **Farben:** warmes Papier `#F5ECE1` mit Orange- und Rosé-Schein, Schrift Aubergine `#2B1F25`, Schlüsselwort mit orangem Marker-Unterstrich.
- **Schrift:** wie A, etwas leichter (semibold).
- **Gerät:** nur Bildschirm, warmer Schatten; **Inhalt: Hellmodus-Aufnahmen** (liegen unter `rohmaterial/`, bisher nur zwei).
- **Wirkung:** freundlich, offen, familiennah; nahe an Todoist und Structured, daher weniger eigenständig im Vergleich zu A.
- **Risiko:** Kontrast Schlagzeile/Hintergrund geringer, Wirkung „nett“ statt „besonders“.

### C · „Mutig“ (grafisch, orange)

- **Farben:** durchgehend Orange-Verlauf (`#FF9A55` → `#E8631A`), Schrift Aubergine, Schlüsselwort Cremeweiß.
- **Schrift:** Bricolage extrafett, sehr groß; ausgeschnittene echte Oberflächenteile (z. B. „Für alle erledigt“) als schwebende „Aufkleber“.
- **Gerät:** Bildschirm angeschnitten, dazu Ausschnitte der echten Oberfläche.
- **Wirkung:** laut, auffällig, wiedererkennbar im Store-Ergebnis, erinnert an das Icon.
- **Risiko:** Passt nicht zur ruhigen Marke („ruhig, warm“), wirkt schnell werblich und ermüdet über 8 Bilder. Die Ausschnitte müssen ehrlich bleiben (nur echte, unveränderte Teile der Oberfläche).

### D · „Orange & Weiß“ (Idee des Inhabers)

- **Farben:** durchgehend Marken-Orange (`#F9954A` → `#E8631A`) mit hellem Lichtschein oben links; Schlagzeile und Unterzeile **weiß**; das Gerät zeigt die **helle** App (cremeweiß).
- **Schrift:** Bricolage, wie bei den anderen.
- **Gerät:** nur Bildschirm, unten angeschnitten, weicher Schatten.
- **Wirkung:** frisch, freundlich, sofort als Familiar erkennbar (gleiche Farbe wie das Icon); heller Bildschirm hebt sich vom Orange klar ab, ruhiger als C, weil kein Schwarz und keine Riesenschrift.
- **Risiko:** Weiße Schrift auf Orange hat nur mittleren Kontrast (ca. 3 : 1 bis 3,6 : 1). Das geht nur mit großer, fetter Schlagzeile; die Unterzeile bleibt ein Hilfstext (in der Endfassung nur wenn nötig oder mit dunklerem Orange). Alle acht Bilder brauchen Hellmodus-Aufnahmen (neu aufzunehmen).

### E · Mischung (Wunsch des Inhabers, Stand 2026-11-08)

Rückmeldung zu den Skizzen: **Texte und zweifarbige Schlagzeilen aus A, Hintergrund-Design aus D (Orange mit aufsteigender weißer Fläche), aber mit deutlich mehr Abwechslung zwischen den Bildern.** Umsetzung als Serie von 6 Bildern, `entwuerfe/E1-serie.png` bis `E6-serie.png`, Überblick `entwuerfe/serie-E-ueberblick.png` (Quelle: `quelle/serie.py`).

- **Rhythmus der Hintergründe (ohne komplett dunkle Seiten, auf Wunsch des Inhabers):** 1 Orange + weiße Fläche · 2 Warmes Papier · 3 Voll-Orange · 4 Warmes Papier · 5 Orange + weiße Fläche · 6 Warmes Papier. Wer wischt, sieht Wechsel statt sechsmal dasselbe.
- **Zweifarbige Schlagzeile nur bei den ersten drei Bildern** (der „Haken“ im Store: 1 weiß + dunkles Schlüsselwort, 2 weiß + orange, 3 dunkel + orange); ab Bild 4 einfarbig und ruhiger. So bleibt die Betonung etwas Besonderes.
- **Geräte:** abwechselnd helle und dunkle App-Aufnahmen; die dunkle App steht nur auf hellem Grund (kein schwarzer Hintergrund). Die Skizze nutzt, was vorhanden ist (die Reihenfolge entspricht deshalb noch nicht dem Storyboard in Abschnitt 4; die Sperrbildschirm-, Reihum- und Widget-Bilder fehlen noch, weil es dafür noch keine Aufnahmen gibt).
- **Offener Punkt:** Auf der weißen Fläche verschwimmt das helle Gerät mit dem Hintergrund; in der Endfassung bekommt die Fläche einen Hauch Abstand/Schatten oder wird nur bei dunklen Geräten gezeigt.

### F · Vielfalt (aktueller Stand, 2026-11-08)

Rückmeldung zu E: „Jede Seite sieht gleich aus“, die komplett dunklen Seiten sind zu viel. Quellen zu Abwechslung in Store-Bildern empfehlen eine Idee pro Bild, wechselnde Geräte-Positionen (mittig, links, rechts, zwei Geräte, **auch ohne Gerät**) und Kontrastbilder innerhalb einer Farbfamilie ([Butterkit-Cheatsheet](https://www.butterkit.app/guides/app-store-design-cheatsheet/), [SplitMetrics](https://splitmetrics.com/blog/app-store-screenshots/), [AppTweak](https://www.apptweak.com/en/aso-blog/how-to-optimize-your-app-screenshots)). Apple verlangt, dass die App in Benutzung zu sehen ist ([Richtlinie 2.3.3](https://developer.apple.com/help/app-review/guideline-reference/2-3-3-screenshots)) – deshalb keine reinen Textbilder, sondern **unveränderte Ausschnitte echter Aufnahmen**.

Serie `entwuerfe/F1-vielfalt.png` … `F7-vielfalt.png`, Überblick `entwuerfe/serie-F-ueberblick.png`, Quelle `quelle/vielfalt.py`. Jedes Bild hat ein eigenes Layout; Hintergründe aus der **Familienpalette der App** (Orange, Papier, Sonne, Salbei, Rose) – passend zu „jede Familie in ihrer Farbe“:

| # | Layout | Hintergrund | Inhalt |
|---|---|---|---|
| F1 | Handy rechts angeschnitten + **vergrößerte Karte**, die aus dem Bild ragt | Orange | Aufgabenliste hell |
| F2 | **Zoom ohne Handy**: Bildschirm randlos, größer als sonst | Papier | Details „Jede Person einzeln“ |
| F3 | **Poster**: Kalender oben, Schlagzeile unten | Sonne | Kalender hell |
| F4 | **Kartenstapel**, versetzt, ohne Handy | Salbei | Verlauf-Karten |
| F5 | Handy **oben** angeschnitten, Schlagzeile unten | Rose | Familie mit Regeln |
| F6 | **Zwei Ausschnitte**, Schlagzeile in der Mitte | Orange | Neue Aufgabe, Zuweisung |
| F7 | **Abschluss**: App-Icon, Versprechen, Listen-Ausschnitt | Papier | Aufgabenliste hell |

Zweifarbige Schlagzeile (Schlüsselwort in Akzentfarbe) bleibt; auf Orange dunkel, auf hellen Gründen in der jeweils dunklen Variante der Farbe. Noch nicht enthalten (fehlende Aufnahmen): Sperrbildschirm/Live Activity, Reihum, Widgets. Ein Panorama über zwei Bilder (ein Element läuft über die Bildkante) ist als weitere Variante möglich.

## 4. Dramaturgie (Storyboard, 8 Bilder)

Die ersten drei Bilder entscheiden im Store (Suchergebnis zeigt nur diese). Reihenfolge nach Verkaufsargument. **Jedes Bild zeigt die echte App in Benutzung** (Richtlinie 2.3.3), kein Mockup-Bildschirm, keine erfundene Funktion. Ausschnitte nur aus echten Aufnahmen.

| # | Schlagzeile (max. 7 Wörter) | Funktion | Aufnahme-Szenario | Status |
|---|---|---|---|---|
| 1 | **Wer macht was – und bis wann?** | Aufgabenliste: Heute/Morgen, Personen, Familienfarben | `showcase`, Startseite, saubere Statusleiste (9:41, voller Akku, kein Ladeblitz) | Neu aufnehmen (bisher vorhanden, aber Aufbau ändern) |
| 2 | **Abhaken direkt vom Sperrbildschirm** | Live Activity / Mitteilung mit Haken | **Echtes iPhone** (siehe Abschnitt 6) | Neu, braucht echtes Gerät |
| 3 | **Jeder hakt seinen Teil ab.** | „Jede Person einzeln“, 1 von 2 erledigt, „Für alle erledigt“ | `showcase`, Detail „Zimmer aufräumen“ | Vorhanden, anders zuschneiden (leere untere Hälfte weg) |
| 4 | **Diese Woche Paul, nächste Mia.** | Reihum-Wiederholung („Reihum · nächstes Mal: Mia“) | Aufgabe „Müll rausbringen“ mit Reihum anlegen oder im showcase ergänzen | Neu, in den Vorführdaten prüfen, ob Reihum-Aufgabe vorhanden ist |
| 5 | **Der Monat im Blick.** | Kalender mit Punkten, Tagesliste (optional Outlook-Termin sichtbar, nur lesend) | `showcase`, Kalender | Vorhanden, neu aufnehmen (aktuelles Datum) |
| 6 | **Familie, WG, Oma & Opa – eine Liste.** | Mehrere Familien, Familienfarben, Filter „Alle Familien“ | `showcase`, Startseite mit geöffnetem Familienfilter | Neu |
| 7 | **Die Liste immer dabei.** | Widgets Homescreen/Sperrbildschirm, Siri-Befehl | Widget auf dem Homescreen (Apple erlaubt das ausdrücklich bei Widgets ohne Fremdinhalte) | Neu, im Simulator machbar |
| 8 | **Aus Versehen gelöscht? 30 Tage zurückholen.** | Verlauf mit „Wiederherstellen“; Unterzeile „Ohne Werbung. Ohne Tracking.“ | `showcase`, Verlauf | Vorhanden, neu aufnehmen |

Nicht mehr dabei: „Neue Aufgabe“-Formular (Bild 3 alt) und Rechte-Schalter (Bild 5 alt). Die Rechte-Seite lässt sich als Ausschnitt in Bild 6 einbauen oder weglassen. Beides sind Bildschirme für Experten, nicht für Neugierige.

Ton der Schlagzeilen: **du, kurz, konkret, mit Alltagsbeispiel** (Müll, Zimmer, Paul und Mia). Kein „revolutionär“, kein „endlich“.

## 5. Weitere Bausteine

| Baustein | Empfehlung | Aufwand | Anmerkung |
|---|---|---|---|
| **Screenshot-Reihe (8 Bilder)** | **Ja** | ca. 1 Arbeitstag Claude + 20 Min. für dich (Foto vom iPhone) | Hauptsache |
| **Untertitel** (≤ 30 Zeichen) | **Ja** | 5 Min. | Heute scheinbar nicht gesetzt. Vorschläge: „Aufgaben teilen, reihum planen“ (30), „Familienaufgaben fair teilen“ (28), „Wer macht was – und bis wann?“ (29, dann nicht auch als Bild-1-Schlagzeile). Empfehlung: **„Aufgaben teilen, reihum planen“** (nennt das Alleinstellungsmerkmal). |
| **Werbetext** (≤ 170) | **Ja** | 5 Min. | Vorschlag (149 Zeichen): „Wer macht was – und bis wann? Aufgaben zuweisen, reihum verteilen, rechtzeitig erinnern und vom Sperrbildschirm abhaken. Ohne Werbung, ohne Tracking.“ Der Werbetext lässt sich nach Apples Regeln jederzeit ändern, auch ohne neue App-Version. |
| **Beschreibung** | **Ja, nur Anfang** | 30 Min. | Inhalt bleibt, die ersten drei Zeilen (sichtbar vor „mehr“) bekommen den Nutzen („Wer macht was – und bis wann? …“) statt „Familiar ist der Planer für …“. Rest unverändert, ist ehrlich und gut gegliedert. Ob eine Änderung eine neue Version braucht, zeigt App Store Connect; sicher ohne neue Version geht nur der Werbetext. |
| **Schlüsselwörter** (≤ 100) | **Ja, kleine Änderung** | 10 Min. | Name und Untertitel werden schon durchsucht, Wörter dort nicht wiederholen. Vorschlag (94 Zeichen): `familie,todo,haushalt,putzplan,wg,erinnerung,kalender,eltern,kinder,reihum,widget,siri,outlook`. Entfernt: „aufgaben“ (im Untertitel), „planer“ (im Namen). Die Wirkung ist ohne Daten nicht messbar, dafür sind keine Analyse-Tools nötig: App Store Connect zeigt Impressionen. |
| **App-Vorschau-Film (15–30 s)** | **Später (Phase 2), optional** | ca. 1 Tag | Zeigt Abhaken, Reihum und Sperrbildschirm lebendig. Am besten vom echten iPhone (Bildschirmaufnahme), geschnitten mit iMovie (kostenlos) oder per Skript. Erst nach den Bildern, falls Zeit. Format siehe Abschnitt 6. |
| **Produktseiten-Varianten (Custom Product Pages)** | **Nein, jetzt nicht** | – | Sinnvoll erst, wenn es gezielte Werbe-Links gibt (z. B. „WG“ vs. „Familie“). Ohne Anzeigen bringt das nichts. |
| **App-Icon-Feinschliff** | **Nein** | – | Das Icon (Haus mit Haken, Orange, ruhig) ist klar und gut. Nur auf kleinster Größe (Suche, 60 px) kurz prüfen, ob der Haken noch lesbar ist. |

## 6. Machbarkeit und Grenzen

**Bildgrößen** (Quelle: [Apple, Screenshot-Spezifikationen](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), gelesen 2026-11-08):

- iPhone, 6,9″-Klasse („Dynamic Island, large“): **1320 × 2868** (auch 1290 × 2796 und 1260 × 2736). Das ist unser Rohmaterial (iPhone 18 Pro Max, auch 17 Pro Max).
- 6,1″-Klasse („Dynamic Island, medium“): 1206 × 2622 oder 1179 × 2556. Laut Apple fehlende Größen werden aus der nächstgrößeren Klasse skaliert. Das ist der heutige Zustand und funktioniert. Wir liefern **1320 × 2868** als Master. Eine zweite Größe ist nicht nötig.
- 1 bis **10** Bilder je Größe, PNG oder JPEG, **ohne Transparenz**, mit Alpha-Kanal wird abgelehnt.
- **iPad:** nicht nötig. Die App ist iPhone-only (`TARGETED_DEVICE_FAMILY = 1` in `ios/Config/Base.xcconfig`).
- Hinweis: Die Seite von Apple nennt die Zoll-Klassen nur in Dateinamen. Beim Hochladen in App Store Connect prüft das System die Größe ohnehin.

**App-Vorschau-Film** ([Apple, App-Preview-Spezifikationen](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)): 15–30 s, bis 3 Filme je Größe, H.264 (.mov/.m4v/.mp4), höchstens 30 Bilder/s, bis 500 MB, iPhone hochkant **886 × 1920**, Stereo-Tonspur (AAC) laut Seite vorgesehen. Der Film muss in der geöffneten App beginnen, Übergänge nur als Überblendung, gekürzte Abläufe mit Hinweis.

**Marketing-Richtlinien** ([Apple](https://developer.apple.com/app-store/marketing/guidelines/)):

- Geräterahmen nur Apples unveränderte Vorlagen, keine selbst gezeichneten Geräte, keine Schatten/Spiegelungen/Kippen am Gerät. **Darum: kein Rahmen.** Der Bildschirm selbst ist App-Inhalt, kein Apple-Produktbild.
- Statusleiste vollständig (Netz, WLAN, Akku). Bei den Rohbildern: Ladeblitz beim Akku vermeiden (`simctl status_bar … --batteryState discharging --batteryLevel 100`). Beim Hellmodus-Rohmaterial ist der Ladeblitz noch zu sehen und wird bei der Endfassung ersetzt.
- Fiktive Namen („Familie Berger“) sind erlaubt und gewollt. Keine echten Personendaten.
- Schreibweisen: „iPhone“, „App Store“, „Dynamic Island“. Keine Apple-Logos und keine Auszeichnungen (haben wir keine).
- Push-Mitteilung nur eine, auf dem Sperrbildschirm, und ein Tippen muss die App öffnen. Der Homescreen darf nur bei Widgets ohne Fremdinhalte zu sehen sein.

**Schriftlizenz:**

- **Bricolage Grotesque** (SIL Open Font License 1.1, Lizenztext liegt im Repo bei der Schrift): darf in Bildern, Film und Print kostenlos verwendet werden. Alle Überschriften und Nebentexte der Store-Bilder setzen wir damit.
- **SF Pro (Systemschrift):** Apples Lizenz erlaubt sie für Bildschirmdarstellungen der App. **Für eigenen Werbetext in Bildern verwenden wir sie nicht** (Lizenz nicht eindeutig für Marketing). Die App-Oberfläche in den Aufnahmen enthält sie, das ist unproblematisch (echte Bildschirmaufnahme).
- Keine Stockfotos, keine fremden Logos, keine Icons aus Fremdquellen. Erlaubte Zutaten: Aufnahmen aus der App, das eigene Icon/Zeichen, Schrift Bricolage, einfache Formen.

**Live Activity ehrlich zeigen:**
Im Simulator erscheint die Live Activity auf dem Sperrbildschirm nicht zuverlässig. Vorschlag in dieser Reihenfolge:

1. **Echtes iPhone (Empfehlung).** Du startest die Aufgabe mit „Live Activity“ (Testversion), sperrst das Gerät und machst einen normalen Screenshot (Seitentaste + Lauter). Größe passt, wenn das iPhone zur 6,9″- oder 6,1″-Klasse gehört. Wir legen das Bild, wie es ist, in die Reihe (Namen/Mitteilungen vorher prüfen). Ehrlich, einfach, 10 Minuten für dich.
2. **Ausschnitt aus der Xcode-Vorschau**, falls kein passendes iPhone da ist: Die Live-Activity-Ansicht wird aus dem echten App-Code gerendert und als **Ausschnitt** (nicht als vorgetäuschter Sperrbildschirm) neben der Schlagzeile gezeigt. Wird in der Bildunterzeile nicht als Aufnahme vom Gerät ausgegeben.
3. **Weglassen**, falls beides nicht geht: Die Reihe funktioniert auch mit 7 Bildern. Nichts erfinden.

## 7. Empfehlung

**Richtung A „Nacht“** (dunkel, edel), mit zwei Ideen aus B: ein Schlüsselwort hervorheben (bei A durch Orange) und warme Hintergründe statt Schwarz.

**Warum:**
1. Passt zur Marke („ruhig, warm, orange“) und zum Icon.
2. Hebt sich von der hellen, bunten Konkurrenz ab (Cozi blau, FamilyWall blau, TimeTree grün, Todoist/Structured Pastell).
3. Unser Rohmaterial ist bereits dunkel und braucht keine zweite Aufnahmerunde.
4. C ist auffällig, aber zu laut für „ruhig“; B ist nett, aber austauschbar. D (Orange & Weiß) ist die ernsthafte Alternative: markentreuer und freundlicher, aber weniger edel und mit mäßigem Kontrast der weißen Schrift; es braucht komplett neue Hellmodus-Aufnahmen.
Hellmodus zeigen wir **innerhalb von A** in genau einem Bild (z. B. Kalender, Bild 5) als Hinweis, dass die App auch hell kann.

**Ablauf nach Freigabe:**

1. **Entscheidung** Richtung, Ton, Film (deine Antworten unten). *Du, 5 Min.*
2. **Aufnahmen** per Skript im Simulator (iPhone 18 Pro Max, 9:41, voller Akku, Vorführdaten), 6 Szenen (Bilder 1, 3, 4, 5, 6, 7, 8). *Claude, ca. 2 Stunden.*
3. **Live-Activity-Foto** vom echten iPhone. *Du, 10 Min.* (oder Weg 2/3 aus Abschnitt 6).
4. **Gestaltung** in 1320 × 2868 mit dem Bau-Skript (HTML → PNG), Prüfung jedes Bildes Pixel für Pixel (Lesbarkeit bei Mini-Größe 200 px Breite, Kontrast, keine Transparenz). *Claude, ca. 3 Stunden.*
5. **Du siehst die 8 Bilder** (Überblick + Einzelbilder), Korrekturrunde. *Claude + du, 1 Runde.*
6. **Texte** (Untertitel, Werbetext, Schlüsselwörter, Beschreibungsanfang) liegen als Datei bereit, du trägst sie in App Store Connect ein, die Bilder lädst du dort hoch (oder wir machen das gemeinsam). Der Werbetext ist jederzeit änderbar; Bilder, Untertitel, Schlüsselwörter und Beschreibung am besten mit der nächsten App-Version einreichen (App Store Connect zeigt, was beim Eintrag gesperrt ist). *Du, 20 Min.*
7. **Optional Phase 2:** App-Vorschau-Film. *ca. 1 Tag.*

**Gesamt:** etwa 1 Arbeitstag Claude plus rund 35 Minuten von dir.

## Entscheidungsfragen an den Inhaber

1. **Richtung:** A „Nacht“ (Empfehlung), B „Papier“ oder C „Mutig“? Oder eine Mischung (z. B. A mit hellem Kalenderbild)?
2. **Ton der Schlagzeilen:** sachlich und ruhig wie im Storyboard („Wer macht was – und bis wann?“) oder lockerer („Müll? Diese Woche Paul.“)?
3. **Live-Activity-Bild:** Hast du ein iPhone zur Hand, mit dem du einen Sperrbildschirm-Screenshot machen kannst (Weg 1)? Wenn nein: Weg 2 (Ausschnitt) oder weglassen?
4. **App-Vorschau-Film:** Gleich mit einplanen (Phase 2, ca. 1 Tag) oder erst nach den Bildern entscheiden?
