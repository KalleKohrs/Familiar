import FamiliarCore
import SwiftUI

/// Markenzeichen: flaches oranges Haus mit Haken – „zu Hause erledigt“. Gleiche Geometrie wie das App-Icon
/// (`tools/render-app-icon.swift`) und das Website-Logo (`website/assets/mark.svg`); bewusst ohne Verläufe,
/// Leuchten und 3D-Effekte.
public struct FamiliarMark: View {
    let size: CGFloat

    public init(size: CGFloat = 72) {
        self.size = size
    }

    public var body: some View {
        // Das Haus ist so breit wie das Zeichen und 0,95-mal so hoch; senkrecht mittig.
        let height = size * 0.9505
        ZStack {
            HouseShape()
                .fill(FamiliarColor.accentFill)
            TickShape()
                .stroke(FamiliarColor.onAccent, style: StrokeStyle(lineWidth: size * 0.1182, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: height)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Fünfeck mit abgerundeten Ecken, Maße relativ zur Breite.
private struct HouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let points = [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.4073), CGPoint(x: 1, y: 0.9505),
                      CGPoint(x: 0, y: 0.9505), CGPoint(x: 0, y: 0.4073)]
            .map { CGPoint(x: rect.minX + $0.x * w, y: rect.minY + $0.y * w) }
        var path = Path()
        let last = points[points.count - 1]
        path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for i in points.indices {
            path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % points.count], radius: w * 0.0958)
        }
        path.closeSubpath()
        return path
    }
}

/// Haken mit Armen im Verhältnis 1 : 2, Schwerpunkt auf der Mittelachse.
private struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        var path = Path()
        path.addLines([CGPoint(x: 0.2987, y: 0.5911), CGPoint(x: 0.4345, y: 0.7268), CGPoint(x: 0.6981, y: 0.4393)]
            .map { CGPoint(x: rect.minX + $0.x * w, y: rect.minY + $0.y * w) })
        return path
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
