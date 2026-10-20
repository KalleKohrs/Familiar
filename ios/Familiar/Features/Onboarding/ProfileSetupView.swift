import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Onboarding, Schritt 1: Name und Profilbild. Der Name ist aus der Anmeldung vorbelegt.
struct ProfileSetupView: View {
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FamiliarSpacing.xl) {
                    VStack(spacing: FamiliarSpacing.xs) {
                        Text("Wie sollen dich andere sehen?")
                            .font(FamiliarFont.title)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Name und Bild sehen alle in deinen Familien. Du kannst beides später ändern.")
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, FamiliarSpacing.l)

                    AvatarEditor()
                    DisplayNameField(name: $name)

                    if let errorMessage {
                        FamiliarInlineError(errorMessage)
                    }

                    Button(action: continueTapped) {
                        HStack(spacing: FamiliarSpacing.xs) {
                            if isSaving { ProgressView().tint(FamiliarColor.onAccent) }
                            Text("Weiter")
                        }
                    }
                    .buttonStyle(.familiarPrimary)
                    .disabled(!InputRules.isValidDisplayName(name) || isSaving)
                    .accessibilityIdentifier("profile.continue")
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.bottom, FamiliarSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .familiarScreenBackground()
            .announcesChanges(of: errorMessage)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SignOutToolbarButton()
                }
            }
            .onAppear {
                if name.isEmpty { name = session.profile?.displayName ?? "" }
            }
        }
    }

    private func continueTapped() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do throws(FamiliarError) {
                if InputRules.trimmed(name) != session.profile?.displayName {
                    try await session.saveDisplayName(name)
                }
                session.confirmProfile()
            } catch {
                errorMessage = error.message
            }
        }
    }
}

/// Ausweg aus dem Onboarding, z. B. bei falscher E-Mail-Adresse.
struct SignOutToolbarButton: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Button("Abmelden") {
            Task { try? await session.signOut(everywhere: false) }
        }
    }
}
