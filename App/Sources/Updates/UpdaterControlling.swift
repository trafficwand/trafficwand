import Foundation

/// The seam through which the menu-bar agent and Settings drive in-app updates.
///
/// Sparkle is an App-layer concern (it touches AppKit and the system), so the
/// update logic the UI cares about — "can I check?", "check now", "auto-check
/// on/off" — is expressed as a narrow `@MainActor` protocol. `StatusBarController`
/// (the "Check for Updates…" menu item) and `SettingsViewModel` (the
/// auto-update toggle) talk to this seam, never to Sparkle directly. The concrete
/// `SparkleUpdater` wraps `SPUStandardUpdaterController`; tests inject a
/// `MockUpdater` that records calls and round-trips the property.
///
/// Mirrors the existing `PickerPresenting` / `InstalledBrowsersProviding` seam
/// convention: a pure protocol the App defines over a concrete adapter so the
/// decision/plumbing logic stays testable without the real framework.
@MainActor
protocol UpdaterControlling: AnyObject {
    /// Whether Sparkle automatically checks for updates in the background.
    ///
    /// Bound to the "Automatically check for updates" toggle in General settings;
    /// forwards to the underlying updater's preference.
    var automaticallyChecksForUpdates: Bool { get set }

    /// Whether a manual update check can currently be initiated (e.g. not already
    /// checking). Used to validate the "Check for Updates…" menu item.
    var canCheckForUpdates: Bool { get }

    /// Initiates a user-driven update check, presenting Sparkle's standard UI.
    func checkForUpdates()
}
