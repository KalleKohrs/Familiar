import FamiliarDesign
import SwiftUI

/// Schwebende Hauptnavigation: Liquid-Glass-Pille mit den drei Bereichen und rechts daneben
/// ein abgesetzter, orange getönter Glas-Button „Neue Aufgabe“.
///
/// Eigene Leiste statt `TabRole.prominent`, weil das Plus eine Aktion ist und laut Apple HIG
/// eine Tab-Bar nur der Navigation dient (ADR 0006).
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onCreateTask: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    /// Maße wie die System-Leiste ab iOS 26 (im Simulator an der Fotos-App gemessen).
    static let barHeight: CGFloat = 62
    static let edgeInset: CGFloat = 21
    private var barHeight: CGFloat { Self.barHeight }

    var body: some View {
        GlassEffectContainer(spacing: FamiliarSpacing.s) {
            HStack(spacing: FamiliarSpacing.s) {
                tabPill
                createButton
            }
        }
        .padding(.horizontal, Self.edgeInset)
        // Wie die System-Tab-Bar: Beschriftungen wachsen nur begrenzt mit,
        // bei großen Schriftgrößen hilft der Large Content Viewer (lange drücken).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var tabPill: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(FamiliarSpacing.xxs)
        .frame(minHeight: barHeight)
        .glassEffect(.regular, in: .capsule)
        // Bewusst ohne `.isTabBar`-Container: Damit legt SwiftUI Symbol und Text jedes Bereichs
        // zusätzlich als eigene Buttons offen (UI-Test `testEachTabIsASingleAccessibilityElement`).
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(FamiliarMotion.animation(FamiliarMotion.snappy, reduceMotion: reduceMotion)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .frame(height: 26)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? FamiliarColor.accent : FamiliarColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: barHeight - 2 * FamiliarSpacing.xxs)
            .background {
                if isSelected {
                    selectionIndicator
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tab.\(tab)")
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.systemImage)
        }
    }

    /// Dunkle Kapsel hinter dem aktiven Bereich (wie die System-Leiste im dunklen Erscheinungsbild,
    /// z. B. App Store); gleitet mit, bei „Bewegung reduzieren“ nur Überblendung.
    @ViewBuilder
    private var selectionIndicator: some View {
        let capsule = Capsule()
            .fill(Color.black.opacity(0.32))
            .overlay(Capsule().strokeBorder(FamiliarColor.hairline, lineWidth: 0.5))
        if reduceMotion {
            capsule.transition(.opacity)
        } else {
            capsule.matchedGeometryEffect(id: "selection", in: selectionNamespace)
        }
    }

    private var createButton: some View {
        Button(action: onCreateTask) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FamiliarColor.onAccent)
                .frame(width: barHeight, height: barHeight)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(FamiliarColor.accent).interactive(), in: .circle)
        .accessibilityLabel("Neue Aufgabe")
        .accessibilityIdentifier("createTask")
        .accessibilityShowsLargeContentViewer {
            Label("Neue Aufgabe", systemImage: "plus")
        }
    }
}

#Preview {
    @Previewable @State var selection = AppTab.tasks
    VStack {
        Spacer()
        FloatingTabBar(selection: $selection) {}
    }
    .familiarScreenBackground()
    .preferredColorScheme(.dark)
}
