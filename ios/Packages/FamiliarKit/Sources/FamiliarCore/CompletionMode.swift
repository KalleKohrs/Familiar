import Foundation

/// Erledigungsart einer Aufgabe. Die Rohwerte entsprechen dem Datenbank-Enum.
public enum CompletionMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Eine zugewiesene Person erledigt die Aufgabe für alle.
    case anyOne = "any_one"
    /// Jede zugewiesene Person erledigt die Aufgabe einzeln.
    case each
}
