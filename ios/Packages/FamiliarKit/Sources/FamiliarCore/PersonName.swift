import Foundation

public enum PersonName {
    /// Initialen für Avatare: erster Buchstabe der ersten beiden Namensteile, in Großbuchstaben.
    /// Leere Namen ergeben „?“.
    public static func initials(from name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
