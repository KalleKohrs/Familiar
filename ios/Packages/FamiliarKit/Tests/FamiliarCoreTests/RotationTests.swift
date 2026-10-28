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

    /// Wie W16 in `0010_rotation_nudges.sql`: Freitag → Montag ab diesem Freitag (Mia) – danach Otto, nicht wieder Mia.
    @Test func ruleChangeDoesNotGiveTwoTurnsInARow() {
        let friday = LocalDate(year: 2026, month: 10, day: 23)
        let monday = friday.adding(days: 3)
        let rule = RecurrenceRule.weekly([monday.isoWeekday])
        let person = { (date: LocalDate) in
            RotationRules.person(order: [self.mia, self.otto], index: RotationRules.index(
                rule: rule, unit: .occurrence, start: friday, date: date))
        }
        #expect(person(friday) == mia)
        #expect(person(monday) == otto)
        #expect(person(monday.adding(days: 7)) == mia)
        let preview = RotationRules.upcoming(rule: rule, unit: .occurrence, start: friday, order: [mia, otto],
                                             from: friday.adding(days: 1), count: 2)
        #expect(preview.map(\.person) == [otto, mia])
    }

    /// Wie W17: Start in der Vergangenheit – die Reihe beginnt beim ersten Termin, der entsteht.
    @Test func rotationStartsAtFirstRealOccurrence() {
        let rule = RecurrenceRule.weekly([thursday.isoWeekday])
        #expect(RotationRules.start(rule: rule, startDate: thursday.adding(days: -7), today: thursday) == thursday)
        #expect(RotationRules.start(rule: rule, startDate: thursday.adding(days: -6), today: thursday.adding(days: 1))
                == thursday.adding(days: 7))
        #expect(RotationRules.start(rule: rule, startDate: thursday.adding(days: 7), today: thursday)
                == thursday.adding(days: 7))
        // Startdatum an einem anderen Wochentag: Erste Person ist beim ersten Donnerstag dran.
        let sunday = thursday.adding(days: 3)
        let start = RotationRules.start(rule: rule, startDate: sunday, today: sunday)
        #expect(RotationRules.index(rule: rule, unit: .week, start: start, date: thursday.adding(days: 7)) == 0)
        #expect(RotationRules.index(rule: rule, unit: .occurrence, start: start, date: thursday.adding(days: 7)) == 0)
    }

    @Test func draftDropsFormerMembers() {
        var draft = TaskDraft(familyID: UUID())
        draft.assigneeIDs = [otto, mia, clara]
        draft.keepOnlyMembers([mia, clara])
        #expect(draft.assigneeIDs == [mia, clara])
    }

    @Test func editingASwappedOccurrenceShowsItsPersonFirst() {
        let series = TaskSeries(id: UUID(), rule: .daily, startDate: thursday, assignmentMode: .rotate,
                                rotationStart: thursday, assigneeOrder: [mia, otto, clara])
        // Laut Reihe wäre Mia dran, getauscht wurde an Clara.
        let task = TaskItem(id: UUID(), familyID: UUID(), createdBy: mia, title: "Tisch decken",
                            startDate: thursday, completionMode: .anyOne,
                            assignees: [TaskAssignee(userID: clara)], seriesID: series.id,
                            occurrenceDate: thursday, series: series)
        let draft = TaskDraft(task: task)
        #expect(draft.isRotating)
        #expect(draft.assigneeIDs == [clara, mia, otto])
    }
}
