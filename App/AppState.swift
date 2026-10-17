import AppKit
import Foundation
import Observation
import os
import PyawwCore

/// The app's explicit state machine (SPEC §6.6):
/// `idle -> recording -> transcribing -> idle`, `error` recoverable.
///
/// Behavior decisions (documented in docs/decisions.md):
/// - a hotkey press while recording/transcribing is ignored (nothing queued);
/// - Esc cancels recording without pasting, or abandons an in-flight
///   transcription (the paste is skipped even though the model call itself
///   cannot be interrupted);
/// - at the maximum duration the recorder stops itself, transcribes what was
///   captured, and shows a notice (FR-6).
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    private enum StopReason {
        case keyRelease
        case limit
    }

    /// Peak below this is treated as silence (FR-5). About -80 dBFS: room
    /// tone and speech are far above; this only catches digital silence.
    private static let silencePeakThreshold: Float = 1e-4

    private(set) var phase: Phase = .idle
    private(set) var isModelReady = false
    /// Informational, auto-clearing message (e.g. the truncation notice).
    private(set) var notice: String?

    private let settings: SettingsStore
    private let recorder: any AudioRecording
    private let inserter: any TextInserting
    private let logger = Logger(subsystem: "com.tklwin.pyaww", category: "state")
    /// Phase 4: Myanmar word segmentation (owner decision: default on).
    /// `nil` when the lexicon bundle is missing — transcription still works,
    /// pasting the raw model text (logged at startup).
    private let segmenter: MMDTSegmenter?

    private var transcriber: (any Transcribing)?
    /// Internal so tests can await pipeline completion.
    private(set) var recordingStopTask: Task<Void, Never>?
    private(set) var transcriptionTask: Task<Void, Never>?
    private var noticeDismissTask: Task<Void, Never>?

    init(settings: SettingsStore, recorder: any AudioRecording, inserter: any TextInserting) {
        self.settings = settings
        self.recorder = recorder
        self.inserter = inserter
        let loadedSegmenter: MMDTSegmenter?
        var segmenterError: String?
        do {
            loadedSegmenter = try MMDTSegmenter()
        } catch {
            loadedSegmenter = nil
            segmenterError = String(describing: error)
        }
        self.segmenter = loadedSegmenter
        if let segmenterError {
            logger.error("word segmentation unavailable: \(segmenterError, privacy: .public)")
        } else {
            logger.info("word segmentation ready")
        }
    }

    /// True when the Phase 4 segmentation lexicon loaded (Settings shows it).
    var isWordSegmentationAvailable: Bool { segmenter != nil }

    // MARK: - Model lifecycle

    func modelDidLoad(_ transcriber: any Transcribing) {
        self.transcriber = transcriber
        isModelReady = true
        if case .error(let message) = phase, message.contains("model") {
            phase = .idle
        }
    }

    func modelLoadFailed(_ message: String) {
        isModelReady = false
        logger.error("the speech model failed to load: \(message, privacy: .public)")
        showError("speech model failed to load — reopen Pyaww")
    }

    // MARK: - Menu bar presentation

    var statusText: String {
        switch phase {
        case .idle: return isModelReady ? "Ready" : "Loading model…"
        case .recording: return "Recording — release to transcribe (Esc cancels)"
        case .transcribing: return "Transcribing…"
        case .error(let message): return message
        }
    }

    // MARK: - Hotkey / recording (FR-2, FR-4, FR-5, FR-6)

    func hotkeyPressed() {
        switch phase {
        case .recording, .transcribing:
            // Ignored while busy (nothing is queued) — see the type comment.
            return
        case .idle, .error:
            break
        }
        guard isModelReady else {
            showError("still loading — try again in a moment")
            return
        }
        do {
            try recorder.startRecording()
        } catch {
            logger.error("could not start recording: \(String(describing: error), privacy: .public)")
            showError("could not start the recording")
            return
        }
        phase = .recording
        playCue(named: "Tink")
        startRecordingStopTimer()
    }

    func hotkeyReleased() {
        guard phase == .recording else { return }
        recordingStopTask?.cancel()
        recordingStopTask = Task { await self.finishRecording(stoppedBy: .keyRelease) }
    }

    /// Esc while recording cancels without pasting (FR-4); Esc while
    /// transcribing abandons the paste (SPEC §6.6).
    func cancel() {
        switch phase {
        case .recording:
            recordingStopTask?.cancel()
            recorder.cancelRecording()
            phase = .idle
            logger.debug("recording cancelled")
        case .transcribing:
            transcriptionTask?.cancel()
            transcriptionTask = nil
            phase = .idle
            logger.debug("transcription abandoned")
        case .idle, .error:
            break
        }
    }

    // MARK: - Pipeline

    private func startRecordingStopTimer() {
        let limit = settings.maximumDuration
        recordingStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard let self, !Task.isCancelled else { return }
            await self.finishRecording(stoppedBy: .limit)
        }
    }

    private func finishRecording(stoppedBy reason: StopReason) async {
        guard phase == .recording else { return }
        playCue(named: "Pop")
        var samples: [Float]
        do {
            samples = try await recorder.stopRecording()
        } catch {
            phase = .idle
            logger.error("could not stop the recording: \(String(describing: error), privacy: .public)")
            showError("could not stop the recording")
            return
        }
        // The audio tap can deliver one last buffer after the stop decision,
        // so a limit stop can end a fraction past the model's fixed window
        // (seen in the owner's live >30 s test, 2026-10-18). Clip instead of
        // letting the transcriber throw: the notice's promise
        // ("transcribing what was captured") must hold.
        if samples.count > Transcriber.maxSamples {
            logger.debug("clipping \(samples.count) samples to the 30 s window")
            samples = Array(samples.prefix(Transcriber.maxSamples))
        }

        let duration = Double(samples.count) / Double(Transcriber.sampleRate)
        if duration < settings.minimumDuration {
            phase = .idle
            logger.debug("ignored a \(duration, format: .fixed(precision: 2)) s recording (below the minimum)")
            return
        }
        if !samples.contains(where: { abs($0) > Self.silencePeakThreshold }) {
            phase = .idle
            logger.debug("ignored a silent recording")
            return
        }
        if reason == .limit {
            showNotice("\(Int(settings.maximumDuration)) s limit reached — using what was captured")
        }
        guard let transcriber else {
            phase = .error("the speech model is not loaded")
            return
        }
        phase = .transcribing
        transcriptionTask = Task { [weak self] in
            do {
                let text = try await transcriber.transcribe(samples: samples)
                guard let self else { return }
                await self.completeTranscription(text)
            } catch {
                guard let self else { return }
                self.transcriptionTask = nil
                if Task.isCancelled {
                    self.phase = .idle
                } else {
                    // A short headline goes in the header; the technical
                    // detail stays in the log — embedded raw errors made
                    // the header grow and truncate (owner's live test).
                    self.logger.error("transcription failed: \(String(describing: error), privacy: .public)")
                    self.showError("transcription failed — try again")
                }
            }
        }
    }

    private func completeTranscription(_ rawText: String) async {
        transcriptionTask = nil
        if Task.isCancelled {
            phase = .idle
            return
        }
        var text = rawText
        if settings.wordSegmentation, let segmenter {
            let segmentStart = ContinuousClock.now
            text = segmenter.segment(text)
            logger.debug("word segmentation took \(ContinuousClock.now - segmentStart)")
        }
        guard !text.isEmpty else {
            phase = .idle
            showNotice("nothing recognizable — no text was pasted")
            return
        }
        let outcome = await inserter.insert(text, restoreClipboard: settings.restoreClipboard)
        switch outcome {
        case .pasted:
            phase = .idle
        case .copiedToClipboardOnly(let reason):
            showError(reason)
        }
    }

    // MARK: - Errors, notices, cues

    private func showError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        phase = .error(message)
        scheduleNoticeDismiss(clearsError: true)
    }

    private func showNotice(_ message: String) {
        notice = message
        scheduleNoticeDismiss(clearsError: false)
    }

    private func scheduleNoticeDismiss(clearsError: Bool) {
        noticeDismissTask?.cancel()
        noticeDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled else { return }
            if clearsError, case .error = self.phase { self.phase = .idle }
            self.notice = nil
        }
    }

    private func playCue(named name: String) {
        guard settings.soundCue else { return }
        NSSound(named: name)?.play()
    }
}
