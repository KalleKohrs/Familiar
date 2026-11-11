import Foundation
import Testing
@testable import FamiliarCore

/// Private Aufgaben und zuletzt genutzte Familie (ADR 0012).
struct PrivateTaskTests {
    let me = UUID()
    let other = UUID()

    func draft(familyID: UUID? = UUID(), title: String = "Geschenk") -> TaskDraft {
        var draft = TaskDraft(familyID: familyID)
        draft.title = title
        return draft
    }

    // MARK: Entwurf

    @Test func privateDraftNeedsNoAssigneesAndNoCompletionChoice() {
        var draft = draft()
        #expect(draft.issues.contains(.assigneesMissing))
        draft.isPrivate = true
        #expect(draft.isValid)
        #expect(!draft.needsCompletionModeChoice)
        #expect(draft.effectiveCompletionMode == .anyOne)
    }

    @Test func privateInputAssignsOnlyTheCreatorEvenIfOthersWereChosen() throws {
        var draft = draft()
        draft.assigneeIDs = [other, me]
        draft.isPrivate = true
        let input = try #require(draft.input(creatorID: me))
        #expect(input.isPrivate)
        #expect(input.assigneeIDs == [me])
        #expect(input.completionMode == .anyOne)
    }

    @Test func sharedInputKeepsAssigneesAndIsNotPrivate() throws {
        var draft = draft()
        draft.assigneeIDs = [other]
        let input = try #require(draft.input(creatorID: me))
        #expect(!input.isPrivate)
        #expect(input.assigneeIDs == [other])
    }

    @Test func privateSeriesIsNeverRotating() throws {
        var draft = draft()
        draft.recurrence = .daily
        draft.assignmentMode = .rotate
        draft.assigneeIDs = [me, other]
        draft.isPrivate = true
        #expect(!draft.isRotating)
        let input = try #require(draft.input(creatorID: me))
        #expect(input.assignmentMode == .together)
        #expect(input.assigneeIDs == [me])
        #expect(input.recurrence != nil)
    }

    @Test func editingKeepsPrivacyOfTheTask() {
        let task = TaskItem(id: UUID(), familyID: UUID(), createdBy: me, title: "Geheim", completionMode: .anyOne,
                            assignees: [TaskAssignee(userID: me)], isPrivate: true)
        #expect(TaskDraft(task: task).isPrivate)
    }

    @Test func duplicateOfPrivateTaskIsPrivate() {
        let family = UUID()
        let task = TaskItem(id: UUID(), familyID: family, createdBy: me, title: "Geheim", completionMode: .anyOne,
                            assignees: [TaskAssignee(userID: me)], isPrivate: true)
        let copy = TaskDraft(duplicating: task)
        #expect(copy.isPrivate)
        #expect(copy.familyID == family)
        #expect(copy.isValid)
    }

    @Test func decodesIsPrivateWithDefaultFalse() throws {
        func json(_ extra: String) -> Data {
            Data("""
            {"id": "\(UUID())", "family_id": "\(UUID())", "title": "T", "timezone": "Europe/Berlin",
             "completion_mode": "any_one", "version": 1, "created_at": "2026-11-11T10:00:00Z"\(extra)}
            """.utf8)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(TaskItem.self, from: json(", \"is_private\": true")).isPrivate)
        #expect(try !decoder.decode(TaskItem.self, from: json("")).isPrivate)
    }

    // MARK: Zuletzt genutzte Familie

    func store() -> LastTaskFamily {
        let suite = "LastTaskFamilyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return LastTaskFamily(defaults: defaults)
    }

    @Test func firstTaskUsesFirstFamily() {
        let first = UUID(), second = UUID()
        #expect(store().preferred(for: me, among: [first, second]) == first)
    }

    @Test func rememberedFamilyIsPreferred() {
        let first = UUID(), second = UUID()
        let store = store()
        store.remember(second, for: me)
        #expect(store.preferred(for: me, among: [first, second]) == second)
    }

    @Test func rememberingIsPerAccount() {
        let first = UUID(), second = UUID()
        let store = store()
        store.remember(second, for: me)
        #expect(store.preferred(for: other, among: [first, second]) == first)
    }

    @Test func unknownRememberedFamilyFallsBackToFirst() {
        let first = UUID(), second = UUID(), gone = UUID()
        let store = store()
        store.remember(gone, for: me)
        #expect(store.preferred(for: me, among: [first, second]) == first)
        #expect(store.preferred(for: me, among: []) == nil)
        #expect(store.preferred(for: nil, among: [second]) == second)
    }
}
