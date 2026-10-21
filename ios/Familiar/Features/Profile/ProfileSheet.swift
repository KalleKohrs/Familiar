import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Profil und Einstellungen (Profilbild oben rechts). Kalender, Mitteilungen und „Konto löschen“
/// kommen in den Phasen 6, 7 und 9 dazu.
struct ProfileSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var isSigningOut = false
    @State private var confirmSignOutEverywhere = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    private var nameChanged: Bool {
        InputRules.trimmed(name) != (session.profile?.displayName ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FamiliarSpacing.l) {
                    AvatarEditor()
                        .frame(maxWidth: .infinity)

                    DisplayNameField(name: $name)
                    if nameChanged {
                        Button(action: saveName) {
                            HStack(spacing: FamiliarSpacing.xs) {
                                if isSaving { ProgressView().tint(FamiliarColor.onAccent) }
                                Text("Name speichern")
                            }
                        }
                        .buttonStyle(.familiarPrimary)
                        .disabled(!InputRules.isValidDisplayName(name) || isSaving)
                    }
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.success)
                    }

                    if let email = session.email {
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                            Text("Angemeldet als")
                                .font(FamiliarFont.meta)
                                .foregroundStyle(FamiliarColor.textSecondary)
                            Text(email)
                                .font(FamiliarFont.body)
                                .foregroundStyle(FamiliarColor.textPrimary)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if let errorMessage {
                        FamiliarInlineError(errorMessage)
                    }

                    #if DEBUG
                    NavigationLink("Design-System ansehen") {
                        DesignGalleryView()
                    }
                    .buttonStyle(.familiarSecondary)
                    #endif

                    VStack(spacing: FamiliarSpacing.s) {
                        Button("Abmelden") { signOut(everywhere: false) }
                            .buttonStyle(.familiarSecondary)
                            .disabled(isSigningOut)
                            .accessibilityIdentifier("profile.signOut")
                        Button("Auf allen Geräten abmelden", role: .destructive) { confirmSignOutEverywhere = true }
                            .buttonStyle(.familiarDestructive)
                            .disabled(isSigningOut)
                    }
                    .padding(.top, FamiliarSpacing.m)
                }
                .padding(FamiliarSpacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .familiarScreenBackground()
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .announcesChanges(of: errorMessage)
            .announcesChanges(of: savedMessage)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Auf allen Geräten abmelden?", isPresented: $confirmSignOutEverywhere, titleVisibility: .visible) {
                Button("Überall abmelden", role: .destructive) { signOut(everywhere: true) }
            } message: {
                Text("Alle Sitzungen deines Kontos werden beendet. Bereits geöffnete Apps merken das spätestens nach einer Stunde.")
            }
            .onAppear { name = session.profile?.displayName ?? "" }
        }
    }

    private func saveName() {
        isSaving = true
        errorMessage = nil
        savedMessage = nil
        Task {
            defer { isSaving = false }
            do throws(FamiliarError) {
                try await session.saveDisplayName(name)
                savedMessage = String(localized: "Name gespeichert.")
            } catch {
                errorMessage = error.message
            }
        }
    }

    private func signOut(everywhere: Bool) {
        isSigningOut = true
        errorMessage = nil
        Task {
            defer { isSigningOut = false }
            do throws(FamiliarError) {
                try await session.signOut(everywhere: everywhere)
            } catch {
                errorMessage = error.message
            }
        }
    }
}
