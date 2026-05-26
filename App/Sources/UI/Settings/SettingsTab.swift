import Foundation

/// Deep-link key for the Settings window's `TabView` selection.
///
/// Used by `SettingsRootView` as the `TabView` selection binding and by
/// `SettingsWindowController.show(initialTab:)` when callers want to open
/// Settings on a specific tab (e.g. the "About TrafficWand…" menu item).
enum SettingsTab: String, CaseIterable {
    case general
    case rules
    case about
}
