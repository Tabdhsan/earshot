// Renders the Earshot app icon to Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift  (run from the repo root)
import Cocoa

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024

    // Squircle-ish background with a sunset gradient
    let inset = 100 * u, body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: body, xRadius: 185 * u, yRadius: 185 * u)
    NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.36, blue: 0.45, alpha: 1),
                        NSColor(srgbRed: 0.55, green: 0.24, blue: 0.85, alpha: 1),
                        NSColor(srgbRed: 0.16, green: 0.14, blue: 0.42, alpha: 1)])!
        .draw(in: bg, angle: -60)

    // Frosted classic-HUD tile in the middle
    let tw = 520 * u, tile = NSRect(x: (s - tw) / 2, y: (s - tw) / 2, width: tw, height: tw)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 40 * u; shadow.shadowOffset = NSSize(width: 0, height: -14 * u)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    NSColor(white: 0.08, alpha: 0.55).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 70 * u, yRadius: 70 * u).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Speaker
    let cfg = NSImage.SymbolConfiguration(pointSize: 230 * u, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let r = NSRect(x: tile.midX - sym.size.width / 2, y: tile.minY + 175 * u,
                       width: sym.size.width, height: sym.size.height)
        sym.draw(in: r)
    }

    // Chiclet bar
    let n = 12, gap = 6 * u, bw = 400 * u, bh = 30 * u
    let cw = (bw - gap * CGFloat(n - 1)) / CGFloat(n), x0 = tile.midX - bw / 2, y0 = tile.minY + 85 * u
    for i in 0..<n {
        (i < 8 ? NSColor.white : NSColor.white.withAlphaComponent(0.22)).setFill()
        NSBezierPath(roundedRect: NSRect(x: x0 + CGFloat(i) * (cw + gap), y: y0, width: cw, height: bh),
                     xRadius: 4 * u, yRadius: 4 * u).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "build/AppIcon.iconset"
try? fm.removeItem(atPath: set)
try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let p = Process(); p.launchPath = "/usr/bin/iconutil"
p.arguments = ["-c", "icns", set, "-o", "Resources/AppIcon.icns"]; p.launch(); p.waitUntilExit()
try! render(1024).write(to: URL(fileURLWithPath: "Resources/icon.png"))
print("wrote Resources/AppIcon.icns")
