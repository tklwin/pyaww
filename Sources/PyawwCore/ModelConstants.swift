import Foundation

/// I-8 feature-extraction constants, exported from the Python reference by
/// `scripts/export_fe_constants.py`. `load(from:)` reads the JSON files that
/// live next to the Core ML model (the `Models/` directory in dev, the app
/// bundle in Phase 2). Shapes and semantics: docs/model-spec.md §4.
public struct ModelConstants: Sendable {
    /// (80 x 201) mel filterbank, row-major: row = mel band, column = FFT bin.
    public let melFilters: [Float]
    /// (400,) periodic Hann window.
    public let hannWindow: [Float]
    /// (80,) CMVN mean.
    public let cmvnMean: [Float]
    /// (80,) CMVN std.
    public let cmvnStd: [Float]
    /// Token -> id, as in vocab.json (2566 entries).
    public let tokenToID: [String: Int]
    /// id -> token (inverse of `tokenToID`; duplicate ids are rejected).
    public let idToToken: [Int: String]

    public static let melBins = 80
    public static let fftSize = 400
    public static let fftBins = 201
    public static let hopLength = 160

    public enum LoadError: Error, CustomStringConvertible {
        case unreadableConstant(name: String, reason: String)
        case badShape(name: String, expected: [Int], actual: [Int])
        case duplicateTokenID(id: Int, first: String, second: String)

        public var description: String {
            switch self {
            case .unreadableConstant(let name, let reason):
                return "cannot read \(name): \(reason)"
            case .badShape(let name, let expected, let actual):
                return "\(name): expected shape \(expected), got \(actual)"
            case .duplicateTokenID(let id, let first, let second):
                return "vocab.json has duplicate id \(id) (\(first), \(second))"
            }
        }
    }

    public static func load(from directory: URL) throws -> ModelConstants {
        let filters: [[Float]] = try decode(directory, "mel_filters.json")
        let hann: [Float] = try decode(directory, "hann_window.json")
        let cmvn: CMVN = try decode(directory, "cmvn.json")
        let vocab: [String: Int] = try decode(directory, "vocab.json")

        guard filters.count == melBins,
              filters.allSatisfy({ $0.count == fftBins }) else {
            throw LoadError.badShape(
                name: "mel_filters.json",
                expected: [melBins, fftBins],
                actual: [filters.count, filters.first?.count ?? 0])
        }
        guard hann.count == fftSize else {
            throw LoadError.badShape(
                name: "hann_window.json", expected: [fftSize],
                actual: [hann.count])
        }
        guard cmvn.mean.count == melBins, cmvn.std.count == melBins else {
            throw LoadError.badShape(
                name: "cmvn.json", expected: [melBins, melBins],
                actual: [cmvn.mean.count, cmvn.std.count])
        }
        guard !vocab.isEmpty else {
            throw LoadError.badShape(name: "vocab.json", expected: [1], actual: [0])
        }

        var idToToken = [Int: String](minimumCapacity: vocab.count)
        for (token, id) in vocab {
            if let existing = idToToken[id], existing != token {
                throw LoadError.duplicateTokenID(id: id, first: existing, second: token)
            }
            idToToken[id] = token
        }

        var flatFilters = [Float]()
        flatFilters.reserveCapacity(melBins * fftBins)
        for row in filters { flatFilters.append(contentsOf: row) }

        return ModelConstants(
            melFilters: flatFilters,
            hannWindow: hann,
            cmvnMean: cmvn.mean,
            cmvnStd: cmvn.std,
            tokenToID: vocab,
            idToToken: idToToken)
    }

    private struct CMVN: Decodable {
        let mean: [Float]
        let std: [Float]
    }

    private static func decode<T: Decodable>(_ directory: URL, _ name: String) throws -> T {
        let url = directory.appendingPathComponent(name)
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw LoadError.unreadableConstant(name: name, reason: error.localizedDescription) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw LoadError.unreadableConstant(name: name, reason: "\(error)") }
    }
}
