// Misst Kanten in einer Aufnahme: gibt entlang einer Zeile oder Spalte die Stellen aus, an denen sich die Farbe deutlich ändert.
// Aufruf: probe <bild.png> row <y> <x0> <x1>   |   probe <bild.png> col <x> <y0> <y1>   [schwelle, Standard 6]
import AppKit

let a = CommandLine.arguments
guard a.count >= 6, let img = NSImage(contentsOfFile: a[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("Aufruf falsch"); exit(2) }
let w = cg.width, h = cg.height
var data = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
func px(_ x: Int, _ y: Int) -> (Int, Int, Int) { let i = (y * w + x) * 4; return (Int(data[i]), Int(data[i+1]), Int(data[i+2])) }
let mode = a[2], fixed = Int(a[3])!, from = Int(a[4])!, to = Int(a[5])!
let thr = a.count > 6 ? Int(a[6])! : 6
var prev: (Int, Int, Int)? = nil
for p in stride(from: from, through: to, by: from <= to ? 1 : -1) {
    let c = mode == "row" ? px(p, fixed) : px(fixed, p)
    if let q = prev, abs(c.0 - q.0) + abs(c.1 - q.1) + abs(c.2 - q.2) >= thr { print("\(p): \(c.0),\(c.1),\(c.2)  (vorher \(q.0),\(q.1),\(q.2))") }
    prev = c
}
