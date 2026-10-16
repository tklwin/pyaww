import Foundation
import PyawwCore

/// pyaww-cli — Phase 1 parity harness: `pyaww-cli file.wav` prints text.
@main
struct PyawwCLI {
    static func main() {
        var modelDirectory = URL(fileURLWithPath: "Models", isDirectory: true)
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
            case "--help", "-h":
                printUsage()
                return
            default:
                files.append(argument)
            }
            index += 1
        }
        guard !files.isEmpty else {
            fail("usage: pyaww-cli [--model-dir DIR] audio-file [audio-file ...]")
        }

        let transcriber: Transcriber
        do {
            transcriber = try Transcriber(modelDirectory: modelDirectory)
        } catch {
            fail("cannot load models from \(modelDirectory.path): \(error)")
        }

        var exitCode: Int32 = 0
        for file in files {
            let url = URL(fileURLWithPath: file)
            do {
                let text = try transcriber.transcribe(audioFileURL: url)
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
        pyaww-cli — Pyaww ASR command line (Phase 1)
        usage: pyaww-cli [--model-dir DIR] audio-file [audio-file ...]
          --model-dir  directory with the Core ML package and constants
                       (default: ./Models)
        Prints one line per file: <name>\t<text>
        """)
    }
}
