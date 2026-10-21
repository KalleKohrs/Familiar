import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Eine Familie: Mitglieder (Rolle ändern, entfernen), Einladung, Einstellungen, Rechte für
/// Mitglieder (nur Admins, Entscheidung E4), verlassen bzw. löschen.
struct FamilyDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let familyID: UUID

    @State private var invite: FamilyInvite?
    @State private var isCreatingInvite = false
    @State private var isWorking = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var memberToRemove: FamilyMember?
    @State private var errorMessage: String?

    var body: some View {
        if let membership = session.membership(familyID) {
            content(membership)
        } else {
            // Nach dem Verlassen oder Löschen ist die Familie weg.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ membership: FamilyMembership) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.l) {
                HStack(spacing: FamiliarSpacing.s) {
                    FamilyBadge(name: membership.family.name, color: Color(membership.family.color))
                    Spacer(minLength: 0)
                    if membership.allows(.manageFamily) {
                        NavigationLink {
                            FamilySettingsForm(family: membership.family)
                        } label: {
                            Label("Bearbeiten", systemImage: "slider.horizontal.3")
                                .font(FamiliarFont.secondary.weight(.semibold))
                        }
                        .tint(FamiliarColor.accent)
                        .accessibilityIdentifier("familyDetail.edit")
                    }
                }

                if let errorMessage {
                    FamiliarInlineError(errorMessage)
                }

                membersSection(membership)

                if membership.allows(.invite) {
                    inviteSection(membership)
                }

                if membership.myRole == .admin {
                    permissionsSection(membership)
                } else {
                    restrictionsNote(membership)
                }

                dangerSection(membership)
            }
            .padding(FamiliarSpacing.m)
        }
        .familiarScreenBackground()
        .navigationTitle(membership.family.name)
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: errorMessage)
        .sheet(isPresented: $confirmLeave) {
            FamiliarChoiceSheet(
                systemImage: "rectangle.portrait.and.arrow.right", tint: FamiliarColor.danger,
                title: "„\(membership.family.name)“ verlassen?",
                message: membership.members.count == 1
                    ? "Du bist das letzte Mitglied. Die Familie wird dabei samt Aufgaben gelöscht."
                    : "Du siehst danach keine Aufgaben dieser Familie mehr. Ein neuer Beitritt braucht eine Einladung."
            ) {
                Button("Verlassen", role: .destructive) { confirmLeave = false; leave() }
                    .buttonStyle(.familiarDestructive)
            }
        }
        .sheet(isPresented: $confirmDelete) {
            FamiliarChoiceSheet(
                systemImage: "trash", tint: FamiliarColor.danger,
                title: "„\(membership.family.name)“ löschen?",
                message: "Die Familie wird für alle Mitglieder gelöscht – mit allen Aufgaben, Serien, Bildern und dem Verlauf. Das lässt sich nicht rückgängig machen."
            ) {
                Button("Familie endgültig löschen", role: .destructive) { confirmDelete = false; deleteFamily() }
                    .buttonStyle(.familiarDestructive)
                    .accessibilityIdentifier("familyDetail.deleteConfirm")
            }
        }
        .sheet(item: $memberToRemove) { member in
            FamiliarChoiceSheet(
                systemImage: "person.badge.minus", tint: FamiliarColor.danger,
                title: "\(member.displayName) entfernen?",
                message: "Die Person sieht danach keine Aufgaben dieser Familie mehr und wird aus Zuweisungen entfernt."
            ) {
                Button("Entfernen", role: .destructive) { memberToRemove = nil; remove(member) }
                    .buttonStyle(.familiarDestructive)
            }
        }
    }

    // MARK: Mitglieder

    private func membersSection(_ membership: FamilyMembership) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Mitglieder")
            VStack(spacing: 0) {
                ForEach(membership.sortedMembers) { member in
                    memberRow(member, in: membership)
                    if member.id != membership.sortedMembers.last?.id {
                        Divider().overlay(FamiliarColor.hairline)
                    }
                }
            }
            .familiarCard(padding: FamiliarSpacing.s)
        }
    }

    private func memberRow(_ member: FamilyMember, in membership: FamilyMembership) -> some View {
        let isMe = member.userID == membership.currentUserID
        let canChangeRole = membership.myRole == .admin && !isMe
        // Admins darf nur ein Admin entfernen (wie `remove_member`).
        let canRemove = !isMe && membership.allows(.removeMembers)
            && (member.role == .member || membership.myRole == .admin)

        return HStack(spacing: FamiliarSpacing.s) {
            ProfileAvatar(profile: member.profile, name: member.displayName, diameter: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(member.displayName) (du)" : member.displayName)
                    .font(FamiliarFont.body)
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .lineLimit(2)
                if member.role == .admin {
                    Text("Admin")
                        .font(FamiliarFont.meta)
                        .foregroundStyle(FamiliarColor.accent)
                }
            }
            Spacer(minLength: 0)
            if canChangeRole || canRemove {
                Menu {
                    if canChangeRole {
                        if member.role == .member {
                            Button("Zum Admin machen", systemImage: "star") { setRole(.admin, for: member) }
                        } else {
                            Button("Admin-Rolle entziehen", systemImage: "star.slash") { setRole(.member, for: member) }
                        }
                    }
                    if canRemove {
                        Button("Aus der Familie entfernen", systemImage: "person.badge.minus", role: .destructive) {
                            memberToRemove = member
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FamiliarColor.textSecondary)
                        .frame(width: FamiliarSize.minimumTouchTarget, height: FamiliarSize.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .disabled(isWorking)
                .accessibilityLabel("Aktionen für \(member.displayName)")
                .accessibilityIdentifier("familyDetail.member.\(member.displayName)")
            }
        }
        .padding(.vertical, FamiliarSpacing.xxs)
    }

    // MARK: Einladen

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

    // MARK: Rechte (E4)

    private static let permissionOrder: [(FamilyPermission, LocalizedStringKey)] = [
        (.createTasks, "Aufgaben anlegen"),
        (.editTasks, "Aufgaben bearbeiten"),
        (.deleteTasks, "Aufgaben löschen und wiederherstellen"),
        (.invite, "Personen einladen"),
        (.manageFamily, "Familie bearbeiten"),
        (.removeMembers, "Mitglieder entfernen"),
    ]

    private func permissionsSection(_ membership: FamilyMembership) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Mitglieder dürfen …")
            VStack(spacing: 0) {
                ForEach(Array(Self.permissionOrder.enumerated()), id: \.offset) { index, item in
                    Toggle(item.1, isOn: permissionBinding(item.0, in: membership))
                        .font(FamiliarFont.body)
                        // Kein Orange: Akzent bleibt den wichtigsten Aktionen vorbehalten.
                        .tint(FamiliarColor.success)
                        .disabled(isWorking)
                        .padding(.vertical, FamiliarSpacing.xs)
                        .accessibilityIdentifier("familyDetail.permission.\(index)")
                    if index < Self.permissionOrder.count - 1 {
                        Divider().overlay(FamiliarColor.hairline)
                    }
                }
            }
            .familiarCard(padding: FamiliarSpacing.m)
            Text("Gilt für Mitglieder ohne Admin-Rolle. Abhaken und Rückgängig dürfen immer alle.")
                .font(FamiliarFont.meta)
                .foregroundStyle(FamiliarColor.textSecondary)
        }
    }

    /// Für Mitglieder: welche Rechte ein Admin abgeschaltet hat.
    @ViewBuilder
    private func restrictionsNote(_ membership: FamilyMembership) -> some View {
        let restricted = Self.permissionOrder.filter { !membership.family.membersMay($0.0) }
        if !restricted.isEmpty {
            VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                FamiliarSectionHeader("Nur für Admins")
                ForEach(Array(restricted.enumerated()), id: \.offset) { _, item in
                    Label(item.1, systemImage: "lock")
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                }
            }
        }
    }

    private func permissionBinding(_ permission: FamilyPermission, in membership: FamilyMembership) -> Binding<Bool> {
        Binding {
            membership.family.membersMay(permission)
        } set: { allowed in
            run { () async throws(FamiliarError) in try await session.setPermission(permission, allowed: allowed, in: familyID) }
        }
    }

    // MARK: Verlassen / Löschen

    private func dangerSection(_ membership: FamilyMembership) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            Button("Familie verlassen", role: .destructive) { confirmLeave = true }
                .buttonStyle(.familiarDestructive)
                .disabled(membership.isLastAdminWithOthers || isWorking)
            if membership.isLastAdminWithOthers {
                Text("Du bist der einzige Admin. Mach zuerst eine andere Person zum Admin (über ⋯ neben dem Namen).")
                    .font(FamiliarFont.meta)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
            if membership.myRole == .admin {
                Button("Familie löschen", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.familiarDestructive)
                    .disabled(isWorking)
                    .accessibilityIdentifier("familyDetail.delete")
            }
        }
        .padding(.top, FamiliarSpacing.m)
    }

    // MARK: Aktionen

    private func shareText(invite: FamilyInvite, family: Family) -> String {
        String(localized: "Komm in unsere Familie „\(family.name)“ bei Familiar! Öffne die App, wähle „Mit Code beitreten“ und gib diesen Code ein: \(InviteCode.formatted(invite.code)) (gültig bis \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))).")
    }

    private func run(_ action: @escaping () async throws(FamiliarError) -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do throws(FamiliarError) {
                try await action()
            } catch {
                errorMessage = error.message
            }
        }
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

    private func setRole(_ role: FamilyRole, for member: FamilyMember) {
        run { () async throws(FamiliarError) in try await session.setRole(role, for: member.userID, in: familyID) }
    }

    private func remove(_ member: FamilyMember) {
        run { () async throws(FamiliarError) in try await session.removeMember(member.userID, from: familyID) }
    }

    private func leave() {
        run { () async throws(FamiliarError) in try await session.leaveFamily(familyID) }
    }

    private func deleteFamily() {
        run { () async throws(FamiliarError) in try await session.deleteFamily(familyID) }
    }
}
