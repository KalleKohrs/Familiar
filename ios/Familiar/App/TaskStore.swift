import FamiliarCore
import Foundation
import Observation

/// Offene Aufgaben der Startseite und alle Aufgaben-Aktionen.
///
/// Die Datenbank ist maßgeblich: Nach jeder Aktion und jedem Realtime-Hinweis wird neu geladen,
/// statt lokale Kopien fortzuschreiben.
@Observable
final class TaskStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(FamiliarError)
    }

    /// Hinweis mit „Rückgängig“ direkt nach dem Abhaken oder Löschen (Plan, Abschnitt 4).
    struct UndoOffer: Identifiable, Equatable {
        enum Kind: Equatable {
            case uncomplete(CompletionScope)
            case restore
            case restoreSeries(deletionID: UUID)
        }

        let id = UUID()
        let taskID: UUID
        let message: String
        let kind: Kind
    }

    private(set) var tasks: [TaskItem] = []
    private(set) var state: LoadState = .idle
    private(set) var undo: UndoOffer?
    private(set) var actionError: String?
    private(set) var busyTaskIDs: Set<UUID> = []
    /// Verlauf: erledigte und gelöschte Aufgaben sowie gelöschte Serien der letzten 30 Tage, neueste zuerst.
    private(set) var history: [HistoryEntry] = []
    private(set) var historyState: LoadState = .idle
    /// Gab es in dieser Sitzung offene Aufgaben? Dann heißt die leere Liste „Alles erledigt“.
    private(set) var hadOpenTasks = false

    private let repository: any TaskRepository
    private var userID: UUID?
    private var changesTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    init(repository: any TaskRepository) {
        self.repository = repository
    }

    /// Lädt die Aufgaben und hört auf Realtime-Hinweise für diesen Nutzer.
    func start(userID: UUID) async {
        if self.userID != userID {
            stop()
            self.userID = userID
            let changes = repository.changes(for: userID)
            changesTask = Task { [weak self] in
                for await _ in changes {
                    self?.scheduleReload()
                }
            }
        }
        await reload()
    }

    func stop() {
        changesTask?.cancel()
        changesTask = nil
        userID = nil
        tasks = []
        state = .idle
        history = []
        historyState = .idle
        hadOpenTasks = false
        undo = nil
    }

    /// Lädt Liste und – falls schon geöffnet – den Verlauf neu.
    func refreshAll() async {
        await reload()
        if historyState != .idle { await reloadHistory() }
    }

    func reloadHistory() async {
        if history.isEmpty { historyState = .loading }
        do throws(FamiliarError) {
            let tasks = try await repository.historyTasks()
            let deletions = try await repository.seriesDeletions()
            history = HistoryRules.entries(tasks, deletions: deletions)
            historyState = .loaded
        } catch {
            if history.isEmpty { historyState = .failed(error) } else { showError(error.message) }
        }
    }

    /// Wiederherstellen aus dem Verlauf (jedes Mitglied mit Sicht, Guide, Abschnitt 3):
    /// gelöschte Aufgaben kommen zurück, erledigte werden wieder offen, gelöschte Serien
    /// samt ihrer offenen Vorkommen wieder aktiv.
    func restoreFromHistory(_ entry: HistoryEntry) async -> Bool {
        busyTaskIDs.insert(entry.id)
        defer { busyTaskIDs.remove(entry.id) }
        do throws(FamiliarError) {
            switch entry {
            case .seriesDeletion(let deletion):
                try await repository.restoreSeries(deletionID: deletion.id)
            case .task(let task):
                switch HistoryRules.kind(of: task) {
                case .deleted: try await repository.restore(taskID: task.id)
                case .completed: try await repository.uncomplete(taskID: task.id, scope: .all)
                case nil: return true
                }
            }
            await refreshAll()
            return true
        } catch {
            showError(error.message)
            await refreshAll()
            return false
        }
    }

    func reload() async {
        // Ladeanzeige nur beim ersten Laden – sonst blitzen Platzhalter auf, sobald die letzte
        // Aufgabe erledigt ist.
        if state == .idle { state = .loading }
        do throws(FamiliarError) {
            tasks = TaskRules.homeOrder(try await repository.openTasks())
            if !tasks.isEmpty { hadOpenTasks = true }
            state = .loaded
            // Leere Liste: am Verlauf erkennen, ob „Alles erledigt“ oder „Noch keine Aufgaben“ passt.
            if tasks.isEmpty && historyState == .idle { await reloadHistory() }
        } catch {
            // Beim Aktualisieren bleibt die bisherige Liste stehen.
            if tasks.isEmpty { state = .failed(error) } else { showError(error.message) }
        }
    }

    /// Mehrere Hinweise kurz hintereinander lösen nur ein Neuladen aus.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refreshAll()
        }
    }

    /// Aufgaben und geplante Serientermine eines Zeitraums (Kalender, Phase 6).
    func calendarData(from: LocalDate, through: LocalDate) async throws(FamiliarError)
        -> (tasks: [TaskItem], projected: [ProjectedOccurrence]) {
        let tasks = try await repository.calendarTasks(from: from, through: through)
        let projected = try await repository.projectedOccurrences(from: from, through: through)
        return (tasks, projected)
    }

    /// Ändert sich, sobald Liste oder Verlauf neu geladen wurden – Anlass für den Kalender, nachzuladen.
    var changeToken: Int {
        var hasher = Hasher()
        for task in tasks { hasher.combine(task.id); hasher.combine(task.version) }
        hasher.combine(history.count)
        return hasher.finalize()
    }

    func task(_ id: UUID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    func fetch(_ id: UUID) async throws(FamiliarError) -> TaskItem {
        try await repository.task(id: id)
    }

    // MARK: Abhaken, Löschen, Rückgängig

    func perform(_ action: TaskCompletionAction, on task: TaskItem) async {
        busyTaskIDs.insert(task.id)
        defer { busyTaskIDs.remove(task.id) }
        do throws(FamiliarError) {
            switch action {
            case .completeForMe:
                try await repository.complete(taskID: task.id, scope: .me)
                let message = task.completionMode == .each
                    ? String(localized: "Für dich abgehakt")
                    : String(localized: "Erledigt")
                offerUndo(task.id, message: message, kind: .uncomplete(.me))
            case .completeForAll:
                try await repository.complete(taskID: task.id, scope: .all)
                offerUndo(task.id, message: String(localized: "Für alle erledigt"), kind: .uncomplete(.all))
            case .undoMine:
                try await repository.uncomplete(taskID: task.id, scope: .me)
            }
        } catch {
            showError(error.message)
        }
        await refreshAll()
    }

    func delete(_ task: TaskItem) async -> Bool {
        busyTaskIDs.insert(task.id)
        defer { busyTaskIDs.remove(task.id) }
        do throws(FamiliarError) {
            try await repository.delete(taskID: task.id)
            offerUndo(task.id, message: String(localized: "Aufgabe gelöscht"), kind: .restore)
            await refreshAll()
            return true
        } catch {
            showError(error.message)
            return false
        }
    }

    /// „Gesamte Serie“ löschen (Guide, Abschnitt 4); ein Verlaufseintrag mit Rückgängig.
    func deleteSeries(from task: TaskItem) async -> Bool {
        busyTaskIDs.insert(task.id)
        defer { busyTaskIDs.remove(task.id) }
        do throws(FamiliarError) {
            let deletionID = try await repository.deleteSeries(fromTaskID: task.id)
            offerUndo(task.id, message: String(localized: "Serie gelöscht"), kind: .restoreSeries(deletionID: deletionID))
            await refreshAll()
            return true
        } catch {
            showError(error.message)
            return false
        }
    }

    func performUndo() async {
        guard let offer = undo else { return }
        undo = nil
        do throws(FamiliarError) {
            switch offer.kind {
            case .uncomplete(let scope): try await repository.uncomplete(taskID: offer.taskID, scope: scope)
            case .restore: try await repository.restore(taskID: offer.taskID)
            case .restoreSeries(let deletionID): try await repository.restoreSeries(deletionID: deletionID)
            }
        } catch {
            showError(error.message)
        }
        await refreshAll()
    }

    func dismissBanner() {
        undo = nil
        actionError = nil
    }

    private func offerUndo(_ taskID: UUID, message: String, kind: UndoOffer.Kind) {
        actionError = nil
        undo = UndoOffer(taskID: taskID, message: message, kind: kind)
        scheduleBannerDismissal()
    }

    /// Hinweis unten anzeigen (z. B. fehlendes Recht), ohne dass eine Aktion lief.
    func notify(_ message: String) {
        showError(message)
    }

    private func showError(_ message: String) {
        undo = nil
        actionError = message
        scheduleBannerDismissal()
    }

    private func scheduleBannerDismissal() {
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    // MARK: Anlegen und Bearbeiten

    /// Geltungsbereich beim Bearbeiten eines Vorkommens (Guide, Abschnitt 4).
    enum EditScope {
        case thisOccurrence
        case thisAndFuture
    }

    /// Lädt neue Bilder hoch und legt die Aufgabe bzw. Serie an oder speichert den vollständigen Stand.
    /// Liefert die gespeicherte Aufgabe; beim Anlegen einer Serie `nil` (die Vorkommen erscheinen in der Liste).
    @discardableResult
    func save(_ draft: TaskDraft, editing original: TaskItem?, scope: EditScope = .thisOccurrence,
              onUploadProgress: (Int, Int) -> Void = { _, _ in }) async throws(FamiliarError) -> TaskItem? {
        guard let input = draft.input() else {
            throw .unknown(message: "Ungültiger Entwurf")
        }
        let newImages = draft.images.compactMap { image -> PreparedImage? in
            if case .new(let prepared) = image { return prepared }
            return nil
        }
        for (index, image) in newImages.enumerated() {
            onUploadProgress(index + 1, newImages.count)
            try await repository.upload(image, familyID: input.familyID)
        }
        let saved: TaskItem?
        if let original {
            if original.isOccurrence && scope == .thisAndFuture && input.recurrence != nil {
                saved = try await repository.updateSeries(fromTaskID: original.id, expectedVersion: original.version, input)
            } else {
                var single = input
                single.recurrence = nil
                saved = try await repository.updateTask(id: original.id, expectedVersion: original.version, single)
            }
        } else if input.recurrence != nil {
            try await repository.createSeries(input)
            saved = nil
        } else {
            saved = try await repository.createTask(input)
        }
        await reload()
        return saved
    }
}
