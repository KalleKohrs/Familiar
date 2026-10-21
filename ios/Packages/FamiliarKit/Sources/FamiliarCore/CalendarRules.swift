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

/// Persönlicher Termin aus einem externen Kalender (`public.external_events`, Migration 0011), nur lesend.
/// Anbieter-unabhängig, damit weitere Kalender ohne Änderung der Ansicht folgen können.
public struct ExternalEvent: Decodable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var calendarID: UUID?
    public var provider: String
    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var isAllDay: Bool
    /// Ganztägig: Kalendertage ohne Zeitzone; `endDate` ist exklusiv.
    public var startDate: LocalDate?
    public var endDate: LocalDate?
    public var location: String?
    public var organizerName: String?
    public var isCancelled: Bool

    public init(id: UUID, calendarID: UUID? = nil, provider: String, title: String, startsAt: Date, endsAt: Date,
                isAllDay: Bool, startDate: LocalDate? = nil, endDate: LocalDate? = nil, location: String? = nil,
                organizerName: String? = nil, isCancelled: Bool = false) {
        self.id = id
        self.calendarID = calendarID
        self.provider = provider
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.organizerName = organizerName
        self.isCancelled = isCancelled
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, title
        case calendarID = "calendar_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case isAllDay = "is_all_day"
        case startDate = "start_date"
        case endDate = "end_date"
        case location = "location_name"
        case organizerName = "organizer_name"
        case isCancelled = "is_cancelled"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        calendarID = try c.decodeIfPresent(UUID.self, forKey: .calendarID)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "outlook"
        title = try c.decode(String.self, forKey: .title)
        startsAt = try c.decode(Date.self, forKey: .startsAt)
        endsAt = try c.decode(Date.self, forKey: .endsAt)
        isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        startDate = try c.decodeIfPresent(LocalDate.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(LocalDate.self, forKey: .endDate)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        organizerName = try c.decodeIfPresent(String.self, forKey: .organizerName)
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
    }

    /// Anzeigename des Anbieters.
    public var providerName: String { provider == "outlook" ? "Outlook" : provider.capitalized }

    /// Tage, an denen der Termin erscheint: ganztägig über alle Tage, sonst am Starttag.
    public func days(in timeZone: TimeZone) -> [LocalDate] {
        if isAllDay, let startDate {
            let last = endDate.map { $0.adding(days: -1) } ?? startDate
            return startDate <= last ? RecurrenceRule.daily.dates(from: startDate, through: last) : [startDate]
        }
        return [LocalDate(startsAt, timeZone: timeZone)]
    }
}

public enum CalendarConnectionStatus: String, Decodable, Hashable, Sendable {
    case active
    case needsReauth = "needs_reauth"
    case error
}

/// Eigener Kalender bei einem Anbieter (`public.external_calendars`).
public struct ExternalCalendar: Decodable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var color: String?
    public var isDefault: Bool
    public var isSelected: Bool

    public init(id: UUID, name: String, color: String? = nil, isDefault: Bool = false, isSelected: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.isDefault = isDefault
        self.isSelected = isSelected
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case isDefault = "is_default"
        case isSelected = "is_selected"
    }
}

/// Verbindung zu einem Kalender-Konto (`public.calendar_connections` mit eingebetteten Kalendern).
public struct CalendarConnection: Decodable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var provider: String
    public var accountEmail: String?
    public var status: CalendarConnectionStatus
    public var lastSyncAt: Date?
    public var lastError: String?
    public var calendars: [ExternalCalendar]

    public init(id: UUID, provider: String = "outlook", accountEmail: String?, status: CalendarConnectionStatus,
                lastSyncAt: Date? = nil, lastError: String? = nil, calendars: [ExternalCalendar] = []) {
        self.id = id
        self.provider = provider
        self.accountEmail = accountEmail
        self.status = status
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
        self.calendars = calendars
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, status
        case accountEmail = "account_email"
        case lastSyncAt = "last_sync_at"
        case lastError = "last_error"
        case calendars = "external_calendars"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "outlook"
        accountEmail = try c.decodeIfPresent(String.self, forKey: .accountEmail)
        status = try c.decode(CalendarConnectionStatus.self, forKey: .status)
        lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        calendars = (try c.decodeIfPresent([ExternalCalendar].self, forKey: .calendars) ?? [])
            .sorted { $0.isDefault != $1.isDefault ? $0.isDefault : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        for event in external where !event.isCancelled {
            for day in event.days(in: timeZone) {
                result[day, default: []].append(.external(event))
            }
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
