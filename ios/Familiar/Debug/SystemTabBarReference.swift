#if DEBUG
import FamiliarDesign
import SwiftUI

/// Nur zum Messen (`-FamiliarSystemTabBarReference`): eine echte System-`TabView` mit denselben drei
/// Bereichen, damit sich Maße der Systemleiste (Höhe, Kapsel-Einrückung, Symbole, Ränder) im Simulator
/// pixelgenau mit der eigenen ``FloatingTabBar`` vergleichen lassen. Kommt nie in die Release-App.
struct SystemTabBarReference: View {
    @State private var selection: AppTab = .tasks

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    ZStack {
                        FamiliarColor.canvas.ignoresSafeArea()
                        Text(tab.title).foregroundStyle(FamiliarColor.textPrimary)
                    }
                }
            }
        }
    }
}
#endif
