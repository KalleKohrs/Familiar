import FamiliarCore
import Foundation

/// Vorgeschlagene Familienfarben. Auf dem dunklen Hintergrund gut lesbar und
/// untereinander klar unterscheidbar. Nutzer können zusätzlich eine eigene Farbe wählen.
public struct FamilyPaletteColor: Identifiable, Hashable, Sendable {
    public let name: String
    public let hex: String

    public var id: String { hex }
    public var rgb: RGBColor { RGBColor(hex: hex) ?? RGBColor(hex: 0xFFA43A) }
}

public enum FamilyPalette {
    public static let presets: [FamilyPaletteColor] = [
        FamilyPaletteColor(name: "Koralle", hex: "#FF7F66"),
        FamilyPaletteColor(name: "Sonne", hex: "#F7C548"),
        FamilyPaletteColor(name: "Salbei", hex: "#8FD19E"),
        FamilyPaletteColor(name: "Himmel", hex: "#5EC2F2"),
        FamilyPaletteColor(name: "Lavendel", hex: "#B39DFF"),
        FamilyPaletteColor(name: "Rose", hex: "#F59AC0"),
        FamilyPaletteColor(name: "Petrol", hex: "#4CCFBF"),
        FamilyPaletteColor(name: "Sand", hex: "#D9B38C"),
    ]
}
