import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `PickerViewModel` (Task 16).
///
/// The view model is the fully unit-testable heart of the picker popup. It holds
/// the URL being routed and the offered browsers, and turns a user choice into a
/// `BrowserTarget` (bundle ID + optional profile), a "copy URL" action, or a
/// cancel (no selection). It depends only on injected closures for the side
/// effects (the resolved target / the copied string), so the live panel display
/// and keyboard handling are the only untested parts (Post-Completion).
///
/// These tests drive each user action and assert the resolved outcome via the
/// injected closures.
@MainActor
final class PickerViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private let url = URL(string: "https://gist.github.com/foo")!

    private let chrome = Browser(
        bundleID: "com.google.Chrome",
        name: "Google Chrome",
        appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
        profiles: [
            BrowserProfile(id: "Default", name: "Personal"),
            BrowserProfile(id: "Profile 1", name: "Work")
        ]
    )

    private let safari = Browser(
        bundleID: "com.apple.Safari",
        name: "Safari",
        appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
        profiles: []
    )

    /// Records the picker's outcomes as the injected closures fire.
    ///
    /// `selectedTarget` is the chosen `BrowserTarget` (nil until a selection is
    /// made); `rememberFlag` is the remember-choice flag passed alongside the
    /// selection; `copiedString` is the copied URL string (nil until "copy URL");
    /// `cancelCount` increments each time `onCancel` fires; `openedSettingsTabs`
    /// accumulates each tab the view model asked to open (empty until
    /// `openSettings(tab:)` is called).
    private final class Outcomes: @unchecked Sendable {
        var selectedTarget: BrowserTarget?
        var rememberFlag: Bool?
        var copiedString: String?
        var cancelCount: Int = 0
        var openedSettingsTabs: [SettingsTab] = []
    }

    /// Builds a view model wired to a fresh `Outcomes` recorder, returning both.
    private func makeViewModel(
        browsers: [Browser],
        url: URL? = nil
    ) -> (PickerViewModel, Outcomes) {
        let outcomes = Outcomes()
        let vm = PickerViewModel(
            url: url ?? self.url,
            browsers: browsers,
            onSelect: { target, remember in
                outcomes.selectedTarget = target
                outcomes.rememberFlag = remember
            },
            onCancel: { outcomes.cancelCount += 1 },
            onCopy: { outcomes.copiedString = $0 },
            onOpenSettings: { outcomes.openedSettingsTabs.append($0) }
        )
        return (vm, outcomes)
    }

    // MARK: - select browser, no profile

    func testSelectBrowserWithNoProfileYieldsTargetWithNilProfile() {
        let (vm, outcomes) = makeViewModel(browsers: [safari])

        vm.select(browser: safari, profile: nil)

        XCTAssertEqual(outcomes.selectedTarget, BrowserTarget(bundleID: "com.apple.Safari", profileID: nil))
    }

    // MARK: - select browser + specific profile

    func testSelectBrowserWithProfileYieldsTargetWithThatProfileID() {
        let (vm, outcomes) = makeViewModel(browsers: [chrome])

        let work = chrome.profiles[1] // id "Profile 1"
        vm.select(browser: chrome, profile: work)

        XCTAssertEqual(
            outcomes.selectedTarget,
            BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        )
    }

    // MARK: - copy URL

    func testCopyURLYieldsTheURLString() {
        let (vm, outcomes) = makeViewModel(browsers: [chrome])

        vm.copyURL()

        XCTAssertEqual(outcomes.copiedString, url.absoluteString)
        // Copying is not a selection.
        XCTAssertNil(outcomes.selectedTarget)
    }

    // MARK: - cancel

    func testCancelYieldsNoSelection() {
        let (vm, outcomes) = makeViewModel(browsers: [chrome])

        vm.cancel()

        XCTAssertNil(outcomes.selectedTarget)
        XCTAssertNil(outcomes.copiedString)
        XCTAssertEqual(outcomes.cancelCount, 1)
    }

    // MARK: - exposed url string

    func testURLStringIsExposed() {
        let (vm, _) = makeViewModel(browsers: [chrome])
        XCTAssertEqual(vm.urlString, url.absoluteString)
    }

    // MARK: - remember choice

    func testRememberChoiceDefaultsToFalse() {
        let (vm, _) = makeViewModel(browsers: [chrome])
        XCTAssertFalse(vm.rememberChoice)
    }

    func testSelectForwardsRememberChoiceFalse() {
        let (vm, outcomes) = makeViewModel(browsers: [safari])

        vm.select(browser: safari, profile: nil)

        XCTAssertEqual(outcomes.rememberFlag, false)
    }

    func testSelectForwardsRememberChoiceTrue() {
        let (vm, outcomes) = makeViewModel(browsers: [safari])

        vm.rememberChoice = true
        vm.select(browser: safari, profile: nil)

        XCTAssertEqual(outcomes.rememberFlag, true)
    }

    func testRememberHostUsesRegistrableDomain() {
        let (vm, _) = makeViewModel(
            browsers: [chrome],
            url: URL(string: "https://www.x.com/path")!
        )
        XCTAssertEqual(vm.rememberHost, "x.com")
    }

    func testRememberHostFallsBackToRawHostForIPLiteral() {
        let (vm, _) = makeViewModel(
            browsers: [chrome],
            url: URL(string: "http://192.168.0.1/admin")!
        )
        XCTAssertEqual(vm.rememberHost, "192.168.0.1")
    }

    func testRememberHostIsNilForHostlessURL() {
        let (vm, _) = makeViewModel(
            browsers: [chrome],
            url: URL(string: "mailto:foo@example.com")!
        )
        XCTAssertNil(vm.rememberHost)
    }

    func testRememberHostFallsBackToLowercasedSingleLabelHost() {
        let (vm, _) = makeViewModel(
            browsers: [chrome],
            url: URL(string: "http://localhost:3000/")!
        )
        // No registrable domain → falls back to the lowercased exact host, matching
        // the lowercase pattern RememberRule persists for single-label hosts.
        XCTAssertEqual(vm.rememberHost, "localhost")
    }

    func testRememberHostLowercasesRawHostFallback() {
        let (vm, _) = makeViewModel(
            browsers: [chrome],
            url: URL(string: "http://LOCALHOST:3000/")!
        )
        XCTAssertEqual(vm.rememberHost, "localhost")
    }

    // MARK: - selectable items flattening

    func testSelectableItemsFlattensBrowsersThenProfiles() {
        // Chrome (2 profiles) then Safari (no profiles): expect Chrome default,
        // Chrome "Personal", Chrome "Work", then Safari default.
        let (vm, _) = makeViewModel(browsers: [chrome, safari])

        let items = vm.selectableItems
        XCTAssertEqual(items.count, 4)

        XCTAssertEqual(items[0].browser.bundleID, "com.google.Chrome")
        XCTAssertNil(items[0].profile)

        XCTAssertEqual(items[1].browser.bundleID, "com.google.Chrome")
        XCTAssertEqual(items[1].profile?.id, "Default")

        XCTAssertEqual(items[2].browser.bundleID, "com.google.Chrome")
        XCTAssertEqual(items[2].profile?.id, "Profile 1")

        XCTAssertEqual(items[3].browser.bundleID, "com.apple.Safari")
        XCTAssertNil(items[3].profile)

        // IDs are stable and unique.
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    }

    func testSelectableItemIDsDoNotCollideWithDefaultNamedProfile() throws {
        // Firefox profiles are commonly named literally "default"/"default-release",
        // and BrowserProfile.id is that name. Ensure the default-row sentinel id can
        // never collide with a profile whose id is "default".
        let firefox = Browser(
            bundleID: "org.mozilla.firefox",
            name: "Firefox",
            appURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            profiles: [
                BrowserProfile(id: "default", name: "default"),
                BrowserProfile(id: "default-release", name: "default-release")
            ]
        )
        let (vm, _) = makeViewModel(browsers: [firefox])

        let items = vm.selectableItems
        XCTAssertEqual(items.count, 3) // default row + 2 profiles

        // All ids are unique despite the "default"-named profile.
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)

        // The browser-default item (profile == nil) and the "default"-named profile
        // item are distinct entries with distinct ids.
        let defaultRow = try XCTUnwrap(items.first(where: { $0.profile == nil }))
        let defaultNamedProfileRow = try XCTUnwrap(
            items.first(where: { $0.profile?.id == "default" })
        )
        XCTAssertNotEqual(defaultRow.id, defaultNamedProfileRow.id)
    }

    // MARK: - keyboard navigation

    func testMoveSelectionClampsAtLowerBound() {
        let (vm, _) = makeViewModel(browsers: [chrome, safari])

        XCTAssertEqual(vm.selectedIndex, 0)
        vm.moveSelection(by: -1)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func testMoveSelectionClampsAtUpperBound() {
        let (vm, _) = makeViewModel(browsers: [chrome, safari]) // 4 items, max index 3

        vm.moveSelection(by: 100)
        XCTAssertEqual(vm.selectedIndex, 3)

        vm.moveSelection(by: 1)
        XCTAssertEqual(vm.selectedIndex, 3)
    }

    func testMoveSelectionMovesWithinBounds() {
        let (vm, _) = makeViewModel(browsers: [chrome, safari])

        vm.moveSelection(by: 2)
        XCTAssertEqual(vm.selectedIndex, 2)

        vm.moveSelection(by: -1)
        XCTAssertEqual(vm.selectedIndex, 1)
    }

    func testMoveSelectionIsNoOpForEmptyList() {
        let (vm, _) = makeViewModel(browsers: [])

        vm.moveSelection(by: 1)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func testActivateSelectionSelectsHighlightedItem() {
        let (vm, outcomes) = makeViewModel(browsers: [chrome, safari])

        // Index 2 is Chrome "Work" (id "Profile 1").
        vm.selectedIndex = 2
        vm.activateSelection()

        XCTAssertEqual(
            outcomes.selectedTarget,
            BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        )
    }

    func testActivateSelectionSelectsBrowserDefault() {
        let (vm, outcomes) = makeViewModel(browsers: [chrome, safari])

        // Index 3 is the Safari default (no profile).
        vm.selectedIndex = 3
        vm.activateSelection()

        XCTAssertEqual(
            outcomes.selectedTarget,
            BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)
        )
    }

    func testActivateSelectionIsNoOpForEmptyList() {
        let (vm, outcomes) = makeViewModel(browsers: [])

        vm.activateSelection()
        XCTAssertNil(outcomes.selectedTarget)
    }

    // MARK: - open settings

    func testOpenSettingsRulesInvokesClosureWithRulesTab() {
        let (vm, outcomes) = makeViewModel(browsers: [chrome])

        vm.openSettings(tab: .rules)

        XCTAssertEqual(outcomes.openedSettingsTabs, [.rules])
        // Opening settings is not a selection / copy / cancel side-effect.
        XCTAssertNil(outcomes.selectedTarget)
        XCTAssertNil(outcomes.copiedString)
        XCTAssertEqual(outcomes.cancelCount, 0)
    }

    func testOpenSettingsGeneralInvokesClosureWithGeneralTab() {
        let (vm, outcomes) = makeViewModel(browsers: [chrome])

        vm.openSettings(tab: .general)

        XCTAssertEqual(outcomes.openedSettingsTabs, [.general])
        XCTAssertEqual(outcomes.cancelCount, 0)
    }
}
