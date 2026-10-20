import SwiftUI

/// Leuchtende Bernstein-Kugel als ruhiges Markenelement für Leerzustände und Onboarding.
/// Statisch gerendert (Verläufe und ein weicher Schatten), keine Animation.
public struct FamiliarOrb: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let diameter: CGFloat

    public init(diameter: CGFloat = 72) {
        self.diameter = diameter
    }

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.82, blue: 0.56),
                        Color(red: 1.0, green: 0.55, blue: 0.26),
                        Color(red: 0.86, green: 0.27, blue: 0.09),
                    ],
                    center: UnitPoint(x: 0.38, y: 0.3),
                    startRadius: 0,
                    endRadius: diameter * 0.62
                )
            )
            .overlay(
                Ellipse()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: diameter * 0.34, height: diameter * 0.18)
                    .offset(x: -diameter * 0.12, y: -diameter * 0.26)
                    .blendMode(.screen)
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: FamiliarColor.glowWarm.opacity(reduceTransparency ? 0.2 : 0.55), radius: diameter * 0.45)
            .accessibilityHidden(true)
    }
}
