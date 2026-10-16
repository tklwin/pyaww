import AVFoundation

/// Audio file loading and resampling to the model contract: 16 kHz mono
/// Float32 (SPEC §4 AudioResampler).
public enum AudioIOError: Error, CustomStringConvertible {
    case cannotReadFile(String)
    case emptyFile
    case fileTooLong(seconds: Double)
    case unsupportedFormat
    case resamplerSetupFailed
    case resampleFailed(String)

    public var description: String {
        switch self {
        case .cannotReadFile(let detail): return "cannot read audio file: \(detail)"
        case .emptyFile: return "audio file contains no samples"
        case .fileTooLong(let seconds): return String(format: "audio file is %.1f s; the CLI accepts at most 600 s", seconds)
        case .unsupportedFormat: return "unsupported audio format"
        case .resamplerSetupFailed: return "could not set up audio resampling"
        case .resampleFailed(let detail): return "audio resampling failed: \(detail)"
        }
    }
}

/// Decodes any AVFoundation-readable file (wav, mp3, m4a, flac, ...) into
/// mono Float32 samples and resamples to 16 kHz.
public enum AudioLoader {
    public static let targetSampleRate: Double = 16_000

    /// Loads the file as mono Float32 at its native sample rate.
    public static func loadMono(url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch {
            throw AudioIOError.cannotReadFile("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioIOError.unsupportedFormat
        }
        let seconds = Double(file.length) / format.sampleRate
        guard seconds <= 600 else { throw AudioIOError.fileTooLong(seconds: seconds) }
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioIOError.emptyFile
        }
        do { try file.read(into: buffer) }
        catch { throw AudioIOError.cannotReadFile(error.localizedDescription) }
        guard let channels = buffer.floatChannelData else {
            throw AudioIOError.unsupportedFormat
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            mono.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress!.update(from: channels[0], count: frameCount)
            }
        } else {
            let scale = 1.0 / Float(channelCount)
            for channel in 0..<channelCount {
                let source = channels[channel]
                for i in 0..<frameCount { mono[i] += source[i] * scale }
            }
        }
        return (mono, format.sampleRate)
    }

    /// Loads the file and guarantees exactly 16 kHz mono Float32 output.
    public static func load16kMono(url: URL) throws -> [Float] {
        let (samples, sampleRate) = try loadMono(url: url)
        if sampleRate == targetSampleRate { return samples }
        return try AudioResampler.resample(samples, from: sampleRate, to: targetSampleRate)
    }
}

/// Sample-rate conversion via AVAudioConverter.
///
/// Note: the Python reference resamples with torchaudio's sinc interpolation;
/// AVAudioConverter uses a different (polyphase) kernel, so resampled inputs
/// can differ slightly. All golden fixtures are already 16 kHz, where this
/// path is a no-op.
public enum AudioResampler {
    public static func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) throws -> [Float] {
        guard inputRate != outputRate else { return samples }
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate,
                                              channels: 1, interleaved: false),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outputRate,
                                               channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                 frameCapacity: AVAudioFrameCount(samples.count)),
              let inputChannel = inputBuffer.floatChannelData?[0] else {
            throw AudioIOError.resamplerSetupFailed
        }
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            inputChannel.update(from: source.baseAddress!, count: samples.count)
        }

        let ratio = outputRate / inputRate
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 1024
        var output = [Float]()
        output.reserveCapacity(Int(Double(samples.count) * ratio) + 64)

        var inputProvided = false
        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                      frameCapacity: capacity) else {
                throw AudioIOError.resamplerSetupFailed
            }
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if inputProvided {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                inputProvided = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
            if status == .error {
                throw AudioIOError.resampleFailed(conversionError?.localizedDescription ?? "unknown error")
            }
            if outputBuffer.frameLength > 0, let channel = outputBuffer.floatChannelData?[0] {
                output.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
            }
            if status == .endOfStream { break }
        }

        let expectedCount = Int((Double(samples.count) * ratio).rounded())
        if output.count > expectedCount { output.removeLast(output.count - expectedCount) }
        return output
    }
}
