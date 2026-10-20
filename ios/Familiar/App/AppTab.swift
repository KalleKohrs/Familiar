import Foundation

/// Bereiche der unteren Navigation (Reihenfolge wie in der Leiste).
///
/// „Neue Aufgabe“ ist bewusst kein Bereich, sondern eine Aktion (eigener Button neben der Leiste).
enum AppTab: Hashable, CaseIterable, Identifiable {
    case tasks
    case calendar
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .tasks: String(localized: "Aufgaben")
        case .calendar: String(localized: "Kalender")
        case .history: String(localized: "Verlauf")
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .history: "clock.arrow.circlepath"
        }
    }
}
