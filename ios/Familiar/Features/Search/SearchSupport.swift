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

/// Verlässt man einen Bereich der Tab-Leiste, steht er beim Zurückkommen wieder auf seiner Startseite (nicht mehr in
/// einer geöffneten Aufgabe). Die Ansicht ist beim Wechsel schon verdeckt, man sieht das Zurücksetzen nicht.
private struct PopsToRootOnTabChange: ViewModifier {
    let tab: AppTab
    @Binding var path: [UUID]
    @Environment(\.tabSelection) private var tabSelection

    func body(content: Content) -> some View {
        content.onChange(of: tabSelection.tab) { old, new in
            if old == tab && new != tab && !path.isEmpty { path = [] }
        }
    }
}

extension View {
    func popsToRootOnTabChange(_ tab: AppTab, path: Binding<[UUID]>) -> some View {
        modifier(PopsToRootOnTabChange(tab: tab, path: path))
    }
}

extension SessionStore {
    /// Namen so, wie die App sie anzeigt – für die Personensuche.
    var searchNames: TaskSearch.NameResolver {
        { [self] userID, familyID in displayName(of: userID, in: familyID) }
    }
}

/// Scroll-Ansicht mit eingebautem Suchfeld, das **oberhalb** des Inhalts liegt und beim Start verborgen ist:
/// Herunterziehen der Liste holt es hervor, wie bei Apples Listen (für VoiceOver: Knopf „Suchen“).
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(y: 0)
    @State private var slot: CGFloat = 56
    @State private var viewportHeight: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var scrollPhase: ScrollPhase = .idle
    /// Hat die Person das Feld selbst hervorgeholt (Herunterziehen, Lupe)? Dann bleibt es stehen, bis sie es
    /// wieder wegscrollt oder abbricht. Solange das nicht der Fall ist, hält die Ansicht es verborgen –
    /// jederzeit, nicht nur beim Start (Inhalte laden nach, Größen ändern sich; ein einmaliges Wegscrollen
    /// reichte am echten Gerät nicht).
    @State private var revealedByUser = false
    /// Solange das Feld per Animation ein- oder ausgefahren wird, greift `settle()` nicht ein (es würde die
    /// Animation durch einen sofortigen Sprung ersetzen).
    @State private var isSliding = false
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
                    // Solange das Feld verborgen ist, steht an seiner Stelle für VoiceOver und Sprachsteuerung ein
                    // unsichtbarer „Suchen“-Knopf (sehende Personen ziehen die Liste herunter).
                    .overlay {
                        if fieldOpacity < 0.05 {
                            Button(action: reveal) { Color.clear }
                                .accessibilityLabel("Suchen")
                                .accessibilityIdentifier("search.open")
                        }
                    }
                content
            }
            // Mindesthöhe, damit sich das Feld auch bei kurzen Inhalten wegscrollen lässt. Gemessen (gemessen: bei
            // Inhalt kürzer als der Sichtbereich scrollt SwiftUI gar nicht, auch nicht per `scrollTo`) – maßgeblich
            // ist die vom Scrollbereich gemeldete Höhe, nicht eine Schätzung aus Rändern.
            // Ideale Höhe zuerst: Sonst gibt die Mindesthöhe dem Inhalt eine zu knappe Höhenvorgabe und Texte werden
            // auf eine Zeile gekürzt („…erste Au…“).
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: containerHeight + slot + 1, alignment: .top)
        }
        .scrollPosition($position)
        .scrollTargetBehavior(SearchRevealSnap(slot: slot))
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in
            offsetY = new
            // Vom Finger (oder Auslaufen) bis über die Kante gezogen: gewollt hervorgeholt.
            if (scrollPhase == .interacting || scrollPhase == .decelerating), new < slot - 1 { revealedByUser = true }
            if new >= slot - 1 { revealedByUser = false }
            settle()
        }
        .onScrollPhaseChange { _, new in
            scrollPhase = new
            settle()
        }
        // Verborgen halten, sobald Höhen bekannt sind oder sich ändern.
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, new in
            containerHeight = new
        }
        .onChange(of: viewportHeight) { settle() }
        .onChange(of: slot) { settle() }
        .onChange(of: isSearching) { settle() }
        .task(id: viewportHeight > 0) { await hideInitially() }
        // Kein Such-Symbol in der Leiste (machte die Oberfläche unruhig): Das Feld kommt per Herunterziehen.
        .onChange(of: tabSelection) { old, new in
            // Jeder Wechsel des Bereichs leert die Suche und verbirgt das Feld wieder (ohne Bewegung: der
            // Bereich ist gerade nicht zu sehen).
            if new.switches != old.switches, !text.isEmpty || isFocused {
                revealedByUser = false
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

    /// Das Feld verbergen, wenn niemand es hervorgeholt hat und die Liste ruht (ohne Bewegung: sonst zuckte
    /// der Inhalt beim Start).
    private func settle() {
        guard scrollPhase == .idle, !isSliding, !revealedByUser, !isFocused, !isSearching, viewportHeight > 0 else { return }
        guard offsetY < slot - 1 else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { position.scrollTo(y: slot) }
    }

    /// Zusätzlich in kurzen Abständen nachsehen: Meldet SwiftUI beim Start keine Änderung mehr (Inhalt war
    /// schon fertig, bevor die Größen bekannt waren), käme `settle()` sonst nie zum Zug.
    private func hideInitially() async {
        guard viewportHeight > 0 else { return }
        for delay in [60, 200, 500, 1200] {
            try? await Task.sleep(for: .milliseconds(delay))
            if Task.isCancelled { return }
            settle()
        }
    }

    /// Weiches Ein- und Ausfahren ohne Nachfedern: Ein Überschwingen ließ den ganzen Inhalt kurz mitzucken.
    private var slideAnimation: Animation {
        reduceMotion ? FamiliarMotion.reduced : .smooth(duration: 0.32)
    }

    /// Lupe: Feld hervorholen und gleich mit dem Tippen beginnen lassen.
    private func reveal() {
        revealedByUser = true
        slide { position.scrollTo(y: 0) }
        isFocused = true
        // Das Feld war eben noch ausgeblendet; nimmt es den Fokus nicht sofort an, erneut anfordern.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if !isFocused { isFocused = true }
        }
    }

    private func cancel() {
        revealedByUser = false
        text = ""
        isFocused = false
        slide { position.scrollTo(y: slot) }
    }

    /// Animiert scrollen und `settle()` bis kurz nach dem Ende heraushalten.
    private func slide(_ scroll: () -> Void) {
        isSliding = true
        withAnimation(slideAnimation) { scroll() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            isSliding = false
            settle()
        }
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
