import FamiliarCore
import Foundation
import Supabase

final class SupabaseTaskRepository: TaskRepository {
    private let client: SupabaseClient
    private static let bucket = "task-images"
    private static let select =
        "*, task_assignees(user_id, completed_at), task_image_links(position, images(id, path, thumb_path, width, height)), "
        + "task_series(id, family_id, title, freq, weekdays, month_days, start_date, deleted_at, assignment_mode, rotation_unit, rotation_start, series_assignees(user_id, position))"

    init(client: SupabaseClient) {
        self.client = client
    }

    func openTasks() async throws(FamiliarError) -> [TaskItem] {
        try await perform {
            try await client.from("tasks")
                .select(Self.select)
                .is("deleted_at", value: nil)
                .is("completed_at", value: nil)
                .execute()
                .value
        }
    }

    func task(id: UUID) async throws(FamiliarError) -> TaskItem {
        let rows: [TaskItem] = try await perform {
            try await client.from("tasks").select(Self.select).eq("id", value: id).execute().value
        }
        guard let task = rows.first else {
            throw .app(key: .taskNotFound, message: String(localized: "Aufgabe nicht gefunden oder für dich nicht sichtbar."))
        }
        return task
    }

    func historyTasks() async throws(FamiliarError) -> [TaskItem] {
        let since = Date.now.addingTimeInterval(-Double(HistoryRules.retentionDays) * 86_400)
        let iso = since.formatted(.iso8601)
        let rows: [TaskItem] = try await perform {
            try await client.from("tasks")
                .select(Self.select)
                .or("completed_at.gte.\(iso),deleted_at.gte.\(iso)")
                .is("deleted_by_series_op", value: nil)
                .execute()
                .value
        }
        return HistoryRules.entries(rows)
    }

    func upload(_ image: PreparedImage, familyID: UUID) async throws(FamiliarError) {
        let folder = familyID.uuidString.lowercased()
        let name = image.id.uuidString.lowercased()
        let storage = client.storage.from(Self.bucket)
        let options = FileOptions(contentType: "image/jpeg")
        // Bild und Miniatur gleichzeitig (die Miniatur ist winzig, das Warten auf sie kostete nur Zeit).
        async let full = attemptUpload("\(folder)/\(name).jpg", data: image.jpegData, to: storage, options: options)
        async let thumbnail = attemptUpload("\(folder)/\(name)_thumb.jpg", data: image.thumbnailData, to: storage, options: options)
        let (fullResult, thumbnailResult) = await (full, thumbnail)
        try fullResult.get()
        try thumbnailResult.get()
    }

    private func attemptUpload(_ path: String, data: Data, to storage: StorageFileApi,
                               options: FileOptions) async -> Result<Void, FamiliarError> {
        do throws(FamiliarError) {
            try await uploadOnce(path, data: data, to: storage, options: options)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Lädt eine Datei hoch; „gibt es schon“ (409) zählt als Erfolg. Das Speichern einer Aufgabe lädt bei jedem Versuch
    /// alle neuen Bilder hoch – nach einem Fehler mitten in der Reihe (z. B. Server kurz überlastet) liegen die ersten
    /// schon dort, und ein zweiter Versuch würde sonst an genau diesen scheitern.
    private func uploadOnce(_ path: String, data: Data, to storage: StorageFileApi, options: FileOptions) async throws(FamiliarError) {
        do {
            _ = try await storage.upload(path, data: data, options: options)
        } catch let error as StorageError where error.statusCode == "409" || error.error == "Duplicate" {
            return
        } catch {
            throw FamiliarError(supabaseError: error)
        }
    }

    func createTask(_ input: TaskInput) async throws(FamiliarError) -> TaskItem {
        let row: TaskRowID = try await perform {
            try await client.rpc("create_task", params: TaskParams(input: input)).execute().value
        }
        return try await task(id: row.id)
    }

    func updateTask(id: UUID, expectedVersion: Int, _ input: TaskInput) async throws(FamiliarError) -> TaskItem {
        let params = TaskParams(input: input, taskID: id, expectedVersion: expectedVersion)
        let row: TaskRowID = try await perform {
            try await client.rpc("update_task", params: params).execute().value
        }
        return try await task(id: row.id)
    }

    func complete(taskID: UUID, scope: CompletionScope) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("complete_task", params: ["p_task_id": taskID.uuidString, "p_scope": scope.rawValue]).execute()
        }
    }

