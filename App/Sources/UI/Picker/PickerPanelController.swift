import AppKit
import SwiftUI
import TrafficWandCore
import os

/// Presents the interactive picker in a borderless, animated popup `NSPanel`
/// and carries out the user's choice.
///
/// Conforms to `PickerPresenting`, so `RoutingService` hands every `.prompt`
/// decision here. `presentPicker(url:browsers:)` builds a `PickerViewModel`, hosts
/// `BrowserPickerView` in a borderless nonactivating `NSPanel` (so the menu-bar
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
final class PickerPanelController: NSObject, PickerPresenting {
    private static let logger = Logger(subsystem: AppIdentity.subsystem, category: "picker")
    /// Sheet-like entrance: ~0.18s feels snappy without being instant. Tune here.
    private static let animationDuration: TimeInterval = 0.18
    /// Vertical pixels the popup slides down on entrance (up on exit).
    private static let entranceSlide: CGFloat = 12

    private let launcher: BrowserLaunching
    private let lastUsedStore: LastUsedRecording
    private let rulePersister: RulePersisting
    private let iconProvider: BrowserIconProviding

    /// The currently-shown panel, retained while visible so it is not deallocated
    /// mid-display; cleared on dismiss.
    private var panel: NSPanel?

    /// Re-entrancy guard for `handleSelection`. The animated dismiss keeps the
    /// panel hit-testable for ~0.18s while alpha fades; a second click (or
    /// repeated Return) on a row during that window would otherwise re-enter
    /// `handleSelection` and launch a second browser / overwrite last-used /
    /// re-persist the remember rule. Set to true at the start of `dismiss()`,
    /// reset when the fade completes or when a fresh panel is shown.
    private var isDismissing = false

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
    /// Bails out if a dismiss animation is in flight — the panel is still
    /// hit-testable during the ~0.18s fade and re-entry here would double-launch.
    ///
    /// If the selected target's browser cannot be resolved among `browsers` (it
    /// should not happen — the picker only offers targets from that very list — but
    /// defend against it), the link is NOT dropped: the picker is re-presented so
    /// the user can pick again, and the unresolvable target is NOT recorded as
    /// last-used nor remembered. On a resolvable selection, last-used is recorded,
    /// the choice is persisted as a routing rule when `remember` is set, and the
    /// chosen target launched; a launch failure is logged, never fatal.
    private func handleSelection(target: BrowserTarget, url: URL, browsers: [Browser], remember: Bool) {
        guard !isDismissing else { return }

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

    /// Builds and shows the borderless, centered popup hosting `view`.
    ///
    /// The panel is a borderless `NSPanel` (no titlebar, no traffic-light
    /// buttons) so the SwiftUI content paints its own card (rounded corners,
    /// system background) — the "popup" silhouette comes from the SwiftUI
    /// view, not from AppKit chrome. The window itself is transparent
    /// (`backgroundColor = .clear`, `isOpaque = false`) with a system drop
    /// shadow that picks up the SwiftUI card's rounded shape; `invalidateShadow`
    /// in the entrance completion ensures the shadow tracks the final frame
    /// instead of a transient shape captured mid-animation.
    ///
    /// Borderless `NSPanel`s return `canBecomeKey = false` by default, which
    /// would silently break Esc / arrow / Return inside the picker — `KeyablePanel`
    /// exists solely to override that, so keyboard selection keeps working.
    ///
    /// `panel.title` is set even though no titlebar renders it — `NSWindow.title`
    /// is still surfaced to Accessibility / VoiceOver as the window's announced
    /// label.
    ///
    /// The entrance is animated (alpha 0→1 plus a small downward slide) over
    /// `Self.animationDuration`, approximating a sheet drop.
    private func showPanel(hosting view: BrowserPickerView) {
        // Synchronously tear down any existing panel (including one still
        // animating out from a prior dismiss) so the new one doesn't overlap
        // a fading predecessor.
        if let existing = panel {
            panel = nil
            existing.orderOut(nil)
        }
        isDismissing = false

        let hosting = NSHostingController(rootView: view)
        // Drive the window size from the SwiftUI content's ideal size. Without this
        // the panel keeps its default (too-short) content height and the browser
        // list — laid out below the header — is clipped off the bottom.
        hosting.sizingOptions = [.preferredContentSize]
        let panel = KeyablePanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        // Invisible without a titlebar, but VoiceOver / AX still announce it.
        panel.title = "Open Link"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Transparent window so only the SwiftUI card (and its shadow) shows.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Force a SwiftUI layout pass before reading fittingSize, otherwise it
        // can return .zero on first presentation and the panel ends up centered
        // with no size until sizingOptions resizes it asynchronously.
        hosting.view.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.view.fittingSize)
        panel.center()

        // Pre-animation state: slightly above final position and fully transparent.
        let finalFrame = panel.frame
        var startFrame = finalFrame
        startFrame.origin.y += Self.entranceSlide
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0

        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }, completionHandler: {
            // Drop shadow on a borderless transparent panel is derived from
            // the opaque region (the SwiftUI card). Invalidate it after the
            // frame animation settles so the shadow tracks the final outline.
            panel.invalidateShadow()
        })
    }

    /// Animates the panel out and orders it out on completion. `isDismissing`
    /// gates `handleSelection` for the duration of the fade so a stray click
    /// on a still-visible row can't double-launch.
    private func dismiss() {
        guard let current = panel else { return }
        panel = nil
        isDismissing = true

        var endFrame = current.frame
        endFrame.origin.y += Self.entranceSlide
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            current.animator().alphaValue = 0
            current.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            current.orderOut(nil)
            self?.isDismissing = false
        })
    }
}

/// Borderless `NSPanel`s return `canBecomeKey = false` by default, which would
/// stop keyboard events (Esc, arrows, Return) from reaching the SwiftUI picker.
/// Overriding both `canBecomeKey` and `canBecomeMain` keeps the picker
/// keyboard-driven without re-introducing a titlebar.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
