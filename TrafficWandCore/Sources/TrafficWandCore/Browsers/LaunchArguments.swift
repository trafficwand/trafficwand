import Foundation

/// Builds the launch argv **tail** for a routing target — everything that follows
/// `--args` under `open -n -a <app> --args …` (or everything after the executable
/// when spawning the binary directly). It does **not** include the executable
/// path, `open`, `-n`, `-a`, or `--args`; those belong to the App-level launcher.
///
/// Contract (launch-mechanism spike §4):
/// - The **URL is always the last element**; profile flags come first.
/// - Chromium with a profile → `["--profile-directory=<dir>", "<url>"]`.
/// - Firefox with a profile → `["-P", "<name>", "<url>"]` — **no** `-no-remote`
///   (it breaks the already-running-browser case; remoting must stay on).
/// - Safari, unknown families, or any target without a profile → `["<url>"]`.
///
/// An empty or whitespace-only `profileID` is treated as **no profile** (no flag
/// is emitted) rather than producing an empty flag value.
///
/// The URL element is `url.absoluteString`.
public enum LaunchArguments {
    /// Returns the argv tail for launching `url` in `target`'s browser/profile.
    ///
    /// - Parameters:
    ///   - target: The browser (and optional profile) to launch.
    ///   - url: The link to open; serialized via `absoluteString`.
    /// - Returns: The argv tail, URL last.
    public static func build(for target: BrowserTarget, url: URL) -> [String] {
        let urlArg = url.absoluteString

        // No profile selected → there is no flag to add for any family. An empty
        // (or whitespace-only) profileID is treated as *no profile*: emitting an
        // empty flag value (e.g. `--profile-directory=`) would be a broken argument.
        guard let profileID = target.profileID,
              !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [urlArg]
        }

        switch BrowserFamily(bundleID: target.bundleID) {
        case .chromium:
            return ["--profile-directory=\(profileID)", urlArg]
        case .firefox:
            return ["-P", profileID, urlArg]
        case .safari, .other:
            // No command-line profile selection; the profile is ignored.
            return [urlArg]
        }
    }
}
