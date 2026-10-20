import Foundation

/// Eingabe für ``FamilyColorResolver``: eine Familie und ihre gespeicherte Originalfarbe.
public struct FamilyColorInput: Hashable, Sendable {
    public let familyID: String
    public let color: RGBColor

    public init(familyID: String, color: RGBColor) {
        self.familyID = familyID
        self.color = color
    }
}

/// Ermittelt Anzeigefarben für die Familien eines Nutzers.
///
/// Sind zwei Familienfarben für einen Nutzer gleich oder schwer unterscheidbar,
/// wird die Anzeige leicht in Farbton und Helligkeit verschoben. Die gespeicherte
/// Originalfarbe bleibt unverändert – das Ergebnis gilt nur lokal für die Darstellung.
///
/// Das Verfahren ist deterministisch: Familien werden nach ID sortiert verarbeitet,
/// die erste behält ihre Originalfarbe, spätere weichen bei Bedarf aus.
public enum FamilyColorResolver {
    /// Mindestabstand in OKLab, ab dem zwei Farben als gut unterscheidbar gelten.
    public static let minimumDistance = 0.09

    /// Liefert die Anzeigefarbe je Familien-ID.
    public static func displayColors(for inputs: [FamilyColorInput]) -> [String: RGBColor] {
        var result: [String: RGBColor] = [:]
        var placed: [OKLab] = []

        for input in inputs.sorted(by: { $0.familyID < $1.familyID }) {
            let options = candidates(around: OKLab(input.color.clamped))

            func nearestDistance(_ lab: OKLab) -> Double {
                placed.map { $0.distance(to: lab) }.min() ?? .infinity
            }

            let chosen = options.first { nearestDistance($0) >= minimumDistance }
                ?? options.max { nearestDistance($0) < nearestDistance($1) }
                ?? OKLab(input.color.clamped)

            placed.append(chosen)
            result[input.familyID] = chosen.rgb.clamped
        }
        return result
    }

    /// Kandidaten in aufsteigender Stärke der Abweichung; der erste ist die Originalfarbe.
    static func candidates(around original: OKLab) -> [OKLab] {
        let hueSteps: [Double] = [0, 18, -18, 36, -36, 54, -54, 72, -72]
        let lightnessSteps: [Double] = [0, 0.08, -0.08, 0.14, -0.14]

        var result: [OKLab] = []
        for lightnessStep in lightnessSteps {
            for hueStep in hueSteps {
                // Graue Farben haben keinen sinnvollen Farbton; dort hilft nur Helligkeit.
                if original.chroma < 0.02, hueStep != 0 { continue }
                let shifted = OKLab(
                    lightness: min(max(original.lightness + lightnessStep, 0.35), 0.92),
                    chroma: original.chroma,
                    hue: original.hue + hueStep * .pi / 180
                )
                // Über sRGB zurückrechnen, damit der Abstand die tatsächlich darstellbare Farbe misst.
                result.append(OKLab(shifted.rgb.clamped))
            }
        }
        return result
    }
}
