import CoreML
import Foundation
import PyawwCore

/// Benchmark and soak harness for Phase 3 (SPEC §5.2).
///
/// Runs the exact app pipeline (`Transcriber.transcribe(samples:)` on 16 kHz
/// mono samples) with the same warm-up the app performs after loading, and
/// reports per-iteration latency and memory footprint as TSV rows (`#` lines
/// are metadata/summary).
enum Bench {
    static func parseComputeUnits(_ raw: String) -> MLComputeUnits? {
        switch raw {
        case "cpuOnly": return .cpuOnly
        case "cpuAndNeuralEngine": return .cpuAndNeuralEngine
        case "all": return .all
        default: return nil
        }
    }

    static func unitsLabel(_ units: MLComputeUnits) -> String {
        switch units {
        case .cpuOnly: return "cpuOnly"
        case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
        case .all: return "all"
        @unknown default: return "unknown"
        }
    }

    static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: end).components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Nearest-rank percentile over an ascending array.
    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let rank = max(0, min(sorted.count - 1, Int((fraction * Double(sorted.count)).rounded(.up)) - 1))
        return sorted[rank]
    }

    static func run(
        transcriber: Transcriber,
        iterations: Int,
        files: [URL],
        loadMs: Double,
        startupMs: Double,
        units: MLComputeUnits
    ) async -> Int32 {
        // Decode each file once, then benchmark on samples — the app path
        // (mic samples -> transcribe) without per-iteration file I/O.
        var loaded: [(url: URL, samples: [Float])] = []
        var decodeMs: Double = 0
        for url in files {
            do {
                let start = ContinuousClock.now
                let samples = try AudioLoader.load16kMono(url: url)
                decodeMs += milliseconds(from: start, to: .now)
                loaded.append((url, samples))
            } catch {
                FileHandle.standardError.write(Data("error: \(url.lastPathComponent): \(error)\n".utf8))
                return 1
            }
        }
        guard !loaded.isEmpty else { return 1 }

        print("# units=\(unitsLabel(units))")
        print("# load_ms=\(fmt(loadMs)) startup_ms=\(fmt(startupMs)) decode_ms=\(fmt(decodeMs))")
        for entry in loaded {
            let seconds = Double(entry.samples.count) / Double(Transcriber.sampleRate)
            print("# file=\(entry.url.lastPathComponent) seconds=\(String(format: "%.2f", seconds))")
        }

        // Same post-load warm-up as the app: 1 s of digital silence.
        let warmStart = ContinuousClock.now
        _ = try? await transcriber.transcribe(samples: [Float](repeating: 0, count: 16_000))
        print("# silence_warmup_ms=\(fmt(milliseconds(from: warmStart, to: .now)))")
        print("iter\tfile\tms\tchars\tfootprint_mb")

        var latencies: [Double] = []
        var footprintFirst = 0.0
        var footprintLast = 0.0
        var footprintMax = 0.0
        var exitCode: Int32 = 0

        for iteration in 0..<iterations {
            let entry = loaded[iteration % loaded.count]
            let start = ContinuousClock.now
            do {
                let text = try await transcriber.transcribe(samples: entry.samples)
                let ms = milliseconds(from: start, to: .now)
                let footprint = currentFootprintMB()
                latencies.append(ms)
                if footprintFirst == 0 { footprintFirst = footprint }
                footprintLast = footprint
                footprintMax = max(footprintMax, footprint)
                print("\(iteration)\t\(entry.url.lastPathComponent)\t\(fmt(ms))\t\(text.count)\t\(fmt(footprint))")
            } catch {
                print("\(iteration)\t\(entry.url.lastPathComponent)\terror\t0\t\(fmt(currentFootprintMB()))")
                FileHandle.standardError.write(Data("error: iteration \(iteration): \(error)\n".utf8))
                exitCode = 1
            }
        }

        let sorted = latencies.sorted()
        if let minimum = sorted.first, let maximum = sorted.last {
            let mean = sorted.reduce(0, +) / Double(sorted.count)
            print("# latency_ms n=\(sorted.count) min=\(fmt(minimum)) p50=\(fmt(percentile(sorted, 0.50)))"
                + " p90=\(fmt(percentile(sorted, 0.90))) mean=\(fmt(mean)) max=\(fmt(maximum))")
        } else {
            print("# latency_ms n=0")
        }
        print("# footprint_mb first=\(fmt(footprintFirst)) last=\(fmt(footprintLast))"
            + " max=\(fmt(footprintMax)) peak_rss=\(fmt(peakRSSMB()))")
        return exitCode
    }
}
