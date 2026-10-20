import Foundation

/// Reihenfolge nach der Anmeldung (Plan, Abschnitt 6): Profil → Familie → App.
/// Die Mitteilungs-Erklärung kommt mit Phase 7 dazu.
public enum OnboardingStep: Hashable, Sendable {
    case profile
    case family
    case done
}

public enum OnboardingFlow {
    /// - Parameters:
    ///   - hasFamily: Mitglied in mindestens einer Familie.
    ///   - profileConfirmed: Name/Bild wurden auf diesem Gerät bestätigt.
    /// Wer schon in einer Familie ist, hat das Onboarding früher abgeschlossen und kommt direkt in die App.
    public static func nextStep(hasFamily: Bool, profileConfirmed: Bool) -> OnboardingStep {
        if hasFamily { return .done }
        return profileConfirmed ? .family : .profile
    }
}
