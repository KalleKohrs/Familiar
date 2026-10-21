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
        .familiarScreenBackground()
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
            if task.isOpen {
                ToolbarItem(placement: .primaryAction) {
                    Button("Bearbeiten") { editing = task }
                        .accessibilityIdentifier("task.edit")
                }
            }
        }
        .confirmationDialog("Aufgabe löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task {
                    if await store.delete(task) { dismiss() }
                }
            }
        } message: {
            Text("Die Aufgabe landet im Verlauf und lässt sich dort 30 Tage lang wiederherstellen.")
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
            if !task.isOpen {
                FamiliarTag(task.deletedAt != nil ? "Gelöscht" : "Erledigt",
                            systemImage: task.deletedAt != nil ? "trash" : "checkmark",
                            tone: task.deletedAt != nil ? .danger : .success)
            }
            VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                Text(TaskFormatting.modeTitle(task.completionMode))
                    .font(FamiliarFont.sectionTitle)
                    .foregroundStyle(FamiliarColor.textPrimary)
                Text(TaskFormatting.modeExplanation(task.completionMode))
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
            .padding(.top, FamiliarSpacing.xs)
            .accessibilityElement(children: .combine)
            if let creator = task.createdBy {
                Text("Erstellt von \(session.displayName(of: creator, in: task.familyID))")
                    .font(FamiliarFont.meta)
                    .foregroundStyle(FamiliarColor.textTertiary)
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
                    if assignee.id != task.assignees.last?.id {
                        Divider().overlay(FamiliarColor.hairline)
                    }
                }
            }
            .familiarCard(padding: FamiliarSpacing.s)
        }
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
            if !task.isOpen {
                Button {
                    Task { _ = await store.restoreFromHistory(task) ; fetched = try? await store.fetch(task.id) }
                } label: {
                    Label(task.deletedAt != nil ? "Wiederherstellen" : "Wieder öffnen", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.familiarPrimary)
                .disabled(busy)
                .accessibilityIdentifier("task.restore")
            }
            if task.isOpen {
                Button("Aufgabe löschen", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.familiarDestructive)
                    .disabled(busy)
                    .padding(.top, FamiliarSpacing.m)
            }
        }
    }

    private func title(for action: TaskCompletionAction, task: TaskItem) -> String {
        switch action {
        case .completeForMe:
            task.completionMode == .each ? String(localized: "Für mich erledigt") : String(localized: "Erledigt")
        case .completeForAll:
            String(localized: "Für alle erledigt")
        case .undoMine:
            String(localized: "Meinen Haken zurücknehmen")
        }
    }
}
