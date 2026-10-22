import FamiliarCore
import Foundation
import WidgetKit

/// Hält die Widgets „Heute“ aktuell (ADR 0010): Schnappschuss schreiben und nur bei Änderung neu laden.
enum WidgetSync {
    static let kind = "FamiliarToday"

    static func update(openTasks: [TaskItem], families: [FamilyMembership], userID: UUID) {
        let snapshot = WidgetSnapshot(openTasks: openTasks, families: families, userID: userID)
        if WidgetSnapshotStore.write(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    static func clear() {
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
