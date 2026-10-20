import Foundation
import Testing
@testable import FamiliarActivity

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
