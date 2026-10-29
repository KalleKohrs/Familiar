import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Hauptnavigation: drei Bereiche in einer `TabView` (behält den Zustand je Bereich),
/// deren System-Tab-Bar ausgeblendet und durch die eigene ``FloatingTabBar`` ersetzt ist.
struct RootTabView: View {
    @State private var selection: AppTab = .tasks
    @State private var isCreatingTask = false
    @State private var createTaskRequests = 0
    @State private var tabBarHeight: CGFloat = 0
    @State private var bottomSafeArea: CGFloat = 0
    @State private var showsNotificationPrimer = false

    /// Abstand der Leiste zur Bildschirmunterkante: auf Geräten mit Home-Indikator wie Apples
    /// Leiste (konzentrisch zu den Displayecken), sonst etwas knapper.
    private var barBottomInset: CGFloat { bottomSafeArea > 0 ? FloatingTabBar.bottomInset : 12 }

    /// Platz, den Inhalte unten freihalten (relativ zur Safe Area), plus etwas Luft.
    private var contentInset: CGFloat {
        max(0, tabBarHeight + barBottomInset - bottomSafeArea) + FamiliarSpacing.xs
    }
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var tasks
    @Environment(OutlookStore.self) private var outlook
    @Environment(NotificationStore.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    content(for: tab)
                        .toolbarVisibility(.hidden, for: .tabBar)
                        // Platz für die schwebende Leiste in allen Scroll-Ansichten des Bereichs
                        // (auch auf Unterseiten), damit das Ende von Listen nicht verdeckt wird;
                        // Inhalte scrollen weiterhin darunter durch. `safeAreaInset` erreicht die
                        // Inhalte im NavigationStack hier nicht (im Simulator geprüft).
                        // Verschachtelte horizontale Scroll-Ansichten setzen den Rand auf 0 zurück.
                        .contentMargins(.bottom, contentInset)
                        .environment(\.floatingTabBarHeight, contentInset)
                        .environment(\.openNewTask, OpenNewTaskAction(action: openNewTask))
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeArea = $0 }
        .overlay(alignment: .bottom) {
            // Weicher Übergang wie bei der System-Leiste: Inhalte dunkeln zum unteren Rand hin ab,
            // statt hart hinter der Leiste zu verschwinden.
            LinearGradient(
                colors: [FamiliarColor.canvas.opacity(0), FamiliarColor.canvas.opacity(0.85), FamiliarColor.canvas],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: tabBarHeight + barBottomInset + 28)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection, onCreateTask: openNewTask)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
                .padding(.bottom, barBottomInset)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .sheet(isPresented: $isCreatingTask) {
            TaskEditorView(mode: .create)
        }
        .task(id: session.userID) {
            if let userID = session.userID { await tasks.start(userID: userID) }
        }
        .task(id: session.userID) {
            if session.userID != nil { await outlook.reload() } else { outlook.stop() }
        }
        .task(id: session.userID) {
            guard let userID = session.userID else { return }
            await notifications.start(userID: userID)
            // Der Abgleich kann vor dem Start gelaufen und dabei übersprungen worden sein.
            await reconcileLiveActivities()
            // Einmal je Konto erklären, wofür Familiar Mitteilungen nutzt – erst dann fragt das System.
            if notifications.isAvailable && notifications.authorization == .notDetermined
                && !notifications.hasAskedForPermission(userID) {
                showsNotificationPrimer = true
            }
        }
        .task(id: tasks.changeToken) { await reconcileLiveActivities() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reconcileLiveActivities() } }
        }
        .onChange(of: notifications.requestedTaskID) { _, taskID in
            if taskID != nil { selection = .tasks }
        }
        .sheet(isPresented: $showsNotificationPrimer) {
            NotificationPrimerView()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: createTaskRequests)
    }

    /// Nur mit geladener Liste abgleichen – sonst würden laufende Activities fälschlich beendet.
    private func reconcileLiveActivities() async {
        guard tasks.state == .loaded else { return }
        if let userID = session.userID {
            WidgetSync.update(openTasks: tasks.tasks, families: session.families, userID: userID)
        }
        await notifications.refreshAuthorization()
        await notifications.reconcile(openTasks: tasks.tasks, families: session.families)
    }

    private func openNewTask() {
        createTaskRequests += 1
        // Ohne Recht in allen Familien: erklären statt ein Formular zeigen, das nicht speichern kann.
        if !session.families.isEmpty && !session.canCreateTasksAnywhere {
            tasks.notify(String(localized: "In deinen Familien dürfen nur Admins Aufgaben anlegen."))
            return
        }
        isCreatingTask = true
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .tasks: TasksHomeView()
        case .calendar: CalendarHomeView()
        case .history: HistoryHomeView()
        }
    }
}

#if DEBUG
#Preview {
    RootTabView()
        .previewEnvironment(.ready)
}
#endif
