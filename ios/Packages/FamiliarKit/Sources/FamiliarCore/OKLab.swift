import Foundation

/// Farbe im wahrnehmungsnahen OKLab-Farbraum (Björn Ottosson, 2020).
///
/// Euklidische Abstände in OKLab entsprechen gut dem wahrgenommenen Farbunterschied
/// und eignen sich deshalb, um zu ähnliche Familienfarben zu erkennen.
public struct OKLab: Hashable, Sendable {
    public var lightness: Double
    public var a: Double
    public var b: Double

    public init(lightness: Double, a: Double, b: Double) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }

    public init(_ color: RGBColor) {
        let r = Self.linearize(color.red)
        let g = Self.linearize(color.green)
        let bl = Self.linearize(color.blue)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)

        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    /// Umrechnung zurück nach sRGB. Das Ergebnis kann außerhalb von 0…1 liegen;
    /// bei Bedarf `RGBColor.clamped` verwenden.
    public var rgb: RGBColor {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)

        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        return RGBColor(red: Self.delinearize(r), green: Self.delinearize(g), blue: Self.delinearize(bl))
    }

    public func distance(to other: OKLab) -> Double {
        let dl = lightness - other.lightness
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    public var chroma: Double { (a * a + b * b).squareRoot() }

    /// Farbton in Bogenmaß.
    public var hue: Double { atan2(b, a) }

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.init(lightness: lightness, a: chroma * cos(hue), b: chroma * sin(hue))
    }

    private static func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func delinearize(_ channel: Double) -> Double {
        if channel <= 0.0031308 { return 12.92 * channel }
        return 1.055 * pow(channel, 1 / 2.4) - 0.055
    }
}
