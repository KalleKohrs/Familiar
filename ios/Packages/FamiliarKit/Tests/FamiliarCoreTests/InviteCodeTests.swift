import Testing
@testable import FamiliarCore

struct InviteCodeTests {
    @Test(arguments: [
        ("abcd-efgh", "ABCDEFGH"),
        (" 7k3m 9p2q ", "7K3M9P2Q"),
        ("O0IL-1lio", "00111110"),
    ])
    func normalizesLikeServer(input: String, expected: String) {
        #expect(InviteCode.normalize(input) == expected)
    }

    @Test func acceptsEightCrockfordCharacters() {
        #expect(InviteCode.isValid("7K3M-9P2Q"))
        #expect(InviteCode.isValid("o1lI-2345"))
    }

    @Test(arguments: ["", "ABC", "ABCDEFGHJ", "ABCD-EFGU", "ÄBCDEFGH"])
    func rejectsInvalidCodes(_ input: String) {
        #expect(!InviteCode.isValid(input))
    }

    @Test func formatsWithHyphen() {
        #expect(InviteCode.formatted("7k3m9p2q") == "7K3M-9P2Q")
        #expect(InviteCode.formatted("kurz") == "kurz")
    }
}
