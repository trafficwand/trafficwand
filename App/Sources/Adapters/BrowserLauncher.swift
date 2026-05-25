import Foundation
import TrafficWandCore

/// The concrete launch invocation: an executable plus its argument vector, ready
/// to hand to `Process` — but produced **without** launching anything.
///
/// Separating command construction from execution makes the whole decision —
/// which executable, which flags, where the URL lands — fully unit-testable; only
/// the final `process.run()` in `BrowserLauncher` is left to manual verification.
public struct BrowserLaunchCommand: Equatable, Sendable {
    /// The executable to run (always `/usr/bin/open` for mechanism (b)).
    public let executableURL: URL
    /// The full argument vector passed to the executable.
    public let arguments: [String]

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

extension BrowserLaunchCommand {
    /// Path to the system `open` tool used as the launch front door (spike §3).
    static let openExecutableURL = URL(fileURLWithPath: "/usr/bin/open")

    /// Builds the launch command for opening `url` in `browser` with `target`'s
    /// optional profile — the **pure** core of `BrowserLauncher`.
    ///
    /// Two shapes, per the launch-mechanism spike §3/§4:
    ///
    /// - **With a profile** (`target.profileID != nil`):
    ///
    ///       /usr/bin/open -n -a <app path> --args <argv tail…>
    ///
    ///   `-n` requests a new instance so our argv reaches the browser's own
    ///   argument parser (which then forwards to a running instance over the
    ///   browser's IPC — the only way profile routing survives an already-running
    ///   browser). The `--args` tail is exactly `LaunchArguments.build(for:url:)`
    ///   (Core), so the URL is always last and the profile flag is family-correct.
    ///
    /// - **Without a profile** (`target.profileID == nil`, incl. Safari): there is
    ///   no argv contract to honor, so spawning a brand-new instance is wrong (for
    ///   Safari `-n` opens a *duplicate* app rather than a tab in the running one —
    ///   spike §3). Use the plain open-document path:
    ///
    ///       /usr/bin/open -a <app path> <url>
    ///
    /// In both cases `-a <app path>` resolves the browser by the path we already
    /// have (`browser.appURL`), avoiding display-name ambiguity.
    ///
    /// - Parameters:
    ///   - target: The routing target (bundle ID + optional profile).
    ///   - browser: The resolved browser supplying its `appURL`.
    ///   - url: The link to open.
    /// - Returns: The executable + argv to run, never launched here.
    public static func make(target: BrowserTarget, browser: Browser, url: URL) -> BrowserLaunchCommand {
        let appPath = browser.appURL.path
        let hasProfile = target.profileID?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let arguments: [String]
        if hasProfile {
            // Profile selected → new instance so argv reaches the browser parser.
            let argvTail = LaunchArguments.build(for: target, url: url)
            arguments = ["-n", "-a", appPath, "--args"] + argvTail
        } else {
            // No profile → no argv contract; plain open-document path (no -n).
            arguments = ["-a", appPath, url.absoluteString]
        }
        return BrowserLaunchCommand(executableURL: openExecutableURL, arguments: arguments)
    }
}

/// The App-level browser launcher: builds a `BrowserLaunchCommand` (pure, tested)
/// and runs it via `Process` (the one live, manually-verified line).
///
/// Conforms to Core's `BrowserLaunching`, keeping the launching concern behind a
/// protocol seam so routing logic and its tests never spawn a subprocess.
public struct BrowserLauncher: BrowserLaunching {
    public init() {}

    /// Opens `url` in `browser`, selecting `target`'s profile if any.
    ///
    /// Builds the command with `BrowserLaunchCommand.make` then spawns it. We do
    /// **not** `waitUntilExit()`: `open` returns immediately and the launched
    /// browser is detached (not our child).
    public func launch(target: BrowserTarget, browser: Browser, url: URL) throws {
        let command = BrowserLaunchCommand.make(target: target, browser: browser, url: url)
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        try process.run()
    }
}
