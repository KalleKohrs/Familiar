import Foundation
import Testing
@testable import FamiliarCore

struct TaskRulesTests {
    let me = UUID()
    let other = UUID()
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    func task(
        mode: CompletionMode,
        createdBy: UUID?,
        assignees: [TaskAssignee],
        startDate: LocalDate? = nil,
        startTime: LocalTime? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) -> TaskItem {
        TaskItem(
            id: UUID(), familyID: UUID(), createdBy: createdBy, title: "Test",
            startDate: startDate, startTime: startTime, timezone: "Europe/Berlin",
            startsAt: startDate?.date(at: startTime, in: berlin),
            completionMode: mode,
            completedAt: completedAt, completionSource: completedAt == nil ? nil : .assignee,
            createdAt: createdAt, assignees: assignees
        )
    }

    // MARK: Abhaken (Guide, Abschnitt 3)

    @Test func anyOneAssigneeCompletesForEveryone() {
        let item = task(mode: .anyOne, createdBy: other, assignees: [TaskAssignee(userID: me)])
        #expect(TaskRules.actions(for: item, userID: me) == [.completeForMe])
    }

    @Test func creatorWithoutAssignmentMayCompleteAll() {
        let item = task(mode: .anyOne, createdBy: me, assignees: [TaskAssignee(userID: other)])
        #expect(TaskRules.actions(for: item, userID: me) == [.completeForAll])
    }

    @Test func creatorIsNotTreatedAsAssignee() {
        // Der Ersteller ist nicht automatisch zugewiesen: Er sieht „für alle erledigen“, nicht „für mich“.
        let item = task(mode: .each, createdBy: me, assignees: [TaskAssignee(userID: other)])
        #expect(TaskRules.actions(for: item, userID: me) == [.completeForAll])
    }

    @Test func eachCreatorAssigneeGetsBothOptions() {
        let item = task(mode: .each, createdBy: me, assignees: [TaskAssignee(userID: me), TaskAssignee(userID: other)])
        #expect(TaskRules.actions(for: item, userID: me) == [.completeForMe, .completeForAll])
    }

    @Test func eachAssigneeCanUndoOwnCheck() {
        let item = task(mode: .each, createdBy: other,
                        assignees: [TaskAssignee(userID: me, completedAt: .now), TaskAssignee(userID: other)])
        #expect(TaskRules.actions(for: item, userID: me) == [.undoMine])
    }

    @Test func othersMayNotComplete() {
        let item = task(mode: .anyOne, createdBy: other, assignees: [TaskAssignee(userID: other)])
        #expect(TaskRules.actions(for: item, userID: me).isEmpty)
    }

    @Test func completedTaskHasNoActions() {
        let item = task(mode: .anyOne, createdBy: me, assignees: [TaskAssignee(userID: me)], completedAt: .now)
        #expect(TaskRules.actions(for: item, userID: me).isEmpty)
    }

    // MARK: Startseite (Guide, Abschnitt 5)

    @Test func undatedFirstNewestOnTopThenChronological() {
        let old = task(mode: .anyOne, createdBy: me, assignees: [], createdAt: Date(timeIntervalSince1970: 100))
        let new = task(mode: .anyOne, createdBy: me, assignees: [], createdAt: Date(timeIntervalSince1970: 200))
        let later = task(mode: .anyOne, createdBy: me, assignees: [], startDate: LocalDate(year: 2026, month: 11, day: 3))
        let sooner = task(mode: .anyOne, createdBy: me, assignees: [],
                          startDate: LocalDate(year: 2026, month: 11, day: 3), startTime: LocalTime(hour: 8, minute: 0))
        let ordered = TaskRules.homeOrder([later, old, sooner, new])
        #expect(ordered.map(\.id) == [new.id, old.id, later.id, sooner.id])
    }

    // MARK: Überfällig

    @Test func timedTaskIsOverdueOneHourAfterStart() {
        let item = task(mode: .anyOne, createdBy: me, assignees: [],
                        startDate: LocalDate(year: 2026, month: 10, day: 21), startTime: LocalTime(hour: 10, minute: 0))
        let start = LocalDate(year: 2026, month: 10, day: 21).date(at: LocalTime(hour: 10, minute: 0), in: berlin)
        #expect(!TaskRules.isOverdue(item, now: start.addingTimeInterval(59 * 60)))
        #expect(TaskRules.isOverdue(item, now: start.addingTimeInterval(61 * 60)))
    }

