import AppKit
import TrafficWandCore
import os

/// Application entry point and URL intake.
///
/// TrafficWand runs as a menu-bar agent (`.accessory` activation policy /
/// `LSUIElement`), registers as an `http`/`https` URL handler (declared in
/// `Info.plist`), and forwards every link the system hands to
/// `application(_:open:)` to `RoutingService`.
///
/// The status-bar menu, Settings, and the picker panel compose the rest of the
/// app; `.prompt` decisions are presented by the real `PickerPanelController`.
@main
final class AppMain: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: AppIdentity.subsystem, category: "intake")

    /// The composed routing pipeline (Core `Router` + App adapters). Built once in
    /// `applicationDidFinishLaunching`; used for every incoming link.
    private var routingService: RoutingService?

    /// The menu-bar status item controller. Retained for the app's lifetime so the
    /// status item stays installed; built in `applicationDidFinishLaunching`.
    private var statusBarController: StatusBarController?

    /// The Settings window controller. Retained so the window persists across
    /// open/close; built lazily in `applicationDidFinishLaunching`.
    private var settingsWindowController: SettingsWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppMain()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no main menu activation.
        NSApp.setActivationPolicy(.accessory)
        routingService = Self.makeRoutingService()

        // Settings window: the view model depends only on Core (FileConfigStore) and
        // the App provider seam (WorkspaceBrowserProvider); the window controller
        // hosts the SwiftUI views and activates the app when shown.
        let settingsViewModel = SettingsViewModel(
            configStore: FileConfigStore(directory: Self.configDirectory()),
            browserProvider: WorkspaceBrowserProvider()
        )
        settingsWindowController = SettingsWindowController(viewModel: settingsViewModel)

        statusBarController = StatusBarController(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenAbout: { [weak self] in self?.openAbout() }
        )
        Self.logger.log("TrafficWand launched.")
    }

    /// URL intake: forward each link to `RoutingService` for routing.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let routingService else {
            Self.logger.error("Received URLs before routing service was ready; dropping.")
            return
        }
        for url in urls {
            Self.logger.log("Routing URL: \(url.absoluteString, privacy: .public)")
            routingService.route(url: url)
        }
    }

    /// Shows the Settings window (status-bar "Settings…" item hook).
    ///
    /// The window controller activates the app and brings the window forward, since
    /// TrafficWand is an `.accessory`/`LSUIElement` agent with no regular windows.
    @MainActor
    private func openSettings() {
        Self.logger.log("Opening Settings window.")
        settingsWindowController?.show()
    }

    /// Shows the Settings window deep-linked to the About tab (status-bar
    /// "About TrafficWand…" item hook).
    @MainActor
    private func openAbout() {
        Self.logger.log("Opening About (Settings → About tab).")
        settingsWindowController?.show(initialTab: .about)
    }

    /// Assembles the real `RoutingService` from the concrete adapters.
    ///
    /// `FileConfigStore` points at `~/Library/Application Support/TrafficWand` and is
    /// hoisted into a shared `configStore` so the router and the picker's
    /// `ConfigRuleStore` read/write the *same* config — a remembered choice persisted
    /// by the picker is then seen by routing. `WorkspaceBrowserProvider` enumerates
    /// installed browsers, `BrowserLauncher` performs the spike-chosen launch, and
    /// `LastUsedStore` persists the last-used target. `.prompt` decisions are
    /// presented by `PickerPanelController`, which reuses the same launcher +
    /// last-used store, persists remembered choices through `ConfigRuleStore`, and
    /// renders real browser icons via `WorkspaceBrowserIconProvider`.
    @MainActor
    private static func makeRoutingService() -> RoutingService {
        let configStore = FileConfigStore(directory: configDirectory())
        let launcher = BrowserLauncher()
        let lastUsedStore = LastUsedStore()
        return RoutingService(
            configStore: configStore,
            browserProvider: WorkspaceBrowserProvider(),
            launcher: launcher,
            lastUsedStore: lastUsedStore,
            picker: PickerPanelController(
                launcher: launcher,
                lastUsedStore: lastUsedStore,
                rulePersister: ConfigRuleStore(configStore: configStore),
                iconProvider: WorkspaceBrowserIconProvider()
            )
        )
    }

    /// `~/Library/Application Support/TrafficWand`, created lazily by the store.
    private static func configDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TrafficWand", isDirectory: true)
    }
}
