import FamiliarCore
import FamiliarDesign
import SwiftUI
import UIKit

/// „Wen holst du dazu?“: erstellt auf Tipp einen Einladungscode und öffnet das Teilen-Blatt.
/// Der Code wird erst erzeugt, wenn die Person wirklich einlädt (er gilt 7 Tage).
/// Genutzt direkt nach dem Anlegen der ersten Familie und über den Hinweis auf der Startseite.
struct InviteFamilySheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let familyID: UUID

    @State private var invite: FamilyInvite?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var shareText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FamiliarSpacing.l) {
                    VStack(spacing: FamiliarSpacing.xs) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(FamiliarColor.accent)
                            .accessibilityHidden(true)
                        Text("Wen holst du dazu?")
                            .font(FamiliarFont.title)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Schick einen Einladungslink an deine Familie. Wer ihn öffnet, ist mit einem Tipp dabei – dann seht ihr alle Aufgaben gemeinsam.")
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, FamiliarSpacing.l)

                    if let invite {
                        VStack(spacing: FamiliarSpacing.xs) {
                            Text(InviteCode.formatted(invite.code))
                                .font(.largeTitle.monospaced().weight(.semibold))
                                .foregroundStyle(FamiliarColor.textPrimary)
                                .textSelection(.enabled)
                                .accessibilityLabel("Einladungscode \(invite.code.map(String.init).joined(separator: " "))")
                                .accessibilityIdentifier("invite.code")
                            Text("Gültig bis \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened)). Der Code kann mehrfach verwendet werden.")
                                .font(FamiliarFont.meta)
                                .foregroundStyle(FamiliarColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .familiarCard()
                    }

                    if let errorMessage {
                        FamiliarInlineError(errorMessage)
                    }

                    VStack(spacing: FamiliarSpacing.s) {
                        Button(action: share) {
                            HStack(spacing: FamiliarSpacing.xs) {
                                if isCreating { ProgressView().tint(FamiliarColor.onAccent) }
                                Label(invite == nil ? "Einladung teilen" : "Noch einmal teilen",
                                      systemImage: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(.familiarPrimary)
                        .disabled(isCreating)
                        .accessibilityIdentifier("invite.share")

                        Button(invite == nil ? "Später" : "Fertig") { dismiss() }
                            .buttonStyle(.familiarSecondary)
                            .accessibilityIdentifier("invite.later")
                    }
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.bottom, FamiliarSpacing.xl)
            }
            .familiarScreenBackground()
            .announcesChanges(of: errorMessage)
            .sheet(item: Binding(get: { shareText.map(ShareItem.init) }, set: { shareText = $0?.text })) { item in
                ActivityView(items: [item.text])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func share() {
        errorMessage = nil
        if let invite, invite.isActive(), let family = session.membership(familyID)?.family {
            shareText = InviteMessage.text(familyName: family.name, code: invite.code, expiresAt: invite.expiresAt)
            return
        }
        isCreating = true
        Task {
            defer { isCreating = false }
            do throws(FamiliarError) {
                let created = try await session.createInvite(familyID: familyID)
                invite = created
                let name = session.membership(familyID)?.family.name ?? ""
                shareText = InviteMessage.text(familyName: name, code: created.code, expiresAt: created.expiresAt)
            } catch {
                errorMessage = error.message
            }
        }
    }
}

private struct ShareItem: Identifiable {
    let text: String
    var id: String { text }
}

/// Das System-Teilen-Blatt (Nachrichten, AirDrop, Mail …) für einen Text.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Hinweis oben auf der Startseite, solange man allein in einer Familie ist: „Hol deine Familie dazu“.
/// „Später“ blendet ihn für diese Familie dauerhaft aus (nur auf diesem Gerät gemerkt).
struct InviteHintSection: View {
    @Environment(SessionStore.self) private var session
    @State private var dismissed: Set<UUID> = []
    @State private var invitingFamily: InviteTarget?

    private static func key(_ familyID: UUID) -> String { "inviteHint.dismissed.\(familyID.uuidString)" }

    private var candidate: FamilyMembership? {
        session.families.first {
            $0.suggestsInvite && !dismissed.contains($0.id) && !UserDefaults.standard.bool(forKey: Self.key($0.id))
        }
    }

    var body: some View {
        // Das Blatt hängt außerhalb der Bedingung: Tritt jemand bei, während es offen ist, bleibt es stehen.
        Group {
            if let membership = candidate { card(membership) }
        }
        .sheet(item: $invitingFamily) { target in
            InviteFamilySheet(familyID: target.familyID)
        }
    }

    private func card(_ membership: FamilyMembership) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                HStack(spacing: FamiliarSpacing.s) {
                    Image(systemName: "person.badge.plus")
                        .font(.title2)
                        .foregroundStyle(FamiliarColor.accent)
                        .accessibilityHidden(true)
                    Text("Hol deine Familie dazu")
                        .font(FamiliarFont.cardTitle)
                        .foregroundStyle(FamiliarColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                Text("Du bist in „\(membership.family.name)“ noch allein. Mit einem Einladungslink sind die anderen mit einem Tipp dabei.")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
                HStack(spacing: FamiliarSpacing.s) {
                    Button("Einladen") { invitingFamily = InviteTarget(familyID: membership.id) }
                        .buttonStyle(.familiarPrimary)
                        .accessibilityIdentifier("inviteHint.invite")
                    Button("Später") {
                        UserDefaults.standard.set(true, forKey: Self.key(membership.id))
                        dismissed.insert(membership.id)
                    }
                    .buttonStyle(.familiarSecondary)
                    .accessibilityIdentifier("inviteHint.later")
                }
            }
            .familiarCard()
    }
}

private struct InviteTarget: Identifiable {
    let familyID: UUID
    var id: UUID { familyID }
}
