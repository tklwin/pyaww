import Foundation

/// Boundary protocols (SPEC §4): the app shell talks to `PyawwCore` only
/// through these, so tests can substitute fakes.

/// Audio → text. The single async entry point the app shell uses.
public protocol Transcribing: Sendable {
    func transcribe(samples: [Float]) async throws -> String
}

/// Microphone capture at the model contract (16 kHz mono Float32 on stop).
@MainActor
public protocol AudioRecording: AnyObject {
    func startRecording() throws
    /// Stops capture and returns 16 kHz mono Float32 samples. Resampling runs
    /// off the main thread, hence `async`.
    func stopRecording() async throws -> [Float]
    /// Aborts capture and discards the samples (Esc, FR-4). Synchronous so a
    /// following `startRecording` can never race the teardown.
    func cancelRecording()
}

/// Result of trying to paste text into the focused app.
public enum InsertionOutcome: Sendable, Equatable {
    /// The text was pasted at the cursor.
    case pasted
    /// Paste was not possible (no permission, secure input, …); the text was
    /// left on the clipboard so it is never lost.
    case copiedToClipboardOnly(reason: String)
}

/// Text → focused app (clipboard + synthetic paste, clipboard restored).
@MainActor
public protocol TextInserting: AnyObject {
    func insert(_ text: String, restoreClipboard: Bool) async -> InsertionOutcome
}
