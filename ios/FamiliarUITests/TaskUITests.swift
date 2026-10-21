import XCTest

/// Aufgaben mit dem In-Memory-Backend (Szenario „ready“: Kalle und Anna in „Familie Kohrs“,
/// Aufgaben „Müll rausbringen“ und „Zimmer aufräumen“).
final class TaskUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", "ready"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testCreateTaskRequiresModeAndAppearsInList() {
        let app = launch()
        app.buttons["createTask"].tap()

        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Blumen gießen")

        // Ohne Person und Erledigungsart wird nicht gespeichert.
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Noch offen'")).firstMatch.waitForExistence(timeout: 5))

        app.buttons["editor.assignee.Anna"].firstMatch.tap()
        app.swipeUp()
        app.buttons["editor.mode.any_one"].firstMatch.tap()
        app.buttons["editor.save"].tap()

        XCTAssertTrue(app.staticTexts["Blumen gießen"].waitForExistence(timeout: 5))
        // Undatierte Aufgaben: die neueste steht ganz oben.
        let newest = app.staticTexts["Blumen gießen"].frame.minY
        XCTAssertLessThan(newest, app.staticTexts["Müll rausbringen"].frame.minY)
    }

    @MainActor
    func testCompleteAndUndo() {
        let app = launch()
        let check = app.buttons["Müll rausbringen abhaken"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()

        // „Eine Person für alle“: Die Aufgabe verschwindet, der Hinweis bietet Rückgängig an.
        let undo = app.buttons["banner.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForNonExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEachModeKeepsTaskUntilEveryoneIsDone() {
        let app = launch()
        let check = app.buttons["Zimmer aufräumen abhaken"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()

        // Kalle ist fertig, Anna noch nicht: Die Aufgabe bleibt, mit Fortschritt.
        XCTAssertTrue(app.buttons["Haken bei Zimmer aufräumen zurücknehmen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 von 2 erledigt"].exists)
    }

    @MainActor
    func testDetailEditAndDelete() {
        let app = launch()
        app.staticTexts["Zimmer aufräumen"].tap()

        let edit = app.buttons["task.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.clearAndType("Zimmer gründlich aufräumen")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["Zimmer gründlich aufräumen"].waitForExistence(timeout: 5))

        app.swipeUp()
        app.buttons["Aufgabe löschen"].tap()
        app.buttons["Löschen"].firstMatch.tap()
        XCTAssertTrue(app.buttons["banner.undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Zimmer gründlich aufräumen"].exists)
    }
}

/// Verlauf: Erledigtes erscheint dort und lässt sich wiederherstellen.
final class HistoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCompletedTaskAppearsInHistoryAndCanBeRestored() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", "ready"]
        app.launch()

        let check = app.buttons["Müll rausbringen abhaken"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForNonExistence(timeout: 5))

        app.buttons["tab.history"].tap()
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Noch 30 Tage im Verlauf"].exists || app.staticTexts["Noch 29 Tage im Verlauf"].exists)

        app.buttons["history.restore.Müll rausbringen"].tap()
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForNonExistence(timeout: 5))

        app.buttons["tab.tasks"].tap()
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForExistence(timeout: 5))
    }
}
