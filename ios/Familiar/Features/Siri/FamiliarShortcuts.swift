import AppIntents
import FamiliarCore
import Foundation

/// Siri und Kurzbefehle (ADR 0010): Aufgabe erledigen, Aufgabe hinzufügen, „Was steht heute an?“.
/// Die Intents laufen im Prozess der App mit der gespeicherten Anmeldung; die App hinterlegt beim Start
/// ihre Datenquellen in ``IntentEnvironment``.
@MainActor
enum IntentEnvironment {
    static var dependencies: AppDependencies?
    /// Nach einer Änderung: Listen, Widgets und Live Activities neu laden.
    static var didChange: (@MainActor () async -> Void)?

    static func notifyChange() async {
        await didChange?()
    }

    static func require() throws -> AppDependencies {
        guard let dependencies else { throw IntentError.notReady }
        return dependencies
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case notSignedIn
    case noFamily
    case notAllowed
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "Familiar startet gerade. Bitte versuche es gleich noch einmal."
        case .notSignedIn: "Bitte melde dich zuerst in Familiar an."
        case .noFamily: "Du bist noch in keiner Familie. Lege in Familiar zuerst eine an."
        case .notAllowed: "Diese Aufgabe kannst du nicht abhaken – sie ist anderen zugewiesen."
        case .failed(let message): "\(message)"
        }
    }

    static func from(_ error: FamiliarError) -> IntentError {
        if case .notAuthenticated = error { return .notSignedIn }
        return .failed(error.message)
    }
}

// MARK: Aufgaben als Parameter

struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Aufgabe"
    static let defaultQuery = TaskEntityQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

/// Offene, sichtbare Aufgaben; Suche nach Titel (ohne Groß-/Kleinschreibung und Akzente).
struct TaskEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        try await openTasks().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [TaskEntity] {
        let query = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return try await openTasks().filter {
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
        }
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        try await openTasks()
    }

    /// Nur Aufgaben, die die Person abhaken darf (wie die Knöpfe in der App); gleiche Titel
    /// (z. B. Serie heute und morgen): der frühere Termin zuerst.
    private func openTasks() async throws -> [TaskEntity] {
        let dependencies = try await IntentEnvironment.require()
        do {
            let me = try await dependencies.profiles.myProfile().id
            return try await dependencies.tasks.openTasks()
                .filter { task in
                    TaskRules.actions(for: task, userID: me).contains { $0 == .completeForMe || $0 == .completeForAll }
                }
                .sorted { ($0.startDate ?? .init(year: 1, month: 1, day: 1)) < ($1.startDate ?? .init(year: 1, month: 1, day: 1)) }
                .map { TaskEntity(id: $0.id, title: $0.title) }
        } catch {
            throw IntentError.from(error)
        }
    }
}

struct FamilyEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Familie"
    static let defaultQuery = FamilyEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FamilyEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [FamilyEntity] {
        try await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FamilyEntity] { try await all() }

    private func all() async throws -> [FamilyEntity] {
        let dependencies = try await IntentEnvironment.require()
        do {
            return try await dependencies.families.myFamilies().map { FamilyEntity(id: $0.family.id, name: $0.family.name) }
        } catch {
            throw IntentError.from(error)
        }
    }
}

// MARK: Intents

