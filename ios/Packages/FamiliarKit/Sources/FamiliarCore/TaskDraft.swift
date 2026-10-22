import Foundation

/// Neues, bereits verkleinertes Bild, das beim Speichern hochgeladen wird.
public struct PreparedImage: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let jpegData: Data
    public let thumbnailData: Data
    public let width: Int
    public let height: Int

    public init(id: UUID = UUID(), jpegData: Data, thumbnailData: Data, width: Int, height: Int) {
        self.id = id
        self.jpegData = jpegData
        self.thumbnailData = thumbnailData
        self.width = width
        self.height = height
    }
}

/// Bild im Editor: schon gespeichert oder neu.
public enum DraftImage: Hashable, Identifiable, Sendable {
    case existing(TaskImage)
    case new(PreparedImage)

    public var id: UUID {
        switch self {
        case .existing(let image): image.id
        case .new(let image): image.id
        }
    }
}

/// Bildangabe für `create_task`/`update_task` (`p_images`).
public struct TaskImageReference: Codable, Hashable, Sendable {
    public let id: UUID
    public let width: Int
    public let height: Int

    public init(id: UUID, width: Int, height: Int) {
        self.id = id
        self.width = width
        self.height = height
    }
}

/// Vollständiger Stand einer Aufgabe für `create_task` bzw. `update_task`.
public struct TaskInput: Hashable, Sendable {
    public var familyID: UUID
    public var title: String
    public var description: String?
    public var startDate: LocalDate?
    public var startTime: LocalTime?
    public var timezone: String
    public var completionMode: CompletionMode
    public var assigneeIDs: [UUID]
    public var images: [TaskImageReference]
    /// Wiederholungsregel (normalisiert); `nil` bei Einzelaufgaben. Dann ist `startDate` gesetzt.
    public var recurrence: RecurrenceRule?
    /// Nur bei Serien: alle gemeinsam oder reihum (Reihenfolge = `assigneeIDs`).
    public var assignmentMode: AssignmentMode
    public var rotationUnit: RotationUnit

    public init(
        familyID: UUID,
        title: String,
        description: String?,
        startDate: LocalDate?,
        startTime: LocalTime?,
        timezone: String,
        completionMode: CompletionMode,
        assigneeIDs: [UUID],
        images: [TaskImageReference],
        recurrence: RecurrenceRule? = nil,
        assignmentMode: AssignmentMode = .together,
        rotationUnit: RotationUnit = .occurrence
    ) {
        self.familyID = familyID
        self.title = title
        self.description = description
        self.startDate = startDate
        self.startTime = startTime
        self.timezone = timezone
        self.completionMode = completionMode
        self.assigneeIDs = assigneeIDs
        self.images = images
        self.recurrence = recurrence
        self.assignmentMode = assignmentMode
        self.rotationUnit = rotationUnit
    }
}

/// Zustand des Aufgaben-Editors. Regeln wie in `create_task`/`update_task` (Migration 0007).
public struct TaskDraft: Hashable, Sendable {
    public static let titleLength = 1...200
    public static let maxDescriptionLength = 4000
    public static let maxImages = 10

    public var familyID: UUID?
    public var title = ""
    public var description = ""
    public var hasDate = false
    public var date: LocalDate
    public var hasTime = false
    public var time: LocalTime
    public var timezone: String
    /// Muss beim Anlegen bewusst gewählt werden (Guide, Abschnitt 3) – daher kein Standardwert.
    public var completionMode: CompletionMode?
    public var assigneeIDs: [UUID] = []
    public var images: [DraftImage] = []
    /// `nil` = keine Wiederholung. Eine Wiederholung braucht ein Startdatum (erstes Vorkommen).
    public var recurrence: RecurrenceRule?
    /// Bei Serien: alle gemeinsam oder reihum in der Reihenfolge von `assigneeIDs`.
    public var assignmentMode: AssignmentMode = .together
    public var rotationUnit: RotationUnit = .occurrence

    public init(familyID: UUID?, now: Date = .now, timeZone: TimeZone = .current) {
        self.familyID = familyID
        timezone = timeZone.identifier
        date = LocalDate(now, timeZone: timeZone)
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        time = LocalTime(hour: LocalTime(nextHour, timeZone: timeZone).hour, minute: 0)
    }

    /// Editor-Stand einer bestehenden Aufgabe.
    public init(task: TaskItem, now: Date = .now) {
        self.init(familyID: task.familyID, now: now, timeZone: task.timeZone)
        title = task.title
        description = task.description ?? ""
        if let startDate = task.startDate {
            hasDate = true
            date = startDate
        }
        if let startTime = task.startTime {
            hasTime = true
            time = startTime
        }
        timezone = task.timezone
        completionMode = task.completionMode
        assigneeIDs = task.assignees.map(\.userID)
        images = task.images.map(DraftImage.existing)
        recurrence = task.series?.rule
        if let series = task.series, series.isRotating {
            assignmentMode = .rotate
            rotationUnit = series.rotationUnit
            // Reihenfolge so, dass oben steht, wer bei diesem Termin dran ist.
            let order = series.assigneeOrder.isEmpty ? assigneeIDs : series.assigneeOrder
            if let start = series.rotationStart ?? series.startDate, let date = task.occurrenceDate {
                assigneeIDs = RotationRules.rotated(
                    order, startingAt: RotationRules.index(rule: series.rule, unit: series.rotationUnit,
                                                           start: start, date: date))
            } else {
                assigneeIDs = order
            }
        }
    }

