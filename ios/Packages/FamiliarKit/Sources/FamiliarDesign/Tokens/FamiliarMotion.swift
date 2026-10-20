import SwiftUI

/// Bewegungs-Tokens. Federn statt harter Standardübergänge; bei aktivierter
/// Einstellung „Bewegung reduzieren“ nur kurze Überblendungen ohne Positionsänderung.
public enum FamiliarMotion {
    public static let standard = Animation.spring(response: 0.42, dampingFraction: 0.82)
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    public static let reduced = Animation.easeInOut(duration: 0.2)

    public static func animation(_ base: Animation = standard, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : base
    }

    /// Übergang für erscheinende Elemente: weiches Skalieren oder reine Überblendung.
    public static func appearTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }
}

extension View {
    /// Animiert Änderungen von `value` mit einer Familiar-Feder und respektiert „Bewegung reduzieren“.
    public func familiarAnimation<Value: Equatable>(
        _ base: Animation = FamiliarMotion.standard,
        value: Value
    ) -> some View {
        modifier(FamiliarAnimationModifier(base: base, value: value))
    }
}

private struct FamiliarAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let base: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(FamiliarMotion.animation(base, reduceMotion: reduceMotion), value: value)
    }
}
