# ADR 0006: Eigene Liquid-Glass-Leiste mit orangem Plus-Button

- **Status:** angenommen (2026-10-20), ersetzt den Navigationsteil von [ADR 0002](0002-ios27-native-tabview.md)
- **Kontext:** Spike S1 hat gezeigt, dass ein Tab mit `TabRole.prominent` als abgesetzter runder Glas-Button erscheint und sich abfangen lässt. Zwei Punkte sprechen aber dagegen:
  - Apple HIG (Tab bars): „Use a tab bar to support navigation, not to provide actions.“ Das Plus ist eine Aktion (öffnet „Neue Aufgabe“), kein Bereich.
  - Der Guide und die Design-Referenz verlangen einen Plus-Button in der Akzentfarbe; für eine Einfärbung des `.prominent`-Tabs fand sich keine dokumentierte API.
- **Entscheidung (Nutzer: Variante B):**
  - Inhalte bleiben in einer SwiftUI-`TabView` (Zustand je Bereich bleibt erhalten); deren System-Tab-Bar wird mit `toolbarVisibility(.hidden, for: .tabBar)` ausgeblendet.
  - `FloatingTabBar` (App-Target) liegt als Overlay unten: Pille mit drei Bereichen (`glassEffect(.regular, in: .capsule)`) und daneben ein runder Button „Neue Aufgabe“ mit `glassEffect(.regular.tint(accent).interactive(), in: .circle)`, beide in einem `GlassEffectContainer` (laut Apple-Artikel „Applying Liquid Glass to custom views“ für Leistung und Verschmelzen der Formen; Tint „to suggest prominence“).
  - Der Platz für die Leiste wird über `contentMargins(.bottom, Höhe)` an alle Scroll-Ansichten der Bereiche weitergegeben (auch auf Unterseiten). `safeAreaInset` an der Tab-Wurzel erreichte die Inhalte im `NavigationStack` im Simulator nicht.
- **Barrierefreiheit:** Jeder Bereich ist genau ein Element (Symbol ausgeblendet, Inhalt zusammengefasst), der aktive Bereich trägt `.isSelected`. Bewusst **ohne** `AccessibilityTraits.isTabBar` an der Pille: Mit diesem Container-Trait legte SwiftUI Symbol und Text jedes Bereichs zusätzlich als eigene Buttons offen (im UI-Test `testEachTabIsASingleAccessibilityElement` nachgewiesen, ohne den Trait behoben); Beschriftungen wachsen bis Dynamic-Type-Größe „xLarge“ mit, darüber zeigt der Large Content Viewer (lange drücken) Symbol und Titel. Auswahl-Kapsel gleitet mit, bei „Bewegung reduzieren“ nur Überblendung. Plus-Symbol in `onAccent` (dunkel) auf Orange für ausreichenden Kontrast.
- **Geprüft (Simulator, iPhone 17, iOS 27.0):** System-Tab-Bar bleibt auch auf Unterseiten ausgeblendet; Plus öffnet das Sheet, nach „Abbrechen“ bleibt der aktive Bereich ausgewählt; das Listenende bleibt oberhalb der Leiste sichtbar.
- **Konsequenzen / offen:**
  - Verhalten der System-Tab-Bar, das jetzt selbst gebaut werden muss, falls gewünscht: erneutes Antippen des aktiven Bereichs scrollt nach oben bzw. springt zur Wurzel; Verkleinern beim Scrollen.
  - Verschachtelte horizontale Scroll-Ansichten (z. B. Bildstreifen ab Phase 3) setzen den unteren Inhaltsrand mit `contentMargins(.bottom, 0)` zurück.
  - UI-Test `PlusTabUITests` (prüft Auswahl-Status und Sheet) wurde angepasst, aber wegen Speichermangels noch nicht ausgeführt.
