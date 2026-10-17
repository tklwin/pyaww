import Foundation

/// Trie node for the mmdt word-segmentation lexicons
/// (`rule_segmenter/scanner.py` — `build_trie`).
final class MMDTTrieNode {
    var children: [String: MMDTTrieNode] = [:]
    var endTag: String?
}

/// Loads `lexicons.json` (mmdt-tokenizer 0.1.3, MIT) into one trie per tag.
enum MMDTLexicon {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    /// - Note: upstream normalizes every part to NFC before building the
    ///   trie (`rule_segmenter/lexicon.py`); mirrored here.
    static func load(from url: URL) throws -> [String: MMDTTrieNode] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError(description: "cannot read \(url.path): \(error)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError(description: "lexicons.json: expected a top-level object")
        }
        var tries: [String: MMDTTrieNode] = [:]
        for (tag, value) in root {
            guard let entries = value as? [Any] else { continue }
            let trie = MMDTTrieNode()
            for entry in entries {
                let parts: [String]
                if let word = entry as? String {
                    parts = [word]
                } else if let wordParts = entry as? [Any] {
                    parts = wordParts.compactMap { $0 as? String }
                } else {
                    continue
                }
                var node = trie
                for part in parts {
                    let key = part.precomposedStringWithCanonicalMapping
                    if let child = node.children[key] {
                        node = child
                    } else {
                        let child = MMDTTrieNode()
                        node.children[key] = child
                        node = child
                    }
                }
                node.endTag = tag
            }
            tries[tag] = trie
        }
        return tries
    }
}
