import AuthenticationServices
import FamiliarCore
import FamiliarData
import FamiliarDesign
import SwiftUI

/// Anmeldung per E-Mail-Code, mit Apple oder mit Google (Plan, Abschnitt 6).
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var codeRequestedFor: String?
    @State private var appleNonce = ""
    @State private var isSigningInWithApple = false
    @State private var isSigningInWithGoogle = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FamiliarSpacing.xl) {
                    VStack(spacing: FamiliarSpacing.m) {
                        FamiliarMark(size: 76)
                            .padding(.top, FamiliarSpacing.xxl)
                        Text("Willkommen bei Familiar")
                            .font(FamiliarFont.display)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Gemeinsam den Familienalltag planen. Melde dich mit deiner E-Mail-Adresse an – du bekommst einen Code, kein Passwort nötig.")
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: FamiliarSpacing.s) {
                        TextField("E-Mail-Adresse", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .focused($emailFocused)
                            .onSubmit(send)
                            .familiarInputField()
                            .accessibilityIdentifier("signIn.email")

                        if let errorMessage {
                            FamiliarInlineError(errorMessage)
                        }

                        Button(action: send) {
                            HStack(spacing: FamiliarSpacing.xs) {
                                if isSending { ProgressView().tint(FamiliarColor.onAccent) }
                                Text("Code senden")
                            }
                        }
                        .buttonStyle(.familiarPrimary)
                        .disabled(!InputRules.isPlausibleEmail(email) || isSending)
                        .accessibilityIdentifier("signIn.send")

                        HStack(spacing: FamiliarSpacing.s) {
                            Rectangle().fill(FamiliarColor.textTertiary.opacity(0.4)).frame(height: 1)
                            Text("oder")
                                .font(FamiliarFont.meta)
                                .foregroundStyle(FamiliarColor.textSecondary)
                            Rectangle().fill(FamiliarColor.textTertiary.opacity(0.4)).frame(height: 1)
                        }
                        .accessibilityHidden(true)
                        .padding(.vertical, FamiliarSpacing.xxs)

                        SignInWithAppleButton(.signIn) { request in
                            appleNonce = AppleSignIn.makeNonce()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = AppleSignIn.sha256(appleNonce)
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        // Apple: auf hellem Grund schwarz, auf dunklem weiß.
                        .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
                        .frame(height: 50)
                        .clipShape(Capsule())
                        .disabled(isSigningInWithApple)
                        .accessibilityIdentifier("signIn.apple")

                        if GoogleSignInFlow.isConfigured {
                            GoogleSignInButtonView(action: signInWithGoogle)
                                .disabled(isSigningInWithGoogle)
                                .accessibilityIdentifier("signIn.google")
                        }

                        // Rechtstexte schon vor der Anmeldung erreichbar (§ 5 DDG, App-Store-Richtlinie 5.1.1).
                        Text(legalNotice)
                            .font(FamiliarFont.meta)
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .tint(FamiliarColor.accent)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, FamiliarSpacing.xs)
                    }
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.bottom, FamiliarSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .familiarScreenBackground()
            .announcesChanges(of: errorMessage)
            .navigationDestination(item: $codeRequestedFor) { email in
                EmailCodeView(email: email)
            }
        }
    }

    private var legalNotice: AttributedString {
        let markdown = String(localized: "Mit der Anmeldung gelten die [Nutzungsbedingungen](\(LegalLink.terms.absoluteString)).\n[Datenschutz](\(LegalLink.privacy.absoluteString)) · [Impressum](\(LegalLink.imprint.absoluteString))")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    private func send() {
        guard InputRules.isPlausibleEmail(email), !isSending else { return }
        let address = InputRules.trimmed(email)
        isSending = true
        errorMessage = nil
        Task {
            defer { isSending = false }
            do throws(FamiliarError) {
                try await session.dependencies.auth.sendEmailCode(to: address)
                emailFocused = false
                codeRequestedFor = address
            } catch {
                errorMessage = error.message
            }
        }
    }
}