    @Test func dateOnlyTaskIsOverdueFromNextDay() {
        let item = task(mode: .anyOne, createdBy: me, assignees: [], startDate: LocalDate(year: 2026, month: 10, day: 21))
        let lateEvening = LocalDate(year: 2026, month: 10, day: 21).date(at: LocalTime(hour: 23, minute: 30), in: berlin)
        let nextMorning = LocalDate(year: 2026, month: 10, day: 22).date(at: LocalTime(hour: 0, minute: 30), in: berlin)
        #expect(!TaskRules.isOverdue(item, now: lateEvening))
        #expect(TaskRules.isOverdue(item, now: nextMorning))
    }

    @Test func undatedTaskIsNeverOverdue() {
        #expect(!TaskRules.isOverdue(task(mode: .anyOne, createdBy: me, assignees: []), now: .distantFuture))
    }
}

struct LocalDateTimeTests {
    @Test func parsesAndFormatsPostgresValues() {
        #expect(LocalDate("2026-10-21") == LocalDate(year: 2026, month: 10, day: 21))
        #expect(LocalDate("2026-10-21")?.description == "2026-10-21")
        #expect(LocalDate("21.10.2026") == nil)
        #expect(LocalTime("14:30:00") == LocalTime(hour: 14, minute: 30))
        #expect(LocalTime("07:05")?.description == "07:05:00")
        #expect(LocalTime("25:00") == nil)
    }

    @Test func combinesDateAndTimeInTaskTimeZone() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        // 21.10.2026 gilt Sommerzeit (UTC+2), 3.11.2026 Winterzeit (UTC+1).
        let summer = LocalDate(year: 2026, month: 10, day: 21).date(at: LocalTime(hour: 14, minute: 30), in: berlin)
        let winter = LocalDate(year: 2026, month: 11, day: 3).date(at: LocalTime(hour: 14, minute: 30), in: berlin)
        #expect(summer == ISO8601DateFormatter().date(from: "2026-10-21T12:30:00Z"))
        #expect(winter == ISO8601DateFormatter().date(from: "2026-11-03T13:30:00Z"))
    }
}

struct TaskDraftTests {
    let family = UUID()
    let person = UUID()

    @Test func newDraftNeedsTitleAssigneeAndExplicitMode() {
        var draft = TaskDraft(familyID: family)
        #expect(Set(draft.issues) == [.titleMissing, .assigneesMissing])
        #expect(draft.input() == nil)
        // Ab zwei Personen muss die Erledigungsart bewusst gewählt werden.
        draft.title = "Aufräumen"
        draft.toggleAssignee(person)
        draft.toggleAssignee(UUID())
        #expect(draft.issues == [.completionModeMissing])
    }

    @Test func singleAssigneeNeedsNoModeChoice() {
        var draft = TaskDraft(familyID: family)
        draft.title = "Müll"
        draft.toggleAssignee(person)
        #expect(!draft.needsCompletionModeChoice)
        #expect(draft.input()?.completionMode == .anyOne)
    }

    @Test func inputDropsTimeWithoutDateAndEmptyDescription() throws {
        var draft = TaskDraft(familyID: family)
        draft.title = "  Müll rausbringen  "
        draft.description = "   "
        draft.hasTime = true
        draft.completionMode = .anyOne
        draft.toggleAssignee(person)
        let input = try #require(draft.input())
        #expect(input.title == "Müll rausbringen")
        #expect(input.description == nil)
        #expect(input.startDate == nil)
        #expect(input.startTime == nil)
        #expect(input.assigneeIDs == [person])
    }

    @Test func toggleAssigneeAddsAndRemoves() {
        var draft = TaskDraft(familyID: family)
        draft.toggleAssignee(person)
        draft.toggleAssignee(person)
        #expect(draft.assigneeIDs.isEmpty)
    }

    @Test func limitsTitleLengthAndImages() {
        var draft = TaskDraft(familyID: family)
        draft.title = String(repeating: "a", count: 201)
        draft.images = (0..<11).map { _ in .new(PreparedImage(jpegData: Data(), thumbnailData: Data(), width: 1, height: 1)) }
        #expect(draft.issues.contains(.titleTooLong))
        #expect(draft.issues.contains(.tooManyImages))
    }

    @Test func soleAssigneeCreatorGetsOnlyOneAction() {
        let me = UUID()
        let item = TaskItem(id: UUID(), familyID: UUID(), createdBy: me, title: "Allein", completionMode: .each,
                            assignees: [TaskAssignee(userID: me)])
        #expect(TaskRules.actions(for: item, userID: me) == [.completeForMe])
        #expect(TaskRules.completesTask(item, userID: me))
    }

    @Test func lastOpenAssigneeCreatorGetsOnlyOneAction() {
        let me = UUID()
        let other = TaskAssignee(userID: UUID(), completedAt: .now)
        let item = TaskItem(id: UUID(), familyID: UUID(), createdBy: me, title: "Fast fertig", completionMode: .each,
                            assignees: [TaskAssignee(userID: me), other])
        #expect(TaskRules.actions(for: item, userID: me) == [.completeForMe])
    }
}