struct CompleteTaskByNameIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufgabe erledigen"
    static let description = IntentDescription("Hakt eine offene Aufgabe in Familiar ab.")
    /// Familiendaten nur bei entsperrtem iPhone ändern.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Aufgabe", requestValueDialog: "Welche Aufgabe ist erledigt?")
    var task: TaskEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dependencies = try await IntentEnvironment.require()
        do {
            // Wie in der App: als zugewiesene Person den eigenen Teil, als Erstellerin ohne Zuweisung „für alle“.
            let me = try await dependencies.profiles.myProfile().id
            let current = try await dependencies.tasks.task(id: task.id)
            let actions = TaskRules.actions(for: current, userID: me)
            if actions.contains(.completeForMe) {
                try await dependencies.tasks.complete(taskID: task.id, scope: .me)
            } else if actions.contains(.completeForAll) {
                try await dependencies.tasks.complete(taskID: task.id, scope: .all)
            } else {
                throw IntentError.notAllowed
            }
        } catch let error as FamiliarError {
            throw IntentError.from(error)
        }
        await IntentEnvironment.notifyChange()
        return .result(dialog: "„\(task.title)“ ist erledigt.")
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufgabe hinzufügen"
    static let description = IntentDescription("Legt in Familiar eine Aufgabe für dich an.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Aufgabe", requestValueDialog: "Was soll erledigt werden?")
    var title: String

    @Parameter(title: "Familie")
    var family: FamilyEntity?

    @Parameter(title: "Tag")
    var day: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dependencies = try await IntentEnvironment.require()
        let trimmed = InputRules.trimmed(title)
        guard TaskDraft.titleLength.contains(trimmed.count) else {
            throw $title.needsValueError("Wie soll die Aufgabe heißen?")
        }
        do {
            let me = try await dependencies.profiles.myProfile().id
            let families = try await dependencies.families.myFamilies()
            let familyID: UUID
            if let family {
                familyID = family.id
            } else if families.count == 1, let only = families.first {
                familyID = only.family.id
            } else if families.isEmpty {
                throw IntentError.noFamily
            } else {
                throw $family.needsValueError("Für welche Familie?")
            }
            let timezone = TimeZone.current
            let input = TaskInput(familyID: familyID, title: trimmed, description: nil,
                                  startDate: day.map { LocalDate($0, timeZone: timezone) }, startTime: nil,
                                  timezone: timezone.identifier, completionMode: .anyOne, assigneeIDs: [me],
                                  images: [])
            _ = try await dependencies.tasks.createTask(input)
        } catch let error as FamiliarError {
            throw IntentError.from(error)
        }
        await IntentEnvironment.notifyChange()
        return .result(dialog: "„\(trimmed)“ ist eingetragen.")
    }
}

struct TodayTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Was steht heute an?"
    static let description = IntentDescription("Liest deine offenen Aufgaben für heute vor.")
    /// Aufgabentitel nicht bei gesperrtem iPhone vorlesen.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dependencies = try await IntentEnvironment.require()
        do {
            let me = try await dependencies.profiles.myProfile().id
            let snapshot = WidgetSnapshot(openTasks: try await dependencies.tasks.openTasks(),
                                          families: try await dependencies.families.myFamilies(), userID: me)
            let titles = WidgetRules.today(snapshot, onlyMine: true).map(\.item.title)
            switch titles.count {
            case 0:
                return .result(dialog: "Für heute ist alles erledigt.")
            case 1:
                return .result(dialog: "Heute steht an: \(titles[0]).")
            default:
                let shown = titles.prefix(5).formatted(.list(type: .and))
                let more = titles.count > 5 ? String(localized: " Und \(titles.count - 5) weitere.") : ""
                return .result(dialog: "Heute stehen \(titles.count) Aufgaben an: \(shown).\(more)")
            }
        } catch let error as FamiliarError {
            throw IntentError.from(error)
        }
    }
}

// MARK: App Shortcuts (ohne Einrichtung in Siri und der Kurzbefehle-App)

struct FamiliarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteTaskByNameIntent(),
            phrases: [
                "\(\.$task) in \(.applicationName) erledigen",
                "\(\.$task) in \(.applicationName) abhaken",
                "Aufgabe in \(.applicationName) erledigen",
            ],
            shortTitle: "Aufgabe erledigen",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Neue Aufgabe in \(.applicationName)",
                "Aufgabe in \(.applicationName) hinzufügen",
            ],
            shortTitle: "Aufgabe hinzufügen",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodayTasksIntent(),
            phrases: [
                "Was steht heute in \(.applicationName) an",
                "Meine Aufgaben in \(.applicationName)",
            ],
            shortTitle: "Heute",
            systemImageName: "checklist"
        )
    }
}
