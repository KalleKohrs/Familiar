import FamiliarDesign
import SwiftUI

/// Bereich „Verlauf“. Phase 0: Platzhalter; erledigte und gelöschte Aufgaben folgen in Phase 4.
struct HistoryHomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                FamiliarEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "Noch kein Verlauf",
                    message: "Erledigte und gelöschte Aufgaben bleiben hier 30 Tage und lassen sich wiederherstellen."
                )
                .familiarCard()
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .familiarScreenBackground()
            .navigationTitle("Verlauf")
        }
    }
}
