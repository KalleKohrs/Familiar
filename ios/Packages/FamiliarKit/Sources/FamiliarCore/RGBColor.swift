import Foundation

/// Eine sRGB-Farbe mit Kanälen im Bereich 0…1.
///
/// Familienfarben werden in der Datenbank als `#RRGGBB` gespeichert. Dieser Typ
/// ist die gemeinsame, UI-unabhängige Darstellung für Parsing und Farbabstände.
public struct RGBColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Erstellt eine Farbe aus `#RRGGBB` oder `RRGGBB`. Gibt `nil` bei ungültiger Eingabe zurück.
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(hex: number)
    }

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// `#RRGGBB` in Großbuchstaben, Kanäle auf 0…1 begrenzt.
    public var hexString: String {
        func byte(_ channel: Double) -> Int { Int((min(max(channel, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Kanäle auf den darstellbaren Bereich 0…1 begrenzt.
    public var clamped: RGBColor {
        RGBColor(red: min(max(red, 0), 1), green: min(max(green, 0), 1), blue: min(max(blue, 0), 1))
    }
}
