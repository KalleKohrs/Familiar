import SwiftUI

extension View {
    /// Eingabefeld im Stil „sunken“: vertiefte Fläche, feine Kante, mindestens 50 pt hoch.
    /// Für `TextField` und `SecureField`; Tastatur- und Autofill-Einstellungen setzt der Aufrufer.
    public func familiarInputField() -> some View {
        modifier(FamiliarInputFieldModifier())
    }

    /// Liest eine Fehler- oder Statusmeldung bei VoiceOver sofort vor, sobald sie erscheint.
    public func announcesChanges(of message: String?) -> some View {
        onChange(of: message) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            AccessibilityNotification.Announcement(newValue).post()
        }
    }
}

private struct FamiliarInputFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous)
        content
            .font(FamiliarFont.body)
            .foregroundStyle(FamiliarColor.textPrimary)
            .tint(FamiliarColor.accent)
            .focused($isFocused)
            .padding(.horizontal, FamiliarSpacing.m)
            .frame(minHeight: 50)
            .background(shape.fill(FamiliarColor.sunken))
            .overlay(
                shape.strokeBorder(isFocused ? FamiliarColor.accent.opacity(0.7) : FamiliarColor.hairline, lineWidth: 1)
            )
            .contentShape(shape)
    }
}

/// Fehlermeldung unter einem Formular: Symbol plus Text in `danger`, wird vorgelesen.
public struct FamiliarInlineError: View {
    let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(FamiliarFont.secondary)
        .foregroundStyle(FamiliarColor.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
