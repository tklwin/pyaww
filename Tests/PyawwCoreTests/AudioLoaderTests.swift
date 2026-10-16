import Foundation
import Testing
@testable import PyawwCore

/// Stage parity: AVAudioFile decode vs the Python sample fixtures.
/// The golden WAVs are 16 kHz PCM_16, so decode differences must be exactly zero.
@Suite
struct AudioLoaderTests {
    @Test("WAV decode matches Python samples")
    func wavDecodeMatchesPython() throws {
        for stem in ["g0001", "g0002", "g0003"] {
            let directory = TestPaths.intermediates.appendingPathComponent(stem)
            let reference = try NPY(contentsOf: directory.appendingPathComponent("samples_full.npy"))

            let loaded = try AudioLoader.load16kMono(url: TestPaths.audio.appendingPathComponent("\(stem).wav"))

            #expect(loaded.count == reference.floats.count, "\(stem): sample count")
            let difference = maxAbsDifference(loaded, reference.floats)
            print("audio parity \(stem): samples=\(loaded.count) max|diff|=\(difference)")
            #expect(difference <= 1e-7, "\(stem): max|diff| \(difference)")
        }
    }
}