extension SignInView {
    private func signInWithGoogle() {
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        // Den obersten sichtbaren Controller nehmen (die Anmeldung kann in einem Sheet liegen).
        var top = presenter
        while let presented = top.presentedViewController { top = presented }
        let nonce = AppleSignIn.makeNonce()
        isSigningInWithGoogle = true
        errorMessage = nil
        Task {
            defer { isSigningInWithGoogle = false }
            do {
                let tokens = try await GoogleSignInFlow.signIn(presenting: top, hashedNonce: AppleSignIn.sha256(nonce))
                try await session.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken, nonce: nonce)
            } catch let error as FamiliarError {
                errorMessage = error.message
            } catch {
                if !GoogleSignInFlow.isCancellation(error) {
                    errorMessage = String(localized: "Die Anmeldung mit Google hat nicht geklappt. Bitte versuche es erneut.")
                }
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let error):
            // Abbrechen ist keine Fehlermeldung wert.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = String(localized: "Die Anmeldung mit Apple hat nicht geklappt. Bitte versuche es erneut.")
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let idToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
                errorMessage = String(localized: "Die Anmeldung mit Apple hat nicht geklappt. Bitte versuche es erneut.")
                return
            }
            let nonce = appleNonce
            let name = AppleSignIn.displayName(from: credential.fullName)
            isSigningInWithApple = true
            errorMessage = nil
            Task {
                defer { isSigningInWithApple = false }
                do throws(FamiliarError) {
                    try await session.signInWithApple(idToken: idToken, nonce: nonce, fullName: name)
                } catch {
                    errorMessage = error.message
                }
            }
        }
    }
}

/// Eingabe des Codes aus der E-Mail. Nach erfolgreicher Prüfung wechselt die App von selbst,
/// weil der Anmeldestatus `signedIn` meldet.
struct EmailCodeView: View {
    @Environment(SessionStore.self) private var session
    let email: String

    @State private var code = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var resendAvailableAt = Date.now.addingTimeInterval(60)
    @State private var infoMessage: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.m) {
                Text("Code eingeben")
                    .font(FamiliarFont.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Wir haben einen Code an \(email) geschickt. Schau auch im Spam-Ordner nach.")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)

                TextField("Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .focused($codeFocused)
                    .familiarInputField()
                    .accessibilityIdentifier("code.field")

                if let errorMessage {
                    FamiliarInlineError(errorMessage)
                }

                Button(action: verify) {
                    HStack(spacing: FamiliarSpacing.xs) {
                        if isVerifying { ProgressView().tint(FamiliarColor.onAccent) }
                        Text("Anmelden")
                    }
                }
                .buttonStyle(.familiarPrimary)
                .disabled(!InputRules.isPlausibleEmailCode(code) || isVerifying)
                .accessibilityIdentifier("code.submit")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up))
                    Button(remaining > 0 ? "Neuen Code senden (in \(remaining) s)" : "Neuen Code senden", action: resend)
                        .buttonStyle(.familiarSecondary)
                        .disabled(remaining > 0)
                }

                if let infoMessage {
                    Text(infoMessage)
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                }
            }
            .padding(FamiliarSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .familiarScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: errorMessage)
        .announcesChanges(of: infoMessage)
        .onAppear { codeFocused = true }
    }

    private func verify() {
        guard InputRules.isPlausibleEmailCode(code), !isVerifying else { return }
        isVerifying = true
        errorMessage = nil
        Task {
            defer { isVerifying = false }
            do throws(FamiliarError) {
                try await session.dependencies.auth.verifyEmailCode(code, email: email)
            } catch {
                errorMessage = error.message
            }
        }
    }

    private func resend() {
        resendAvailableAt = .now.addingTimeInterval(60)
        errorMessage = nil
        infoMessage = nil
        Task {
            do throws(FamiliarError) {
                try await session.dependencies.auth.sendEmailCode(to: email)
                infoMessage = String(localized: "Neuer Code ist unterwegs.")
            } catch {
                errorMessage = error.message
            }
        }
    }
}
