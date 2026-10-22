# Heller Modus – Konzept (2026-10-22, Entwurf)

Status: **Vorschlag**, wartet auf Freigabe. Ergänzt [design-system.md](../design-system.md) („V1 ist ausschließlich dunkel“).

## Ziel

Familiar bekommt neben dem dunklen „Fluid Ambient“ eine helle Variante: **warmes Papier** statt reinem Weiß, gleiche Marke (Bernstein-Orange, Kachel-Zeichen), gleiche Ruhe. Kein zweites Design – dieselben Bildschirme, nur andere Farbwerte.

## Auswahl

- Standard: **folgt der iPhone-Einstellung** (Hell/Dunkel/Automatisch).
- Im Profil: „Darstellung: System · Hell · Dunkel“. Gilt nur auf diesem Gerät (`@AppStorage`), keine Server-Daten.
- Widgets und Live Activity folgen immer dem System (iOS gibt deren Darstellung vor).

## Palette

Kontrastwerte berechnet (WCAG), Karte = `#FFFDFB`, Hintergrund = `#F6F0E9`.

| Token | Dunkel (bisher) | Hell | Hell, Kontrast erhöht | Kontrast hell |
|---|---|---|---|---|
| `canvas` | `#1E1519` | `#F6F0E9` (warmes Papier) | `#FBF8F4` | – |
| `elevated` | `#2A2024` | `#ECE3D9` | `#E4D9CD` | – |
| `card` | `#2C2427` | `#FFFDFB` | `#FFFFFF` | – |
| `cardPressed` | `#352B2F` | `#F3ECE4` | `#EBE2D8` | – |
| `cardGlass` | Weiß · 6 % | Weiß · 72 % | · 92 % | – |
| `cardGlassPressed` | Weiß · 10 % | Weiß · 50 % | · 70 % | – |
| `sunken` | `#160F12` | `#EEE6DD` | `#E6DCD1` | – |
| `textPrimary` | `#F6EEE6` | `#2B1F25` (Aubergine-Tinte) | `#140C10` | 15,6 : 1 |
| `textSecondary` | `#BFB2A5` | `#675850` | `#4A3D36` | 6,7 : 1 |
| `textTertiary` | `#8F8378` | `#8A7B71` (nur groß/dekorativ) | `#6B5D55` | 4,0 : 1 |
| `accent` (Fläche: Plus, Hauptknopf, „heute“-Kreis) | `#FF8C42` | `#F27A2B` | `#E86E1F` | Schrift darauf 6,8 : 1 |
| **neu** `accentInk` (orange Schrift, Symbole, Links) | = `accent` | `#B04E0C` | `#A04608` | 5,3 : 1 |
| `onAccent` | `#1B1006` | `#1B1006` | `#000000` | 6,8 : 1 |
| `success` | `#7DD69B` | `#24834A` | `#1B6E3C` | 4,7 : 1 |
| `warning` | `#F5C451` | `#9A6400` | `#7F5200` | 4,9 : 1 |
| `danger` | `#FF6B5B` | `#C23A2C` | `#A62D21` | 5,3 : 1 |
| `hairline` | `#FFF3E6` · 8 % | `#2B1F25` · 10 % | · 25 % | – |
| `lightEdge` | `#FFF3E6` · 14 % | Weiß · 90 % + weicher Schatten | – | – |
| `glowWarm` | `#FF7A3D` · 16 % | `#FF9A5C` · 12 % | aus | – |
| `glowPlum` | `#7A3B5C` · 28 % | `#E8A3B8` · 16 % (Rosé) | aus | – |

**Warum zwei Orange-Töne:** Das Marken-Orange ist auf Hell als Schrift zu schwach (2,4 : 1). Flächen (Plus, „Für alle erledigt“) behalten ein kräftiges Orange mit dunkler Schrift; orange **Schrift** („Heute“, „Bearbeiten“, aktiver Tab) bekommt das dunklere Bernstein `accentInk`. Im Dunkelmodus sind beide gleich – dort ändert sich nichts.

**Karten auf Hell:** Ohne Lichtkante wirken weiße Karten auf Papier flach. Statt der hellen Kante: feine Linie (`hairline`) plus sehr weicher Schatten (Aubergine · 6 %, 2 pt nach unten, 8 pt weich). Bei „Transparenz reduzieren“ opak (`card`).

## Familienfarben

Die acht Voreinstellungen sind auf Hell zu blass (Sonne 1,6 : 1, Salbei 1,8 : 1). Sie bleiben gespeichert wie sie sind; nur die **Anzeige** passt sich an:

- Punkte und Abzeichen bekommen einen feinen Ring (`textPrimary` · 18 %).
- Wo die Farbe trägt (Kalenderpunkte, Ring um Kacheln), dunkelt `FamilyColorResolver` sie im OKLab-Raum ab: Helligkeit höchstens L = 0,68, Farbton und Sättigung bleiben. Nur lokal, deterministisch – wie die bestehende Abstands-Korrektur.
- Familien stehen weiterhin immer mit Namen da, nie nur als Farbe.

## Unverändert

- Liquid Glass (Tab-Leiste, schwebende Knöpfe) stellt sich selbst auf Hell um.
- Schrift (Bricolage Grotesque / SF Pro), Abstände, Radien, Bewegung, Haptik.
- App-Icon: bleibt; optional später die iOS-Varianten „dunkel“ und „getönt“.
- Markenzeichen `FamiliarMark`: orange Kachel `#FF8C42` bleibt (Marke), zweite Kachel wie bisher.

## Umsetzung (nach Freigabe)

1. `FamiliarColor`: jede Farbe bekommt eine helle Variante (dieselbe Mechanik wie „Kontrast erhöhen“), neues Token `accentInk`; Stellen mit orangem Text darauf umstellen.
2. Feste Dunkelmodus-Sperre entfernen (`preferredColorScheme(.dark)` an drei Stellen, `UIUserInterfaceStyle`), Auswahl im Profil.
3. Ambient-Hintergrund, Karten-Schatten, ca. 15 fest kodierte Farbwerte (Schatten, Glanzlichter).
4. Familienfarben-Anzeige (`FamilyColorResolver`).
5. Widgets und Live Activity.
6. Prüfung: alle Bildschirme hell/dunkel × normal/Kontrast erhöht/Transparenz reduziert, UI-Tests in beiden Modi, Design-Galerie mit Umschalter; App-Store-Bilder zusätzlich hell.
