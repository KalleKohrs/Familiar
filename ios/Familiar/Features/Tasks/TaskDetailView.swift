import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Aufgabendetails mit „Bearbeiten“ oben (Guide, Abschnitt 2), Personenstatus, Bildern,
/// Abhak-Aktionen und Löschen.
struct TaskDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID

    @State private var fetched: TaskItem?
    @State private var loadError: String?
    @State private var editing: TaskItem?
    @State private var gallery: GalleryState?
    @State private var confirmDelete = false

    /// Aus der Liste (aktuell per Realtime) oder einmalig geladen, falls nicht in der Liste.
    private var task: TaskItem? { store.task(taskID) ?? fetched }

    var body: some View {
        Group {
            if let task {
                content(task)
            } else if let loadError {
                FamiliarErrorState(message: loadError) { Task { await load() } }
                    .familiarCard()
                    .padding(FamiliarSpacing.m)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .familiarContentSwap(value: task == nil)
        .familiarScreenBackground()
        // Rückmeldungen (Erinnert, Fehler) auch hier sichtbar, nicht nur auf den Hauptbildschirmen.
        .overlay(alignment: .bottom) { TaskBanner() }
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.task(taskID) == nil { await load() } }
        .sheet(item: $editing) { task in
            TaskEditorView(mode: .edit(task))
        }
        .fullScreenCover(item: $gallery) { state in
            ImageGalleryView(images: state.images, startIndex: state.index)
        }
    }

    private func load() async {
        loadError = nil
        do throws(FamiliarError) {
            fetched = try await store.fetch(taskID)
        } catch {
            loadError = error.message
        }
    }

    private func content(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.l) {
                header(task)
                peopleSection(task)
                if !task.images.isEmpty {
                    imagesSection(task)
                }
                actionsSection(task)
            }
            .padding(FamiliarSpacing.m)
        }
        .toolbar {
            if task.isOpen && session.allows(.editTasks, in: task.familyID) {
                ToolbarItem(placement: .primaryAction) {
                    Button("Bearbeiten") { editing = task }
                        .accessibilityIdentifier("task.edit")
                }
            }
        }
        .sheet(isPresented: $confirmDelete) {
            if task.isOccurrence {
                FamiliarChoiceSheet(
                    systemImage: "trash", tint: FamiliarColor.danger,
                    title: "Wiederkehrende Aufgabe löschen?",
                    message: "Bei der ganzen Serie entfallen alle offenen Termine; erledigte bleiben. Beides lässt sich 30 Tage lang im Verlauf wiederherstellen."
                ) {
                    Button("Nur diesen Termin löschen", role: .destructive) { deleteNow(task, series: false) }
                        .buttonStyle(.familiarDestructive)
                        .accessibilityIdentifier("delete.single")
                    Button("Ganze Serie löschen", role: .destructive) { deleteNow(task, series: true) }
                        .buttonStyle(.familiarDestructive)
                        .accessibilityIdentifier("delete.series")
                }
            } else {
                FamiliarChoiceSheet(
                    systemImage: "trash", tint: FamiliarColor.danger,
                    title: "Aufgabe löschen?",
                    message: "Sie landet im Verlauf und lässt sich dort 30 Tage lang wiederherstellen."
                ) {
                    Button("Löschen", role: .destructive) { deleteNow(task, series: false) }
                        .buttonStyle(.familiarDestructive)
                        .accessibilityIdentifier("delete.confirm")
                }
            }
        }
    }

    private func deleteNow(_ task: TaskItem, series: Bool) {
        confirmDelete = false
        Task {
            let deleted = series ? await store.deleteSeries(from: task) : await store.delete(task)
            if deleted { dismiss() }
        }
    }

    private func header(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            if let family = session.membership(task.familyID)?.family {
                FamilyBadge(name: family.name, color: Color(session.familyDisplayColors[task.familyID] ?? family.color))
            }
            Text(task.title)
                .font(FamiliarFont.title)
                .foregroundStyle(FamiliarColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let description = task.description {
                Text(description)
                    .font(FamiliarFont.body)
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .textSelection(.enabled)
            }
            TaskMetaTags(task: task)
            if let rotation = rotationText(task) {
                FamiliarTag(rotation, systemImage: "arrow.triangle.2.circlepath", tone: .neutral)
                    .accessibilityIdentifier("task.rotation")
            }
            if task.isOccurrence && task.isDetached {
                Text("Dieses Vorkommen wurde einzeln geändert; Änderungen an der Serie gelten hier nicht.")
                    .font(FamiliarFont.meta)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
            if !task.isOpen {
                FamiliarTag(task.deletedAt != nil ? "Gelöscht" : "Erledigt",
                            systemImage: task.deletedAt != nil ? "trash" : "checkmark",
                            tone: task.deletedAt != nil ? .danger : .success)
            }
            FamiliarTag(TaskFormatting.modeTitle(task.completionMode),
                        systemImage: TaskFormatting.modeSymbol(task.completionMode), tone: .neutral)
                .accessibilityHint(TaskFormatting.modeExplanation(task.completionMode))
            if let creator = task.createdBy {
                Text("Erstellt von \(session.displayName(of: creator, in: task.familyID))")
                    .font(FamiliarFont.meta)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
        }
    }

    private func peopleSection(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Zugewiesen")
            VStack(spacing: 0) {
                ForEach(task.assignees) { assignee in
                    let status: AssigneeCompletion? = task.completionMode == .each ? (assignee.isDone ? .done : .open) : nil
                    let name = session.displayName(of: assignee.userID, in: task.familyID)
                    HStack(spacing: FamiliarSpacing.s) {
                        ProfileAvatar(
                            profile: session.member(assignee.userID, in: task.familyID)?.profile,
                            name: name, diameter: 36, completion: status
                        )
                        Text(assignee.userID == session.userID ? "\(name) (du)" : name)
                            .font(FamiliarFont.body)
                            .foregroundStyle(FamiliarColor.textPrimary)
                        Spacer(minLength: 0)
                        if let status {
                            FamiliarTag(status == .done ? "Erledigt" : "Offen",
                                        systemImage: status == .done ? "checkmark" : nil,
                                        tone: status == .done ? .success : .neutral)
                        }
                    }
                    .padding(.vertical, FamiliarSpacing.xs)
                    .accessibilityElement(children: .combine)
                    if canNudge(assignee, in: task) {
                        nudgeButton(task: task, userID: assignee.userID, name: name)
                            .padding(.bottom, FamiliarSpacing.xs)
                    }
                    if assignee.id != task.assignees.last?.id {
                        Divider().overlay(FamiliarColor.hairline)
                    }
                }
            }
            .familiarCard(padding: FamiliarSpacing.s)
        }
    }

    // MARK: Reihum und Anstupsen (ADR 0010)

    /// „Reihum · nächstes Mal: Mia“ für Vorkommen einer Reihum-Serie. Ist der nächste Termin schon
    /// erzeugt (vielleicht getauscht), zählt dessen Person, sonst die Regel.
    private func rotationText(_ task: TaskItem) -> String? {
        guard let series = task.series, series.isRotating, let date = task.occurrenceDate,
              let start = series.rotationStart ?? series.startDate else { return nil }
        let generated = store.tasks
            .filter { $0.seriesID == series.id && ($0.occurrenceDate.map { $0 > date } ?? false) }
            .min { ($0.occurrenceDate ?? date) < ($1.occurrenceDate ?? date) }
        let person: UUID?
        if let generated, generated.assignees.count == 1 {
            person = generated.assignees.first?.userID
        } else {
            let members = Set(session.membership(task.familyID)?.members.map(\.userID) ?? [])
            let order = series.assigneeOrder.filter(members.contains)
            person = RotationRules.upcoming(rule: series.rule, unit: series.rotationUnit, start: start,
                                            order: order, from: date.adding(days: 1), count: 1).first?.person
        }
        guard let person else { return String(localized: "Reihum") }
        return String(localized: "Reihum · nächstes Mal: \(session.displayName(of: person, in: task.familyID))")
    }

    /// Erinnern geht bei offenen Aufgaben an Personen, die ihren Teil noch nicht erledigt haben – nie an sich selbst.
    private func canNudge(_ assignee: TaskAssignee, in task: TaskItem) -> Bool {
        task.isOpen && !assignee.isDone && assignee.userID != session.userID
            && session.member(assignee.userID, in: task.familyID) != nil
    }

    private func nudgeButton(task: TaskItem, userID: UUID, name: String) -> some View {
        let recently = store.wasNudgedRecently(task.id, userID)
        return Button {
            Task { await store.nudge(task, userID: userID, name: name) }
        } label: {
            Label(recently ? "Erinnert" : "Erinnern", systemImage: recently ? "bell.badge" : "bell")
                .font(FamiliarFont.secondary.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: FamiliarSize.minimumTouchTarget)
        }
        .buttonStyle(.familiarSecondary)
        .disabled(recently)
        .accessibilityLabel(recently ? "\(name) wurde erinnert" : "\(name) erinnern")
        .accessibilityHint("Schickt \(name) eine freundliche Mitteilung zu dieser Aufgabe.")
        .accessibilityIdentifier("task.nudge.\(name)")
    }

    private func imagesSection(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Bilder")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: FamiliarSpacing.xs)], spacing: FamiliarSpacing.xs) {
                ForEach(Array(task.images.enumerated()), id: \.element.id) { index, image in
                    Button {
                        gallery = GalleryState(images: task.images, index: index)
                    } label: {
                        TaskImageView(path: image.thumbPath)
                            .frame(minWidth: 96, minHeight: 96)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.chip, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bild \(index + 1) von \(task.images.count) ansehen")
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ task: TaskItem) -> some View {
        let actions = session.userID.map { TaskRules.actions(for: task, userID: $0) } ?? []
        let busy = store.busyTaskIDs.contains(task.id)
        VStack(spacing: FamiliarSpacing.s) {
            ForEach(actions, id: \.self) { action in
                Button {
                    Task {
                        await store.perform(action, on: task)
                        if store.task(task.id) == nil { dismiss() }
                    }
                } label: {
                    Label(title(for: action, task: task), systemImage: action == .undoMine ? "arrow.uturn.backward" : "checkmark")
                }
                .buttonStyle(action == actions.first ? .familiarPrimary : .familiarSecondary)
                .disabled(busy)
            }
            if task.deletedBySeriesOp != nil {
                Text("Mit der ganzen Serie gelöscht. Im Verlauf lässt sich die Serie wiederherstellen.")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !task.isOpen && (task.deletedAt == nil || session.allows(.deleteTasks, in: task.familyID)) {
                Button {
                    Task { _ = await store.restoreFromHistory(.task(task)); fetched = try? await store.fetch(task.id) }
                } label: {
                    Label(task.deletedAt != nil ? "Wiederherstellen" : "Wieder öffnen", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.familiarPrimary)
                .disabled(busy)
                .accessibilityIdentifier("task.restore")
            }
            if task.isOpen && session.allows(.deleteTasks, in: task.familyID) {
                Button("Aufgabe löschen", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.familiarDestructive)
                    .disabled(busy)
                    .padding(.top, FamiliarSpacing.m)
            }
            // Rechtswidrige Inhalte melden (Art. 16 DSA, App-Store-Richtlinie 1.2) – ruhig, ganz unten.
            if task.createdBy != session.userID || !task.images.isEmpty {
                Link(destination: LegalLink.report(taskID: task.id)) {
                    Label("Inhalt melden", systemImage: "exclamationmark.bubble")
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: FamiliarSize.minimumTouchTarget)
                }
                .padding(.top, FamiliarSpacing.s)
                .accessibilityHint("Öffnet das Meldeformular auf familiar-app.de mit der Kennung dieser Aufgabe.")
                .accessibilityIdentifier("task.report")
            }
        }
    }

    private func title(for action: TaskCompletionAction, task: TaskItem) -> String {
        switch action {
        case .completeForMe:
            session.userID.map { TaskRules.completesTask(task, userID: $0) } ?? true
                ? String(localized: "Erledigt")
                : String(localized: "Für mich erledigt")
        case .completeForAll:
            String(localized: "Für alle erledigt")
        case .undoMine:
            String(localized: "Meinen Haken zurücknehmen")
        }
    }
}
