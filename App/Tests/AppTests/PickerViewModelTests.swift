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
    /// made); `copiedString` is the copied URL string (nil until "copy URL").
    private final class Outcomes: @unchecked Sendable {
        var selectedTarget: BrowserTarget?
        var copiedString: String?
    }

    /// Builds a view model wired to a fresh `Outcomes` recorder, returning both.
    private func makeViewModel(browsers: [Browser]) -> (PickerViewModel, Outcomes) {
        let outcomes = Outcomes()
        let vm = PickerViewModel(
            url: url,
            browsers: browsers,
            onSelect: { outcomes.selectedTarget = $0 },
            onCancel: { },
            onCopy: { outcomes.copiedString = $0 }
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
    }

    // MARK: - exposed url string

    func testURLStringIsExposed() {
        let (vm, _) = makeViewModel(browsers: [chrome])
        XCTAssertEqual(vm.urlString, url.absoluteString)
    }
}
