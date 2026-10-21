import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Bereich „Kalender“ (Plan, Abschnitt 7): Monatsraster mit Aufgaben und geplanten Serienterminen,
/// darunter die Einträge des gewählten Tages. Persönliche Outlook-Termine folgen in Phase 8
/// über ``ExternalEventRepository`` und werden dann getrennt gekennzeichnet.
struct CalendarHomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var transition

    @State private var path: [UUID] = []
    @State private var month = CalendarRules.month(LocalDate(.now, timeZone: .current), offset: 0)
    @State private var selected = LocalDate(.now, timeZone: .current)
    @State private var entries: [LocalDate: [CalendarEntry]] = [:]
    @State private var loadError: String?
    @State private var isLoading = false
    /// Richtung des letzten Monatswechsels, für die Überblendung.
    @State private var direction = 1

    private var today: LocalDate { LocalDate(.now, timeZone: .current) }
    private var grid: [LocalDate] { CalendarRules.monthGrid(year: month.year, month: month.month) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: FamiliarSpacing.m) {
                    Text("Kalender")
                        .font(FamiliarFont.display)
                        .foregroundStyle(FamiliarColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    monthCard
                    dayList
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .refreshable { await load() }
            .familiarScreenBackground()
            .navigationTitle("Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .navigationDestination(for: UUID.self) { taskID in
                TaskDetailView(taskID: taskID)
                    .navigationTransition(.zoom(sourceID: taskID, in: transition))
            }
            .overlay(alignment: .bottom) { TaskBanner() }
            .task(id: ReloadKey(month: month, token: store.changeToken)) { await load() }
        }
    }

    private struct ReloadKey: Hashable {
        let month: LocalDate
        let token: Int
    }

    // MARK: Laden

    private func load() async {
        guard let first = grid.first, let last = grid.last else { return }
        isLoading = entries.isEmpty
        defer { isLoading = false }
        do throws(FamiliarError) {
            let data = try await store.calendarData(from: first, through: last)
            entries = CalendarRules.entriesByDay(tasks: data.tasks, projected: data.projected)
            loadError = nil
        } catch {
            loadError = error.message
        }
    }

    private func changeMonth(by offset: Int) {
        direction = offset
        withAnimation(reduceMotion ? FamiliarMotion.reduced : FamiliarMotion.standard) {
            month = CalendarRules.month(month, offset: offset)
            // Auswahl bleibt sinnvoll: heute im aktuellen Monat, sonst der Erste.
            selected = (month.year == today.year && month.month == today.month) ? today : month
        }
    }

    private func goToToday() {
        direction = today < month ? -1 : 1
        withAnimation(reduceMotion ? FamiliarMotion.reduced : FamiliarMotion.standard) {
            month = CalendarRules.month(today, offset: 0)
            selected = today
        }
    }

    // MARK: Monatskarte

    private var monthCard: some View {
        VStack(spacing: FamiliarSpacing.s) {
            HStack(spacing: FamiliarSpacing.xs) {
                Text(monthTitle)
                    .font(FamiliarFont.sectionTitle)
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .contentTransition(.numericText(countsDown: direction < 0))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !(month.year == today.year && month.month == today.month) || selected != today {
                    Button("Heute", action: goToToday)
                        .font(FamiliarFont.secondary.weight(.semibold))
                        .foregroundStyle(FamiliarColor.accent)
                        .padding(.horizontal, FamiliarSpacing.s)
                        .frame(minHeight: FamiliarSize.minimumTouchTarget)
                        .accessibilityIdentifier("calendar.today")
                }
                roundButton("chevron.left", label: "Vorheriger Monat") { changeMonth(by: -1) }
                    .accessibilityIdentifier("calendar.previous")
                roundButton("chevron.right", label: "Nächster Monat") { changeMonth(by: 1) }
                    .accessibilityIdentifier("calendar.next")
            }

            HStack(spacing: 0) {
                ForEach(RecurrenceFormatting.weekdayOrder, id: \.self) { weekday in
                    Text(RecurrenceFormatting.shortWeekday(weekday))
                        .font(FamiliarFont.caption)
                        .foregroundStyle(FamiliarColor.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: FamiliarSpacing.xxs) {
                ForEach(grid, id: \.self) { day in
                    dayCell(day)
                }
            }
            .id(month)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)))
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height),
                              abs(value.translation.width) > 50 else { return }
                        changeMonth(by: value.translation.width < 0 ? 1 : -1)
                    }
            )
        }
        .familiarCard(padding: FamiliarSpacing.m)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var monthTitle: String {
        month.date(at: nil, in: .current).formatted(.dateTime.month(.wide).year())
    }

    private func roundButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FamiliarColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(FamiliarColor.cardGlassPressed))
                .overlay(Circle().strokeBorder(FamiliarColor.lightEdge, lineWidth: 1))
                .frame(width: FamiliarSize.minimumTouchTarget, height: FamiliarSize.minimumTouchTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayCell(_ day: LocalDate) -> some View {
        let inMonth = day.month == month.month
        let isToday = day == today
        let isSelected = day == selected
        let dayEntries = entries[day] ?? []

        return Button {
            selected = day
            if !inMonth { changeMonth(by: day < month ? -1 : 1); selected = day }
        } label: {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(.callout.weight(isToday || isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? FamiliarColor.onAccent
                                     : inMonth ? FamiliarColor.textPrimary : FamiliarColor.textTertiary)
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(FamiliarColor.accent)
                        } else if isSelected {
                            Circle().fill(FamiliarColor.cardGlassPressed)
                                .overlay(Circle().strokeBorder(FamiliarColor.accent.opacity(0.7), lineWidth: 1.5))
                        }
                    }
                dots(for: dayEntries)
                    .opacity(inMonth ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cellLabel(day, entries: dayEntries, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("calendar.day.\(day.description)")
    }

    /// Bis zu drei Punkte in Familienfarbe: voll für Aufgaben, blass für geplante Serientermine.
    private func dots(for dayEntries: [CalendarEntry]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(dayEntries.prefix(3))) { entry in
                switch entry {
                case .task(let task):
                    Circle().fill(familyColor(task.familyID).opacity(task.isOpen ? 1 : 0.35))
                        .frame(width: 5, height: 5)
                case .projected(let occurrence):
                    Circle().fill(familyColor(occurrence.familyID).opacity(0.35))
                        .frame(width: 5, height: 5)
                case .external:
                    Circle().strokeBorder(FamiliarColor.textSecondary, lineWidth: 1)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(height: 6)
    }

    private func familyColor(_ familyID: UUID) -> Color {
        Color(session.familyDisplayColors[familyID] ?? session.membership(familyID)?.family.color ?? RGBColor(hex: 0xFF8C42))
    }

    private func cellLabel(_ day: LocalDate, entries: [CalendarEntry], isToday: Bool) -> String {
        let date = day.date(at: nil, in: .current).formatted(.dateTime.day().month(.wide))
        let tasks = entries.filter { if case .task = $0 { true } else { false } }.count
        let planned = entries.filter { if case .projected = $0 { true } else { false } }.count
        var parts = [isToday ? String(localized: "Heute, \(date)") : date]
        if tasks > 0 { parts.append(tasks == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(tasks) Aufgaben")) }
        if planned > 0 { parts.append(String(localized: "\(planned) geplant")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Tagesliste

    @ViewBuilder
    private var dayList: some View {
        let dayEntries = entries[selected] ?? []
        Text(dayTitle)
            .font(FamiliarFont.meta.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(FamiliarColor.textSecondary)
            .padding(.top, FamiliarSpacing.xs)
            .padding(.leading, FamiliarSpacing.xxs)
            .accessibilityAddTraits(.isHeader)

        if let loadError, entries.isEmpty {
            FamiliarErrorState(message: loadError) { Task { await load() } }
                .familiarCard()
        } else if isLoading {
            FamiliarSkeleton(height: 64)
        } else if dayEntries.isEmpty {
            Text("Nichts geplant.")
                .font(FamiliarFont.secondary)
                .foregroundStyle(FamiliarColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .familiarCard(padding: FamiliarSpacing.m)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(dayEntries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().overlay(FamiliarColor.hairline).padding(.leading, 64)
                    }
                    CalendarEntryRow(entry: entry) { taskID in path.append(taskID) }
                }
            }
            .familiarCard(padding: FamiliarSpacing.xs)
        }
    }

    private var dayTitle: String {
        let date = selected.date(at: nil, in: .current).formatted(.dateTime.weekday(.wide).day().month(.wide))
        return selected == today ? String(localized: "Heute · \(date)") : date
    }
}

/// Eine Zeile der Tagesliste: Uhrzeit links, Titel mit Familie, Status rechts.
private struct CalendarEntryRow: View {
    @Environment(SessionStore.self) private var session
    let entry: CalendarEntry
    let onOpen: (UUID) -> Void

    var body: some View {
        switch entry {
        case .task(let task):
            Button { onOpen(task.id) } label: {
                row(time: timeText(task.startTime), title: task.title, familyID: task.familyID,
                    subtitle: subtitle(for: task), done: !task.isOpen, planned: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet die Details")
            .accessibilityIdentifier("calendar.task.\(task.title)")
        case .projected(let occurrence):
            row(time: timeText(occurrence.startTime), title: occurrence.title, familyID: occurrence.familyID,
                subtitle: occurrence.rule.map(RecurrenceFormatting.summary) ?? String(localized: "Serie"),
                done: false, planned: true)
                .accessibilityHint("Geplanter Termin einer Serie; erscheint als Aufgabe, sobald er an der Reihe ist.")
        case .external(let event):
            row(time: event.isAllDay ? String(localized: "Ganztägig") : event.startsAt.formatted(date: .omitted, time: .shortened),
                title: event.title, familyID: nil, subtitle: event.provider, done: false, planned: false)
        }
    }

    private func row(time: String, title: String, familyID: UUID?, subtitle: String?, done: Bool, planned: Bool) -> some View {
        HStack(alignment: .center, spacing: FamiliarSpacing.s) {
            Text(time)
                .font(FamiliarFont.time)
                .foregroundStyle(FamiliarColor.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FamiliarFont.body.weight(.medium))
                    .foregroundStyle(done ? FamiliarColor.textTertiary : FamiliarColor.textPrimary)
                    .strikethrough(done, color: FamiliarColor.textTertiary)
                HStack(spacing: FamiliarSpacing.xxs) {
                    if let familyID, session.families.count > 1, let family = session.membership(familyID)?.family {
                        Circle()
                            .fill(Color(session.familyDisplayColors[familyID] ?? family.color))
                            .frame(width: 7, height: 7)
                        Text(family.name)
                    }
                    if let subtitle {
                        if planned { Image(systemName: "repeat").imageScale(.small) }
                        Text(subtitle)
                    }
                }
                .font(FamiliarFont.meta)
                .foregroundStyle(FamiliarColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(FamiliarColor.success)
                    .accessibilityLabel("Erledigt")
            } else if planned {
                Text("Geplant")
                    .font(FamiliarFont.caption)
                    .foregroundStyle(FamiliarColor.textTertiary)
            }
        }
        .padding(.horizontal, FamiliarSpacing.s)
        .padding(.vertical, FamiliarSpacing.s)
        .frame(minHeight: FamiliarSize.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func timeText(_ time: LocalTime?) -> String {
        guard let time else { return String(localized: "Ganzer Tag") }
        return String(format: "%02d:%02d", time.hour, time.minute)
    }

    private func subtitle(for task: TaskItem) -> String? {
        if let rule = task.series?.rule { return RecurrenceFormatting.summary(rule) }
        return nil
    }
}

#Preview {
    CalendarHomeView()
        .previewEnvironment(.ready)
}
