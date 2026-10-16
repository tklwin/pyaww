import Foundation

/// v1 text post-processing: trim only (SPEC §4 — richer rules come with the
/// app if the owner asks for them).
public enum TextPostProcessor {
    public static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
