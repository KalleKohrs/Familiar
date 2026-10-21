import FamiliarCore
import Foundation

extension TaskActivityAttributes.ContentState {
    /// Inhalt für einen lokalen Start oder Abgleich – dieselben Felder, die `push_claim_jobs` liefert.
    /// - Parameter names: Anzeigenamen der Zugewiesenen (für die Initialen).
    public init(task: TaskItem, userID: UUID, names: [UUID: String]) {
        self.init(
            title: task.title,
            startsAtUnix: task.startTime != nil ? task.startsAt?.timeIntervalSince1970 : nil,
            completionMode: task.completionMode,
            assignees: task.assignees
                .map { (name: names[$0.userID] ?? "?", isDone: $0.isDone) }
                .sorted { $0.name < $1.name }
                .map { .init(initials: String($0.name.prefix(1)).uppercased(), isDone: $0.isDone) },
            canComplete: LiveActivityRules.isOpen(task, for: userID)
        )
    }
}
