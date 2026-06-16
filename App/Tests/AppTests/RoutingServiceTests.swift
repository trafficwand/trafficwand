import XCTest
import TrafficWandCore
@testable import TrafficWand

/// A recorded `BrowserLaunching.launch` call (file-scope to avoid deep nesting).
private struct LaunchCall: Equatable {
    let target: BrowserTarget
    let browserBundleID: String
    let url: URL
}

/// A recorded `PickerPresenting.presentPicker` call (file-scope to avoid deep nesting).
private struct PickerCall: Equatable {
    let url: URL
    let browserBundleIDs: [String]
    let aliases: [ProfileAlias]
}

/// Tests for `RoutingService.route(url:)` (Task 13).
///
/// `RoutingService` composes the pure Core `Router` with the App's injected
/// adapters: it loads config, gets available browsers, reads last-used, asks
/// `Router.decide`, then either launches (recording last-used) or presents the
/// picker. These tests drive the decision by choosing config rules / fallback so
/// the **real** `Router` is exercised, and assert the resulting side effects on
/// mock collaborators (launcher, last-used store, picker presenter).
@MainActor
final class RoutingServiceTests: XCTestCase {

    // MARK: - Mocks / stubs

    /// In-memory `ConfigStore` returning a fixed config; records saves (unused here).
    private struct StubConfigStore: ConfigStore {
        let config: AppConfig
        func load() throws -> AppConfig { config }
        func save(_ config: AppConfig) throws {}
    }

    /// Stub provider returning a fixed browser list.
    private struct StubBrowserProvider: InstalledBrowsersProviding {
        let browsers: [Browser]
        func installedBrowsers() -> [Browser] { browsers }
    }

    /// Mock launcher recording every `launch` call.
    ///
    /// `@unchecked Sendable` because `BrowserLaunching` is `Sendable` but the mock
    /// holds mutable recording state; the tests use it single-threaded on the main
    /// actor, so the unchecked escape is safe here.
    private final class MockLauncher: BrowserLaunching, @unchecked Sendable {
        private(set) var calls: [LaunchCall] = []
        func launch(target: BrowserTarget, browser: Browser, url: URL) throws {
            calls.append(LaunchCall(target: target, browserBundleID: browser.bundleID, url: url))
        }
    }

    /// Mock last-used store recording `set` calls and returning a seeded value.
    private final class MockLastUsed: LastUsedRecording {
        var stored: BrowserTarget?
        private(set) var recorded: [BrowserTarget] = []
        func get() -> BrowserTarget? { stored }
        func set(_ target: BrowserTarget) {
            recorded.append(target)
            stored = target
        }
    }

    /// Mock picker presenter recording `presentPicker` calls.
    private final class MockPicker: PickerPresenting {
        private(set) var calls: [PickerCall] = []
        func presentPicker(url: URL, browsers: [Browser], aliases: [ProfileAlias]) {
            calls.append(PickerCall(url: url, browserBundleIDs: browsers.map(\.bundleID), aliases: aliases))
        }
    }

    // MARK: - Fixtures

    private let url = URL(string: "https://gist.github.com/foo")!

    private func browser(_ bundleID: String, _ name: String) -> Browser {
        Browser(
            bundleID: bundleID,
            name: name,
            appURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            profiles: []
        )
    }

    private func makeService(
        config: AppConfig,
        browsers: [Browser],
        launcher: MockLauncher,
        lastUsedStore: MockLastUsed,
        picker: MockPicker
    ) -> RoutingService {
        RoutingService(
            configStore: StubConfigStore(config: config),
            browserProvider: StubBrowserProvider(browsers: browsers),
            launcher: launcher,
            lastUsedStore: lastUsedStore,
            picker: picker
        )
    }

    // MARK: - .open decision

