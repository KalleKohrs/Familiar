import ActivityKit
import Foundation

/// Beendet Live Activities einer Aufgabe auf diesem Gerät sofort.
///
/// Nach dem Abhaken in der Live Activity darf sie nicht noch bis zum nächsten Server-Push (bis zu einer Minute)
/// stehen bleiben: Sonst tippt man mehrfach und hält das Abhaken für gescheitert. Der Server beendet sie später
/// zusätzlich; ein zweites Ende ist unschädlich.
public enum LiveActivityEnding {
    /// `Activity` ist nicht `Sendable`: nur über die Aufgaben-ID nachschlagen und beenden.
    nonisolated public static func end(taskID: UUID) async {
        for activity in Activity<TaskActivityAttributes>.activities where activity.attributes.taskID == taskID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