    func uncomplete(taskID: UUID, scope: CompletionScope) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("uncomplete_task", params: ["p_task_id": taskID.uuidString, "p_scope": scope.rawValue]).execute()
        }
    }

    func delete(taskID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("delete_task", params: ["p_task_id": taskID.uuidString]).execute()
        }
    }

    func restore(taskID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("restore_task", params: ["p_task_id": taskID.uuidString]).execute()
        }
    }

    func createSeries(_ input: TaskInput) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("create_recurring_task", params: TaskParams(input: input)).execute()
        }
    }

    func updateSeries(fromTaskID taskID: UUID, expectedVersion: Int, _ input: TaskInput) async throws(FamiliarError) -> TaskItem {
        let params = TaskParams(input: input, taskID: taskID, expectedVersion: expectedVersion)
        let row: TaskRowID = try await perform {
            try await client.rpc("update_series_from", params: params).execute().value
        }
        return try await task(id: row.id)
    }

    func deleteSeries(fromTaskID taskID: UUID) async throws(FamiliarError) -> UUID {
        let row: TaskRowID = try await perform {
            try await client.rpc("delete_series", params: ["p_task_id": taskID.uuidString]).execute().value
        }
        return row.id
    }

    func restoreSeries(deletionID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("restore_series_deletion", params: ["p_deletion_id": deletionID.uuidString]).execute()
        }
    }

    func clearHistory() async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("clear_history").execute()
        }
    }

    func purge(taskID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("purge_history_entry",
                                 params: ["p_kind": "task", "p_id": taskID.uuidString]).execute()
        }
    }

    func purgeSeriesDeletion(deletionID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("purge_history_entry",
                                 params: ["p_kind": "series", "p_id": deletionID.uuidString]).execute()
        }
    }

    func seriesDeletions() async throws(FamiliarError) -> [SeriesDeletion] {
        let since = Date.now.addingTimeInterval(-Double(HistoryRules.retentionDays) * 86_400)
        return try await perform {
            try await client.from("series_deletions")
                .select("*, task_series(id, family_id, title, freq, weekdays, month_days, start_date, deleted_at, assignment_mode, rotation_unit, rotation_start, series_assignees(user_id, position))")
                .is("restored_at", value: nil)
                .gte("deleted_at", value: since.formatted(.iso8601))
                .execute()
                .value
        }
    }

    func calendarTasks(from: LocalDate, through: LocalDate) async throws(FamiliarError) -> [TaskItem] {
        try await perform {
            try await client.from("tasks")
                .select(Self.select)
                .is("deleted_at", value: nil)
                .gte("start_date", value: from.description)
                .lte("start_date", value: through.description)
                .execute()
                .value
        }
    }

    func projectedOccurrences(from: LocalDate, through: LocalDate) async throws(FamiliarError) -> [ProjectedOccurrence] {
        let rows: [ProjectionRow] = try await perform {
            try await client.rpc("project_series_occurrences",
                                 params: ["p_from": from.description, "p_to": through.description])
                .execute()
                .value
        }
        let ids = Array(Set(rows.map(\.seriesID)))
        guard !ids.isEmpty else { return [] }
        let series: [TaskSeries] = try await perform {
            try await client.from("task_series")
                .select("id, family_id, title, freq, weekdays, month_days, start_date, deleted_at, assignment_mode, rotation_unit, rotation_start, series_assignees(user_id, position)")
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
        }
        let byID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        // series_assignees enthält nur aktuelle Mitglieder (Austritt räumt auf, Migration 0018) –
        // die Reihenfolge entspricht also schon der Reihe, die der Server verteilt.
        return rows.compactMap { row in
            guard let info = byID[row.seriesID] else { return nil }
            return ProjectedOccurrence(seriesID: row.seriesID, familyID: row.familyID, date: row.occurrenceDate,
                                       startTime: row.startTime, timezone: row.timezone,
                                       title: info.title ?? "", rule: info.rule,
                                       rotationPerson: info.rotationPerson(on: row.occurrenceDate))
        }
    }

    func imageURL(path: String) async throws(FamiliarError) -> URL {
        try await perform {
            try await client.storage.from(Self.bucket).createSignedURL(path: path, expiresIn: 60 * 60)
        }
    }

    func changes(for userID: UUID) -> AsyncStream<UUID> {
        // Privater Kanal user:<uid>; die Policy „realtime_receive_own_user_channel“ lässt nur den eigenen zu.
        let channel = client.channel("user:\(userID.uuidString.lowercased())") { $0.isPrivate = true }
        let messages = channel.broadcastStream(event: "task_changed")
        let client = client
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                } catch {
                    // Ohne Realtime bleibt Neuladen beim Öffnen und per Pull-to-Refresh.
                    continuation.finish()
                    return
                }
                for await message in messages {
                    if let id = Self.changedID(in: message) {
                        continuation.yield(id)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    func nudge(taskID: UUID, userID: UUID) async throws(FamiliarError) -> NudgeResult {
        try await perform {
            try await client.rpc("nudge_task", params: ["p_task_id": taskID.uuidString, "p_user_id": userID.uuidString])
                .execute()
                .value
        }
    }

    /// `task_id` bzw. `series_id` aus der Broadcast-Nachricht (`{"payload": {"task_id": …}}`).
    static func changedID(in message: JSONObject) -> UUID? {
        let payload = message["payload"]?.objectValue ?? message
        let id = payload["task_id"]?.stringValue ?? payload["series_id"]?.stringValue
        return id.flatMap(UUID.init(uuidString:))
    }
}

/// Zeile aus `project_series_occurrences`.
struct ProjectionRow: Decodable {
    let seriesID: UUID
    let familyID: UUID
    let occurrenceDate: LocalDate
    let startTime: LocalTime?
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case timezone
        case seriesID = "series_id"
        case familyID = "family_id"
        case occurrenceDate = "occurrence_date"
        case startTime = "start_time"
    }
}

