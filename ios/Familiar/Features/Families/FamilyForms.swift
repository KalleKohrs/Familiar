import FamiliarCore
import FamiliarDesign
import SwiftUI
import UIKit

/// Neue Familie: Name und Farbe (Vorschläge oder eigene Farbe). Der Ersteller wird Admin.
struct CreateFamilyForm: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = FamilyPalette.presets[0].hex
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.l) {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                    Text("Name")
                        .font(FamiliarFont.sectionTitle)
                        .foregroundStyle(FamiliarColor.textSecondary)
                    TextField("z. B. Familie Lindner", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .familiarInputField()
                        .accessibilityLabel("Name der Familie")
                        .accessibilityIdentifier("createFamily.name")
                }

                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    Text("Farbe")
                        .font(FamiliarFont.sectionTitle)
                        .foregroundStyle(FamiliarColor.textSecondary)
                    FamilyColorPicker(colorHex: $colorHex)
                    FamilyBadge(name: InputRules.trimmed(name).isEmpty ? "Vorschau" : InputRules.trimmed(name),
                                color: Color(RGBColor(hex: colorHex) ?? FamilyPalette.presets[0].rgb))
                }

                if let errorMessage {
                    FamiliarInlineError(errorMessage)
                }

                Button(action: save) {
                    HStack(spacing: FamiliarSpacing.xs) {
                        if isSaving { ProgressView().tint(FamiliarColor.onAccent) }
                        Text("Familie erstellen")
                    }
                }
                .buttonStyle(.familiarPrimary)
                .disabled(!InputRules.isValidFamilyName(name) || isSaving)
                .accessibilityIdentifier("createFamily.submit")
            }
            .padding(FamiliarSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .familiarScreenBackground()
        .navigationTitle("Familie erstellen")
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: errorMessage)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do throws(FamiliarError) {
                try await session.createFamily(name: name, colorHex: colorHex)
                dismiss()
            } catch {
                errorMessage = error.message
            }
        }
    }
}

/// Mit Einladungscode beitreten. Ungültige Codes zeigt der Server als Meldung (mit Rate-Limit).
struct JoinFamilyForm: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.m) {
                Text("Den 8-stelligen Code bekommst du von jemandem aus der Familie – zum Beispiel ABCD-EFGH. Er gilt 7 Tage.")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)

                TextField("Einladungscode", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3.monospaced().weight(.semibold))
                    .submitLabel(.join)
                    .onSubmit(join)
                    .familiarInputField()
                    .accessibilityIdentifier("joinFamily.code")

                if let message {
                    FamiliarInlineError(message)
                }

                Button(action: join) {
                    HStack(spacing: FamiliarSpacing.xs) {
                        if isJoining { ProgressView().tint(FamiliarColor.onAccent) }
                        Text("Beitreten")
                    }
                }
                .buttonStyle(.familiarPrimary)
                .disabled(!InviteCode.isValid(code) || isJoining)
                .accessibilityIdentifier("joinFamily.submit")
            }
            .padding(FamiliarSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .familiarScreenBackground()
        .navigationTitle("Mit Code beitreten")
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: message)
    }

    private func join() {
        guard InviteCode.isValid(code), !isJoining else { return }
        isJoining = true
        message = nil
        Task {
            defer { isJoining = false }
            do throws(FamiliarError) {
                let result = try await session.joinFamily(code: code)
                if result.isSuccess {
                    dismiss()
                } else {
                    message = result.message
                }
            } catch {
                message = error.message
            }
        }
    }
}

