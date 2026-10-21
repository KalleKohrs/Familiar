import XCTest

/// Anmeldung und Onboarding mit dem In-Memory-Backend (ohne Netzwerk, Code 123456).
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInProfileCreateFamilyInviteAndSignOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend"]
        app.launch()

        // Anmeldung: E-Mail, dann zuerst ein falscher Code.
        let email = app.textFields["signIn.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("kalle@example.test")
        app.buttons["signIn.send"].tap()

        let code = app.textFields["code.field"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.typeText("000000")
        app.buttons["code.submit"].tap()
        XCTAssertTrue(app.staticTexts["Der Code ist falsch oder abgelaufen. Fordere bei Bedarf einen neuen an."].waitForExistence(timeout: 5))

        code.clearAndType("123456")
        app.buttons["code.submit"].tap()

        // Profil: Name aus der E-Mail vorbelegt, wird geändert.
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "kalle")
        name.clearAndType("Kalle")
        app.buttons["profile.continue"].tap()

        // Familie erstellen.
        let create = app.buttons["family.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let familyName = app.textFields["createFamily.name"]
        XCTAssertTrue(familyName.waitForExistence(timeout: 5))
        familyName.tap()
        familyName.typeText("Familie Kohrs")
        app.buttons["Himmel"].tap()
        app.buttons["createFamily.submit"].tap()

        // Hauptansicht mit Familie im Kopf.
        XCTAssertTrue(app.buttons["tab.tasks"].waitForExistence(timeout: 5))
        let header = app.buttons["header.family"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "Familie Kohrs, Familien verwalten")

        // Einladungscode erstellen.
        header.tap()
        app.buttons["Familie Kohrs, 1 Mitglied"].firstMatch.tap()
        app.buttons["familyDetail.invite"].tap()
        XCTAssertTrue(app.staticTexts["invite.code"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Fertig"].tap()

        // Abmelden führt zurück zur Anmeldung.
        app.buttons["header.profile"].tap()
        let signOut = app.buttons["profile.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        XCTAssertTrue(app.textFields["signIn.email"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testJoinWithCode() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend"]
        app.launch()

        let email = app.textFields["signIn.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("anna@example.test")
        app.buttons["signIn.send"].tap()
        let code = app.textFields["code.field"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.typeText("123456")
        app.buttons["code.submit"].tap()

        XCTAssertTrue(app.buttons["profile.continue"].waitForExistence(timeout: 5))
        app.buttons["profile.continue"].tap()

        app.buttons["family.join"].tap()
        let invite = app.textFields["joinFamily.code"]
        XCTAssertTrue(invite.waitForExistence(timeout: 5))
        invite.tap()
        invite.typeText("zzzz-zzzz")
        app.buttons["joinFamily.submit"].tap()
        XCTAssertTrue(app.staticTexts["Dieser Einladungscode ist ungültig."].waitForExistence(timeout: 5))

        invite.clearAndType("test-2345")
        app.buttons["joinFamily.submit"].tap()
        XCTAssertTrue(app.buttons["header.family"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["header.family"].label, "Familie Beispiel, Familien verwalten")
    }

    /// Einladungslink vor der Anmeldung geöffnet: bleibt vorgemerkt und wird nach dem Profil erfragt.
    @MainActor
    func testInviteLinkOpenedBeforeSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-FamiliarInMemoryBackend", "-FamiliarOpenURL", "https://familiar-app.de/join/TEST-2345"]
        app.launch()

        let email = app.textFields["signIn.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("ben@example.test")
        app.buttons["signIn.send"].tap()
        let code = app.textFields["code.field"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.typeText("123456")
        app.buttons["code.submit"].tap()

        XCTAssertTrue(app.buttons["profile.continue"].waitForExistence(timeout: 5))
        app.buttons["profile.continue"].tap()

        XCTAssertTrue(app.staticTexts["Familie beitreten?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Code T E S T 2 3 4 5"].exists)
        app.buttons["invite.join"].tap()
        XCTAssertTrue(app.buttons["header.family"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["header.family"].label, "Familie Beispiel, Familien verwalten")
    }
}

extension XCUIElement {
    /// Leert ein Textfeld und tippt neuen Text.
    func clearAndType(_ text: String) {
        // Ans Ende des Textes tippen, damit das Löschen den ganzen Inhalt erfasst
        // (bei mehrzeiligen Feldern landet der Cursor sonst mitten im Text).
        tap()
        coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
