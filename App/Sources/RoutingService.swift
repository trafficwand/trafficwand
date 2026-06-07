import Foundation
import TrafficWandCore
import os

/// Supplies the installed browsers offered for routing/picking.
///
/// A thin App-side seam over `WorkspaceBrowserProvider` so `RoutingService` can be
/// unit-tested with a stub list instead of a live `NSWorkspace` query.
protocol InstalledBrowsersProviding {
    /// Returns the installed http(s)-handling browsers with profiles attached.
    func installedBrowsers() -> [Browser]
}

/// Reads and records the last-used routing target.
///
/// A narrow App-side seam over `LastUsedStore` (read for the `.lastUsed` fallback,
/// write to remember each `.open`) so `RoutingService` can be tested with a mock.
protocol LastUsedRecording {
    /// Returns the last-used target, or `nil` if none has been recorded.
    func get() -> BrowserTarget?
    /// Records `target` as the most recently used routing destination.
    func set(_ target: BrowserTarget)
}

extension WorkspaceBrowserProvider: InstalledBrowsersProviding {}
extension LastUsedStore: LastUsedRecording {}

/// Composes the pure Core `Router` with the App's adapters to carry out routing.
///
/// `route(url:)` is the single entry point used by `application(_:open:)`:
///  1. load the current `AppConfig` (via `ConfigStore`),
///  2. gather available browsers (via the provider),
///  3. read the last-used target (via `LastUsedStore`),
///  4. ask `Router.decide(...)` for a `RoutingDecision`, then
///  5. act on it:
///     - `.open(target)` → resolve the matching `Browser` for the target's bundle
///       ID and launch via `BrowserLaunching`, recording the target as last-used.
///     - `.prompt(url:browsers:)` → hand off to `PickerPresenting`.
///
/// Every collaborator is injected, so the whole composition is unit-testable with
/// mocks. `RoutingService` itself makes **no** `NSWorkspace`/`Process` calls — all
/// system effects live behind the injected protocols.
@MainActor
final class RoutingService {
    private static let logger = Logger(subsystem: AppIdentity.subsystem, category: "routing")

    private let configStore: ConfigStore
    private let browserProvider: InstalledBrowsersProviding
    private let launcher: BrowserLaunching
    private let lastUsedStore: LastUsedRecording
    private let picker: PickerPresenting

    /// - Parameters:
    ///   - configStore: Source of the current `AppConfig`.
    ///   - browserProvider: Supplies the available browsers.
    ///   - launcher: Carries out `.open` decisions.
    ///   - lastUsedStore: Records the last-used target on each `.open`.
    ///   - picker: Presents the UI for `.prompt` decisions.
    init(
        configStore: ConfigStore,
        browserProvider: InstalledBrowsersProviding,
        launcher: BrowserLaunching,
        lastUsedStore: LastUsedRecording,
        picker: PickerPresenting
    ) {
        self.configStore = configStore
        self.browserProvider = browserProvider
        self.launcher = launcher
        self.lastUsedStore = lastUsedStore
        self.picker = picker
    }

    /// Routes a single link to its destination per the current configuration.
    ///
    /// A corrupt/unreadable config degrades to `AppConfig.default` (picker
    /// fallback) so a link is never dropped on a configuration error.
    func route(url: URL) {
        let config = (try? configStore.load()) ?? .default
        let browsers = browserProvider.installedBrowsers()
        let lastUsed = lastUsedStore.get()

        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: lastUsed,
            availableBrowsers: browsers
        )

        switch decision {
        case .open(let target):
            open(target: target, url: url, browsers: browsers)
        case .prompt(let promptURL, let promptBrowsers):
            picker.presentPicker(url: promptURL, browsers: promptBrowsers)
        }
    }

    /// Launches `target` for `url`, recording it as last-used.
    ///
    /// If the target's browser is not among the available browsers (a stale rule or
    /// a `.defaultBrowser` pointing at a removed/renamed browser) there is no
    /// `appURL` to launch. Rather than silently drop the link, fall back to the
    /// picker so the user can still choose a destination — the "never drop a link"
    /// principle. In that case last-used is NOT recorded for the unresolvable
    /// target (it would mislead the `.lastUsed` fallback toward a browser that no
    /// longer exists); the picker records whatever the user actually picks.
    private func open(target: BrowserTarget, url: URL, browsers: [Browser]) {
        guard let browser = browsers.first(where: { $0.bundleID == target.bundleID }) else {
            let bundleID = target.bundleID
            let link = url.absoluteString
            Self.logger.error(
                """
                No installed browser for target bundle ID \(bundleID, privacy: .public); \
                presenting picker for \(link, privacy: .public)
                """
            )
            picker.presentPicker(url: url, browsers: browsers)
            return
        }

        lastUsedStore.set(target)

        do {
            try launcher.launch(target: target, browser: browser, url: url)
        } catch {
            let bundleID = target.bundleID
            let link = url.absoluteString
            let reason = String(describing: error)
            Self.logger.error(
                """
                Failed to launch \(link, privacy: .public) in \(bundleID, privacy: .public): \
                \(reason, privacy: .public)
                """
            )
        }
    }
}
