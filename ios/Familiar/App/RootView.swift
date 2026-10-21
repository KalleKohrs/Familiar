import FamiliarCore
import FamiliarData
import FamiliarDesign
import SwiftUI

/// Wählt nach dem Anmeldestatus: Anmeldung, Onboarding oder die App.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var tasks

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
        // Einladungslink (Universal Link): vormerken; gefragt wird, sobald das Profil steht.
        .onOpenURL { url in
            // Rücksprung von der Google-Anmeldung, sonst ggf. Einladungslink.
            if !GoogleSignInFlow.handle(url) { session.receive(url) }
        }
        #if DEBUG
        // UI-Tests: Universal Links lassen sich im Simulator ohne Website nicht auslösen.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-FamiliarOpenURL"), arguments.indices.contains(index + 1),
               let url = URL(string: arguments[index + 1]) {
                session.receive(url)
            }
        }
        #endif
        .sheet(isPresented: showsInvite) {
            if let code = session.pendingInviteCode { InviteJoinSheet(code: code) }
        }
        .onChange(of: session.userID) { _, userID in
            // Nach dem Abmelden keine Aufgaben der vorigen Person im Speicher behalten.
            if userID == nil { tasks.stop() }
        }
    }
}

extension RootView {
    /// Beitritts-Frage erst nach dem Profil-Schritt; „Nicht jetzt“ bzw. Wischen verwirft den Link.
    private var showsInvite: Binding<Bool> {
        Binding {
            guard session.pendingInviteCode != nil else { return false }
            switch session.phase {
            case .ready, .onboarding(.family), .onboarding(.done): return true
            default: return false
            }
        } set: { isPresented in
            if !isPresented { session.clearPendingInvite() }
        }
    }
}

/// Kurzer Zwischenzustand, während die gespeicherte Sitzung geladen wird.
private struct LaunchView: View {
    var body: some View {
        FamiliarMark(size: 72)
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
