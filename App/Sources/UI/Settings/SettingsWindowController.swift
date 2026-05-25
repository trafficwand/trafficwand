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
@MainActor
final class SettingsWindowController {
    private let viewModel: SettingsViewModel
    private let defaultBrowserManager: DefaultBrowserManager
    private var windowController: NSWindowController?

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

        return NSWindowController(window: window)
    }
}
