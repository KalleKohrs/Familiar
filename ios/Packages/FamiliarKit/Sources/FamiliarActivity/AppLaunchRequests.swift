import Foundation
import Synchronization

/// Brücke von Steuerelementen (Kontrollzentrum, Sperrbildschirm-Taste) in die App: Das Steuerelement startet
/// einen Intent, der in der App läuft und hier „Neue Aufgabe“ anmeldet. Ist die App schon bereit, öffnet sie das
/// Formular sofort; läuft sie gerade erst an, wird die Anfrage kurz vorgemerkt.
///
/// Anfragen verfallen nach 60 Sekunden – wer die App aus dem Kontrollzentrum startet, aber erst danach
/// anmeldet, soll nicht plötzlich ein Formular sehen.
public final class AppLaunchRequests: Sendable {
    public typealias Handler = @MainActor @Sendable () -> Void

    public static let shared = AppLaunchRequests()
    public static let validity: TimeInterval = 60

    private struct State {
        var handler: Handler?
        var pendingNewTask: Date?
    }

    private let state = Mutex(State())

    public init() {}

    /// Vom Intent aufgerufen (im Prozess der App).
    @MainActor
    public func requestNewTask(now: Date = .now) {
        let handler = state.withLock { state -> Handler? in
            if let handler = state.handler { return handler }
            state.pendingNewTask = now
            return nil
        }
        handler?()
    }

    /// Die App meldet sich an, sobald sie ein Formular öffnen kann. Eine vorgemerkte, noch gültige
    /// Anfrage wird sofort ausgeführt. Mit `nil` abmelden (z. B. beim Abmelden des Kontos).
    @MainActor
    public func setNewTaskHandler(_ handler: Handler?, now: Date = .now) {
        let runNow = state.withLock { state -> Bool in
            state.handler = handler
            defer { state.pendingNewTask = nil }
            guard handler != nil, let requested = state.pendingNewTask else { return false }
            return now.timeIntervalSince(requested) <= Self.validity
        }
        if runNow { handler?() }
    }
}
