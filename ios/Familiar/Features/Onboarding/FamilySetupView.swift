import FamiliarDesign
import SwiftUI

/// Onboarding, Schritt 2: Familie erstellen oder mit Code beitreten.
/// Sobald eine Familie existiert, wechselt die App von selbst in die Hauptansicht.
struct FamilySetupView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FamiliarSpacing.l) {
                    VStack(spacing: FamiliarSpacing.xs) {
                        FamiliarOrb(diameter: 64)
                            .padding(.bottom, FamiliarSpacing.xs)
                        Text("Deine Familie")
                            .font(FamiliarFont.title)
                            .accessibilityAddTraits(.isHeader)
                        Text("Lege eine neue Familie an oder tritt mit einem Einladungscode bei. Du kannst später weitere Familien hinzufügen.")
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, FamiliarSpacing.l)

                    FamilyEntryLinks()
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.bottom, FamiliarSpacing.xl)
            }
            .familiarScreenBackground()
            .navigationDestination(for: FamilyEntryRoute.self) { route in
                route.destination
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SignOutToolbarButton()
                }
            }
        }
    }
}

enum FamilyEntryRoute: Hashable {
    case create
    case join

    @ViewBuilder
    var destination: some View {
        switch self {
        case .create: CreateFamilyForm()
        case .join: JoinFamilyForm()
        }
    }
}

/// Zwei Einstiege als Cards; der umgebende NavigationStack braucht `navigationDestination(for: FamilyEntryRoute.self)`.
struct FamilyEntryLinks: View {
    var body: some View {
        VStack(spacing: FamiliarSpacing.s) {
            NavigationLink(value: FamilyEntryRoute.create) {
                entryLabel(title: "Neue Familie erstellen",
                           message: "Du wirst Admin und kannst andere einladen.",
                           systemImage: "plus.circle.fill")
            }
            .buttonStyle(.familiarCard)
            .accessibilityIdentifier("family.create")

            NavigationLink(value: FamilyEntryRoute.join) {
                entryLabel(title: "Mit Code beitreten",
                           message: "Du hast einen Einladungscode bekommen.",
                           systemImage: "person.2.badge.key.fill")
            }
            .buttonStyle(.familiarCard)
            .accessibilityIdentifier("family.join")
        }
    }

    private func entryLabel(title: LocalizedStringKey, message: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: FamiliarSpacing.m) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(FamiliarColor.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                Text(title)
                    .font(FamiliarFont.cardTitle)
                    .foregroundStyle(FamiliarColor.textPrimary)
                Text(message)
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FamiliarColor.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
