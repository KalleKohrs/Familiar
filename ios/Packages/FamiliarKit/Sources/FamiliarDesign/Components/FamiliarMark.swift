import FamiliarCore
import SwiftUI

/// Markenzeichen: eine flache Kachel mit Haken vor einer zweiten Kachel in einer Familienfarbe –
/// „geteilte Aufgaben“. Bewusst ohne Verläufe, Leuchten und 3D-Effekte.
public struct FamiliarMark: View {
    let size: CGFloat

    public init(size: CGFloat = 72) {
        self.size = size
    }

    public var body: some View {
        let tile = size * 0.78
        let shape = RoundedRectangle(cornerRadius: tile * 0.3, style: .continuous)
        let gap = max(2, size * 0.04)
        ZStack(alignment: .bottomLeading) {
            shape
                .fill(Color(RGBColor(hex: 0x5EC2F2)))
                .frame(width: tile, height: tile)
                .rotationEffect(.degrees(8))
                .offset(x: size - tile, y: -(size - tile))
            // Schmale Lücke: schneidet die hintere Kachel um die vordere herum aus, sodass dort
            // der echte Hintergrund durchscheint.
            RoundedRectangle(cornerRadius: tile * 0.3 + gap, style: .continuous)
                .frame(width: tile + 2 * gap, height: tile + 2 * gap)
                .offset(x: -gap, y: gap)
                .blendMode(.destinationOut)
            shape
                .fill(FamiliarColor.accent)
                .frame(width: tile, height: tile)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: tile * 0.42, weight: .heavy))
                        .foregroundStyle(FamiliarColor.onAccent)
                }
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 32) {
        FamiliarMark(size: 88)
        FamiliarMark(size: 64)
        FamiliarMark(size: 40)
    }
    .padding(40)
    .background(FamiliarColor.canvas)
}
