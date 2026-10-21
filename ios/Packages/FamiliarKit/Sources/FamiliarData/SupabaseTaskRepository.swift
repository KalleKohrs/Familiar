import FamiliarCore
import Foundation
import Supabase

final class SupabaseTaskRepository: TaskRepository {
    private let client: SupabaseClient
    private static let bucket = "task-images"
    private static let select =
        "*, task_assignees(user_id, completed_at), task_image_links(position, images(id, path, thumb_path, width, height))"

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
        _ = try await perform {
            try await storage.upload("\(folder)/\(name).jpg", data: image.jpegData, options: options)
        }
        _ = try await perform {
            try await storage.upload("\(folder)/\(name)_thumb.jpg", data: image.thumbnailData, options: options)
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
                    if let taskID = Self.taskID(in: message) {
                        continuation.yield(taskID)
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

    /// `task_id` aus der Broadcast-Nachricht (`{"payload": {"task_id": …}}`).
    static func taskID(in message: JSONObject) -> UUID? {
        let payload = message["payload"]?.objectValue ?? message
        return payload["task_id"]?.stringValue.flatMap(UUID.init(uuidString:))
    }
}

/// Rückgabe der RPCs (komplette tasks-Zeile); gebraucht wird nur die ID zum Neuladen mit Einbettungen.
private struct TaskRowID: Decodable {
    let id: UUID
}

/// Parameter von `create_task` und `update_task`; `nil` wird nicht gesendet (Standardwert der RPC).
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
    }
}
