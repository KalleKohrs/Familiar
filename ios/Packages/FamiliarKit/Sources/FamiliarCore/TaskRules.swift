import Foundation

/// Was die angemeldete Person mit einer offenen Aufgabe tun darf (spiegelt `complete_task`).
public enum TaskCompletionAction: Hashable, Sendable {
    /// Als zugewiesene Person abhaken („Eine für alle“: ganze Aufgabe; „einzeln“: eigener Teil).
    case completeForMe
    /// Ganze Aufgabe erledigen, weil man sie erstellt hat.
    case completeForAll
    /// Eigenen Haken zurücknehmen („einzeln“, Aufgabe noch offen).
    case undoMine
}

/// Umfang für `complete_task` / `uncomplete_task`.
public enum CompletionScope: String, Sendable {
    case me = "self"
    case all
}

public enum TaskRules {
    /// Mögliche Aktionen; Reihenfolge = Wichtigkeit (die erste ist die Haupt-Aktion in der Liste).
    public static func actions(for task: TaskItem, userID: UUID) -> [TaskCompletionAction] {
        guard task.isOpen else { return [] }
        let mine = task.assignees.first { $0.userID == userID }
        let isCreator = task.createdBy == userID
        var actions: [TaskCompletionAction] = []

        switch task.completionMode {
        case .anyOne:
            if mine != nil {
                actions.append(.completeForMe)
            } else if isCreator {
                actions.append(.completeForAll)
            }
        case .each:
            if let mine {
                actions.append(mine.isDone ? .undoMine : .completeForMe)
            }
            if isCreator {
                actions.append(.completeForAll)
            }
        }
        return actions
    }

    /// Startseite: zuerst Aufgaben ohne Datum (neueste oben), dann datierte chronologisch.
    public static func homeOrder(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch (lhs.startsAt, rhs.startsAt) {
            case (nil, nil):
                return lhs.createdAt > rhs.createdAt
            case (nil, _):
                return true
            case (_, nil):
                return false
            case let (left?, right?):
                return left == right ? lhs.createdAt < rhs.createdAt : left < right
            }
        }
    }

    /// Überfällig: mit Uhrzeit 1 h nach Start (wie `staleDate` der Live Activity),
    /// nur mit Datum ab dem Folgetag in der Zeitzone der Aufgabe.
    public static func isOverdue(_ task: TaskItem, now: Date = .now) -> Bool {
        guard task.isOpen, let startDate = task.startDate else { return false }
        if let startTime = task.startTime {
            return now > startDate.date(at: startTime, in: task.timeZone).addingTimeInterval(3600)
        }
        return LocalDate(now, timeZone: task.timeZone) > startDate
    }

    /// Fortschritt bei „einzeln“, z. B. 1 von 3.
    public static func progress(_ task: TaskItem) -> (done: Int, total: Int) {
        (task.assignees.filter(\.isDone).count, task.assignees.count)
    }
}

/// Eintrag im Verlauf: erledigte oder gelöschte Aufgabe der letzten 30 Tage (Guide, Abschnitt 5).
public enum HistoryRules {
    public static let retentionDays = 30

    public enum Kind: Hashable, Sendable {
        case completed
        case deleted
    }

    /// Gelöscht hat Vorrang: Eine erledigte und danach gelöschte Aufgabe gilt als gelöscht.
    public static func kind(of task: TaskItem) -> Kind? {
        if task.deletedAt != nil { return .deleted }
        if task.completedAt != nil { return .completed }
        return nil
    }

    public static func date(of task: TaskItem) -> Date? {
        task.deletedAt ?? task.completedAt
    }

    /// Wer erledigt bzw. gelöscht hat (`completed_by` / `deleted_by`).
    public static func actor(of task: TaskItem) -> UUID? {
        task.deletedAt != nil ? task.deletedBy : task.completedBy
    }

    /// Ab wann der Eintrag frühestens endgültig entfernt wird (täglicher Bereinigungsjob).
    public static func expiry(of task: TaskItem) -> Date? {
        date(of: task).map { $0.addingTimeInterval(Double(retentionDays) * 24 * 3600) }
    }

    /// Verbleibende ganze Tage, mindestens 0.
    public static func daysRemaining(for task: TaskItem, now: Date = .now) -> Int? {
        guard let expiry = expiry(of: task) else { return nil }
        return max(0, Int((expiry.timeIntervalSince(now) / 86_400).rounded(.down)))
    }

    /// Neueste zuerst; nur Einträge innerhalb der Aufbewahrungsfrist.
    public static func entries(_ tasks: [TaskItem], now: Date = .now) -> [TaskItem] {
        tasks
            .filter { task in expiry(of: task).map { $0 > now } ?? false }
            .sorted { (date(of: $0) ?? .distantPast) > (date(of: $1) ?? .distantPast) }
    }
}
