// App-Icon aus dem Markenzeichen erzeugen: swiftc -O tools/render-app-icon.swift -o /tmp/render && /tmp/render ios/Familiar/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import SwiftUI
import AppKit

// Gleiche Geometrie wie FamiliarMark (FamiliarDesign), auf dunklem Grund.
struct Icon: View {
    let side: CGFloat = 1024
    var body: some View {
        let size = side * 0.6
        let tile = size * 0.78
        let gap = size * 0.04
        let shape = RoundedRectangle(cornerRadius: tile * 0.3, style: .continuous)
        ZStack {
            Color(red: 0x1E/255, green: 0x15/255, blue: 0x19/255)
            ZStack(alignment: .bottomLeading) {
                shape.fill(Color(red: 0x5E/255, green: 0xC2/255, blue: 0xF2/255))
                    .frame(width: tile, height: tile)
                    .rotationEffect(.degrees(8))
                    .offset(x: size - tile, y: -(size - tile))
                RoundedRectangle(cornerRadius: tile * 0.3 + gap, style: .continuous)
                    .fill(Color(red: 0x1E/255, green: 0x15/255, blue: 0x19/255))
                    .frame(width: tile + 2 * gap, height: tile + 2 * gap)
                    .offset(x: -gap, y: gap)
                shape.fill(Color(red: 1, green: 0x8C/255, blue: 0x42/255))
                    .frame(width: tile, height: tile)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: tile * 0.42, weight: .heavy))
                            .foregroundStyle(Color(red: 0x1B/255, green: 0x10/255, blue: 6/255))
                    }
            }
            .frame(width: size, height: size)
            .offset(x: -side * 0.015, y: side * 0.015)
        }
        .frame(width: side, height: side)
    }
}

@MainActor func render() {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    // Ohne Alphakanal speichern (App Store verlangt ein undurchsichtiges Icon).
    let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
MainActor.assumeIsolated { render() }
