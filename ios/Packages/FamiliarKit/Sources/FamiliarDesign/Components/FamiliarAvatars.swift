import FamiliarCore
import SwiftUI

/// Erledigungsstatus einer Person innerhalb einer Aufgabe.
public enum AssigneeCompletion: Sendable, Hashable {
    case open
    case done
}

/// Rundes Profilbild oder Initialen.
///
/// Erledigte Personen werden abgeschwächt und mit einem Häkchen markiert,
/// damit der Status nicht allein über Farbe erkennbar ist.
public struct AvatarView: View {
    let name: String
    let image: Image?
    let diameter: CGFloat
    let completion: AssigneeCompletion?

    public init(name: String, image: Image? = nil, diameter: CGFloat = 32, completion: AssigneeCompletion? = nil) {
        self.name = name
        self.image = image
        self.diameter = diameter
        self.completion = completion
    }

    public var body: some View {
        ZStack {
            Circle().fill(FamiliarColor.elevated)
            if let image {
                image.resizable().scaledToFill()
            } else {
                Text(PersonName.initials(from: name))
                    .font(.system(size: diameter * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        // Erledigt: grüner Ring plus Häkchen-Abzeichen (nicht nur über Farbe erkennbar).
        .overlay(Circle().strokeBorder(completion == .done ? FamiliarColor.success : FamiliarColor.hairline,
                                       lineWidth: completion == .done ? 2 : 1))
        .overlay(alignment: .bottomTrailing) {
            if completion == .done {
                let badge = max(diameter * 0.42, 12)
                Image(systemName: "checkmark")
                    .font(.system(size: badge * 0.55, weight: .heavy))
                    .foregroundStyle(FamiliarColor.onAccent)
                    .frame(width: badge, height: badge)
                    .background(Circle().fill(FamiliarColor.success))
                    .overlay(Circle().strokeBorder(FamiliarColor.canvas, lineWidth: 1.5))
                    .offset(x: badge * 0.2, y: badge * 0.2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch completion {
        case .done: "\(name), erledigt"
        case .open: "\(name), offen"
        case nil: name
        }
    }
}

/// Überlappende Avatare der zugewiesenen Personen mit Überlauf-Zähler.
public struct AvatarStack: View {
    public struct Person: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let completion: AssigneeCompletion?

        public init(id: String, name: String, completion: AssigneeCompletion? = nil) {
            self.id = id
            self.name = name
            self.completion = completion
        }
    }

    let people: [Person]
    let diameter: CGFloat
    let maxVisible: Int

    public init(people: [Person], diameter: CGFloat = 26, maxVisible: Int = 4) {
        self.people = people
        self.diameter = diameter
        self.maxVisible = maxVisible
    }

    public var body: some View {
        HStack(spacing: -diameter * 0.28) {
            ForEach(people.prefix(maxVisible)) { person in
                AvatarView(name: person.name, diameter: diameter, completion: person.completion)
                    .padding(1.5)
                    .background(Circle().fill(FamiliarColor.card))
            }
            if people.count > maxVisible {
                Text("+\(people.count - maxVisible)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FamiliarColor.textSecondary)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(FamiliarColor.elevated))
                    .padding(1.5)
                    .background(Circle().fill(FamiliarColor.card))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let parts = people.map { person in
            switch person.completion {
            case .done: "\(person.name) erledigt"
            case .open: "\(person.name) offen"
            case nil: person.name
            }
        }
        return "Zugewiesen: " + parts.formatted(.list(type: .and))
    }
}
