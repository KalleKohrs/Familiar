import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Wählt nach dem Anmeldestatus: Anmeldung, Onboarding oder die App.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            switch session.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                SignInView()
            case .onboarding(.profile):
                ProfileSetupView()
            case .onboarding(.family), .onboarding(.done):
                FamilySetupView()
            case .ready:
                RootTabView()
            case .failed(let error):
                LoadingFailedView(error: error)
            }
        }
        .transition(.opacity)
        .familiarAnimation(value: session.phase)
    }
}

/// Kurzer Zwischenzustand, während die gespeicherte Sitzung geladen wird.
private struct LaunchView: View {
    var body: some View {
        FamiliarOrb(diameter: 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .familiarScreenBackground()
            .accessibilityElement()
            .accessibilityLabel("Familiar wird geladen")
    }
}

private struct LoadingFailedView: View {
    @Environment(SessionStore.self) private var session
    let error: FamiliarError

    var body: some View {
        VStack(spacing: FamiliarSpacing.m) {
            FamiliarErrorState(message: error.message) {
                Task { await session.reload() }
            }
            .familiarCard()
            Button("Abmelden") {
                Task { try? await session.signOut(everywhere: false) }
            }
            .buttonStyle(.familiarSecondary)
        }
        .padding(FamiliarSpacing.m)
        .frame(maxHeight: .infinity)
        .familiarScreenBackground()
    }
}
