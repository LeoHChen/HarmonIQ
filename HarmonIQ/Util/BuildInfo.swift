import Foundation

/// Static accessors for the build metadata baked into the app bundle.
///
/// `version` and `build` come from XcodeGen's generated Info.plist
/// (`CFBundleShortVersionString` / `CFBundleVersion`). The git fields and
/// build timestamp are written into the same Info.plist by the
/// `Embed build metadata` postBuildScript declared in `project.yml` —
/// see issue #52.
enum BuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static var gitCommit: String {
        Bundle.main.object(forInfoDictionaryKey: "GitCommit") as? String ?? "unknown"
    }

    static var gitTag: String {
        Bundle.main.object(forInfoDictionaryKey: "GitTag") as? String ?? "dev"
    }

    static var builtAt: String {
        Bundle.main.object(forInfoDictionaryKey: "BuildTimestamp") as? String ?? "unknown"
    }

    /// Multi-line block suitable for pasting into a bug report.
    static var clipboardSummary: String {
        """
        HarmonIQ \(version) (build \(build))
        commit \(gitCommit)
        tag \(gitTag)
        built \(builtAt)
        """
    }
}
