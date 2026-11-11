import SwiftUI

/// Bewegungs-Tokens – das Regelwerk steht in `docs/design/motion.md`.
///
/// Alle Federn sind über **Dauer und Bounce** beschrieben (WWDC23 „Animate with springs“), nicht über
/// Masse/Steifigkeit: Die Dauer ist vorhersagbar, `bounce 0` = glatt ohne Überschwingen. Federn nehmen
/// die Geschwindigkeit einer laufenden Bewegung mit, wenn sie umgelenkt werden – deshalb nie
/// `easeInOut` & Co. für Dinge, die der Finger anstößt oder unterbricht.
///
/// Bei „Bewegung reduzieren“ gibt es nur kurze Überblendungen ohne Positions- oder Größenänderung.
public enum FamiliarMotion {
    // MARK: Federn (Bewegung)

    /// Standard für Layoutänderungen: Karten rücken nach, Bereiche klappen auf, Zustände wechseln.
    /// Glatt, ohne Überschwingen (Listen sollen nicht nachwippen).
    public static let standard = Animation.smooth(duration: 0.4)

    /// Kleine, direkte Rückmeldung: Drücken, Auswahlkapsel, Schalter, Haken.
    /// Minimal federnd (Bounce 0,15) und kurz – reagiert sofort.
    public static let snappy = Animation.snappy(duration: 0.3)

    /// Während ein Finger etwas zieht: folgt ohne Verzögerung und lenkt laufende Federn um.
    public static let interactive = Animation.interactiveSpring(response: 0.15, dampingFraction: 0.86)

    // MARK: Überblendungen (kein Weg, nur Deckkraft)

    /// Inhalt tritt an die Stelle von Platzhalter, Leerzustand oder anderem Inhalt.
    /// Ohne Verzögerung: Wer wartet, bekommt sofort die erste Veränderung zu sehen.
    public static let fade = Animation.easeOut(duration: 0.25)

    /// Ersatz für jede Bewegung bei „Bewegung reduzieren“ (und „Querblenden bevorzugen“).
    public static let reduced = Animation.easeInOut(duration: 0.2)

    // MARK: Zeiten (Staffelung, Haltezeiten)

    /// Obergrenze für jede Reaktion auf eine Eingabe (Sekunden). Länger wirkt träge.
    public static let maximumDuration: TimeInterval = 0.5

    /// Abhaken: So lange bleibt der Haken sichtbar, bevor die Karte ausblendet (Rückmeldung, dann Wirkung).
    public static let checkHold: Duration = .milliseconds(350)

    /// Dauer des Ausblendens einer erledigten Karte (muss zu `leave` passen).
    public static let leaveDuration: TimeInterval = 0.22

    /// Ausblenden einer Karte, bevor sie aus der Liste fällt.
    public static let leave = Animation.easeOut(duration: leaveDuration)

    // MARK: Helfer

    /// Die Animation – oder bei „Bewegung reduzieren“ die kurze Überblendung.
    public static func animation(_ base: Animation = standard, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : base
    }

    /// Übergang für erscheinende Elemente (Banner, Hinweise): weiches Skalieren oder reine Überblendung.
    public static func appearTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    /// Übergang für Inhalte, die Platzhalter/Leerzustand/anderen Inhalt ersetzen: immer nur Überblendung.
    public static var contentTransition: AnyTransition { .opacity }
}

extension View {
    /// Animiert Änderungen von `value` mit einer Familiar-Feder und respektiert „Bewegung reduzieren“.
    public func familiarAnimation<Value: Equatable>(
        _ base: Animation = FamiliarMotion.standard,
        value: Value
    ) -> some View {
        modifier(FamiliarAnimationModifier(base: base, value: value))
    }

    /// Wechsel zwischen Ladezustand, Leerzustand und Inhalt: reine Überblendung, gesteuert von **einem**
    /// Zustandswert des umgebenden Bereichs – nie von `onAppear` einzelner Elemente (das erzeugt
    /// Verzögerungen und lässt Dinge beim Tabwechsel erneut einblenden).
    public func familiarContentSwap<Value: Equatable>(value: Value) -> some View {
        modifier(FamiliarAnimationModifier(base: FamiliarMotion.fade, value: value, alwaysFade: true))
    }
}

private struct FamiliarAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let base: Animation
    let value: Value
    var alwaysFade = false

    func body(content: Content) -> some View {
        // Überblendungen sind bei „Bewegung reduzieren“ erlaubt (und gewollt) – nur kürzer/ruhiger.
        content.animation(alwaysFade ? base : FamiliarMotion.animation(base, reduceMotion: reduceMotion), value: value)
    }
}
