import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Sheet „Familien“ (Plan, Abschnitt 6): alle eigenen Familien, Einstieg zu Mitgliedern und
/// Einladungen sowie „Familie erstellen/beitreten“. Bewusst kein Filter.
struct FamiliesSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    ForEach(session.families) { membership in
                        NavigationLink(value: membership.id) {
                            FamilyRowLabel(membership: membership)
                        }
                        .buttonStyle(.familiarCard)
                        .accessibilityIdentifier("families.row.\(membership.family.name)")
                    }

                    FamiliarSectionHeader("Weitere Familie")
                        .padding(.top, FamiliarSpacing.m)
                    FamilyEntryLinks()
                }
                .padding(FamiliarSpacing.m)
            }
            .familiarScreenBackground()
            .navigationTitle("Familien")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { familyID in
                FamilyDetailView(familyID: familyID)
            }
            .navigationDestination(for: FamilyEntryRoute.self) { route in
                route.destination
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

private struct FamilyRowLabel: View {
    let membership: FamilyMembership

    var body: some View {
        HStack(spacing: FamiliarSpacing.m) {
            Circle()
                .fill(Color(membership.family.color))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                Text(membership.family.name)
                    .font(FamiliarFont.cardTitle)
                    .foregroundStyle(FamiliarColor.textPrimary)
                Text(membership.members.count == 1 ? "1 Mitglied" : "\(membership.members.count) Mitglieder")
                    .font(FamiliarFont.meta)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
            Spacer(minLength: 0)
            AvatarStack(people: membership.sortedMembers.map {
                AvatarStack.Person(id: $0.userID.uuidString, name: $0.displayName)
            })
            .accessibilityHidden(true)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FamiliarColor.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
