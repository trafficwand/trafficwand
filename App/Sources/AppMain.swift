import AppKit
import os

/// Minimal application entry point for the Task 1 scaffold.
///
/// At this stage the app only needs to:
/// - launch as a menu-bar agent (`.accessory` activation policy / `LSUIElement`),
/// - register as an `http`/`https` URL handler (declared in `Info.plist`), and
/// - prove the intake path by logging URLs handed to `application(_:open:)`.
///
/// Real routing, the status-bar menu, Settings, and the picker are added in
/// later tasks.
@main
final class AppMain: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.tomakado.TrafficWand", category: "intake")

    static func main() {
        let app = NSApplication.shared
        let delegate = AppMain()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no main menu activation.
        NSApp.setActivationPolicy(.accessory)
        Self.logger.log("TrafficWand launched (scaffold).")
    }

    /// URL intake stub. In Task 13 this forwards to `RoutingService`; for now it
    /// only logs so the default-browser reality check can confirm links arrive.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Self.logger.log("Received URL: \(url.absoluteString, privacy: .public)")
        }
    }
}
