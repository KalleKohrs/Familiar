import FamiliarDesign
import SwiftUI

/// Hauptnavigation: drei Bereiche in einer `TabView` (behält den Zustand je Bereich),
/// deren System-Tab-Bar ausgeblendet und durch die eigene ``FloatingTabBar`` ersetzt ist.
struct RootTabView: View {
    @State private var selection: AppTab = .tasks
    @State private var isCreatingTask = false
    @State private var createTaskRequests = 0
    @State private var tabBarHeight: CGFloat = 0

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
                        .contentMargins(.bottom, tabBarHeight)
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                }
            }
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection) {
                createTaskRequests += 1
                isCreatingTask = true
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
        }
        .sheet(isPresented: $isCreatingTask) {
            NewTaskSheet()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: createTaskRequests)
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

#Preview {
    RootTabView()
        .previewEnvironment(.ready)
}
