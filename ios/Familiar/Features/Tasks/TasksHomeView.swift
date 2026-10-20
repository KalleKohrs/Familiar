import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Startseite „Aufgaben“. Kopf mit Familien und Profil; die echte Liste folgt in Phase 3.
struct TasksHomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var showsFamilies = false
    @State private var showsProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FamiliarSpacing.m) {
                    FamiliarEmptyState(
                        systemImage: "checklist",
                        title: "Noch keine Aufgaben",
                        message: "Lege über das Plus unten rechts die erste Aufgabe an."
                    )
                    .familiarCard()

                    #if DEBUG
                    NavigationLink("Design-System ansehen") {
                        DesignGalleryView()
                    }
                    .buttonStyle(.familiarSecondary)
                    #endif
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .familiarScreenBackground()
            .navigationTitle("Aufgaben")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FamilyHeaderButton(title: session.familyHeaderTitle) { showsFamilies = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileHeaderButton { showsProfile = true }
                }
            }
            .sheet(isPresented: $showsFamilies) { FamiliesSheet() }
            .sheet(isPresented: $showsProfile) { ProfileSheet() }
        }
    }
}

/// Familienname oben links; öffnet das Sheet „Familien“ (Plan, Abschnitt 6).
struct FamilyHeaderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FamiliarSpacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .foregroundStyle(FamiliarColor.textPrimary)
        }
        .accessibilityLabel("\(title), Familien verwalten")
        .accessibilityIdentifier("header.family")
    }
}

/// Eigenes Profilbild oben rechts; öffnet Profil und Einstellungen.
struct ProfileHeaderButton: View {
    @Environment(SessionStore.self) private var session
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileAvatar(profile: session.profile, name: session.profile?.displayName ?? "", diameter: 30)
        }
        .accessibilityLabel("Profil und Einstellungen")
        .accessibilityIdentifier("header.profile")
    }
}

#Preview {
    TasksHomeView()
        .previewEnvironment(.ready)
}
