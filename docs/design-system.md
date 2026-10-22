# Design-System „Fluid Ambient“

Dunkle, warme Ästhetik (Aubergine-Graphit) mit Bernstein-Orange-Akzent und weichem Ambient-Licht. Ruhig, klar, flüssig. **Lesbarkeit, Bedienbarkeit, Performance und Barrierefreiheit haben Vorrang vor Effekten.**

Umsetzung: `ios/Packages/FamiliarKit/Sources/FamiliarDesign`. Alle Screens verwenden ausschließlich diese Tokens und Komponenten. Die Übersicht `DesignGalleryView` ist in Debug-Builds über „Design-System ansehen“ auf der Aufgaben-Startseite erreichbar und dient als Xcode-Preview.

## Farben

Dunkel und hell (seit 2026-10-22). Standard: folgt der iPhone-Einstellung; im Profil „Darstellung: System · Hell · Dunkel“ (nur dieses Gerät, `Appearance`, gesetzt per `overrideUserInterfaceStyle` am Fenster, damit auch offene Blätter sofort wechseln). Jede Farbe hat je Erscheinungsbild eine Variante für **Kontrast erhöhen**, die das System automatisch wählt. Die Tabelle zeigt die dunklen Werte; helle Werte, `accentFill` und Begründungen: [design/light-mode.md](design/light-mode.md).

| Token | Standard | Kontrast erhöht | Verwendung |
|---|---|---|---|
| `canvas` | `#1E1519` | `#150F12` | Bildschirmhintergrund (warmes Graphit mit Aubergine-Ton) |
| `elevated` | `#2A2024` | `#241A1E` | Avatare, Platzhalter, erhöhte Flächen |
| `cardGlass` | Weiß · 6 % | · 9 % | Card-Fläche, leicht durchscheinend über dem Ambient-Hintergrund (ohne Blur) |
| `cardGlassPressed` | Weiß · 10 % | · 13 % | Card im gedrückten Zustand |
| `card` | `#2C2427` | `#2A2125` | Opake Card (bei „Transparenz reduzieren“), Trennringe |
| `cardPressed` | `#352B2F` | `#3B2F34` | Opake Card gedrückt |
| `sunken` | `#160F12` | `#0F0A0C` | Eingabefelder |
| `textPrimary` | `#F6EEE6` | `#FFFFFF` | Titel und Fließtext |
| `textSecondary` | `#BFB2A5` | `#DDD2C7` | Beschreibungen, Metadaten (≈ 7,4 : 1 auf Card) |
| `textTertiary` | `#8F8378` | `#B8ACA0` | nur große oder dekorative Texte (≈ 4,1 : 1) |
| `accent` | `#FF8C42` | `#FFA266` | Strahlendes Bernstein-Orange: interaktive Elemente, Plus, Hinweise, Logo (≈ 6,6 : 1 auf Card) |
| `onAccent` | `#1B1006` | `#000000` | Text/Symbole auf Akzentflächen (≈ 8 : 1) |
| `success` | `#7DD69B` | `#9BE6B2` | Erledigt |
| `warning` | `#F5C451` | `#FFD878` | Hinweise, Wiederholung |
| `danger` | `#FF6B5B` | `#FF8E81` | Überfällig, Löschen |
| `hairline` | `#FFF3E6` · 8 % | · 22 % | Feine Trennlinien |
| `lightEdge` | `#FFF3E6` · 14 % | · 30 % | Helle Lichtkante oben an Cards |
| `glowWarm` | `#FF7A3D` | – | Warmer Lichtschein (Hintergrund) |
| `glowPlum` | `#7A3B5C` | – | Pflaumen-Schein (Hintergrund) |

**Familienpalette** (Voreinstellungen, eigene Farbe per Farbwähler möglich): Koralle `#FF7F66`, Sonne `#F7C548`, Salbei `#8FD19E`, Himmel `#5EC2F2`, Lavendel `#B39DFF`, Rose `#F59AC0`, Petrol `#4CCFBF`, Sand `#D9B38C`.

