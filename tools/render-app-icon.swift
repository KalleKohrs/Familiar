// App-Icon in allen drei Erscheinungsbildern erzeugen:
// swiftc -O tools/render-app-icon.swift -o /tmp/render && /tmp/render ios/Familiar/Resources/Assets.xcassets/AppIcon.appiconset
//
// Motiv: Haus mit Haken („zu Hause erledigt“), ruhig – eine Fläche, ein Hauch Verlauf, ein weicher Schatten.
// Standard: helles Haus auf Bernstein-Orange, oranger Haken. Dunkel: oranges Haus, dunkler Haken auf Aubergine
// (eigener farbiger Grund statt durchsichtig – laut HIG geben farbige Hintergründe im Dunkeln den besten Kontrast).
// Getönt als Graustufenbild auf durchsichtigem Grund (Apple-Doku „Configuring your app icon“).
import AppKit
import CoreGraphics

let side: CGFloat = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

enum Variant: String, CaseIterable {
    case standard = "AppIcon", dark = "AppIcon-Dark", tinted = "AppIcon-Tinted"
}

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: w, green: w, blue: w, alpha: a) }

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: Geometrie (Koordinaten von oben links, 1024 × 1024)

// Das Haus ist achsensymmetrisch zu x = 512. Wegen des spitzen Dachs liegt sein Flächenschwerpunkt unter der
// Mitte seines Rahmens; deshalb sitzt es 25 px höher (Schwerpunkt bei y ≈ 545). Ganz auf die Mitte gerückt wirkte
// es zu hoch, weil das Auge die Dachkante als oberen Rand liest.
let houseLift: CGFloat = 25
let house = [P(512, 215), P(825, 470), P(825, 810), P(199, 810), P(199, 470)].map { P($0.x, $0.y - houseLift) }
let houseRadius: CGFloat = 60

// Haken mit Armen im Verhältnis 1 : 2; sein Schwerpunkt liegt genau auf der Achse x = 512 und knapp unter
// dem Schwerpunkt des Hauses, mit gleichem Abstand zu beiden Hauswänden.
let tick = [P(386, 560), P(471, 645), P(636, 465)]
let tickWidth: CGFloat = 74

func roundedPolygon(_ pts: [CGPoint], radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let n = pts.count
    p.move(to: P((pts[n - 1].x + pts[0].x) / 2, (pts[n - 1].y + pts[0].y) / 2))
    for i in 0..<n {
        p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radius)
    }
    p.closeSubpath()
    return p
}

// MARK: Malen

func linear(_ c: CGContext, _ colors: [CGColor], _ from: CGPoint, _ to: CGPoint) {
    let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil)!
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Form mit senkrechtem Verlauf füllen, darunter ein weicher Schatten.
func fill(_ c: CGContext, _ path: CGPath, _ colors: [CGColor], shadow: CGColor?) {
    let b = path.boundingBoxOfPath
    if let shadow {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: shadow)
        c.addPath(path); c.setFillColor(colors[0]); c.fillPath()
        c.restoreGState()
    }
    c.saveGState(); c.addPath(path); c.clip()
    linear(c, colors, P(b.midX, b.minY), P(b.midX, b.maxY))
    c.restoreGState()
}

func draw(_ v: Variant, in c: CGContext) {
    let orange = [hex(0xFFA45C), hex(0xF5742C)]
    let houseColors: [CGColor]
    let tickColors: [CGColor]
    let shadow: CGColor
    switch v {
    case .standard:
        linear(c, orange, P(512, 0), P(512, side))
        houseColors = [hex(0xFFFBF5), hex(0xF6E8DA)]
        tickColors = orange
        shadow = hex(0x2A0A10, 0.22)
    case .dark:
        linear(c, [hex(0x2C1D25), hex(0x1E1519)], P(512, 0), P(512, side))
        houseColors = orange
        tickColors = [hex(0x2B141A), hex(0x22100F)]
        shadow = gray(0, 0.5)
    case .tinted:
        houseColors = [gray(1), gray(0.86)]
        tickColors = [gray(0.18), gray(0.12)]
        shadow = gray(0, 0.4)
    }
    fill(c, roundedPolygon(house, radius: houseRadius), houseColors, shadow: shadow)
    let line = CGMutablePath()
    line.addLines(between: tick)
    fill(c, line.copy(strokingWithWidth: tickWidth, lineCap: .round, lineJoin: .round, miterLimit: 10), tickColors, shadow: nil)
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
for v in Variant.allCases {
    // Standard und Dunkel ohne Alphakanal (undurchsichtig), Getönt mit Transparenz.
    let alpha: CGImageAlphaInfo = v == .tinted ? .premultipliedLast : .noneSkipLast
    let c = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                      bitmapInfo: alpha.rawValue)!
    c.translateBy(x: 0, y: side); c.scaleBy(x: 1, y: -1) // Koordinaten von oben links
    draw(v, in: c)
    let data = NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
    try! data.write(to: dir.appendingPathComponent("\(v.rawValue).png"))
}
