import Foundation
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

struct InviteLinkTests {
    @Test func roundTrip() throws {
        let url = try #require(InviteLink.url(for: "abcd efgh"))
        #expect(url.absoluteString == "https://familiar-app.de/join/ABCD-EFGH")
        #expect(InviteLink.code(from: url) == "ABCDEFGH")
    }

    @Test func acceptsVariants() throws {
        #expect(InviteLink.code(from: try #require(URL(string: "https://www.familiar-app.de/join/abcdefgh/"))) == "ABCDEFGH")
        #expect(InviteLink.code(from: try #require(URL(string: "https://familiar-app.de/JOIN/ABCD-EFGH?x=1"))) == "ABCDEFGH")
    }

    @Test func rejectsOtherURLs() throws {
        for string in ["https://example.com/join/ABCDEFGH", "http://familiar-app.de/join/ABCDEFGH",
                       "https://familiar-app.de/join/ABC", "https://familiar-app.de/datenschutz",
                       "familiar://outlook?status=ok", "https://familiar-app.de/join/ABCDEFGH/extra"] {
            #expect(InviteLink.code(from: try #require(URL(string: string))) == nil)
        }
        #expect(InviteLink.url(for: "zu kurz") == nil)
    }
}
