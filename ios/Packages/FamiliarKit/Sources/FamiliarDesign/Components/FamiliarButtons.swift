import SwiftUI

/// Kapselförmige Buttons in drei Rollen. Mindesthöhe 50 pt für komfortable Touch-Flächen.
public struct FamiliarButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        case primary
        case secondary
        case destructive
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, FamiliarSpacing.l)
            .background(Capsule().fill(background))
            .overlay {
                if kind != .primary {
                    Capsule().strokeBorder(FamiliarGradient.edge, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(FamiliarMotion.animation(FamiliarMotion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: FamiliarColor.onAccent
        case .secondary: FamiliarColor.textPrimary
        case .destructive: FamiliarColor.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: FamiliarColor.accent
        case .secondary, .destructive: FamiliarColor.card
        }
    }
}

extension ButtonStyle where Self == FamiliarButtonStyle {
    public static var familiarPrimary: FamiliarButtonStyle { FamiliarButtonStyle(kind: .primary) }
    public static var familiarSecondary: FamiliarButtonStyle { FamiliarButtonStyle(kind: .secondary) }
    public static var familiarDestructive: FamiliarButtonStyle { FamiliarButtonStyle(kind: .destructive) }
}

/// Runder Abhak-Button: 28 pt sichtbar, mindestens 44 pt Touch-Fläche.
public struct CompletionCheckButton: View {
    let isDone: Bool
    let tint: Color
    let action: () -> Void

    public init(isDone: Bool, tint: Color = FamiliarColor.accent, action: @escaping () -> Void) {
        self.isDone = isDone
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? tint : FamiliarColor.textTertiary, lineWidth: 2)
                    .background(Circle().fill(isDone ? tint : .clear))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FamiliarColor.onAccent)
                        .transition(.opacity)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: FamiliarSize.minimumTouchTarget, height: FamiliarSize.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .familiarAnimation(FamiliarMotion.snappy, value: isDone)
        .accessibilityLabel(isDone ? "Erledigt" : "Abhaken")
        .accessibilityHint(isDone ? "Doppeltippen, um das Abhaken rückgängig zu machen." : "")
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}
