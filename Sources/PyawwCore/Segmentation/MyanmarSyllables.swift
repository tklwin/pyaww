import Foundation

/// Swift port of the mmdt-tokenizer syllable splitter
/// (`tokenizer/syllable_tokenizer.py` — `_break_one`), MIT, Myanmar Data
/// Tech. See `docs/third-party.md`.
struct MyanmarSyllables {
    private let breakPattern: NSRegularExpression

    init(breakPattern: NSRegularExpression) {
        self.breakPattern = breakPattern
    }

    /// Splits `text` into writing syllables. A boundary is inserted before
    /// every character matched by the syllable-break pattern; the inserted
    /// spaces (and any original spaces) then separate the tokens.
    func breakIntoSyllables(_ text: String) -> [String] {
        let trimmed = MMDTText.trimWhitespace(text)
        guard !trimmed.isEmpty else { return [] }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let segmented = breakPattern.stringByReplacingMatches(
            in: trimmed, range: range, withTemplate: " $1")
        // Upstream: `.lstrip(separator).split(separator)` with `separator = " "`
        // — a plain single-space split, not a whitespace split.
        return segmented.components(separatedBy: " ").filter { !$0.isEmpty }
    }
}
