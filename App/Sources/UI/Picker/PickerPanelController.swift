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
///    `BrowserLaunching` and record it via the injected `LastUsedRecording`, then
///    dismiss;
///  - **cancel** → just dismiss;
///  - **copy URL** → write the string to the general `NSPasteboard`.
///
/// The launcher and last-used store are injected so the controller is
/// constructible and its wiring is reviewable; the live panel display + keyboard
/// handling are the untested parts (Post-Completion manual verification).
@MainActor
final class PickerPanelController: PickerPresenting {
    private static let logger = Logger(subsystem: "com.tomakado.TrafficWand", category: "picker")

    private let launcher: BrowserLaunching
    private let lastUsedStore: LastUsedRecording

    /// The currently-shown panel, retained while visible so it is not deallocated
    /// mid-display; cleared on dismiss.
    private var panel: NSPanel?

    /// - Parameters:
    ///   - launcher: Launches the chosen target on selection.
    ///   - lastUsedStore: Records the chosen target as last-used on selection.
    init(launcher: BrowserLaunching, lastUsedStore: LastUsedRecording) {
        self.launcher = launcher
        self.lastUsedStore = lastUsedStore
    }

    // MARK: - PickerPresenting

    func presentPicker(url: URL, browsers: [Browser]) {
        let viewModel = PickerViewModel(
            url: url,
            browsers: browsers,
            onSelect: { [weak self] target in
                self?.handleSelection(target: target, url: url, browsers: browsers)
            },
            onCancel: { [weak self] in
                self?.dismiss()
            },
            onCopy: { string in
                Self.copyToPasteboard(string)
            }
        )

        showPanel(hosting: BrowserPickerView(viewModel: viewModel))
    }

    // MARK: - Outcomes

    /// Launches the chosen target and records it as last-used, then dismisses.
    ///
    /// Records last-used regardless of whether the browser resolves, mirroring
    /// `RoutingService.open` so a `.lastUsed` fallback reflects the user's most
    /// recent intent. A missing browser (no `appURL`) or a launch failure is
    /// logged, never fatal.
    private func handleSelection(target: BrowserTarget, url: URL, browsers: [Browser]) {
        lastUsedStore.set(target)

        defer { dismiss() }

        guard let browser = browsers.first(where: { $0.bundleID == target.bundleID }) else {
            Self.logger.error(
                "Picker selected a target with no installed browser: \(target.bundleID, privacy: .public)"
            )
            return
        }

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
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
        panel.title = "Open Link"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()

        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes and releases the current panel, if any.
    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
