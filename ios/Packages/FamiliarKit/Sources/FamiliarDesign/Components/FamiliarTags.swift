import SwiftUI

/// Kennzeichnung der Familie einer Aufgabe: Farbpunkt plus Name,
/// damit die Zuordnung nie allein über die Farbe erfolgt.
public struct FamilyBadge: View {
    let name: String
    let color: Color

    public init(name: String, color: Color) {
        self.name = name
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color)
                .overlay(Circle().strokeBorder(FamiliarColor.hairline, lineWidth: 0.5))
                .frame(width: 8, height: 8)
            Text(name)
                .font(FamiliarFont.caption)
                .foregroundStyle(FamiliarColor.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, FamiliarSpacing.xs)
        .padding(.vertical, FamiliarSpacing.xxs)
        .background(Capsule().fill(color.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Familie \(name)")
    }
}

/// Kleines Etikett für Zeit, Status oder Hinweise.
public struct FamiliarTag: View {
    public enum Tone: Sendable {
        case neutral
        case accent
        case success
        case warning
        case danger
    }

    let text: String
    let systemImage: String?
    let tone: Tone

    public init(_ text: String, systemImage: String? = nil, tone: Tone = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        Label {
            Text(text).font(FamiliarFont.time)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(color)
        .padding(.horizontal, FamiliarSpacing.xs)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(tone == .neutral ? 0.10 : 0.16)))
    }

    private var color: Color {
        switch tone {
        case .neutral: FamiliarColor.textSecondary
        case .accent: FamiliarColor.accent
        case .success: FamiliarColor.success
        case .warning: FamiliarColor.warning
        case .danger: FamiliarColor.danger
        }
    }
}

/// Überschrift einer Gruppe in Listen; für VoiceOver als Überschrift markiert.
public struct FamiliarSectionHeader: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(FamiliarFont.sectionTitle)
            .foregroundStyle(FamiliarColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
