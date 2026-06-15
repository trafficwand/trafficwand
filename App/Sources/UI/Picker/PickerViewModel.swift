import Foundation
import Observation
import TrafficWandCore

/// The observable state and decision logic backing the picker popup.
///
/// This is the fully unit-testable heart of the picker. It holds the URL being
/// routed and the offered browsers, and turns a user action into one of four
/// outcomes, each delivered through an injected closure so the view model itself
/// performs **no** AppKit / launching / pasteboard work:
///
///  - `select(item:)` (or `select(browser:profile:)`) → resolves the concrete
///    `BrowserTarget` to launch **and** the `RoutingDestination` to remember, and
///    hands both to `onSelect` along with the current `rememberChoice` flag. For an
///    alias row the launch target is the alias's resolved `BrowserTarget` while the
///    remember destination is `.alias(id)` (the reusable, late-binding rule); for a
///    browser/profile row both collapse to `.browser(target)`. The controller
///    launches the concrete target and records last-used, and when `rememberChoice`
///    is true it persists a routing rule for the site (an alias rule for an alias
///    pick, a concrete rule otherwise).
///  - `copyURL()` → hands the URL string to `onCopy` (the actual `NSPasteboard`
///    write is the controller's / view's thin closure), keeping the decision
///    (what string to copy) testable.
///  - `cancel()` → invokes `onCancel`; no selection is produced (the picker is
///    simply dismissed and the link dropped).
///  - `openSettings(tab:)` → hands the requested `SettingsTab` to
///    `onOpenSettings` (gear button → `.rules`, `⌘,` → `.general`); the
///    controller performs the actual window open + picker dismiss.
///
/// SwiftUI views observe the `@Observable` state (`selectableItems`,
/// `selectedIndex`, `rememberChoice`, `rememberHost`) and call these methods; the
/// floating `NSPanel` host (`PickerPanelController`) supplies the closures.
@MainActor
@Observable
final class PickerViewModel {
    /// The link awaiting a destination.
    let url: URL

    /// The browsers (with profiles) offered to the user.
    let browsers: [Browser]

    /// The reusable aliases offered to the user (rendered as the "Aliases" section
    /// at the top of the list). Only aliases whose `target.bundleID` is among the
    /// offered `browsers` are surfaced as rows (an uninstalled-target alias can't
    /// launch); see `selectableItems`.
    let aliases: [ProfileAlias]

    /// The URL rendered in the panel and copied by `copyURL()`.
    var urlString: String { url.absoluteString }

    /// Whether the user asked to remember this choice for the site (persist a
    /// routing rule). Bound to the picker's "Remember choice" checkbox and
    /// forwarded to `onSelect` so the controller can persist a rule.
    var rememberChoice: Bool = false

    /// The host label shown next to the "Remember choice" checkbox.
    ///
    /// Computed from the URL's host via `RegistrableDomain.of(host:)` so the label
    /// matches exactly what gets persisted. Falls back to the lowercased `url.host`
    /// when there is no registrable domain (e.g. an IP literal or a single-label
    /// host such as `localhost`) so the checkbox label matches the lowercased
    /// exact-host pattern `RememberRule` will persist, and is `nil` when the URL has
    /// no host at all (the view hides the checkbox when `nil`).
    var rememberHost: String? {
        guard let host = url.host else { return nil }
        return RegistrableDomain.of(host: host) ?? host.lowercased()
    }

    /// One selectable destination in the flattened picker list: a reusable alias,
    /// a browser's default, or a specific profile of a browser.
    struct SelectableItem: Identifiable {
        /// Stable identity:
        /// - alias rows are `"alias:<uuid>"` (the `alias:` prefix can't collide
        ///   with the `bundleID#…` forms);
        /// - the browser's bundle ID plus a structurally-distinct suffix for the
        ///   default row (`#self`) versus a profile row (`#profile:<profile.id>`).
        ///   The `profile:` prefix keeps a profile whose id happens to be `self` —
        ///   or, more realistically, a Firefox profile literally named
        ///   `default`/`default-release` — from ever colliding with the
        ///   default-row sentinel. Unique within the list. Stays a `String` so the
        ///   view's `hoveredItemID: SelectableItem.ID` and `ForEach`/keyboard
        ///   identity keep working.
        let id: String

