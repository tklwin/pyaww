import CoreML
import Foundation

/// End-to-end pipeline: audio -> text.
///
/// AudioResampler (16 kHz mono) -> FeatureExtractor -> fixed-30 s padding and
/// mask contract -> ModelRunner -> greedy CTC -> trim.
/// Input/output contract: docs/model-spec.md §3–§5.
public final class Transcriber {
    public enum TranscribeError: Error, CustomStringConvertible {
        case audioTooLong(samples: Int)
        case modelMissing(String)

        public var description: String {
            switch self {
            case .audioTooLong(let samples):
                return "audio is too long for the fixed 30 s model (\(samples) samples, max \(Transcriber.maxSamples))"
            case .modelMissing(let path):
                return "model package not found at \(path)"
            }
        }
    }

    public static let sampleRate = 16_000
    /// I-9: the model takes a fixed 30 s of audio.
    public static let maxSamples = 480_000
    /// The reference returns "" below 0.5 s.
    public static let minSamples = 8_000
    public static let melFrames = ModelRunner.melFrames
    public static let maxEncoderFrames = ModelRunner.encoderFrames
    public static let maxConv1Frames = ModelRunner.conv1Frames
    /// Mask contract value for padded rows (model-spec.md §3).
    public static let padBias: Float = -10_000

    private let extractor: FeatureExtractor
    private let runner: ModelRunner
    private let tokenizer: Tokenizer

    public init(modelDirectory: URL, computeUnits: MLComputeUnits = .all) throws {
        let constants = try ModelConstants.load(from: modelDirectory)
        self.extractor = FeatureExtractor(constants: constants)
        self.tokenizer = Tokenizer(constants: constants)
        let modelURL = modelDirectory.appendingPathComponent("BurmeseASR-Encoder-30s.mlpackage")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscribeError.modelMissing(modelURL.path)
        }
        self.runner = try ModelRunner(modelURL: modelURL, computeUnits: computeUnits)
    }

    /// Transcribes an audio file (any AVFoundation-readable format).
    public func transcribe(audioFileURL: URL) throws -> String {
        try transcribe(samples: AudioLoader.load16kMono(url: audioFileURL))
    }

    /// Transcribes 16 kHz mono Float32 samples.
    public func transcribe(samples: [Float]) throws -> String {
        guard samples.count >= Self.minSamples else { return "" }
        guard samples.count <= Self.maxSamples else {
            throw TranscribeError.audioTooLong(samples: samples.count)
        }

        let features = try extractor.extract(samples: samples)
        let melFrameCount = features.frameCount
        let encoderFrames = Self.encoderFrames(forMelFrames: melFrameCount)
        let conv1Frames = Self.conv1Frames(forMelFrames: melFrameCount)

        // Zero-pad features to the fixed 3001 frames (pad rows must be zeros).
        var mel = [Float](repeating: 0, count: Self.melFrames * ModelConstants.melBins)
        let featureCount = melFrameCount * ModelConstants.melBins
        mel.withUnsafeMutableBufferPointer { destination in
            features.samples.withUnsafeBufferPointer { source in
                destination.baseAddress!.update(from: source.baseAddress!, count: featureCount)
            }
        }

        // Mask contract: -10000 from R (attention keys, GLU) and l1 (conv1).
        var frameBias = [Float](repeating: 0, count: Self.maxEncoderFrames)
        for i in encoderFrames..<Self.maxEncoderFrames { frameBias[i] = Self.padBias }
        var conv1Bias = [Float](repeating: 0, count: Self.maxConv1Frames)
        for i in conv1Frames..<Self.maxConv1Frames { conv1Bias[i] = Self.padBias }

        let logits = try runner.logits(mel: mel, frameBias: frameBias, conv1Bias: conv1Bias)
        let text = GreedyCTCDecoder.decode(logits: logits.values, frames: logits.frames,
                                           vocab: logits.vocab, frameLimit: encoderFrames,
                                           tokenizer: tokenizer)
        return TextPostProcessor.clean(text)
    }

    /// R = max(1, ((T + 1)/2 + 1)/2) — the owner's `calc_subsampled_lens`.
    public static func encoderFrames(forMelFrames t: Int) -> Int {
        max(1, ((t + 1) / 2 + 1) / 2)
    }

    /// l1 = (T + 1)/2 — conv1 rows that survive the reference computation.
    public static func conv1Frames(forMelFrames t: Int) -> Int {
        (t + 1) / 2
    }
}