// MARK: Schnellaktionen: Verschieben und Duplizieren

struct TaskQuickActionsTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    /// 2026-11-11 12:00 in Berlin.
    var now: Date { LocalDate(year: 2026, month: 11, day: 11).date(at: LocalTime(hour: 12, minute: 0), in: berlin) }

    func task(date: LocalDate?, time: LocalTime? = nil, open: Bool = true) -> TaskItem {
        TaskItem(
            id: UUID(), familyID: UUID(), createdBy: UUID(), title: "Müll rausbringen", description: "Biotonne nicht vergessen",
            startDate: date, startTime: time, timezone: "Europe/Berlin",
            startsAt: date?.date(at: time, in: berlin),
            completionMode: .each,
            completedAt: open ? nil : now, completionSource: open ? nil : .assignee,
            createdAt: now, assignees: [TaskAssignee(userID: UUID()), TaskAssignee(userID: UUID())],
            images: [TaskImage(id: UUID(), path: "a", thumbPath: "b", width: 10, height: 10)]
        )
    }

    @Test func overdueTaskMovesFromToday() {
        let item = task(date: LocalDate(year: 2026, month: 11, day: 3))
        #expect(TaskRules.postponedDate(for: item, by: .oneDay, now: now) == LocalDate(year: 2026, month: 11, day: 12))
        #expect(TaskRules.postponedDate(for: item, by: .oneWeek, now: now) == LocalDate(year: 2026, month: 11, day: 18))
    }

    @Test func futureTaskMovesFromItsOwnDate() {
        let item = task(date: LocalDate(year: 2026, month: 11, day: 20))
        #expect(TaskRules.postponedDate(for: item, by: .oneDay, now: now) == LocalDate(year: 2026, month: 11, day: 21))
    }

    @Test func monthAndYearBoundariesAreHandled() {
        let item = task(date: LocalDate(year: 2026, month: 12, day: 30))
        #expect(TaskRules.postponedDate(for: item, by: .oneWeek, now: now) == LocalDate(year: 2027, month: 1, day: 6))
    }

    @Test func todayUsesTheTaskTimeZone() {
        // 2026-11-11 23:30 in Berlin ist in Tokio schon der 12.
        let lateEvening = LocalDate(year: 2026, month: 11, day: 11).date(at: LocalTime(hour: 23, minute: 30), in: berlin)
        var item = task(date: LocalDate(year: 2026, month: 11, day: 1))
        item.timezone = "Asia/Tokyo"
        #expect(TaskRules.postponedDate(for: item, by: .oneDay, now: lateEvening) == LocalDate(year: 2026, month: 11, day: 13))
    }

    @Test func undatedClosedOrDeletedTasksCannotBePostponed() {
        #expect(!TaskRules.canPostpone(task(date: nil)))
        #expect(!TaskRules.canPostpone(task(date: LocalDate(year: 2026, month: 11, day: 12), open: false)))
        #expect(TaskRules.postponedDate(for: task(date: nil), by: .oneDay, now: now) == nil)
        #expect(TaskRules.canPostpone(task(date: LocalDate(year: 2026, month: 11, day: 12))))
    }

    @Test func duplicateKeepsContentAndImagesButNotRecurrence() {
        let item = task(date: LocalDate(year: 2026, month: 11, day: 20), time: LocalTime(hour: 18, minute: 30))
        let draft = TaskDraft(duplicating: item, now: now)
        #expect(draft.title == "Müll rausbringen")
        #expect(draft.description == "Biotonne nicht vergessen")
        #expect(draft.familyID == item.familyID)
        #expect(draft.assigneeIDs == item.assignees.map(\.userID))
        #expect(draft.completionMode == .each)
        #expect(draft.hasDate && draft.date == LocalDate(year: 2026, month: 11, day: 20))
        #expect(draft.hasTime && draft.time == LocalTime(hour: 18, minute: 30))
        #expect(draft.images == item.images.map(DraftImage.existing))
        #expect(draft.recurrence == nil)
        #expect(draft.assignmentMode == .together)
        #expect(draft.isValid)
    }

    @Test func duplicateOfPastTaskStartsToday() {
        let item = task(date: LocalDate(year: 2026, month: 11, day: 3))
        #expect(TaskDraft(duplicating: item, now: now).date == LocalDate(year: 2026, month: 11, day: 11))
    }

    @Test func duplicateOfUndatedTaskStaysUndated() {
        let draft = TaskDraft(duplicating: task(date: nil), now: now)
        #expect(!draft.hasDate && !draft.hasTime)
    }
}
