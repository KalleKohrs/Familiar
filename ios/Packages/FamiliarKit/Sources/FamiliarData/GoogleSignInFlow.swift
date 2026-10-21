import FamiliarCore
import Foundation
import GoogleSignIn
import SwiftUI
import UIKit

/// Native Google-Anmeldung (GoogleSignIn-iOS), danach `AuthService.signInWithGoogle`.
/// Konfiguration aus der Info.plist: `GIDClientID` (iOS-Client) und `GIDServerClientID` (Web-Client,
/// Zielgruppe des ID-Tokens für Supabase); der umgekehrte iOS-Client als URL-Schema.
public enum GoogleSignInFlow {
    /// Ob die Client-IDs eingetragen sind (sonst wird kein Google-Knopf angezeigt).
    public static var isConfigured: Bool {
        let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        return id.hasSuffix(".apps.googleusercontent.com")
    }

    /// Google-Anmeldung zeigen. `hashedNonce` landet im ID-Token, Supabase prüft es gegen den Klartext.
    @MainActor
    public static func signIn(presenting viewController: UIViewController,
                              hashedNonce: String) async throws -> (idToken: String, accessToken: String) {
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController, hint: nil, additionalScopes: nil, nonce: hashedNonce)
        guard let idToken = result.user.idToken?.tokenString else { throw FamiliarError.unknown(message: "Kein ID-Token von Google") }
        return (idToken, result.user.accessToken.tokenString)
    }

    /// Rücksprung von Google (URL-Schema des iOS-Clients); `true`, wenn die URL zu Google gehörte.
    @MainActor
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// Abgebrochen durch die Person – keine Fehlermeldung nötig.
    public static func isCancellation(_ error: any Error) -> Bool {
        (error as NSError).domain == kGIDSignInErrorDomain && (error as NSError).code == GIDSignInError.canceled.rawValue
    }

    /// Beim Abmelden auch die Google-Sitzung im Gerät vergessen.
    @MainActor
    public static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
}

/// Anmelde-Knopf in Form und Höhe des Apple-Knopfs: weiße Kapsel mit dem offiziellen „G“ aus dem
/// GoogleSignIn-Paket (Googles Branding-Richtlinien erlauben die Kapselform mit diesem Logo).
public struct GoogleSignInButtonView: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let logo = Self.logo {
                    Image(uiImage: logo)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }
                Text("Mit Google anmelden")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color(white: 0.12))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(.white))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Das G-Logo liegt im Ressourcen-Bündel des GoogleSignIn-Pakets.
    private static let logo: UIImage? = {
        guard let url = Bundle.main.url(forResource: "GoogleSignIn_GoogleSignIn", withExtension: "bundle"),
              let bundle = Bundle(url: url) else { return nil }
        return UIImage(named: "google", in: bundle, compatibleWith: nil)
    }()
}
