import AppKit

/// The **pure** decision logic backing the status-bar menu.
///
/// This holds no AppKit menu state — it only maps inputs (e.g. whether
/// TrafficWand is currently the system default browser) to the title and
/// checkmark a menu item should display. Keeping it separate from
/// `StatusBarController` lets the interesting decision be unit-tested without a
/// live `NSStatusItem`.
enum StatusMenuState {
    /// Title + checkmark state for the default-browser menu item.
    ///
    /// - When TrafficWand is already the default, the item reads as a status
    ///   ("TrafficWand is your default browser") and is checked; selecting it is
    ///   a no-op (re-asserting default is harmless but unnecessary).
    /// - Otherwise it reads as an action ("Set as Default Browser…") and is
    ///   unchecked; selecting it requests default-browser status.
    ///
    /// - Parameter isDefault: Whether TrafficWand currently handles `http`/`https`.
    /// - Returns: The item's `title` and whether it should show a checkmark.
    static func defaultBrowserItem(isDefault: Bool) -> (title: String, isChecked: Bool) {
        if isDefault {
            return (title: "TrafficWand is your default browser", isChecked: true)
        } else {
            return (title: "Set as Default Browser…", isChecked: false)
        }
    }
}

/// Owns the menu-bar status item and its menu.
///
/// The controller is the thin AppKit shell: it builds an `NSStatusItem` with an
/// SF Symbol icon and a menu (Set as Default Browser…, Settings…, Quit), and
/// wires each item's action to the existing managers / app hooks. The
/// *decisions* (the default-browser item's title/checkmark) come from the pure
/// `StatusMenuState`. The live menu visuals are covered by Post-Completion
/// manual verification.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    /// SF Symbol name for the menu-bar status icon. Single source of truth shared
    /// by `configureButton()` and the `#if DEBUG` SwiftUI preview at the bottom of
    /// this file, so the previewed glyph can never drift from the live one.
    static let statusIconSymbolName = "arrow.trianglehead.branch"

    private let statusItem: NSStatusItem
    private let defaultBrowserManager: DefaultBrowserManager

    /// The update seam used to validate the "Check for Updates…" item: the item is
    /// enabled only while `canCheckForUpdates` is true (Sparkle is idle / ready).
    /// Optional so tests that don't exercise update validation can omit it; when
    /// `nil` the item stays enabled (no seam to consult).
    private let updater: UpdaterControlling?

    /// Invoked when the user picks "Settings…". Defaults to a no-op for
    /// testability; `AppMain` injects the real Settings-open hook.
    private let onOpenSettings: () -> Void

    /// Invoked when the user picks "About TrafficWand". Defaults to a no-op
    /// for testability; `AppMain` injects the real About-open hook (which
    /// deep-links the Settings window to the About tab).
    private let onOpenAbout: () -> Void

    /// Invoked when the user picks "Check for Updates…". Defaults to a no-op
    /// for testability; `AppMain` injects a hook that drives the Sparkle
    /// updater seam (`UpdaterControlling.checkForUpdates()`).
    private let onCheckForUpdates: () -> Void

    /// The "Check for Updates…" item, retained so `validateMenuItem(_:)` can
    /// identify it and reflect the updater's `canCheckForUpdates` readiness.
    private let checkForUpdatesMenuItem = NSMenuItem()

    /// The default-browser item, retained so `menuWillOpen` can refresh its
    /// title/checkmark to reflect the current default-handler status.
    private let defaultBrowserMenuItem = NSMenuItem()

    /// Test seam: exposes the live `NSMenu` so tests can locate items by
    /// title and invoke their `action` via `perform(_:with:)` without
    /// driving a real status-item click. Safe to expose — the menu is fully
    /// owned by this controller and is set non-nil at the end of `init` via
    /// `configureMenu()`, so this access is always safe in practice.
    var menuForTesting: NSMenu? { statusItem.menu }

    /// Test-only: removes the underlying `NSStatusItem` from the system status
    /// bar. Without this, each test that constructs a controller would leak a
    /// menu-bar item into the host process for the full test run.
    /// Production code never needs to remove the status item — the controller is
    /// retained for the app's lifetime.
    func removeStatusItemForTesting() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// - Parameters:
    ///   - defaultBrowserManager: Source of truth for whether TrafficWand is the
    ///     default browser and the way to request becoming it.
    ///   - onOpenSettings: Hook invoked for the "Settings…" item. Defaults to a
    ///     no-op for testability; `AppMain` injects the real Settings-open hook.
    ///   - onOpenAbout: Hook invoked for the "About TrafficWand" item. Defaults
    ///     to a no-op for testability; `AppMain` injects a hook that opens the
    ///     Settings window deep-linked to the About tab.
    ///   - onCheckForUpdates: Hook invoked for the "Check for Updates…" item.
    ///     Defaults to a no-op for testability; `AppMain` injects a hook that
    ///     drives the Sparkle updater seam.
    ///   - updater: The update seam consulted by `validateMenuItem(_:)` to enable
    ///     the "Check for Updates…" item only when `canCheckForUpdates` is true.
    ///     Defaults to `nil` (item always enabled) so tests can omit it.
    init(
        defaultBrowserManager: DefaultBrowserManager = DefaultBrowserManager(),
        onOpenSettings: @escaping () -> Void = {},
        onOpenAbout: @escaping () -> Void = {},
        onCheckForUpdates: @escaping () -> Void = {},
        updater: UpdaterControlling? = nil
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.defaultBrowserManager = defaultBrowserManager
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onCheckForUpdates = onCheckForUpdates
        self.updater = updater
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: Self.statusIconSymbolName,
                accessibilityDescription: "TrafficWand"
            )
            button.image?.isTemplate = true
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self

        defaultBrowserMenuItem.target = self
        defaultBrowserMenuItem.action = #selector(setAsDefault)
        refreshDefaultBrowserItem()
        menu.addItem(defaultBrowserMenuItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About TrafficWand",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = NSImage(
            systemSymbolName: "info.circle",
            accessibilityDescription: nil
        )
        menu.addItem(aboutItem)

        checkForUpdatesMenuItem.title = "Check for Updates…"
        checkForUpdatesMenuItem.action = #selector(checkForUpdates)
        checkForUpdatesMenuItem.target = self
        checkForUpdatesMenuItem.image = NSImage(
            systemSymbolName: "arrow.down.circle",
            accessibilityDescription: nil
        )
        menu.addItem(checkForUpdatesMenuItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit TrafficWand",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Refreshes the default-browser item's title and checkmark from the pure
    /// helper, driven by the current default-handler status.
    private func refreshDefaultBrowserItem() {
        let state = StatusMenuState.defaultBrowserItem(isDefault: defaultBrowserManager.isDefault)
        defaultBrowserMenuItem.title = state.title
        defaultBrowserMenuItem.state = state.isChecked ? .on : .off
    }

    // MARK: - NSMenuDelegate

    /// Re-evaluate the default-browser status each time the menu opens so the
    /// checkmark/title always reflect the current state.
    func menuWillOpen(_ menu: NSMenu) {
        refreshDefaultBrowserItem()
    }

    // MARK: - NSMenuItemValidation

    /// Enables the "Check for Updates…" item only while the updater reports it can
    /// start a check (`canCheckForUpdates`); without an injected seam the item stays
    /// enabled. All other items validate as enabled (their own actions handle no-op
    /// cases, e.g. re-asserting default browser).
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === checkForUpdatesMenuItem, let updater {
            return updater.canCheckForUpdates
        }
        return true
    }

    // MARK: - Actions

    @objc private func setAsDefault() {
        // No-op when already the default; the pure helper marks it checked and
        // its title is a status line rather than an action.
        guard !defaultBrowserManager.isDefault else { return }
        defaultBrowserManager.setAsDefault { [weak self] _ in
            Task { @MainActor in self?.refreshDefaultBrowserItem() }
        }
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openAbout() {
        onOpenAbout()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

#if DEBUG
import SwiftUI

/// Preview-only rendering of the menu-bar status glyph.
///
/// The live icon is an `NSImage(systemSymbolName:)` template drawn by AppKit, which
/// has no SwiftUI canvas. This view mirrors it with `Image(systemName:)` using the
/// same shared `StatusBarController.statusIconSymbolName`, rendered as a template
/// over both a light and a dark swatch so the template (monochrome) appearance can be
/// eyeballed in the Xcode canvas.
private struct MenuBarIconPreview: View {
    private func glyph(over background: Color) -> some View {
        Image(systemName: StatusBarController.statusIconSymbolName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(width: 18, height: 18)
            .padding(8)
            .background(background)
    }

    var body: some View {
        HStack(spacing: 0) {
            glyph(over: .white)
                .environment(\.colorScheme, .light)
            glyph(over: .black)
                .environment(\.colorScheme, .dark)
        }
    }
}

#Preview("Menu-bar icon") {
    MenuBarIconPreview()
}
#endif
