import FamiliarDesign
import SwiftUI

/// Startseite „Aufgaben“. Phase 0: Gerüst mit Kopfzeile und Leerzustand.
/// Die echte Liste folgt in Phase 3.
struct TasksHomeView: View {
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
                    FamilyHeaderButton(title: "Meine Familie")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileHeaderButton(name: "Ich")
                }
            }
        }
    }
}

/// Familienname oben links. Öffnet später das Sheet „Familien“ (Plan, Abschnitt 6).
struct FamilyHeaderButton: View {
    let title: String

    var body: some View {
        Button {} label: {
            HStack(spacing: FamiliarSpacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .foregroundStyle(FamiliarColor.textPrimary)
        }
        .accessibilityLabel("\(title), Familien verwalten")
    }
}

/// Profilbild oben rechts. Öffnet später Profil und Einstellungen.
struct ProfileHeaderButton: View {
    let name: String

    var body: some View {
        Button {} label: {
            AvatarView(name: name, diameter: 30)
        }
        .accessibilityLabel("Profil und Einstellungen")
    }
}

#Preview {
    TasksHomeView()
        .preferredColorScheme(.dark)
}
