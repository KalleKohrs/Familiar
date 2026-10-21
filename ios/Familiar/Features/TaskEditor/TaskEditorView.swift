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

    private var members: [FamilyMember] {
        guard let familyID = draft.familyID else { return [] }
        return session.membership(familyID)?.sortedMembers ?? []
    }

    var body: some View {
        NavigationStack {
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
                titleSection
                if editingTask == nil && session.families.count > 1 {
                    familySection
                }
                startSection
                assigneesSection
                modeSection
                imagesSection
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
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
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await addPhotos(items) }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { data in addImage(data) }
                    .ignoresSafeArea()
            }
            .sensoryFeedback(.selection, trigger: draft.completionMode)
            .announcesChanges(of: errorMessage)
            .onAppear {
                if draft.familyID == nil { draft.familyID = session.families.first?.id }
                original.familyID = draft.familyID
            }
        }
    }

    // MARK: Abschnitte

    private var titleSection: some View {
        Section {
            TextField("Titel", text: $draft.title, axis: .vertical)
                .font(FamiliarFont.cardTitle)
                .lineLimit(1...3)
                .submitLabel(.next)
                .accessibilityIdentifier("editor.title")
            TextField("Beschreibung (optional)", text: $draft.description, axis: .vertical)
                .lineLimit(2...8)
                .accessibilityIdentifier("editor.description")
        }
        .listRowBackground(FamiliarColor.card)
    }

    private var familySection: some View {
        Section("Familie") {
            Picker("Familie", selection: $draft.familyID) {
                ForEach(session.families) { membership in
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
            Toggle("Datum", isOn: $draft.hasDate.animation())
                .accessibilityIdentifier("editor.hasDate")
            if draft.hasDate {
                DatePicker("Tag", selection: dateBinding, displayedComponents: .date)
                    .environment(\.timeZone, timeZone)
                Toggle("Uhrzeit", isOn: $draft.hasTime.animation())
                if draft.hasTime {
                    DatePicker("Uhrzeit", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, timeZone)
                }
            }
        } header: {
            Text("Start")
        } footer: {
            Text("Optional. Ohne Datum steht die Aufgabe ganz oben in der Liste.")
        }
        .listRowBackground(FamiliarColor.card)
    }

    private var assigneesSection: some View {
        Section {
            ForEach(members) { member in
                let isSelected = draft.assigneeIDs.contains(member.userID)
                Button {
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
            Text("Mindestens eine Person. Wer die Aufgabe anlegt, ist nicht automatisch zugewiesen.")
        }
        .listRowBackground(FamiliarColor.card)
    }

    private var modeSection: some View {
        Section {
            ForEach([CompletionMode.anyOne, .each], id: \.self) { mode in
                let isSelected = draft.completionMode == mode
                Button {
                    if let task = editingTask, task.completionMode != mode, task.assignees.contains(where: \.isDone) {
                        errorMessage = String(localized: "Die Erledigungsart lässt sich nicht mehr ändern, weil schon jemand abgehakt hat.")
                        return
                    }
                    draft.completionMode = mode
                } label: {
                    HStack(alignment: .top, spacing: FamiliarSpacing.s) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? FamiliarColor.accent : FamiliarColor.textTertiary)
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                            Text(TaskFormatting.modeTitle(mode))
                                .font(FamiliarFont.body.weight(.semibold))
                                .foregroundStyle(FamiliarColor.textPrimary)
                            Text(TaskFormatting.modeExplanation(mode))
                                .font(FamiliarFont.secondary)
                                .foregroundStyle(FamiliarColor.textSecondary)
                        }
                    }
                    .padding(.vertical, FamiliarSpacing.xxs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("editor.mode.\(mode.rawValue)")
            }
        } header: {
            Text("Erledigung")
        } footer: {
            if editingTask == nil {
                Text("Bitte bewusst wählen.")
            }
        }
        .listRowBackground(FamiliarColor.card)
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
        guard draft.isValid else { return }
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
                _ = try await store.save(draft, editing: editingTask) { current, total in
                    progressText = String(localized: "Bild \(current) von \(total) wird hochgeladen …")
                }
                dismiss()
            } catch {
                errorMessage = error.message
            }
        }
    }
}
