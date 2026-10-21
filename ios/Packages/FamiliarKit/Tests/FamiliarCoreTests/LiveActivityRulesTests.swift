import Foundation
import Testing
@testable import FamiliarCore

struct LiveActivityRulesTests {
    let me = UUID()
    let other = UUID()
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    /// 21.10.2026, 14:00 in Berlin.
    var start: Date { LocalDate(year: 2026, month: 10, day: 21).date(at: LocalTime(hour: 14, minute: 0), in: berlin) }

    func task(time: LocalTime? = LocalTime(hour: 14, minute: 0), date: LocalDate? = LocalDate(year: 2026, month: 10, day: 21),
              assignees: [TaskAssignee]? = nil, completedAt: Date? = nil) -> TaskItem {
        TaskItem(
            id: UUID(), familyID: UUID(), createdBy: other, title: "Termin",
            startDate: date, startTime: time, timezone: "Europe/Berlin",
            startsAt: date?.date(at: time, in: berlin),
            completionMode: .anyOne, completedAt: completedAt,
            createdAt: .now, assignees: assignees ?? [TaskAssignee(userID: me)]
        )
    }

    @Test func startsFiveMinutesBeforeTimedTask() {
        let item = task()
        #expect(!LiveActivityRules.shouldStart(item, userID: me, now: start.addingTimeInterval(-6 * 60)))
        #expect(LiveActivityRules.shouldStart(item, userID: me, now: start.addingTimeInterval(-5 * 60)))
        #expect(LiveActivityRules.shouldStart(item, userID: me, now: start.addingTimeInterval(59 * 60)))
        #expect(!LiveActivityRules.shouldStart(item, userID: me, now: start.addingTimeInterval(60 * 60)))
    }

    @Test func dateOnlyStartsAtEightLocalTime() {
        let item = task(time: nil)
        let eight = LocalDate(year: 2026, month: 10, day: 21).date(at: LocalTime(hour: 8, minute: 0), in: berlin)
        #expect(LiveActivityRules.anchor(of: item) == eight)
        #expect(!LiveActivityRules.shouldStart(item, userID: me, now: eight.addingTimeInterval(-60)))
        #expect(LiveActivityRules.shouldStart(item, userID: me, now: eight))
    }

    @Test func undatedTasksAreLeftToTheServer() {
        #expect(!LiveActivityRules.shouldStart(task(time: nil, date: nil), userID: me, now: start))
    }

    @Test func onlyOpenAssignmentsStart() {
        #expect(!LiveActivityRules.shouldStart(task(assignees: [TaskAssignee(userID: other)]), userID: me, now: start))
        #expect(!LiveActivityRules.shouldStart(task(assignees: [TaskAssignee(userID: me, completedAt: .now)]),
                                               userID: me, now: start))
        #expect(!LiveActivityRules.shouldStart(task(completedAt: .now), userID: me, now: start))
    }

    @Test func reconcileStartsMissingAndEndsStale() {
        let due = task()
        let running = task()
        let doneForMe = task(assignees: [TaskAssignee(userID: me, completedAt: .now), TaskAssignee(userID: other)])
        let gone = UUID()
        let plan = LiveActivityRules.reconcile(openTasks: [due, running, doneForMe],
                                               running: [running.id, doneForMe.id, gone], userID: me, now: start)
        #expect(plan.start.map(\.id) == [due.id])
        #expect(plan.end == [doneForMe.id, gone])
    }
}
