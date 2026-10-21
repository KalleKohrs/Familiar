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
            // „Für alle erledigt“ nur, wenn es etwas anderes bewirkt als der eigene Haken.
            if isCreator && !completesTask(task, userID: userID) {
                actions.append(.completeForAll)
            }
        }
        return actions
    }

    /// Erledigt der eigene Haken die ganze Aufgabe? (allein zugewiesen bzw. alle anderen fertig)
    public static func completesTask(_ task: TaskItem, userID: UUID) -> Bool {
        guard let mine = task.assignees.first(where: { $0.userID == userID }), !mine.isDone else { return false }
        return task.completionMode == .anyOne || task.assignees.allSatisfy { $0.userID == userID || $0.isDone }
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

    /// Abschnitte der Startseite in fester Reihenfolge. Aufgaben ohne Datum gehören zu „Heute“
    /// (dort zuerst, neueste oben), Überfälliges steht davor.
    public enum HomeSection: Int, CaseIterable, Hashable, Sendable {
        case overdue
        case today
        case tomorrow
        case later
    }

    /// Ordnet die Aufgaben (Reihenfolge wie `homeOrder`) den Abschnitten zu; leere Abschnitte entfallen.
    /// Der Tag zählt in der Zeitzone der Aufgabe.
    public static func homeSections(_ tasks: [TaskItem], now: Date = .now) -> [(section: HomeSection, tasks: [TaskItem])] {
        let grouped = Dictionary(grouping: homeOrder(tasks)) { task -> HomeSection in
            guard let startDate = task.startDate else { return .today }
            if isOverdue(task, now: now) { return .overdue }
            let today = LocalDate(now, timeZone: task.timeZone)
            if startDate <= today { return .today }
            if startDate == today.adding(days: 1) { return .tomorrow }
            return .later
        }
        return HomeSection.allCases.compactMap { section in
            grouped[section].map { (section, $0) }
        }
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

    /// Neueste zuerst; nur Einträge innerhalb der Aufbewahrungsfrist. Mit der Serie gelöschte
    /// Vorkommen erscheinen nicht einzeln (Guide, Abschnitt 4), sondern als ein Serien-Eintrag.
    public static func entries(_ tasks: [TaskItem], now: Date = .now) -> [TaskItem] {
        tasks
            .filter { task in task.deletedBySeriesOp == nil && (expiry(of: task).map { $0 > now } ?? false) }
            .sorted { (date(of: $0) ?? .distantPast) > (date(of: $1) ?? .distantPast) }
    }

    /// Aufgaben und Serien-Löschungen zusammen, neueste zuerst.
    public static func entries(_ tasks: [TaskItem], deletions: [SeriesDeletion], now: Date = .now) -> [HistoryEntry] {
        let retention = Double(retentionDays) * 86_400
        let taskEntries = entries(tasks, now: now).map(HistoryEntry.task)
        let deletionEntries = deletions
            .filter { $0.restoredAt == nil && $0.deletedAt.addingTimeInterval(retention) > now }
            .map(HistoryEntry.seriesDeletion)
        return (taskEntries + deletionEntries).sorted { $0.date > $1.date }
    }

    /// Verbleibende ganze Tage eines Verlaufseintrags, mindestens 0.
    public static func daysRemaining(for entry: HistoryEntry, now: Date = .now) -> Int {
        let expiry = entry.date.addingTimeInterval(Double(retentionDays) * 86_400)
        return max(0, Int((expiry.timeIntervalSince(now) / 86_400).rounded(.down)))
    }
}

/// Ein Eintrag im Verlauf: erledigte bzw. gelöschte Aufgabe oder gelöschte Serie.
public enum HistoryEntry: Hashable, Identifiable, Sendable {
    case task(TaskItem)
    case seriesDeletion(SeriesDeletion)

    public var id: UUID {
        switch self {
        case .task(let task): task.id
        case .seriesDeletion(let deletion): deletion.id
        }
    }

    public var date: Date {
        switch self {
        case .task(let task): HistoryRules.date(of: task) ?? .distantPast
        case .seriesDeletion(let deletion): deletion.deletedAt
        }
    }

    public var familyID: UUID {
        switch self {
        case .task(let task): task.familyID
        case .seriesDeletion(let deletion): deletion.familyID
        }
    }
}
