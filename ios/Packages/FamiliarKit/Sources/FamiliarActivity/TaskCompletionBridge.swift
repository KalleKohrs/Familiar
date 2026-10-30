import FamiliarCore
import Foundation
import Synchronization

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
    public func complete(_ taskID: UUID) async throws {
        guard let handler = handler.withLock({ $0 }) else { throw BridgeError.notReady }
        try await handler(taskID)
    }

    /// Wie ``complete(_:)``, aber robust für den Start im Hintergrund: Ist die App noch nicht bereit (Handler fehlt),
    /// wird bis zu drei Sekunden gewartet. Bei Verbindungsfehlern (z. B. veraltete Verbindung nach dem Aufwecken
    /// der App) folgen zwei weitere Versuche. Fachliche Fehler (keine Berechtigung usw.) gelten sofort.
    @MainActor
    public func completeWithRetry(_ taskID: UUID) async throws {
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
