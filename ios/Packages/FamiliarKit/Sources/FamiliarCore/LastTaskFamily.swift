import Foundation

/// Merkt sich pro Konto, in welcher Familie zuletzt eine Aufgabe erstellt wurde (nur lokal auf dem Gerät,
/// `UserDefaults`; nichts davon geht an den Server). „Neue Aufgabe“ wählt diese Familie vor (ADR 0012).
public struct LastTaskFamily {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ userID: UUID) -> String { "LastTaskFamily.\(userID.uuidString.lowercased())" }

    public func familyID(for userID: UUID) -> UUID? {
        defaults.string(forKey: key(userID)).flatMap(UUID.init(uuidString:))
    }

    public func remember(_ familyID: UUID, for userID: UUID) {
        defaults.set(familyID.uuidString.lowercased(), forKey: key(userID))
    }

    /// Die zuletzt genutzte Familie, wenn sie noch zur Auswahl steht, sonst die erste der Liste
    /// (bei der ersten Aufgabe also die erste Familie).
    public func preferred(for userID: UUID?, among familyIDs: [UUID]) -> UUID? {
        if let userID, let last = familyID(for: userID), familyIDs.contains(last) {
            return last
        }
        return familyIDs.first
    }
}
