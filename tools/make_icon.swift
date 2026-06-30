import AppKit

// Renders the app icon (headphones on a gradient rounded square) → iconset → .icns
let OUT = "resources/RedmiBudsControl.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: OUT)
try? fm.createDirectory(atPath: OUT, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let r = NSRect(x: 0, y: 0, width: size, height: size)
    let bg = NSImage(size: r.size)
    bg.lockFocus()
    let path = NSBezierPath(roundedRect: r.insetBy(dx: s*0.04, dy: s*0.04),
                            xRadius: s*0.22, yRadius: s*0.22)
    if let g = NSGradient(colors: [NSColor(srgbRed: 0.30, green: 0.34, blue: 0.95, alpha: 1),
                                   NSColor(srgbRed: 0.62, green: 0.28, blue: 0.92, alpha: 1)]) {
        g.draw(in: path, angle: -45)
    }
    bg.unlockFocus()
    bg.draw(in: r)
    if let sym = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: s*0.52, weight: .regular)
        let rendered = sym.withSymbolConfiguration(cfg)!
        let r2 = NSRect(x: (s-rendered.size.width)/2, y: (s-rendered.size.height)/2,
                        width: rendered.size.width, height: rendered.size.height)
        NSColor.white.set()
        rendered.draw(in: r2)
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(at: .zero, from: r, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),
    ("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),
    ("icon_512x512",512),("icon_512x512@2x",1024),
]
for (name, px) in sizes {
    try render(px).write(to: URL(fileURLWithPath: "\(OUT)/\(name).png"))
}
print("iconset written")