    func testOpenDecisionLaunchesTargetAndRecordsLastUsed() throws {
        // A rule matching the URL host yields .open(target). The launcher must be
        // called with that target (resolving the Browser whose bundleID matches)
        // and last-used must be recorded; the picker must NOT be shown.
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Work")
        let rule = Rule(pattern: "*github.com", destination: .browser(target), isEnabled: true)
        let config = AppConfig(rules: [rule], fallback: .picker)
        let browsers = [
            browser("com.google.Chrome", "Google Chrome"),
            browser("org.mozilla.firefox", "Firefox")
        ]

        let launcher = MockLauncher()
        let lastUsed = MockLastUsed()
        let picker = MockPicker()
        let service = makeService(
            config: config, browsers: browsers,
            launcher: launcher, lastUsedStore: lastUsed, picker: picker
        )

        service.route(url: url)

        XCTAssertEqual(launcher.calls.count, 1)
        XCTAssertEqual(launcher.calls.first?.target, target)
        XCTAssertEqual(launcher.calls.first?.browserBundleID, "com.google.Chrome")
        XCTAssertEqual(launcher.calls.first?.url, url)
        XCTAssertEqual(lastUsed.recorded, [target])
        XCTAssertTrue(picker.calls.isEmpty)
    }

    // MARK: - .prompt decision

    func testPromptDecisionPresentsPickerAndDoesNotLaunch() throws {
        // No rule matches and fallback is .picker → .prompt. The picker must be
        // presented with the available browsers; the launcher must NOT be called
        // and nothing recorded as last-used.
        let config = AppConfig(rules: [], fallback: .picker)
        let browsers = [
            browser("com.google.Chrome", "Google Chrome"),
            browser("org.mozilla.firefox", "Firefox")
        ]

        let launcher = MockLauncher()
        let lastUsed = MockLastUsed()
        let picker = MockPicker()
        let service = makeService(
            config: config, browsers: browsers,
            launcher: launcher, lastUsedStore: lastUsed, picker: picker
        )

        service.route(url: url)

        XCTAssertEqual(picker.calls.count, 1)
        XCTAssertEqual(picker.calls.first?.url, url)
        XCTAssertEqual(
            picker.calls.first?.browserBundleIDs,
            ["com.google.Chrome", "org.mozilla.firefox"]
        )
        XCTAssertTrue(launcher.calls.isEmpty)
        XCTAssertTrue(lastUsed.recorded.isEmpty)
    }

    func testPromptDecisionPassesConfigAliasesToPicker() throws {
        // The aliases in config must reach the picker so it can offer alias rows.
        let alias = ProfileAlias(
            name: "Work",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        )
        let config = AppConfig(aliases: [alias], rules: [], fallback: .picker)
        let browsers = [browser("com.google.Chrome", "Google Chrome")]

        let picker = MockPicker()
        let service = makeService(
            config: config, browsers: browsers,
            launcher: MockLauncher(), lastUsedStore: MockLastUsed(), picker: picker
        )

        service.route(url: url)

        XCTAssertEqual(picker.calls.count, 1)
        XCTAssertEqual(picker.calls.first?.aliases, [alias])
    }

    // MARK: - .open with target not in available browsers

    func testOpenDecisionWithUnknownTargetFallsBackToPicker() throws {
        // If the .open target's browser is not among the available browsers (stale
        // rule / removed-or-renamed default browser), the launcher cannot be
        // invoked (no appURL to resolve). The link must NOT be dropped: the service
        // falls back to presenting the picker so the user can still choose. The
        // unresolvable target must NOT be recorded as last-used (it would mislead
        // the .lastUsed fallback toward a browser that no longer exists).
        let target = BrowserTarget(bundleID: "com.unknown.Browser", profileID: nil)
        // Seed an alias so we can assert config.aliases is threaded through the
        // private `open(...)` recovery path into the fallback picker (not just the
        // direct `.prompt` path), so a remembered alias still works on recovery.
        let alias = ProfileAlias(
            name: "Work",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: nil)
        )
        let config = AppConfig(
            aliases: [alias],
            rules: [],
            fallback: .defaultBrowser(.browser(target))
        )
        let browsers = [browser("com.google.Chrome", "Google Chrome")]

        let launcher = MockLauncher()
        let lastUsed = MockLastUsed()
        let picker = MockPicker()
        let service = makeService(
            config: config, browsers: browsers,
            launcher: launcher, lastUsedStore: lastUsed, picker: picker
        )

        service.route(url: url)

        XCTAssertTrue(launcher.calls.isEmpty)
        XCTAssertEqual(picker.calls.count, 1)
        XCTAssertEqual(picker.calls.first?.url, url)
        XCTAssertEqual(picker.calls.first?.browserBundleIDs, ["com.google.Chrome"])
        XCTAssertEqual(picker.calls.first?.aliases, [alias])
        XCTAssertTrue(lastUsed.recorded.isEmpty)
    }
}
