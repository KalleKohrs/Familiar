import AppIntents
import FamiliarCore
import Foundation
import os
import Synchronization

/// Abhaken direkt in der Live Activity. Läuft laut Apple im Prozess der App (`LiveActivityIntent`),
/// auch wenn die App dafür im Hintergrund gestartet wird. Die App hinterlegt beim Start, wie
/// abgehakt wird (``TaskCompletionBridge``); die Datenbank entscheidet über die Berechtigung.
public struct CompleteTaskIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Aufgabe abhaken"
    public static let isDiscoverable = false

    @Parameter(title: "Aufgabe")
    public var taskID: String

    public init() {}

    public init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let log = Logger(subsystem: "de.kohrs.familiar", category: "live-activity")
        FamiliarDiagnostics.record("Haken in Live Activity getippt")
        log.notice("Abhaken aus Live Activity gestartet")
        do {
            try await TaskCompletionBridge.shared.completeWithRetry(id)
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

/// Verbindung vom Intent zur App: Die App setzt beim Start den Handler (Repository-Aufruf).
public final class TaskCompletionBridge: Sendable {
    /// Läuft auf dem MainActor: Danach werden Listen, Widgets und Siri-Parameter (UIKit/WidgetKit) angefasst.
    public typealias Handler = @MainActor @Sendable (UUID) async throws -> Void

    public static let shared = TaskCompletionBridge()

    private let handler = Mutex<Handler?>(nil)

    public func setHandler(_ handler: Handler?) {
        self.handler.withLock { $0 = handler }
    }

    @MainActor
    func complete(_ taskID: UUID) async throws {
        guard let handler = handler.withLock({ $0 }) else { throw BridgeError.notReady }
        try await handler(taskID)
    }

    /// Wie ``complete(_:)``, aber robust für den Start im Hintergrund: Ist die App noch nicht bereit (Handler fehlt),
    /// wird bis zu drei Sekunden gewartet. Bei Verbindungsfehlern (z. B. veraltete Verbindung nach dem Aufwecken
    /// der App) folgen zwei weitere Versuche. Fachliche Fehler (keine Berechtigung usw.) gelten sofort.
    @MainActor
    func completeWithRetry(_ taskID: UUID) async throws {
        var waited = 0
        while handler.withLock({ $0 }) == nil, waited < 6 {
            FamiliarDiagnostics.record("App noch nicht bereit, warte")
            try? await Task.sleep(for: .milliseconds(500))
            waited += 1
        }
        var attempt = 1
        while true {
            do {
                try await complete(taskID)
                return
            } catch let error as FamiliarError where error == .offline && attempt < 3 {
                attempt += 1
                FamiliarDiagnostics.record("Keine Verbindung, Versuch \(attempt)")
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    enum BridgeError: Error {
        case notReady
    }
}

/// App Intents aus diesem Paket für App und Widget-Extension (siehe `AppIntentsPackage`).
public struct FamiliarActivityIntents: AppIntentsPackage {}
