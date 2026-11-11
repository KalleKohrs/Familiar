import AppIntents
import FamiliarCore
import SwiftUI
import WidgetKit

/// Steuerelemente für Kontrollzentrum, Sperrbildschirm-Tasten und Action-Button (iOS „Controls“).
/// Sie lesen wie die Widgets nur den Schnappschuss aus dem App-Group-Container – kein Konto, kein Netz.
struct NewTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.newTask) {
            ControlWidgetButton(action: OpenNewTaskIntent()) {
                Label("Neue Aufgabe", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Neue Aufgabe")
        .description("Öffnet Familiar direkt mit einer neuen Aufgabe.")
    }
}

/// Zeigt, wie viele Aufgaben heute für dich offen sind (nur Anzahl, keine Titel).
struct OpenTodayControl: ControlWidget {
    struct Provider: ControlValueProvider {
        /// `nil`: noch keine Daten (nicht angemeldet) – dann zeigt das Steuerelement nur „Familiar“.
        var previewValue: Int? { 3 }

        func currentValue() async throws -> Int? {
            guard let snapshot = WidgetSnapshotStore.read() else { return nil }
            return WidgetRules.today(snapshot, onlyMine: true).count
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.openToday, provider: Provider()) { count in
            ControlWidgetButton(action: OpenTodayIntent()) {
                Label(OpenTodayControl.title(count), systemImage: count == 0 ? "checkmark.circle" : "checklist")
            }
        }
        .displayName("Heute offen")
        .description("Zeigt, wie viele Aufgaben heute für dich offen sind, und öffnet Familiar.")
    }

    static func title(_ count: Int?) -> LocalizedStringResource {
        switch count {
        case nil: "Familiar"
        case 0?: "Alles erledigt"
        case 1?: "1 Aufgabe offen"
        case let n?: "\(n) Aufgaben offen"
        }
    }
}
