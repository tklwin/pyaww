import Foundation

/// Looks up PyawwCore's bundled resources without SwiftPM's generated
/// `Bundle.module` accessor: that accessor calls `fatalError` when the
/// bundle cannot be found, which the project's no-crash rule forbids.
///
/// The candidate list mirrors the accessor's (main bundle's `resourceURL`,
/// `Bundle(for:)`, and `bundleURL`) plus a direct
/// `Contents/Resources/lexicons.json` lookup for the hand-assembled
/// Pyaww.app (scripts/make-app.sh copies both layouts).
enum PyawwCoreResources {
    private static let bundleName = "Pyaww_PyawwCore.bundle"
    private static let bundledRelativePath = "Contents/Resources/lexicons.json"

    /// URL of the word-segmentation lexicon, or `nil` when missing.
    static func lexiconsURL() -> URL? {
        let fileManager = FileManager.default
        if let resources = Bundle.main.resourceURL {
            let direct = resources.appendingPathComponent("lexicons.json")
            if fileManager.fileExists(atPath: direct.path) { return direct }
        }
        let bases: [URL?] = [
            Bundle.main.resourceURL,
            Bundle(for: BundleFinder.self).resourceURL,
            Bundle.main.bundleURL,
        ]
        for case let base? in bases {
            let candidate = base
                .appendingPathComponent(bundleName)
                .appendingPathComponent(bundledRelativePath)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

private final class BundleFinder {}
