import AppKit
import XCTest
@testable import TrafficWand

/// Tests for the "About TrafficWand" status-bar menu item wiring.
///
/// The pure menu-state decision is covered by `StatusMenuStateTests`; this
/// suite asserts the AppKit shell wiring: that the controller's `NSMenu`
/// contains the new About item (above Settings), that each item targets the
/// controller, and that invoking each action selector runs the right injected
/// closure and *only* that closure.
///
/// We avoid driving real status-bar clicks by reaching into the controller's
/// `menuForTesting` test seam, locating items by title, and calling
/// `controller.perform(item.action!, with: item)` directly.
///
/// Each test removes the status item in `tearDown` so the suite doesn't leak
/// menu-bar entries into the host process.
@MainActor
final class StatusBarControllerAboutTests: XCTestCase {

    /// Bundle of a built controller plus accessors for the hook counters,
    /// so tests can assert which closure fired without juggling a 3-tuple.
    private struct Harness {
        let controller: StatusBarController
        let aboutCount: () -> Int
        let settingsCount: () -> Int
    }

    private var liveHarness: Harness?

    override func tearDown() {
        // Tear down the live status item so we don't leak menu-bar entries
        // across the rest of the suite.
        liveHarness?.controller.removeStatusItemForTesting()
        liveHarness = nil
        super.tearDown()
    }

    /// Builds a controller with both hooks instrumented and returns the
    /// harness wrapping it plus its capture counters.
    ///
    /// Injects a `DefaultBrowserManager(ourBundleID:)` with a fixed-but-empty
    /// bundle ID so the suite stays isolated from the host machine's actual
    /// default-browser state (the live `NSWorkspace` query result is irrelevant
    /// here — these tests don't exercise the default-browser item).
    private func makeHarness() -> Harness {
        // Reference-typed boxes so the closure-captured counters survive
        // mutation across multiple invocations without juggling inout state.
        let aboutBox = IntBox()
        let settingsBox = IntBox()
        let controller = StatusBarController(
            defaultBrowserManager: DefaultBrowserManager(ourBundleID: "test.trafficwand.fixed"),
            onOpenSettings: { settingsBox.value += 1 },
            onOpenAbout: { aboutBox.value += 1 }
        )
        let harness = Harness(
            controller: controller,
            aboutCount: { aboutBox.value },
            settingsCount: { settingsBox.value }
        )
        liveHarness = harness
        return harness
    }

    /// Reference-typed capture cell — closures capture `var Int` by value, so
    /// we need a class to count invocations across the test body.
    private final class IntBox {
        var value = 0
    }

    private func menu(of controller: StatusBarController) -> NSMenu {
        guard let menu = controller.menuForTesting else {
            XCTFail("Controller has no menu — configureMenu() must run during init")
            return NSMenu()
        }
        return menu
    }

    private func item(in controller: StatusBarController, withTitle title: String) -> NSMenuItem? {
        menu(of: controller).items.first { $0.title == title }
    }

    func testAboutMenuItemExistsAboveSettings() {
        let harness = makeHarness()

        let titles = menu(of: harness.controller).items.map(\.title)
        guard let aboutIndex = titles.firstIndex(of: "About TrafficWand"),
              let settingsIndex = titles.firstIndex(of: "Settings…") else {
            XCTFail("Expected both About and Settings items in the menu (titles: \(titles))")
            return
        }
        XCTAssertLessThan(aboutIndex, settingsIndex,
                          "About TrafficWand should appear above Settings…")
    }

    func testAboutMenuItemHasInfoCircleImage() {
        let harness = makeHarness()

        guard let aboutItem = item(in: harness.controller, withTitle: "About TrafficWand") else {
            XCTFail("Missing About TrafficWand item")
            return
        }
        XCTAssertNotNil(aboutItem.image,
                        "About item should carry an SF Symbol icon (info.circle) like macOS conventional About menus")
    }

    func testAboutMenuItemHasNoKeyEquivalent() {
        let harness = makeHarness()

        guard let aboutItem = item(in: harness.controller, withTitle: "About TrafficWand") else {
            XCTFail("Missing About TrafficWand item")
            return
        }
        XCTAssertEqual(aboutItem.keyEquivalent, "",
                       "About item should not have a keyboard shortcut (matches system About convention)")
    }

    /// Without this assertion the most-likely-to-break wiring (the menu item's
    /// `target`) wouldn't be checked — `perform(_:with:)` bypasses the menu's
    /// normal target dispatch, so the per-item action could fire even if the
    /// target were nil at the menu-dispatch level.
    func testAboutMenuItemTargetsController() {
        let harness = makeHarness()

        guard let aboutItem = item(in: harness.controller, withTitle: "About TrafficWand") else {
            XCTFail("Missing About TrafficWand item")
            return
        }
        XCTAssertTrue(aboutItem.target === harness.controller,
                      "About item must target the controller for menu dispatch to reach the action")
    }

    func testSettingsMenuItemTargetsController() {
        let harness = makeHarness()

        guard let settingsItem = item(in: harness.controller, withTitle: "Settings…") else {
            XCTFail("Missing Settings… item")
            return
        }
        XCTAssertTrue(settingsItem.target === harness.controller,
                      "Settings item must target the controller for menu dispatch to reach the action")
    }

    func testInvokingAboutItemRunsOnOpenAboutOnly() {
        let harness = makeHarness()
        guard let aboutItem = item(in: harness.controller, withTitle: "About TrafficWand"),
              let action = aboutItem.action else {
            XCTFail("Missing About item or its action")
            return
        }

        harness.controller.perform(action, with: aboutItem)

        XCTAssertEqual(harness.aboutCount(), 1, "onOpenAbout should have run exactly once")
        XCTAssertEqual(harness.settingsCount(), 0, "onOpenSettings must not run for the About item")
    }

    func testInvokingSettingsItemRunsOnOpenSettingsOnly() {
        let harness = makeHarness()
        guard let settingsItem = item(in: harness.controller, withTitle: "Settings…"),
              let action = settingsItem.action else {
            XCTFail("Missing Settings item or its action")
            return
        }

        harness.controller.perform(action, with: settingsItem)

        XCTAssertEqual(harness.settingsCount(), 1, "onOpenSettings should have run exactly once")
        XCTAssertEqual(harness.aboutCount(), 0, "onOpenAbout must not run for the Settings item")
    }
}
