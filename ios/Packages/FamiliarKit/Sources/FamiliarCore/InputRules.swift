import Foundation

/// Eingaberegeln wie in den RPCs (Migration 0004). Die App prüft vorab für sofortiges Feedback;
/// maßgeblich bleibt der Server.
public enum InputRules {
    public static let familyNameLength = 1...60
    public static let displayNameLength = 1...80

    public static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isValidFamilyName(_ name: String) -> Bool {
        familyNameLength.contains(trimmed(name).count)
    }

    public static func isValidDisplayName(_ name: String) -> Bool {
        displayNameLength.contains(trimmed(name).count)
    }

    /// Grobe Plausibilitätsprüfung; die echte Prüfung ist der Code per E-Mail.
    public static func isPlausibleEmail(_ email: String) -> Bool {
        let value = trimmed(email)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !value.contains(" ") else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// E-Mail-Codes sind laut Supabase standardmäßig 6-stellig; die Länge ist im Dashboard
    /// auf bis zu 10 Stellen einstellbar, daher werden 6–10 Ziffern akzeptiert.
    public static func isPlausibleEmailCode(_ code: String) -> Bool {
        let value = trimmed(code)
        return (6...10).contains(value.count) && value.allSatisfy(\.isASCII) && value.allSatisfy(\.isNumber)
    }
}
