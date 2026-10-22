import FamiliarCore
import SwiftUI

/// Übersicht aller Tokens und Komponenten – Referenz für die Ausrichtung aller Screens.
/// Wird in Debug-Builds aus der App heraus geöffnet und dient als Xcode-Preview.
public struct DesignGalleryView: View {
    @State private var demoDone = false
    @State private var demoText = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.xl) {
                brandSection
                colorSection
                familySection
                typographySection
                cardSection
                avatarSection
                controlSection
                stateSection
            }
            .padding(.horizontal, FamiliarSpacing.m)
            .padding(.bottom, FamiliarSpacing.xxl)
        }
        .familiarScreenBackground()
        .navigationTitle("Design-System")
    }

    // MARK: Abschnitte

    private var brandSection: some View {
        VStack(spacing: FamiliarSpacing.m) {
            FamiliarMark(size: 76)
                .padding(.top, FamiliarSpacing.l)
            Text("Familiar")
                .font(FamiliarFont.display)
                .foregroundStyle(FamiliarColor.textPrimary)
            Text("Ruhig, warm, klar – Fluid Ambient")
                .font(FamiliarFont.secondary)
                .foregroundStyle(FamiliarColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Farben")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: FamiliarSpacing.s)], spacing: FamiliarSpacing.s) {
                swatch("canvas", FamiliarColor.canvas)
                swatch("elevated", FamiliarColor.elevated)
                swatch("card", FamiliarColor.card)
                swatch("cardGlass", FamiliarColor.cardGlass)
                swatch("sunken", FamiliarColor.sunken)
                swatch("textPrimary", FamiliarColor.textPrimary)
                swatch("textSecondary", FamiliarColor.textSecondary)
                swatch("textTertiary", FamiliarColor.textTertiary)
                swatch("accent", FamiliarColor.accent)
                swatch("accentFill", FamiliarColor.accentFill)
                swatch("success", FamiliarColor.success)
                swatch("warning", FamiliarColor.warning)
                swatch("danger", FamiliarColor.danger)
                swatch("hairline", FamiliarColor.hairline)
            }
        }
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Familienfarben")
            FlowRow {
                ForEach(FamilyPalette.presets) { preset in
                    FamilyBadge(name: preset.name, color: Color(preset.rgb))
                }
            }
            Text("Gleiche Farbe in zwei Familien → lokale Anzeige-Variation:")
                .font(FamiliarFont.meta)
                .foregroundStyle(FamiliarColor.textSecondary)
            let resolved = FamilyColorResolver.displayColors(for: [
                FamilyColorInput(familyID: "a", color: RGBColor(hex: 0xFF7F66)),
                FamilyColorInput(familyID: "b", color: RGBColor(hex: 0xFF7F66)),
            ])
            HStack {
                FamilyBadge(name: "Familie A", color: Color(resolved["a"] ?? RGBColor(hex: 0xFF7F66)))
                FamilyBadge(name: "Familie B", color: Color(resolved["b"] ?? RGBColor(hex: 0xFF7F66)))
            }
        }
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
            FamiliarSectionHeader("Typografie")
            Text("Display – Aufgaben").font(FamiliarFont.display)
            Text("Titel – Neue Aufgabe").font(FamiliarFont.title)
            Text("Card-Titel – Müll rausbringen").font(FamiliarFont.cardTitle)
            Text("Fließtext – Bitte vor 19 Uhr an die Straße stellen.").font(FamiliarFont.body)
            Text("Sekundär – Beschreibung und Hinweise").font(FamiliarFont.secondary)
                .foregroundStyle(FamiliarColor.textSecondary)
            Text("Meta – Erstellt von Anna").font(FamiliarFont.meta)
                .foregroundStyle(FamiliarColor.textSecondary)
            Text("Zeit – 18:30").font(FamiliarFont.time)
                .foregroundStyle(FamiliarColor.textSecondary)
        }
        .foregroundStyle(FamiliarColor.textPrimary)
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Aufgaben-Card (Beispiel)")
            Button {} label: {
                HStack(alignment: .top, spacing: FamiliarSpacing.s) {
                    CompletionCheckButton(isDone: demoDone) { demoDone.toggle() }
                        .padding(.leading, -FamiliarSpacing.xs)
                        .padding(.top, -FamiliarSpacing.xs)
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
                        HStack {
                            FamilyBadge(name: "Familie Berg", color: Color(FamilyPalette.presets[3].rgb))
                            Spacer()
                            FamiliarTag("Heute 18:30", systemImage: "clock")
                        }
                        Text("Müll rausbringen")
                            .font(FamiliarFont.cardTitle)
                            .foregroundStyle(FamiliarColor.textPrimary)
                        Text("Gelbe Tonne und Papier, bitte vor 19 Uhr.")
                            .font(FamiliarFont.secondary)
                            .foregroundStyle(FamiliarColor.textSecondary)
                            .lineLimit(2)
                        AvatarStack(people: [
                            .init(id: "1", name: "Anna Berg", completion: demoDone ? .done : .open),
                            .init(id: "2", name: "Ben Berg", completion: .done),
                            .init(id: "3", name: "Clara Berg", completion: .open),
                        ])
                    }
                    RoundedRectangle(cornerRadius: FamiliarRadius.chip, style: .continuous)
                        .fill(FamiliarColor.elevated)
                        .frame(width: 56, height: 56)
                        .overlay(Image(systemName: "photo").foregroundStyle(FamiliarColor.textTertiary))
                        .accessibilityLabel("Bild-Miniatur")
                }
            }
            .buttonStyle(.familiarCard)

            FamiliarTag("Überfällig seit gestern", systemImage: "exclamationmark.circle", tone: .danger)
        }
    }

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Avatare: offen vs. erledigt")
            HStack(spacing: FamiliarSpacing.m) {
                AvatarView(name: "Anna Berg", diameter: 44, completion: .open)
                AvatarView(name: "Ben Berg", diameter: 44, completion: .done)
                AvatarView(name: "Clara", diameter: 44)
                AvatarStack(people: (1...6).map { .init(id: "\($0)", name: "Person \($0)", completion: $0 < 3 ? .done : .open) })
            }
        }
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Buttons und Tags")
            Button("Aufgabe anlegen") {}.buttonStyle(.familiarPrimary)
            Button("Abbrechen") {}.buttonStyle(.familiarSecondary)
            Button("Aufgabe löschen") {}.buttonStyle(.familiarDestructive)
            Button("Deaktiviert") {}.buttonStyle(.familiarPrimary).disabled(true)
            TextField("E-Mail-Adresse", text: $demoText)
                .familiarInputField()
            FamiliarInlineError("Der Code ist falsch oder abgelaufen.")
            FlowRow {
                FamiliarTag("Ohne Datum")
                FamiliarTag("Mo, 3. Nov · 08:00", systemImage: "calendar", tone: .accent)
                FamiliarTag("Erledigt", systemImage: "checkmark", tone: .success)
                FamiliarTag("Wiederholt sich", systemImage: "repeat", tone: .warning)
            }
        }
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Zustände")
            FamiliarSkeleton()
            FamiliarEmptyState(
                systemImage: "checklist",
                title: "Alles erledigt",
                message: "Neue Aufgaben legst du über das Plus an.",
                actionTitle: "Aufgabe anlegen",
                action: {}
            )
            .familiarCard()
            FamiliarErrorState(message: "Die Aufgaben konnten nicht geladen werden.") {}
                .familiarCard()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
            RoundedRectangle(cornerRadius: FamiliarRadius.chip, style: .continuous)
                .fill(color)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: FamiliarRadius.chip, style: .continuous).strokeBorder(FamiliarColor.hairline))
            Text(name)
                .font(FamiliarFont.caption)
                .foregroundStyle(FamiliarColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { DesignGalleryView() }
        .preferredColorScheme(.dark)
}