        /// What this row represents: a reusable alias, or a browser with an
        /// optional profile (`nil` → the browser's default profile).
        let kind: Kind

        // swiftlint:disable:next nesting
        enum Kind {
            case alias(ProfileAlias)
            case browser(Browser, BrowserProfile?)
        }

        /// The concrete `BrowserTarget` to launch when this row is chosen: the
        /// alias's resolved target for an alias row, or the browser's bundle ID +
        /// the chosen profile's id for a browser/profile row.
        var launchTarget: BrowserTarget {
            switch kind {
            case .alias(let alias):
                return alias.target
            case .browser(let browser, let profile):
                return BrowserTarget(bundleID: browser.bundleID, profileID: profile?.id)
            }
        }

        /// The `RoutingDestination` to persist when "Remember choice" is ticked: an
        /// `.alias(id)` for an alias row (the reusable, late-binding rule) or a
        /// concrete `.browser(target)` otherwise.
        var rememberDestination: RoutingDestination {
            switch kind {
            case .alias(let alias):
                return .alias(alias.id)
            case .browser:
                return .browser(launchTarget)
            }
        }
    }

    /// The flattened, ordered list of selectable destinations: the installed
    /// aliases first (in order), then for each browser its default row followed by
    /// one row per profile in display order.
    let selectableItems: [SelectableItem]

    /// Index of the keyboard-highlighted item within `selectableItems`.
    var selectedIndex: Int = 0

    /// The selection callback shape: the concrete `BrowserTarget` to launch, the
    /// `RoutingDestination` to persist (an `.alias(id)` for an alias pick, a
    /// `.browser(target)` for a concrete pick), and whether to remember the choice.
    typealias SelectHandler = (
        _ launchTarget: BrowserTarget,
        _ rememberDestination: RoutingDestination,
        _ remember: Bool
    ) -> Void

    /// Delivers, on selection, the launch target, the remember destination, and the
    /// remember flag (see ``SelectHandler``).
    private let onSelect: SelectHandler

    /// Invoked when the user cancels (Esc / Cancel). Yields no selection.
    private let onCancel: () -> Void

    /// Delivers the URL string to copy (the actual pasteboard write is injected).
    private let onCopy: (String) -> Void

    /// Invoked when the user asks to open Settings from the picker (gear icon or
    /// `⌘,` shortcut). The argument is the deep-link tab to land on.
    private let onOpenSettings: (SettingsTab) -> Void

    /// - Parameters:
    ///   - url: The link being routed.
    ///   - browsers: The browsers (with profiles) to offer.
    ///   - aliases: The reusable aliases to offer at the top of the list. Aliases
    ///     whose `target.bundleID` is not among `browsers` (uninstalled targets,
    ///     which can't launch) are filtered out.
    ///   - onSelect: Receives the concrete `BrowserTarget` to launch, the
    ///     `RoutingDestination` to remember, and whether to remember the choice.
    ///   - onCancel: Invoked when the user dismisses the picker without choosing.
    ///   - onCopy: Receives the URL string when the user copies it; the caller
    ///     performs the actual pasteboard write.
    ///   - onOpenSettings: Receives the `SettingsTab` the user asked to land on
    ///     when opening Settings from the picker (gear → `.rules`, `⌘,` →
    ///     `.general`).
    init(
        url: URL,
        browsers: [Browser],
        aliases: [ProfileAlias] = [],
        onSelect: @escaping SelectHandler,
        onCancel: @escaping () -> Void,
        onCopy: @escaping (String) -> Void,
        onOpenSettings: @escaping (SettingsTab) -> Void
    ) {
        self.url = url
        self.browsers = browsers
        self.aliases = aliases
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onCopy = onCopy
        self.onOpenSettings = onOpenSettings

        // Alias rows first, filtered to those whose target browser is installed
        // (an uninstalled-target alias can't launch, so it would dead-end).
        let installedBundleIDs = Set(browsers.map(\.bundleID))
        let aliasItems = aliases
            .filter { installedBundleIDs.contains($0.target.bundleID) }
            .map { alias in
                SelectableItem(id: "alias:\(alias.id.uuidString)", kind: .alias(alias))
            }

        // Then flatten browsers → (default, then profiles) into one ordered list.
        let browserItems = browsers.flatMap { browser -> [SelectableItem] in
            let defaultItem = SelectableItem(
                id: "\(browser.bundleID)#self",
                kind: .browser(browser, nil)
            )
            let profileItems = browser.profiles.map { profile in
                SelectableItem(
                    id: "\(browser.bundleID)#profile:\(profile.id)",
                    kind: .browser(browser, profile)
                )
            }
            return [defaultItem] + profileItems
        }

        self.selectableItems = aliasItems + browserItems
    }