    /// Serie mit „Reihum“: pro Termin genau eine Person, Erledigungsart entfällt.
    public var isRotating: Bool { recurrence != nil && assignmentMode == .rotate }

    /// Wöchentlicher Wechsel nur, wenn es mehrere Termine pro Woche gibt (täglich oder mehrere Wochentage).
    public var offersWeeklyRotation: Bool {
        guard let rule = recurrence?.normalized else { return false }
        return rule.frequency == .daily || (rule.frequency == .weekly && rule.weekdays.count > 1)
    }

    public var effectiveRotationUnit: RotationUnit { offersWeeklyRotation ? rotationUnit : .occurrence }

    /// Mit Wiederholung ist das Datum immer gesetzt (erstes bzw. dieses Vorkommen).
    public var usesDate: Bool { hasDate || recurrence != nil }

    public enum Issue: Hashable, Sendable {
        case familyMissing
        case titleMissing
        case titleTooLong
        case descriptionTooLong
        case assigneesMissing
        case completionModeMissing
        case tooManyImages
        case recurrenceIncomplete
        case rotationNeedsTwo
    }

    public var issues: [Issue] {
        var issues: [Issue] = []
        let trimmedTitle = InputRules.trimmed(title)
        if familyID == nil { issues.append(.familyMissing) }
        if trimmedTitle.isEmpty { issues.append(.titleMissing) }
        if trimmedTitle.count > Self.titleLength.upperBound { issues.append(.titleTooLong) }
        if InputRules.trimmed(description).count > Self.maxDescriptionLength { issues.append(.descriptionTooLong) }
        if assigneeIDs.isEmpty { issues.append(.assigneesMissing) }
        if effectiveCompletionMode == nil { issues.append(.completionModeMissing) }
        if images.count > Self.maxImages { issues.append(.tooManyImages) }
        if let recurrence, !recurrence.isComplete { issues.append(.recurrenceIncomplete) }
        if isRotating && assigneeIDs.count < 2 { issues.append(.rotationNeedsTwo) }
        return issues
    }

    public var isValid: Bool { issues.isEmpty }

    /// Erst ab zwei Personen macht die Erledigungsart einen Unterschied – dann muss sie bewusst
    /// gewählt werden (Guide, Abschnitt 3). Bei einer Person gilt „Eine für alle“.
    /// Bei „Reihum“ ist pro Termin nur eine Person zugewiesen – keine Wahl nötig.
    public var needsCompletionModeChoice: Bool { assigneeIDs.count > 1 && !isRotating }

    public var effectiveCompletionMode: CompletionMode? {
        if isRotating { return .anyOne }
        return needsCompletionModeChoice ? completionMode : (completionMode ?? .anyOne)
    }

    /// Reihenfolge bei „Reihum“ ändern (oben = als Nächstes dran).
    public mutating func moveAssignee(_ userID: UUID, by offset: Int) {
        guard let index = assigneeIDs.firstIndex(of: userID) else { return }
        let target = index + offset
        guard assigneeIDs.indices.contains(target) else { return }
        assigneeIDs.swapAt(index, target)
    }

    public mutating func toggleAssignee(_ userID: UUID) {
        if let index = assigneeIDs.firstIndex(of: userID) {
            assigneeIDs.remove(at: index)
        } else {
            assigneeIDs.append(userID)
        }
    }

    /// Server-Eingabe; Bilder müssen vorher hochgeladen sein. `nil`, solange der Entwurf ungültig ist.
    public func input() -> TaskInput? {
        guard isValid, let familyID, let completionMode = effectiveCompletionMode else { return nil }
        let trimmedDescription = InputRules.trimmed(description)
        return TaskInput(
            familyID: familyID,
            title: InputRules.trimmed(title),
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            startDate: usesDate ? date : nil,
            startTime: usesDate && hasTime ? time : nil,
            timezone: timezone,
            completionMode: completionMode,
            assigneeIDs: assigneeIDs,
            images: images.map { image in
                switch image {
                case .existing(let image): TaskImageReference(id: image.id, width: image.width, height: image.height)
                case .new(let image): TaskImageReference(id: image.id, width: image.width, height: image.height)
                }
            },
            recurrence: recurrence?.normalized,
            assignmentMode: isRotating ? .rotate : .together,
            rotationUnit: effectiveRotationUnit
        )
    }
}
