import AppIntents
import FamiliarActivity
import Foundation
import os

/// Abhaken direkt in der Live Activity und im Widget. Läuft laut Apple im Prozess der App (`LiveActivityIntent`),
/// auch wenn die App dafür im Hintergrund gestartet wird. Die App hinterlegt beim Start, wie abgehakt wird
/// (``TaskCompletionBridge``); die Datenbank entscheidet über die Berechtigung.
///
/// Wichtig: Diese Datei gehört zu App **und** Widget-Extension (Ordner `Shared`) und darf nicht in ein Swift-Paket
/// wandern. Das System sucht die Metadaten einer Aktion nur in der ausführbaren Datei der App; liegt sie in einem
/// Paket, meldet iOS in TestFlight- und App-Store-Builds „There is no metadata for CompleteTaskIntent“, und der
/// Haken tut nichts (in Xcode-Builds fällt das nicht auf).
struct CompleteTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aufgabe abhaken"
    static let isDiscoverable = false

    @Parameter(title: "Aufgabe")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let log = Logger(subsystem: "de.kohrs.familiar", category: "live-activity")
        FamiliarDiagnostics.record("Haken in Live Activity getippt")
        log.notice("Abhaken aus Live Activity gestartet")
        do {
            try await TaskCompletionBridge.shared.completeWithRetry(id)
            // Sofort vom Sperrbildschirm nehmen, nicht erst auf den Server-Push warten.
            await LiveActivityEnding.end(taskID: id)
            FamiliarDiagnostics.record("Abhaken erledigt")
            log.notice("Abhaken aus Live Activity erledigt")
        } catch {
            FamiliarDiagnostics.record("Abhaken fehlgeschlagen: \(String(describing: error))")
            log.error("Abhaken aus Live Activity fehlgeschlagen: \(String(describing: error), privacy: .public)")
            throw error
        }
        return .result()
    }
}
