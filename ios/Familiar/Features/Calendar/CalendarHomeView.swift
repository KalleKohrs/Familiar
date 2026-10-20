import FamiliarDesign
import SwiftUI

/// Bereich „Kalender“. Phase 0: Platzhalter; die Monatsansicht folgt in Phase 6.
struct CalendarHomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                FamiliarEmptyState(
                    systemImage: "calendar",
                    title: "Monatsübersicht",
                    message: "Hier erscheinen deine Aufgaben und – getrennt gekennzeichnet – deine Outlook-Termine."
                )
                .familiarCard()
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .familiarScreenBackground()
            .navigationTitle("Kalender")
        }
    }
}
