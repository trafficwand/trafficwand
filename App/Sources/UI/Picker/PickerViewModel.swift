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
///  - `select(browser:profile:)` → resolves a `BrowserTarget` (bundle ID + the
///    chosen profile's family-native id, or `nil` for the default profile) and
///    hands it to `onSelect` along with the current `rememberChoice` flag. The
///    controller launches it and records last-used, and when `rememberChoice` is
///    true it also persists a routing rule for the site.
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

    /// One selectable destination in the flattened picker list: a browser's
    /// default (when `profile == nil`) or a specific profile of that browser.
    struct SelectableItem: Identifiable {
        /// Stable identity: the browser's bundle ID plus a structurally-distinct
        /// suffix for the default row (`#self`) versus a profile row
        /// (`#profile:<profile.id>`). The `profile:` prefix keeps a profile whose
        /// id happens to be `self` — or, more realistically, a Firefox profile
        /// literally named `default`/`default-release` — from ever colliding with
        /// the default-row sentinel. Unique within the list.
        let id: String
        let browser: Browser
        /// The chosen profile, or `nil` for the browser's default profile.
        let profile: BrowserProfile?
    }

    /// The flattened, ordered list of selectable destinations: for each browser,
    /// its default row first, then one row per profile in display order.
    let selectableItems: [SelectableItem]

    /// Index of the keyboard-highlighted item within `selectableItems`.
    var selectedIndex: Int = 0

    /// Delivers the chosen routing target on selection along with whether the
    /// user asked to remember the choice.
    private let onSelect: (BrowserTarget, _ remember: Bool) -> Void

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
    ///   - onSelect: Receives the resolved `BrowserTarget` when the user picks a
    ///     browser (and optionally a profile), plus whether to remember the choice.
    ///   - onCancel: Invoked when the user dismisses the picker without choosing.
    ///   - onCopy: Receives the URL string when the user copies it; the caller
    ///     performs the actual pasteboard write.
    ///   - onOpenSettings: Receives the `SettingsTab` the user asked to land on
    ///     when opening Settings from the picker (gear → `.rules`, `⌘,` →
    ///     `.general`).
    init(
        url: URL,
        browsers: [Browser],
        onSelect: @escaping (BrowserTarget, _ remember: Bool) -> Void,
        onCancel: @escaping () -> Void,
        onCopy: @escaping (String) -> Void,
        onOpenSettings: @escaping (SettingsTab) -> Void
    ) {
        self.url = url
        self.browsers = browsers
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onCopy = onCopy
        self.onOpenSettings = onOpenSettings

        // Flatten browsers → (default, then profiles) into one ordered list.
        self.selectableItems = browsers.flatMap { browser -> [SelectableItem] in
            let defaultItem = SelectableItem(
                id: "\(browser.bundleID)#self",
                browser: browser,
                profile: nil
            )
            let profileItems = browser.profiles.map { profile in
                SelectableItem(
                    id: "\(browser.bundleID)#profile:\(profile.id)",
                    browser: browser,
                    profile: profile
                )
            }
            return [defaultItem] + profileItems
        }
    }

    /// Selects `browser` (and optionally `profile`) as the routing destination.
    ///
    /// Builds a `BrowserTarget` carrying the browser's bundle ID and the chosen
    /// profile's family-native id (`nil` → launch the default profile) and hands
    /// it to `onSelect` along with the current `rememberChoice` flag.
    func select(browser: Browser, profile: BrowserProfile?) {
        let target = BrowserTarget(bundleID: browser.bundleID, profileID: profile?.id)
        onSelect(target, rememberChoice)
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
        let item = selectableItems[selectedIndex]
        select(browser: item.browser, profile: item.profile)
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
