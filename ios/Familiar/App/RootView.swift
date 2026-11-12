import FamiliarCore
import FamiliarData
import FamiliarDesign
import SwiftUI

/// Wählt nach dem Anmeldestatus: Anmeldung, Onboarding oder die App.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var tasks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Beim Start liegt die Startansicht noch über der Hauptansicht, bis die erste Liste geladen ist. So
    /// blendet sich die fertige Liste in einem Zug ein, statt dass Platzhalter, Leerzustand und Liste
    /// nacheinander überblendet werden.
    @State private var showsLaunchCover = true

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
                    .overlay {
                        if showsLaunchCover {
                            LaunchView()
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
            case .failed(let error):
                LoadingFailedView(error: error)
            }
        }
        .transition(.opacity)
        .familiarAnimation(value: session.phase)
        .task(id: session.phase == .ready) { await dismissLaunchCover() }
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
        // Gerade angelegte Familie: einmal anbieten, Leute einzuladen.
        .sheet(isPresented: showsInvitePrompt) {
            if let familyID = session.invitePromptFamilyID { InviteFamilySheet(familyID: familyID) }
        }
        .onChange(of: session.userID) { _, userID in
            // Nach dem Abmelden keine Aufgaben der vorigen Person im Speicher behalten.
            if userID == nil { tasks.stop() }
        }
    }
}

extension RootView {
    private var tasksSettled: Bool {
        switch tasks.state {
        case .idle, .loading: false
        default: true
        }
    }

    /// Wartet höchstens 1,5 s auf die erste Liste und blendet dann die Startansicht ruhig aus.
    private func dismissLaunchCover() async {
        guard session.phase == .ready else { showsLaunchCover = true; return }
        for _ in 0..<30 where !tasksSettled {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
        }
        withAnimation(reduceMotion ? FamiliarMotion.reduced : .easeOut(duration: 0.45)) { showsLaunchCover = false }
    }

    private var showsInvitePrompt: Binding<Bool> {
        Binding {
            session.invitePromptFamilyID != nil && session.phase == .ready && session.pendingInviteCode == nil
        } set: { isPresented in
            if !isPresented { session.clearInvitePrompt() }
        }
    }

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
