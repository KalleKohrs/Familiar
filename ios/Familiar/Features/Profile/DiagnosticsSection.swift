import FamiliarActivity
import FamiliarCore
import FamiliarDesign
import SwiftUI
import UIKit

/// Nur in Testversionen (Xcode, TestFlight): zeigt, was im Hintergrund passiert ist – Abhaken in der Live Activity,
/// Anmeldung für Mitteilungen. Die Zeilen liegen nur auf dem Gerät und enthalten keine Aufgabentitel oder Namen.
struct DiagnosticsSection: View {
    @Environment(NotificationStore.self) private var notifications
    @State private var lines: [String] = []
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Diagnose (Testversion)")
            VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                Text("Push-Umgebung: \(NotificationStore.currentEnvironment.rawValue)")
                Text("Geräte-Token: \(notifications.deviceToken == nil ? "fehlt" : "vorhanden")")
                if lines.isEmpty {
                    Text("Noch keine Einträge.")
                } else {
                    ForEach(Array(lines.suffix(14).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
            }
            .font(FamiliarFont.meta)
            .foregroundStyle(FamiliarColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .familiarCard()

            HStack(spacing: FamiliarSpacing.s) {
                Button("Aktualisieren") { lines = FamiliarDiagnostics.lines() }
                    .buttonStyle(.familiarSecondary)
                Button(copied ? "Kopiert" : "Kopieren") {
                    UIPasteboard.general.string = (["Umgebung: \(NotificationStore.currentEnvironment.rawValue)"]
                        + FamiliarDiagnostics.lines()).joined(separator: "\n")
                    copied = true
                }
                .buttonStyle(.familiarSecondary)
            }
        }
        .onAppear { lines = FamiliarDiagnostics.lines() }
    }
}
