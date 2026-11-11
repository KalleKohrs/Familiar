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

    /// Maße der System-Leiste ab iOS 26, im Simulator an einer echten `TabView` gemessen (Debug-Aufbau
    /// `-FamiliarSystemTabBarReference`, iPhone 17, 402 pt breit, Pixel ÷ 3):
    /// Pille 62 pt hoch, 21 pt zur Unterkante, Auswahlkapsel **rundum exakt 4 pt** eingerückt (also
    /// 54 pt hoch und an den runden Enden konzentrisch), Beschriftung 10 pt halbfett, Symbol 23 pt.
    /// 20 pt Seitenrand wie bei Apples Leiste mit fünf Bereichen (App-Store-Bild).
    static let barHeight: CGFloat = 62
    static let edgeInset: CGFloat = 20
    static let bottomInset: CGFloat = 21
    /// Abstand der Auswahlkapsel zum Rand der Pille – an allen vier Seiten gleich.
    static let selectionInset: CGFloat = 4
    private static let symbolSize: CGFloat = 23
    /// Luft zwischen dem Ende einer Liste und der Leiste (Token statt Einzelwert in `RootTabView`).
    static let listClearance: CGFloat = FamiliarSpacing.m
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
        .padding(Self.selectionInset)
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
                    .font(.system(size: Self.symbolSize, weight: .medium))
                    .frame(height: 26)
                    .accessibilityHidden(true)
                TabLabel(title: tab.title)
            }
            .foregroundStyle(isSelected ? FamiliarColor.accent : FamiliarColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: barHeight - 2 * Self.selectionInset)
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

    /// Kapsel hinter dem aktiven Bereich (wie die System-Leiste, z. B. App Store: im Dunkeln dunkel,
    /// im Hellen zart abgedunkelt); gleitet mit, bei „Bewegung reduzieren“ nur Überblendung.
    @ViewBuilder
    private var selectionIndicator: some View {
        let capsule = Capsule()
            .fill(FamiliarColor.selection)
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
        .glassEffect(.regular.tint(FamiliarColor.accentFill).interactive(), in: .circle)
        .accessibilityLabel("Neue Aufgabe")
        .accessibilityIdentifier("createTask")
        .accessibilityShowsLargeContentViewer {
            Label("Neue Aufgabe", systemImage: "plus")
        }
    }
}

/// Beschriftung eines Bereichs: 10 pt wie die System-Leiste, wächst mit der Schriftgröße. Eigene Ansicht, damit
/// `ScaledMetric` die begrenzte Schriftgröße der Leiste (`dynamicTypeSize(...xLarge)`) sieht und nicht die
/// ungebremste – sonst würden die Namen bei den größten Stufen abgeschnitten.
private struct TabLabel: View {
    let title: String
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 10

    var body: some View {
        Text(title)
            .font(.system(size: size, weight: .semibold))
            .lineLimit(1)
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
