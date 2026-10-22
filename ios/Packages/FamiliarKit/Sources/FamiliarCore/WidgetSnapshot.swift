import Foundation

/// Kleiner Schnappschuss für die Widgets „Heute“ (ADR 0010). Die App schreibt ihn in den gemeinsamen
/// App-Group-Container; das Widget liest nur – ohne Konto, ohne Netz. Enthält bewusst nur, was die
/// Widgets anzeigen: Titel, Zeit, Familie, Initialen, Abhak-Erlaubnis.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public var title: String
        public var familyID: UUID
        public var startDate: LocalDate?
        public var startTime: LocalTime?
        public var startsAt: Date?
        public var createdAt: Date
        public var isAssignedToMe: Bool
        /// Darf die Person auf diesem Gerät abhaken (wie in der Live Activity)?
        public var canComplete: Bool
        public var initials: [String]

        public init(id: UUID, title: String, familyID: UUID, startDate: LocalDate?, startTime: LocalTime?,
                    startsAt: Date?, createdAt: Date, isAssignedToMe: Bool, canComplete: Bool, initials: [String]) {
            self.id = id
            self.title = title
            self.familyID = familyID
            self.startDate = startDate
            self.startTime = startTime
            self.startsAt = startsAt
            self.createdAt = createdAt
            self.isAssignedToMe = isAssignedToMe
            self.canComplete = canComplete
            self.initials = initials
        }
    }

    public struct FamilyInfo: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public var name: String
        public var colorHex: String

        public init(id: UUID, name: String, colorHex: String) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
        }
    }

    public var generatedAt: Date
    public var items: [Item]
    public var families: [FamilyInfo]

    public init(generatedAt: Date = .now, items: [Item], families: [FamilyInfo]) {
        self.generatedAt = generatedAt
        self.items = items
        self.families = families
    }

    public func family(_ id: UUID) -> FamilyInfo? { families.first { $0.id == id } }

    /// Schnappschuss aus den offenen Aufgaben der App.
    public init(openTasks: [TaskItem], families: [FamilyMembership], userID: UUID, now: Date = .now) {
        let names = Dictionary(families.flatMap(\.members).map { ($0.userID, $0.profile?.displayName ?? "?") },
                               uniquingKeysWith: { first, _ in first })
        self.init(
            generatedAt: now,
            items: openTasks.filter(\.isOpen).map { task in
                Item(id: task.id, title: task.title, familyID: task.familyID, startDate: task.startDate,
                     startTime: task.startTime, startsAt: task.startsAt, createdAt: task.createdAt,
                     isAssignedToMe: task.assignees.contains { $0.userID == userID },
                     canComplete: LiveActivityRules.isOpen(task, for: userID),
                     initials: task.assignees
                        .map { names[$0.userID] ?? "?" }
                        .sorted()
                        .map { String($0.prefix(1)).uppercased() })
            },
            families: families.map { FamilyInfo(id: $0.family.id, name: $0.family.name, colorHex: $0.family.colorHex) }
        )
    }
}

/// Auswahl für die Widgets: was „heute“ ansteht – wie der Abschnitt „Heute“ der Startseite plus Überfälliges.
public enum WidgetRules {
    public struct Entry: Hashable, Sendable {
        public var item: WidgetSnapshot.Item
        public var isOverdue: Bool
    }

    /// Überfällige zuerst, dann Heute mit Uhrzeit nach Zeit, dann ohne Uhrzeit bzw. ohne Datum (neueste zuerst).
    public static func today(_ snapshot: WidgetSnapshot, now: Date = .now, timeZone: TimeZone = .current,
                             onlyMine: Bool, familyID: UUID? = nil) -> [Entry] {
        let today = LocalDate(now, timeZone: timeZone)
        let entries = snapshot.items.compactMap { item -> Entry? in
            if onlyMine && !item.isAssignedToMe { return nil }
            if let familyID, item.familyID != familyID { return nil }
            if let date = item.startDate, date > today { return nil }
            let overdue: Bool
            if let date = item.startDate, date < today {
                overdue = true
            } else if item.startTime != nil, let startsAt = item.startsAt {
                overdue = startsAt.addingTimeInterval(3600) < now
            } else {
                overdue = false
            }
            return Entry(item: item, isOverdue: overdue)
        }
        return entries.sorted { lhs, rhs in
            if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
            switch (lhs.item.startTime != nil ? lhs.item.startsAt : nil, rhs.item.startTime != nil ? rhs.item.startsAt : nil) {
            case let (l?, r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.item.createdAt > rhs.item.createdAt
            }
        }
    }

    /// Nächster Zeitpunkt, an dem sich die Auswahl ohne neue Daten ändert (Mitternacht oder „überfällig“).
    public static func nextRefresh(_ snapshot: WidgetSnapshot, now: Date = .now, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(3600)
        let overdueSoon = snapshot.items
            .compactMap { $0.startTime != nil ? $0.startsAt?.addingTimeInterval(3600) : nil }
            .filter { $0 > now }
            .min()
        return min(midnight, overdueSoon ?? midnight)
    }
}

/// Lesen und Schreiben des Schnappschusses im App-Group-Container (`FamiliarAppGroup` in der Info.plist).
public enum WidgetSnapshotStore {
    private static let fileName = "widget-today.json"

    public static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FamiliarAppGroup") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            return nil
        }
        return container.appending(path: fileName)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Schreibt nur bei Änderung; liefert, ob sich etwas geändert hat (dann Widgets neu laden).
    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        var comparable = snapshot
        if let current = read() {
            comparable.generatedAt = current.generatedAt
            if comparable == current { return false }
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Beim Abmelden: keine Aufgaben mehr auf Homescreen und Sperrbildschirm.
    public static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
