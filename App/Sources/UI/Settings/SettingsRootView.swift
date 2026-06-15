import SwiftUI
import TrafficWandCore

/// The Settings window container: a `TabView` hosting the General, Rules, and
/// About tabs.
///
/// It owns the `SettingsViewModel` and triggers `load()` on appear so the window
/// always reflects the persisted config and the current installed-browser list.
/// `DefaultBrowserManager` is passed through to the General tab for its
/// status/Set-as-Default affordance.
///
/// The tab selection is held in a controller-owned `SettingsSelection`
/// observable rather than `@State`, so deep-link writes from
/// `SettingsWindowController.show(initialTab:)` are picked up even when the
/// window has already been shown (see `SettingsSelection`'s doc comment).
struct SettingsRootView: View {
    @Bindable var viewModel: SettingsViewModel
    let defaultBrowserManager: DefaultBrowserManager
    @Bindable var selection: SettingsSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView(
                viewModel: viewModel,
                defaultBrowserManager: defaultBrowserManager
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(SettingsTab.general)

            RulesListView(viewModel: viewModel)
                .tabItem {
                    Label("Rules", systemImage: "arrow.triangle.branch")
                }
                .tag(SettingsTab.rules)

            AliasesListView(viewModel: viewModel)
                .tabItem {
                    Label("Aliases", systemImage: "link")
                }
                .tag(SettingsTab.aliases)

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 480)
        .onAppear { viewModel.load() }
    }
}
