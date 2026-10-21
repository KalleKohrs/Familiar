import FamiliarCore
import Foundation
import Supabase

/// Anmeldung per 6-stelligem E-Mail-Code (`signInWithOTP` + `verifyOTP(type: .email)`) oder mit Apple.
/// Der Code statt eines Links funktioniert geräteübergreifend und braucht keine Universal Links;
/// dafür muss die E-Mail-Vorlage `{{ .Token }}` enthalten (docs/setup/supabase-auth.md).
final class SupabaseAuthService: AuthService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func authStates() -> AsyncStream<AuthState> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                var last: AuthState?
                for await (_, session) in changes {
                    let state: AuthState = session.map { .signedIn(userID: $0.user.id, email: $0.user.email) } ?? .signedOut
                    if state != last {
                        last = state
                        continuation.yield(state)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sendEmailCode(to email: String) async throws(FamiliarError) {
        try await perform {
            try await client.auth.signInWithOTP(email: InputRules.trimmed(email), shouldCreateUser: true)
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws(FamiliarError) {
        let address = InputRules.trimmed(email)
        let token = InputRules.trimmed(code)
        do throws(FamiliarError) {
            _ = try await perform {
                try await client.auth.verifyOTP(email: address, token: token, type: .email)
            }
        } catch {
            // Prüf-Konto für Apples App-Prüfung (Edge Function `review-sign-in`): Nur die dort
            // hinterlegte Adresse mit festem Prüf-Code erhält einen gültigen Einmal-Code.
            guard error == .invalidEmailCode,
                  let review: ReviewSignIn = try? await client.functions.invoke(
                      "review-sign-in",
                      options: FunctionInvokeOptions(method: .post, body: ["email": address, "code": token]))
            else { throw error }
            _ = try await perform {
                try await client.auth.verifyOTP(email: address, token: review.emailOTP, type: .email)
            }
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws(FamiliarError) {
        _ = try await perform {
            try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken,
                                                                                        nonce: nonce))
        }
        // Supabase-Doku: Apple liefert den Namen nur beim ersten Mal und nicht im ID-Token; als
        // Vorschlag für den Profil-Schritt in den Metadaten ablegen.
        if let fullName, !fullName.isEmpty {
            _ = try? await client.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
        }
    }

    func isLinkedToApple() async -> Bool {
        guard let user = try? await client.auth.user() else { return false }
        return user.identities?.contains { $0.provider == "apple" } ?? false
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws(FamiliarError) {
        // Die Function prüft das mitgeschickte Nutzer-JWT, widerruft ggf. die Apple-Anmeldung und
        // löscht serverseitig (Migration 0010).
        _ = try await perform {
            try await client.functions.invoke("account-delete", options: FunctionInvokeOptions(
                method: .post, body: DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode)))
        }
        // Lokale Sitzung beenden; das Konto existiert nicht mehr.
        _ = try? await client.auth.signOut(scope: .local)
    }

    func signOut(everywhere: Bool) async throws(FamiliarError) {
        // Achtung: Das SDK meldet ohne Angabe überall ab (`.global`).
        try await perform {
            try await client.auth.signOut(scope: everywhere ? .global : .local)
        }
    }
}

private struct DeleteAccountBody: Encodable {
    let appleAuthorizationCode: String?

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

private struct ReviewSignIn: Decodable {
    let emailOTP: String

    enum CodingKeys: String, CodingKey {
        case emailOTP = "email_otp"
    }
}
