import Testing
@testable import FamiliarCore

struct InputRulesTests {
    @Test func familyNameIsTrimmedAndLimited() {
        #expect(InputRules.isValidFamilyName("  Familie Lindner  "))
        #expect(!InputRules.isValidFamilyName("   "))
        #expect(InputRules.isValidFamilyName(String(repeating: "a", count: 60)))
        #expect(!InputRules.isValidFamilyName(String(repeating: "a", count: 61)))
    }

    @Test func displayNameIsTrimmedAndLimited() {
        #expect(InputRules.isValidDisplayName("Kalle"))
        #expect(!InputRules.isValidDisplayName(""))
        #expect(!InputRules.isValidDisplayName(String(repeating: "a", count: 81)))
    }

    @Test(arguments: ["kalle@example.de", " anna.b+test@mail.example.com "])
    func plausibleEmails(_ email: String) {
        #expect(InputRules.isPlausibleEmail(email))
    }

    @Test(arguments: ["", "kalle", "kalle@", "@example.de", "kalle@example", "ka lle@example.de", "a@b@c.de", "kalle@.de"])
    func implausibleEmails(_ email: String) {
        #expect(!InputRules.isPlausibleEmail(email))
    }

    @Test func emailCodesHaveSixToTenDigits() {
        #expect(InputRules.isPlausibleEmailCode("123456"))
        #expect(InputRules.isPlausibleEmailCode(" 12345678 "))
        #expect(!InputRules.isPlausibleEmailCode("12345"))
        #expect(!InputRules.isPlausibleEmailCode("12345a"))
        #expect(!InputRules.isPlausibleEmailCode("١٢٣٤٥٦"))
    }
}
