import Foundation
import Testing
@testable import FamiliarCore

/// Reihum (ADR 0010): gleiche Fälle wie `supabase/tests/0010_rotation_nudges.sql`.
struct RotationTests {
    private let mia = UUID()
    private let otto = UUID()
    private let clara = UUID()
    private let thursday = LocalDate(year: 2026, month: 10, day: 22)

    @Test func weeklySeriesRotatesPerOccurrence() {
        let rule = RecurrenceRule.weekly([thursday.isoWeekday])
        let order = [mia, otto, clara]
        let people = (0..<4).map { week in
            RotationRules.person(order: order, index: RotationRules.index(
                rule: rule, unit: .occurrence, start: thursday, date: thursday.adding(days: 7 * week)))
        }
        #expect(people == [mia, otto, clara, mia])
    }

    @Test func dailySeriesWithWeeklyUnitKeepsPersonForTheWeek() {
        let monday = thursday.adding(days: -(thursday.isoWeekday - 1))
        let index = { (date: LocalDate) in
            RotationRules.index(rule: .daily, unit: .week, start: thursday, date: date)
        }
        #expect(index(monday) == 0)
        #expect(index(monday.adding(days: 6)) == 0)
        #expect(index(monday.adding(days: 7)) == 1)
        #expect(index(monday.adding(days: -1)) == -1)
        #expect(RotationRules.person(order: [mia, otto], index: -1) == otto)
    }

    @Test func rotatedOrderStartsWithPersonDue() {
        #expect(RotationRules.rotated([mia, otto, clara], startingAt: 4) == [otto, clara, mia])
        #expect(RotationRules.rotated([mia, otto, clara], startingAt: 0) == [mia, otto, clara])
    }

    @Test func upcomingListsDatesAndPeople() {
        let next = RotationRules.upcoming(rule: .weekly([thursday.isoWeekday]), unit: .occurrence, start: thursday,
                                          order: [mia, otto], from: thursday.adding(days: 1), count: 2)
        #expect(next.map(\.date) == [thursday.adding(days: 7), thursday.adding(days: 14)])
        #expect(next.map(\.person) == [otto, mia])
    }

    @Test func seriesSkipsFormerMembers() {
        let series = TaskSeries(id: UUID(), rule: .daily, startDate: thursday, assignmentMode: .rotate,
                                rotationStart: thursday, assigneeOrder: [mia, otto, clara])
        // Otto ist ausgetreten: Reihe rückt zusammen (Mia, Clara, Mia …).
        let members: Set = [mia, clara]
        let people = (0..<3).map { series.rotationPerson(on: thursday.adding(days: $0), members: members) }
        #expect(people == [mia, clara, mia])
    }

    @Test func draftRotationNeedsTwoAndForcesSinglePerson() {
        var draft = TaskDraft(familyID: UUID())
        draft.title = "Müll rausbringen"
        draft.hasDate = true
        draft.recurrence = .weekly([thursday.isoWeekday])
        draft.assignmentMode = .rotate
        draft.assigneeIDs = [mia]
        #expect(draft.issues.contains(.rotationNeedsTwo))
        draft.assigneeIDs = [mia, otto]
        #expect(!draft.needsCompletionModeChoice)
        #expect(draft.effectiveCompletionMode == .anyOne)
        let input = draft.input()
        #expect(input?.assignmentMode == .rotate)
        #expect(input?.rotationUnit == .occurrence) // eine Termin pro Woche: Wochenwechsel entfällt
        draft.moveAssignee(otto, by: -1)
        #expect(draft.assigneeIDs == [otto, mia])
    }
}
