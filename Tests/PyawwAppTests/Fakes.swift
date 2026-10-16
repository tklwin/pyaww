import Foundation
import PyawwCore

/// Test doubles for the app-boundary protocols (SPEC §4).

@MainActor
final class FakeRecorder: AudioRecording {
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    var samplesToReturn: [Float] = []

    func startRecording() throws {
        if let startError { throw startError }
        startCount += 1
    }

    func stopRecording() async throws -> [Float] {
        stopCount += 1
        return samplesToReturn
    }

    func cancelRecording() {
        cancelCount += 1
    }
}

actor FakeTranscriber: Transcribing {
    private(set) var callCount = 0
    private let text: String
    private let delay: Duration

    init(text: String, delay: Duration = .zero) {
        self.text = text
        self.delay = delay
    }

    func transcribe(samples: [Float]) async throws -> String {
        callCount += 1
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return text
    }
}

@MainActor
final class FakeInserter: TextInserting {
    private(set) var inserted: [String] = []
    private(set) var restoreFlags: [Bool] = []
    var outcome: InsertionOutcome = .pasted

    func insert(_ text: String, restoreClipboard: Bool) async -> InsertionOutcome {
        inserted.append(text)
        restoreFlags.append(restoreClipboard)
        return outcome
    }
}
