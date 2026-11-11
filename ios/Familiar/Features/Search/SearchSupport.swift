import FamiliarCore
import FamiliarDesign
import SwiftUI

// Gemeinsame Bausteine der Suche in „Aufgaben“ und „Verlauf“. Die Filterregeln selbst stehen
// UI-frei in `FamiliarCore/TaskSearch.swift`.

/// Welcher Bereich der Tab-Leiste sichtbar ist und wie oft gewechselt wurde (gesetzt in `RootTabView`).
/// Der Zähler macht auch ein schnelles Hin-und-zurück erkennbar, bei dem die Auswahl am Ende gleich aussieht.
struct TabSelection: Equatable {
    var tab: AppTab = .tasks
    var switches = 0
}

extension EnvironmentValues {
    @Entry var tabSelection = TabSelection()
}

extension SessionStore {
    /// Namen so, wie die App sie anzeigt – für die Personensuche.
    var searchNames: TaskSearch.NameResolver {
        { [self] userID, familyID in displayName(of: userID, in: familyID) }
    }
}

extension View {
    /// Suchfeld für einen Bereich: Lupe in der Leiste (und Herunterziehen der Liste), Eingabe wird beim
    /// Verlassen des Bereichs geleert, und VoiceOver hört nach einer kurzen Pause die Trefferzahl.
    ///
    /// Warum zurücksetzen? Ein vergessener Filter würde Aufgaben verstecken – in einem Familienplaner
    /// das größere Übel. Beim Öffnen einer Aufgabe und Zurückkehren bleibt die Suche dagegen stehen.
    func familiarSearch(text: Binding<String>, tab: AppTab, resultCount: Int, prompt: LocalizedStringKey) -> some View {
        modifier(FamiliarSearchModifier(text: text, tab: tab, resultCount: resultCount, prompt: prompt))
    }
}

private struct FamiliarSearchModifier: ViewModifier {
    @Binding var text: String
    let tab: AppTab
    let resultCount: Int
    let prompt: LocalizedStringKey
    @Environment(\.tabSelection) private var tabSelection
    @State private var isPresented = false
    @State private var dismissToken = 0
    @State private var closeOnReturn = false

    private var isSearching: Bool { TaskSearch.isActive(text) }

    func body(content: Content) -> some View {
        content
            // Muss innerhalb der durchsuchbaren Ansicht liegen, damit `dismissSearch` dort verfügbar ist.
            .background { SearchDismisser(token: dismissToken) }
            .searchable(text: $text, isPresented: $isPresented,
                        placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Suchen")
                        .accessibilityIdentifier("search.open")
                }
            }
            .onChange(of: tabSelection) { old, new in
                // Jeder Wechsel des Bereichs leert die Suche. Das Feld selbst lässt sich erst schließen, wenn der
                // Bereich wieder sichtbar ist (im Hintergrund bleibt es für UIKit „aktiv“).
                if new.switches != old.switches, !text.isEmpty || isPresented {
                    text = ""
                    isPresented = false
                    closeOnReturn = true
                }
                if new.tab == tab, closeOnReturn {
                    closeOnReturn = false
                    dismissToken += 1
                }
            }
            // Trefferzahl ansagen – erst nach einer kurzen Pause, damit das Mitsprechen der Eingabe nicht gestört wird.
            .task(id: isSearching ? resultCount : -1) {
                guard isSearching else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                AccessibilityNotification.Announcement(SearchResultText.count(resultCount)).post()
            }
    }
}

/// Schließt das Suchfeld, sobald sich `token` ändert (`isPresented = false` allein lässt es offen stehen).
private struct SearchDismisser: View {
    @Environment(\.dismissSearch) private var dismissSearch
    let token: Int

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: token) { dismissSearch() }
    }
}

enum SearchResultText {
    static func count(_ count: Int) -> String {
        count == 0 ? String(localized: "Keine Treffer") : String(localized: "\(count) Treffer")
    }
}

/// Kleine Zeile über den Treffern: „3 Treffer“.
struct SearchResultsSummary: View {
    let count: Int

    var body: some View {
        // Bei null Treffern sagt es schon der Leerzustand darunter.
        if count > 0 {
            Text(SearchResultText.count(count))
                .font(FamiliarFont.meta)
                .foregroundStyle(FamiliarColor.textSecondary)
                .padding(.leading, FamiliarSpacing.xxs)
                .accessibilityIdentifier("search.count")
        }
    }
}

/// Leerzustand, wenn nichts zur Suche passt.
struct NoSearchResultsView: View {
    let query: String
    let hint: String

    var body: some View {
        FamiliarEmptyState(
            systemImage: "magnifyingglass",
            title: String(localized: "Keine Treffer für „\(query.trimmingCharacters(in: .whitespacesAndNewlines))“"),
            message: hint
        )
        .padding(.vertical, FamiliarSpacing.xl)
        .accessibilityIdentifier("search.empty")
    }
}
