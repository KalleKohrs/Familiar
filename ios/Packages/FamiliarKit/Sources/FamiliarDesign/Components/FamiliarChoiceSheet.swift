import SwiftUI

/// Ruhige Entscheidungsfrage als kleines Blatt von unten (statt System-Aktionsmenü, das je nach
/// Gerät an wechselnden Stellen aufspringt): Symbol, Überschrift, Erklärung, untereinander die Aktionen.
/// Die Höhe passt sich dem Inhalt an, auch bei großen Schriften (dann scrollbar).
public struct FamiliarChoiceSheet<Actions: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 320

    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let actions: Actions

    public init(
        systemImage: String,
        tint: Color = FamiliarColor.accent,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: FamiliarSpacing.m) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(spacing: FamiliarSpacing.xs) {
                    Text(title)
                        .font(FamiliarFont.title)
                        .foregroundStyle(FamiliarColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message)
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: FamiliarSpacing.s) {
                    actions
                    Button("Abbrechen") { dismiss() }
                        .buttonStyle(.familiarSecondary)
                }
                .padding(.top, FamiliarSpacing.xs)
            }
            .padding(.horizontal, FamiliarSpacing.l)
            .padding(.top, FamiliarSpacing.xl)
            .padding(.bottom, FamiliarSpacing.m)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(FamiliarColor.elevated)
        .presentationCornerRadius(FamiliarRadius.card + 8)
    }
}
