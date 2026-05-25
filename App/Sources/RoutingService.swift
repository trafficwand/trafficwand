import Foundation
import TrafficWandCore
import os

/// Supplies the installed browsers offered for routing/picking.
///
/// A thin App-side seam over `WorkspaceBrowserProvider` so `RoutingService` can be
/// unit-tested with a stub list instead of a live `NSWorkspace` query.
protocol InstalledBrowsersProviding {
    /// Returns the installed, allowlisted browsers with profiles attached.
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
    private static let logger = Logger(subsystem: "com.tomakado.TrafficWand", category: "routing")

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
    /// Records last-used regardless of whether the browser could be resolved, so a
    /// `.lastUsed` fallback still reflects the user's most recent routing intent.
    /// If the target's browser is not among the available browsers there is no
    /// `appURL` to launch, so the launch is skipped (logged, never crashes).
    private func open(target: BrowserTarget, url: URL, browsers: [Browser]) {
        lastUsedStore.set(target)

        guard let browser = browsers.first(where: { $0.bundleID == target.bundleID }) else {
            Self.logger.error(
                "No installed browser for target bundle ID \(target.bundleID, privacy: .public); cannot launch \(url.absoluteString, privacy: .public)"
            )
            return
        }

        do {
            try launcher.launch(target: target, browser: browser, url: url)
        } catch {
            Self.logger.error(
                "Failed to launch \(url.absoluteString, privacy: .public) in \(target.bundleID, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
