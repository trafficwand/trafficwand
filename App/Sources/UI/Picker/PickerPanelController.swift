import AppKit
import SwiftUI
import TrafficWandCore
import os

/// Presents the interactive picker in a floating, centered `NSPanel` and carries
/// out the user's choice.
///
/// Conforms to `PickerPresenting`, so `RoutingService` hands every `.prompt`
/// decision here. `presentPicker(url:browsers:)` builds a `PickerViewModel`, hosts
/// `BrowserPickerView` in a nonactivating utility `NSPanel` (so the menu-bar
/// agent can show it without becoming a regular foreground app), and wires the
/// view model's outcomes:
///
///  - **selection** → launch the chosen `BrowserTarget` via the injected
///    `BrowserLaunching`, record it via the injected `LastUsedRecording`, and (when
///    the user ticked "remember") persist a routing rule via the injected
///    `RulePersisting`, then dismiss;
///  - **cancel** → just dismiss;
///  - **copy URL** → write the string to the general `NSPasteboard`.
///
/// The launcher, last-used store, rule persister, and icon provider are injected so
/// the controller is constructible and its wiring is reviewable; the live panel
/// display + keyboard handling are the untested parts (Post-Completion manual
/// verification).
@MainActor
final class PickerPanelController: NSObject, PickerPresenting, NSWindowDelegate {
    private static let logger = Logger(subsystem: AppIdentity.subsystem, category: "picker")

    private let launcher: BrowserLaunching
    private let lastUsedStore: LastUsedRecording
    private let rulePersister: RulePersisting
    private let iconProvider: BrowserIconProviding

    /// The currently-shown panel, retained while visible so it is not deallocated
    /// mid-display; cleared on dismiss.
    private var panel: NSPanel?

    /// - Parameters:
    ///   - launcher: Launches the chosen target on selection.
    ///   - lastUsedStore: Records the chosen target as last-used on selection.
    ///   - rulePersister: Persists a routing rule when the user ticks "remember".
    ///   - iconProvider: Supplies each browser's real app icon to the picker view.
    init(
        launcher: BrowserLaunching,
        lastUsedStore: LastUsedRecording,
        rulePersister: RulePersisting,
        iconProvider: BrowserIconProviding
    ) {
        self.launcher = launcher
        self.lastUsedStore = lastUsedStore
        self.rulePersister = rulePersister
        self.iconProvider = iconProvider
        super.init()
    }

    // MARK: - PickerPresenting

    func presentPicker(url: URL, browsers: [Browser]) {
        let viewModel = PickerViewModel(
            url: url,
            browsers: browsers,
            onSelect: { [weak self] target, remember in
                self?.handleSelection(target: target, url: url, browsers: browsers, remember: remember)
            },
            onCancel: { [weak self] in
                self?.dismiss()
            },
            onCopy: { string in
                Self.copyToPasteboard(string)
            }
        )

        showPanel(hosting: BrowserPickerView(viewModel: viewModel, iconProvider: iconProvider))
    }

    // MARK: - Outcomes

    /// Launches the chosen target and records it as last-used, then dismisses.
    ///
    /// If the selected target's browser cannot be resolved among `browsers` (it
    /// should not happen — the picker only offers targets from that very list — but
    /// defend against it), the link is NOT dropped: the picker is re-presented so
    /// the user can pick again, and the unresolvable target is NOT recorded as
    /// last-used nor remembered. On a resolvable selection, last-used is recorded,
    /// the choice is persisted as a routing rule when `remember` is set, and the
    /// chosen target launched; a launch failure is logged, never fatal.
    private func handleSelection(target: BrowserTarget, url: URL, browsers: [Browser], remember: Bool) {
        guard let browser = browsers.first(where: { $0.bundleID == target.bundleID }) else {
            Self.logger.error(
                """
                Picker selected a target with no installed browser: \
                \(target.bundleID, privacy: .public); re-presenting picker
                """
            )
            // Recover rather than lose the link: show the picker again.
            presentPicker(url: url, browsers: browsers)
            return
        }

        lastUsedStore.set(target)

        if remember {
            rulePersister.remember(url: url, target: target)
        }

        defer { dismiss() }

        do {
            try launcher.launch(target: target, browser: browser, url: url)
        } catch {
            let detail = "\(url.absoluteString) in \(target.bundleID): \(String(describing: error))"
            Self.logger.error("Picker launch failed: \(detail, privacy: .public)")
        }
    }

    /// Writes `string` to the general pasteboard (the picker's "copy URL").
    private static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: - Panel lifecycle

    /// Builds and shows the floating, centered panel hosting `view`.
    ///
    /// The panel is a nonactivating utility `NSPanel` so the `.accessory`/
    /// `LSUIElement` agent can present it without becoming a regular foreground
    /// app, yet `NSApp.activate` brings it forward and makes it key so keyboard
    /// selection (and Esc to cancel) works.
    private func showPanel(hosting view: BrowserPickerView) {
        // Replace any previously-shown panel.
        dismiss()

        let hosting = NSHostingController(rootView: view)
        // Drive the window size from the SwiftUI content's ideal size. Without this
        // the panel keeps its default (too-short) content height and the browser
        // list — laid out below the header — is clipped off the bottom.
        hosting.sizingOptions = [.preferredContentSize]
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
        // Observe the title-bar close button: closing that way bypasses the
        // in-view Cancel, so clear our retained reference (treat it as a cancel —
        // the link simply isn't opened) instead of leaking the panel.
        panel.delegate = self
        panel.title = "Open Link"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Size the content to the SwiftUI fitting size before centering, so the full
        // browser list is visible (belt-and-suspenders with `sizingOptions` above).
        panel.setContentSize(hosting.view.fittingSize)
        panel.center()

        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes and releases the current panel, if any.
    private func dismiss() {
        // Avoid re-entrancy with `windowWillClose` (orderOut does not post that
        // notification, but clearing first keeps the delegate callback a no-op).
        let current = panel
        panel = nil
        current?.delegate = nil
        current?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// Handles the title-bar close button: the user dismissed the picker without
    /// choosing, so just drop our retained reference (a cancel — the link is not
    /// opened) and avoid leaking the panel.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSPanel) === panel else { return }
        panel?.delegate = nil
        panel = nil
    }
}
