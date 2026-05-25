import SwiftUI
import TrafficWandCore

/// The Settings window container: a `TabView` hosting the General and Rules tabs.
///
/// It owns the `SettingsViewModel` and triggers `load()` on appear so the window
/// always reflects the persisted config and the current installed-browser list.
/// `DefaultBrowserManager` is passed through to the General tab for its
/// status/Set-as-Default affordance.
struct SettingsRootView: View {
    @Bindable var viewModel: SettingsViewModel
    let defaultBrowserManager: DefaultBrowserManager

    var body: some View {
        TabView {
            GeneralSettingsView(
                viewModel: viewModel,
                defaultBrowserManager: defaultBrowserManager
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            RulesListView(viewModel: viewModel)
                .tabItem {
                    Label("Rules", systemImage: "arrow.triangle.branch")
                }
        }
        .frame(width: 560, height: 480)
        .onAppear { viewModel.load() }
    }
}
