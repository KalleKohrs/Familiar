import Foundation

/// Einladungscodes: 8 Zeichen Crockford-Base32 (Migration 0002).
///
/// Die Normalisierung entspricht `private.normalize_invite_code` auf dem Server, damit die App
/// Eingaben schon vor dem Senden prüfen und einheitlich anzeigen kann. Maßgeblich bleibt der Server.
public enum InviteCode {
    public static let length = 8
    static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Großschreibung, Leerzeichen und Bindestriche entfernen, `O → 0`, `I/L → 1`.
    public static func normalize(_ input: String) -> String {
        var result = ""
        for character in input.uppercased() {
            switch character {
            case " ", "-", "\t", "\n": continue
            case "O": result.append("0")
            case "I", "L": result.append("1")
            default: result.append(character)
            }
        }
        return result
    }

    /// `true`, wenn die Eingabe nach Normalisierung ein gültiger Code sein kann.
    public static func isValid(_ input: String) -> Bool {
        let code = normalize(input)
        return code.count == length && code.allSatisfy(alphabet.contains)
    }

    /// Lesbare Schreibweise `ABCD-EFGH`; ungültige Eingaben bleiben unverändert.
    public static func formatted(_ input: String) -> String {
        let code = normalize(input)
        guard code.count == length else { return input }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}

/// Einladungslinks `https://familiar-app.de/join/ABCD-EFGH` (Universal Link, Plan Abschnitt 6).
/// Ohne App öffnet der Link eine Seite mit dem Code und dem Weg in den App Store.
public enum InviteLink {
    public static let host = "familiar-app.de"

    public static func url(for code: String) -> URL? {
        guard InviteCode.isValid(code) else { return nil }
        return URL(string: "https://\(host)/join/\(InviteCode.formatted(code))")
    }

    /// Code aus einem Einladungslink; `nil` für alle anderen Adressen.
    public static func code(from url: URL) -> String? {
        guard url.scheme == "https",
              let urlHost = url.host()?.lowercased(), urlHost == host || urlHost == "www.\(host)" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0].lowercased() == "join", InviteCode.isValid(parts[1]) else { return nil }
        return InviteCode.normalize(parts[1])
    }
}

/// Text, den die Teilen-Funktion verschickt (Nachricht, AirDrop, Mail).
public enum InviteMessage {
    /// Mit Link: Der Link öffnet die App oder – ohne App – eine Seite mit dem Weg in den App Store.
    /// Der Code steht zusätzlich da, falls der Link nicht geöffnet werden kann.
    public static func text(familyName: String, code: String, expiresAt: Date) -> String {
        let formatted = InviteCode.formatted(code)
        let until = expiresAt.formatted(date: .abbreviated, time: .omitted)
        guard let link = InviteLink.url(for: code) else {
            return String(localized: "Komm in unsere Familie „\(familyName)“ bei Familiar! Code: \(formatted) (gültig bis \(until)).")
        }
        return String(localized: "Komm in unsere Familie „\(familyName)“ bei Familiar: \(link.absoluteString)\nNoch nicht in der App? Der Link führt dich zum kostenlosen Download. Oder in der App „Mit Code beitreten“ wählen: \(formatted) (gültig bis \(until)).")
    }
}
