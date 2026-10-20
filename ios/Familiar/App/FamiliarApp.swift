import FamiliarDesign
import SwiftUI

@main
struct FamiliarApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .tint(FamiliarColor.accent)
        }
    }
}
