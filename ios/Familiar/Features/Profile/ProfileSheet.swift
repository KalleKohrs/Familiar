import FamiliarCore
import FamiliarDesign
import SwiftUI
import UIKit

/// Profil und Einstellungen (Profilbild oben rechts): Name, Bild, Outlook, Mitteilungen, Abmelden,
/// Konto löschen.
struct ProfileSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(OutlookStore.self) private var outlook
    @Environment(NotificationStore.self) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var isSigningOut = false
    @State private var confirmSignOutEverywhere = false
    @State private var confirmDeleteAccount = false
    @State private var isDeletingAccount = false
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

                    VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                        FamiliarSectionHeader("Persönlicher Kalender")
                        NavigationLink {
                            OutlookSettingsView()
                        } label: {
                            HStack(spacing: FamiliarSpacing.s) {
                                Image(systemName: "calendar")
                                    .font(.title3)
                                    .foregroundStyle(FamiliarColor.textSecondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Outlook")
                                        .font(FamiliarFont.cardTitle)
                                        .foregroundStyle(FamiliarColor.textPrimary)
                                    Text(outlook.isConnected ? "Verbunden" : "Nicht verbunden")
                                        .font(FamiliarFont.meta)
                                        .foregroundStyle(FamiliarColor.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(FamiliarColor.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.familiarCard)
                        .accessibilityIdentifier("profile.outlook")
                    }

                    if notifications.isAvailable {
                        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                            FamiliarSectionHeader("Mitteilungen")
                            Button(action: openNotificationSettings) {
                                HStack(spacing: FamiliarSpacing.s) {
                                    Image(systemName: notificationsOn ? "bell.badge" : "bell.slash")
                                        .font(.title3)
                                        .foregroundStyle(FamiliarColor.textSecondary)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(notificationsOn ? "Eingeschaltet" : "Ausgeschaltet")
                                            .font(FamiliarFont.cardTitle)
                                            .foregroundStyle(FamiliarColor.textPrimary)
                                        Text(notificationsOn ? "In den iOS-Einstellungen ändern" : "Antippen zum Einschalten")
                                            .font(FamiliarFont.meta)
                                            .foregroundStyle(FamiliarColor.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.forward")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(FamiliarColor.textTertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.familiarCard)
                            .accessibilityIdentifier("profile.notifications")
                        }
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

                    VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                        Button(role: .destructive) { confirmDeleteAccount = true } label: {
                            HStack(spacing: FamiliarSpacing.xs) {
                                if isDeletingAccount { ProgressView() }
                                Text("Konto löschen")
                            }
                        }
                        .buttonStyle(.familiarDestructive)
                        .disabled(isDeletingAccount || isSigningOut)
                        .accessibilityIdentifier("profile.deleteAccount")
                        Text("Löscht dein Profil und deine Mitgliedschaften endgültig. Familien, in denen du allein bist, werden mit gelöscht.")
                            .font(FamiliarFont.meta)
                            .foregroundStyle(FamiliarColor.textSecondary)
                    }
                    .padding(.top, FamiliarSpacing.l)
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
            .sheet(isPresented: $confirmDeleteAccount) {
                FamiliarChoiceSheet(
                    systemImage: "person.crop.circle.badge.xmark", tint: FamiliarColor.danger,
                    title: "Konto endgültig löschen?",
                    message: "Dein Profil, dein Profilbild und deine Mitgliedschaften werden gelöscht. Familien, in denen du allein bist, verschwinden samt Aufgaben. Bist du einziger Admin, übernimmt die Person, die am längsten dabei ist. Von dir hochgeladene Fotos an Familienaufgaben bleiben für die Familie erhalten. Das lässt sich nicht rückgängig machen."
                ) {
                    Button("Konto endgültig löschen", role: .destructive) {
                        confirmDeleteAccount = false
                        deleteAccount()
                    }
                    .buttonStyle(.familiarDestructive)
                    .accessibilityIdentifier("profile.deleteAccountConfirm")
                }
            }
            .onAppear { name = session.profile?.displayName ?? "" }
            .task { await notifications.refreshAuthorization() }
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

    private func deleteAccount() {
        isDeletingAccount = true
        errorMessage = nil
        Task {
            defer { isDeletingAccount = false }
            do throws(FamiliarError) {
                try await session.deleteAccount()
            } catch {
                errorMessage = error.message
            }
        }
    }

    private var notificationsOn: Bool {
        notifications.authorization == .authorized || notifications.authorization == .provisional
    }

    /// Noch nie gefragt: System-Abfrage; sonst die Mitteilungs-Einstellungen von Familiar öffnen.
    private func openNotificationSettings() {
        Task {
            if notifications.authorization == .notDetermined {
                await notifications.requestAuthorization()
            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                openURL(url)
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
