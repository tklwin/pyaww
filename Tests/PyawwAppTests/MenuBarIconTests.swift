import AppKit
import Testing
@testable import PyawwApp

/// The menu bar wave factory (owner decision 2026-10-17).
@MainActor
struct MenuBarIconTests {
    @Test func statesExistAtTheMenuBarCanvas() {
        for image in [MenuBarIcon.idle, MenuBarIcon.transcribing, MenuBarIcon.recording] {
            #expect(image.size == MenuBarIcon.canvas)
            #expect(!image.representations.isEmpty)
        }
    }

    @Test func idleAndTranscribingAreTemplates() {
        #expect(MenuBarIcon.idle.isTemplate)
        #expect(MenuBarIcon.transcribing.isTemplate)
    }

    @Test func recordingCarriesARealColour() {
        #expect(!MenuBarIcon.recording.isTemplate)
    }

    /// Guards the silent-empty-drawing failure mode (draws landing nowhere),
    /// the class of bug vorssaint's icon tool warns about.
    @Test func everyStateDrawsVisibleInk() {
        for image in [MenuBarIcon.idle, MenuBarIcon.transcribing, MenuBarIcon.recording] {
            #expect(inkPixelCount(image) > 50)
        }
    }

    /// The wave is wide and flat; a placeholder that draws a corner dot or
    /// nothing at all would fail here.
    @Test func inkSpansTheWaveNotASpeck() {
        let extent = inkExtent(MenuBarIcon.idle)
        #expect(extent.maxX - extent.minX > 20) // 36 px canvas, 16 pt ink ≈ 32 px
    }

    // MARK: - Rasterization helpers

    private func rasterize(_ image: NSImage) -> NSBitmapImageRep? {
        let px = 36
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func inkPixelCount(_ image: NSImage) -> Int {
        inkExtent(image).count
    }

    private func inkExtent(_ image: NSImage) -> (count: Int, minX: Int, maxX: Int) {
        guard let rep = rasterize(image) else { return (0, 0, 0) }
        var count = 0
        var minX = rep.pixelsWide
        var maxX = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                count += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        return (count, minX, maxX)
    }
}