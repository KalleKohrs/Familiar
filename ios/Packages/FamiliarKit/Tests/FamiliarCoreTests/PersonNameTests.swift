import Testing
@testable import FamiliarCore

struct PersonNameTests {
    @Test(arguments: [
        ("Anna Schmidt", "AS"),
        ("anna", "A"),
        ("Jean-Luc Picard", "JL"),
        ("  Ölf  Über  Drei ", "ÖÜ"),
        ("", "?"),
        ("   ", "?"),
    ])
    func initials(name: String, expected: String) {
        #expect(PersonName.initials(from: name) == expected)
    }
}
