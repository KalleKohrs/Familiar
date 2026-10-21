import AuthenticationServices
import CryptoKit
import Foundation

/// Hilfen für „Mit Apple anmelden“ (Apple: „Implementing User Authentication with Sign in with Apple“).
enum AppleSignIn {
    /// Zufällige Nonce; in die Anfrage kommt ihr SHA-256-Hash, an Supabase der Klartext.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Name aus der ersten Anmeldung, z. B. „Anna Kohrs“.
    static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
    }
}

/// Erneute Bestätigung mit Apple vor dem Löschen des Kontos. Liefert einen frischen
/// Autorisierungscode, mit dem der Server die Apple-Anmeldung widerruft (Apple TN3194).
@MainActor
final class AppleReauthorization: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, any Error>?

    func authorizationCode() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            if let code {
                continuation?.resume(returning: code)
            } else {
                continuation?.resume(throwing: ASAuthorizationError(.invalidResponse))
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            // Aufruf nur aus dem sichtbaren Profil – eine Szene gibt es dann immer.
            guard let scene = scenes.first else { preconditionFailure("Keine Fensterszene für Apple-Bestätigung") }
            return ASPresentationAnchor(windowScene: scene)
        }
    }
}
