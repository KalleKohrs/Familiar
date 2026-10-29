import AppIntents
import Foundation
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
        try await TaskCompletionBridge.shared.complete(id)
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

    enum BridgeError: Error {
        case notReady
    }
}

/// App Intents aus diesem Paket für App und Widget-Extension (siehe `AppIntentsPackage`).
public struct FamiliarActivityIntents: AppIntentsPackage {}
