import AppIntents
import FamiliarActivity
import Foundation

/// Namen der Steuerelemente (Kontrollzentrum, Sperrbildschirm-Tasten) – App und Widget-Extension brauchen sie beide.
enum ControlKind {
    static let newTask = "de.kohrs.familiar.control.newTask"
    static let openToday = "de.kohrs.familiar.control.openToday"
}

/// „Neue Aufgabe“ aus dem Kontrollzentrum: öffnet Familiar mit dem Formular für eine neue Aufgabe.
///
/// Wichtig: Diese Datei gehört zu App **und** Widget-Extension (Ordner `Shared`) und darf nicht in ein Swift-Paket
/// wandern – siehe `CompleteTaskIntent` (das System sucht die Metadaten nur in der ausführbaren Datei der App).
struct OpenNewTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Neue Aufgabe"
    static let description = IntentDescription("Öffnet Familiar mit einer neuen Aufgabe.")
    static let isDiscoverable = false
    /// Die App kommt nach vorn; `perform()` läuft in ihrem Prozess.
    static let supportedModes: IntentModes = .foreground

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppLaunchRequests.shared.requestNewTask()
        return .result()
    }
}

/// „Heute offen“ aus dem Kontrollzentrum: öffnet Familiar (Aufgabenliste).
struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Heute offen"
    static let description = IntentDescription("Öffnet Familiar.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}
