import Foundation

/// Wann Familiar um eine Bewertung im App Store bittet: nach einem Erfolgsmoment, selten und nie aufdringlich.
///
/// Regeln: mindestens 10 erledigte Aufgaben insgesamt, die App ist mindestens 3 Tage in Benutzung,
/// seit der letzten Bitte sind mindestens 120 Tage vergangen, und je App-Version höchstens einmal.
/// Das System (`requestReview`) zeigt die Abfrage ohnehin höchstens dreimal pro Jahr.
/// Es werden nur Zähler und Zeitpunkte lokal auf dem Gerät gespeichert, nichts wird übertragen.
struct ReviewPrompt {
    static let minimumCompletions = 10
    static let minimumDaysInUse = 3
    static let minimumDaysBetweenPrompts = 120

    private let defaults: UserDefaults
    private let now: () -> Date

    private enum Key {
        static let completions = "review.completions"
        static let firstUse = "review.firstUse"
        static let lastPrompt = "review.lastPrompt"
        static let lastVersion = "review.lastVersion"
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
    }

    /// Beim ersten Start merken, ab wann die App in Benutzung ist.
    func noteLaunch() {
        if defaults.object(forKey: Key.firstUse) == nil { defaults.set(now(), forKey: Key.firstUse) }
    }

    /// Nach einer erfolgreich erledigten Aufgabe aufrufen; `true`, wenn jetzt gefragt werden soll.
    func recordCompletionShouldAsk(version: String) -> Bool {
        noteLaunch()
        let count = defaults.integer(forKey: Key.completions) + 1
        defaults.set(count, forKey: Key.completions)
        guard count >= Self.minimumCompletions else { return false }
        guard defaults.string(forKey: Key.lastVersion) != version else { return false }
        if let first = defaults.object(forKey: Key.firstUse) as? Date,
           now().timeIntervalSince(first) < Double(Self.minimumDaysInUse) * 86_400 { return false }
        if let last = defaults.object(forKey: Key.lastPrompt) as? Date,
           now().timeIntervalSince(last) < Double(Self.minimumDaysBetweenPrompts) * 86_400 { return false }
        return true
    }

    /// Nach dem Anfordern aufrufen, damit nicht erneut gefragt wird.
    func markAsked(version: String) {
        defaults.set(now(), forKey: Key.lastPrompt)
        defaults.set(version, forKey: Key.lastVersion)
    }
}
