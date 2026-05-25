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
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let defaultBrowserManager: DefaultBrowserManager

    /// Invoked when the user picks "Settings…". A placeholder hook until Task 15
    /// installs the real Settings window; defaults to a no-op so there is no
    /// dead/broken reference now.
    private let onOpenSettings: () -> Void

    /// The default-browser item, retained so `menuWillOpen` can refresh its
    /// title/checkmark to reflect the current default-handler status.
    private let defaultBrowserMenuItem = NSMenuItem()

    /// - Parameters:
    ///   - defaultBrowserManager: Source of truth for whether TrafficWand is the
    ///     default browser and the way to request becoming it.
    ///   - onOpenSettings: Hook invoked for the "Settings…" item. Task 15 fills
    ///     this in with the real Settings window; defaults to a no-op.
    init(
        defaultBrowserManager: DefaultBrowserManager = DefaultBrowserManager(),
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.defaultBrowserManager = defaultBrowserManager
        self.onOpenSettings = onOpenSettings
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "wand.and.stars",
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
