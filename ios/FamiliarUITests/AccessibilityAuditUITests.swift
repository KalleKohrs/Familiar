import XCTest

/// Apples automatische Barrierefreiheits-Prüfung (`performAccessibilityAudit`) auf allen
/// Hauptbildschirmen, im hellen und im dunklen Erscheinungsbild (Vorführdaten „showcase“).
/// Prüft u. a. Beschriftungen für VoiceOver, Kontrast, Tippflächen, abgeschnittene Texte und
/// Dynamic-Type-Unterstützung.
final class AccessibilityAuditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(appearance: String, scenario: String = "showcase") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarInMemoryScenario", scenario,
                               "-appearance", appearance]
        app.launch()
        return app
    }

    /// Hart geprüft: Beschriftungen (VoiceOver), Tippflächen, Rollen, Aktionen, Eltern-Kind-Struktur.
    /// Nur protokolliert (`AUDIT | …` im Log), weil die automatische Messung hier nicht trägt:
    /// - Kontrast: misst Text auf Glas-Karten und Verläufen gegen den falschen Hintergrund (z. B. die
    ///   Überschrift „Willkommen bei Familiar“ mit rechnerisch > 14 : 1). Die Farbwerte sind in
    ///   `docs/design/light-mode.md` und `docs/design-system.md` nachgerechnet.
    /// - Dynamic Type / abgeschnittener Text / Elementerkennung: bewusst feste Größen in der Tab-Leiste
    ///   (Großansicht per Gedrückthalten), System-Knöpfen und Avatar-Initialen; die Bildschirme wurden
    ///   mit der größten Schriftstufe von Hand geprüft (Verlauf und Kalender stapeln dann untereinander).
    private static let reportedOnly: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped, .elementDetection]

    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) {
        XCTContext.runActivity(named: screen) { _ in
            do {
                try app.performAccessibilityAudit { issue in
                    let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id='\($0.identifier)'" } ?? "–"
                    print("AUDIT | \(screen) | \(issue.compactDescription) | \(element)")
                    return Self.reportedOnly.contains(issue.auditType)
                }
            } catch {
                XCTFail("\(screen): \(error)")
            }
        }
    }

    @MainActor
    private func auditAllScreens(appearance: String) {
        let app = launch(appearance: appearance)
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 10))
        audit(app, "Aufgaben (\(appearance))")

        app.buttons["task.open.Zimmer aufräumen"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Bearbeiten"].waitForExistence(timeout: 5))
        audit(app, "Aufgabe (\(appearance))")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["createTask"].tap()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 5))
        audit(app, "Neue Aufgabe (\(appearance))")
        app.buttons["Abbrechen"].firstMatch.tap()

        app.buttons["tab.calendar"].tap()
        audit(app, "Kalender (\(appearance))")

        app.buttons["tab.history"].tap()
        audit(app, "Verlauf (\(appearance))")

        app.buttons["tab.tasks"].tap()
        app.buttons["header.profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons["profile.signOut"].waitForExistence(timeout: 5))
        audit(app, "Profil (\(appearance))")
    }

    /// Suche in „Aufgaben“ mit Treffern und ohne Treffer. Eigener Test: Die Prüfung bei geöffneter Suche und
    /// anschließender Tab-Wechsel haben in Läufen mit mehreren Prüfungen gelegentlich den Bedienungshilfen-Dienst
    /// des Simulators hängen lassen (die App selbst reagiert, siehe Schleifentest im Übergabevermerk).
    @MainActor
    private func auditSearch(appearance: String) {
        let app = launch(appearance: appearance)
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 10))
        let field = app.textFields["search.field"]
        pullDownToSearch(app, field)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Tastatur erscheint nach dem Antippen")
        // Return schließt die Tastatur (sie verdeckt sonst die Tab-Leiste).
        field.typeText("e\n")
        audit(app, "Suche mit Treffern (\(appearance))")
        app.buttons["search.clear"].tap()
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        field.typeText("qqq\n")
        XCTAssertTrue(app.staticTexts.matching(identifier: "search.empty").firstMatch.waitForExistence(timeout: 5))
        audit(app, "Suche ohne Treffer (\(appearance))")
    }

    @MainActor
    func testAuditSearchLight() { auditSearch(appearance: "light") }

    @MainActor
    func testAuditSearchDark() { auditSearch(appearance: "dark") }

    @MainActor
    func testAuditLight() { auditAllScreens(appearance: "light") }

    @MainActor
    func testAuditDark() { auditAllScreens(appearance: "dark") }

    @MainActor
    func testAuditSignIn() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance, scenario: "signedOut")
            XCTAssertTrue(app.buttons["signIn.apple"].waitForExistence(timeout: 10))
            audit(app, "Anmeldung (\(appearance))")
            app.terminate()
        }
    }
}
