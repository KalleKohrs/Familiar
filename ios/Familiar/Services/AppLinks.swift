import Foundation

/// Adressen, die die App selbst nach außen gibt (Weiterempfehlen, Bewerten).
enum AppLinks {
    /// Leitet im Browser in den App Store weiter (`website/_redirects`); bleibt gültig, auch wenn sich die Store-Adresse ändert.
    static let share = URL(string: "https://familiar-app.de/app")!
    /// Öffnet im App Store direkt das Bewertungsfeld (Apple: „Requesting App Store reviews“, `action=write-review`).
    static let writeReview = URL(string: "https://apps.apple.com/de/app/id6828540894?action=write-review")!
}
