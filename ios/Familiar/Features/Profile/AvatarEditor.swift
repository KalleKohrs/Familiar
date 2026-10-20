import FamiliarCore
import FamiliarDesign
import PhotosUI
import SwiftUI

/// Profilbild anzeigen, aus Fotos wählen oder entfernen. Der Fotoauswahl-Dialog des Systems
/// braucht keine Fotos-Berechtigung.
struct AvatarEditor: View {
    @Environment(SessionStore.self) private var session
    @State private var selection: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var name: String { session.profile?.displayName ?? "" }
    private var hasAvatar: Bool { session.profile?.avatarPath != nil }

    var body: some View {
        VStack(spacing: FamiliarSpacing.s) {
            ProfileAvatar(profile: session.profile, name: name, diameter: 104)
                .overlay {
                    if isWorking {
                        Circle().fill(.black.opacity(0.45))
                        ProgressView().tint(FamiliarColor.textPrimary)
                    }
                }
                .accessibilityLabel(hasAvatar ? "Profilbild" : "Kein Profilbild, Initialen")

            HStack(spacing: FamiliarSpacing.s) {
                // Das Label von PhotosPicker ist eine Sendable-Closure: Titel vorher berechnen.
                let pickerTitle: LocalizedStringKey = hasAvatar ? "Bild ändern" : "Bild wählen"
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    Text(pickerTitle)
                }
                .buttonStyle(.familiarSecondary)
                .disabled(isWorking)

                if hasAvatar {
                    Button("Entfernen", role: .destructive, action: remove)
                        .buttonStyle(.familiarSecondary)
                        .disabled(isWorking)
                }
            }

            if let errorMessage {
                FamiliarInlineError(errorMessage)
            }
        }
        .announcesChanges(of: errorMessage)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            upload(item)
        }
    }

    private func upload(_ item: PhotosPickerItem) {
        isWorking = true
        errorMessage = nil
        Task {
            defer {
                isWorking = false
                selection = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = AvatarImageProcessor.jpegData(from: data) else {
                errorMessage = String(localized: "Das Bild konnte nicht gelesen werden. Bitte wähle ein anderes.")
                return
            }
            do throws(FamiliarError) {
                try await session.uploadAvatar(jpegData: jpeg)
            } catch {
                errorMessage = error.message
            }
        }
    }

    private func remove() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do throws(FamiliarError) {
                try await session.removeAvatar()
            } catch {
                errorMessage = error.message
            }
        }
    }
}

/// Anzeigename bearbeiten; gespeichert wird erst über die Aktion des Aufrufers.
struct DisplayNameField: View {
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
            Text("Name")
                .font(FamiliarFont.sectionTitle)
                .foregroundStyle(FamiliarColor.textSecondary)
            TextField("Wie dich andere sehen", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .familiarInputField()
                .accessibilityLabel("Name")
                .accessibilityIdentifier("profile.name")
            if !name.isEmpty && !InputRules.isValidDisplayName(name) {
                FamiliarInlineError(String(localized: "Der Name darf höchstens 80 Zeichen lang sein."))
            }
        }
    }
}
