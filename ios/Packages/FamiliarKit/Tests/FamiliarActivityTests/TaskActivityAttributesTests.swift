import Foundation
import Testing
@testable import FamiliarActivity
import FamiliarCore

struct TaskActivityAttributesTests {
    /// ActivityKit erlaubt für statische und dynamische Daten zusammen höchstens 4 KB.
    @Test func worstCasePayloadStaysBelowFourKilobytes() throws {
        let attributes = TaskActivityAttributes(taskID: UUID(), familyColorHex: "#FF7F66")
        let state = TaskActivityAttributes.ContentState(
            title: String(repeating: "Überlange Aufgabe ", count: 10),
            startsAtUnix: 1_800_000_000,
            completionMode: .each,
            assignees: (0..<12).map { .init(initials: "M\($0)", isDone: $0.isMultiple(of: 2)) },
            canComplete: true
        )
        let encoder = JSONEncoder()
        let size = try encoder.encode(attributes).count + encoder.encode(state).count
        #expect(size < 4096)
    }

    @Test func decodesServerPayloadWithDefaultStrategies() throws {
        let json = """
        {"title":"Müll rausbringen","startsAtUnix":1800000000,"completionMode":"any_one",
         "assignees":[{"initials":"AK","isDone":false}],"canComplete":true}
        """
        let state = try JSONDecoder().decode(TaskActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(state.completionMode == .anyOne)
        #expect(state.startsAt == Date(timeIntervalSince1970: 1_800_000_000))
    }
}

struct TaskActivityContentTests {
    @Test func contentFromTaskMatchesServerFields() throws {
        let me = UUID(), other = UUID()
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let date = LocalDate(year: 2026, month: 10, day: 21)
        let timed = TaskItem(id: UUID(), familyID: UUID(), createdBy: other, title: "Arzt",
                             startDate: date, startTime: LocalTime(hour: 9, minute: 30), timezone: "Europe/Berlin",
                             startsAt: date.date(at: LocalTime(hour: 9, minute: 30), in: berlin),
                             completionMode: .each, createdAt: .now,
                             assignees: [TaskAssignee(userID: other, completedAt: .now), TaskAssignee(userID: me)])
        let state = TaskActivityAttributes.ContentState(task: timed, userID: me, names: [me: "mia", other: "Ben"])
        #expect(state.assignees == [.init(initials: "B", isDone: true), .init(initials: "M", isDone: false)])
        #expect(state.canComplete)
        #expect(state.startsAtUnix == timed.startsAt?.timeIntervalSince1970)

        var dateOnly = timed
        dateOnly.startTime = nil
        #expect(TaskActivityAttributes.ContentState(task: dateOnly, userID: me, names: [:]).startsAtUnix == nil)
    }
}
