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
