import Foundation

/// vocab.json wrapper: id -> token lookup for the decoder.
public struct Tokenizer: Sendable {
    private let idToToken: [Int: String]

    public var vocabSize: Int { idToToken.count }

    public init(constants: ModelConstants) {
        self.idToToken = constants.idToToken
    }

    public func token(for id: Int) -> String? {
        idToToken[id]
    }
}
