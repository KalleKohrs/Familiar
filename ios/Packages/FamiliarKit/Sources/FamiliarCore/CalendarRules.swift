import Foundation

/// Künftiges, noch nicht erzeugtes Vorkommen einer Serie (`project_series_occurrences`, Migration 0009).
public struct ProjectedOccurrence: Hashable, Identifiable, Sendable {
    public let seriesID: UUID
    public let familyID: UUID
    public let date: LocalDate
    public var startTime: LocalTime?
    public var timezone: String
    public var title: String
    public var rule: RecurrenceRule?

    public var id: String { "\(seriesID)-\(date)" }

    public init(seriesID: UUID, familyID: UUID, date: LocalDate, startTime: LocalTime?, timezone: String,
                title: String, rule: RecurrenceRule? = nil) {
        self.seriesID = seriesID
        self.familyID = familyID
        self.date = date
        self.startTime = startTime
        self.timezone = timezone
        self.title = title
        self.rule = rule
    }
}

/// Persönlicher Termin aus einem externen Kalender (ab Phase 8: Outlook), nur lesend.
/// Anbieter-unabhängig, damit weitere Kalender ohne Änderung der Ansicht folgen können.
public struct ExternalEvent: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var provider: String
    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var isAllDay: Bool

    public init(id: UUID, provider: String, title: String, startsAt: Date, endsAt: Date, isAllDay: Bool) {
        self.id = id
        self.provider = provider
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
    }
}

/// Ein Eintrag im Kalender.
public enum CalendarEntry: Hashable, Identifiable, Sendable {
    case task(TaskItem)
    case projected(ProjectedOccurrence)
    case external(ExternalEvent)

    public var id: String {
        switch self {
        case .task(let task): task.id.uuidString
        case .projected(let occurrence): occurrence.id
        case .external(let event): "external-\(event.id)"
        }
    }
}

public enum CalendarRules {
    /// Tage eines Monatsrasters: volle Wochen von Montag bis Sonntag, inklusive der angrenzenden
    /// Tage aus Vor- und Folgemonat.
    public static func monthGrid(year: Int, month: Int) -> [LocalDate] {
        let first = LocalDate(year: year, month: month, day: 1)
        let start = first.adding(days: -(first.isoWeekday - 1))
        let last = LocalDate(year: year, month: month, day: first.daysInMonth)
        let end = last.adding(days: 7 - last.isoWeekday)
        var days: [LocalDate] = []
        var day = start
        while day <= end {
            days.append(day)
            day = day.adding(days: 1)
        }
        return days
    }

    /// Erster Tag des Vor- (`-1`) bzw. Folgemonats (`+1`).
    public static func month(_ date: LocalDate, offset: Int) -> LocalDate {
        let index = date.year * 12 + (date.month - 1) + offset
        return LocalDate(year: index / 12, month: index % 12 + 1, day: 1)
    }

    /// Einträge nach Tag. Aufgaben ohne Datum und gelöschte Aufgaben erscheinen nicht.
    /// Pro Tag: ganztägig zuerst, dann nach Uhrzeit, bei Gleichstand nach Titel.
    public static func entriesByDay(
        tasks: [TaskItem],
        projected: [ProjectedOccurrence],
        external: [ExternalEvent] = [],
        timeZone: TimeZone = .current
    ) -> [LocalDate: [CalendarEntry]] {
        var result: [LocalDate: [CalendarEntry]] = [:]
        for task in tasks where task.deletedAt == nil {
            guard let date = task.startDate else { continue }
            result[date, default: []].append(.task(task))
        }
        // Projektionen nur, wenn das Vorkommen nicht schon als Aufgabe existiert.
        let existing = Set(tasks.compactMap { task in
            task.seriesID.flatMap { id in task.occurrenceDate.map { "\(id)-\($0)" } }
        })
        for occurrence in projected where !existing.contains(occurrence.id) {
            result[occurrence.date, default: []].append(.projected(occurrence))
        }
        for event in external {
            result[LocalDate(event.startsAt, timeZone: timeZone), default: []].append(.external(event))
        }
        return result.mapValues { entries in
            entries.sorted { lhs, rhs in
                let left = sortKey(lhs, timeZone: timeZone)
                let right = sortKey(rhs, timeZone: timeZone)
                return left.minutes == right.minutes ? left.title < right.title : left.minutes < right.minutes
            }
        }
    }

    private static func sortKey(_ entry: CalendarEntry, timeZone: TimeZone) -> (minutes: Int, title: String) {
        switch entry {
        case .task(let task):
            return (task.startTime.map { $0.hour * 60 + $0.minute } ?? -1, task.title)
        case .projected(let occurrence):
            return (occurrence.startTime.map { $0.hour * 60 + $0.minute } ?? -1, occurrence.title)
        case .external(let event):
            if event.isAllDay { return (-1, event.title) }
            let time = LocalTime(event.startsAt, timeZone: timeZone)
            return (time.hour * 60 + time.minute, event.title)
        }
    }
}
