import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Bereich „Verlauf“: erledigte und gelöschte Aufgaben sowie gelöschte Serien der letzten 30 Tage
/// (Guide, Abschnitte 4 und 5).
/// Jedes Mitglied mit Sicht auf eine Aufgabe darf sie wiederherstellen (Guide, Abschnitt 3).
struct HistoryHomeView: View {
    @Environment(TaskStore.self) private var store
    @Namespace private var transition
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    content
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .refreshable { await store.reloadHistory() }
            .familiarScreenBackground()
            .navigationTitle("Verlauf")
            .navigationDestination(for: UUID.self) { taskID in
                TaskDetailView(taskID: taskID)
                    .navigationTransition(.zoom(sourceID: taskID, in: transition))
            }
            .overlay(alignment: .bottom) { TaskBanner() }
            .task { await store.reloadHistory() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.history.isEmpty && (store.historyState == .idle || store.historyState == .loading) {
            ForEach(0..<3, id: \.self) { _ in FamiliarSkeleton(height: 88) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Verlauf wird geladen")
        } else if store.history.isEmpty, case .failed(let error) = store.historyState {
            FamiliarErrorState(message: error.message) {
                Task { await store.reloadHistory() }
            }
            .familiarCard()
        } else {
            if store.history.isEmpty {
                FamiliarEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "Noch kein Verlauf",
                    message: "Erledigte und gelöschte Aufgaben bleiben hier 30 Tage und lassen sich wiederherstellen."
                )
                .familiarCard()
            } else {
                ForEach(sections, id: \.day) { section in
                    FamiliarSectionHeader(section.title)
                        .padding(.top, FamiliarSpacing.s)
                    ForEach(section.entries) { entry in
                        switch entry {
                        case .task(let task):
                            HistoryRow(task: task) { path.append(task.id) }
                                .matchedTransitionSource(id: task.id, in: transition)
                        case .seriesDeletion(let deletion):
                            SeriesDeletionRow(deletion: deletion, entry: entry)
                        }
                    }
                }
            }
        }
    }

    /// Einträge nach Tag gruppiert (Heute, Gestern, Datum), neueste zuerst.
    private var sections: [(day: Date, title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.history) { entry in
            calendar.startOfDay(for: entry.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = String(localized: "Heute")
            } else if calendar.isDateInYesterday(day) {
                title = String(localized: "Gestern")
            } else {
                title = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            }
            return (day, title, grouped[day] ?? [])
        }
    }
}

/// Eine Zeile im Verlauf: Titel, Familie, wer was wann getan hat, Restlaufzeit, Wiederherstellen.
private struct HistoryRow: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    let onOpen: () -> Void

    var body: some View {
        let kind = HistoryRules.kind(of: task)
        HStack(alignment: .center, spacing: FamiliarSpacing.s) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: FamiliarSpacing.s) {
                    Image(systemName: kind == .deleted ? "trash.circle.fill" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(kind == .deleted ? FamiliarColor.danger : FamiliarColor.success)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                        Text(task.title)
                            .font(FamiliarFont.cardTitle)
                            .foregroundStyle(FamiliarColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(statusText(kind))
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                        if let days = HistoryRules.daysRemaining(for: task) {
                            Text(days == 1 ? "Noch 1 Tag im Verlauf" : "Noch \(days) Tage im Verlauf")
                                .font(FamiliarFont.meta)
                                .foregroundStyle(FamiliarColor.textTertiary)
                        }
                        if session.families.count > 1, let family = session.membership(task.familyID)?.family {
                            FamilyBadge(name: family.name,
                                        color: Color(session.familyDisplayColors[task.familyID] ?? family.color))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Öffnet die Details")

            RestoreButton(entry: .task(task), label: "\(task.title) wiederherstellen")
                .accessibilityIdentifier("history.restore.\(task.title)")
        }
        .familiarCard(padding: FamiliarSpacing.m)
        .opacity(store.busyTaskIDs.contains(task.id) ? 0.6 : 1)
    }

    private func statusText(_ kind: HistoryRules.Kind?) -> String {
        let time = HistoryRules.date(of: task)?.formatted(date: .omitted, time: .shortened) ?? ""
        let actorName = HistoryRules.actor(of: task).map { session.displayName(of: $0, in: task.familyID) }
        switch kind {
        case .deleted:
            return actorName.map { String(localized: "Gelöscht von \($0) · \(time)") } ?? String(localized: "Gelöscht · \(time)")
        case .completed:
            let byCreator = task.completionSource == .creator
            if let actorName {
                return byCreator
                    ? String(localized: "Für alle erledigt von \(actorName) · \(time)")
                    : String(localized: "Erledigt von \(actorName) · \(time)")
            }
            return String(localized: "Erledigt · \(time)")
        case nil:
            return ""
        }
    }
}

/// Runder Knopf „Wiederherstellen“ für einen Verlaufseintrag.
private struct RestoreButton: View {
    @Environment(TaskStore.self) private var store
    let entry: HistoryEntry
    let label: String

    var body: some View {
        Button {
            Task { _ = await store.restoreFromHistory(entry) }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.body.weight(.semibold))
                .foregroundStyle(FamiliarColor.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(FamiliarColor.accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(store.busyTaskIDs.contains(entry.id))
        .accessibilityLabel(label)
    }
}

/// Eine gelöschte Serie: ein Eintrag statt vieler einzelner Vorkommen (Guide, Abschnitt 4).
private struct SeriesDeletionRow: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    let deletion: SeriesDeletion
    let entry: HistoryEntry

    private var title: String {
        deletion.series?.title ?? String(localized: "Wiederkehrende Aufgabe")
    }

    var body: some View {
        HStack(alignment: .center, spacing: FamiliarSpacing.s) {
            HStack(alignment: .top, spacing: FamiliarSpacing.s) {
                Image(systemName: "repeat.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FamiliarColor.danger)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                    Text(title)
                        .font(FamiliarFont.cardTitle)
                        .foregroundStyle(FamiliarColor.textPrimary)
                    Text(statusText)
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                    if let rule = deletion.series?.rule {
                        Text(RecurrenceFormatting.summary(rule))
                            .font(FamiliarFont.meta)
                            .foregroundStyle(FamiliarColor.textSecondary)
                    }
                    let days = HistoryRules.daysRemaining(for: entry)
                    Text(days == 1 ? "Noch 1 Tag im Verlauf" : "Noch \(days) Tage im Verlauf")
                        .font(FamiliarFont.meta)
                        .foregroundStyle(FamiliarColor.textTertiary)
                    if session.families.count > 1, let family = session.membership(deletion.familyID)?.family {
                        FamilyBadge(name: family.name,
                                    color: Color(session.familyDisplayColors[deletion.familyID] ?? family.color))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            RestoreButton(entry: entry, label: String(localized: "Serie \(title) wiederherstellen"))
                .accessibilityIdentifier("history.restoreSeries.\(title)")
        }
        .familiarCard(padding: FamiliarSpacing.m)
        .opacity(store.busyTaskIDs.contains(deletion.id) ? 0.6 : 1)
    }

    private var statusText: String {
        let time = deletion.deletedAt.formatted(date: .omitted, time: .shortened)
        if let actor = deletion.deletedBy {
            let name = session.displayName(of: actor, in: deletion.familyID)
            return String(localized: "Serie gelöscht von \(name) · \(time)")
        }
        return String(localized: "Serie gelöscht · \(time)")
    }
}
