import Foundation
import Testing
@testable import PyawwCore

/// Full pipeline: WAV -> text must equal the Python reference text.
/// (`g2063` is deliberately excluded — its one knife-edge frame is the
/// owner-approved w16 tolerance, see docs/model-spec.md §6.)
@Suite(.serialized)
struct EndToEndTests {
    let stems = ["g0001", "g0002", "g0003", "g1013", "g2057", "g3097"]

    @Test("golden subset texts match the reference")
    func goldenTextsMatchReference() async throws {
        let transcriber = try Transcriber(modelDirectory: TestPaths.models)
        for stem in stems {
            let wav = TestPaths.audio.appendingPathComponent("\(stem).wav")
            let text = try await transcriber.transcribe(audioFileURL: wav)
            let expected = try expectedText(for: stem)
            #expect(text == expected, "\(stem)")
        }
    }

    @Test("silence decodes to empty text")
    func silenceDecodesToEmptyText() async throws {
        let transcriber = try Transcriber(modelDirectory: TestPaths.models)
        let silence = [Float](repeating: 0, count: 16_000)
        let text = try await transcriber.transcribe(samples: silence)
        #expect(text == "")
    }

    @Test("input below 0.5 s returns empty text")
    func tooShortReturnsEmptyText() async throws {
        let transcriber = try Transcriber(modelDirectory: TestPaths.models)
        let tooShort = [Float](repeating: 0.1, count: 7_999)
        let text = try await transcriber.transcribe(samples: tooShort)
        #expect(text == "")
    }

    @Test("input over 30 s throws")
    func tooLongThrows() async throws {
        let transcriber = try Transcriber(modelDirectory: TestPaths.models)
        let tooLong = [Float](repeating: 0, count: 480_001)
        await #expect(throws: Transcriber.TranscribeError.self) {
            _ = try await transcriber.transcribe(samples: tooLong)
        }
    }
}
