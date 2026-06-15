#if DEBUG
import AppKit
import Foundation
import TrafficWandCore

/// Shared sample data and mock seams for SwiftUI `#Preview` blocks.
///
/// `#Preview` code compiles into the **app target**, never the test target, so the
/// mocks in `App/Tests/AppTests/` are invisible to previews. This file fills that
/// gap: it provides preview-only sample browsers/rules plus the mock trio
/// (`ConfigStore` / `InstalledBrowsersProviding` / `UpdaterControlling`) the
/// Settings UI depends on, so each Settings view can be previewed with a fully
/// wired `SettingsViewModel`.
///
/// Everything here is `internal` (not `private`) so the DEBUG test target can
/// `@testable import TrafficWand` and assert the fixtures stay valid (see
/// `PreviewFixturesTests`). The whole file is `#if DEBUG`-guarded so none of it
/// ships in release builds.
enum PreviewFixtures {

    /// Sample installed browsers. Chrome carries two profiles (Personal + Work);
    /// Firefox and Safari carry none. Bundle IDs are the real ones so previews look
    /// representative.
    static let sampleBrowsers: [Browser] = [
        Browser(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            profiles: [
                BrowserProfile(id: "Default", name: "Personal"),
                BrowserProfile(id: "Profile 1", name: "Work")
            ]
        ),
        Browser(
            bundleID: "org.mozilla.firefox",
            name: "Firefox",
            appURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            profiles: []
        ),
        Browser(
            bundleID: "com.apple.Safari",
            name: "Safari",
            appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            profiles: []
        )
    ]

    /// A sample alias ("Personal" → Chrome / Personal profile) referenced by one of
    /// the sample rules, so previews exercise the alias-backed destination path.
    static let personalAlias = ProfileAlias(
        name: "Personal",
        target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Default")
    )

    /// Sample reusable aliases. Each `target.bundleID` references a browser in
    /// `sampleBrowsers` (`PreviewFixturesTests` asserts this).
    static let sampleAliases: [ProfileAlias] = [
        personalAlias,
        ProfileAlias(
            name: "Work",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        )
    ]

    /// Sample routing rules covering the interesting states: enabled/disabled, a
    /// concrete `.browser` destination (with and without a profile), and an `.alias`
    /// destination. Every concrete `target.bundleID` references a browser in
    /// `sampleBrowsers`, and the `.alias` references `personalAlias`
    /// (`PreviewFixturesTests` asserts both).
    static let sampleRules: [Rule] = [
        Rule(
            pattern: "github.com",
            destination: .browser(BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")),
            isEnabled: true
        ),
        Rule(
            pattern: "*.example.com",
            destination: .browser(BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)),
            isEnabled: true
        ),
        Rule(
            pattern: "personal.example",
            destination: .alias(personalAlias.id),
            isEnabled: true
        ),
        Rule(
            pattern: "old-intranet.local",
            destination: .browser(BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)),
            isEnabled: false
        )
    ]

    /// A populated config used by the default factory path.
    static let populatedConfig = AppConfig(aliases: sampleAliases, rules: sampleRules, fallback: .picker)

    /// An empty config used to exercise the empty-state preview.
    static let emptyConfig = AppConfig(rules: [], fallback: .picker)

    /// Builds a fully wired `SettingsViewModel` for previews from the mock trio and
    /// calls `load()` so its `rules`/`browsers` are populated.
    ///
    /// - Parameter config: the config the mock store returns on `load()`. Defaults to
    ///   `populatedConfig`; pass `emptyConfig` for the empty-state preview.
    @MainActor
    static func makePreviewSettingsViewModel(
        config: AppConfig = PreviewFixtures.populatedConfig
    ) -> SettingsViewModel {
        let viewModel = SettingsViewModel(
            configStore: PreviewConfigStore(config: config),
            browserProvider: PreviewBrowserProvider(),
            updater: PreviewUpdater()
        )
        viewModel.load()
        return viewModel
    }
}

/// Preview `ConfigStore`: an immutable `struct` (so it is naturally `Sendable`).
/// `load` returns a fixed config; `save` is a no-op — previews never persist.
struct PreviewConfigStore: ConfigStore {
    let config: AppConfig
    func load() throws -> AppConfig { config }
    func save(_ config: AppConfig) throws {}
}

/// Preview browser provider: returns the shared sample browsers.
struct PreviewBrowserProvider: InstalledBrowsersProviding {
    func installedBrowsers() -> [Browser] { PreviewFixtures.sampleBrowsers }
}

/// Preview update seam: stores the auto-check preference, always reports it can
/// check, and no-ops the actual check.
@MainActor
final class PreviewUpdater: UpdaterControlling {
    var automaticallyChecksForUpdates = true
    var canCheckForUpdates = true
    func checkForUpdates() {}
}

/// Preview `BrowserIconProviding`: a browser's real macOS app icon when that app is
/// installed on disk, and a per-family SF Symbol fallback otherwise.
///
/// The sample browsers point at the real `/Applications/...` paths, so on a dev
/// machine the picker preview shows the actual browser logos via the same
/// `WorkspaceBrowserIconProvider` the app uses at runtime. The fallback keeps the
/// preview deterministic (and the rows visually distinct) on a machine where a
/// browser happens to be missing — `#Preview` should never break just because Brave
/// isn't installed. Family classification reuses Core's `BrowserFamily`.
struct PreviewIconProvider: BrowserIconProviding {
    func icon(for browser: Browser) -> NSImage {
        if FileManager.default.fileExists(atPath: browser.appURL.path) {
            return WorkspaceBrowserIconProvider().icon(for: browser)
        }
        let symbolName: String
        switch BrowserFamily(bundleID: browser.bundleID) {
        case .safari: symbolName = "safari"
        case .firefox: symbolName = "flame"
        case .chromium: symbolName = "globe"
        }
        // All three are valid system symbols, so the force-unwrap is safe (matches the
        // menu-bar icon pattern); `PreviewFixturesTests` guards against a typo here.
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
    }
}
#endif