**Ähnliche Familienfarben:** `FamilyColorResolver` (FamiliarCore) misst Abstände im OKLab-Farbraum. Liegen zwei Familienfarben eines Nutzers näher als 0,09 beieinander, wird die Anzeige leicht in Farbton und/oder Helligkeit verschoben – nur lokal, deterministisch; die gespeicherte Originalfarbe bleibt unverändert. Familien werden zusätzlich immer mit Namen gekennzeichnet (`FamilyBadge`), nie allein über Farbe.

## Typografie

Alle Stile basieren auf Dynamic-Type-Textstilen und skalieren mit der Systemschriftgröße.

| Token | Basis | Standardgröße | Verwendung |
|---|---|---|---|
| `display` | `largeTitle`, New York, semibold | 34 pt | Bildschirmtitel |
| `title` | `title2`, New York, semibold | 22 pt | Sheet- und Abschnittstitel, Leerzustände |
| `sectionTitle` | `headline` | 17 pt | Gruppenüberschriften |
| `cardTitle` | `body`, semibold | 17 pt | Aufgabentitel |
| `body` | `body` | 17 pt | Fließtext |
| `secondary` | `subheadline` | 15 pt | Beschreibungen |
| `meta` | `footnote` | 13 pt | Metadaten |
| `caption` | `caption`, medium | 12 pt | Badges |
| `time` | `footnote`, monospaced digits, medium | 13 pt | Uhrzeiten |

## Maße

- **Abstände:** 4 · 8 · 12 · 16 · 20 · 24 · 32 pt (`FamiliarSpacing.xxs … xxl`)
- **Radien:** Card 24 pt, Steuerelement 16 pt, Chip 12 pt – immer `continuous`
- **Touch-Flächen:** mindestens 44 × 44 pt; Buttons mindestens 50 pt hoch

## Materialien und Licht

Referenzbilder: [`design/reference-overview.webp`](design/reference-overview.webp), [`design/reference-feed.webp`](design/reference-feed.webp).
Leitbild aus der Design-Referenz vom 2026-10-20: dunkles Aubergine-Graphit, weiches Ambient-Licht, leicht durchscheinende Cards mit Lichtkante, (ursprünglich ein leuchtender Orange-Orb als Markenelement – am 2026-10-21 durch das flache Kachel-Zeichen ersetzt), schwebende runde Glas-Buttons mit orangem Plus.

- **Ambient-Hintergrund** (`FamiliarAmbientBackground`, über `familiarScreenBackground()`): `canvas` plus zwei statische Radialverläufe – warm oben (`glowWarm`, dunkel 16 %, hell 42 %), Pflaume bzw. Rosé unten links (`glowPlum`, dunkel 28 %, hell 45 %). Keine Animation, kein Blur; bei „Kontrast erhöhen“ oder „Transparenz reduzieren“ auf 40 % reduziert.
- **Oberer Scroll-Rand:** weich (`scrollEdgeEffectStyle(.soft)`) – Inhalte verschwimmen unter den schwebenden Knöpfen, ohne sichtbare Kante (der harte Stil zeichnete eine Trennlinie).
- **Markenzeichen** (`FamiliarMark`): flache orange Kachel mit Haken vor einer zweiten Kachel in Familienfarbe („geteilte Aufgaben“); ohne Verläufe, Leuchten oder 3D. Anmeldung, Onboarding, Ladebildschirm, App-Icon (`tools/render-app-icon.swift`). Leerzustände zeigen nur ein Symbol auf ruhigem Grund.
- **Liquid Glass** nur für schwebende Bedienelemente: die eigene Navigationsleiste `FloatingTabBar` (Glas-Pille mit drei Bereichen und daneben ein orange getönter Glas-Button „Neue Aufgabe“, `glassEffect(.regular.tint(accent).interactive())`, siehe [ADR 0006](decisions/0006-custom-glass-tab-bar.md)), System-Toolbars und ggf. weitere schwebende Buttons (`glassEffect`, `GlassEffectContainer`). Aktiver Bereich: Symbol und Text in `accent` auf heller Kapsel (`textPrimary` · 10 %).
- **Cards** sind leicht durchscheinend (`cardGlass`) mit Verlaufs-Lichtkante (`lightEdge` → `hairline`) – ohne Blur, damit Listen flüssig scrollen. Bei „Transparenz reduzieren“ automatisch opak (`card`).
- **Perlmutt-Reflex** (`pearlEdge`): statischer, dezenter chromatischer Rand nur für hervorgehobene Einzelelemente; keine Dauer-Animation.

