// Rendert eine HTML-Datei in eine PNG-Datei (ohne Browser-Installation, nutzt WebKit des Macs).
// Aufruf: swiftc -O render-html.swift -o /tmp/render-html && /tmp/render-html <eingabe.html> <ausgabe.png> <breite> <hoehe>
// Breite/Höhe = Seitengröße in CSS-Pixeln; das fertige Bild hat die doppelte Pixelzahl, ohne Alpha-Kanal
// (z. B. 660 × 1434 → 1320 × 2868 für App Store Connect).
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 5, let w = Double(args[3]), let h = Double(args[4]) else {
    FileHandle.standardError.write(Data("Aufruf: render-html <in.html> <out.png> <breite> <hoehe>\n".utf8)); exit(2)
}
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])

final class Delegate: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let w: Double, h: Double, output: URL
    init(_ web: WKWebView, w: Double, h: Double, output: URL) { self.web = web; self.w = w; self.h = h; self.output = output }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Schriften und Bilder in Ruhe laden lassen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = CGRect(x: 0, y: 0, width: self.w, height: self.h)
            cfg.snapshotWidth = NSNumber(value: self.w)
            self.web.takeSnapshot(with: cfg) { image, error in
                // Immer doppelte Pixelzahl und OHNE Alpha-Kanal (App Store Connect lehnt Transparenz ab).
                let pw = Int(self.w * 2), ph = Int(self.h * 2)
                guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                    FileHandle.standardError.write(Data("Fehler: \(String(describing: error))\n".utf8)); exit(1)
                }
                ctx.interpolationQuality = .high
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
                guard let out = ctx.makeImage(),
                      let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { exit(1) }
                try? png.write(to: self.output); exit(0)
            }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let cfg = WKWebViewConfiguration()
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: w, height: h), configuration: cfg)
    let win = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = web
    win.orderBack(nil)
    let d = Delegate(web, w: w, h: h, output: output)
    web.navigationDelegate = d
    objc_setAssociatedObject(web, "d", d, .OBJC_ASSOCIATION_RETAIN)
    web.loadFileURL(input, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    app.run()
}
