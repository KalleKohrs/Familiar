import FamiliarDesign
import SwiftUI

/// Sheet „Neue Aufgabe“. Phase 0: Platzhalter; der Editor folgt in Phase 3.
struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                FamiliarEmptyState(
                    systemImage: "square.and.pencil",
                    title: "Neue Aufgabe",
                    message: "Titel, Personen, Bilder und Wiederholung legst du hier bald fest."
                )
                .familiarCard()
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .familiarScreenBackground()
            .navigationTitle("Neue Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
