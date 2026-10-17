// Renders the Pyaww app icon (draft) as a 1024×1024 PNG.
//
// Usage: swift scripts/make-icon.swift out-1024.png
//
// Design (draft, 2026-10-17): Big Sur-style rounded square with an indigo →
// violet gradient and the Burmese word "ပြော" (pyaw — "to speak") in white.
// Regenerate the .icns via scripts/make-icon.sh. Dev tool only — not part of
// the app; no third-party dependencies.
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let canvas: CGFloat = 1024
let margin: CGFloat = 100
let radius: CGFloat = 190

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

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

// Burmese glyph for "speak". Try the Myanmar fonts macOS ships; the system
// font also cascades to a Myanmar face if neither is present.
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
print("wrote \(outPath) (font: \(font.fontName))")
