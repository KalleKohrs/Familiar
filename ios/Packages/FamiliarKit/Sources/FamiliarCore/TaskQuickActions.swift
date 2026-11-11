import Foundation

/// Wie weit eine Aufgabe mit einem Tipp verschoben wird („Einen Tag später“, „Eine Woche später“).
public enum TaskPostponement: Hashable, Sendable, CaseIterable {
    case oneDay
    case oneWeek

    public var days: Int {
        switch self {
        case .oneDay: 1
        case .oneWeek: 7
        }
    }
}

extension TaskRules {
    /// Verschieben geht bei offenen Aufgaben mit Datum. Ohne Datum gibt es nichts zu verschieben.
    public static func canPostpone(_ task: TaskItem) -> Bool {
        task.isOpen && task.startDate != nil
    }

    /// Neues Datum: ab dem späteren von Aufgabendatum und heute (in der Zeitzone der Aufgabe).
    /// So rückt eine überfällige Aufgabe nie wieder in die Vergangenheit, und eine Aufgabe in der
    /// Zukunft wird nie früher. Die Uhrzeit bleibt, wie sie ist.
    public static func postponedDate(for task: TaskItem, by postponement: TaskPostponement, now: Date = .now) -> LocalDate? {
        guard canPostpone(task), let startDate = task.startDate else { return nil }
        let today = LocalDate(now, timeZone: task.timeZone)
        return max(startDate, today).adding(days: postponement.days)
    }
}

extension TaskDraft {
    /// Neue, einzelne Aufgabe nach dem Vorbild einer bestehenden („Duplizieren“).
    ///
    /// Übernommen werden Familie, Titel, Beschreibung, Personen und Erledigungsart. Das Datum bleibt, solange es
    /// nicht in der Vergangenheit liegt (sonst heute); die Uhrzeit bleibt. Nicht übernommen werden Bilder
    /// (jede Aufgabe hat ihre eigenen Dateien) und Wiederholung bzw. Reihum – die Kopie ist eine einmalige Aufgabe.
    public init(duplicating task: TaskItem, now: Date = .now) {
        self.init(familyID: task.familyID, now: now, timeZone: task.timeZone)
        title = task.title
        description = task.description ?? ""
        if let startDate = task.startDate {
            hasDate = true
            date = max(startDate, LocalDate(now, timeZone: task.timeZone))
        }
        if let startTime = task.startTime {
            hasTime = true
            time = startTime
        }
        completionMode = task.completionMode
        assigneeIDs = task.assignees.map(\.userID)
    }
}
