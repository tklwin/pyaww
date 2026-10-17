import AppKit

/// The Pyaww menu bar wave (owner decision 2026-10-17): the same voice
/// ribbon as the app icon, tuned for menu bar size — the stroke is
/// optically bolded from the icon's 6.25% to ~9.7% of the ink width,
/// the way type has optical sizes.
///
/// Drawn as a vector, so every display scale stays crisp — no bundled
/// PNG pairs to go blurry on Retina (the pattern learned from
/// vorssaint's `BlackHoleGlyph`, which needs them only because its
/// glyph comes from a bitmap logo):
/// - idle and transcribing are *template* images — macOS paints them
///   black on light and white on dark menu bars automatically;
/// - recording is a real colour (`isTemplate = false`), so "live" reads
///   at a glance. Red is the universal recording signal.
@MainActor
enum MenuBarIcon {
    /// Logical size of the glyph in the menu bar, in points.
    static let canvas = NSSize(width: 18, height: 18)

    static let idle = wave(tint: nil, alpha: 1)
    static let transcribing = wave(tint: nil, alpha: 0.45)
    static let recording = wave(tint: .systemRed, alpha: 1)

    /// The wave "B" geometry from the app icon (uniformly 11/12 of the
    /// wide variant; cap tips on the 128/896 design-grid lines — see
    /// `Design/`), drawn with the design's centre at the canvas centre.
    private static func wave(tint: NSColor?, alpha: CGFloat) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { rect in
            // Ink (tips + caps) spans 768 design units; aim for 16 pt of
            // the 18 pt canvas, leaving the usual menu bar breathing room.
            let scale = 16.0 / 768.0
            func x(_ value: CGFloat) -> CGFloat { rect.midX + (value - 512) * scale }
            func y(_ value: CGFloat) -> CGFloat { rect.midY - (value - 512) * scale }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x(160), y: y(570.6667)))
            path.curve(to: NSPoint(x: x(394.6667), y: y(394.6667)),
                       controlPoint1: NSPoint(x: x(277.3333), y: y(570.6667)),
                       controlPoint2: NSPoint(x: x(277.3333), y: y(394.6667)))
            path.curve(to: NSPoint(x: x(629.3333), y: y(629.3333)),
                       controlPoint1: NSPoint(x: x(512), y: y(394.6667)),
                       controlPoint2: NSPoint(x: x(512), y: y(629.3333)))
            path.curve(to: NSPoint(x: x(864), y: y(453.3333)),
                       controlPoint1: NSPoint(x: x(746.6667), y: y(629.3333)),
                       controlPoint2: NSPoint(x: x(746.6667), y: y(453.3333)))
            path.lineWidth = 84 * scale // 1.75 pt at this scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (tint ?? .black).withAlphaComponent(alpha).setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = tint == nil
        return image
    }
}
