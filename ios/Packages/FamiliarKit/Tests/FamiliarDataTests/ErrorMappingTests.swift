import FamiliarCore
import Foundation
import Supabase
import Testing
@testable import FamiliarData

struct ErrorMappingTests {
    @Test func catalogHintBecomesAppError() {
        let error = PostgrestError(hint: "last_admin", code: "P0001", message: "Die Familie braucht mindestens einen Admin.")
        #expect(FamiliarError(supabaseError: error) == .app(key: .lastAdmin, message: "Die Familie braucht mindestens einen Admin."))
    }

    @Test func notAuthenticatedHintBecomesNotAuthenticated() {
        let error = PostgrestError(hint: "not_authenticated", code: "42501", message: "Nicht angemeldet.")
        #expect(FamiliarError(supabaseError: error) == .notAuthenticated)
    }

    @Test func supabaseOwnHintIsIgnored() {
        let error = PostgrestError(
            hint: "Grant the required privileges to the current role with: GRANT …",
            code: "42501",
            message: "permission denied for function create_family"
        )
        #expect(FamiliarError(supabaseError: error) == .unknown(message: "permission denied for function create_family"))
    }

    @Test func expiredJWTBecomesNotAuthenticated() {
        #expect(FamiliarError(supabaseError: PostgrestError(code: "PGRST301", message: "JWT expired")) == .notAuthenticated)
    }

    @Test func authErrors() {
        #expect(FamiliarError(supabaseError: AuthError.sessionMissing) == .notAuthenticated)
        #expect(FamiliarError(supabaseError: apiError("otp_expired")) == .invalidEmailCode)
        #expect(FamiliarError(supabaseError: apiError("over_email_send_rate_limit")) == .emailRateLimited)
    }

    @Test func offline() {
        #expect(FamiliarError(supabaseError: URLError(.notConnectedToInternet)) == .offline)
    }

    private func apiError(_ code: String) -> AuthError {
        .api(
            message: code,
            errorCode: ErrorCode(code),
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        )
    }
}
