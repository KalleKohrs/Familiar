import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Öffnet „Neue Aufgabe“; aufrufbar wie eine Funktion (wie SwiftUIs `DismissAction`).
struct OpenNewTaskAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

extension EnvironmentValues {
    /// Gesetzt von RootTabView, genutzt z. B. vom Leerzustand der Startseite.
    @Entry var openNewTask = OpenNewTaskAction {}
    /// Höhe der schwebenden Leiste, damit Hinweise darüber erscheinen.
    @Entry var floatingTabBarHeight: CGFloat = 0
}

/// Texte zum Startzeitpunkt. Nur-Datum-Aufgaben zeigen das Kalenderdatum der Aufgabe,
/// Aufgaben mit Uhrzeit den Zeitpunkt in der Zeitzone des Geräts.
enum TaskFormatting {
    static func startText(for task: TaskItem, now: Date = .now) -> String? {
        guard let startDate = task.startDate else { return nil }
        let calendar = Calendar.current
        if task.startTime != nil, let startsAt = task.startsAt {
            let time = startsAt.formatted(date: .omitted, time: .shortened)
            return "\(dayText(for: calendar.startOfDay(for: startsAt), now: now)) · \(time)"
        }
        let day = startDate.date(at: nil, in: .current)
        return dayText(for: day, now: now)
    }

    private static func dayText(for day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Heute") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return String(localized: "Morgen")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Gestern")
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return sameYear
            ? day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : day.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func modeTitle(_ mode: CompletionMode) -> String {
        switch mode {
        case .anyOne: String(localized: "Eine Person für alle")
        case .each: String(localized: "Jede Person einzeln")
        }
    }

    static func modeExplanation(_ mode: CompletionMode) -> String {
        switch mode {
        case .anyOne: String(localized: "Sobald eine zugewiesene Person abhakt, ist die Aufgabe für alle erledigt.")
        case .each: String(localized: "Jede zugewiesene Person hakt selbst ab. Erledigt ist die Aufgabe, wenn alle fertig sind.")
        }
    }
}

/// Start, Überfällig und Fortschritt als kleine Etiketten.
struct TaskMetaTags: View {
    let task: TaskItem

    var body: some View {
        let overdue = TaskRules.isOverdue(task)
        FlowRow {
            if let start = TaskFormatting.startText(for: task) {
                FamiliarTag(
                    overdue ? String(localized: "Überfällig · \(start)") : start,
                    systemImage: overdue ? "exclamationmark.circle" : (task.startTime == nil ? "calendar" : "clock"),
                    tone: overdue ? .danger : .accent
                )
            }
            if task.completionMode == .each && task.assignees.count > 1 {
                let progress = TaskRules.progress(task)
                FamiliarTag("\(progress.done) von \(progress.total) erledigt", systemImage: "person.2", tone: .neutral)
            }
        }
    }
}

/// Profilbilder bzw. Initialen der zugewiesenen Personen mit Status pro Person.
/// Bei „Eine für alle“ gibt es keinen Einzelstatus, solange die Aufgabe offen ist.
struct AssigneeAvatars: View {
    @Environment(SessionStore.self) private var session
    let task: TaskItem
    var diameter: CGFloat = 26
    var maxVisible = 5

