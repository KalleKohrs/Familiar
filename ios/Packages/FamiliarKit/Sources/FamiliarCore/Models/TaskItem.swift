import Foundation

/// Wer eine Aufgabe komplett erledigt hat. Rohwerte wie das Datenbank-Enum `completion_source`.
public enum CompletionSource: String, Codable, Hashable, Sendable {
    case assignee
    case creator
}

/// Zugewiesene Person mit eigenem Erledigungsstatus (`public.task_assignees`).
public struct TaskAssignee: Codable, Hashable, Identifiable, Sendable {
    public let userID: UUID
    public var completedAt: Date?

    public var id: UUID { userID }
    public var isDone: Bool { completedAt != nil }

    public init(userID: UUID, completedAt: Date? = nil) {
        self.userID = userID
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case completedAt = "completed_at"
    }
}

/// Angehängtes Bild (`public.images`) mit Pfaden im Bucket `task-images`.
public struct TaskImage: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let thumbPath: String
    public let width: Int
    public let height: Int

    public init(id: UUID, path: String, thumbPath: String, width: Int, height: Int) {
        self.id = id
        self.path = path
        self.thumbPath = thumbPath
        self.width = width
        self.height = height
    }

    enum CodingKeys: String, CodingKey {
        case id, path, width, height
        case thumbPath = "thumb_path"
    }

    public var aspectRatio: Double { Double(width) / Double(max(height, 1)) }
}

/// Aufgabe (`public.tasks`) mit Zuweisungen und Bildern in Anzeige-Reihenfolge.
public struct TaskItem: Decodable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let familyID: UUID
    public var createdBy: UUID?
    public var title: String
    public var description: String?
    public var startDate: LocalDate?
    public var startTime: LocalTime?
    /// IANA-Zeitzone der Aufgabe, z. B. `Europe/Berlin`.
    public var timezone: String
    /// Startzeitpunkt (nur Datum = Tagesbeginn in `timezone`), vom Server berechnet.
    public var startsAt: Date?
    public var completionMode: CompletionMode
    public var completedAt: Date?
    public var completedBy: UUID?
    public var completionSource: CompletionSource?
    public var deletedAt: Date?
    public var deletedBy: UUID?
    public var version: Int
    public var createdAt: Date
    public var assignees: [TaskAssignee]
    public var images: [TaskImage]
    /// Serie, zu der dieses Vorkommen gehört (`nil` bei Einzelaufgaben).
    public var seriesID: UUID?
    /// Ursprünglicher Termin des Vorkommens in der Serie (bleibt beim Verschieben gleich).
    public var occurrenceDate: LocalDate?
    /// Mit „Nur dieses Vorkommen“ geändert; spätere Serienänderungen lassen es in Ruhe.
    public var isDetached: Bool
    /// Mit der ganzen Serie gelöscht – erscheint nicht einzeln im Verlauf.
    public var deletedBySeriesOp: UUID?
    /// Eingebettete Serie (Regel), sofern sichtbar.
    public var series: TaskSeries?
    /// Private Aufgabe: nur der Ersteller sieht sie (ADR 0012). Nur dem Ersteller zugewiesen.
    public var isPrivate: Bool

    public init(
        id: UUID,
        familyID: UUID,
        createdBy: UUID?,
        title: String,
        description: String? = nil,
        startDate: LocalDate? = nil,
        startTime: LocalTime? = nil,
        timezone: String = "Europe/Berlin",
        startsAt: Date? = nil,
        completionMode: CompletionMode,
        completedAt: Date? = nil,
        completedBy: UUID? = nil,
        completionSource: CompletionSource? = nil,
        deletedAt: Date? = nil,
        deletedBy: UUID? = nil,
        version: Int = 1,
        createdAt: Date = .now,
        assignees: [TaskAssignee],
        images: [TaskImage] = [],
        seriesID: UUID? = nil,
        occurrenceDate: LocalDate? = nil,
        isDetached: Bool = false,
        deletedBySeriesOp: UUID? = nil,
        series: TaskSeries? = nil,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.familyID = familyID
        self.createdBy = createdBy
        self.title = title
        self.description = description
        self.startDate = startDate
        self.startTime = startTime
        self.timezone = timezone
        self.startsAt = startsAt
        self.completionMode = completionMode
        self.completedAt = completedAt
        self.completedBy = completedBy
        self.completionSource = completionSource
        self.deletedAt = deletedAt
        self.deletedBy = deletedBy
        self.version = version
        self.createdAt = createdAt
        self.assignees = assignees
        self.images = images
        self.seriesID = seriesID
        self.occurrenceDate = occurrenceDate
        self.isDetached = isDetached
        self.deletedBySeriesOp = deletedBySeriesOp
        self.series = series
        self.isPrivate = isPrivate
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, timezone, version
        case familyID = "family_id"
        case createdBy = "created_by"
        case startDate = "start_date"
        case startTime = "start_time"
        case startsAt = "starts_at"
        case completionMode = "completion_mode"
        case completedAt = "completed_at"
        case completedBy = "completed_by"
        case completionSource = "completion_source"
        case deletedAt = "deleted_at"
        case deletedBy = "deleted_by"
        case createdAt = "created_at"
        case assignees = "task_assignees"
        case imageLinks = "task_image_links"
        case seriesID = "series_id"
        case occurrenceDate = "occurrence_date"
        case isDetached = "is_detached"
        case deletedBySeriesOp = "deleted_by_series_op"
        case series = "task_series"
        case isPrivate = "is_private"
    }

    /// Eingebettete Verknüpfung `task_image_links(position, images(*))`.
    private struct ImageLink: Decodable {
        let position: Int
        let images: TaskImage?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        familyID = try container.decode(UUID.self, forKey: .familyID)
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        startDate = try container.decodeIfPresent(LocalDate.self, forKey: .startDate)
        startTime = try container.decodeIfPresent(LocalTime.self, forKey: .startTime)
        timezone = try container.decode(String.self, forKey: .timezone)
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        completionMode = try container.decode(CompletionMode.self, forKey: .completionMode)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedBy = try container.decodeIfPresent(UUID.self, forKey: .completedBy)
        completionSource = try container.decodeIfPresent(CompletionSource.self, forKey: .completionSource)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        deletedBy = try container.decodeIfPresent(UUID.self, forKey: .deletedBy)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        assignees = try container.decodeIfPresent([TaskAssignee].self, forKey: .assignees) ?? []
        images = (try container.decodeIfPresent([ImageLink].self, forKey: .imageLinks) ?? [])
            .sorted { $0.position < $1.position }
            .compactMap(\.images)
        seriesID = try container.decodeIfPresent(UUID.self, forKey: .seriesID)
        occurrenceDate = try container.decodeIfPresent(LocalDate.self, forKey: .occurrenceDate)
        isDetached = try container.decodeIfPresent(Bool.self, forKey: .isDetached) ?? false
        deletedBySeriesOp = try container.decodeIfPresent(UUID.self, forKey: .deletedBySeriesOp)
        series = try container.decodeIfPresent(TaskSeries.self, forKey: .series)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
    }

    public var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }
    public var hasStart: Bool { startDate != nil }
    public var isOpen: Bool { completedAt == nil && deletedAt == nil }
    public var isOccurrence: Bool { seriesID != nil }
}
