import SwiftUI

/// Leerer Zustand mit Orb und Symbol, Text und optionaler Aktion.
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
            ZStack {
                FamiliarOrb(diameter: 64)
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FamiliarColor.onAccent.opacity(0.85))
            }
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
                    }
                    .clipShape(shape)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
            .accessibilityHidden(true)
    }
}
