import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for the **pure** command builder behind `BrowserLauncher` (Task 11).
///
/// The builder turns `(Browser, BrowserTarget, URL)` into the concrete invocation
/// `(executableURL, arguments)` per the launch-mechanism spike §3/§4, **without**
/// launching anything. There are two shapes:
///
/// - **With a profile** (spike §4):
///     executableURL = /usr/bin/open
///     arguments     = ["-n", "-a", <app path>, "--args"] + LaunchArguments.build(...)
///   `-n` forces a new instance so argv reaches the browser's own parser.
///
/// - **Without a profile** (spike §3 — no argv contract, so no `-n`; for Safari
///   `-n` would open a duplicate app rather than a tab in the running one):
///     arguments     = ["-a", <app path>, <url>]
///
/// The URL is always the last element of `arguments`. The live `process.run()` is
/// the only line not exercised here (manual verification).
final class BrowserLauncherCommandTests: XCTestCase {

    private let url = URL(string: "https://example.com/path?q=1")!

    private func browser(
        bundleID: String,
        name: String,
        appURL: URL
    ) -> Browser {
        Browser(bundleID: bundleID, name: name, appURL: appURL, profiles: [])
    }

    // MARK: - Executable + open flags

    func testProfiledCommandUsesUsrBinOpenWithNAArgsFlags() {
        let chrome = browser(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        // A profile is selected → new-instance path with the --args contract.
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")

        let command = BrowserLaunchCommand.make(target: target, browser: chrome, url: url)

        XCTAssertEqual(command.executableURL, URL(fileURLWithPath: "/usr/bin/open"))
        // The fixed open prefix: -n (new instance) -a <app path> --args …
        XCTAssertEqual(Array(command.arguments.prefix(4)), [
            "-n",
            "-a",
            "/Applications/Google Chrome.app",
            "--args"
        ])
    }

    func testCommandUsesResolvedAppPathFromBrowser() {
        // The app path must come from browser.appURL.path, not the display name.
        let chrome = browser(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            appURL: URL(fileURLWithPath: "/Users/me/Applications/Google Chrome.app")
        )
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")

        let command = BrowserLaunchCommand.make(target: target, browser: chrome, url: url)

        XCTAssertEqual(command.arguments[2], "/Users/me/Applications/Google Chrome.app")
    }

    // MARK: - Chromium with profile

    func testChromiumWithProfileCommand() {
        let chrome = browser(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")

        let command = BrowserLaunchCommand.make(target: target, browser: chrome, url: url)

        XCTAssertEqual(command.executableURL, URL(fileURLWithPath: "/usr/bin/open"))
        XCTAssertEqual(command.arguments, [
            "-n",
            "-a",
            "/Applications/Google Chrome.app",
            "--args",
            "--profile-directory=Profile 1",
            url.absoluteString
        ])
        // URL is last.
        XCTAssertEqual(command.arguments.last, url.absoluteString)
    }

    // MARK: - Firefox with profile

    func testFirefoxWithProfileCommand() {
        let firefox = browser(
            bundleID: "org.mozilla.firefox",
            name: "Firefox",
            appURL: URL(fileURLWithPath: "/Applications/Firefox.app")
        )
        let target = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "default-release")

        let command = BrowserLaunchCommand.make(target: target, browser: firefox, url: url)

        XCTAssertEqual(command.arguments, [
            "-n",
            "-a",
            "/Applications/Firefox.app",
            "--args",
            "-P",
            "default-release",
            url.absoluteString
        ])
        // No -no-remote (spike §4): must not appear anywhere.
        XCTAssertFalse(command.arguments.contains("-no-remote"))
        XCTAssertEqual(command.arguments.last, url.absoluteString)
    }

    // MARK: - Safari / no-profile

    func testSafariCommandHasOnlyURLInTail() {
        let safari = browser(
            bundleID: "com.apple.Safari",
            name: "Safari",
            appURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        // Safari has no CLI profile selection; even a profileID is ignored.
        let target = BrowserTarget(bundleID: "com.apple.Safari", profileID: "ignored")

        let command = BrowserLaunchCommand.make(target: target, browser: safari, url: url)

        XCTAssertEqual(command.arguments, [
            "-n",
            "-a",
            "/Applications/Safari.app",
            "--args",
            url.absoluteString
        ])
        XCTAssertEqual(command.arguments.last, url.absoluteString)
    }

    func testUnknownFamilyNoProfileUsesPlainOpenWithoutNewInstance() {
        let unknown = browser(
            bundleID: "com.example.MysteryBrowser",
            name: "Mystery",
            appURL: URL(fileURLWithPath: "/Applications/Mystery.app")
        )
        let target = BrowserTarget(bundleID: "com.example.MysteryBrowser", profileID: nil)

        let command = BrowserLaunchCommand.make(target: target, browser: unknown, url: url)

        // No profile → plain open-document path: no -n, no --args.
        XCTAssertEqual(command.arguments, [
            "-a",
            "/Applications/Mystery.app",
            url.absoluteString
        ])
    }

    // MARK: - No profile → no new instance (spike §3)

    func testChromiumNoProfileUsesPlainOpenWithoutNewInstance() {
        let chrome = browser(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: nil)

        let command = BrowserLaunchCommand.make(target: target, browser: chrome, url: url)

        // Without a profile there is no argv contract, so we must NOT force a new
        // instance: plain `open -a <app> <url>` (spike §3).
        XCTAssertEqual(command.executableURL, URL(fileURLWithPath: "/usr/bin/open"))
        XCTAssertEqual(command.arguments, [
            "-a",
            "/Applications/Google Chrome.app",
            url.absoluteString
        ])
        XCTAssertFalse(command.arguments.contains("-n"))
        XCTAssertFalse(command.arguments.contains("--args"))
        XCTAssertEqual(command.arguments.last, url.absoluteString)
    }

    func testSafariNoProfileUsesPlainOpenWithoutNewInstance() {
        // The duplicate-Safari case the spike §3 warns about: a no-profile Safari
        // target must reuse the running Safari (plain open), not spawn a new copy.
        let safari = browser(
            bundleID: "com.apple.Safari",
            name: "Safari",
            appURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        let target = BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)

        let command = BrowserLaunchCommand.make(target: target, browser: safari, url: url)

        XCTAssertEqual(command.arguments, [
            "-a",
            "/Applications/Safari.app",
            url.absoluteString
        ])
        XCTAssertFalse(command.arguments.contains("-n"))
    }

    // MARK: - Tail is exactly LaunchArguments.build

    func testTailMatchesCoreLaunchArguments() {
        // The portion after "--args" must be exactly what Core's LaunchArguments
        // produces — the builder reuses Core rather than re-deriving argv.
        let chrome = browser(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Default")

        let command = BrowserLaunchCommand.make(target: target, browser: chrome, url: url)

        let argsIndex = try? XCTUnwrap(command.arguments.firstIndex(of: "--args"))
        let tail = Array(command.arguments.suffix(from: (argsIndex ?? -1) + 1))
        XCTAssertEqual(tail, LaunchArguments.build(for: target, url: url))
    }
}
