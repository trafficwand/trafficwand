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
/// The status-bar menu (Task 14), Settings (Task 15), and the real picker panel
/// (Task 16) are added in later tasks; until then `.prompt` decisions are handed
/// to a logging placeholder presenter.
@main
final class AppMain: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.tomakado.TrafficWand", category: "intake")

    /// The composed routing pipeline (Core `Router` + App adapters). Built once in
    /// `applicationDidFinishLaunching`; used for every incoming link.
    private var routingService: RoutingService?

    /// The menu-bar status item controller. Retained for the app's lifetime so the
    /// status item stays installed; built in `applicationDidFinishLaunching`.
    private var statusBarController: StatusBarController?

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
        // Settings… is a placeholder hook until Task 15 installs the real window.
        statusBarController = StatusBarController(
            onOpenSettings: { [weak self] in self?.openSettings() }
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

    /// Placeholder hook for the status-bar "Settings…" item.
    ///
    /// Task 15 replaces this with the real Settings window; for now it logs so the
    /// action is observable and there is no dead/broken reference.
    private func openSettings() {
        Self.logger.log("Settings requested (placeholder; Task 15).")
    }

    /// Assembles the real `RoutingService` from the concrete adapters.
    ///
    /// `FileConfigStore` points at `~/Library/Application Support/TrafficWand`,
    /// `WorkspaceBrowserProvider` enumerates installed browsers, `BrowserLauncher`
    /// performs the spike-chosen launch, and `LastUsedStore` persists the last-used
    /// target. The picker is the Task 16 placeholder for now.
    @MainActor
    private static func makeRoutingService() -> RoutingService {
        RoutingService(
            configStore: FileConfigStore(directory: configDirectory()),
            browserProvider: WorkspaceBrowserProvider(),
            launcher: BrowserLauncher(),
            lastUsedStore: LastUsedStore(),
            picker: PlaceholderPickerPresenter()
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

/// Temporary `PickerPresenting` until the real floating panel lands in Task 16.
///
/// Logs the request so `.prompt` decisions are observable during interim manual
/// testing; replaced by `PickerPanelController` in Task 16.
@MainActor
private struct PlaceholderPickerPresenter: PickerPresenting {
    private static let logger = Logger(subsystem: "com.tomakado.TrafficWand", category: "picker")

    func presentPicker(url: URL, browsers: [Browser]) {
        Self.logger.log(
            "Picker requested for \(url.absoluteString, privacy: .public) over \(browsers.count) browser(s) (placeholder; Task 16)."
        )
    }
}
