import SwiftUI

/// Leerer Zustand mit Symbol, Text und optionaler Aktion.
public struct FamiliarEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: FamiliarSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(FamiliarColor.accent)
                .frame(width: 60, height: 60)
                .background(Circle().fill(FamiliarColor.elevated))
            .padding(.bottom, FamiliarSpacing.xs)
            .accessibilityHidden(true)
            VStack(spacing: FamiliarSpacing.xs) {
                Text(title)
                    .font(FamiliarFont.title)
                    .foregroundStyle(FamiliarColor.textPrimary)
                Text(message)
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.familiarPrimary)
                    .frame(maxWidth: 280)
            }
        }
        .padding(FamiliarSpacing.xl)
        .frame(maxWidth: .infinity)
        .transition(FamiliarMotion.contentTransition)
    }
}

/// Fehlerzustand mit verständlicher Meldung und „Erneut versuchen“.
public struct FamiliarErrorState: View {
    let message: String
    let retry: () -> Void

    public init(message: String, retry: @escaping () -> Void) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: FamiliarSpacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(FamiliarColor.warning)
                .accessibilityHidden(true)
            Text(message)
                .font(FamiliarFont.secondary)
                .foregroundStyle(FamiliarColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen", action: retry)
                .buttonStyle(.familiarSecondary)
                .frame(maxWidth: 240)
        }
        .padding(FamiliarSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Platzhalterblock während des Ladens. Der Schimmer entfällt bei „Bewegung reduzieren“.
///
/// Erscheint sofort (keine Verzögerung): Der Platz ist von Anfang an belegt, und der Wechsel zum
/// Inhalt ist eine Überblendung, die der umgebende Bereich mit `familiarContentSwap(value:)`
/// steuert. Liegen die Daten schon vor (Tabwechsel), wird der Platzhalter gar nicht erst gezeigt –
/// das entscheidet der Ladezustand, nicht ein Zeitgeber.
public struct FamiliarSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1
    let height: CGFloat

    public init(height: CGFloat = 88) {
        self.height = height
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
        shape
            .fill(FamiliarColor.card)
            .frame(height: height)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, FamiliarColor.lightEdge, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width)
                        // Nur der Schimmer läuft endlos – an den Wert gebunden, damit die
                        // Endlos-Animation nie auf andere Änderungen im selben Durchlauf übergreift.
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: phase)
                    }
                    .clipShape(shape)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                phase = 1.4
            }
            .transition(FamiliarMotion.contentTransition)
            .accessibilityHidden(true)
    }
}
