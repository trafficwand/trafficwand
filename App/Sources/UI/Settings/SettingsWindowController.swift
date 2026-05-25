import AppKit
import SwiftUI
import TrafficWandCore

/// Hosts `SettingsRootView` in a real `NSWindow` via `NSHostingController`.
///
/// TrafficWand is an `.accessory`/`LSUIElement` menu-bar agent with no regular
/// windows, so showing Settings must explicitly activate the app and bring the
/// window forward (otherwise the window can appear behind other apps or not take
/// focus). The controller lazily builds the window on first show and reuses it on
/// subsequent shows, re-loading the view model each time so the window reflects the
/// latest persisted config and installed browsers.
///
/// Dual-writer note: the picker is a *second* writer to `config.json` (it persists
/// a remembered rule via `ConfigRuleStore` while Settings holds an in-memory rule
/// array). To avoid a lost update when Settings is left open and the user remembers
/// a choice in the picker elsewhere, the controller also reloads the view model
/// whenever this window *becomes key* (regains focus). That re-reads the latest
/// on-disk config — picking up any picker-added rule — before the user edits.
/// A theoretical instant-of-edit race (an external save landing between a keystroke
/// and `persist()`, with no focus change) remains; closing it would require an
/// optimistic-merge/locking persistence refactor that is out of scope here.
@MainActor
final class SettingsWindowController {
    private let viewModel: SettingsViewModel
    private let defaultBrowserManager: DefaultBrowserManager
    private var windowController: NSWindowController?

    /// Observer token for the window's `didBecomeKeyNotification`, kept so it can be
    /// removed and so the closure (which captures `self` weakly) doesn't leak.
    ///
    /// `nonisolated(unsafe)` so the `nonisolated deinit` can read it to deregister;
    /// this is safe because the token is only assigned once on the main actor during
    /// `makeWindowController()` and is never mutated thereafter, and
    /// `NotificationCenter.removeObserver(_:)` is itself thread-safe.
    private nonisolated(unsafe) var didBecomeKeyObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - viewModel: The shared Settings view model (depends only on Core + the
    ///     provider seam).
    ///   - defaultBrowserManager: Passed to the General tab for default-browser
    ///     status and the Set-as-Default action.
    init(
        viewModel: SettingsViewModel,
        defaultBrowserManager: DefaultBrowserManager = DefaultBrowserManager()
    ) {
        self.viewModel = viewModel
        self.defaultBrowserManager = defaultBrowserManager
    }

    /// Shows the Settings window, building it on first call.
    ///
    /// Activates the app and orders the window to the front so it is visible and
    /// focused even though the app is an accessory agent.
    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller

        // Refresh content each time it is shown so it reflects the latest config.
        viewModel.load()

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let root = SettingsRootView(
            viewModel: viewModel,
            defaultBrowserManager: defaultBrowserManager
        )
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(contentViewController: hosting)
        window.title = "TrafficWand Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        // Reload whenever this specific window regains focus so returning to an
        // already-open Settings window re-reads the latest on-disk config (e.g. a
        // rule the picker remembered while Settings was open) before the user edits.
        // `weak self` avoids a retain cycle; the token is removed on deinit.
        didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewModel.load()
            }
        }

        return NSWindowController(window: window)
    }

    deinit {
        if let didBecomeKeyObserver {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
        }
    }
}
