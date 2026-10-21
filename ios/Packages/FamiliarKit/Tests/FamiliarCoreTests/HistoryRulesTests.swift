import Foundation
import Testing
@testable import FamiliarCore

struct HistoryRulesTests {
    let me = UUID()
    let other = UUID()
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func task(completedAt: Date? = nil, completedBy: UUID? = nil, deletedAt: Date? = nil, deletedBy: UUID? = nil) -> TaskItem {
        TaskItem(id: UUID(), familyID: UUID(), createdBy: me, title: "Test", completionMode: .anyOne,
                 completedAt: completedAt, completedBy: completedBy, completionSource: completedAt == nil ? nil : .assignee,
                 deletedAt: deletedAt, deletedBy: deletedBy, assignees: [])
    }

    @Test func deletedWinsOverCompleted() {
        let item = task(completedAt: now.addingTimeInterval(-7200), completedBy: me,
                        deletedAt: now.addingTimeInterval(-3600), deletedBy: other)
        #expect(HistoryRules.kind(of: item) == .deleted)
        #expect(HistoryRules.actor(of: item) == other)
        #expect(HistoryRules.date(of: item) == now.addingTimeInterval(-3600))
    }

    @Test func openTaskIsNoHistoryEntry() {
        #expect(HistoryRules.kind(of: task()) == nil)
        #expect(HistoryRules.daysRemaining(for: task(), now: now) == nil)
    }

    @Test func daysRemainingCountsDownFromThirty() {
        #expect(HistoryRules.daysRemaining(for: task(completedAt: now), now: now) == 30)
        #expect(HistoryRules.daysRemaining(for: task(completedAt: now.addingTimeInterval(-29.5 * 86_400)), now: now) == 0)
    }

    @Test func entriesAreNewestFirstWithinRetention() {
        let old = task(completedAt: now.addingTimeInterval(-31 * 86_400))
        let yesterday = task(completedAt: now.addingTimeInterval(-86_400))
        let hourAgo = task(deletedAt: now.addingTimeInterval(-3600))
        #expect(HistoryRules.entries([yesterday, old, hourAgo], now: now).map(\.id) == [hourAgo.id, yesterday.id])
    }
}