## Bewegung

- Standard: `spring(response: 0.42, dampingFraction: 0.82)`; schnelle Reaktionen: `spring(response: 0.28, dampingFraction: 0.86)`.
- **Bewegung reduzieren:** nur Überblendungen (0,2 s), keine Skalierung oder Positionswechsel (`familiarAnimation`, `FamiliarMotion.appearTransition`).
- Card → Detail: `matchedTransitionSource` + `.navigationTransition(.zoom)`; Miniatur → Galerie analog.
- Bedienbarkeit hängt nie von Animationen ab.

## Haptik

Zurückhaltend über `sensoryFeedback`:

| Moment | Feedback |
|---|---|
| Plus-Button „Neue Aufgabe“ antippen | `impact(weight: .medium)` |
| Auswahl/Einrasten (Picker, Segmente) | `selection` |
| Aufgabe erfolgreich erledigt | `success` |

Keine Haptik bei gewöhnlichen Taps, Scrollen oder Navigation.

## Status von Personen

Offene und erledigte Personen sind ohne Farbwahrnehmung unterscheidbar: Erledigte Avatare werden auf 45 % abgeschwächt **und** erhalten ein Häkchen-Abzeichen. VoiceOver sagt „Name, erledigt“ bzw. „Name, offen“.

## Komponenten

| Komponente | Zweck |
|---|---|
| `familiarCard()` / `.buttonStyle(.familiarCard)` | Content-Fläche, antippbar mit Druckzustand |
| `familiarScreenBackground()` / `FamiliarAmbientBackground` | Bildschirmhintergrund mit Ambient-Licht |
| `FamiliarMark` | Flaches Kachel-Zeichen mit Haken (Markenelement, App-Icon) |
| `.familiarPrimary` / `.familiarSecondary` / `.familiarDestructive` | Kapsel-Buttons |
| `CompletionCheckButton` | Abhaken (28 pt sichtbar, 44 pt Touch-Fläche) |
| `AvatarView`, `AvatarStack` | Profilbild/Initialen mit Status, Stapel mit Überlauf |
| `FamilyBadge` | Familienfarbe + Name |
| `FamiliarTag` | Zeit, Status, Hinweise |
| `FamiliarSectionHeader` | Gruppenüberschrift (VoiceOver-Überschrift) |
| `FamiliarEmptyState`, `FamiliarErrorState`, `FamiliarSkeleton` | Leer-, Fehler- und Ladezustände |

## Barrierefreiheit – Checkliste je Screen

- VoiceOver-Labels für alle interaktiven Elemente; Status in Worten.
- Dynamic Type bis zu den größten Bedienungshilfen-Größen ohne abgeschnittene Inhalte.
- Kontrast mindestens 4,5 : 1 für Fließtext; „Kontrast erhöhen“ getestet.
- „Bewegung reduzieren“ und „Transparenz reduzieren“ getestet.
- Kleine Displays (iPhone 17e) und Tastatur geprüft.

## Aufgabenliste und Editor (Überarbeitung 2026-10-21)

Nach Rückmeldung „nicht clean genug“ an der Referenz ausgerichtet:

