import Foundation
import Testing
@testable import PyawwCore

/// Stage parity: the Core ML encoder vs the Python reference logits.
/// Uses the reference's own padded inputs (`mel_cmvn_padded` + biases) so
/// this isolates the model stage from the Swift feature extractor.
@Suite(.serialized)
struct ModelRunnerTests {
    @Test("example logits match the Python reference")
    func exampleLogitsMatchReference() throws {
        let modelURL = TestPaths.models.appendingPathComponent("BurmeseASR-Encoder-30s.mlpackage")
        let runner = try ModelRunner(modelURL: modelURL)
        let directory = TestPaths.intermediates.appendingPathComponent("example")

        let mel = try NPY(contentsOf: directory.appendingPathComponent("mel_cmvn_padded.npy"))
        let frameBias = try NPY(contentsOf: directory.appendingPathComponent("frame_bias.npy"))
        let conv1Bias = try NPY(contentsOf: directory.appendingPathComponent("conv1_bias.npy"))
        let reference = try NPY(contentsOf: directory.appendingPathComponent("logits_full.npy"))

        let logits = try runner.logits(mel: mel.floats, frameBias: frameBias.floats,
                                       conv1Bias: conv1Bias.floats)

        #expect(logits.frames == 751)
        #expect(logits.vocab == 2566)

        let referenceFrames = reference.shape[0]
        var flips = 0
        var maxDifference: Float = 0
        for t in 0..<referenceFrames {
            var referenceBest = 0
            var referenceBestValue = -Float.greatestFiniteMagnitude
            var actualBest = 0
            var actualBestValue = -Float.greatestFiniteMagnitude
            for v in 0..<logits.vocab {
                let expected = reference.floats[t * logits.vocab + v]
                if expected > referenceBestValue { referenceBestValue = expected; referenceBest = v }
                let actual = logits.values[t * logits.vocab + v]
                if actual > actualBestValue { actualBestValue = actual; actualBest = v }
                maxDifference = max(maxDifference, abs(expected - actual))
            }
            if referenceBest != actualBest { flips += 1 }
        }
        print("logits parity example: frames=\(referenceFrames) flips=\(flips) max|diff|=\(maxDifference)")
        #expect(flips == 0)
    }
}
