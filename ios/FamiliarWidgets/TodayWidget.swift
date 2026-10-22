import AppIntents
import FamiliarActivity
import FamiliarCore
import FamiliarDesign
import SwiftUI
import WidgetKit

/// Widgets „Heute“ für Homescreen und Sperrbildschirm (ADR 0010). Liest nur den Schnappschuss der App
/// aus dem App-Group-Container; Abhaken läuft über `CompleteTaskIntent` im Prozess der App.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FamiliarToday", intent: TodayWidgetConfiguration.self,
                               provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { FamiliarAmbientBackground() }
        }
        .configurationDisplayName("Heute")
        .description("Was heute ansteht – direkt abhaken.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: Einstellungen

struct TodayWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Heute"
    static let description = IntentDescription("Zeigt, was heute ansteht.")

    @Parameter(title: "Nur meine Aufgaben", default: true)
    var onlyMine: Bool

    @Parameter(title: "Familie")
    var family: WidgetFamilyEntity?
}

struct WidgetFamilyEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Familie"
    static let defaultQuery = WidgetFamilyQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetFamilyQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetFamilyEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetFamilyEntity] { all() }

    private func all() -> [WidgetFamilyEntity] {
        (WidgetSnapshotStore.read()?.families ?? []).map { WidgetFamilyEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: Zeitleiste

struct TodayEntry: TimelineEntry {
    let date: Date
    let entries: [WidgetRules.Entry]
    let snapshot: WidgetSnapshot?

    var count: Int { entries.count }

    func color(of item: WidgetSnapshot.Item) -> Color {
        snapshot?.family(item.familyID).flatMap { RGBColor(hex: $0.colorHex) }.map(Color.init) ?? FamiliarColor.accent
    }

    static let preview: TodayEntry = {
        let family = UUID()
        let items = [
            WidgetSnapshot.Item(id: UUID(), title: "Müll rausbringen", familyID: family, startDate: nil, startTime: nil,
                                startsAt: nil, createdAt: .now, isAssignedToMe: true, canComplete: true, initials: ["P"]),
            WidgetSnapshot.Item(id: UUID(), title: "Zimmer aufräumen", familyID: family, startDate: nil, startTime: nil,
                                startsAt: nil, createdAt: .now, isAssignedToMe: true, canComplete: true, initials: ["M", "P"]),
            WidgetSnapshot.Item(id: UUID(), title: "Pausenbrote machen", familyID: family, startDate: nil, startTime: nil,
                                startsAt: nil, createdAt: .now, isAssignedToMe: true, canComplete: true, initials: ["J"]),
        ]
        let snapshot = WidgetSnapshot(items: items, families: [.init(id: family, name: "Familie", colorHex: "#5EC2F2")])
        return TodayEntry(date: .now, entries: WidgetRules.today(snapshot, onlyMine: false), snapshot: snapshot)
    }()
}

struct TodayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .preview }

    func snapshot(for configuration: TodayWidgetConfiguration, in context: Context) async -> TodayEntry {
        if context.isPreview && WidgetSnapshotStore.read() == nil { return .preview }
        return entry(for: configuration, now: .now)
    }

    func timeline(for configuration: TodayWidgetConfiguration, in context: Context) async -> Timeline<TodayEntry> {
        let now = Date.now
        let entry = entry(for: configuration, now: now)
        let next = entry.snapshot.map { WidgetRules.nextRefresh($0, now: now) } ?? now.addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: TodayWidgetConfiguration, now: Date) -> TodayEntry {
        guard let snapshot = WidgetSnapshotStore.read() else {
            return TodayEntry(date: now, entries: [], snapshot: nil)
        }
        return TodayEntry(date: now,
                          entries: WidgetRules.today(snapshot, now: now, onlyMine: configuration.onlyMine,
                                                     familyID: configuration.family?.id),
                          snapshot: snapshot)
    }
}

// MARK: Ansichten

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        default:
            list(limit: family == .systemLarge ? 7 : 3)
        }
    }

    // Sperrbildschirm

    private var inline: some View {
        Label(entry.snapshot == nil ? "Familiar" : inlineText, systemImage: "checklist")
    }

    private var inlineText: String {
        switch entry.count {
        case 0: String(localized: "Heute alles erledigt")
        case 1: String(localized: "1 Aufgabe heute")
        default: String(localized: "\(entry.count) Aufgaben heute")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.count == 0 ? "checkmark" : "checklist")
                    .font(.caption.weight(.semibold))
                if entry.count > 0 {
                    Text("\(entry.count)")
                        .font(.title3.weight(.bold).monospacedDigit())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(inlineText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(inlineText)
                .font(.headline)
                .widgetAccentable()
            ForEach(entry.entries.prefix(2), id: \.item.id) { row in
                Text(row.item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Homescreen

    private var small: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
            header
            Spacer(minLength: 0)
            if let first = entry.entries.first {
                Text("\(entry.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(FamiliarColor.textPrimary)
                HStack(spacing: 6) {
                    Circle().fill(entry.color(of: first.item)).frame(width: 7, height: 7)
                    Text(first.item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FamiliarColor.textSecondary)
                        .lineLimit(2)
                        .privacySensitive()
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xs) {
            header
            if entry.entries.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                ForEach(entry.entries.prefix(limit), id: \.item.id) { row in
                    TodayRow(row: row, color: entry.color(of: row.item))
                }
                if entry.count > limit {
                    Text("+ \(entry.count - limit) weitere")
                        .font(.caption)
                        .foregroundStyle(FamiliarColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Text("Heute")
                .font(.headline)
                .foregroundStyle(FamiliarColor.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FamiliarColor.accent)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if entry.snapshot == nil {
            Text("Öffne Familiar, um deine Aufgaben hier zu sehen.")
                .font(.caption)
                .foregroundStyle(FamiliarColor.textSecondary)
        } else {
            Label("Alles erledigt", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FamiliarColor.success)
        }
    }
}

/// Eine Zeile mit Familienfarbe, Titel, Zeit und Abhak-Knopf (falls erlaubt).
private struct TodayRow: View {
    let row: WidgetRules.Entry
    let color: Color

    var body: some View {
        HStack(spacing: FamiliarSpacing.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .lineLimit(1)
                    .privacySensitive()
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(row.isOverdue ? FamiliarColor.danger : FamiliarColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if row.item.canComplete {
                Button(intent: CompleteTaskIntent(taskID: row.item.id)) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(FamiliarColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.item.title) abhaken")
            }
        }
    }

    private var detail: String? {
        if row.isOverdue { return String(localized: "Überfällig") }
        if row.item.startTime != nil, let startsAt = row.item.startsAt {
            return startsAt.formatted(date: .omitted, time: .shortened)
        }
        return nil
    }
}
