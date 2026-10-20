import XCTest

/// Der Plus-Button neben der Leiste öffnet „Neue Aufgabe“, ohne den aktiven Bereich zu wechseln.
final class PlusTabUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPlusButtonOpensSheetAndKeepsSelectedTab() {
        let app = XCUIApplication()
        app.launch()

        let tasksTab = app.buttons["Aufgaben"]
        XCTAssertTrue(tasksTab.waitForExistence(timeout: 10))
        XCTAssertTrue(tasksTab.isSelected)

        let calendarTab = app.buttons["Kalender"]
        calendarTab.tap()
        XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 5))
        XCTAssertTrue(calendarTab.isSelected)
        XCTAssertFalse(tasksTab.isSelected)

        app.buttons["Neue Aufgabe"].tap()
        XCTAssertTrue(app.navigationBars["Neue Aufgabe"].waitForExistence(timeout: 5))

        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Neue Aufgabe"].exists)
        XCTAssertTrue(calendarTab.isSelected)
    }
}
