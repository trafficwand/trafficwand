import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `PickerViewModel`'s alias rows (the picker-alias-selection plan,
/// Task 2).
///
/// Aliases are prepended to `selectableItems` (filtered to those whose target
/// browser is installed) with `alias:<uuid>` ids; selecting an alias row yields the
/// alias's resolved concrete `BrowserTarget` to launch and an `.alias(id)` remember
/// destination. The browser/profile-row behaviour and keyboard mechanics live in
/// `PickerViewModelTests`.
@MainActor
final class PickerViewModelAliasTests: XCTestCase {

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

    private let chromeWorkAlias = ProfileAlias(
        name: "Work",
        target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
    )

    private let safariAlias = ProfileAlias(
        name: "Personal",
        target: BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)
    )

    private final class Outcomes: @unchecked Sendable {
        var selectedTarget: BrowserTarget?
        var rememberDestination: RoutingDestination?
    }

    private func makeViewModel(
        browsers: [Browser],
        aliases: [ProfileAlias]
    ) -> (PickerViewModel, Outcomes) {
        let outcomes = Outcomes()
        let vm = PickerViewModel(
            url: url,
            browsers: browsers,
            aliases: aliases,
            onSelect: { launchTarget, rememberDestination, _ in
                outcomes.selectedTarget = launchTarget
                outcomes.rememberDestination = rememberDestination
            },
            onCancel: {},
            onCopy: { _ in },
            onOpenSettings: { _ in }
        )
        return (vm, outcomes)
    }

    private func alias(of item: PickerViewModel.SelectableItem) -> ProfileAlias? {
        if case .alias(let alias) = item.kind { return alias }
        return nil
    }

    private func browser(of item: PickerViewModel.SelectableItem) -> Browser? {
        if case .browser(let browser, _) = item.kind { return browser }
        return nil
    }

    // MARK: - alias rows

    func testAliasesAreListedFirstInOrderWithAliasIDs() throws {
        // Two installed-target aliases (Chrome "Work", Safari "Personal") then the
        // browser/profile rows. Aliases appear first, in the order given, with
        // `alias:<uuid>` ids.
        let (vm, _) = makeViewModel(
            browsers: [chrome, safari],
            aliases: [chromeWorkAlias, safariAlias]
        )

        let items = vm.selectableItems
        // 2 alias rows + Chrome default + 2 Chrome profiles + Safari default = 6.
        XCTAssertEqual(items.count, 6)

        XCTAssertEqual(items[0].id, "alias:\(chromeWorkAlias.id.uuidString)")
        XCTAssertEqual(alias(of: items[0]), chromeWorkAlias)
        XCTAssertEqual(items[1].id, "alias:\(safariAlias.id.uuidString)")
        XCTAssertEqual(alias(of: items[1]), safariAlias)

        // The third item is the first browser row.
        XCTAssertEqual(browser(of: items[2])?.bundleID, "com.google.Chrome")
        XCTAssertNil(alias(of: items[2]))

        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    }

    func testAliasWithUninstalledTargetIsExcluded() {
        // `safariAlias` targets Safari, which is NOT among the offered browsers, so
        // it must be filtered out; `chromeWorkAlias` (Chrome installed) stays.
        let (vm, _) = makeViewModel(
            browsers: [chrome],
            aliases: [chromeWorkAlias, safariAlias]
        )

        let aliasRows = vm.selectableItems.compactMap { alias(of: $0) }
        XCTAssertEqual(aliasRows, [chromeWorkAlias])
    }

    func testSelectingAliasRowYieldsAliasTargetAndAliasDestination() throws {
        let (vm, outcomes) = makeViewModel(
            browsers: [chrome, safari],
            aliases: [chromeWorkAlias]
        )

        let aliasRow = try XCTUnwrap(vm.selectableItems.first(where: { alias(of: $0) != nil }))
        vm.select(item: aliasRow)

        XCTAssertEqual(outcomes.selectedTarget, chromeWorkAlias.target)
        XCTAssertEqual(outcomes.rememberDestination, .alias(chromeWorkAlias.id))
    }

    func testActivateSelectionOverAliasRowYieldsAliasDestination() {
        let (vm, outcomes) = makeViewModel(
            browsers: [chrome, safari],
            aliases: [chromeWorkAlias]
        )

        // Index 0 is the alias row (aliases are prepended).
        vm.selectedIndex = 0
        vm.activateSelection()

        XCTAssertEqual(outcomes.selectedTarget, chromeWorkAlias.target)
        XCTAssertEqual(outcomes.rememberDestination, .alias(chromeWorkAlias.id))
    }

    func testArrowKeyNavigationReachesAliasRows() {
        // With one alias prepended, index 0 is the alias row and arrow-down reaches
        // the browser rows beyond it.
        let (vm, _) = makeViewModel(
            browsers: [chrome, safari],
            aliases: [chromeWorkAlias]
        )

        XCTAssertNotNil(alias(of: vm.selectableItems[0]))
        vm.moveSelection(by: 1)
        XCTAssertEqual(vm.selectedIndex, 1)
        XCTAssertNil(alias(of: vm.selectableItems[vm.selectedIndex]))
    }
}
