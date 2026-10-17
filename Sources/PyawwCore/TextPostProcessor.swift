import Foundation

/// v1 text post-processing: trim only. Myanmar word segmentation (Phase 4,
/// owner decision: default on) lives in `MMDTSegmenter` and the app applies
/// it after transcription (see docs/decisions.md).
public enum TextPostProcessor {
    public static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
