import Foundation

/// Rohwerte wie das Datenbank-Enum `recurrence_freq`.
public enum RecurrenceFrequency: String, Codable, Hashable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
}

/// Wiederholungsregel einer Serie (Guide, Abschnitt 4).
/// Wochentage nach ISO (1 = Montag … 7 = Sonntag), Monatstage 1–31.
/// Fehlt ein Monatstag im Monat, gilt der letzte Tag des Monats (Entscheidung E2);
/// gleiche Algorithmen wie `private.series_dates` (Migration 0009).
public struct RecurrenceRule: Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    public var weekdays: [Int]
    public var monthDays: [Int]

    public init(frequency: RecurrenceFrequency, weekdays: [Int] = [], monthDays: [Int] = []) {
        self.frequency = frequency
        self.weekdays = weekdays
        self.monthDays = monthDays
    }

    public static let daily = RecurrenceRule(frequency: .daily)

    public static func weekly(_ weekdays: [Int]) -> RecurrenceRule {
        RecurrenceRule(frequency: .weekly, weekdays: weekdays)
    }

    public static func monthly(_ monthDays: [Int]) -> RecurrenceRule {
        RecurrenceRule(frequency: .monthly, monthDays: monthDays)
    }

    /// Sortiert, ohne Doppelte; nur die zur Häufigkeit passende Liste bleibt.
    public var normalized: RecurrenceRule {
        switch frequency {
        case .daily: .daily
        case .weekly: .weekly(Array(Set(weekdays.filter { (1...7).contains($0) })).sorted())
        case .monthly: .monthly(Array(Set(monthDays.filter { (1...31).contains($0) })).sorted())
        }
    }

    /// Wochen- bzw. Monatsregeln brauchen mindestens einen gültigen Tag.
    public var isComplete: Bool {
        switch frequency {
        case .daily: true
        case .weekly: !normalized.weekdays.isEmpty
        case .monthly: !normalized.monthDays.isEmpty
        }
    }

    public func matches(_ date: LocalDate) -> Bool {
        switch frequency {
        case .daily:
            return true
        case .weekly:
            return weekdays.contains(date.isoWeekday)
        case .monthly:
            let lastDay = date.daysInMonth
            return monthDays.contains { min($0, lastDay) == date.day }
        }
    }

    /// Alle passenden Tage in `from...to`, aufsteigend.
    public func dates(from: LocalDate, through to: LocalDate) -> [LocalDate] {
        var result: [LocalDate] = []
        var day = from
        while day <= to {
            if matches(day) { result.append(day) }
            day = day.adding(days: 1)
        }
        return result
    }

    /// Erster passender Tag ab `from` (einschließlich), höchstens 62 Tage weit wie auf dem Server.
    public func firstDate(onOrAfter from: LocalDate) -> LocalDate? {
        dates(from: from, through: from.adding(days: 62)).first
    }
}

extension LocalDate {
    private static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private var noonUTC: Date {
        Self.gregorianUTC.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    /// ISO-Wochentag: 1 = Montag … 7 = Sonntag.
    public var isoWeekday: Int {
        let weekday = Self.gregorianUTC.component(.weekday, from: noonUTC) // 1 = Sonntag
        return weekday == 1 ? 7 : weekday - 1
    }

    public var daysInMonth: Int {
        Self.gregorianUTC.range(of: .day, in: .month, for: noonUTC)?.count ?? 31
    }

    public func adding(days: Int) -> LocalDate {
        let date = Self.gregorianUTC.date(byAdding: .day, value: days, to: noonUTC) ?? noonUTC
        return LocalDate(date, timeZone: Self.gregorianUTC.timeZone)
    }

    /// Ganze Tage von `self` bis `other` (positiv, wenn `other` später liegt).
    public func days(until other: LocalDate) -> Int {
        Self.gregorianUTC.dateComponents([.day], from: noonUTC, to: other.noonUTC).day ?? 0
    }
}

/// Serie (`public.task_series`) – so viel, wie die App für Anzeige und Editor braucht.
public struct TaskSeries: Decodable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var familyID: UUID?
    public var title: String?
    public var rule: RecurrenceRule
    public var startDate: LocalDate?
    public var deletedAt: Date?

    public init(id: UUID, familyID: UUID? = nil, title: String? = nil, rule: RecurrenceRule,
                startDate: LocalDate? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.familyID = familyID
        self.title = title
        self.rule = rule
        self.startDate = startDate
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, freq, weekdays
        case familyID = "family_id"
        case monthDays = "month_days"
        case startDate = "start_date"
        case deletedAt = "deleted_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        familyID = try container.decodeIfPresent(UUID.self, forKey: .familyID)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        rule = RecurrenceRule(
            frequency: try container.decode(RecurrenceFrequency.self, forKey: .freq),
            weekdays: try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? [],
            monthDays: try container.decodeIfPresent([Int].self, forKey: .monthDays) ?? []
        )
        startDate = try container.decodeIfPresent(LocalDate.self, forKey: .startDate)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

/// Verlaufseintrag „Serie gelöscht“ (`public.series_deletions` mit eingebetteter Serie).
public struct SeriesDeletion: Decodable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let seriesID: UUID
    public let familyID: UUID
    public var deletedBy: UUID?
    public var deletedAt: Date
    public var restoredAt: Date?
    public var series: TaskSeries?

    public init(id: UUID, seriesID: UUID, familyID: UUID, deletedBy: UUID?, deletedAt: Date,
                restoredAt: Date? = nil, series: TaskSeries? = nil) {
        self.id = id
        self.seriesID = seriesID
        self.familyID = familyID
        self.deletedBy = deletedBy
        self.deletedAt = deletedAt
        self.restoredAt = restoredAt
        self.series = series
    }

    enum CodingKeys: String, CodingKey {
        case id
        case seriesID = "series_id"
        case familyID = "family_id"
        case deletedBy = "deleted_by"
        case deletedAt = "deleted_at"
        case restoredAt = "restored_at"
        case series = "task_series"
    }
}
