import AppKit
import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `PickerPanelController`'s selection wiring (the picker-alias-selection
/// plan, Task 4).
///
/// `handleSelection` is private, so these tests drive it the way the live UI does:
/// build the wired view model via the internal `makeViewModel(url:browsers:aliases:)`
/// seam and invoke its selection methods. They assert the controller:
///
///  - launches the **concrete** `launchTarget` (an alias resolves to its target;
///    a browser/profile row to its `BrowserTarget`);
///  - records that concrete target as last-used;
///  - persists the chosen **`RoutingDestination`** when "remember" is ticked (an
///    `.alias(id)` for an alias pick, a `.browser(...)` otherwise);
///  - recovers (re-presents) rather than dropping the link when the launch target's
///    browser isn't installed — exercised via a stale concrete target, since
///    uninstalled-target aliases are filtered out at the view-model layer.
@MainActor
final class PickerPanelControllerSelectionTests: XCTestCase {

    // MARK: - Recording fakes

    private struct LaunchCall: Equatable {
        let target: BrowserTarget
        let browserBundleID: String
    }

    private final class RecordingLauncher: BrowserLaunching, @unchecked Sendable {
        private(set) var calls: [LaunchCall] = []
        func launch(target: BrowserTarget, browser: Browser, url: URL) throws {
            calls.append(LaunchCall(target: target, browserBundleID: browser.bundleID))
        }
    }

    private final class RecordingLastUsed: LastUsedRecording {
        private(set) var recorded: [BrowserTarget] = []
        func get() -> BrowserTarget? { nil }
        func set(_ target: BrowserTarget) { recorded.append(target) }
    }

    private struct RememberCall: Equatable {
        let url: URL
        let destination: RoutingDestination
    }

    private final class RecordingRulePersister: RulePersisting, @unchecked Sendable {
        private(set) var calls: [RememberCall] = []
        func remember(url: URL, destination: RoutingDestination) {
            calls.append(RememberCall(url: url, destination: destination))
        }
    }

    private struct StubIconProvider: BrowserIconProviding {
        func icon(for browser: Browser) -> NSImage {
            NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
        }
    }

    // MARK: - Fixtures

    private let url = URL(string: "https://www.x.com/page")!

    private let chrome = Browser(
        bundleID: "com.google.Chrome",
        name: "Google Chrome",
        appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
        profiles: [BrowserProfile(id: "Profile 1", name: "Work")]
    )

    /// A controller wired to its recording collaborators, returned together so the
    /// tests can assert on each effect.
    private struct Harness {
        let controller: PickerPanelController
        let launcher: RecordingLauncher
        let lastUsed: RecordingLastUsed
        let persister: RecordingRulePersister
    }

    private func makeController() -> Harness {
        let launcher = RecordingLauncher()
        let lastUsed = RecordingLastUsed()
        let persister = RecordingRulePersister()
        let controller = PickerPanelController(
            launcher: launcher,
            lastUsedStore: lastUsed,
            rulePersister: persister,
            iconProvider: StubIconProvider(),
            onOpenSettings: { _ in }
        )
        return Harness(controller: controller, launcher: launcher, lastUsed: lastUsed, persister: persister)
    }

    // MARK: - browser/profile selection

    func testSelectingBrowserRowLaunchesTargetAndRemembersBrowserDestination() throws {
        let harness = makeController()
        let vm = harness.controller.makeViewModel(url: url, browsers: [chrome])
        vm.rememberChoice = true

        let work = chrome.profiles[0] // "Profile 1"
        vm.select(browser: chrome, profile: work)

        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        XCTAssertEqual(harness.launcher.calls, [LaunchCall(target: target, browserBundleID: "com.google.Chrome")])
        XCTAssertEqual(harness.lastUsed.recorded, [target])
        XCTAssertEqual(harness.persister.calls, [RememberCall(url: url, destination: .browser(target))])
    }

    func testNotRememberingDoesNotPersist() {
        let harness = makeController()
        let vm = harness.controller.makeViewModel(url: url, browsers: [chrome])
        // rememberChoice stays false.

        vm.select(browser: chrome, profile: nil)

        XCTAssertEqual(harness.launcher.calls.count, 1)
        XCTAssertTrue(harness.persister.calls.isEmpty)
    }

    // MARK: - alias selection

    func testSelectingAliasRowLaunchesResolvedTargetAndRemembersAliasDestination() throws {
        let alias = ProfileAlias(
            name: "Work",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        )
        let harness = makeController()
        let vm = harness.controller.makeViewModel(url: url, browsers: [chrome], aliases: [alias])
        vm.rememberChoice = true

        let aliasRow = try XCTUnwrap(vm.selectableItems.first { item in
            if case .alias = item.kind { return true }
            return false
        })
        vm.select(item: aliasRow)

        // Launch + last-used use the alias's resolved concrete target.
        XCTAssertEqual(harness.launcher.calls, [LaunchCall(target: alias.target, browserBundleID: "com.google.Chrome")])
        XCTAssertEqual(harness.lastUsed.recorded, [alias.target])
        // Remember persists the reusable alias destination, not the frozen target.
        XCTAssertEqual(harness.persister.calls.count, 1)
        XCTAssertEqual(harness.persister.calls.first?.destination, .alias(alias.id))
    }

    // MARK: - no-installed-browser recovery

    func testSelectingStaleTargetRecoversWithoutLaunchingOrRemembering() throws {
        // A launch target whose browser isn't among the offered browsers (a
        // stale/edge target) must NOT launch, NOT record last-used, and NOT
        // persist — instead the picker re-presents to recover the link.
        let harness = makeController()
        let vm = harness.controller.makeViewModel(url: url, browsers: [chrome])
        vm.rememberChoice = true

        // Synthesize a browser-kind item pointing at an uninstalled browser.
        let staleBrowser = Browser(
            bundleID: "com.unknown.Browser",
            name: "Unknown",
            appURL: URL(fileURLWithPath: "/Applications/Unknown.app"),
            profiles: []
        )
        vm.select(item: .init(id: "stale", kind: .browser(staleBrowser, nil)))

        XCTAssertTrue(harness.launcher.calls.isEmpty)
        XCTAssertTrue(harness.lastUsed.recorded.isEmpty)
        XCTAssertTrue(harness.persister.calls.isEmpty)
        // Recovery re-presents a live panel.
        XCTAssertTrue(harness.controller.isPickerVisible)
    }
}
