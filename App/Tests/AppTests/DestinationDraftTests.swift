import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `DestinationDraft` — the pure mode↔`RoutingDestination` mapping that
/// backs the extracted `DestinationEditor` control (the "Browser vs Alias" segmented
/// editor shared by the rule editor and the fallback editor).
///
/// The SwiftUI `DestinationEditor` view itself isn't unit-testable, but its decision
/// logic — seeding the mode/selection from a destination, keeping both sides'
/// selection independent, and mapping the active mode back to a `RoutingDestination`
/// — lives in this value type so it can be asserted directly.
@MainActor
final class DestinationDraftTests: XCTestCase {

    private func browser(_ bundleID: String, profiles: [BrowserProfile] = []) -> Browser {
        Browser(
            bundleID: bundleID,
            name: bundleID,
            appURL: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            profiles: profiles
        )
    }

    private let chrome = "com.google.Chrome"
    private let firefox = "org.mozilla.firefox"

    // MARK: - Seeding from a destination

    func testSeedsBrowserModeFromBrowserDestination() {
        let target = BrowserTarget(bundleID: chrome, profileID: "Profile 2")
        let draft = DestinationDraft(
            destination: .browser(target),
            browsers: [browser(chrome)],
            aliases: []
        )
        XCTAssertEqual(draft.mode, .browser)
        XCTAssertEqual(draft.target, target)
    }

    func testSeedsAliasModeFromAliasDestination() {
        let aliasID = UUID()
        let alias = ProfileAlias(id: aliasID, name: "Work", target: BrowserTarget(bundleID: firefox, profileID: nil))
        let draft = DestinationDraft(
            destination: .alias(aliasID),
            browsers: [browser(chrome)],
            aliases: [alias]
        )
        XCTAssertEqual(draft.mode, .alias)
        XCTAssertEqual(draft.aliasID, aliasID)
    }

    /// In browser mode the alias side still defaults to the first alias, so toggling
    /// to Alias mode has a sensible default instead of an empty selection.
    func testBrowserModeSeedsAliasSideToFirstAlias() {
        let alias = ProfileAlias(name: "Personal", target: BrowserTarget(bundleID: firefox, profileID: nil))
        let draft = DestinationDraft(
            destination: .browser(BrowserTarget(bundleID: chrome, profileID: nil)),
            browsers: [browser(chrome)],
            aliases: [alias]
        )
        XCTAssertEqual(draft.aliasID, alias.id)
    }

    /// In alias mode the browser side defaults to the first installed browser.
    func testAliasModeSeedsBrowserSideToFirstBrowser() {
        let alias = ProfileAlias(name: "Personal", target: BrowserTarget(bundleID: firefox, profileID: nil))
        let draft = DestinationDraft(
            destination: .alias(alias.id),
            browsers: [browser(chrome)],
            aliases: [alias]
        )
        XCTAssertEqual(draft.target, BrowserTarget(bundleID: chrome, profileID: nil))
    }

    // MARK: - Mapping the active mode back to a destination

    func testDestinationInBrowserModeIsTheTarget() {
        var draft = DestinationDraft(
            destination: .browser(BrowserTarget(bundleID: chrome, profileID: nil)),
            browsers: [browser(chrome)],
            aliases: []
        )
        draft.target = BrowserTarget(bundleID: firefox, profileID: "Dev")
        XCTAssertEqual(draft.destination, .browser(BrowserTarget(bundleID: firefox, profileID: "Dev")))
    }

    func testDestinationInAliasModeIsTheSelectedAlias() {
        let aliasID = UUID()
        let alias = ProfileAlias(id: aliasID, name: "Work", target: BrowserTarget(bundleID: firefox, profileID: nil))
        let draft = DestinationDraft(
            destination: .alias(aliasID),
            browsers: [browser(chrome)],
            aliases: [alias]
        )
        XCTAssertEqual(draft.destination, .alias(aliasID))
    }

    /// In alias mode with no alias selected, the draft resolves to `nil` so the
    /// editor never clobbers the bound destination with an empty selection.
    func testDestinationInAliasModeWithNoSelectionIsNil() {
        var draft = DestinationDraft(
            destination: .browser(BrowserTarget(bundleID: chrome, profileID: nil)),
            browsers: [browser(chrome)],
            aliases: []
        )
        draft.mode = .alias
        draft.aliasID = nil
        XCTAssertNil(draft.destination)
    }

    /// Independent state: switching Browser → Alias → Browser preserves the browser
    /// target instead of discarding it.
    func testTogglingModesPreservesBothSelections() {
        let aliasID = UUID()
        let alias = ProfileAlias(id: aliasID, name: "Work", target: BrowserTarget(bundleID: firefox, profileID: nil))
        let target = BrowserTarget(bundleID: chrome, profileID: "Profile 2")
        var draft = DestinationDraft(
            destination: .browser(target),
            browsers: [browser(chrome)],
            aliases: [alias]
        )
        // Switch to alias and back.
        draft.mode = .alias
        XCTAssertEqual(draft.destination, .alias(aliasID))
        draft.mode = .browser
        XCTAssertEqual(
            draft.destination,
            .browser(target),
            "Browser selection survives a round-trip through Alias mode."
        )
    }
}
