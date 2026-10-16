import Foundation
import Testing
@testable import PyawwCore

/// Stage parity: Swift features vs the Python reference tensors saved by
/// `scripts/export_fixtures.py` (Gate 1 feature tolerance: model-spec.md §6).
@Suite(.serialized)
struct FeatureExtractorTests {
    let stems = ["example", "g0001", "g0002", "g0003"]

    @Test("features match Python within tolerance")
    func featuresMatchPython() throws {
        let extractor = FeatureExtractor(constants: try loadTestConstants())
        for stem in stems {
            let directory = TestPaths.intermediates.appendingPathComponent(stem)
            let samples = try NPY(contentsOf: directory.appendingPathComponent("samples_full.npy"))
            let reference = try NPY(contentsOf: directory.appendingPathComponent("mel_cmvn_full.npy"))

            let features = try extractor.extract(samples: samples.floats)

            #expect(features.frameCount == reference.shape[0], "\(stem): frame count")
            #expect(features.samples.count == reference.floats.count, "\(stem): element count")
            let difference = maxAbsDifference(features.samples, reference.floats)
            print("feature parity \(stem): frames=\(features.frameCount) max|diff|=\(difference)")
            #expect(difference <= 1e-3, "\(stem): max|diff| \(difference)")
        }
    }
}
