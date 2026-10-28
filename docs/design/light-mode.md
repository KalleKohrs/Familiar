# Heller Modus – Konzept (2026-10-22, Entwurf)

Status: **umgesetzt 2026-10-22** (Entwurf 2 nach Rückmeldung „zu flach, mehr Glow, minimal wärmeres Weiß, Leiste wie im Dunkeln“).

## Ziel

Familiar bekommt neben dem dunklen „Fluid Ambient“ eine helle Variante: **warmes Papier** statt reinem Weiß, gleiche Marke (Bernstein-Orange, Kachel-Zeichen), gleiche Ruhe. Kein zweites Design – dieselben Bildschirme, nur andere Farbwerte.

## Auswahl

- Standard: **folgt der iPhone-Einstellung** (Hell/Dunkel/Automatisch).
- Im Profil: „Darstellung: System · Hell · Dunkel“. Gilt nur auf diesem Gerät (`@AppStorage`), keine Server-Daten.
- Widgets und Live Activity folgen immer dem System (iOS gibt deren Darstellung vor).

## Palette

Kontrastwerte berechnet (WCAG) für den ungünstigsten Fall: Glas-Karte über dem stärksten Orange-Schein (ergibt etwa `#FCEEE2`).

| Token | Dunkel (bisher) | Hell | Hell, Kontrast erhöht | Kontrast hell |
|---|---|---|---|---|
| `canvas` | `#1E1519` | `#F5ECE1` (warmes Papier) | `#FAF4EC` | – |
| `elevated` | `#2A2024` | `#ECE1D5` | `#E4D9CD` | – |
| `card` | `#2C2427` | `#FFFAF4` | `#FFFFFF` | – |
| `cardPressed` | `#352B2F` | `#F3EADF` | `#EBE2D8` | – |
| `cardGlass` | Weiß · 6 % | `#FFFAF4` · 78 → 58 % (Verlauf von oben) | · 92 % | – |
| `cardGlassPressed` | Weiß · 10 % | `#FFFAF4` · 45 % | · 70 % | – |
| `sunken` | `#160F12` | `#EEE4D9` | `#E6DCD1` | – |
| `textPrimary` | `#F6EEE6` | `#2B1F25` (Aubergine-Tinte) | `#140C10` | 15,6 : 1 |
| `textSecondary` | `#BFB2A5` | `#675850` | `#4A3D36` | 6,7 : 1 |
| `textTertiary` | `#8F8378` | `#857669` (nur groß/dekorativ) | `#6B5D55` | 3,9 : 1 |
| `accent` (orange **Schrift**, Symbole, Links, aktiver Tab) | `#FF8C42` | `#A84A0A` | `#943F06` | 5,1 : 1 auf Glas-Karte, 4,3 : 1 im stärksten Schein |
| **neu** `accentFill` (orange **Fläche**: Plus, Hauptknopf, „heute“-Kreis, Schalter) | = `accent` | `#F27A2B` | `#E86E1F` | `onAccent` darauf 6,8 : 1 |
| `onAccent` | `#1B1006` | `#1B1006` | `#000000` | 6,8 : 1 |
| `success` | `#7DD69B` | `#1B7340` | `#165E34` | 5,2 : 1 |
| `warning` | `#F5C451` | `#855500` | `#6E4600` | 5,6 : 1 |
| `danger` | `#FF6B5B` | `#C23A2C` | `#A62D21` | 4,7 : 1 |
| `hairline` | `#FFF3E6` · 8 % | `#2B1F25` · 10 % | · 25 % | – |
| `lightEdge` | `#FFF3E6` · 14 % | Weiß · 90 % (Glanzkante oben) + warmer Schatten (`#783C1E` · 10 %, 6 pt nach unten, 18 pt weich) | – | – |
| `glowWarm` | `#FF7A3D` · 16 % | `#FF9655` · 42 % (oben rechts) | 40 % davon | – |
| `glowPlum` | `#7A3B5C` · 28 % | `#E896B2` · 45 % (Rosé, unten links) | 40 % davon | – |

