import FamiliarCore
import Foundation
import Testing

/// Gleiche Fälle wie die SQL-Prüfung von `private.series_dates` (Migration 0009, Entscheidung E2).
struct RecurrenceTests {
    func day(_ string: String) -> LocalDate { LocalDate(string)! }

    @Test func missingMonthDayFallsOnLastDayAndIsCountedOnce() {
        let dates = RecurrenceRule.monthly([30, 31]).dates(from: day("2027-01-01"), through: day("2027-04-30"))
        #expect(dates.map(\.description) == ["2027-01-30", "2027-01-31", "2027-02-28", "2027-03-30", "2027-03-31", "2027-04-30"])
    }

    @Test func leapYearFebruary() {
        let dates = RecurrenceRule.monthly([31]).dates(from: day("2028-01-01"), through: day("2028-03-31"))
        #expect(dates.map(\.description) == ["2028-01-31", "2028-02-29", "2028-03-31"])
    }

    @Test func weekdaysUseISONumbering() {
        let dates = RecurrenceRule.weekly([1, 5]).dates(from: day("2026-10-19"), through: day("2026-11-01"))
        #expect(dates.map(\.description) == ["2026-10-19", "2026-10-23", "2026-10-26", "2026-10-30"])
        #expect(day("2026-10-25").isoWeekday == 7)
    }

    @Test func dailyAcrossDaylightSavingChange() {
        let dates = RecurrenceRule.daily.dates(from: day("2026-10-24"), through: day("2026-10-27"))
        #expect(dates.count == 4)
    }

    @Test func emptyRangeAndFirstDate() {
        #expect(RecurrenceRule.daily.dates(from: day("2026-11-02"), through: day("2026-11-01")).isEmpty)
        #expect(RecurrenceRule.weekly([7]).firstDate(onOrAfter: day("2026-10-21")) == day("2026-10-25"))
    }

    @Test func normalizedAndComplete() {
        #expect(RecurrenceRule.weekly([5, 1, 5, 9]).normalized == .weekly([1, 5]))
        #expect(RecurrenceRule(frequency: .daily, weekdays: [1]).normalized == .daily)
        #expect(!RecurrenceRule.weekly([]).isComplete)
        #expect(!RecurrenceRule.monthly([0, 32]).isComplete)
        #expect(RecurrenceRule.monthly([31]).isComplete)
    }

    @Test func dateArithmetic() {
        #expect(day("2026-12-31").adding(days: 1) == day("2027-01-01"))
        #expect(day("2026-10-21").days(until: day("2026-11-01")) == 11)
    }

    @Test func draftWithRecurrenceAlwaysHasStartDate() {
        var draft = TaskDraft(familyID: UUID())
        draft.title = "Sport"
        draft.completionMode = .anyOne
        draft.assigneeIDs = [UUID()]
        draft.recurrence = .weekly([])
        #expect(draft.issues == [.recurrenceIncomplete])
        draft.recurrence = .weekly([3, 1])
        let input = draft.input()
        #expect(input?.startDate == draft.date)
        #expect(input?.recurrence == .weekly([1, 3]))
    }

    @Test func historyHidesOccurrencesDeletedWithTheSeries() {
        let now = Date.now
        let familyID = UUID()
        let single = TaskItem(id: UUID(), familyID: familyID, createdBy: nil, title: "A", completionMode: .anyOne,
                              deletedAt: now.addingTimeInterval(-60), assignees: [])
        let bySeries = TaskItem(id: UUID(), familyID: familyID, createdBy: nil, title: "B", completionMode: .anyOne,
                                deletedAt: now.addingTimeInterval(-30), assignees: [], deletedBySeriesOp: UUID())
        let deletion = SeriesDeletion(id: UUID(), seriesID: UUID(), familyID: familyID, deletedBy: nil,
                                      deletedAt: now.addingTimeInterval(-30))
        let restored = SeriesDeletion(id: UUID(), seriesID: UUID(), familyID: familyID, deletedBy: nil,
                                      deletedAt: now.addingTimeInterval(-10), restoredAt: now)
        let entries = HistoryRules.entries([single, bySeries], deletions: [deletion, restored], now: now)
        #expect(entries.map(\.id) == [deletion.id, single.id])
    }

    @Test func homeSectionsKeepOrderAndSkipEmptyOnes() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let now = LocalDate(year: 2026, month: 10, day: 21).date(at: LocalTime(hour: 12, minute: 0), in: berlin)
        let familyID = UUID()
        func task(_ title: String, _ date: String?, _ time: LocalTime? = nil) -> TaskItem {
            let start = date.flatMap(LocalDate.init)
            return TaskItem(id: UUID(), familyID: familyID, createdBy: nil, title: title, startDate: start, startTime: time,
                            startsAt: start?.date(at: time, in: berlin), completionMode: .anyOne, assignees: [])
        }
        let sections = TaskRules.homeSections([
            task("später", "2026-10-30"), task("morgen", "2026-10-22"), task("heute abend", "2026-10-21", LocalTime(hour: 18, minute: 0)),
            task("ohne", nil), task("gestern", "2026-10-20"), task("heute früh", "2026-10-21", LocalTime(hour: 8, minute: 0)),
        ], now: now)
        #expect(sections.map(\.section) == [.overdue, .today, .tomorrow, .later])
        #expect(sections.map { $0.tasks.map(\.title) } == [["gestern", "heute früh"], ["ohne", "heute abend"], ["morgen"], ["später"]])
    }
}
