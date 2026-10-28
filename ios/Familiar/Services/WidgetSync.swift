import AppIntents
import FamiliarCore
import Foundation
import WidgetKit

/// Hält die Widgets „Heute“ aktuell (ADR 0010): Schnappschuss schreiben und nur bei Änderung neu laden.
enum WidgetSync {
    static let kind = "FamiliarToday"

    /// Konto, für das geschrieben werden darf. Beim Abmelden sofort `nil` – so legt ein noch laufendes
    /// Neuladen den Schnappschuss nicht wieder an.
    private static var activeUserID: UUID?

    /// Nach der Anmeldung (auch beim Start mit gespeicherter Sitzung).
    static func activate(userID: UUID) {
        activeUserID = userID
    }

    static func update(openTasks: [TaskItem], families: [FamilyMembership], userID: UUID) {
        guard userID == activeUserID else { return }
        let snapshot = WidgetSnapshot(openTasks: openTasks, families: families, userID: userID)
        if WidgetSnapshotStore.write(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            // Siri kennt die aktuellen Aufgabentitel für „… in Familiar erledigen“.
            FamiliarShortcuts.updateAppShortcutParameters()
        }
    }

    /// Bei jeder Abmeldung – auch wenn die Sitzung von selbst endet (z. B. „Überall abmelden“ woanders).
    static func clear() {
        activeUserID = nil
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
