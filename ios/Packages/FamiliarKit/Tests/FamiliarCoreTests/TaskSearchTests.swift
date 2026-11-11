import Foundation
import Testing
@testable import FamiliarCore

struct TaskSearchTests {
    let anna = UUID()
    let juergen = UUID()
    let familyID = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var names: TaskSearch.NameResolver {
        let anna = anna, juergen = juergen
        return { userID, _ in
            userID == anna ? "Anna" : userID == juergen ? "Jürgen" : "Ehemaliges Mitglied"
        }
    }

    func task(_ title: String, description: String? = nil, assignees: [UUID] = [], completed: Bool = false,
              completedBy: UUID? = nil, deleted: Bool = false, deletedBy: UUID? = nil) -> TaskItem {
        TaskItem(
            id: UUID(), familyID: familyID, createdBy: nil, title: title, description: description,
            completionMode: .anyOne,
            completedAt: completed ? now : nil, completedBy: completedBy,
            deletedAt: deleted ? now : nil, deletedBy: deletedBy,
            assignees: assignees.map { TaskAssignee(userID: $0) }
        )
    }

    func titles(_ tasks: [TaskItem]) -> [String] { tasks.map(\.title) }

    // MARK: Aufgaben

    @Test func emptyQueryKeepsEverythingInOrder() {
        let all = [task("B"), task("A")]
        #expect(titles(TaskSearch.filter(all, query: "", nameOf: names)) == ["B", "A"])
        #expect(titles(TaskSearch.filter(all, query: "  \n ", nameOf: names)) == ["B", "A"])
        #expect(!TaskSearch.isActive("   "))
        #expect(TaskSearch.isActive(" a "))
    }

    @Test func findsTitleIgnoringCaseAndAccents() {
        let all = [task("Müll rausbringen"), task("Zimmer aufräumen"), task("Café besuchen")]
        #expect(titles(TaskSearch.filter(all, query: "MÜLL", nameOf: names)) == ["Müll rausbringen"])
        #expect(titles(TaskSearch.filter(all, query: "mull", nameOf: names)) == ["Müll rausbringen"])
        #expect(titles(TaskSearch.filter(all, query: "muell", nameOf: names)).isEmpty)
        #expect(titles(TaskSearch.filter(all, query: "aufraumen", nameOf: names)) == ["Zimmer aufräumen"])
        #expect(titles(TaskSearch.filter(all, query: "cafe", nameOf: names)) == ["Café besuchen"])
        #expect(titles(TaskSearch.filter(all, query: "café", nameOf: names)) == ["Café besuchen"])
    }

    @Test func eszettCountsLikeDoubleS() {
        let all = [task("Straße fegen")]
        #expect(titles(TaskSearch.filter(all, query: "strasse", nameOf: names)) == ["Straße fegen"])
        #expect(titles(TaskSearch.filter(all, query: "STRAßE", nameOf: names)) == ["Straße fegen"])
    }

    @Test func decomposedAndComposedUmlautsMatch() {
        let all = [task("Mu\u{0308}ll rausbringen")] // „u“ + kombinierendes Trema
        #expect(titles(TaskSearch.filter(all, query: "Müll", nameOf: names)).count == 1)
    }

    @Test func findsPartOfAWordAndDescription() {
        let all = [task("Einkaufen", description: "Milch, Brot und Äpfel"), task("Sport")]
        #expect(titles(TaskSearch.filter(all, query: "einkauf", nameOf: names)) == ["Einkaufen"])
        #expect(titles(TaskSearch.filter(all, query: "apfel", nameOf: names)) == ["Einkaufen"])
        #expect(titles(TaskSearch.filter(all, query: "brot", nameOf: names)) == ["Einkaufen"])
    }

    @Test func findsByAssigneeName() {
        let all = [task("Müll", assignees: [anna]), task("Wäsche", assignees: [juergen]),
                   task("Bad", assignees: [anna, juergen])]
        #expect(titles(TaskSearch.filter(all, query: "anna", nameOf: names)) == ["Müll", "Bad"])
        #expect(titles(TaskSearch.filter(all, query: "jurgen", nameOf: names)) == ["Wäsche", "Bad"])
    }

    @Test func allWordsMustMatchInAnyOrderAcrossFields() {
        let all = [task("Müll rausbringen", assignees: [anna]), task("Müll sortieren", assignees: [juergen])]
        #expect(titles(TaskSearch.filter(all, query: "müll anna", nameOf: names)) == ["Müll rausbringen"])
        #expect(titles(TaskSearch.filter(all, query: "anna  müll", nameOf: names)) == ["Müll rausbringen"])
        #expect(titles(TaskSearch.filter(all, query: "müll bad", nameOf: names)).isEmpty)
    }

    @Test func noMatchGivesEmptyList() {
        #expect(TaskSearch.filter([task("Müll")], query: "xyz", nameOf: names).isEmpty)
    }

    // MARK: Verlauf

    @Test func historyFindsTasksByActorWhoCompletedOrDeleted() {
        let done = task("Wäsche", completed: true, completedBy: anna)
        let deleted = task("Garage", deleted: true, deletedBy: juergen)
        let entries: [HistoryEntry] = [.task(done), .task(deleted)]
        #expect(TaskSearch.filter(entries, query: "anna", nameOf: names).map(\.id) == [done.id])
        #expect(TaskSearch.filter(entries, query: "JÜRGEN", nameOf: names).map(\.id) == [deleted.id])
        #expect(TaskSearch.filter(entries, query: "garage", nameOf: names).map(\.id) == [deleted.id])
        #expect(TaskSearch.filter(entries, query: "", nameOf: names).count == 2)
    }

    @Test func historyFindsSeriesDeletionsByTitleAndPeople() {
        let series = TaskSeries(
            id: UUID(), familyID: familyID, title: "Blumen gießen",
            rule: .weekly([1]), assigneeOrder: [anna]
        )
        let deletion = SeriesDeletion(id: UUID(), seriesID: series.id, familyID: familyID, deletedBy: juergen,
                                      deletedAt: now, series: series)
        let entries: [HistoryEntry] = [.seriesDeletion(deletion)]
        #expect(TaskSearch.filter(entries, query: "giessen", nameOf: names).count == 1)
        #expect(TaskSearch.filter(entries, query: "anna", nameOf: names).count == 1)
        #expect(TaskSearch.filter(entries, query: "jürgen", nameOf: names).count == 1)
        #expect(TaskSearch.filter(entries, query: "garage", nameOf: names).isEmpty)
    }
}
