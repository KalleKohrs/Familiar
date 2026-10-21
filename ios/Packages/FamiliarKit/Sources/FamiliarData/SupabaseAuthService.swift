import FamiliarCore
import Foundation
import Supabase

/// Anmeldung per 6-stelligem E-Mail-Code (`signInWithOTP` + `verifyOTP(type: .email)`).
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
        _ = try await perform {
            try await client.auth.verifyOTP(email: InputRules.trimmed(email), token: InputRules.trimmed(code), type: .email)
        }
    }

    func deleteAccount() async throws(FamiliarError) {
        // Die Function prüft das mitgeschickte Nutzer-JWT und löscht serverseitig (Migration 0010).
        _ = try await perform {
            try await client.functions.invoke("account-delete", options: FunctionInvokeOptions(method: .post))
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
