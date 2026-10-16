import Foundation
import PyawwCore

/// Repo-relative paths for the committed Phase 0 fixtures.
enum TestPaths {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // PyawwCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static var fixtures: URL { repoRoot.appendingPathComponent("Tests/Fixtures") }
    static var intermediates: URL { fixtures.appendingPathComponent("intermediates") }
    static var audio: URL { fixtures.appendingPathComponent("audio") }
    static var expected: URL { fixtures.appendingPathComponent("expected") }
    static var models: URL { repoRoot.appendingPathComponent("Models") }
}

func loadTestConstants() throws -> ModelConstants {
    try ModelConstants.load(from: TestPaths.models)
}

func expectedText(for stem: String) throws -> String {
    try String(contentsOf: TestPaths.expected.appendingPathComponent("\(stem).txt"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func maxAbsDifference(_ a: [Float], _ b: [Float]) -> Float {
    precondition(a.count == b.count)
    var maxDifference: Float = 0
    for i in 0..<a.count {
        maxDifference = max(maxDifference, abs(a[i] - b[i]))
    }
    return maxDifference
}