**Warum zwei Orange-Töne:** Das Marken-Orange ist auf Hell als Schrift zu schwach (2,4 : 1). Flächen (Plus, „Für alle erledigt“) behalten ein kräftiges Orange mit dunkler Schrift; orange **Schrift** („Heute“, „Bearbeiten“, aktiver Tab) bekommt das dunklere Bernstein. Im Code: `accent` = Schrift/Symbol, `accentFill` = Fläche (mit `onAccent`). Im Dunkelmodus sind beide gleich – dort ändert sich nichts.

**Karten auf Hell:** durchscheinendes warmes Glas, damit der Schein durchkommt; oben eine weiße Glanzkante, darunter ein warmer, weicher Schatten. Bei „Transparenz reduzieren“ opak (`card`).

**Leiste unten:** wie im Dunkeln – Liquid-Glass-Pille (`glassEffect`) mit heller Kapsel für den aktiven Bereich und orange getönter Glas-Plus-Knopf mit Glanz und warmem Schein. Liquid Glass passt sich automatisch an; Tönung und Schatten werden für Hell eingestellt.

## Familienfarben

Die acht Voreinstellungen sind auf Hell zu blass (Sonne 1,6 : 1, Salbei 1,8 : 1). Sie bleiben gespeichert wie sie sind; nur die **Anzeige** passt sich an:

- Punkte und Abzeichen bekommen einen feinen Ring (`textPrimary` · 18 %).
- Wo die Farbe trägt (Kalenderpunkte, Ring um Kacheln), dunkelt `FamilyColorResolver` sie im OKLab-Raum ab: Helligkeit höchstens L = 0,68, Farbton und Sättigung bleiben. Nur lokal, deterministisch – wie die bestehende Abstands-Korrektur.
- Familien stehen weiterhin immer mit Namen da, nie nur als Farbe.

## Unverändert

- Liquid Glass (Tab-Leiste, schwebende Knöpfe) stellt sich selbst auf Hell um.
- Schrift (Bricolage Grotesque / SF Pro), Abstände, Radien, Bewegung, Haptik.
- App-Icon: seit 2026-10-22 Haus mit Haken, hell auf Orange; eigene Varianten „dunkel“ und „getönt“, siehe [design-system.md](../design-system.md) (Abschnitt Markenzeichen).
- Markenzeichen `FamiliarMark`: seit 2026-10-22 oranges Haus mit Haken, in beiden Modi gleich.

## Umsetzung (erledigt)

1. `FamiliarColor`: jede Farbe bekommt eine helle Variante (dieselbe Mechanik wie „Kontrast erhöhen“), neues Token `accentFill` für orange Flächen (`accent` bleibt für Schrift und Symbole); Flächen darauf umstellen.
2. Feste Dunkelmodus-Sperre entfernen (`preferredColorScheme(.dark)` an drei Stellen, `UIUserInterfaceStyle`), Auswahl im Profil.
3. Ambient-Hintergrund, Karten-Schatten, ca. 15 fest kodierte Farbwerte (Schatten, Glanzlichter).
4. Familienfarben-Anzeige (`FamilyColorResolver`).
5. Widgets und Live Activity.
6. Prüfung: alle Bildschirme hell/dunkel × normal/Kontrast erhöht/Transparenz reduziert, UI-Tests in beiden Modi, Design-Galerie mit Umschalter; App-Store-Bilder zusätzlich hell.

Ergänzungen bei der Umsetzung: neue Tokens `onScrim`/`scrim` (helle Schrift auf dunklem Schleier über Bildern, in beiden Modi gleich), `cardGlassLow` (unteres Ende des Glas-Verlaufs), `cardShadow`, `selection` (Kapsel des aktiven Tabs); Schalter im Editor in `accentFill`; Anmelde-Knöpfe: Apple im Hellen schwarz, Google mit grauem Rand (#747775); `LaunchBackground` und `AccentColor` mit heller und dunkler Variante; Familienfarben über `RGBColor.forLightBackground` (OKLab-Helligkeit ≤ 0,68, getestet).
