import FamiliarCore
import Foundation
import Supabase
import Testing
@testable import FamiliarData

struct TaskDecodingTests {
    let decoder = PostgrestClient.Configuration.jsonDecoder

    @Test func taskWithAssigneesAndImagesInPositionOrder() throws {
        let json = """
        [{
          "id": "7d3c1e2a-0b4f-4c5d-8e6f-7a8b9c0d1e2f",
          "family_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
          "series_id": null, "occurrence_date": null,
          "created_by": "a1111111-1111-4111-8111-111111111111",
          "title": "Müll rausbringen", "description": null,
          "start_date": "2026-10-21", "start_time": "18:30:00", "timezone": "Europe/Berlin",
          "starts_at": "2026-10-21T16:30:00+00:00", "sort_at": "2026-10-21T16:30:00+00:00",
          "completion_mode": "each", "is_detached": false,
          "completed_at": null, "completed_by": null, "completion_source": null,
          "deleted_at": null, "deleted_by": null, "deleted_by_series_op": null,
          "version": 3, "created_at": "2026-10-20T20:00:00.123456+00:00", "updated_at": "2026-10-20T20:00:00+00:00",
          "task_assignees": [
            {"user_id": "a1111111-1111-4111-8111-111111111111", "completed_at": "2026-10-20T21:00:00+00:00"},
            {"user_id": "a2222222-2222-4222-8222-222222222222", "completed_at": null}
          ],
          "task_image_links": [
            {"position": 1, "images": {"id": "b2222222-2222-4222-8222-222222222222", "path": "f/b2.jpg", "thumb_path": "f/b2_thumb.jpg", "width": 800, "height": 600}},
            {"position": 0, "images": {"id": "b1111111-1111-4111-8111-111111111111", "path": "f/b1.jpg", "thumb_path": "f/b1_thumb.jpg", "width": 600, "height": 800}}
          ]
        }]
        """
        let tasks = try decoder.decode([TaskItem].self, from: Data(json.utf8))
        let task = try #require(tasks.first)
        #expect(task.title == "Müll rausbringen")
        #expect(task.startDate == LocalDate(year: 2026, month: 10, day: 21))
        #expect(task.startTime == LocalTime(hour: 18, minute: 30))
        #expect(task.startsAt == ISO8601DateFormatter().date(from: "2026-10-21T16:30:00Z"))
        #expect(task.completionMode == .each)
        #expect(task.version == 3)
        #expect(task.assignees.map(\.isDone) == [true, false])
        #expect(task.images.map(\.path) == ["f/b1.jpg", "f/b2.jpg"])
        #expect(task.isOpen)
    }

    @Test func updateParamsSendNullsSoRemovedValuesAreCleared() throws {
        let input = TaskInput(
            familyID: UUID(), title: "Einkaufen", description: nil, startDate: nil, startTime: nil,
            timezone: "Europe/Berlin", completionMode: .anyOne, assigneeIDs: [UUID()], images: []
        )
        let data = try JSONEncoder().encode(TaskParams(input: input, taskID: UUID(), expectedVersion: 2))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["p_family_id"] == nil)
        #expect(object["p_expected_version"] as? Int == 2)
        #expect(object["p_description"] is NSNull)
        #expect(object["p_start_date"] is NSNull)
        #expect(object["p_completion_mode"] as? String == "any_one")
    }

    @Test func createParamsEncodeDateTimeAsPostgresStrings() throws {
        let input = TaskInput(
            familyID: UUID(), title: "Arzt", description: "Impfung", startDate: LocalDate(year: 2026, month: 11, day: 3),
            startTime: LocalTime(hour: 8, minute: 15), timezone: "Europe/Berlin", completionMode: .each,
            assigneeIDs: [UUID()], images: [TaskImageReference(id: UUID(), width: 10, height: 20)]
        )
        let data = try JSONEncoder().encode(TaskParams(input: input))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["p_task_id"] == nil)
        #expect(object["p_start_date"] as? String == "2026-11-03")
        #expect(object["p_start_time"] as? String == "08:15:00")
        #expect((object["p_images"] as? [[String: Any]])?.first?["width"] as? Int == 10)
    }

    @Test func broadcastPayloadYieldsTaskID() {
        let id = UUID()
        let message: JSONObject = ["event": "task_changed", "payload": ["task_id": .string(id.uuidString.lowercased())]]
        #expect(SupabaseTaskRepository.taskID(in: message) == id)
        #expect(SupabaseTaskRepository.taskID(in: ["payload": ["other": "x"]]) == nil)
    }
}
