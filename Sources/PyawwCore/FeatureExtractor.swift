import Accelerate
import Foundation

/// Log-mel + CMVN feature extractor — the Swift port of the Python reference
/// front-end (torchaudio `MelSpectrogram` with defaults + `transcribe.py`):
/// reflect-padded 400-point STFT (periodic Hann), power spectrum, 80-bin HTK
/// mel filterbank, `log(clamp(min: 1e-5))`, then CMVN. Float32 end-to-end.
/// Contract: docs/model-spec.md §4.
public struct FeatureExtractor: Sendable {
    public struct Features: Sendable {
        /// (frameCount x 80) row-major, `[frame][melBin]` — the reference's
        /// (1, T, 80) transposed layout.
        public let samples: [Float]
        public let frameCount: Int
    }

    public enum ExtractionError: Error, CustomStringConvertible {
        case tooShort(samples: Int)

        public var description: String {
            switch self {
            case .tooShort(let count):
                return "need more than 200 samples for reflect padding, got \(count)"
            }
        }
    }

    private let filtersT: [Float]    // (201 x 80) transpose of the mel filterbank
    private let hann: [Float]        // (400,)
    private let mean: [Float]        // (80,)
    private let std: [Float]         // (80,)
    private let cosTable: [Float]    // (400 x 201): cos(2*pi*n*k/400)
    private let negSinTable: [Float] // (400 x 201): -sin(2*pi*n*k/400)

    public init(constants: ModelConstants) {
        let fftSize = ModelConstants.fftSize
        let bins = ModelConstants.fftBins
        let melBins = ModelConstants.melBins

        self.hann = constants.hannWindow
        self.mean = constants.cmvnMean
        self.std = constants.cmvnStd

        var filtersT = [Float](repeating: 0, count: bins * melBins)
        for mel in 0..<melBins {
            for k in 0..<bins {
                filtersT[k * melBins + mel] = constants.melFilters[mel * bins + k]
            }
        }
        self.filtersT = filtersT

        // The reference computes a 400-point real DFT per frame; express it as
        // two matrix multiplies against precomputed cos/sin tables (Double
        // accuracy, rounded to Float32 once).
        var cosT = [Float](repeating: 0, count: fftSize * bins)
        var negSinT = [Float](repeating: 0, count: fftSize * bins)
        for n in 0..<fftSize {
            for k in 0..<bins {
                let angle = 2.0 * Double.pi * Double(n) * Double(k) / Double(fftSize)
                cosT[n * bins + k] = Float(cos(angle))
                negSinT[n * bins + k] = Float(-sin(angle))
            }
        }
        self.cosTable = cosT
        self.negSinTable = negSinT
    }

    /// Computes the log-mel + CMVN features for 16 kHz mono Float32 samples.
    public func extract(samples: [Float]) throws -> Features {
        let sampleCount = samples.count
        let hop = ModelConstants.hopLength
        let fftSize = ModelConstants.fftSize
        let bins = ModelConstants.fftBins
        let melBins = ModelConstants.melBins
        let pad = fftSize / 2
        guard sampleCount > pad else { throw ExtractionError.tooShort(samples: sampleCount) }
        let frameCount = sampleCount / hop + 1

        // center=True reflect padding, torch semantics (no edge repetition):
        // padded[i] = x[pad - i] left, padded[pad + n + j] = x[n - 2 - j] right.
        var padded = [Float](repeating: 0, count: sampleCount + fftSize)
        padded.withUnsafeMutableBufferPointer { destination in
            samples.withUnsafeBufferPointer { source in
                let s = source.baseAddress!
                let d = destination.baseAddress!
                for i in 0..<pad { d[i] = s[pad - i] }
                d.advanced(by: pad).update(from: s, count: sampleCount)
                for j in 0..<pad { d[pad + sampleCount + j] = s[sampleCount - 2 - j] }
            }
        }

        // Hann-windowed frames (frameCount x 400).
        var windowed = [Float](repeating: 0, count: frameCount * fftSize)
        windowed.withUnsafeMutableBufferPointer { destination in
            padded.withUnsafeBufferPointer { source in
                hann.withUnsafeBufferPointer { window in
                    for frame in 0..<frameCount {
                        let d = destination.baseAddress! + frame * fftSize
                        let s = source.baseAddress! + frame * hop
                        for i in 0..<fftSize { d[i] = s[i] * window[i] }
                    }
                }
            }
        }

        // DFT per frame: real/imag = frames x (400 x 201) tables.
        let counts = frameCount * bins
        var real = [Float](repeating: 0, count: counts)
        var imag = [Float](repeating: 0, count: counts)
        windowed.withUnsafeBufferPointer { frames in
            cosTable.withUnsafeBufferPointer { table in
                real.withUnsafeMutableBufferPointer { output in
                    vDSP_mmul(frames.baseAddress!, 1, table.baseAddress!, 1, output.baseAddress!, 1,
                              vDSP_Length(frameCount), vDSP_Length(bins), vDSP_Length(fftSize))
                }
            }
        }
        windowed.withUnsafeBufferPointer { frames in
            negSinTable.withUnsafeBufferPointer { table in
                imag.withUnsafeMutableBufferPointer { output in
                    vDSP_mmul(frames.baseAddress!, 1, table.baseAddress!, 1, output.baseAddress!, 1,
                              vDSP_Length(frameCount), vDSP_Length(bins), vDSP_Length(fftSize))
                }
            }
        }

        // Power spectrum |X|^2.
        var power = [Float](repeating: 0, count: counts)
        for i in 0..<counts {
            power[i] = real[i] * real[i] + imag[i] * imag[i]
        }

        // Mel filterbank: (frames x 201) x (201 x 80).
        var mel = [Float](repeating: 0, count: frameCount * melBins)
        power.withUnsafeBufferPointer { spectrum in
            filtersT.withUnsafeBufferPointer { filters in
                mel.withUnsafeMutableBufferPointer { output in
                    vDSP_mmul(spectrum.baseAddress!, 1, filters.baseAddress!, 1, output.baseAddress!, 1,
                              vDSP_Length(frameCount), vDSP_Length(melBins), vDSP_Length(bins))
                }
            }
        }

        // log(clamp(min: 1e-5)) then CMVN, both elementwise.
        for i in 0..<mel.count {
            mel[i] = log(max(mel[i], 1e-5))
        }
        for frame in 0..<frameCount {
            let base = frame * melBins
            for b in 0..<melBins {
                mel[base + b] = (mel[base + b] - mean[b]) / (std[b] + 1e-9)
            }
        }
        return Features(samples: mel, frameCount: frameCount)
    }
}
