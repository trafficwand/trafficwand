import Foundation
import Observation
import TrafficWandCore

/// The observable state and decision logic backing the picker popup.
///
/// This is the fully unit-testable heart of the picker. It holds the URL being
/// routed and the offered browsers, and turns a user action into one of three
/// outcomes, each delivered through an injected closure so the view model itself
/// performs **no** AppKit / launching / pasteboard work:
///
///  - `select(browser:profile:)` → resolves a `BrowserTarget` (bundle ID + the
///    chosen profile's family-native id, or `nil` for the default profile) and
///    hands it to `onSelect`. The controller launches it and records last-used.
///  - `copyURL()` → hands the URL string to `onCopy` (the actual `NSPasteboard`
///    write is the controller's / view's thin closure), keeping the decision
///    (what string to copy) testable.
///  - `cancel()` → invokes `onCancel`; no selection is produced (the picker is
///    simply dismissed and the link dropped, per Task 16 semantics).
///
/// SwiftUI views observe the `@Observable` state (`urlString`, `browsers`) and
/// call these methods; the floating `NSPanel` host (`PickerPanelController`)
/// supplies the closures.
@MainActor
@Observable
final class PickerViewModel {
    /// The link awaiting a destination.
    let url: URL

    /// The browsers (with profiles) offered to the user.
    let browsers: [Browser]

    /// The URL rendered in the panel and copied by `copyURL()`.
    var urlString: String { url.absoluteString }

    /// Delivers the chosen routing target on selection.
    private let onSelect: (BrowserTarget) -> Void

    /// Invoked when the user cancels (Esc / Cancel). Yields no selection.
    private let onCancel: () -> Void

    /// Delivers the URL string to copy (the actual pasteboard write is injected).
    private let onCopy: (String) -> Void

    /// - Parameters:
    ///   - url: The link being routed.
    ///   - browsers: The browsers (with profiles) to offer.
    ///   - onSelect: Receives the resolved `BrowserTarget` when the user picks a
    ///     browser (and optionally a profile).
    ///   - onCancel: Invoked when the user dismisses the picker without choosing.
    ///   - onCopy: Receives the URL string when the user copies it; the caller
    ///     performs the actual pasteboard write.
    init(
        url: URL,
        browsers: [Browser],
        onSelect: @escaping (BrowserTarget) -> Void,
        onCancel: @escaping () -> Void,
        onCopy: @escaping (String) -> Void
    ) {
        self.url = url
        self.browsers = browsers
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onCopy = onCopy
    }

    /// Selects `browser` (and optionally `profile`) as the routing destination.
    ///
    /// Builds a `BrowserTarget` carrying the browser's bundle ID and the chosen
    /// profile's family-native id (`nil` → launch the default profile) and hands
    /// it to `onSelect`.
    func select(browser: Browser, profile: BrowserProfile?) {
        let target = BrowserTarget(bundleID: browser.bundleID, profileID: profile?.id)
        onSelect(target)
    }

    /// Copies the URL string via the injected `onCopy` closure.
    func copyURL() {
        onCopy(urlString)
    }

    /// Cancels the picker: invokes `onCancel`, producing no selection.
    func cancel() {
        onCancel()
    }
}
