// Renders the DMG window background: a dark ink field in the badge's own
// top-left -> bottom-right diagonal with a soft azure glow behind the app
// icon slot, the title, an arrow between the app and Applications icon
// spots, and the one instruction that matters. Dark field on purpose: the
// full-bleed blue badge needs the contrast (owner note 2026-10-17).
// The two icons themselves are placed by Finder on top of this image.
// Usage: swift scripts/make-dmg-background.swift <output.png>
import AppKit

// Window is 600×400 pt; render at 2× for Retina sharpness (pattern learned
// from vorssaint's MakeDMGBackground.swift).
let scale: CGFloat = 2
let widthPt: CGFloat = 600, heightPt: CGFloat = 400
let px = Int(widthPt * scale), py = Int(heightPt * scale)

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = NSSize(width: widthPt, height: heightPt) // 144 dpi in the PNG

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.cgContext.scaleBy(x: scale, y: scale) // draw in points, output at 2×

let full = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)

// The badge's own diagonal, dropped to near-black navy so the full-bleed
// blue icon (and the blue Applications folder) pop off the field.
func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
if let gradient = NSGradient(starting: srgb(0x16, 0x1F, 0x38),
                             ending: srgb(0x06, 0x08, 0x0F)) {
    gradient.draw(in: full, angle: -45)
}

// Soft azure glow behind the app icon slot (Finder places the icon at
// x=150, y=200) so the badge looks lit from its own field.
if let glow = NSGradient(colors: [srgb(0x4D, 0xA6, 0xF4, 0.20),
                                  srgb(0x4D, 0xA6, 0xF4, 0.0)]) {
    let center = NSPoint(x: 150, y: 200)
    glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 110, options: [])
}

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
    ]
    let s = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (widthPt - s.width) / 2, y: y), withAttributes: attrs)
}

draw("Pyaww", size: 26, weight: .bold, alpha: 0.97, y: heightPt - 70)
draw("Drag the app into Applications", size: 12, weight: .regular, alpha: 0.92, y: 92)
draw("menu-bar dictation for Myanmar · everything stays on this Mac",
     size: 10, weight: .regular, alpha: 0.66, y: 66)

// Arrow between the two icon spots (Finder places them at x = 150 / 450).
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 238, y: 200))
arrow.line(to: NSPoint(x: 356, y: 200))
arrow.move(to: NSPoint(x: 344, y: 210))
arrow.line(to: NSPoint(x: 358, y: 200))
arrow.line(to: NSPoint(x: 344, y: 190))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(white: 1, alpha: 0.9).setStroke()
arrow.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: out))
    print("background \(px)×\(py) -> \(out)")
} catch {
    FileHandle.standardError.write(Data("could not write \(out): \(error)\n".utf8))
    exit(1)
}