    /// Selects `item` as the routing destination, handing its concrete
    /// `launchTarget` and `rememberDestination` to `onSelect` along with the
    /// current `rememberChoice` flag.
    func select(item: SelectableItem) {
        onSelect(item.launchTarget, item.rememberDestination, rememberChoice)
    }

    /// Selects `browser` (and optionally `profile`) as the routing destination.
    ///
    /// Looks the matching row up in `selectableItems` (rather than re-deriving its id
    /// scheme, which would risk drifting from `init`) and delegates to `select(item:)`.
    /// `nil` profile → the browser's default row. Falls back to a freshly-built item if
    /// no matching row exists (e.g. a browser not among the offered list). A test-only
    /// convenience; production selection flows through `select(item:)`.
    func select(browser: Browser, profile: BrowserProfile?) {
        let item = selectableItems.first { item in
            guard case .browser(let rowBrowser, let rowProfile) = item.kind else { return false }
            return rowBrowser.bundleID == browser.bundleID && rowProfile?.id == profile?.id
        } ?? SelectableItem(
            id: profile.map { "\(browser.bundleID)#profile:\($0.id)" } ?? "\(browser.bundleID)#self",
            kind: .browser(browser, profile)
        )
        select(item: item)
    }

    /// Moves the keyboard highlight by `delta`, clamping to the bounds of
    /// `selectableItems` (no wraparound). No-op when the list is empty.
    func moveSelection(by delta: Int) {
        guard !selectableItems.isEmpty else { return }
        let proposed = selectedIndex + delta
        selectedIndex = min(max(proposed, 0), selectableItems.count - 1)
    }

    /// Selects the currently highlighted item, if any.
    func activateSelection() {
        guard selectableItems.indices.contains(selectedIndex) else { return }
        select(item: selectableItems[selectedIndex])
    }

    /// The resolved "Browser — Profile" (or just "Browser") label for a concrete
    /// `target`, using the offered `browsers` to resolve names. Returns `nil` when the
    /// target's browser is not among the offered browsers (e.g. an alias whose target
    /// is uninstalled), so the row can hide the secondary line.
    ///
    /// Pure decision logic kept on the view model (per CLAUDE.md) so the picker rows
    /// stay declarative and this labeling is unit-testable.
    func browserLabel(for target: BrowserTarget) -> String? {
        guard let browser = browsers.first(where: { $0.bundleID == target.bundleID }) else {
            return nil
        }
        if let profileID = target.profileID,
           let profile = browser.profiles.first(where: { $0.id == profileID }) {
            return "\(browser.name) — \(profile.name)"
        }
        return browser.name
    }

    /// Copies the URL string via the injected `onCopy` closure.
    func copyURL() {
        onCopy(urlString)
    }

    /// Cancels the picker: invokes `onCancel`, producing no selection.
    func cancel() {
        onCancel()
    }

    /// Asks the host to open Settings on the given tab via the injected closure.
    ///
    /// The view model itself doesn't dismiss the picker or touch any window — the
    /// controller (`PickerPanelController.handleOpenSettings`) is responsible for
    /// performing the actual open + dismiss when this fires.
    func openSettings(tab: SettingsTab) {
        onOpenSettings(tab)
    }
}
