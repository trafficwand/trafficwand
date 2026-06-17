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
/// *any* path — the last page's "Open Settings" button (whose `onFinish` calls
/// `close()`) or the red close button — marks onboarding completed exactly once
/// (`complete()` is idempotent via its `didFinish` guard) and fires `onFinish`.
/// Wire `onFinish` to call `close()`: the button press completes and closes the
/// window; the close re-enters `complete()`, which is now a no-op, so there is no
/// double-fire or recursion.
@MainActor
final class OnboardingWindowController: NSObject {
    /// Fixed onboarding window size. Mirrors `OnboardingRootView`'s `.frame`; set
    /// explicitly so the window has a known size before we compute its centered
    /// origin (the SwiftUI frame is otherwise only applied on the first layout pass).
    private static let contentSize = NSSize(width: 540, height: 600)

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
        // Position explicitly: NSWindow.center() proved unreliable here (it placed
        // the window in a corner), and NSWindowController cascades on showWindow.
        // Compute the centered origin from the active screen's visible frame using
        // the window's real size after layout.
        if let window = controller.window {
            window.setContentSize(Self.contentSize)
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                let size = window.frame.size
                window.setFrameOrigin(NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2
                ))
            }
        }
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Closes the onboarding window (if any). Closing triggers `windowWillClose`,
    /// which marks completion. Wire this as the view model's `onFinish` so the
    /// last-page "Open Settings" button actually dismisses the window.
    func close() {
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
        window.setContentSize(Self.contentSize)

        let controller = NSWindowController(window: window)
        // Don't let the controller cascade the window away from our centered origin.
        controller.shouldCascadeWindows = false
        return controller
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
