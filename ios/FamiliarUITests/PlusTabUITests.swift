import XCTest

/// Hauptnavigation: genau ein Element pro Bereich, und der Plus-Button öffnet „Neue Aufgabe“,
/// ohne den aktiven Bereich zu wechseln.
final class PlusTabUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEachTabIsASingleAccessibilityElement() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", "ready"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 10))

        for title in ["Aufgaben", "Kalender", "Verlauf", "Neue Aufgabe"] {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", title))
            XCTAssertEqual(matches.count, 1, "„\(title)“ ist mehrfach als Button sichtbar")
        }
    }

    @MainActor
    func testPlusButtonOpensSheetAndKeepsSelectedTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", "ready"]
        app.launch()

        let tasksTab = app.buttons["tab.tasks"]
        XCTAssertTrue(tasksTab.waitForExistence(timeout: 10))
        XCTAssertTrue(tasksTab.isSelected)

        let calendarTab = app.buttons["tab.calendar"]
        calendarTab.tap()
        XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 5))
        XCTAssertTrue(calendarTab.isSelected)
        XCTAssertFalse(tasksTab.isSelected)

        app.buttons["createTask"].tap()
        XCTAssertTrue(app.navigationBars["Neue Aufgabe"].waitForExistence(timeout: 5))

        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Neue Aufgabe"].exists)
        XCTAssertTrue(calendarTab.isSelected)
    }
}
