import FamiliarCore
import SwiftUI
import UIKit

/// Semantische Farb-Tokens des Design-Systems „Fluid Ambient“.
///
/// Dunkel: warmes, leicht auberginefarbenes Graphit statt kaltem Schwarz. Hell: warmes Papier
/// mit kräftigerem Ambient-Licht. Jede Farbe hat je Erscheinungsbild eine Variante für
/// „Kontrast erhöhen“, die das System automatisch wählt. Werte und Begründungen:
/// `docs/design-system.md`, `docs/design/light-mode.md`.
public enum FamiliarColor {
    // MARK: Hintergründe
    public static let canvas = Color.familiar(dark: 0x1E1519, darkHC: 0x150F12, light: 0xF5ECE1, lightHC: 0xFAF4EC)
    public static let elevated = Color.familiar(dark: 0x2A2024, darkHC: 0x241A1E, light: 0xECE1D5, lightHC: 0xE4D9CD)

    // MARK: Flächen
    /// Opake Card-Fläche. Basis für „Transparenz reduzieren“ und für Trennringe.
    public static let card = Color.familiar(dark: 0x2C2427, darkHC: 0x2A2125, light: 0xFFFAF4, lightHC: 0xFFFFFF)
    public static let cardPressed = Color.familiar(dark: 0x352B2F, darkHC: 0x3B2F34, light: 0xF3EADF, lightHC: 0xEBE2D8)
    /// Leicht durchscheinende Card-Fläche über dem Ambient-Hintergrund (ohne Blur), oberer Rand.
    public static let cardGlass = Color.familiar(
        dark: (0xFFFFFF, 0.06, 0.09), light: (0xFFFAF4, 0.78, 0.92))
    /// Unterer Rand des Card-Verlaufs: im Dunkeln wie oben, im Hellen durchscheinender.
    public static let cardGlassLow = Color.familiar(
        dark: (0xFFFFFF, 0.06, 0.09), light: (0xFFFAF4, 0.58, 0.88))
    public static let cardGlassPressed = Color.familiar(
        dark: (0xFFFFFF, 0.10, 0.13), light: (0xFFFAF4, 0.45, 0.70))
    public static let sunken = Color.familiar(dark: 0x160F12, darkHC: 0x0F0A0C, light: 0xEEE4D9, lightHC: 0xE6DCD1)

    // MARK: Text
    public static let textPrimary = Color.familiar(dark: 0xF6EEE6, darkHC: 0xFFFFFF, light: 0x2B1F25, lightHC: 0x140C10)
    public static let textSecondary = Color.familiar(dark: 0xBFB2A5, darkHC: 0xDDD2C7, light: 0x675850, lightHC: 0x4A3D36)
    /// Nur für große oder rein dekorative Texte (Kontrast ca. 4:1 auf Cards).
    public static let textTertiary = Color.familiar(dark: 0x8F8378, darkHC: 0xB8ACA0, light: 0x857669, lightHC: 0x6B5D55)

    // MARK: Akzent und Status
    /// Orange für Schrift, Symbole und Umrandungen. Im Hellen ein dunkleres Bernstein, damit
    /// es als Text lesbar bleibt; im Dunkeln das strahlende Marken-Orange.
    public static let accent = Color.familiar(dark: 0xFF8C42, darkHC: 0xFFA266, light: 0xA84A0A, lightHC: 0x943F06)
    /// Orange für Flächen mit `onAccent` darauf (Plus, Hauptknopf, „heute“, erledigt).
    public static let accentFill = Color.familiar(dark: 0xFF8C42, darkHC: 0xFFA266, light: 0xF27A2B, lightHC: 0xE86E1F)
    public static let onAccent = Color.familiar(dark: 0x1B1006, darkHC: 0x000000, light: 0x1B1006, lightHC: 0x000000)
    /// Schrift und Symbole auf dunklen Schleiern über Bildern (`scrim`) – in beiden Modi hell.
    public static let onScrim = Color.familiar(dark: 0xF6EEE6, darkHC: 0xFFFFFF, light: 0xF6EEE6, lightHC: 0xFFFFFF)
    /// Dunkler Schleier über Bildern und Profilbildern, damit `onScrim` darauf lesbar ist.
    public static let scrim = Color.black.opacity(0.6)
    public static let success = Color.familiar(dark: 0x7DD69B, darkHC: 0x9BE6B2, light: 0x1B7340, lightHC: 0x165E34)
    public static let warning = Color.familiar(dark: 0xF5C451, darkHC: 0xFFD878, light: 0x855500, lightHC: 0x6E4600)
    public static let danger = Color.familiar(dark: 0xFF6B5B, darkHC: 0xFF8E81, light: 0xC23A2C, lightHC: 0xA62D21)

    // MARK: Linien
    public static let hairline = Color.familiar(dark: (0xFFF3E6, 0.08, 0.22), light: (0x2B1F25, 0.10, 0.25))
    /// Feine Lichtkante an der Oberseite von Cards und schwebenden Elementen.
    public static let lightEdge = Color.familiar(dark: (0xFFF3E6, 0.14, 0.30), light: (0xFFFFFF, 0.90, 0.95))
    /// Weicher, warmer Schatten unter Cards – nur im Hellen (im Dunkeln unsichtbar).
    public static let cardShadow = Color.familiar(dark: (0x000000, 0, 0), light: (0x783C1E, 0.10, 0.14))
    /// Kapsel hinter dem aktiven Bereich der Tab-Leiste.
    public static let selection = Color.familiar(dark: (0x000000, 0.32, 0.45), light: (0x2B1F25, 0.07, 0.12))

    // MARK: Ambient-Licht
    /// Warmer Lichtschein für den Hintergrund.
    public static let glowWarm = Color.familiar(dark: 0xFF7A3D, darkHC: 0xFF7A3D, light: 0xFF9655, lightHC: 0xFF9655)
    /// Gegengewicht unten links: im Dunkeln Pflaume, im Hellen Rosé.
    public static let glowPlum = Color.familiar(dark: 0x7A3B5C, darkHC: 0x7A3B5C, light: 0xE896B2, lightHC: 0xE896B2)
}

extension Color {
    /// SwiftUI-Farbe aus einer Familienfarbe bzw. einem ``RGBColor``. Im Hellen werden zu helle
    /// Farben abgedunkelt (``RGBColor/forLightBackground``), damit Punkte und Ringe sichtbar bleiben.
    public init(_ rgb: RGBColor) {
        let dark = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        let shown = rgb.forLightBackground
        let light = UIColor(red: shown.red, green: shown.green, blue: shown.blue, alpha: 1)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .light ? light : dark })
    }

    static func familiar(dark: UInt32, darkHC: UInt32, light: UInt32, lightHC: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            return UIColor(familiarHex: traits.userInterfaceStyle == .light ? (high ? lightHC : light) : (high ? darkHC : dark))
        })
    }

    /// Farbe mit Deckkraft: (Hex, Deckkraft, Deckkraft bei „Kontrast erhöhen“) je Erscheinungsbild.
    static func familiar(dark: (UInt32, CGFloat, CGFloat), light: (UInt32, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let (hex, alpha, highAlpha) = traits.userInterfaceStyle == .light ? light : dark
            return UIColor(familiarHex: hex, alpha: traits.accessibilityContrast == .high ? highAlpha : alpha)
        })
    }
}

extension UIColor {
    convenience init(familiarHex hex: UInt32, alpha: CGFloat = 1) {
        let rgb = RGBColor(hex: hex)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}