/// Farbwahl einer Familie: Vorschläge als Kreise plus eigene Farbe.
struct FamilyColorPicker: View {
    @Binding var colorHex: String
    private let columns = Array(repeating: GridItem(.flexible(), spacing: FamiliarSpacing.s), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            LazyVGrid(columns: columns, spacing: FamiliarSpacing.s) {
                ForEach(FamilyPalette.presets) { preset in
                    colorSwatch(preset)
                }
            }
            ColorPicker("Eigene Farbe", selection: customColor, supportsOpacity: false)
                .font(FamiliarFont.body)
                .padding(.vertical, FamiliarSpacing.xxs)
        }
        .sensoryFeedback(.selection, trigger: colorHex)
    }

    private func colorSwatch(_ preset: FamilyPaletteColor) -> some View {
        let isSelected = preset.hex.caseInsensitiveCompare(colorHex) == .orderedSame
        return Button {
            colorHex = preset.hex
        } label: {
            Circle()
                .fill(Color(preset.rgb))
                .frame(width: 44, height: 44)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(FamiliarColor.onAccent)
                    }
                }
                .overlay(Circle().strokeBorder(FamiliarColor.textPrimary.opacity(isSelected ? 0.9 : 0), lineWidth: 2).padding(-4))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customColor: Binding<Color> {
        Binding {
            Color(RGBColor(hex: colorHex) ?? FamilyPalette.presets[0].rgb)
        } set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            colorHex = RGBColor(red: red, green: green, blue: blue).hexString
        }
    }
}

/// Familie bearbeiten: Name, Farbe und Sichtbarkeit der Aufgaben (Recht „Familie bearbeiten“).
struct FamilySettingsForm: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let family: Family

    @State private var name: String
    @State private var colorHex: String
    @State private var visibility: TaskVisibility
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(family: Family) {
        self.family = family
        _name = State(initialValue: family.name)
        _colorHex = State(initialValue: family.colorHex)
        _visibility = State(initialValue: family.taskVisibility)
    }

    private var hasChanges: Bool {
        InputRules.trimmed(name) != family.name || colorHex.uppercased() != family.colorHex.uppercased()
            || visibility != family.taskVisibility
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.l) {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                    FamiliarSectionHeader("Name")
                    TextField("Name der Familie", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .familiarInputField()
                        .accessibilityIdentifier("familySettings.name")
                }

                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    FamiliarSectionHeader("Farbe")
                    FamilyColorPicker(colorHex: $colorHex)
                }

                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    FamiliarSectionHeader("Wer sieht welche Aufgaben?")
                    visibilityOption(.all, title: "Alle sehen alles",
                                     text: "Jedes Mitglied sieht alle Aufgaben der Familie.")
                    visibilityOption(.assignedOnly, title: "Nur Eigenes",
                                     text: "Jede Person sieht nur Aufgaben, die ihr zugewiesen sind oder die sie angelegt hat.")
                }

                if let errorMessage {
                    FamiliarInlineError(errorMessage)
                }

                Button(action: save) {
                    HStack(spacing: FamiliarSpacing.xs) {
                        if isSaving { ProgressView().tint(FamiliarColor.onAccent) }
                        Text("Speichern")
                    }
                }
                .buttonStyle(.familiarPrimary)
                .disabled(!hasChanges || !InputRules.isValidFamilyName(name) || isSaving)
                .accessibilityIdentifier("familySettings.save")
            }
            .padding(FamiliarSpacing.m)
        }
        .scrollDismissesKeyboard(.immediately)
        .familiarScreenBackground()
        .navigationTitle("Familie bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: errorMessage)
    }

    private func visibilityOption(_ option: TaskVisibility, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        let isSelected = visibility == option
        return Button {
            visibility = option
        } label: {
            HStack(alignment: .top, spacing: FamiliarSpacing.s) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? FamiliarColor.accent : FamiliarColor.textTertiary)
                VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                    Text(title)
                        .font(FamiliarFont.body.weight(.semibold))
                        .foregroundStyle(FamiliarColor.textPrimary)
                    Text(text)
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, FamiliarSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do throws(FamiliarError) {
                try await session.updateFamily(family.id, name: name, colorHex: colorHex.uppercased(), visibility: visibility)
                dismiss()
            } catch {
                errorMessage = error.message
            }
        }
    }
}
