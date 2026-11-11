import XCTest

/// Private Aufgaben und „zuletzt genutzte Familie“ im Formular „Neue Aufgabe“ (ADR 0012).
final class PrivateTaskUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", scenario]
        app.launch()
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 10))
        return app
    }

    /// Menüeintrag (Knopf, Schalter oder Auswahl – je nach Darstellung des Systemmenüs).
    @MainActor
    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func chooseFromScopeMenu(_ app: XCUIApplication, _ label: String) {
        let scope = app.buttons["editor.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.tap()
        let item = menuItem(app, label)
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Menüeintrag „\(label)“ fehlt")
        item.tap()
    }

    @MainActor
    func testCreatePrivateTaskNeedsNoAssigneeAndShowsLock() {
        let app = launch(scenario: "ready")
        app.buttons["createTask"].tap()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        // Eine Familie: ruhiges Element mit dem Namen; die Zuweisung ist noch sichtbar.
        let scope = app.buttons["editor.scope"]
        XCTAssertTrue(scope.exists)
        XCTAssertEqual(scope.label, "Familie: Familie Kohrs")
        XCTAssertTrue(app.buttons["editor.assignee.Anna"].exists)

        chooseFromScopeMenu(app, "Nur für mich (privat)")
        XCTAssertEqual(app.buttons["editor.scope"].label, "Nur für mich, privat")
        // Privat: keine Zuweisung, keine Erledigungsart.
        XCTAssertTrue(app.buttons["editor.assignee.Anna"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.mode.any_one"].exists)

        title.tap()
        title.typeText("Geschenk für Papa")
        app.buttons["editor.save"].tap()

        // Ohne Person und Erledigungsart gespeichert; in der Liste mit Schloss („Privat“).
        let row = app.buttons["task.open.Geschenk für Papa"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.images["Privat"].exists || row.descendants(matching: .any)["Privat"].exists)

        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["task.private"].waitForExistence(timeout: 5))
        // Beim Bearbeiten ist „Privat“ nur Anzeige.
        app.buttons["task.edit"].tap()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.scope"].exists)
        XCTAssertFalse(app.buttons["editor.assignee.Anna"].exists)
    }

    @MainActor
    func testNewTaskPreselectsLastUsedFamily() {
        let app = launch(scenario: "showcase")
        app.buttons["createTask"].tap()
        let scope = app.buttons["editor.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))

        // Zwei Familien: „In …“ zeigt die vorgewählte; die andere wählen und eine Aufgabe anlegen.
        let first = scope.label.replacingOccurrences(of: "Familie: ", with: "")
        let other = first == "Familie Berger" ? "Oma & Opa" : "Familie Berger"
        chooseFromScopeMenu(app, other)
        XCTAssertEqual(app.buttons["editor.scope"].label, "Familie: \(other)")
        chooseFromScopeMenu(app, "Nur für mich (privat)")

        let title = app.textFields["editor.title"]
        title.tap()
        title.typeText("Merkzettel")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["task.open.Merkzettel"].waitForExistence(timeout: 5))

        // Beim nächsten Mal ist diese Familie vorgewählt (Privat gilt nur für die eine Aufgabe).
        app.buttons["createTask"].tap()
        let again = app.buttons["editor.scope"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.label, "Familie: \(other)")
    }
}
