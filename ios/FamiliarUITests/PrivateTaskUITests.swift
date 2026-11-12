import XCTest

/// Private Aufgaben und „zuletzt genutzte Familie“ im Formular „Neue Aufgabe“ (ADR 0012).
final class PrivateTaskUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(scenario: String, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", scenario,
                               "-appearance", appearance]
        app.launch()
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 10))
        return app
    }

    /// Bild für die Sichtprüfung (bleibt im Testergebnis).
    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Die Familien-Zeile steht über den Bildern, also unten im Formular: bei Bedarf hinscrollen.
    @MainActor
    private func scopeButton(_ app: XCUIApplication) -> XCUIElement {
        let scope = app.buttons["editor.scope"]
        _ = scope.waitForExistence(timeout: 5)
        var swipes = 0
        while !(scope.exists && scope.isHittable) && swipes < 5 {
            dragForm(app, up: true)
            swipes += 1
        }
        return scope
    }

    /// Nach dem Hinscrollen zur Familien-Zeile wieder nach oben, damit das Titelfeld antippbar ist.
    @MainActor
    private func scrollToTitle(_ app: XCUIApplication) {
        let title = app.textFields["editor.title"]
        var swipes = 0
        while !(title.exists && title.isHittable) && swipes < 5 {
            dragForm(app, up: false)
            swipes += 1
        }
    }

    /// Das Formular per Ziehen scrollen (bei geöffneter Tastatur läge der Start unter ihr).
    @MainActor
    private func dragForm(_ app: XCUIApplication, up: Bool) {
        // Die Tastatur verdeckt den unteren Teil des Formulars: erst schließen.
        if app.keyboards.firstMatch.exists, app.buttons["Fertig"].exists {
            app.buttons["Fertig"].tap()
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        let form = app.collectionViews.firstMatch
        let from = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.3))
        let to = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.2 : 0.8))
        from.press(forDuration: 0.1, thenDragTo: to)
    }

    /// Menüeintrag (Knopf, Schalter oder Auswahl – je nach Darstellung des Systemmenüs).
    @MainActor
    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        if button.waitForExistence(timeout: 3) { return button }
        return app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// Wartet, bis das Element den Text trägt (das Menü schließt mit einer kurzen Animation).
    @MainActor
    private func assertScope(_ app: XCUIApplication, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let scope = scopeButton(app)
        let predicate = NSPredicate(format: "label == %@", expected)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: scope)], timeout: 5)
        XCTAssertEqual(result, .completed, "Chip zeigt „\(scope.label)“ statt „\(expected)“", file: file, line: line)
    }

    @MainActor
    private func chooseFromScopeMenu(_ app: XCUIApplication, _ label: String) {
        let scope = scopeButton(app)
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
        XCTAssertTrue(app.buttons["editor.assignee.Anna"].exists)
        let scope = scopeButton(app)
        XCTAssertTrue(scope.exists)
        XCTAssertEqual(scope.label, "Familie: Familie Lindner")

        chooseFromScopeMenu(app, "Nur für mich (privat)")
        assertScope(app, "Nur für mich, privat")
        // Privat: keine Zuweisung, keine Erledigungsart.
        XCTAssertTrue(app.buttons["editor.assignee.Anna"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.mode.any_one"].exists)

        // Zurück zu „Familie“ muss gehen (früher blieb das Menü in „privat“ hängen) – und wieder hin.
        chooseFromScopeMenu(app, "Familie Lindner")
        assertScope(app, "Familie: Familie Lindner")
        // Die Zuweisung steht weiter oben: hinaufscrollen.
        for _ in 0..<3 where !app.buttons["editor.assignee.Anna"].exists { dragForm(app, up: false) }
        XCTAssertTrue(app.buttons["editor.assignee.Anna"].waitForExistence(timeout: 5))
        chooseFromScopeMenu(app, "Nur für mich (privat)")
        assertScope(app, "Nur für mich, privat")

        scrollToTitle(app)
        title.tap()
        title.typeText("Geschenk für Papa")
        shot(app, "10-formular-privat")
        app.buttons["editor.save"].tap()

        // Ohne Person und Erledigungsart gespeichert; in der Liste mit Schloss („Privat“).
        let row = app.buttons["task.open.Geschenk für Papa"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.images["Privat"].exists || row.descendants(matching: .any)["Privat"].exists)

        shot(app, "11-liste-mit-schloss")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["task.private"].waitForExistence(timeout: 5))
        shot(app, "12-details-privat")
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
        let scope = scopeButton(app)
        XCTAssertTrue(scope.waitForExistence(timeout: 5))

        // Zwei Familien: „In …“ zeigt die vorgewählte; die andere wählen und eine Aufgabe anlegen.
        let first = scope.label.replacingOccurrences(of: "Familie: ", with: "")
        let other = first == "Familie Berger" ? "Oma & Opa" : "Familie Berger"
        chooseFromScopeMenu(app, other)
        assertScope(app, "Familie: \(other)")
        chooseFromScopeMenu(app, "Nur für mich (privat)")

        let title = app.textFields["editor.title"]
        scrollToTitle(app)
        title.tap()
        title.typeText("Merkzettel")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["task.open.Merkzettel"].waitForExistence(timeout: 5))

        // Beim nächsten Mal ist diese Familie vorgewählt (Privat gilt nur für die eine Aufgabe).
        app.buttons["createTask"].tap()
        let again = scopeButton(app)
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        assertScope(app, "Familie: \(other)")
    }

    @MainActor
    func testScreenshotsDark() {
        let app = launch(scenario: "showcase", appearance: "dark")
        app.buttons["createTask"].tap()
        XCTAssertTrue(scopeButton(app).waitForExistence(timeout: 5))
        shot(app, "20-formular-dunkel")
        scopeButton(app).tap()
        XCTAssertTrue(menuItem(app, "Nur für mich (privat)").waitForExistence(timeout: 5))
        shot(app, "21-menue-dunkel")
        menuItem(app, "Nur für mich (privat)").tap()
        assertScope(app, "Nur für mich, privat")
        let title = app.textFields["editor.title"]
        scrollToTitle(app)
        title.tap()
        title.typeText("Geschenk für Papa")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["task.open.Geschenk für Papa"].waitForExistence(timeout: 5))
        shot(app, "22-liste-dunkel")
    }
}
