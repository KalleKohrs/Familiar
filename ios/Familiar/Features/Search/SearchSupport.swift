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

/// Scroll-Ansicht mit eingebautem Suchfeld, das **oberhalb** des Inhalts liegt und beim Start verborgen ist:
/// Herunterziehen der Liste (oder die Lupe in der Leiste) holt es hervor, wie bei Apples Listen.
///
/// Das Feld ist Teil des Inhalts und hat eine feste Höhe. Die System-Suchleiste (`searchable`) hing
/// dagegen in der Navigationsleiste: Sie war immer sichtbar und sprang beim Wechsel des Bereichs verspätet
/// ein, wodurch der ganze Inhalt um ihre Höhe nach unten rutschte.
///
/// Der Suchtext wird beim Verlassen des Bereichs geleert: Ein vergessener Filter würde Aufgaben verstecken –
/// in einem Familienplaner das größere Übel. Beim Öffnen einer Aufgabe und Zurückkehren bleibt die Suche stehen.
struct SearchRevealScrollView<Content: View>: View {
    @Binding var text: String
    let tab: AppTab
    let resultCount: Int
    let prompt: LocalizedStringKey
    @ViewBuilder let content: Content

    @Environment(\.tabSelection) private var tabSelection
    @Environment(\.floatingTabBarHeight) private var bottomClearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(y: 0)
    @State private var slot: CGFloat = 56
    @State private var viewportHeight: CGFloat = 0
    @State private var topInset: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @FocusState private var isFocused: Bool

    private var isSearching: Bool { TaskSearch.isActive(text) }

    private var fieldOpacity: Double {
        if isFocused || isSearching { return 1 }
        return 1 - min(1, max(0, Double(offsetY / max(slot * 0.7, 1))))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SearchField(text: $text, isFocused: $isFocused, prompt: prompt, onCancel: cancel)
                    .padding(.horizontal, FamiliarSpacing.m)
                    .padding(.top, FamiliarSpacing.xs)
                    .padding(.bottom, FamiliarSpacing.xs)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { slot = $0 }
                    // Beim Wegscrollen ausblenden, damit es nicht unter der Leiste durchschimmert; ausgeblendet
                    // ist es auch für VoiceOver verborgen (die Lupe holt es hervor).
                    .opacity(fieldOpacity)
                    .allowsHitTesting(fieldOpacity > 0.5)
                    .accessibilityHidden(fieldOpacity < 0.05)
                content
            }
            // Mindesthöhe, damit sich das Feld auch bei kurzen Listen wegscrollen lässt.
            .frame(minHeight: max(0, viewportHeight - topInset - bottomClearance) + slot, alignment: .top)
        }
        .scrollPosition($position)
        .scrollTargetBehavior(SearchRevealSnap(slot: slot))
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGSize.self) { CGSize(width: $0.safeAreaInsets.top, height: $0.size.height) } action: {
            topInset = $0.width
            viewportHeight = $0.height
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in
            offsetY = new
        }
        // Sobald die Höhen bekannt sind, das Feld verbergen. Mehrere Versuche, weil sich der Inhalt beim
        // Start noch ändert (Platzhalter, Liste) und ein zu früh gesetzter Versatz zurückgesetzt werden kann.
        .task(id: viewportHeight > 0) { await hideInitially() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: reveal) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Suchen")
                    .accessibilityIdentifier("search.open")
            }
        }
        .onChange(of: tabSelection) { old, new in
            // Jeder Wechsel des Bereichs leert die Suche und verbirgt das Feld wieder (ohne Bewegung: der
            // Bereich ist gerade nicht zu sehen).
            if new.switches != old.switches, !text.isEmpty || isFocused {
                text = ""
                isFocused = false
                position.scrollTo(y: slot)
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

    private func hideInitially() async {
        guard viewportHeight > 0 else { return }
        for delay in [80, 250, 600] {
            try? await Task.sleep(for: .milliseconds(delay))
            if Task.isCancelled || isFocused || isSearching { return }
            if offsetY < slot - 1 { position.scrollTo(y: slot) }
        }
    }

    /// Lupe: Feld hervorholen und gleich mit dem Tippen beginnen lassen.
    private func reveal() {
        withAnimation(FamiliarMotion.animation(reduceMotion: reduceMotion)) { position.scrollTo(y: 0) }
        isFocused = true
        // Das Feld war eben noch ausgeblendet; nimmt es den Fokus nicht sofort an, erneut anfordern.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if !isFocused { isFocused = true }
        }
    }

    private func cancel() {
        text = ""
        isFocused = false
        withAnimation(FamiliarMotion.animation(reduceMotion: reduceMotion)) { position.scrollTo(y: slot) }
    }
}

/// Lässt das Suchfeld beim Loslassen nie halb sichtbar stehen: entweder ganz da oder ganz weg.
private struct SearchRevealSnap: ScrollTargetBehavior {
    let slot: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let y = target.rect.origin.y
        guard y > 0, y < slot else { return }
        target.rect.origin.y = y < slot / 2 ? 0 : slot
    }
}

/// Das Feld selbst: Lupe, Eingabe, Löschen-Knopf und – solange es aktiv ist – „Abbrechen“.
private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let prompt: LocalizedStringKey
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: FamiliarSpacing.s) {
            HStack(spacing: FamiliarSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .accessibilityHidden(true)
                TextField(prompt, text: $text)
                    .focused(isFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .accessibilityIdentifier("search.field")
                if !text.isEmpty {
                    Button { text = ""; isFocused.wrappedValue = true } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .frame(minWidth: 28, minHeight: FamiliarSize.minimumTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suche leeren")
                    .accessibilityIdentifier("search.clear")
                }
            }
            .padding(.horizontal, FamiliarSpacing.s)
            .frame(minHeight: FamiliarSize.minimumTouchTarget)
            .background(RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous).fill(FamiliarColor.card))
            .overlay(RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous)
                .strokeBorder(FamiliarColor.hairline, lineWidth: 1))
            if isFocused.wrappedValue || !text.isEmpty {
                Button("Abbrechen", action: onCancel)
                    .foregroundStyle(FamiliarColor.accent)
                    .accessibilityIdentifier("search.cancel")
                    .transition(.opacity)
            }
        }
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
