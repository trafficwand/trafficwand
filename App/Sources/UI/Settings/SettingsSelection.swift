import Foundation

/// Observable holder for the Settings window's currently selected tab.
///
/// Owned by `SettingsWindowController` and passed to `SettingsRootView` as a
/// `@Bindable`, so the selection lives outside SwiftUI `@State`. This matters
/// because `@State` is preserved across `rootView` reassignments — if the
/// selection were `@State` inside `SettingsRootView`, a deep-link request
/// (`show(initialTab: .about)`) after the window had already been shown once
/// would silently fail: SwiftUI would treat the new root view as an update and
/// keep the previous `@State` value. Moving the selection into an `@Observable`
/// the controller owns means deep-link writes are observed directly by the
/// `TabView` selection binding, *and* are externally observable from tests
/// (no `@State` introspection needed).
@MainActor
@Observable
final class SettingsSelection {
    var tab: SettingsTab

    init(tab: SettingsTab = .general) {
        self.tab = tab
    }
}
