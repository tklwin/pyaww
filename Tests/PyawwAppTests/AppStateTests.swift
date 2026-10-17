import Foundation
import Testing
@testable import PyawwApp
import PyawwCore

/// State-machine tests (SPEC §6.6) with fake recorder/transcriber/inserter.
@MainActor
@Suite(.serialized)
struct AppStateTests {
    private func makeState(
        minimumDuration: Double = 0.3,
        maximumDuration: Double = 30,
        transcriberText: String = "မင်္ဂလာပါ",
        transcriberDelay: Duration = .zero,
        insertionOutcome: InsertionOutcome = .pasted,
        wordSegmentation: Bool = false
    ) throws -> (AppState, FakeRecorder, FakeTranscriber, FakeInserter) {
        let defaults = try #require(UserDefaults(suiteName: "pyaww-tests-\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: defaults)
        settings.minimumDuration = minimumDuration
        settings.maximumDuration = maximumDuration
        settings.wordSegmentation = wordSegmentation
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber(text: transcriberText, delay: transcriberDelay)
        let inserter = FakeInserter()
        inserter.outcome = insertionOutcome
        let state = AppState(settings: settings, recorder: recorder, inserter: inserter)
        state.modelDidLoad(transcriber)
        return (state, recorder, transcriber, inserter)
    }

    /// Non-silent 16 kHz mono test signal.
    private func tone(seconds: Double, amplitude: Float = 0.25) -> [Float] {
        let count = Int(16_000 * seconds)
        return (0..<count).map { amplitude * sinf(2 * .pi * 220 * Float($0) / 16_000) }
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for condition")
    }

    @Test func fullCycleTranscribesAndPastes() async throws {
        let (state, recorder, transcriber, inserter) = try makeState()
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        #expect(state.phase == .recording)
        #expect(recorder.startCount == 1)

        state.hotkeyReleased()
        await state.recordingStopTask?.value
        await state.transcriptionTask?.value

        #expect(state.phase == .idle)
        #expect(await transcriber.callCount == 1)
        #expect(inserter.inserted == ["မင်္ဂလာပါ"])
        #expect(inserter.restoreFlags == [true])
    }

    @Test func shortRecordingIsIgnored() async throws {
        let (state, recorder, transcriber, inserter) = try makeState(minimumDuration: 1.0)
        recorder.samplesToReturn = tone(seconds: 0.5)

        state.hotkeyPressed()
        state.hotkeyReleased()
        await state.recordingStopTask?.value

        #expect(state.phase == .idle)
        #expect(await transcriber.callCount == 0)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func silentRecordingIsIgnored() async throws {
        let (state, recorder, transcriber, inserter) = try makeState()
        recorder.samplesToReturn = [Float](repeating: 0, count: 16_000)

        state.hotkeyPressed()
        state.hotkeyReleased()
        await state.recordingStopTask?.value

        #expect(state.phase == .idle)
        #expect(await transcriber.callCount == 0)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func pressWhileTranscribingIsIgnored() async throws {
        let (state, recorder, _, _) = try makeState(transcriberDelay: .milliseconds(300))
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        state.hotkeyReleased()
        try await waitUntil { state.phase == .transcribing }

        state.hotkeyPressed()
        #expect(recorder.startCount == 1)

        await state.transcriptionTask?.value
        #expect(state.phase == .idle)
    }

    @Test func escapeCancelsRecording() async throws {
        let (state, recorder, transcriber, inserter) = try makeState()
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        state.cancel()

        #expect(state.phase == .idle)
        #expect(recorder.cancelCount == 1)
        #expect(await transcriber.callCount == 0)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func maxDurationStopsAndNotices() async throws {
        let (state, recorder, transcriber, inserter) = try makeState(maximumDuration: 0.2)
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        try await waitUntil { state.notice != nil }
        await state.recordingStopTask?.value
        await state.transcriptionTask?.value

        #expect(state.phase == .idle)
        #expect(state.notice?.contains("limit") == true)
        #expect(await transcriber.callCount == 1)
        #expect(inserter.inserted == ["မင်္ဂလာပါ"])
    }

    /// The tap can deliver one last buffer after the stop decision; a
    /// recording a hair over the model's fixed 30 s window must be clipped,
    /// not fail (owner's live >30 s test, 2026-10-18).
    @Test func overWindowRecordingIsClippedToModelWindow() async throws {
        let (state, recorder, transcriber, _) = try makeState()
        recorder.samplesToReturn = tone(seconds: 30.2)

        state.hotkeyPressed()
        state.hotkeyReleased()
        await state.recordingStopTask?.value
        await state.transcriptionTask?.value

        #expect(state.phase == .idle)
        #expect(await transcriber.lastSampleCount == Transcriber.maxSamples)
    }

    @Test func insertionFailureShowsError() async throws {
        let (state, recorder, _, _) = try makeState(
            insertionOutcome: .copiedToClipboardOnly(reason: "Accessibility permission is off"))
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        state.hotkeyReleased()
        await state.recordingStopTask?.value
        await state.transcriptionTask?.value

        guard case .error(let message) = state.phase else {
            Issue.record("expected error phase, got \(state.phase)")
            return
        }
        #expect(message.contains("Accessibility"))
    }

    @Test func pressBeforeModelReadyShowsError() async throws {
        let defaults = try #require(UserDefaults(suiteName: "pyaww-tests-\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: defaults)
        let recorder = FakeRecorder()
        let state = AppState(settings: settings, recorder: recorder, inserter: FakeInserter())

        state.hotkeyPressed()

        #expect(recorder.startCount == 0)
        guard case .error(let message) = state.phase else {
            Issue.record("expected error phase, got \(state.phase)")
            return
        }
        #expect(message.contains("loading"))
    }

    @Test func emptyTranscriptionDoesNotPaste() async throws {
        let (state, recorder, _, inserter) = try makeState(transcriberText: "")
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        state.hotkeyReleased()
        await state.recordingStopTask?.value
        await state.transcriptionTask?.value

        #expect(state.phase == .idle)
        #expect(inserter.inserted.isEmpty)
        #expect(state.notice != nil)
    }

    @Test func wordSegmentationDefaultsOn() throws {
        let defaults = try #require(UserDefaults(suiteName: "pyaww-tests-\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.wordSegmentation)
    }

    @Test func segmentationAppliesBeforeInsertion() async throws {
        let (state, recorder, _, inserter) = try makeState(wordSegmentation: true)
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        state.hotkeyReleased()
        await state.recordingStopTask?.value
        await state.transcriptionTask?.value

        #expect(state.phase == .idle)
        #expect(state.isWordSegmentationAvailable)
        #expect(inserter.inserted == ["မင်္ဂလာ ပါ"])
    }

    @Test func segmentationOffPastesRawText() async throws {
        let (state, recorder, _, inserter) = try makeState(wordSegmentation: false)
        recorder.samplesToReturn = tone(seconds: 1)

        state.hotkeyPressed()
        state.hotkeyReleased()
        await state.recordingStopTask?.value
        await state.transcriptionTask?.value

        #expect(inserter.inserted == ["မင်္ဂလာပါ"])
    }
}
