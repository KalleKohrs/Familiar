import Foundation

/// Kalenderdatum ohne Uhrzeit und Zeitzone (Postgres `date`, z. B. `2026-10-21`).
public struct LocalDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Erwartet `yyyy-MM-dd`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Datum eines Zeitpunkts in der angegebenen Zeitzone.
    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Beginn dieses Tages in der Zeitzone.
    public func startOfDay(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = LocalDate(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiges Datum: \(string)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Uhrzeit ohne Datum und Zeitzone (Postgres `time`, z. B. `14:30:00`).
public struct LocalTime: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Erwartet `HH:mm` oder `HH:mm:ss` (Sekunden werden ignoriert).
    public init?(_ string: String) {
        let parts = string.split(separator: ":").prefix(2).compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        self.init(hour: parts[0], minute: parts[1])
    }

    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    public var description: String {
        String(format: "%02d:%02d:00", hour, minute)
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = LocalTime(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültige Uhrzeit: \(string)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension LocalDate {
    /// Zeitpunkt aus Datum und optionaler Uhrzeit in der Zeitzone (wie `tasks.starts_at`).
    public func date(at time: LocalTime?, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: time?.hour ?? 0, minute: time?.minute ?? 0)
        return calendar.date(from: components) ?? .distantPast
    }
}
