import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Bereich „Kalender“ (Plan, Abschnitt 7): Monatsraster mit Aufgaben und geplanten Serienterminen,
/// darunter die Einträge des gewählten Tages. Persönliche Outlook-Termine (Phase 8) erscheinen
/// getrennt gekennzeichnet: Ring statt Punkt und mit Anbieter-Namen.
struct CalendarHomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    @Environment(OutlookStore.self) private var outlook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var transition

    @State private var path: [UUID] = []
    @State private var month = CalendarRules.month(LocalDate(.now, timeZone: .current), offset: 0)
    @State private var selected = LocalDate(.now, timeZone: .current)
    @State private var entries: [LocalDate: [CalendarEntry]] = [:]
    @State private var loadError: String?
    /// Erst nach dem ersten Laden zeigt die Tagesliste „Nichts geplant“ – davor Platzhalter statt falscher Leere.
    @State private var hasLoaded = false
    /// Für welchen Monat `entries` zuletzt geladen wurde. Nach einem Monatswechsel ist die Tagesliste bis dahin
    /// unbestimmt (weder Platzhalter noch „Nichts geplant“ – beides blitzte kurz als Kasten bzw. falsche Aussage auf).
    @State private var loadedMonth: LocalDate?
    /// Von welcher Seite der neue Monat hereinkommt (`.trailing` = „nächster“, `.leading` = „vorheriger“).
    @State private var slide: Edge = .trailing

    private var today: LocalDate { LocalDate(.now, timeZone: .current) }
    private var grid: [LocalDate] { CalendarRules.monthGrid(year: month.year, month: month.month) }

    /// Zeilenhöhe der Tageszellen (`minHeight` in `dayCell`) und Abstand der Zeilen.
    private static let rowHeight: CGFloat = 48
    private var gridHeight: CGFloat {
        let rows = CGFloat(max(1, grid.count / 7))
        return rows * Self.rowHeight + (rows - 1) * FamiliarSpacing.xxs
    }

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
            .task(id: ReloadKey(month: month, token: store.changeToken, outlook: outlook.revision)) { await load() }
        }
        .popsToRootOnTabChange(.calendar, path: $path)
    }

    private struct ReloadKey: Hashable {
        let month: LocalDate
        let token: Int
        let outlook: Int
    }

    // MARK: Laden

    private func load() async {
        guard let first = grid.first, let last = grid.last else { return }
        let requested = month
        defer { hasLoaded = true }
        do throws(FamiliarError) {
            let data = try await store.calendarData(from: first, through: last)
            // Persönliche Outlook-Termine (nur für den Nutzer selbst).
            let external = await outlook.events(from: first.startOfDay(in: .current),
                                                to: last.adding(days: 1).startOfDay(in: .current))
            // Kam inzwischen ein anderer Monat dazwischen, gehört dieses Ergebnis nicht mehr hierher.
            guard !Task.isCancelled, requested == month else { return }
            entries = CalendarRules.entriesByDay(tasks: data.tasks, projected: data.projected, external: external)
            loadedMonth = requested
            loadError = nil
        } catch {
            loadError = error.message
        }
    }

    /// Monat wechseln: Das Raster schiebt sich seitlich herein (Richtung wie beim Blättern). SwiftUI liest die
    /// Abgangs-Bewegung des alten Monats vom zuletzt gezeigten Zustand – deshalb wird die Richtung zuerst
    /// gesetzt und der Monat erst einen Augenblick später gewechselt (sonst schöbe sich der alte Monat in die
    /// falsche Richtung hinaus).
    private func changeMonth(by offset: Int, selecting day: LocalDate? = nil) {
        slide = offset > 0 ? .trailing : .leading
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(24))
            let newMonth = CalendarRules.month(month, offset: offset)
            // Auswahl bleibt sinnvoll: heute im aktuellen Monat, sonst der Erste. Ohne Animation, sonst
            // blendet der alte Tagestitel als Geist unter der Karte aus.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                selected = day ?? ((newMonth.year == today.year && newMonth.month == today.month) ? today : newMonth)
            }
            withAnimation(reduceMotion ? FamiliarMotion.reduced : Self.slideAnimation) {
                month = newMonth
            }
        }
    }

    private func goToToday() {
        let target = CalendarRules.month(today, offset: 0)
        slide = target < month ? .leading : .trailing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(24))
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { selected = today }
            withAnimation(reduceMotion ? FamiliarMotion.reduced : Self.slideAnimation) {
                month = target
            }
        }
    }

    /// Ruhiges Schieben ohne Nachfedern (ein Überschwingen ließe das Raster über die Kartenkante ragen).
    private static let slideAnimation: Animation = .smooth(duration: 0.38)

    // MARK: Monatskarte

    private var monthCard: some View {
        VStack(spacing: FamiliarSpacing.s) {
            HStack(spacing: FamiliarSpacing.xs) {
                Text(monthTitle)
                    .font(FamiliarFont.sectionTitle)
                    .foregroundStyle(FamiliarColor.textPrimary)
                    // Reine Überblendung: „numericText“ verwischt Buchstaben („Ja…uar“).
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !(month.year == today.year && month.month == today.month) || selected != today {
                    Button(action: goToToday) {
                        Label("Heute", systemImage: "arrow.uturn.backward")
                            .font(FamiliarFont.caption.weight(.semibold))
                            .foregroundStyle(FamiliarColor.accent)
                            .padding(.horizontal, FamiliarSpacing.s)
                            .padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(FamiliarColor.accent.opacity(0.6), lineWidth: 1))
                            .frame(minHeight: FamiliarSize.minimumTouchTarget)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zurück zu heute")
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
                        .foregroundStyle(FamiliarColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            // Dichtes Raster wächst nur begrenzt mit (wie Apples Kalender); alle Inhalte stehen in
            // voller Größe in der Tagesliste, lange Drücken zeigt den Tag vergrößert.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)

            ZStack(alignment: .top) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: FamiliarSpacing.xxs) {
                    ForEach(grid, id: \.self) { day in
                        dayCell(day)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .id(month)
                // Der alte Monat schiebt sich hinaus, der neue herein – beide blenden dabei aus bzw. ein. Das
                // Raster liegt in einem festen, abgeschnittenen Bereich: nichts ragt über die Karte hinaus.
                .transition(.asymmetric(
                    insertion: .move(edge: slide).combined(with: .opacity),
                    removal: .move(edge: slide == .trailing ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            // Höhe folgt der Zeilenzahl (5 oder 6 Wochen) und wird mit dem Monatswechsel mitanimiert.
            // Ohne feste Höhe bliebe die Karte während der Überblendung so hoch wie der größere Monat
            // und schrumpfte danach ruckartig.
            .frame(height: gridHeight, alignment: .top)
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        // Entscheidend ist, wohin die Geste auslaufen würde (Geschwindigkeit zählt mit),
                        // nicht nur, wie weit der Finger gekommen ist: Ein schnelles Wischen reicht.
                        let projected = value.predictedEndTranslation.width
                        guard abs(value.translation.width) > abs(value.translation.height),
                              abs(projected) > 100 else { return }
                        changeMonth(by: projected < 0 ? 1 : -1)
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
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage)
        }
    }

    private func dayCell(_ day: LocalDate) -> some View {
        let inMonth = day.month == month.month
        let isToday = day == today
        let isSelected = day == selected
        let dayEntries = entries[day] ?? []

        return Button {
            selected = day
            if !inMonth { changeMonth(by: day < month ? -1 : 1, selecting: day) }
        } label: {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(.callout.weight(isToday || isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? FamiliarColor.onAccent
                                     : inMonth ? FamiliarColor.textPrimary : FamiliarColor.textTertiary)
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(FamiliarColor.accentFill)
                        } else if isSelected {
                            Circle().fill(FamiliarColor.cardGlassPressed)
                                .overlay(Circle().strokeBorder(FamiliarColor.textPrimary.opacity(0.55), lineWidth: 1.5))
                        }
                    }
                dots(for: dayEntries)
                    .opacity(inMonth ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cellLabel(day, entries: dayEntries, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("calendar.day.\(day.description)")
        .accessibilityShowsLargeContentViewer {
            Text(cellLabel(day, entries: dayEntries, isToday: isToday))
        }
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
        .animation(FamiliarMotion.fade, value: dayEntries.count)
    }

    private func familyColor(_ familyID: UUID) -> Color {
        Color(session.familyDisplayColors[familyID] ?? session.membership(familyID)?.family.color ?? RGBColor(hex: 0xFF8C42))
    }

    private func cellLabel(_ day: LocalDate, entries: [CalendarEntry], isToday: Bool) -> String {
        let date = day.date(at: nil, in: .current).formatted(.dateTime.day().month(.wide))
        let tasks = entries.filter { if case .task = $0 { true } else { false } }.count
        let planned = entries.filter { if case .projected = $0 { true } else { false } }.count
        let external = entries.filter { if case .external = $0 { true } else { false } }.count
        var parts = [isToday ? String(localized: "Heute, \(date)") : date]
        if tasks > 0 { parts.append(tasks == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(tasks) Aufgaben")) }
        if planned > 0 { parts.append(String(localized: "\(planned) geplant")) }
        if external > 0 { parts.append(external == 1 ? String(localized: "1 Termin") : String(localized: "\(external) Termine")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Tagesliste

    @ViewBuilder
    private var dayList: some View {
        let dayEntries = entries[selected] ?? []
        Text(dayTitle)
            .font(FamiliarFont.groupLabel)
            .foregroundStyle(FamiliarColor.textSecondary)
            .padding(.top, FamiliarSpacing.xs)
            .padding(.leading, FamiliarSpacing.xxs)
            .accessibilityAddTraits(.isHeader)

        VStack(spacing: 0) {
            switch dayPhase {
            case .failed:
                FamiliarErrorState(message: loadError ?? "") { Task { await load() } }
                    .familiarCard()
                    .transition(FamiliarMotion.contentTransition)
            case .loading, .pending:
                // Platz halten, nichts zeigen: kein Kasten (auch nicht beim ersten Öffnen) und keine falsche
                // „Nichts geplant“-Aussage. Gleiche Höhe wie der Leerzustand, damit nichts springt.
                Color.clear.frame(height: Self.placeholderHeight)
            case .empty:
                // Bewusst leise: eine kleine Zeile, kein Symbol, keine Karte.
                // Direkt unter dem Datum, linksbündig wie dessen Überschrift; blendet nur ein (kein Schieben).
                Text("Nichts geplant")
                    .font(FamiliarFont.meta)
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .padding(.leading, FamiliarSpacing.xxs)
                    .frame(maxWidth: .infinity, minHeight: Self.placeholderHeight, alignment: .topLeading)
                    .accessibilityIdentifier("calendar.empty")
                    .transition(FamiliarMotion.contentTransition)
            case .list:
                VStack(spacing: 0) {
                    ForEach(Array(dayEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(FamiliarColor.hairline).padding(.leading, 64)
                        }
                        CalendarEntryRow(entry: entry, transition: transition) { taskID in path.append(taskID) }
                    }
                }
                .familiarCard(padding: FamiliarSpacing.xs)
                .transition(FamiliarMotion.contentTransition)
            }
        }
        // Überblendung nur zwischen den Zuständen (Platzhalter, „Nichts geplant“, Liste) – ein anderer Tag
        // mit eigener Liste wechselt sofort, ohne Geister.
        .familiarContentSwap(value: dayPhase)
    }

    /// Höhe des Bereichs unter dem Datum, solange nichts oder „Nichts geplant“ dort steht.
    private static let placeholderHeight: CGFloat = 28

    private enum DayPhase: Equatable {
        case failed, loading, pending, empty, list
    }

    /// „Nichts geplant“ erst nach dem ersten Laden – davor Platzhalter statt falscher Leere.
    private var dayPhase: DayPhase {
        if loadError != nil, entries.isEmpty || loadedMonth != month { return .failed }
        if !hasLoaded { return .loading }
        // Nach einem Monatswechsel erst anzeigen, wenn dessen Einträge da sind.
        if loadedMonth != month { return .pending }
        return (entries[selected] ?? []).isEmpty ? .empty : .list
    }

    private var dayTitle: String {
        let date = selected.date(at: nil, in: .current).formatted(.dateTime.weekday(.wide).day().month(.wide))
        return selected == today ? String(localized: "Heute · \(date)") : date
    }
}

/// Eine Zeile der Tagesliste: Uhrzeit links, Titel mit Familie, Status rechts.
private struct CalendarEntryRow: View {
    @Environment(SessionStore.self) private var session
    /// Breite der Zeitspalte in der Tagesliste, wächst mit der Schriftgröße.
    @ScaledMetric(relativeTo: .footnote) private var timeColumnWidth: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: CalendarEntry
    /// Quelle für den Zoom-Übergang Zeile → Details (ohne Quelle gäbe es keinen Zoom).
    let transition: Namespace.ID
    let onOpen: (UUID) -> Void

    var body: some View {
        switch entry {
        case .task(let task):
            Button { onOpen(task.id) } label: {
                row(time: timeText(task.startTime), title: task.title, familyID: task.familyID,
                    subtitle: subtitle(for: task), done: !task.isOpen, planned: false)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: task.id, in: transition)
            .accessibilityHint("Öffnet die Details")
            .accessibilityIdentifier("calendar.task.\(task.title)")
        case .projected(let occurrence):
            row(time: timeText(occurrence.startTime), title: occurrence.title, familyID: occurrence.familyID,
                subtitle: plannedSubtitle(occurrence), done: false, planned: true)
                .accessibilityHint("Geplanter Termin einer Serie; erscheint als Aufgabe, sobald er an der Reihe ist.")
        case .external(let event):
            row(time: event.isAllDay ? String(localized: "Ganzer Tag") : timeText(LocalTime(event.startsAt, timeZone: .current)),
                title: event.title, familyID: nil,
                subtitle: [timeRange(event), event.location].compactMap { $0 }.joined(separator: " · "),
                done: false, planned: false, externalProvider: event.providerName)
                .accessibilityIdentifier("calendar.event.\(event.title)")
        }
    }

    /// „9:00–10:00“ für Termine mit Uhrzeit.
    private func timeRange(_ event: ExternalEvent) -> String? {
        guard !event.isAllDay else { return nil }
        return "\(timeText(LocalTime(event.startsAt, timeZone: .current)))–\(timeText(LocalTime(event.endsAt, timeZone: .current)))"
    }

    private func row(time: String, title: String, familyID: UUID?, subtitle: String?, done: Bool, planned: Bool,
                     externalProvider: String? = nil) -> some View {
        // Bei den Bedienungshilfen-Schriftgrößen steht die Zeit über dem Titel (sonst Silbentrennung).
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: FamiliarSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: FamiliarSpacing.s))
        return layout {
            Text(time)
                .font(FamiliarFont.time)
                .foregroundStyle(FamiliarColor.textSecondary)
                // Spalte wächst mit der Schriftgröße, damit „Ganzer Tag“ nicht abgeschnitten wird.
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: stacked ? nil : timeColumnWidth, alignment: .leading)
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
                    .foregroundStyle(FamiliarColor.textSecondary)
            } else if let externalProvider {
                // Persönlicher Termin: eigenes Kennzeichen, kein Abhaken.
                Label(externalProvider, systemImage: "calendar")
                    .labelStyle(CompactLabelStyle())
                    .font(FamiliarFont.caption)
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .padding(.horizontal, FamiliarSpacing.xs)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(FamiliarColor.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, FamiliarSpacing.s)
        .padding(.vertical, FamiliarSpacing.s)
        .frame(minHeight: FamiliarSize.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Regel der Serie; bei „Reihum“ mit der Person, die an diesem Termin dran ist.
    private func plannedSubtitle(_ occurrence: ProjectedOccurrence) -> String {
        let rule = occurrence.rule.map(RecurrenceFormatting.summary) ?? String(localized: "Serie")
        guard let person = occurrence.rotationPerson else { return rule }
        return String(localized: "Reihum: \(session.displayName(of: person, in: occurrence.familyID)) · \(rule)")
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

#if DEBUG
#Preview {
    CalendarHomeView()
        .previewEnvironment(.ready)
}
#endif
