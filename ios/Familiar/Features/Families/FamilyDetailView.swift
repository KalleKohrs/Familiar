import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Eine Familie: Mitglieder, Einladung teilen, Familie verlassen.
/// Rollen ändern, Mitglieder entfernen und Rechte-Schalter folgen in Phase 9.
struct FamilyDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let familyID: UUID

    @State private var invite: FamilyInvite?
    @State private var isCreatingInvite = false
    @State private var isLeaving = false
    @State private var confirmLeave = false
    @State private var errorMessage: String?

    var body: some View {
        if let membership = session.membership(familyID) {
            content(membership)
        } else {
            // Nach dem Verlassen ist die Familie weg.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ membership: FamilyMembership) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.l) {
                FamilyBadge(name: membership.family.name, color: Color(membership.family.color))

                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    FamiliarSectionHeader("Mitglieder")
                    VStack(spacing: 0) {
                        ForEach(membership.sortedMembers) { member in
                            memberRow(member, isMe: member.userID == membership.currentUserID)
                            if member.id != membership.sortedMembers.last?.id {
                                Divider().overlay(FamiliarColor.hairline)
                            }
                        }
                    }
                    .familiarCard(padding: FamiliarSpacing.s)
                }

                if membership.allows(.invite) {
                    inviteSection(membership)
                }

                if let errorMessage {
                    FamiliarInlineError(errorMessage)
                }

                leaveSection(membership)
            }
            .padding(FamiliarSpacing.m)
        }
        .familiarScreenBackground()
        .navigationTitle(membership.family.name)
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: errorMessage)
        .confirmationDialog(
            "Familie „\(membership.family.name)“ verlassen?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Verlassen", role: .destructive) { leave() }
        } message: {
            Text(membership.members.count == 1
                 ? "Du bist das letzte Mitglied. Die Familie wird dabei gelöscht."
                 : "Du siehst danach keine Aufgaben dieser Familie mehr. Ein neuer Beitritt braucht eine Einladung.")
        }
    }

    private func memberRow(_ member: FamilyMember, isMe: Bool) -> some View {
        HStack(spacing: FamiliarSpacing.s) {
            ProfileAvatar(profile: member.profile, name: member.displayName, diameter: 36)
            Text(isMe ? "\(member.displayName) (du)" : member.displayName)
                .font(FamiliarFont.body)
                .foregroundStyle(FamiliarColor.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if member.role == .admin {
                FamiliarTag("Admin", systemImage: "star.fill", tone: .accent)
            }
        }
        .padding(.vertical, FamiliarSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func inviteSection(_ membership: FamilyMembership) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Einladen")
            if let invite {
                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    Text(InviteCode.formatted(invite.code))
                        .font(.largeTitle.monospaced().weight(.semibold))
                        .foregroundStyle(FamiliarColor.textPrimary)
                        .textSelection(.enabled)
                        .accessibilityLabel("Einladungscode \(invite.code.map(String.init).joined(separator: " "))")
                        .accessibilityIdentifier("invite.code")
                    Text("Gültig bis \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened)). Der Code kann mehrfach verwendet werden.")
                        .font(FamiliarFont.meta)
                        .foregroundStyle(FamiliarColor.textSecondary)
                    ShareLink(item: shareText(invite: invite, family: membership.family)) {
                        Label("Code teilen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.familiarPrimary)
                }
                .familiarCard()
            } else {
                Text("Erstelle einen Code und schick ihn an die Person, die beitreten soll.")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
                Button(action: createInvite) {
                    HStack(spacing: FamiliarSpacing.xs) {
                        if isCreatingInvite { ProgressView().tint(FamiliarColor.onAccent) }
                        Text("Einladungscode erstellen")
                    }
                }
                .buttonStyle(.familiarPrimary)
                .disabled(isCreatingInvite)
                .accessibilityIdentifier("familyDetail.invite")
            }
        }
    }

    @ViewBuilder
    private func leaveSection(_ membership: FamilyMembership) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
            Button("Familie verlassen", role: .destructive) { confirmLeave = true }
                .buttonStyle(.familiarDestructive)
                .disabled(membership.isLastAdminWithOthers || isLeaving)
            if membership.isLastAdminWithOthers {
                Text("Du bist der einzige Admin. Ernenne zuerst eine andere Person zum Admin (kommt mit den Familienrechten).")
                    .font(FamiliarFont.meta)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
        }
        .padding(.top, FamiliarSpacing.m)
    }

    private func shareText(invite: FamilyInvite, family: Family) -> String {
        String(localized: "Komm in unsere Familie „\(family.name)“ bei Familiar! Öffne die App, wähle „Mit Code beitreten“ und gib diesen Code ein: \(InviteCode.formatted(invite.code)) (gültig bis \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))).")
    }

    private func createInvite() {
        isCreatingInvite = true
        errorMessage = nil
        Task {
            defer { isCreatingInvite = false }
            do throws(FamiliarError) {
                invite = try await session.createInvite(familyID: familyID)
            } catch {
                errorMessage = error.message
            }
        }
    }

    private func leave() {
        isLeaving = true
        errorMessage = nil
        Task {
            defer { isLeaving = false }
            do throws(FamiliarError) {
                try await session.leaveFamily(familyID)
            } catch {
                errorMessage = error.message
            }
        }
    }
}
