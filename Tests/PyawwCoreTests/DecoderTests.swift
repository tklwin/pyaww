import Foundation
import Testing
@testable import PyawwCore

@Suite
struct DecoderTests {
    /// Synthetic logits: [tok2, tok2, blank, tok3, tok3, blank, tok2]
    /// must collapse to "tok2 tok3 tok2".
    @Test("collapses repeats and drops blanks")
    func collapseRepeatsAndDropBlanks() throws {
        let tokenizer = Tokenizer(constants: try loadTestConstants())
        let sequence = [2, 2, 0, 3, 3, 0, 2]
        let vocab = 32
        var logits = [Float](repeating: -1, count: sequence.count * vocab)
        for (frame, id) in sequence.enumerated() { logits[frame * vocab + id] = 1 }

        let text = GreedyCTCDecoder.decode(logits: logits, frames: sequence.count, vocab: vocab,
                                           frameLimit: sequence.count, tokenizer: tokenizer)
        let expected = [2, 3, 2].compactMap { tokenizer.token(for: $0) }.joined(separator: " ")
        #expect(text == expected)
    }

    @Test("frame limit cuts the tail")
    func frameLimitCutsTail() throws {
        let tokenizer = Tokenizer(constants: try loadTestConstants())
        let sequence = [2, 0, 3]
        let vocab = 32
        var logits = [Float](repeating: -1, count: sequence.count * vocab)
        for (frame, id) in sequence.enumerated() { logits[frame * vocab + id] = 1 }

        let text = GreedyCTCDecoder.decode(logits: logits, frames: sequence.count, vocab: vocab,
                                           frameLimit: 1, tokenizer: tokenizer)
        #expect(text == tokenizer.token(for: 2))
    }

    @Test("post-processor trims whitespace")
    func postProcessorTrims() {
        #expect(TextPostProcessor.clean("  က ခ \n") == "က ခ")
        #expect(TextPostProcessor.clean("") == "")
    }

    @Test("tokenizer round-trips the full vocabulary")
    func tokenizerRoundTrip() throws {
        let constants = try loadTestConstants()
        let tokenizer = Tokenizer(constants: constants)
        #expect(tokenizer.vocabSize == 2566)
        for (token, id) in constants.tokenToID where !token.isEmpty {
            #expect(tokenizer.token(for: id) == token, "id \(id)")
        }
    }
}
