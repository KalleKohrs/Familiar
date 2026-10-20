import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Anmeldung per E-Mail-Code (Plan, Abschnitt 6). Google und Apple folgen in Phase 2b/2c.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var codeRequestedFor: String?
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FamiliarSpacing.xl) {
                    VStack(spacing: FamiliarSpacing.m) {
                        FamiliarOrb(diameter: 88)
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
