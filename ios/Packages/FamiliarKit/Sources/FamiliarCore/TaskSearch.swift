import Foundation

/// Suche in Aufgaben und Verlauf (UI-frei, damit sie getestet werden kann).
///
/// Regeln:
/// - Groß-/Kleinschreibung und Akzente zählen nicht: „mull“ und „MÜLL“ finden „Müll“ („muell“ nicht);
///   „ß“ zählt wie „ss“.
/// - Mehrere Wörter: Jedes Wort muss irgendwo vorkommen (Titel, Beschreibung oder Personenname), in beliebiger
///   Reihenfolge – „müll anna“ findet „Müll rausbringen“, wenn Anna zugewiesen ist.
/// - Ein Wort passt, wenn es irgendwo in einem Feld enthalten ist („rausb“ findet „rausbringen“).
/// - Leere oder nur aus Leerzeichen bestehende Eingabe filtert nichts.
public enum TaskSearch {
    /// Name einer Person in einer Familie, so wie die App ihn anzeigt (siehe `SessionStore.displayName`).
    public typealias NameResolver = (_ userID: UUID, _ familyID: UUID) -> String

    /// Vereinheitlicht Text für den Vergleich: klein, ohne Akzente, ohne Breitenvarianten.
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "de_DE"))
    }

    /// Suchwörter aus der Eingabe (vereinheitlicht, ohne Leerstellen).
    public static func terms(_ query: String) -> [String] {
        normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Gibt es überhaupt etwas zu suchen?
    public static func isActive(_ query: String) -> Bool {
        !terms(query).isEmpty
    }

    // MARK: Aufgaben (Startseite)

    /// Behält die Aufgaben, die zur Suche passen; Reihenfolge bleibt erhalten.
    public static func filter(_ tasks: [TaskItem], query: String, nameOf: NameResolver) -> [TaskItem] {
        let terms = terms(query)
        guard !terms.isEmpty else { return tasks }
        return tasks.filter { matches(fields(of: $0, nameOf: nameOf), terms: terms) }
    }

    // MARK: Verlauf

    /// Behält die Verlaufseinträge, die zur Suche passen. Bei Aufgaben zählt zusätzlich, wer sie erledigt
    /// bzw. gelöscht hat; bei gelöschten Serien der Serientitel und die beteiligten Personen.
    public static func filter(_ entries: [HistoryEntry], query: String, nameOf: NameResolver) -> [HistoryEntry] {
        let terms = terms(query)
        guard !terms.isEmpty else { return entries }
        return entries.filter { entry in
            switch entry {
            case .task(let task):
                var fields = fields(of: task, nameOf: nameOf)
                if let actor = HistoryRules.actor(of: task) {
                    fields.append(nameOf(actor, task.familyID))
                }
                return matches(fields, terms: terms)
            case .seriesDeletion(let deletion):
                var fields: [String] = []
                if let title = deletion.series?.title { fields.append(title) }
                var people = deletion.series?.assigneeOrder ?? []
                if let actor = deletion.deletedBy { people.append(actor) }
                fields += people.map { nameOf($0, deletion.familyID) }
                return matches(fields, terms: terms)
            }
        }
    }

    // MARK: Hilfen

    private static func fields(of task: TaskItem, nameOf: NameResolver) -> [String] {
        var fields = [task.title]
        if let description = task.description { fields.append(description) }
        fields += task.assignees.map { nameOf($0.userID, task.familyID) }
        return fields
    }

    private static func matches(_ fields: [String], terms: [String]) -> Bool {
        let haystack = fields.map(normalized)
        return terms.allSatisfy { term in haystack.contains { $0.contains(term) } }
    }
}
