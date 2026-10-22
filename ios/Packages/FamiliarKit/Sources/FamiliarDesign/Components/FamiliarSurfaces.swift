import SwiftUI

extension View {
    /// Content-Fläche mit großzügigem Radius und feiner Lichtkante oben.
    /// Leicht durchscheinend über dem Ambient-Hintergrund, aber bewusst ohne Blur,
    /// damit lange Listen flüssig scrollen. Bei „Transparenz reduzieren“ opak.
    public func familiarCard(padding: CGFloat = FamiliarSpacing.m, isPressed: Bool = false) -> some View {
        modifier(FamiliarCardModifier(padding: padding, isPressed: isPressed))
    }

    /// Bildschirmhintergrund: warmes Graphit mit ruhigem, statischem Ambient-Licht,
    /// randlos bis in die Safe Areas.
    public func familiarScreenBackground() -> some View {
        background { FamiliarAmbientBackground().ignoresSafeArea() }
            // Scrollende Inhalte blenden oben weich unter den schwebenden Knöpfen aus – ohne
            // sichtbare Kante (der harte Stil zeichnete eine Trennlinie; gilt für alle Scroll-Ansichten).
            .scrollEdgeEffectStyle(.soft, for: .top)
    }

    /// Dezenter, statischer Perlmutt-Reflex als Rand – nur für hervorgehobene Elemente.
    public func pearlEdge<S: InsettableShape>(_ shape: S, lineWidth: CGFloat = 1) -> some View {
        overlay(shape.strokeBorder(FamiliarGradient.pearl, lineWidth: lineWidth).allowsHitTesting(false))
    }
}

/// Statischer Hintergrund mit zwei weichen Lichtquellen: warm oben, Pflaume (hell: Rosé) unten links.
/// Keine Animation und kein Blur – reine Verläufe, daher auch auf älteren Geräten günstig.
/// Im Hellen kräftiger, damit das Papier nicht flach wirkt. Bei „Kontrast erhöhen“ und
/// „Transparenz reduzieren“ deutlich zurückgenommen.
public struct FamiliarAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        let strength = (contrast == .increased || reduceTransparency) ? 0.4 : 1.0
        let light = colorScheme == .light
        ZStack {
            FamiliarColor.canvas
            RadialGradient(
                colors: [FamiliarColor.glowWarm.opacity((light ? 0.42 : 0.16) * strength), .clear],
                center: light ? UnitPoint(x: 0.7, y: -0.05) : UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: light ? 520 : 460
            )
            RadialGradient(
                colors: [FamiliarColor.glowPlum.opacity((light ? 0.45 : 0.28) * strength), .clear],
                center: UnitPoint(x: -0.1, y: light ? 1.05 : 1.0),
                startRadius: 0,
                endRadius: light ? 560 : 520
            )
        }
        .accessibilityHidden(true)
    }
}

public enum FamiliarGradient {
    /// Von der hellen Lichtkante oben zur feinen Linie unten.
    public static let edge = LinearGradient(
        colors: [FamiliarColor.lightEdge, FamiliarColor.hairline],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Zurückhaltende chromatische Reflexe (warm → rosé → kühl → warm).
    public static let pearl = AngularGradient(
        colors: [
            Color(red: 1.0, green: 0.86, blue: 0.70).opacity(0.55),
            Color(red: 1.0, green: 0.78, blue: 0.86).opacity(0.30),
            Color(red: 0.78, green: 0.88, blue: 1.0).opacity(0.35),
            Color(red: 1.0, green: 0.95, blue: 0.85).opacity(0.15),
            Color(red: 1.0, green: 0.86, blue: 0.70).opacity(0.55),
        ],
        center: .center
    )
}

private struct FamiliarCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let padding: CGFloat
    let isPressed: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill).shadow(color: FamiliarColor.cardShadow, radius: 9, y: 6))
            .overlay(shape.strokeBorder(FamiliarGradient.edge, lineWidth: 1))
            .contentShape(shape)
    }

    /// Glas-Verlauf von oben nach unten (im Dunkeln gleichmäßig, im Hellen unten durchscheinender).
    private var fill: LinearGradient {
        let colors: [Color] = switch (reduceTransparency, isPressed) {
        case (true, false): [FamiliarColor.card]
        case (true, true): [FamiliarColor.cardPressed]
        case (false, false): [FamiliarColor.cardGlass, FamiliarColor.cardGlassLow]
        case (false, true): [FamiliarColor.cardGlassPressed]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// Button-Stil für antippbare Cards: etwas hellere Fläche und minimales Einsinken beim Drücken.
public struct FamiliarCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .familiarCard(isPressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(FamiliarMotion.animation(FamiliarMotion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FamiliarCardButtonStyle {
    public static var familiarCard: FamiliarCardButtonStyle { FamiliarCardButtonStyle() }
}
