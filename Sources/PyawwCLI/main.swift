import CoreML
import Foundation
import PyawwCore

/// pyaww-cli — Pyaww command line: `pyaww-cli file.wav` prints text;
/// `--bench N` runs the Phase 3 benchmark/soak harness.
@main
struct PyawwCLI {
    static func main() async {
        let processStart = ContinuousClock.now
        var modelDirectory = URL(fileURLWithPath: "Models", isDirectory: true)
        var computeUnits: MLComputeUnits = .all
        var benchIterations: Int?
        var files: [String] = []
        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--model-dir":
                index += 1
                guard index < arguments.count else {
                    fail("--model-dir needs a directory path")
                }
                modelDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--compute-units":
                index += 1
                guard index < arguments.count,
                      let units = Bench.parseComputeUnits(arguments[index]) else {
                    fail("--compute-units needs one of: cpuOnly, cpuAndNeuralEngine, all")
                }
                computeUnits = units
            case "--bench":
                index += 1
                guard index < arguments.count, let count = Int(arguments[index]), count > 0 else {
                    fail("--bench needs a positive iteration count")
                }
                benchIterations = count
            case "--help", "-h":
                printUsage()
                return
            default:
                files.append(argument)
            }
            index += 1
        }
        guard !files.isEmpty else {
            fail("usage: pyaww-cli [--model-dir DIR] [--compute-units UNITS] [--bench N] audio-file ...")
        }

        let loadStart = ContinuousClock.now
        let transcriber: Transcriber
        do {
            transcriber = try Transcriber(modelDirectory: modelDirectory, computeUnits: computeUnits)
        } catch {
            fail("cannot load models from \(modelDirectory.path): \(error)")
        }
        let loadMs = Bench.milliseconds(from: loadStart, to: .now)
        let startupMs = Bench.milliseconds(from: processStart, to: .now)

        if let iterations = benchIterations {
            let urls = files.map { URL(fileURLWithPath: $0) }
            let code = await Bench.run(
                transcriber: transcriber,
                iterations: iterations,
                files: urls,
                loadMs: loadMs,
                startupMs: startupMs,
                units: computeUnits)
            exit(code)
        }

        var exitCode: Int32 = 0
        for file in files {
            let url = URL(fileURLWithPath: file)
            do {
                let text = try await transcriber.transcribe(audioFileURL: url)
                print("\(url.lastPathComponent)\t\(text)")
            } catch {
                FileHandle.standardError.write(Data("error: \(url.lastPathComponent): \(error)\n".utf8))
                exitCode = 1
            }
        }
        exit(exitCode)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("pyaww-cli: \(message)\n".utf8))
        exit(2)
    }

    private static func printUsage() {
        print("""
        pyaww-cli — Pyaww ASR command line
        usage: pyaww-cli [options] audio-file [audio-file ...]
          --model-dir DIR          directory with the Core ML package and
                                   constants (default: ./Models)
          --compute-units UNITS    cpuOnly | cpuAndNeuralEngine | all
                                   (default: all)
          --bench N                benchmark/soak mode: run N transcriptions
                                   over the files (round-robin), print TSV
                                   rows: iter, file, ms, chars, footprint_mb
        Default: prints one line per file: <name>\\t<text>
        """)
    }
}
