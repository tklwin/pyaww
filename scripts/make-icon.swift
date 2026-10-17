// Renders the Pyaww app icon (draft) as a 1024×1024 PNG.
//
// Usage: swift scripts/make-icon.swift out-1024.png [glyph|wave5|wave7]
//        (default: glyph — the currently shipped design)
//
// Design (draft, 2026-10-17): Big Sur-style rounded square with an indigo →
// violet gradient. Foreground options: the Burmese word "ပြော" (pyaw — "to
// speak") in white, or a white audio-waveform (5 or 7 rounded bars).
// Regenerate the .icns via scripts/make-icon.sh. Dev tool only — not part of
// the app; no third-party dependencies.
import AppKit

let canvas: CGFloat = 1024
let margin: CGFloat = 100
let radius: CGFloat = 190
let center = canvas / 2

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// A capsule (fully rounded bar) centered on `centerX`, `center.y`.
func bar(width: CGFloat, height: CGFloat, centerX: CGFloat) -> NSBezierPath {
    let rect = NSRect(x: centerX - width / 2, y: center - height / 2, width: width, height: height)
    return NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2)
}

/// White audio-waveform: symmetric rounded bars.
func drawWave(barWidth: CGFloat, gap: CGFloat, heights: [CGFloat]) {
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var centerX = center - totalWidth / 2 + barWidth / 2
    NSColor.white.setFill()
    for height in heights {
        bar(width: barWidth, height: height, centerX: centerX).fill()
        centerX += barWidth + gap
    }
}

/// The Burmese word "ပြော" (pyaw — "to speak"). Try the Myanmar fonts macOS
/// ships; the system font also cascades to a Myanmar face if neither is
/// present. Returns the font actually used, for the log line.
func drawGlyph() -> String {
    let glyph = "ပြော" as NSString
    let fontNames = ["Myanmar MN", "Noto Sans Myanmar", "Myanmar Sangam MN", "Myanmar Text"]
    var font = NSFont.boldSystemFont(ofSize: 470)
    for name in fontNames {
        if let candidate = NSFont(name: name, size: 470) {
            font = candidate
            break
        }
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let textSize = glyph.size(withAttributes: attributes)
    glyph.draw(
        at: NSPoint(x: (canvas - textSize.width) / 2, y: (canvas - textSize.height) / 2),
        withAttributes: attributes)
    return font.fontName
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let style = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "glyph"

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let body = NSRect(x: margin, y: margin, width: canvas - 2 * margin, height: canvas - 2 * margin)
let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.22, green: 0.16, blue: 0.55, alpha: 1),
    NSColor(srgbRed: 0.55, green: 0.26, blue: 0.74, alpha: 1),
])
guard let gradient else { fail("could not build gradient") }
gradient.draw(in: shape, angle: -90)

var summary: String
switch style {
case "glyph":
    summary = "(style: glyph, font: \(drawGlyph()))"
case "wave5":
    drawWave(barWidth: 88, gap: 60, heights: [220, 430, 640, 430, 220])
    summary = "(style: wave5)"
case "wave7":
    drawWave(barWidth: 68, gap: 42, heights: [180, 300, 440, 620, 440, 300, 180])
    summary = "(style: wave7)"
default:
    fail("unknown style \"\(style)\" — use glyph, wave5 or wave7")
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else { fail("could not render PNG") }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    fail("could not write \(outPath): \(error)")
}
print("wrote \(outPath) \(summary)")
