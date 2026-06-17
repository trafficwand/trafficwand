import AppKit
import SwiftUI

/// Hosts `OnboardingRootView` in a real `NSWindow` via `NSHostingController`,
/// mirroring `SettingsWindowController`.
///
/// TrafficWand is an `.accessory`/`LSUIElement` menu-bar agent with no regular
/// windows, so showing onboarding must explicitly activate the app and bring the
/// window forward (otherwise it can appear behind other apps or not take focus).
/// The controller lazily builds the window on first `show()` and is retained for
/// the app's lifetime alongside the view model it owns.
///
/// **Completion-on-close:** the controller is its own `NSWindowDelegate` and its
/// `windowWillClose(_:)` calls `viewModel.complete()`. So dismissing the window via
/// *any* path — the last page's "Open Settings" button (which also closes), a
/// future "Done" affordance, or the red close button — marks onboarding completed
/// exactly once (the store flag makes `complete()` effectively idempotent) and
/// fires `onFinish`.
@MainActor
final class OnboardingWindowController: NSObject {
    private let viewModel: OnboardingViewModel
    private let defaultBrowserManager: DefaultBrowserManager
    private var windowController: NSWindowController?

    /// - Parameters:
    ///   - viewModel: The onboarding navigation view model; the controller owns and
    ///     retains it for the app's lifetime. `windowWillClose` calls its
    ///     `complete()`.
    ///   - defaultBrowserManager: Passed to the default-browser page for status and
    ///     the Set-as-Default action (held by the view, like `GeneralSettingsView`).
    init(
        viewModel: OnboardingViewModel,
        defaultBrowserManager: DefaultBrowserManager = DefaultBrowserManager()
    ) {
        self.viewModel = viewModel
        self.defaultBrowserManager = defaultBrowserManager
        super.init()
    }

    /// Shows the onboarding window, building it on first call.
    ///
    /// Activates the app and orders the window to the front so it is visible and
    /// focused even though the app is an accessory agent.
    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Test-only: closes the live window (if any), exercising the
    /// `windowWillClose` completion path.
    func closeWindowForTesting() {
        windowController?.close()
    }

    private func makeWindowController() -> NSWindowController {
        let root = OnboardingRootView(
            viewModel: viewModel,
            defaultBrowserManager: defaultBrowserManager
        )
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to TrafficWand"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        return NSWindowController(window: window)
    }
}

// MARK: - NSWindowDelegate

extension OnboardingWindowController: NSWindowDelegate {
    /// Marks onboarding completed when the window is dismissed via any path.
    /// `complete()` is effectively idempotent (the store flag), so closing after
    /// the last-page button already completed is harmless.
    func windowWillClose(_ notification: Notification) {
        viewModel.complete()
    }
}
