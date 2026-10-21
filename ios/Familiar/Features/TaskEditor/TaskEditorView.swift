import FamiliarCore
import FamiliarDesign
import PhotosUI
import SwiftUI

/// Aufgabe anlegen oder bearbeiten (Guide, Abschnitte 2 und 3).
/// Systemformular für gute Bedienbarkeit auf kleinen Displays, Tastatur und große Schriften.
struct TaskEditorView: View {
    enum Mode {
        case create
        case edit(TaskItem)
    }

    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    @Environment(TaskImageStore.self) private var images
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mode: Mode
    @State private var draft: TaskDraft
    @State private var original: TaskDraft
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var isSaving = false
    @State private var progressText: String?
    @State private var errorMessage: String?
    @State private var triedToSave = false
    @State private var confirmDiscard = false
    @State private var confirmScope = false
    @State private var invalidSaveAttempts = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case description
    }

    /// Sprungziele für „Noch offen“.
    private enum Anchor: Hashable {
        case title, family, repeating, assignees, mode, images
    }

    init(mode: Mode, defaultFamilyID: UUID? = nil) {
        self.mode = mode
        let draft: TaskDraft
        switch mode {
        case .create: draft = TaskDraft(familyID: defaultFamilyID)
        case .edit(let task): draft = TaskDraft(task: task)
        }
        _draft = State(initialValue: draft)
        _original = State(initialValue: draft)
    }

    private var editingTask: TaskItem? {
        if case .edit(let task) = mode { return task }
        return nil
    }

    /// Wiederholung lässt sich beim Anlegen festlegen und bei Vorkommen (mit sichtbarer Serie) ändern.
    private var showsRepeat: Bool {
        guard let task = editingTask else { return true }
        return task.isOccurrence && task.series != nil
    }

    private var editsSeriesOccurrence: Bool { showsRepeat && editingTask != nil }

    private var ruleChanged: Bool {
        draft.recurrence?.normalized != original.recurrence?.normalized
    }

    /// Familien, in denen der Nutzer Aufgaben anlegen darf (Admin-Schalter, Migration 0010).
    private var creatableFamilies: [FamilyMembership] {
        session.families.filter { $0.allows(.createTasks) }
    }

    private var members: [FamilyMember] {
        guard let familyID = draft.familyID else { return [] }
        return session.membership(familyID)?.sortedMembers ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                // Hinweise oben, damit sie auch auf kleinen Displays ohne Scrollen sichtbar sind.
                if let errorMessage {
                    Section { FamiliarInlineError(errorMessage) }
                        .listRowBackground(FamiliarColor.card)
                }
                if triedToSave && !draft.isValid {
                    Section { FamiliarInlineError(missingText) }
                        .listRowBackground(FamiliarColor.card)
                        .accessibilityIdentifier("editor.missing")
                }
                titleSection.id(Anchor.title)
                if editingTask == nil && creatableFamilies.count > 1 {
                    familySection.id(Anchor.family)
                }
                if showsRepeat {
                    repeatSection.id(Anchor.repeating)
                }
                startSection
                assigneesSection.id(Anchor.assignees)
                modeSection.id(Anchor.mode)
                imagesSection.id(Anchor.images)
            }
            .onChange(of: invalidSaveAttempts) { _, _ in
                // Zur ersten fehlenden Angabe springen, damit nichts „einfach wartet“.
                guard let anchor = firstIssueAnchor else { return }
                withAnimation(FamiliarMotion.animation(reduceMotion: reduceMotion)) { proxy.scrollTo(anchor, anchor: .center) }
            }
            }
            .scrollContentBackground(.hidden)
            // Tastatur verschwindet, sobald gescrollt wird.
            .scrollDismissesKeyboard(.immediately)
            .familiarScreenBackground()
            .tint(FamiliarColor.accent)
            .navigationTitle(editingTask == nil ? "Neue Aufgabe" : "Aufgabe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        if draft != original { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focusedField = nil }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingTask == nil ? "Hinzufügen" : "Fertig", action: save)
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .overlay {
                if isSaving {
                    savingOverlay
                }
            }
            .interactiveDismissDisabled(draft != original || isSaving)
            .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $confirmScope) {
                FamiliarChoiceSheet(
                    systemImage: "repeat",
                    title: "Änderung speichern für …",
                    message: ruleChanged
                        ? "Die neue Wiederholung gilt ab diesem Termin. Erledigte Termine bleiben unverändert; spätere offene werden neu geplant."
                        : "Erledigte und schon angefangene Termine bleiben unverändert."
                ) {
                    if !ruleChanged {
                        Button("Nur diesen Termin") { confirmScope = false; performSave(scope: .thisOccurrence) }
                            .buttonStyle(.familiarSecondary)
                            .accessibilityIdentifier("scope.single")
                    }
                    Button("Diesen und alle zukünftigen") { confirmScope = false; performSave(scope: .thisAndFuture) }
                        .buttonStyle(.familiarPrimary)
                        .accessibilityIdentifier("scope.future")
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await addPhotos(items) }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { data in addImage(data) }
                    .ignoresSafeArea()
            }
            .sensoryFeedback(.selection, trigger: draft.completionMode)
            .sensoryFeedback(.error, trigger: invalidSaveAttempts)
            .onChange(of: draft.recurrence) { _, _ in focusedField = nil }
            .onChange(of: draft.hasDate) { _, _ in focusedField = nil }
            .announcesChanges(of: errorMessage)
            .onAppear {
                if draft.familyID == nil { draft.familyID = creatableFamilies.first?.id }
                original.familyID = draft.familyID
            }
            .task {
                // Neue Aufgabe: gleich mit dem Titel beginnen.
                guard editingTask == nil else { return }
                try? await Task.sleep(for: .milliseconds(450))
                focusedField = .title
            }
        }
    }

    // MARK: Abschnitte

    private var titleSection: some View {
        Section {
            TextField("Titel", text: $draft.title)
                .font(FamiliarFont.cardTitle)
                .submitLabel(.next)
                .focused($focusedField, equals: .title)
                .onSubmit { focusedField = .description }
                .accessibilityIdentifier("editor.title")
            TextField("Beschreibung (optional)", text: $draft.description, axis: .vertical)
                .lineLimit(2...8)
                .focused($focusedField, equals: .description)
                .accessibilityIdentifier("editor.description")
        } footer: {
            if showsIssue(.titleMissing) {
                issueText("Bitte gib einen Titel ein.")
            }
        }
        .listRowBackground(FamiliarColor.card)
    }

    private var familySection: some View {
        Section("Familie") {
            Picker("Familie", selection: $draft.familyID) {
                ForEach(creatableFamilies) { membership in
                    Text(membership.family.name).tag(Optional(membership.id))
                }
            }
            .onChange(of: draft.familyID) { _, _ in
                // Zugewiesene Personen gehören zur Familie; bei einem Wechsel neu wählen.
                draft.assigneeIDs = []
            }
        }
        .listRowBackground(FamiliarColor.card)
    }

    private var startSection: some View {
        Section {
            if draft.recurrence == nil {
                Toggle("Datum", isOn: $draft.hasDate.animation(FamiliarMotion.animation(reduceMotion: reduceMotion)))
                    .accessibilityIdentifier("editor.hasDate")
            }
            if draft.usesDate {
                DatePicker(draft.recurrence != nil && editingTask == nil ? "Ab" : "Tag",
                           selection: dateBinding, displayedComponents: .date)
                    .environment(\.timeZone, timeZone)
                    .accessibilityIdentifier("editor.date")
                Toggle("Uhrzeit", isOn: $draft.hasTime.animation(FamiliarMotion.animation(reduceMotion: reduceMotion)))
                if draft.hasTime {
                    DatePicker("Uhrzeit", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, timeZone)
                }
            }
        } header: {
            Text("Start")
        } footer: {
            if draft.recurrence == nil {
                Text("Optional. Ohne Datum steht die Aufgabe ganz oben in der Liste.")
            } else if editingTask != nil {
                Text("Datum dieses Vorkommens.")
            } else {
                Text("Die Aufgabe wiederholt sich ab diesem Tag.")
            }
        }
        .listRowBackground(FamiliarColor.card)
    }

    private var repeatSection: some View {
        Section {
            Picker("Wiederholen", selection: frequencyBinding.animation(FamiliarMotion.animation(reduceMotion: reduceMotion))) {
                if editingTask == nil {
                    Text("Nie").tag(RecurrenceFrequency?.none)
                }
                Text("Täglich").tag(RecurrenceFrequency?.some(.daily))
                Text("An Wochentagen").tag(RecurrenceFrequency?.some(.weekly))
                Text("An Monatstagen").tag(RecurrenceFrequency?.some(.monthly))
            }
            .accessibilityIdentifier("editor.repeat")
            if draft.recurrence?.frequency == .weekly {
                weekdayPicker
            }
            if draft.recurrence?.frequency == .monthly {
                monthDayPicker
            }
        } header: {
            Text("Wiederholung")
        } footer: {
            if showsIssue(.recurrenceIncomplete) {
                issueText("Bitte wähle mindestens einen Tag.")
            } else if let footer = repeatFooter {
                Text(footer)
            }
        }
        .listRowBackground(FamiliarColor.card)
    }

    private var weekdayPicker: some View {
        FlowRow(spacing: FamiliarSpacing.xs) {
            ForEach(RecurrenceFormatting.weekdayOrder, id: \.self) { day in
                let isSelected = draft.recurrence?.weekdays.contains(day) == true
                dayButton(RecurrenceFormatting.shortWeekday(day), isSelected: isSelected) {
                    toggle(day, in: \.weekdays)
                }
                .accessibilityLabel(RecurrenceFormatting.weekday(day))
                .accessibilityIdentifier("editor.weekday.\(day)")
            }
        }
        .padding(.vertical, FamiliarSpacing.xxs)
    }

    private var monthDayPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: FamiliarSpacing.xxs), count: 7),
                  spacing: FamiliarSpacing.xxs) {
            ForEach(1...31, id: \.self) { day in
                let isSelected = draft.recurrence?.monthDays.contains(day) == true
                dayButton("\(day)", isSelected: isSelected) {
                    toggle(day, in: \.monthDays)
                }
                .accessibilityLabel("\(day).")
                .accessibilityIdentifier("editor.monthDay.\(day)")
            }
        }
        .padding(.vertical, FamiliarSpacing.xxs)
    }

    private func dayButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(isSelected ? FamiliarColor.onAccent : FamiliarColor.textPrimary)
                .frame(minWidth: 40, maxWidth: 52, minHeight: 40)
                .background(Circle().fill(isSelected ? FamiliarColor.accent : FamiliarColor.elevated))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ day: Int, in keyPath: WritableKeyPath<RecurrenceRule, [Int]>) {
        guard var rule = draft.recurrence else { return }
        if let index = rule[keyPath: keyPath].firstIndex(of: day) {
            rule[keyPath: keyPath].remove(at: index)
        } else {
            rule[keyPath: keyPath].append(day)
        }
        draft.recurrence = rule
    }

    /// Wochen- und Monatsregeln starten mit dem Wochentag bzw. Tag des gewählten Datums.
    private var frequencyBinding: Binding<RecurrenceFrequency?> {
        Binding {
            draft.recurrence?.frequency
        } set: { frequency in
            guard let frequency else {
                draft.recurrence = nil
                return
            }
            guard frequency != draft.recurrence?.frequency else { return }
            switch frequency {
            case .daily: draft.recurrence = .daily
            case .weekly: draft.recurrence = .weekly([draft.date.isoWeekday])
            case .monthly: draft.recurrence = .monthly([draft.date.day])
            }
        }
    }

    private var repeatFooter: String? {
        guard let rule = draft.recurrence else { return nil }
        if editingTask != nil {
            return ruleChanged
                ? String(localized: "Die neue Wiederholung gilt für dieses und alle späteren Vorkommen.")
                : nil
        }
        var parts: [String] = []
        let today = LocalDate(.now, timeZone: timeZone)
        if rule.isComplete, let first = rule.normalized.firstDate(onOrAfter: max(draft.date, today)) {
            let date = first.date(at: nil, in: timeZone).formatted(.dateTime.weekday(.wide).day().month(.wide))
            parts.append(String(localized: "Erstes Mal: \(date)."))
        }
        if rule.frequency == .monthly && rule.monthDays.contains(where: { $0 > 28 }) {
            parts.append(String(localized: "Gibt es den Tag in einem Monat nicht, gilt der letzte Tag des Monats."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var assigneesSection: some View {
        Section {
            ForEach(members) { member in
                let isSelected = draft.assigneeIDs.contains(member.userID)
                Button {
                    focusedField = nil
                    draft.toggleAssignee(member.userID)
                } label: {
                    HStack(spacing: FamiliarSpacing.s) {
                        ProfileAvatar(profile: member.profile, name: member.displayName, diameter: 32)
                        Text(member.userID == session.userID ? "\(member.displayName) (du)" : member.displayName)
                            .foregroundStyle(FamiliarColor.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? FamiliarColor.accent : FamiliarColor.textTertiary)
                    }
                    .frame(minHeight: FamiliarSize.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("editor.assignee.\(member.displayName)")
            }
        } header: {
            Text("Zugewiesen")
        } footer: {
            if showsIssue(.assigneesMissing) {
                issueText("Bitte weise mindestens eine Person zu.")
            } else {
                Text("Mindestens eine Person. Wer die Aufgabe anlegt, ist nicht automatisch zugewiesen.")
            }
        }
        .listRowBackground(FamiliarColor.card)
    }

    /// Zwei kompakte Kacheln nebeneinander (wie die Aktionskacheln der Design-Referenz);
    /// die Erklärung steht nur einmal darunter – für die gewählte Art.
    private var modeSection: some View {
        Section {
            // Große Schriften: Kacheln untereinander statt nebeneinander.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: FamiliarSpacing.xs))
                : AnyLayout(HStackLayout(spacing: FamiliarSpacing.xs))
            layout {
                ForEach([CompletionMode.anyOne, .each], id: \.self) { mode in
                    modeTile(mode)
                }
            }
            .listRowInsets(EdgeInsets(top: FamiliarSpacing.xs, leading: FamiliarSpacing.xs,
                                      bottom: FamiliarSpacing.xs, trailing: FamiliarSpacing.xs))
        } header: {
            Text("Erledigung")
        } footer: {
            if !draft.needsCompletionModeChoice {
                Text("Bei einer Person spielt das keine Rolle – sie hakt die Aufgabe ab.")
            } else if showsIssue(.completionModeMissing) {
                issueText("Bitte wähle, wie die Aufgabe erledigt wird.")
            } else if let mode = draft.completionMode {
                Text(TaskFormatting.modeExplanation(mode))
            } else {
                Text("Bitte bewusst wählen.")
            }
        }
        .listRowBackground(showsIssue(.completionModeMissing) ? FamiliarColor.danger.opacity(0.12) : FamiliarColor.card)
    }

    private func modeTile(_ mode: CompletionMode) -> some View {
        let isSelected = draft.effectiveCompletionMode == mode
        let isEnabled = draft.needsCompletionModeChoice
        let shape = RoundedRectangle(cornerRadius: FamiliarRadius.chip + 4, style: .continuous)
        return Button {
            focusedField = nil
            if let task = editingTask, task.completionMode != mode, task.assignees.contains(where: \.isDone) {
                errorMessage = String(localized: "Die Erledigungsart lässt sich nicht mehr ändern, weil schon jemand abgehakt hat.")
                return
            }
            draft.completionMode = mode
        } label: {
            VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                Image(systemName: TaskFormatting.modeSymbol(mode))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? FamiliarColor.accent : FamiliarColor.textSecondary)
                Text(TaskFormatting.modeShortTitle(mode))
                    .font(FamiliarFont.secondary.weight(.semibold))
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(FamiliarSpacing.s)
            .background(shape.fill(isSelected ? FamiliarColor.accent.opacity(0.14) : FamiliarColor.cardGlass))
            .overlay(shape.strokeBorder(isSelected ? FamiliarColor.accent : FamiliarColor.hairline,
                                        lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // Bei einer Person automatisch gewählt und ausgegraut.
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .familiarAnimation(FamiliarMotion.snappy, value: isSelected)
        .familiarAnimation(FamiliarMotion.snappy, value: isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TaskFormatting.modeTitle(mode))
        .accessibilityHint(TaskFormatting.modeExplanation(mode))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor.mode.\(mode.rawValue)")
    }

    // MARK: Fehlende Angaben

    private func showsIssue(_ issue: TaskDraft.Issue) -> Bool {
        triedToSave && draft.issues.contains(issue)
    }

    private func issueText(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(FamiliarColor.danger)
            .font(FamiliarFont.meta.weight(.semibold))
    }

    private var firstIssueAnchor: Anchor? {
        guard let issue = draft.issues.first else { return nil }
        return switch issue {
        case .familyMissing: .family
        case .titleMissing, .titleTooLong, .descriptionTooLong: .title
        case .recurrenceIncomplete: .repeating
        case .assigneesMissing: .assignees
        case .completionModeMissing: .mode
        case .tooManyImages: .images
        }
    }

    private var imagesSection: some View {
        Section {
            if !draft.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FamiliarSpacing.xs) {
                        ForEach(Array(draft.images.enumerated()), id: \.element.id) { index, image in
                            thumbnail(image)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        draft.images.removeAll { $0.id == image.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(FamiliarColor.textPrimary, .black.opacity(0.6))
                                            .font(.title3)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 10, y: -10)
                                    .accessibilityLabel("Bild \(index + 1) entfernen")
                                }
                        }
                    }
                    .padding(.vertical, FamiliarSpacing.s)
                    .padding(.trailing, FamiliarSpacing.s)
                }
                // Horizontale Liste: kein Platz für die schwebende Leiste nötig.
                .contentMargins(.bottom, 0)
            }
            let remaining = TaskDraft.maxImages - draft.images.count
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(remaining, 1), matching: .images) {
                Label("Fotos wählen", systemImage: "photo.on.rectangle")
            }
            .disabled(remaining <= 0)
            if CameraPicker.isAvailable {
                Button {
                    showsCamera = true
                } label: {
                    Label("Foto aufnehmen", systemImage: "camera")
                }
                .disabled(remaining <= 0)
            }
        } header: {
            Text("Bilder")
        } footer: {
            Text("Bis zu \(TaskDraft.maxImages) Bilder. Sichtbar nur für Personen, die die Aufgabe sehen dürfen.")
        }
        .listRowBackground(FamiliarColor.card)
    }

    @ViewBuilder
    private func thumbnail(_ image: DraftImage) -> some View {
        Group {
            switch image {
            case .existing(let stored):
                TaskImageView(path: stored.thumbPath)
            case .new(let prepared):
                if let uiImage = UIImage(data: prepared.thumbnailData) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.chip, style: .continuous))
    }

    private var savingOverlay: some View {
        VStack(spacing: FamiliarSpacing.s) {
            ProgressView()
            Text(progressText ?? String(localized: "Wird gespeichert …"))
                .font(FamiliarFont.secondary)
                .foregroundStyle(FamiliarColor.textSecondary)
        }
        .padding(FamiliarSpacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: FamiliarRadius.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: Datum und Uhrzeit

    private var timeZone: TimeZone { TimeZone(identifier: draft.timezone) ?? .current }

    private var dateBinding: Binding<Date> {
        Binding {
            draft.date.date(at: LocalTime(hour: 12, minute: 0), in: timeZone)
        } set: { newValue in
            draft.date = LocalDate(newValue, timeZone: timeZone)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            draft.date.date(at: draft.time, in: timeZone)
        } set: { newValue in
            draft.time = LocalTime(newValue, timeZone: timeZone)
        }
    }

    // MARK: Aktionen

    private var missingText: String {
        let parts = draft.issues.map { issue in
            switch issue {
            case .familyMissing: String(localized: "Familie")
            case .titleMissing: String(localized: "Titel")
            case .titleTooLong: String(localized: "Titel höchstens 200 Zeichen")
            case .descriptionTooLong: String(localized: "Beschreibung höchstens 4000 Zeichen")
            case .assigneesMissing: String(localized: "mindestens eine Person")
            case .completionModeMissing: String(localized: "Erledigungsart")
            case .tooManyImages: String(localized: "höchstens 10 Bilder")
            case .recurrenceIncomplete: String(localized: "mindestens ein Tag für die Wiederholung")
            }
        }
        return String(localized: "Noch offen: \(parts.formatted(.list(type: .and)))")
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                addImage(data)
            }
        }
        pickerItems = []
    }

    private func addImage(_ data: Data) {
        guard draft.images.count < TaskDraft.maxImages else { return }
        guard let prepared = ImageProcessor.taskImage(from: data) else {
            errorMessage = String(localized: "Ein Bild konnte nicht gelesen werden.")
            return
        }
        draft.images.append(.new(prepared))
    }

    private func save() {
        triedToSave = true
        errorMessage = nil
        focusedField = nil
        guard draft.isValid else {
            invalidSaveAttempts += 1
            return
        }
        if editsSeriesOccurrence {
            confirmScope = true
        } else {
            performSave(scope: .thisOccurrence)
        }
    }

    private func performSave(scope: TaskStore.EditScope) {
        isSaving = true
        Task {
            defer {
                isSaving = false
                progressText = nil
            }
            do throws(FamiliarError) {
                if let familyID = draft.familyID {
                    for case .new(let image) in draft.images {
                        images.insert(image, familyID: familyID)
                    }
                }
                try await store.save(draft, editing: editingTask, scope: scope) { current, total in
                    progressText = String(localized: "Bild \(current) von \(total) wird hochgeladen …")
                }
                dismiss()
            } catch {
                errorMessage = error.message
            }
        }
    }
}
