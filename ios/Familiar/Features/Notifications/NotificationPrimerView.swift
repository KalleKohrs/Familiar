import FamiliarDesign
import SwiftUI

/// Erklärt einmal je Konto, wofür Familiar Mitteilungen nutzt, bevor iOS um Erlaubnis fragt.
struct NotificationPrimerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NotificationStore.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @State private var isAsking = false

    var body: some View {
        ScrollView {
            VStack(spacing: FamiliarSpacing.l) {
                VStack(spacing: FamiliarSpacing.xs) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(FamiliarColor.accent)
                        .padding(.bottom, FamiliarSpacing.xs)
                        .accessibilityHidden(true)
                    Text("Nichts verpassen")
                        .font(FamiliarFont.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("Familiar meldet sich nur, wenn es dich betrifft.")
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, FamiliarSpacing.xl)

                VStack(alignment: .leading, spacing: FamiliarSpacing.m) {
                    reason("person.crop.circle.badge.plus", "Neue Aufgaben", "wenn dir jemand etwas zuweist")
                    reason("clock", "Rechtzeitig", "zum Start und als Erinnerung, solange etwas offen ist")
                    reason("checkmark.circle", "Auf dem Sperrbildschirm",
                           "kurz vor dem Start als Live-Anzeige – direkt abhaken")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: FamiliarSpacing.s) {
                    Button("Mitteilungen erlauben") { allow() }
                        .buttonStyle(.familiarPrimary)
                        .disabled(isAsking)
                    Button("Später") { finish() }
                        .buttonStyle(.familiarSecondary)
                }
                Text("Du kannst das jederzeit in den iOS-Einstellungen ändern.")
                    .font(.footnote)
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, FamiliarSpacing.m)
            .padding(.bottom, FamiliarSpacing.l)
        }
        .familiarScreenBackground()
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isAsking)
        .onDisappear { markAsked() }
    }

    private func reason(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FamiliarSpacing.s) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(FamiliarColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FamiliarColor.textPrimary)
                Text(detail)
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func allow() {
        isAsking = true
        Task {
            await notifications.requestAuthorization()
            finish()
        }
    }

    private func finish() {
        markAsked()
        dismiss()
    }

    private func markAsked() {
        if let userID = session.userID { notifications.markAskedForPermission(userID) }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) { NotificationPrimerView() }
        .previewEnvironment(.ready)
}
