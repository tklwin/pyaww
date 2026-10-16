import Foundation

/// Greedy CTC decoder — a direct port of the reference loop in
/// `myanmar_asr/transcribe.py`: per-frame argmax, collapse repeats, drop the
/// blank id (0), skip unknown ids and empty tokens, join tokens with single
/// spaces. Deterministic first-occurrence tie-breaking, like `torch.argmax`.
public enum GreedyCTCDecoder {
    public static let blankID = 0

    public static func decode(logits: [Float], frames: Int, vocab: Int,
                              frameLimit: Int, tokenizer: Tokenizer) -> String {
        let limit = max(0, min(frameLimit, frames))
        var tokens: [String] = []
        tokens.reserveCapacity(limit / 4 + 1)
        var previous = -1
        for t in 0..<limit {
            let row = t * vocab
            var best = 0
            var bestValue = -Float.greatestFiniteMagnitude
            for v in 0..<vocab {
                let value = logits[row + v]
                if value > bestValue {
                    bestValue = value
                    best = v
                }
            }
            if best != previous && best != blankID {
                if let token = tokenizer.token(for: best), !token.isEmpty {
                    tokens.append(token)
                }
            }
            previous = best
        }
        return tokens.joined(separator: " ")
    }
}
