// App-Icon in allen drei Erscheinungsbildern erzeugen:
// swiftc -O tools/render-app-icon.swift -o /tmp/render && /tmp/render ios/Familiar/Resources/Assets.xcassets/AppIcon.appiconset
//
// Motiv wie FamiliarMark: orange Kachel mit Haken vor einer zweiten Kachel in Familienfarbe („geteilte Aufgaben“),
// hier plastisch mit Verläufen, weichem Glanz und Schatten auf warmem Aubergine-Grund.
// Varianten nach Apple-Doku „Configuring your app icon“: Standard undurchsichtig, Dunkel mit durchsichtigem
// Hintergrund (das System legt seinen eigenen darunter), Getönt als Graustufenbild.
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

/// Kachel mit kontinuierlichen Ecken (Superellipse), wie die abgerundeten Formen im System.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    for i in 0...360 {
        let t = CGFloat(i) / 360 * 2 * .pi
        let c = cos(t), s = sin(t)
        let pt = P(r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                   r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func linear(_ c: CGContext, _ colors: [CGColor], _ from: CGPoint, _ to: CGPoint, locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)!
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func glow(_ c: CGContext, _ color: UInt32, _ alpha: CGFloat, at p: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: srgb, colors: [hex(color, alpha), hex(color, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}

/// Form mit senkrechtem Verlauf füllen, darunter ein weicher Schatten.
func fill(_ c: CGContext, _ path: CGPath, _ colors: [CGColor], shadow: (offset: CGFloat, blur: CGFloat, color: CGColor)) {
    let b = path.boundingBoxOfPath
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -shadow.offset), blur: shadow.blur, color: shadow.color)
    c.addPath(path); c.setFillColor(colors[colors.count / 2]); c.fillPath()
    c.restoreGState()
    c.saveGState(); c.addPath(path); c.clip()
    linear(c, colors, P(b.midX, b.minY), P(b.midX, b.maxY))
    c.restoreGState()
}

/// Weicher Glanz in der oberen Hälfte und eine Lichtkante am Rand (oben hell, unten leicht dunkel).
func gloss(_ c: CGContext, _ path: CGPath, strength: CGFloat) {
    let b = path.boundingBoxOfPath
    c.saveGState(); c.addPath(path); c.clip()
    linear(c, [gray(1, strength), gray(1, 0)], P(b.midX, b.minY), P(b.midX, b.minY + b.height * 0.55))
    c.addPath(path.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 10)); c.clip()
    linear(c, [gray(1, 0.55), gray(1, 0), gray(0, 0.12)], P(b.midX, b.minY), P(b.midX, b.maxY), locations: [0, 0.5, 1])
    c.restoreGState()
}

func draw(_ v: Variant, in c: CGContext) {
    if v == .standard {
        linear(c, [hex(0x3D2333), hex(0x1E1519), hex(0x140D11)], P(512, 0), P(512, side), locations: [0, 0.55, 1])
        glow(c, 0xFF7A3D, 0.55, at: P(860, 140), radius: 640)
        glow(c, 0x9A4670, 0.6, at: P(120, 980), radius: 620)
    }

    // Hintere Kachel: Familienfarbe Himmel, leicht gedreht.
    var turn = CGAffineTransform(translationX: 625, y: 395).rotated(by: 9 * .pi / 180).translatedBy(x: -625, y: -395)
    let back = squircle(CGRect(x: 405, y: 175, width: 440, height: 440)).copy(using: &turn)!
    let backColors: [CGColor] = switch v {
    case .standard: [hex(0x9BE0FF), hex(0x5EC2F2), hex(0x2E8FD6)]
    case .dark: [hex(0x86D2F5), hex(0x4FAEDF), hex(0x2878B8)]
    case .tinted: [gray(0.62), gray(0.5), gray(0.38)]
    }
    fill(c, back, backColors, shadow: (18, 40, gray(0, 0.4)))
    gloss(c, back, strength: 0.3)

    // Vordere Kachel: Bernstein-Orange, hebt sich mit kräftigem Schatten ab.
    let front = squircle(CGRect(x: 190, y: 330, width: 520, height: 520))
    let frontColors: [CGColor] = switch v {
    case .standard: [hex(0xFFC27A), hex(0xFF8C42), hex(0xEE5A2A)]
    case .dark: [hex(0xFFB066), hex(0xF57E35), hex(0xD9541F)]
    case .tinted: [gray(1), gray(0.93), gray(0.82)]
    }
    fill(c, front, frontColors, shadow: (26, 60, v == .tinted ? gray(0, 0.65) : hex(0x0A0306, 0.65)))
    gloss(c, front, strength: v == .tinted ? 0.2 : 0.4)

    // Haken in dunkler Aubergine-Tinte.
    let tick = CGMutablePath()
    tick.addLines(between: [P(335, 600), P(425, 700), P(580, 490)])
    let check = tick.copy(strokingWithWidth: 70, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let checkColors: [CGColor] = v == .tinted ? [gray(0.2), gray(0.1)] : [hex(0x3A1A20), hex(0x22100F)]
    fill(c, check, checkColors, shadow: (0, 0, gray(0, 0)))
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
for v in Variant.allCases {
    // Standard ohne Alphakanal (App Store verlangt ein undurchsichtiges Icon), Dunkel/Getönt mit Transparenz.
    let alpha: CGImageAlphaInfo = v == .standard ? .noneSkipLast : .premultipliedLast
    let c = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                      bitmapInfo: alpha.rawValue)!
    c.translateBy(x: 0, y: side); c.scaleBy(x: 1, y: -1) // Koordinaten von oben links
    draw(v, in: c)
    let data = NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
    try! data.write(to: dir.appendingPathComponent("\(v.rawValue).png"))
}
