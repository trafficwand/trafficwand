import XCTest
import TrafficWandCore
@testable import TrafficWand

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
        struct Call: Equatable {
            let target: BrowserTarget
            let browserBundleID: String
            let url: URL
        }
        private(set) var calls: [Call] = []
        func launch(target: BrowserTarget, browser: Browser, url: URL) throws {
            calls.append(Call(target: target, browserBundleID: browser.bundleID, url: url))
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
        struct Call: Equatable {
            let url: URL
            let browserBundleIDs: [String]
        }
        private(set) var calls: [Call] = []
        func presentPicker(url: URL, browsers: [Browser]) {
            calls.append(Call(url: url, browserBundleIDs: browsers.map(\.bundleID)))
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
        let rule = Rule(pattern: "*github.com", target: target, isEnabled: true)
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

    // MARK: - .open with target not in available browsers

    func testOpenDecisionWithUnknownTargetDoesNotLaunchButStillRecords() throws {
        // If the .open target's browser is not among the available browsers, the
        // launcher cannot be invoked (no appURL to resolve); the service must not
        // crash and must not call the launcher. Last-used is still recorded so the
        // routing intent is remembered.
        let target = BrowserTarget(bundleID: "com.unknown.Browser", profileID: nil)
        let config = AppConfig(rules: [], fallback: .defaultBrowser(target))
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
        XCTAssertTrue(picker.calls.isEmpty)
        XCTAssertEqual(lastUsed.recorded, [target])
    }
}