/// Rückgabe der RPCs (komplette Zeile); gebraucht wird nur die ID zum Neuladen mit Einbettungen.
private struct TaskRowID: Decodable {
    let id: UUID
}

/// Parameter von `create_task`/`update_task` und – mit Wiederholung – `create_recurring_task`/
/// `update_series_from`; `nil` wird nicht gesendet (Standardwert der RPC).
struct TaskParams: Encodable {
    let taskID: UUID?
    let expectedVersion: Int?
    let familyID: UUID?
    let title: String
    let completionMode: CompletionMode
    let assigneeIDs: [UUID]
    let description: String?
    let startDate: LocalDate?
    let startTime: LocalTime?
    let timezone: String
    let images: [TaskImageReference]
    let recurrence: RecurrenceRule?
    let assignmentMode: AssignmentMode
    let rotationUnit: RotationUnit
    /// Nur beim Anlegen privater Aufgaben gesendet (ältere Server ohne Migration 0021 kennen den Parameter nicht).
    let isPrivate: Bool

    init(input: TaskInput, taskID: UUID? = nil, expectedVersion: Int? = nil) {
        self.taskID = taskID
        self.expectedVersion = expectedVersion
        familyID = taskID == nil ? input.familyID : nil
        title = input.title
        completionMode = input.completionMode
        assigneeIDs = input.assigneeIDs
        description = input.description
        startDate = input.startDate
        startTime = input.startTime
        timezone = input.timezone
        images = input.images
        recurrence = input.recurrence
        assignmentMode = input.assignmentMode
        rotationUnit = input.rotationUnit
        isPrivate = taskID == nil && input.isPrivate
    }

    enum CodingKeys: String, CodingKey {
        case taskID = "p_task_id"
        case expectedVersion = "p_expected_version"
        case familyID = "p_family_id"
        case title = "p_title"
        case completionMode = "p_completion_mode"
        case assigneeIDs = "p_assignee_ids"
        case description = "p_description"
        case startDate = "p_start_date"
        case startTime = "p_start_time"
        case timezone = "p_timezone"
        case images = "p_images"
        case freq = "p_freq"
        case weekdays = "p_weekdays"
        case monthDays = "p_month_days"
        case assignmentMode = "p_assignment_mode"
        case rotationUnit = "p_rotation_unit"
        case isPrivate = "p_private"
    }

    // Beschreibung, Datum und Uhrzeit werden bei update_task immer gesendet (auch null),
    // damit Entferntes wirklich entfernt wird; RPC-Standardwerte gelten nur beim Anlegen.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encodeIfPresent(expectedVersion, forKey: .expectedVersion)
        try container.encodeIfPresent(familyID, forKey: .familyID)
        try container.encode(title, forKey: .title)
        try container.encode(completionMode, forKey: .completionMode)
        try container.encode(assigneeIDs, forKey: .assigneeIDs)
        try container.encode(description, forKey: .description)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(images, forKey: .images)
        if isPrivate {
            try container.encode(true, forKey: .isPrivate)
        }
        if let recurrence {
            try container.encode(recurrence.frequency, forKey: .freq)
            try container.encode(recurrence.weekdays, forKey: .weekdays)
            try container.encode(recurrence.monthDays, forKey: .monthDays)
            try container.encode(assignmentMode, forKey: .assignmentMode)
            try container.encode(rotationUnit, forKey: .rotationUnit)
        }
    }
}
