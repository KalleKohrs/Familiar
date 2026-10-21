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
        // Die App springt zur ersten fehlenden Angabe und markiert sie direkt am Abschnitt.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Bitte weise mindestens eine Person zu'")).firstMatch.waitForExistence(timeout: 5))

        app.buttons["editor.assignee.Anna"].firstMatch.tap()
        app.swipeUp()
        app.buttons["editor.mode.any_one"].firstMatch.tap()
        app.buttons["editor.save"].tap()

        XCTAssertTrue(app.buttons["task.open.Blumen gießen"].waitForExistence(timeout: 5))
        // Undatierte Aufgaben: die neueste steht ganz oben.
        let newest = app.buttons["task.open.Blumen gießen"].frame.minY
        XCTAssertLessThan(newest, app.buttons["task.open.Müll rausbringen"].frame.minY)
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
        XCTAssertTrue(app.buttons["task.open.Müll rausbringen"].waitForNonExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.buttons["task.open.Müll rausbringen"].waitForExistence(timeout: 5))
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
        app.buttons["task.open.Zimmer aufräumen"].tap()

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
        let confirm = app.buttons["delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["banner.undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task.open.Zimmer gründlich aufräumen"].exists)
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
        XCTAssertTrue(app.buttons["task.open.Müll rausbringen"].waitForNonExistence(timeout: 5))

        app.buttons["tab.history"].tap()
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Noch 30 Tage im Verlauf"].exists || app.staticTexts["Noch 29 Tage im Verlauf"].exists)

        app.buttons["history.restore.Müll rausbringen"].tap()
        XCTAssertTrue(app.staticTexts["Müll rausbringen"].waitForNonExistence(timeout: 5))

        app.buttons["tab.tasks"].tap()
        XCTAssertTrue(app.buttons["task.open.Müll rausbringen"].waitForExistence(timeout: 5))
    }
}

/// Wiederholungen: Serie anlegen, ganze Serie löschen und aus dem Verlauf wiederherstellen.
final class RecurrenceUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDailySeriesCanBeDeletedAndRestoredAsOneEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", "ready"]
        app.launch()
        XCTAssertTrue(app.buttons["createTask"].waitForExistence(timeout: 10))
        app.buttons["createTask"].tap()

        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Blumen gießen")

        app.buttons["editor.repeat"].firstMatch.tap()
        let daily = app.buttons["Täglich"].firstMatch
        XCTAssertTrue(daily.waitForExistence(timeout: 5))
        daily.tap()

        app.buttons["editor.assignee.Kalle"].firstMatch.tap()
        app.swipeUp()
        app.buttons["editor.mode.any_one"].firstMatch.tap()
        app.buttons["editor.save"].tap()

        // Heute und das nächste künftige Vorkommen.
        let occurrences = app.buttons.matching(identifier: "task.open.Blumen gießen")
        XCTAssertTrue(occurrences.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(occurrences.count, 2)

        occurrences.firstMatch.tap()
        XCTAssertTrue(app.buttons["task.edit"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["Aufgabe löschen"].tap()
        let wholeSeries = app.buttons["delete.series"].firstMatch
        XCTAssertTrue(wholeSeries.waitForExistence(timeout: 5))
        wholeSeries.tap()
        XCTAssertTrue(occurrences.firstMatch.waitForNonExistence(timeout: 5))

        // Ein Eintrag für die ganze Serie, nicht zwei einzelne.
        app.buttons["tab.history"].tap()
        let restore = app.buttons["history.restoreSeries.Blumen gießen"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["history.restore.Blumen gießen"].exists)
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5))

        app.buttons["tab.tasks"].tap()
        XCTAssertTrue(occurrences.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(occurrences.count, 2)
    }
}

/// Kalender: Tag wählen zeigt dessen Aufgaben; Monat wechseln.
final class CalendarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSelectingTomorrowShowsItsTasksAndMonthsCanChange() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", "ready"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.calendar"].waitForExistence(timeout: 10))
        app.buttons["tab.calendar"].tap()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let parts = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        let id = String(format: "calendar.day.%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)

        let cell = app.buttons[id]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.buttons["calendar.task.Arzttermin Anna"].waitForExistence(timeout: 5))

        app.buttons["calendar.next"].tap()
        XCTAssertTrue(app.buttons["calendar.today"].waitForExistence(timeout: 5))
        app.buttons["calendar.today"].tap()
        XCTAssertTrue(app.buttons["calendar.today"].waitForNonExistence(timeout: 5))
    }
}
