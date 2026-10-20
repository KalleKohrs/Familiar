import FamiliarCore
import SwiftUI
import UIKit

/// Semantische Farb-Tokens des Design-Systems „Fluid Ambient“.
///
/// V1 ist ausschließlich dunkel: warmes, leicht auberginefarbenes Graphit statt
/// kaltem Schwarz. Jede Farbe hat eine Variante für „Kontrast erhöhen“, die das
/// System automatisch wählt. Werte und Begründungen: `docs/design-system.md`.
public enum FamiliarColor {
    // MARK: Hintergründe
    public static let canvas = Color.familiar(0x1E1519, highContrast: 0x150F12)
    public static let elevated = Color.familiar(0x2A2024, highContrast: 0x241A1E)

    // MARK: Flächen
    /// Opake Card-Fläche. Basis für „Transparenz reduzieren“ und für Trennringe.
    public static let card = Color.familiar(0x2C2427, highContrast: 0x2A2125)
    public static let cardPressed = Color.familiar(0x352B2F, highContrast: 0x3B2F34)
    /// Leicht durchscheinende Card-Fläche über dem Ambient-Hintergrund (ohne Blur).
    public static let cardGlass = Color.familiar(0xFFFFFF, alpha: 0.06, highContrastAlpha: 0.09)
    public static let cardGlassPressed = Color.familiar(0xFFFFFF, alpha: 0.10, highContrastAlpha: 0.13)
    public static let sunken = Color.familiar(0x160F12, highContrast: 0x0F0A0C)

    // MARK: Text
    public static let textPrimary = Color.familiar(0xF6EEE6, highContrast: 0xFFFFFF)
    public static let textSecondary = Color.familiar(0xBFB2A5, highContrast: 0xDDD2C7)
    /// Nur für große oder rein dekorative Texte (Kontrast ca. 4,1:1 auf Cards).
    public static let textTertiary = Color.familiar(0x8F8378, highContrast: 0xB8ACA0)

    // MARK: Akzent und Status
    /// Strahlendes, warmes Bernstein-Orange.
    public static let accent = Color.familiar(0xFF8C42, highContrast: 0xFFA266)
    public static let onAccent = Color.familiar(0x1B1006, highContrast: 0x000000)
    public static let success = Color.familiar(0x7DD69B, highContrast: 0x9BE6B2)
    public static let warning = Color.familiar(0xF5C451, highContrast: 0xFFD878)
    public static let danger = Color.familiar(0xFF6B5B, highContrast: 0xFF8E81)

    // MARK: Linien
    public static let hairline = Color.familiar(0xFFF3E6, alpha: 0.08, highContrastAlpha: 0.22)
    /// Feine, helle Lichtkante an der Oberseite von Cards und schwebenden Elementen.
    public static let lightEdge = Color.familiar(0xFFF3E6, alpha: 0.14, highContrastAlpha: 0.30)

    // MARK: Ambient-Licht
    /// Warmer Lichtschein für den Hintergrund und den Orb.
    public static let glowWarm = Color(.sRGB, red: 1.0, green: 0.478, blue: 0.239)
    /// Kühlerer Pflaumen-Schein als Gegengewicht im Hintergrund.
    public static let glowPlum = Color(.sRGB, red: 0.478, green: 0.231, blue: 0.361)
}

extension Color {
    /// SwiftUI-Farbe aus einer Familienfarbe bzw. einem ``RGBColor``.
    public init(_ rgb: RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func familiar(_ hex: UInt32, highContrast: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(familiarHex: traits.accessibilityContrast == .high ? highContrast : hex)
        })
    }

    static func familiar(_ hex: UInt32, alpha: CGFloat, highContrastAlpha: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(familiarHex: hex, alpha: traits.accessibilityContrast == .high ? highContrastAlpha : alpha)
        })
    }
}

extension UIColor {
    convenience init(familiarHex hex: UInt32, alpha: CGFloat = 1) {
        let rgb = RGBColor(hex: hex)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}