    var body: some View {
        HStack(spacing: -diameter * 0.28) {
            ForEach(task.assignees.prefix(maxVisible)) { assignee in
                ProfileAvatar(
                    profile: session.member(assignee.userID, in: task.familyID)?.profile,
                    name: session.displayName(of: assignee.userID, in: task.familyID),
                    diameter: diameter,
                    completion: status(of: assignee)
                )
                .padding(1.5)
                .background(Circle().fill(FamiliarColor.card))
            }
            if task.assignees.count > maxVisible {
                Text("+\(task.assignees.count - maxVisible)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(FamiliarColor.elevated))
                    .padding(1.5)
                    .background(Circle().fill(FamiliarColor.card))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func status(of assignee: TaskAssignee) -> AssigneeCompletion? {
        task.completionMode == .each ? (assignee.isDone ? .done : .open) : nil
    }

    private var accessibilityText: String {
        let parts = task.assignees.map { assignee in
            let name = session.displayName(of: assignee.userID, in: task.familyID)
            switch status(of: assignee) {
            case .done: return String(localized: "\(name) erledigt")
            case .open: return String(localized: "\(name) offen")
            case nil: return name
            }
        }
        return String(localized: "Zugewiesen: \(parts.formatted(.list(type: .and)))")
    }
}

/// Eine Aufgabe in der Liste. Drei getrennte Tippflächen (Guide, Abschnitt 2):
/// Abhaken, Eintrag (öffnet die Details) und Bild-Miniatur (öffnet die Bildansicht).
struct TaskCard: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    let onOpen: () -> Void
    let onOpenImages: () -> Void

    var body: some View {
        let action = session.userID.flatMap { TaskRules.actions(for: task, userID: $0).first }
        let familyColor = Color(session.familyDisplayColors[task.familyID] ?? task.color(in: session))

        HStack(alignment: .top, spacing: FamiliarSpacing.xs) {
            if let action {
                CompletionCheckButton(isDone: action == .undoMine, tint: FamiliarColor.accent) {
                    Task { await store.perform(action, on: task) }
                }
                .disabled(store.busyTaskIDs.contains(task.id))
                .accessibilityLabel(checkLabel(for: action))
                .padding(.top, -FamiliarSpacing.xs)
                .padding(.leading, -FamiliarSpacing.xs)
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                    Text(task.title)
                        .font(FamiliarFont.cardTitle)
                        .foregroundStyle(FamiliarColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let description = task.description {
                        Text(description)
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    TaskMetaTags(task: task)
                    HStack(spacing: FamiliarSpacing.s) {
                        AssigneeAvatars(task: task)
                        if session.families.count > 1, let family = session.membership(task.familyID)?.family {
                            FamilyBadge(name: family.name, color: familyColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Öffnet die Details")

            if let first = task.images.first {
                Button(action: onOpenImages) {
                    TaskImageView(path: first.thumbPath)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.chip, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if task.images.count > 1 {
                                Text("\(task.images.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(FamiliarColor.textPrimary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.black.opacity(0.6)))
                                    .padding(4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.images.count == 1 ? "Bild ansehen" : "\(task.images.count) Bilder ansehen")
            }
        }
        .familiarCard(padding: FamiliarSpacing.m)
        .overlay(alignment: .leading) {
            // Familienfarbe als feine Kante; die Zuordnung steht zusätzlich als Name im Badge.
            Capsule()
                .fill(familyColor)
                .frame(width: 3)
                .padding(.vertical, FamiliarSpacing.m)
                .accessibilityHidden(true)
        }
        .opacity(store.busyTaskIDs.contains(task.id) ? 0.6 : 1)
    }

    private func checkLabel(for action: TaskCompletionAction) -> String {
        switch action {
        case .completeForMe: String(localized: "\(task.title) abhaken")
        case .completeForAll: String(localized: "\(task.title) für alle erledigen")
        case .undoMine: String(localized: "Haken bei \(task.title) zurücknehmen")
        }
    }
}

extension TaskItem {
    /// Originalfarbe der Familie (Fallback, falls die Familie noch nicht geladen ist).
    func color(in session: SessionStore) -> RGBColor {
        session.membership(familyID)?.family.color ?? RGBColor(hex: 0xFF8C42)
    }
}

/// Schwebender Hinweis über der Leiste: „Erledigt · Rückgängig“ oder eine Fehlermeldung.
struct TaskBanner: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let undo = store.undo {
                banner(text: undo.message, systemImage: "checkmark.circle.fill", tint: FamiliarColor.success) {
                    Button("Rückgängig") { Task { await store.performUndo() } }
                        .font(FamiliarFont.body.weight(.semibold))
                        .foregroundStyle(FamiliarColor.accent)
                        .frame(minHeight: FamiliarSize.minimumTouchTarget)
                        .accessibilityIdentifier("banner.undo")
                }
            } else if let error = store.actionError {
                banner(text: error, systemImage: "exclamationmark.circle.fill", tint: FamiliarColor.danger) {
                    Button { store.dismissBanner() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .accessibilityLabel("Hinweis schließen")
                }
            }
        }
        .padding(.horizontal, FamiliarSpacing.m)
        .padding(.bottom, tabBarHeight + FamiliarSpacing.s)
        .familiarAnimation(value: store.undo?.id)
        .familiarAnimation(value: store.actionError)
        .announcesChanges(of: store.undo?.message ?? store.actionError)
    }

    private func banner(text: String, systemImage: String, tint: Color, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: FamiliarSpacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(FamiliarFont.body)
                .foregroundStyle(FamiliarColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
        .padding(.leading, FamiliarSpacing.m)
        .padding(.trailing, FamiliarSpacing.xs)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .capsule)
        .transition(FamiliarMotion.appearTransition(reduceMotion: reduceMotion))
    }
}
