import ActivityKit
import FamiliarCore
import Foundation

/// Attribute einer Aufgaben-Live-Activity.
///
/// Wichtig für Server-Payloads (Push-to-Start/Update): ActivityKit dekodiert
/// `content-state` und `attributes` mit Standard-`Codable` ohne eigene Strategien.
/// Deshalb werden Zeitpunkte als Unix-Sekunden (`Double`) statt als `Date` übertragen.
/// Statische und dynamische Daten zusammen dürfen 4 KB nicht überschreiten.
public struct TaskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        /// Startzeitpunkt als Sekunden seit 1970 (UTC); `nil` bei Aufgaben ohne Uhrzeit.
        public var startsAtUnix: Double?
        public var completionMode: CompletionMode
        public var assignees: [AssigneeState]
        /// Ob die Person auf diesem Gerät die Aufgabe laut Erledigungsart abhaken darf.
        public var canComplete: Bool

        public init(
            title: String,
            startsAtUnix: Double?,
            completionMode: CompletionMode,
            assignees: [AssigneeState],
            canComplete: Bool
        ) {
            self.title = title
            self.startsAtUnix = startsAtUnix
            self.completionMode = completionMode
            self.assignees = assignees
            self.canComplete = canComplete
        }

        public var startsAt: Date? { startsAtUnix.map { Date(timeIntervalSince1970: $0) } }
    }

    /// Kompakter Status einer zugewiesenen Person.
    public struct AssigneeState: Codable, Hashable, Sendable {
        public var initials: String
        public var isDone: Bool

        public init(initials: String, isDone: Bool) {
            self.initials = initials
            self.isDone = isDone
        }
    }

    public var taskID: UUID
    public var familyColorHex: String

    public init(taskID: UUID, familyColorHex: String) {
        self.taskID = taskID
        self.familyColorHex = familyColorHex
    }
}
