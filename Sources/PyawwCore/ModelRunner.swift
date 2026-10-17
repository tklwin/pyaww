import CoreML
import Foundation

/// Loads the fixed-30 s encoder Core ML asset and runs
/// `mel + frame_bias + conv1_bias -> logits`. Contract: docs/model-spec.md §3.
///
/// The first load compiles the `.mlpackage` with `MLModel.compileModel` (the
/// app must work without Xcode's `coremlc`) and caches the result under
/// Application Support; later loads are plain model reads.
public final class ModelRunner {
    public enum RunnerError: Error, CustomStringConvertible {
        case missingInput(String)
        case noOutput
        case unexpectedOutputShape([Int])
        case unsupportedOutputDataType(String)
        case predictionFailed(String)

        public var description: String {
            switch self {
            case .missingInput(let name): return "model is missing required input '\(name)'"
            case .noOutput: return "prediction produced no output"
            case .unexpectedOutputShape(let shape): return "unexpected output shape \(shape)"
            case .unsupportedOutputDataType(let dataType): return "unsupported output data type \(dataType)"
            case .predictionFailed(let reason): return "prediction failed: \(reason)"
            }
        }
    }

    public static let melKey = "mel"
    public static let frameBiasKey = "frame_bias"
    public static let conv1BiasKey = "conv1_bias"
    public static let melFrames = 3001
    public static let encoderFrames = 751
    public static let conv1Frames = 1501

    private let model: MLModel
    private let outputName: String

    public init(modelURL: URL, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        do {
            self.model = try MLModel(contentsOf: try Self.compiledModelURL(for: modelURL),
                                     configuration: configuration)
        } catch {
            // A stale or half-written cache entry must not brick the app:
            // drop it and compile once more.
            Self.invalidateCachedModel(for: modelURL)
            self.model = try MLModel(contentsOf: try Self.compiledModelURL(for: modelURL),
                                     configuration: configuration)
        }

        let inputNames = Set(model.modelDescription.inputDescriptionsByName.keys)
        for name in [Self.melKey, Self.frameBiasKey, Self.conv1BiasKey] where !inputNames.contains(name) {
            throw RunnerError.missingInput(name)
        }
        guard let name = model.modelDescription.outputDescriptionsByName.keys.first else {
            throw RunnerError.noOutput
        }
        self.outputName = name
    }

    public struct Logits {
        /// (frames x vocab) row-major.
        public let values: [Float]
        public let frames: Int
        public let vocab: Int
    }

    /// Runs the encoder. `mel` must be the zero-padded (1, 3001, 80) tensor;
    /// biases must follow the mask contract for the real audio length.
    ///
    /// Each call runs in an explicit `autoreleasepool`: Core ML allocates
    /// Objective-C objects (feature values, internal buffers) per prediction,
    /// and the actor executor has no run-loop drain — without the pool,
    /// memory grew ~4.7 MB per dictation (Phase 3 soak: 99 → 572 MB over
    /// 100 runs).
    public func logits(mel: [Float], frameBias: [Float], conv1Bias: [Float]) throws -> Logits {
        try autoreleasepool {
            let melArray = try Self.makeMultiArray(mel, shape: [1, Self.melFrames, ModelConstants.melBins])
            let frameBiasArray = try Self.makeMultiArray(frameBias, shape: [1, Self.encoderFrames])
            let conv1BiasArray = try Self.makeMultiArray(conv1Bias, shape: [1, Self.conv1Frames])

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                Self.melKey: MLFeatureValue(multiArray: melArray),
                Self.frameBiasKey: MLFeatureValue(multiArray: frameBiasArray),
                Self.conv1BiasKey: MLFeatureValue(multiArray: conv1BiasArray),
            ])

            let prediction: MLFeatureProvider
            do { prediction = try model.prediction(from: provider) }
            catch { throw RunnerError.predictionFailed(error.localizedDescription) }

            guard let output = prediction.featureValue(for: outputName)?.multiArrayValue else {
                throw RunnerError.noOutput
            }
            let shape = output.shape.map { $0.intValue }
            guard shape.count == 3, shape[0] == 1 else {
                throw RunnerError.unexpectedOutputShape(shape)
            }
            let frames = shape[1]
            let vocab = shape[2]
            let values = try Self.floats(from: output, frames: frames, vocab: vocab)
            return Logits(values: values, frames: frames, vocab: vocab)
        }
    }

    // MARK: - Helpers

    private static func makeMultiArray(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        let destination = array.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<values.count { destination[i] = values[i] }
        return array
    }

    /// Reads a rank-3 (1, frames, vocab) multiarray into row-major Float32.
    /// The w16 asset's logits output is Float16 (the conversion keeps the
    /// classifier in fp16), so the reader must honour the array's data type.
    private static func floats(from array: MLMultiArray, frames: Int, vocab: Int) throws -> [Float] {
        var values = [Float](repeating: 0, count: frames * vocab)
        let rowStride = array.strides[1].intValue
        let columnStride = array.strides[2].intValue
        switch array.dataType {
        case .float16:
            let source = array.dataPointer.assumingMemoryBound(to: UInt16.self)
            for t in 0..<frames {
                let row = t * rowStride
                for v in 0..<vocab {
                    values[t * vocab + v] = Float(Float16(bitPattern: source[row + v * columnStride]))
                }
            }
        case .float32:
            let source = array.dataPointer.assumingMemoryBound(to: Float.self)
            for t in 0..<frames {
                let row = t * rowStride
                for v in 0..<vocab {
                    values[t * vocab + v] = source[row + v * columnStride]
                }
            }
        default:
            throw RunnerError.unsupportedOutputDataType(String(describing: array.dataType))
        }
        return values
    }

    /// Compiles the `.mlpackage` once into the app's Application Support cache
    /// (SPEC §3 first-launch compile fallback) and reuses it afterwards.
    /// Serialized process-wide: concurrent first loads must not race to write
    /// the cache directory.
    private static let compileLock = NSLock()

    private static func compiledModelURL(for modelURL: URL) throws -> URL {
        if modelURL.pathExtension == "mlmodelc" { return modelURL }
        compileLock.lock()
        defer { compileLock.unlock() }

        let fileManager = FileManager.default
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let cacheDirectory = base.appendingPathComponent("Pyaww/CompiledModels", isDirectory: true)
        let cached = cacheDirectory
            .appendingPathComponent(modelURL.deletingPathExtension().lastPathComponent + ".mlmodelc")
        if fileManager.fileExists(atPath: cached.path) { return cached }
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let compiled = try MLModel.compileModel(at: modelURL)
        let staged = cacheDirectory
            .appendingPathComponent(cached.lastPathComponent + ".tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: compiled, to: staged)
        do {
            try fileManager.moveItem(at: staged, to: cached)
        } catch {
            // Another process won the race; its cache is fine if it exists.
            guard fileManager.fileExists(atPath: cached.path) else { throw error }
        }
        return cached
    }

    private static func invalidateCachedModel(for modelURL: URL) {
        guard modelURL.pathExtension != "mlmodelc" else { return }
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: false) else { return }
        let cached = base.appendingPathComponent("Pyaww/CompiledModels", isDirectory: true)
            .appendingPathComponent(modelURL.deletingPathExtension().lastPathComponent + ".mlmodelc")
        try? FileManager.default.removeItem(at: cached)
    }
}
