import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Bestätigung nach dem Öffnen eines Einladungslinks: erst fragen, dann beitreten.
struct InviteJoinSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let code: String
    @State private var isJoining = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: FamiliarSpacing.l) {
            VStack(spacing: FamiliarSpacing.xs) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(FamiliarColor.accent)
                    .padding(.bottom, FamiliarSpacing.xs)
                    .accessibilityHidden(true)
                Text("Familie beitreten?")
                    .font(FamiliarFont.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Du wurdest mit diesem Code eingeladen:")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
                Text(InviteCode.formatted(code))
                    .font(.title2.monospaced().weight(.semibold))
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
            }
            .multilineTextAlignment(.center)

            if let message {
                FamiliarInlineError(message)
            }

            VStack(spacing: FamiliarSpacing.s) {
                Button(action: join) {
                    HStack(spacing: FamiliarSpacing.xs) {
                        if isJoining { ProgressView().tint(FamiliarColor.onAccent) }
                        Text("Beitreten")
                    }
                }
                .buttonStyle(.familiarPrimary)
                .disabled(isJoining)
                .accessibilityIdentifier("invite.join")
                Button("Nicht jetzt") {
                    session.clearPendingInvite()
                    dismiss()
                }
                .buttonStyle(.familiarSecondary)
                .disabled(isJoining)
            }
        }
        .padding(FamiliarSpacing.m)
        .padding(.top, FamiliarSpacing.m)
        .frame(maxWidth: .infinity)
        .familiarScreenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isJoining)
        .announcesChanges(of: message)
    }

    private func join() {
        isJoining = true
        message = nil
        Task {
            defer { isJoining = false }
            do throws(FamiliarError) {
                let result = try await session.joinFamily(code: code)
                if result.isSuccess {
                    session.clearPendingInvite()
                    dismiss()
                } else {
                    message = result.message
                }
            } catch {
                message = error.message
            }
        }
    }
}
