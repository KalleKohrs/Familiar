import AppIntents
import FamiliarActivity
import SwiftUI
import WidgetKit

@main
struct FamiliarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TaskLiveActivityWidget()
        TodayWidget()
    }
}

/// Bindet die App Intents aus FamiliarActivity (Abhak-Knopf) in die Extension ein.
struct FamiliarWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FamiliarActivityIntents.self] }
}
