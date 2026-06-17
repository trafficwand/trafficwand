import AppKit
import TrafficWandCore
import os

/// Application entry point and URL intake.
///
/// TrafficWand runs as a menu-bar agent (`.accessory` activation policy /
/// `LSUIElement`), registers as an `http`/`https` URL handler (declared in
/// `Info.plist`), and forwards every link the system hands to
/// `application(_:open:)` through `LinkIntake` to `RoutingService`.
///
/// On a cold start macOS can deliver the open-URL event before
/// `applicationDidFinishLaunching` has finished wiring the routing pipeline, so
/// intake goes through `LinkIntake`: links that arrive before the pipeline is
/// ready are buffered and flushed in arrival order once launch finishes
/// (cold-start safety — never drop a link).
///
/// The status-bar menu, Settings, and the picker panel compose the rest of the
/// app; `.prompt` decisions are presented by the real `PickerPanelController`.
@main
@MainActor
final class AppMain: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: AppIdentity.subsystem, category: "intake")

    /// The composed routing pipeline (Core `Router` + App adapters). Built once in
    /// `applicationDidFinishLaunching` and retained for the app's lifetime. The live
    /// routing path is the `intake.activate { url in service.route(url:) }` closure,
    /// which captures the local `service` value (not this property) to avoid a retain
    /// cycle; this property holds the same instance so the pipeline stays alive.
    private var routingService: RoutingService?

    /// Buffer-and-flush seam for incoming links. Retained for the app's lifetime.
    /// Links that arrive via `application(_:open:)` before the routing pipeline is
    /// wired (cold start) are buffered here, then flushed in arrival order once
    /// `applicationDidFinishLaunching` activates it — so a cold-start link is never
    /// dropped.
    private let intake = LinkIntake()

    /// The menu-bar status item controller. Retained for the app's lifetime so the
    /// status item stays installed; built in `applicationDidFinishLaunching`.
    private var statusBarController: StatusBarController?

    /// The Settings window controller. Retained so the window persists across
    /// open/close; built lazily in `applicationDidFinishLaunching`.
    private var settingsWindowController: SettingsWindowController?

    /// The Sparkle-backed updater. Retained for the app's lifetime so the
    /// underlying `SPUStandardUpdaterController` keeps running its background
    /// checks; built in `applicationDidFinishLaunching`. Typed as the seam so
    /// the wiring stays decoupled from the concrete framework.
    private var updater: UpdaterControlling?

    /// The first-launch onboarding window controller. Retained so the window and
    /// its view model persist for the app's lifetime; built in
    /// `applicationDidFinishLaunching` and shown once (gated by `OnboardingStore`).
    private var onboardingWindowController: OnboardingWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppMain()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: if another copy is already running, hand off to it
        // and quit (see `yieldIfAnotherInstanceRunning`).
        if yieldIfAnotherInstanceRunning() { return }

        // Menu-bar agent by default (no Dock icon, no ⌘-Tab). The policy is flipped
        // to `.regular` only while the onboarding or Settings window is open, then
        // back to `.accessory` when the last one closes — so the app is reachable via
        // the Dock / ⌘-Tab exactly when there's a window to switch to. See
        // `syncActivationPolicy()`.
        NSApp.setActivationPolicy(.accessory)

        // Re-sync the activation policy whenever any window closes. `willClose` fires
        // while the window is still visible, so defer to the next runloop tick when
        // `isVisible` reflects the close.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.syncActivationPolicy() }
            }
        }

        // Sparkle updater: retained for the app's lifetime so its background
        // checks keep running. The "Check for Updates…" menu item drives it
        // through the seam, and the General-tab "Automatically check for updates"
        // toggle reads/writes it via `SettingsViewModel`. Built FIRST so the *same*
        // instance is injected into both the settings view model and the status-bar
        // controller — a single shared updater, never two.
        let updater = SparkleUpdater()
        self.updater = updater

        // Settings window: the view model depends only on Core (FileConfigStore),
        // the App provider seam (WorkspaceBrowserProvider), and the update seam
        // (the shared `updater` above); the window controller hosts the SwiftUI
        // views and activates the app when shown.
        //
        // Built BEFORE `makeRoutingService` so the opener closure passed into the
        // routing pipeline can deep-link through `settingsWindowController` at
        // invocation time (the closure routes through `self?.openSettings(tab:)`,
        // which reads the live property — see `openSettings(tab:)`).
        let settingsViewModel = SettingsViewModel(
            configStore: FileConfigStore(directory: Self.configDirectory()),
            browserProvider: WorkspaceBrowserProvider(),
            updater: updater
        )
        settingsWindowController = SettingsWindowController(viewModel: settingsViewModel)

        let service = Self.makeRoutingService(
            onOpenSettings: { [weak self] tab in self?.openSettings(tab: tab) }
        )
        routingService = service

        statusBarController = StatusBarController(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenAbout: { [weak self] in self?.openAbout() },
            onCheckForUpdates: { [weak self] in self?.updater?.checkForUpdates() },
            updater: updater
        )
        Self.logger.log("TrafficWand launched.")

        // Activate intake LAST, after the whole app is wired (updater, settings,
        // routing service, status bar). The flush runs synchronously on the launch
        // stack, so any buffered cold-start link routes only once the app is fully
        // constructed — a `.prompt` decision then presents the picker over a complete
        // app. Capturing the local `service` value (not `self`) avoids a retain cycle
        // (the closure is owned by `intake`, owned by `self`) and the awkward
        // double-optional of `[weak self]`.
        intake.activate { url in service.route(url: url) }

        // First-launch onboarding: build ONE `OnboardingStore` (production uses
        // `.standard`) and inject that same instance into the retained
        // `OnboardingWindowController`'s view model — single source of truth for the
        // show-once flag. The "Open Settings" deep link reuses `openSettings(tab:)`
        // (lands on `.rules`); `onFinish` closes the onboarding window via the
        // retained controller (so the last-page button actually dismisses the
        // window). `complete()` is idempotent, so the resulting `windowWillClose`
        // re-entry is a no-op. Presented LAST, after the rest of the app is wired and
        // after `intake.activate`, so it never gates or alters cold-start link routing.
        let onboardingStore = OnboardingStore()
        let onboardingViewModel = OnboardingViewModel(
            store: onboardingStore,
            onOpenSettings: { [weak self] tab in self?.openSettings(tab: tab) },
            onFinish: { [weak self] in self?.onboardingWindowController?.close() }
        )
        let onboardingController = OnboardingWindowController(viewModel: onboardingViewModel)
        onboardingWindowController = onboardingController
        if onboardingStore.hasCompletedOnboarding == false {
            onboardingController.show()
            syncActivationPolicy()
        }
    }

    /// If another copy of TrafficWand is already running, activate it, quit this
    /// process, and return `true`. Two instances sharing one `config.json` can race
    /// on load/save and quarantine the config (see `FileConfigStore`), losing the
    /// user's rules/aliases. ponytail: a tiny launch-race window where two
    /// near-simultaneous starts miss each other is acceptable for a menu-bar agent;
    /// a cross-process file lock would be the upgrade if it ever matters.
    private func yieldIfAnotherInstanceRunning() -> Bool {
        // Never yield under the test harness: the test host app shares our bundle ID,
        // so self-terminating would crash the test runner before it connects.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != NSRunningApplication.current.processIdentifier }
        guard Self.shouldYieldToExistingInstance(otherInstanceCount: others.count) else {
            return false
        }
        Self.logger.log("Another instance is running; activating it and quitting.")
        others.first?.activate()
        NSApp.terminate(nil)
        return true
    }

    /// Whether to yield to an already-running instance (and quit). `nonisolated` and
    /// pure so the single-instance decision is unit-tested off the main actor; the
    /// `NSRunningApplication` query that produces the count is the thin adapter above.
    nonisolated static func shouldYieldToExistingInstance(otherInstanceCount: Int) -> Bool {
        otherInstanceCount > 0
    }

    /// Shows a Dock icon + ⌘-Tab presence (`.regular`) while the onboarding or
    /// Settings window is visible, and reverts to the menu-bar-agent policy
    /// (`.accessory`) when neither is. Called after showing either window and from
    /// the window-close observer.
    @MainActor
    private func syncActivationPolicy() {
        let anyWindowVisible = (onboardingWindowController?.isWindowVisible ?? false)
            || (settingsWindowController?.isWindowVisible ?? false)
        NSApp.setActivationPolicy(anyWindowVisible ? .regular : .accessory)
    }

    /// URL intake: hand each link to `LinkIntake`, which routes it immediately if the
    /// pipeline is ready or buffers it until `applicationDidFinishLaunching` activates
    /// intake (cold-start safety — links arriving before the pipeline is wired are
    /// flushed in arrival order, never dropped).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Self.logger.log("Routing URL: \(url.absoluteString, privacy: .public)")
            intake.accept(url)
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
        syncActivationPolicy()
    }

    /// Shows the Settings window deep-linked to the About tab (status-bar
    /// "About TrafficWand…" item hook).
    @MainActor
    private func openAbout() {
        Self.logger.log("Opening About (Settings → About tab).")
        settingsWindowController?.show(initialTab: .about)
        syncActivationPolicy()
    }

    /// Deep-link variant of `openSettings()`: always lands on `tab`.
    @MainActor
    private func openSettings(tab: SettingsTab) {
        Self.logger.log("Opening Settings window on tab: \(String(describing: tab), privacy: .public).")
        settingsWindowController?.show(initialTab: tab)
        syncActivationPolicy()
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
    ///
    /// - Parameter onOpenSettings: closure invoked by the picker (gear icon /
    ///   `⌘,` shortcut) to deep-link Settings to a specific tab. Threading it in
    ///   as a parameter keeps this factory `static`.
    @MainActor
    private static func makeRoutingService(
        onOpenSettings: @escaping @MainActor (SettingsTab) -> Void
    ) -> RoutingService {
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
                iconProvider: WorkspaceBrowserIconProvider(),
                onOpenSettings: onOpenSettings
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
