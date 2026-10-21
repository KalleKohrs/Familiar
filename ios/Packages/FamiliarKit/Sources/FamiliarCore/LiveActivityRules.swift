import Foundation

/// Wann eine Live Activity laufen soll – dieselben Regeln wie `private.enqueue_due_notifications`
/// (Migration 0012), damit der Abgleich in der App und der Server übereinstimmen.
public enum LiveActivityRules {
    /// Vorlauf vor einer Startzeit mit Uhrzeit.
    public static let lead: TimeInterval = 5 * 60
    /// So lange nach dem Bezugspunkt startet eine fehlende Activity noch.
    public static let startWindow: TimeInterval = 60 * 60
    /// Nur-Datum: Bezugspunkt 08:00 Ortszeit der Aufgabe (E3).
    public static let dateOnlyHour = 8

    /// Bezugspunkt einer Aufgabe; `nil` ohne Datum (dort startet der Server bei der Zuweisung).
    public static func anchor(of task: TaskItem) -> Date? {
        guard let date = task.startDate else { return nil }
        if task.startTime != nil { return task.startsAt }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = task.timeZone
        return calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day,
                                                  hour: dateOnlyHour))
    }

    /// Ob die Person die Aufgabe noch offen hat (zugewiesen und nicht selbst erledigt).
    public static func isOpen(_ task: TaskItem, for userID: UUID) -> Bool {
        task.isOpen && task.assignees.contains { $0.userID == userID && !$0.isDone }
    }

    /// Soll jetzt eine Activity laufen, falls noch keine da ist?
    public static func shouldStart(_ task: TaskItem, userID: UUID, now: Date = .now) -> Bool {
        guard isOpen(task, for: userID), let anchor = anchor(of: task) else { return false }
        let from = anchor.addingTimeInterval(task.startTime != nil ? -lead : 0)
        return now >= from && now < anchor.addingTimeInterval(startWindow)
    }

    /// Abgleich beim Öffnen der App: fehlende Activities starten, veraltete beenden.
    /// - Parameters:
    ///   - openTasks: aktuell geladene offene Aufgaben.
    ///   - running: Aufgaben-IDs der laufenden Activities auf diesem Gerät.
    public static func reconcile(openTasks: [TaskItem], running: Set<UUID>, userID: UUID,
                                 now: Date = .now) -> (start: [TaskItem], end: Set<UUID>) {
        let stillOpen = Set(openTasks.filter { isOpen($0, for: userID) }.map(\.id))
        let start = openTasks.filter { !running.contains($0.id) && shouldStart($0, userID: userID, now: now) }
        return (start, running.subtracting(stillOpen))
    }
}
