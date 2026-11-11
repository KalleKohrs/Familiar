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

    static func modeSymbol(_ mode: CompletionMode) -> String {
        switch mode {
        case .anyOne: "person.fill.checkmark"
        case .each: "person.2.fill"
        }
    }

    /// Kurz für Kacheln im Editor.
    static func modeShortTitle(_ mode: CompletionMode) -> String {
        switch mode {
        case .anyOne: String(localized: "Eine für alle")
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

/// Texte zu Wiederholungen. Wochentage nach ISO (1 = Montag).
enum RecurrenceFormatting {
    static let weekdayOrder = [1, 2, 3, 4, 5, 6, 7]

    static func shortWeekday(_ isoWeekday: Int) -> String {
        switch isoWeekday {
        case 1: String(localized: "Mo")
        case 2: String(localized: "Di")
        case 3: String(localized: "Mi")
        case 4: String(localized: "Do")
        case 5: String(localized: "Fr")
        case 6: String(localized: "Sa")
        default: String(localized: "So")
        }
    }

    static func weekday(_ isoWeekday: Int) -> String {
        switch isoWeekday {
        case 1: String(localized: "Montag")
        case 2: String(localized: "Dienstag")
        case 3: String(localized: "Mittwoch")
        case 4: String(localized: "Donnerstag")
        case 5: String(localized: "Freitag")
        case 6: String(localized: "Samstag")
        default: String(localized: "Sonntag")
        }
    }

    /// Kurz für Etiketten: „Täglich“, „Mo, Mi, Fr“, „Am 1. und 15.“.
    static func summary(_ rule: RecurrenceRule) -> String {
        let rule = rule.normalized
        switch rule.frequency {
        case .daily:
            return String(localized: "Täglich")
        case .weekly:
            if rule.weekdays == weekdayOrder { return String(localized: "Täglich") }
            if rule.weekdays == [1, 2, 3, 4, 5] { return String(localized: "Werktags") }
            return rule.weekdays.map(shortWeekday).formatted(.list(type: .and, width: .narrow))
        case .monthly:
            let days = rule.monthDays.map { "\($0)." }.formatted(.list(type: .and))
            return String(localized: "Monatlich am \(days)")
        }
    }

    /// Ausführlich für VoiceOver und Details.
    static func spokenSummary(_ rule: RecurrenceRule) -> String {
        let rule = rule.normalized
        switch rule.frequency {
        case .daily:
            return String(localized: "Wiederholt sich täglich")
        case .weekly:
            let days = rule.weekdays.map(weekday).formatted(.list(type: .and))
            return String(localized: "Wiederholt sich jeden \(days)")
        case .monthly:
            let days = rule.monthDays.map { "\($0)." }.formatted(.list(type: .and))
            return String(localized: "Wiederholt sich monatlich am \(days)")
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
            if let rule = task.series?.rule {
                FamiliarTag(RecurrenceFormatting.summary(rule), systemImage: "repeat", tone: .neutral)
                    .accessibilityLabel(RecurrenceFormatting.spokenSummary(rule))
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
    /// Wächst mit der Schriftgröße mit (begrenzt), damit Initialen lesbar bleiben.
    @ScaledMetric(relativeTo: .footnote) private var scaledDiameter: CGFloat = 26
    var maxVisible = 5

    private var diameter: CGFloat { min(scaledDiameter, 40) }

    var body: some View {
        // Kleiner Abstand statt Überlappung, damit Häkchen-Abzeichen nie verdeckt werden.
        HStack(spacing: FamiliarSpacing.xs) {
            ForEach(task.assignees.prefix(maxVisible)) { assignee in
                ProfileAvatar(
                    profile: session.member(assignee.userID, in: task.familyID)?.profile,
                    name: session.displayName(of: assignee.userID, in: task.familyID),
                    diameter: diameter,
                    completion: status(of: assignee)
                )
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

/// Eine ruhige Infozeile unter dem Titel: Start (bzw. „Überfällig“), Wiederholung, Familie.
/// Text statt Etiketten-Chips, damit die Karte aufgeräumt bleibt (Design-Referenz).
struct TaskMetaLine: View {
    @Environment(SessionStore.self) private var session
    let task: TaskItem

    static func hasContent(_ task: TaskItem, familyCount: Int) -> Bool {
        task.startDate != nil || task.series != nil || familyCount > 1
    }

    var body: some View {
        let overdue = TaskRules.isOverdue(task)
        FlowRow(spacing: FamiliarSpacing.s) {
            if let start = TaskFormatting.startText(for: task) {
                Label(overdue ? String(localized: "Überfällig · \(start)") : start,
                      systemImage: overdue ? "exclamationmark.circle.fill" : (task.startTime == nil ? "calendar" : "clock"))
                    .foregroundStyle(overdue ? FamiliarColor.danger : FamiliarColor.accent)
            }
            if let rule = task.series?.rule {
                Label(RecurrenceFormatting.summary(rule), systemImage: "repeat")
                    .accessibilityLabel(RecurrenceFormatting.spokenSummary(rule))
            }
            if session.families.count > 1, let family = session.membership(task.familyID)?.family {
                HStack(spacing: FamiliarSpacing.xxs) {
                    Circle()
                        .fill(Color(session.familyDisplayColors[task.familyID] ?? family.color))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(family.name)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Familie \(family.name)")
            }
        }
        .font(FamiliarFont.meta.weight(.medium))
        .foregroundStyle(FamiliarColor.textSecondary)
        .labelStyle(CompactLabelStyle())
    }
}

/// Symbol und Text eng beieinander.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: FamiliarSpacing.xxs) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Eine Aufgabe in der Liste. Drei getrennte Tippflächen (Guide, Abschnitt 2):
/// Eintrag (öffnet die Details), Bild-Miniatur (öffnet die Bildansicht) und Abhaken.
/// Aufbau nach der Design-Referenz: Inhalt oben, Personen und runder Glas-Knopf unten.
struct TaskCard: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    let onOpen: () -> Void
    let onOpenImages: () -> Void
    /// Sofortige Rückmeldung beim Abhaken, bevor der Server antwortet.
    @State private var pendingDone: Bool?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Karte blendet an Ort und Stelle aus, bevor sie aus der Liste fällt – so rücken die
    /// anderen erst nach, wenn sie weg ist (keine Überlagerung).
    @State private var isLeaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let action = session.userID.flatMap { TaskRules.actions(for: task, userID: $0).first }
        let busy = store.busyTaskIDs.contains(task.id)

        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            HStack(alignment: .top, spacing: FamiliarSpacing.s) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xxs + 2) {
                        Text(task.title)
                            .font(FamiliarFont.cardTitle)
                            .foregroundStyle(FamiliarColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        if TaskMetaLine.hasContent(task, familyCount: session.families.count) {
                            TaskMetaLine(task: task)
                        }
                        if let description = task.description {
                            Text(description)
                                .font(FamiliarFont.secondary)
                                .foregroundStyle(FamiliarColor.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Öffnet die Details")
                .accessibilityIdentifier("task.open.\(task.title)")

                if let first = task.images.first {
                    Button(action: onOpenImages) {
                        TaskImageView(path: first.thumbPath)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.chip, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                if task.images.count > 1 {
                                    Text("\(task.images.count)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(FamiliarColor.onScrim)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(FamiliarColor.scrim))
                                        .padding(4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.images.count == 1 ? "Bild ansehen" : "\(task.images.count) Bilder ansehen")
                }
            }

            // Große Schriften: Fortschritt unter die Profilbilder, damit nichts umbricht.
            let footer = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: FamiliarSpacing.xs))
                : AnyLayout(HStackLayout(spacing: FamiliarSpacing.s))
            HStack(alignment: .center, spacing: FamiliarSpacing.s) {
                footer {
                    AssigneeAvatars(task: task)
                    if task.completionMode == .each && task.assignees.count > 1 {
                        let progress = TaskRules.progress(task)
                        Text("\(progress.done)/\(progress.total) erledigt")
                            .font(FamiliarFont.meta.monospacedDigit())
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .accessibilityLabel("\(progress.done) von \(progress.total) erledigt")
                    }
                }
                Spacer(minLength: 0)
                if let action {
                    CompletionCheckButton(isDone: pendingDone ?? (action == .undoMine)) {
                        check(action)
                    }
                    .disabled(busy)
                    .accessibilityLabel(checkLabel(for: action))
                    .padding(-2)
                }
            }
        }
        .familiarCard(padding: FamiliarSpacing.m)
        .opacity(isLeaving ? 0 : (busy && pendingDone == nil ? 0.6 : 1))
        .scaleEffect(isLeaving && !reduceMotion ? 0.97 : 1)
        // „In Arbeit“-Abdunklung blendet ein/aus, statt zu springen.
        .animation(FamiliarMotion.fade, value: busy)
        .sensoryFeedback(.success, trigger: pendingDone) { _, new in new == true }
        .onChange(of: task.version) { _, _ in pendingDone = nil }
    }

    /// Haken sofort zeigen (Feder-Animation), kurz stehen lassen, Karte ausblenden, dann speichern.
    private func check(_ action: TaskCompletionAction) {
        pendingDone = action != .undoMine
        Task {
            try? await Task.sleep(for: FamiliarMotion.checkHold)
            if willLeaveList(after: action) {
                withAnimation(FamiliarMotion.animation(FamiliarMotion.leave, reduceMotion: reduceMotion)) {
                    isLeaving = true
                }
                try? await Task.sleep(for: .seconds(FamiliarMotion.leaveDuration + 0.01))
            }
            await store.perform(action, on: task)
            // Bleibt die Karte (z. B. Fehler oder andere müssen noch abhaken), wieder einblenden.
            withAnimation(FamiliarMotion.animation(FamiliarMotion.fade, reduceMotion: reduceMotion)) {
                isLeaving = false
            }
            pendingDone = nil
        }
    }

    /// Verschwindet die Aufgabe nach dem Abhaken aus der offenen Liste?
    private func willLeaveList(after action: TaskCompletionAction) -> Bool {
        switch action {
        case .completeForAll: return true
        case .undoMine: return false
        case .completeForMe:
            guard task.completionMode == .each, let me = session.userID else { return true }
            return task.assignees.allSatisfy { $0.userID == me || $0.isDone }
        }
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
                let isDeletion = undo.kind == .restore || { if case .restoreSeries = undo.kind { true } else { false } }()
                banner(text: undo.message,
                       systemImage: isDeletion ? "trash.circle.fill" : "checkmark.circle.fill",
                       tint: isDeletion ? FamiliarColor.textSecondary : FamiliarColor.success) {
                    Button { Task { await store.performUndo() } } label: {
                        Text("Rückgängig")
                            .font(FamiliarFont.secondary.weight(.semibold))
                            .foregroundStyle(FamiliarColor.accent)
                            .padding(.horizontal, FamiliarSpacing.s)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(FamiliarColor.accent.opacity(0.16)))
                            .frame(minHeight: FamiliarSize.minimumTouchTarget)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("banner.undo")
                }
            } else if let info = store.info {
                banner(text: info, systemImage: "bell.circle.fill", tint: FamiliarColor.accent) {
                    Button { store.dismissBanner() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .accessibilityLabel("Hinweis schließen")
                }
                .accessibilityIdentifier("banner.info")
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
        .padding(.horizontal, FloatingTabBar.edgeInset)
        .padding(.bottom, tabBarHeight + FamiliarSpacing.s)
        // Ein Wert für alle drei Hinweisarten: Wechselt „Erledigt“ zu „Erinnert“, läuft nur eine Animation.
        .familiarAnimation(FamiliarMotion.snappy, value: bannerKey)
        .announcesChanges(of: store.undo?.message ?? store.actionError ?? store.info)
    }

    private var bannerKey: String {
        store.undo.map { $0.id.uuidString } ?? store.info ?? store.actionError ?? ""
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
        .padding(.trailing, FamiliarSpacing.s)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .capsule)
        .transition(FamiliarMotion.appearTransition(reduceMotion: reduceMotion))
    }
}