- **Kopf:** große Überschrift in New York (`FamiliarFont.display`) im Inhalt statt der System-Navigationsüberschrift; keine Zählzeile.
- **Gliederung:** Abschnitte „Überfällig · Heute · Morgen · Später“ (`TaskRules.homeSections`) als kleine Versal-Überschriften mit Anzahl. Aufgaben ohne Datum stehen in „Heute“ ganz oben (neueste zuerst).
- **Karte:** Titel, darunter *eine* ruhige Infozeile aus Text mit kleinen Symbolen (Start bzw. „Überfällig“, Wiederholung, Familie mit Farbpunkt) statt Chips; Beschreibung höchstens zwei Zeilen; Miniatur rechts oben. Unten Personen links und der runde Glas-Knopf zum Abhaken rechts (40 pt, wie die runden Bedienelemente der Referenz). Kein farbiger Randstreifen mehr.
- **Abhaken:** Der Haken füllt sich sofort (Symbol-Federeffekt, Erfolgs-Haptik), nach 0,35 s wird gespeichert; die Karte blendet mit leichter Verkleinerung aus.
- **Erledigungsart:** im Editor zwei Kacheln nebeneinander (Symbol + Kurztitel), Erklärung nur einmal darunter; in den Details ein kleines Etikett (Erklärung als VoiceOver-Hinweis).
- **Profilbilder an Aufgaben:** mit kleinem Abstand statt Überlappung; erledigt = grüner Ring plus Häkchen-Abzeichen (keine Abschwächung).
- **Entscheidungsfragen** (Löschen, Geltungsbereich bei Serien): `FamiliarChoiceSheet` – kleines Blatt von unten mit Symbol, Überschrift, Erklärung und Knöpfen statt System-Aktionsmenü.
- **Editor:** Tastatur verschwindet beim Scrollen und bei jeder Auswahl; „Weiter“ springt vom Titel zur Beschreibung. Beim Speichern mit fehlenden Angaben: Sprung zur ersten Stelle, rote Hinweise direkt am Abschnitt, Fehler-Haptik.

## Kalender (Phase 6)

- Überschrift „Kalender“ in New York; Monatsraster in einer Card, Wochen ab Montag, Tage anderer Monate abgeschwächt.
- Monat wechseln: runde Glas-Knöpfe (wie die Referenz) oder horizontal wischen; „Heute“-Knopf erscheint, sobald man sich vom heutigen Tag entfernt.
- Heute: orange gefüllter Kreis; gewählter Tag: Glas-Kreis mit orangem Rand.
- Punkte unter dem Tag (max. 3) in Familienfarbe: voll = Aufgabe, blass = geplanter Serientermin bzw. erledigt. Outlook-Termine (Phase 8): Ring statt Punkt und in der Liste mit Anbieter-Namen – nie nur über Farbe unterschieden.
- Tagesliste: Zeilen mit Uhrzeit links (bzw. „Ganzer Tag“), Titel, Wiederholung/Familie; erledigt = durchgestrichen mit grünem Haken; geplante Serientermine mit „Geplant“ und nicht antippbar.
- VoiceOver je Tag: „21. Oktober, 2 Aufgaben, 1 geplant“.

## Eigenständigkeit statt Standard-Look (2026-10-21)

Recherche zu typischen Merkmalen KI-generierter („vibe-coded“) Apps: Standardschriften (Inter, Systemschrift), lila-blaue Verläufe, Leuchteffekte im Dunkelmodus, Karten um alles, große Symbole über jeder Überschrift, Versal-Überschriften mit Sperrung, Akzentfarbe überall. Konsequenzen für Familiar:

- **Schrift:** Überschriften, Kartentitel und Gruppenlabels in **Bricolage Grotesque** (variabel mit optischen Größen, SIL OFL; `FamiliarTypeface`), Fließtext bleibt SF Pro für Lesbarkeit und Dynamic Type. Die Systemschrift „New York“ wird nicht mehr verwendet.
- **Gruppenlabels** in normaler Schreibweise („Heute 2“) statt Versalien mit Sperrung.
- **Akzentfarbe** nur für das Plus, Hauptaktionen und „heute“; Schalter für Rechte in Grün.
- Offene Punkte für den nächsten Design-Durchgang: Ambient-Schein zurücknehmen (Orb ersetzt am 2026-10-21), Karten nur für einzeln bedienbare Einträge (nicht um Leerzustände und Hinweise).
