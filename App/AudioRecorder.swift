import AVFoundation
import Foundation
import os
import PyawwCore

/// Microphone capture via `AVAudioEngine` (SPEC §6.2).
///
/// Records at the hardware format into a preallocated buffer — the audio
/// thread only copies — then converts to the 16 kHz mono contract once, off
/// the main thread, when recording stops.
@MainActor
final class AudioRecorder: AudioRecording {
    enum RecorderError: Error, CustomStringConvertible {
        case noInputDevice
        case engineFailed(String)

        var description: String {
            switch self {
            case .noInputDevice: return "no microphone input device is available"
            case .engineFailed(let reason): return "the audio engine failed to start: \(reason)"
            }
        }
    }

    /// Hard cap so the tap buffer can be preallocated (the model max is 30 s;
    /// the app stops recording at its own limit first).
    private static let accumulationCapSeconds = 31.0

    private let logger = Logger(subsystem: "com.tklwin.pyaww", category: "audio")
    private var engine: AVAudioEngine?
    private var accumulator: TapAccumulator?
    private var hardwareSampleRate: Double = 0
    private var isRecording = false

    func startRecording() throws {
        // A cancelled session may still be tearing down asynchronously;
        // finish that teardown first so this recording always starts clean.
        if isRecording { stopEngine() }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw RecorderError.noInputDevice
        }

        let accumulator = TapAccumulator(capacity: Int(format.sampleRate * Self.accumulationCapSeconds))
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            accumulator.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineFailed(error.localizedDescription)
        }
        self.engine = engine
        self.accumulator = accumulator
        self.hardwareSampleRate = format.sampleRate
        self.isRecording = true
        logger.debug("recording started (\(format.sampleRate) Hz, \(format.channelCount) ch)")
    }

    func stopRecording() async throws -> [Float] {
        guard isRecording, let accumulator else { return [] }
        stopEngine()
        let raw = accumulator.snapshot()
        let rate = hardwareSampleRate
        self.accumulator = nil
        self.hardwareSampleRate = 0
        logger.debug("recording stopped (\(raw.count) samples at \(rate) Hz)")

        guard rate != AudioLoader.targetSampleRate else { return raw }
        return try await Task.detached(priority: .userInitiated) {
            try AudioResampler.resample(raw, from: rate, to: AudioLoader.targetSampleRate)
        }.value
    }

    /// Aborts capture and discards the samples (FR-4); used by Esc.
    func cancelRecording() {
        guard isRecording else { return }
        stopEngine()
        accumulator = nil
        hardwareSampleRate = 0
        logger.debug("recording cancelled")
    }

    /// Stops the engine and removes the tap; leaves the accumulator intact
    /// so `stopRecording` can still snapshot it.
    private func stopEngine() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        isRecording = false
    }
}

/// Lock-protected sample accumulator. The tap (audio thread) appends copies
/// into storage that was preallocated at `startRecording`, so the critical
/// section is a bounded `memcpy`; the scratch buffer handles multi-channel
/// downmixing without per-callback allocation.
private final class TapAccumulator: @unchecked Sendable {
    private struct State {
        var samples: [Float] = []
        var scratch: [Float] = []
        var dropped = 0
    }

    private let capacity: Int
    private let lock = OSAllocatedUnfairLock(initialState: State())

    init(capacity: Int) {
        self.capacity = capacity
        lock.withLock { state in
            state.samples.reserveCapacity(capacity)
            state.scratch.reserveCapacity(8192)
        }
    }

    /// Called from the audio thread. `withLockUnchecked` is used because the
    /// closure borrows the Core Audio buffer pointers; the lock makes the
    /// access to `state` safe.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return }
        lock.withLockUnchecked { state in
            guard state.samples.count + frames <= self.capacity else {
                state.dropped += frames
                return
            }
            if channels == 1 {
                state.samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frames))
            } else {
                if state.scratch.count < frames {
                    state.scratch = [Float](repeating: 0, count: frames)
                }
                let scale = 1 / Float(channels)
                for i in 0..<frames {
                    var value: Float = 0
                    for channel in 0..<channels { value += channelData[channel][i] }
                    state.scratch[i] = value * scale
                }
                state.samples.append(contentsOf: state.scratch[0..<frames])
            }
        }
    }

    func snapshot() -> [Float] {
        lock.withLock { $0.samples }
    }
}
