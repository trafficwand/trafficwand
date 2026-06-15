import AppKit
import SwiftUI
import TrafficWandCore

/// The general tab: fallback policy selection plus default-browser status and a
/// "Set as Default" button.
///
/// The fallback policy is one of three modes. `.defaultBrowser` additionally needs
/// a browser (and optional profile) target, so selecting that mode reveals a
/// browser + profile picker. Every change is committed to `SettingsViewModel`,
/// which persists immediately. The default-browser status and the Set-as-Default
/// action go through the injected `DefaultBrowserManager` (the only AppKit-touching
/// dependency here; injected so the view stays previewable/testable-adjacent).
struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    /// Manages default-browser status + the Set-as-Default request.
    let defaultBrowserManager: DefaultBrowserManager

    /// The selected fallback mode, mapped to/from `FallbackPolicy` by the view model.
    private enum FallbackMode: String, CaseIterable, Identifiable {
        case picker
        case defaultBrowser
        case lastUsed
        var id: String { rawValue }

        var title: String {
            switch self {
            case .picker: return "Show picker"
            case .defaultBrowser: return "Open in a specific browser"
            case .lastUsed: return "Use last-used browser"
            }
        }
    }

    /// Re-read on appear/refresh; the live default status can change outside the app.
    @State private var isDefaultBrowser = false

    var body: some View {
        Form {
            Section("Default Browser") {
                HStack {
                    Image(systemName: isDefaultBrowser ? "checkmark.seal.fill" : "exclamationmark.triangle")
                        .foregroundStyle(isDefaultBrowser ? .green : .orange)
                    Text(isDefaultBrowser
                        ? "TrafficWand is your default browser."
                        : "TrafficWand is not your default browser.")
                    Spacer()
                    if !isDefaultBrowser {
                        Button("Set as Default") { setAsDefault() }
                    }
                }
            }

            Section("When no rule matches") {
                Picker("Fallback", selection: fallbackModeBinding) {
                    ForEach(FallbackMode.allCases) { mode in
                        // The "specific browser" mode needs a real destination; disable
                        // it only when there is neither a browser nor an alias to target,
                        // so we never persist an unusable empty-bundleID target.
                        Text(mode.title)
                            .tag(mode)
                            .disabled(mode == .defaultBrowser && !hasAnyDestination)
                    }
                }
                .pickerStyle(.radioGroup)

                if !hasAnyDestination {
                    Text("Install a browser or create an alias to route to a specific one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if currentMode == .defaultBrowser {
                    fallbackDestinationEditor
                }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $viewModel.automaticUpdatesEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDefaultStatus() }
        // The default-browser status can change outside the app (e.g. via System
        // Settings). Re-read whenever the app becomes active so the row never goes
        // stale while the Settings window stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDefaultStatus()
        }
    }

    /// Re-reads whether TrafficWand is currently the default browser.
    private func refreshDefaultStatus() {
        isDefaultBrowser = defaultBrowserManager.isDefault
    }

    // MARK: - Fallback mode binding

    /// The mode derived from the current `FallbackPolicy`.
    private var currentMode: FallbackMode {
        switch viewModel.fallback {
        case .picker: return .picker
        case .defaultBrowser: return .defaultBrowser
        case .lastUsed: return .lastUsed
        }
    }

    /// Whether there is any destination (browser or alias) to route to. Entering
    /// `.defaultBrowser` mode is refused unless this is true.
    private var hasAnyDestination: Bool {
        !viewModel.browsers.isEmpty || !viewModel.aliases.isEmpty
    }

    /// Binding that maps a `FallbackMode` selection back to a `FallbackPolicy`,
    /// preserving any already-chosen destination when switching into `.defaultBrowser`.
    private var fallbackModeBinding: Binding<FallbackMode> {
        Binding(
            get: { currentMode },
            set: { mode in
                switch mode {
                case .picker:
                    viewModel.setFallback(.picker)
                case .lastUsed:
                    viewModel.setFallback(.lastUsed)
                case .defaultBrowser:
                    // Refuse to enter .defaultBrowser with no destination at all: it
                    // would persist an unusable empty-bundleID target. The option is
                    // also visually disabled above; this is the load-bearing guard.
                    guard hasAnyDestination else { return }
                    viewModel.setFallback(.defaultBrowser(currentDefaultDestination))
                }
            }
        )
    }

    /// The destination used when entering `.defaultBrowser` mode: the existing one if
    /// the policy already carries it, else the first browser, else the first alias.
    private var currentDefaultDestination: RoutingDestination {
        if case .defaultBrowser(let destination) = viewModel.fallback {
            return destination
        }
        if let bundleID = viewModel.browsers.first?.bundleID {
            return .browser(BrowserTarget(bundleID: bundleID, profileID: nil))
        }
        if let alias = viewModel.aliases.first {
            return .alias(alias.id)
        }
        return .browser(BrowserTarget(bundleID: "", profileID: nil))
    }

    // MARK: - Fallback destination editor (browser-or-alias)

    /// Browser-or-alias editor for the `.defaultBrowser` destination, persisting any
    /// change straight through `setFallback`. Reuses the same `DestinationEditor`
    /// control as the rule editor so the segmented control, profile-reset, and
    /// alias-empty disabling live in one place.
    @ViewBuilder
    private var fallbackDestinationEditor: some View {
        DestinationEditor(
            browsers: viewModel.browsers,
            aliases: viewModel.aliases,
            destination: fallbackDestinationBinding
        )
    }

    /// Binding over the `.defaultBrowser` destination: reads the current one and
    /// persists edits immediately via `setFallback`.
    private var fallbackDestinationBinding: Binding<RoutingDestination> {
        Binding(
            get: { currentDefaultDestination },
            set: { viewModel.setFallback(.defaultBrowser($0)) }
        )
    }

    // MARK: - Set as default

    private func setAsDefault() {
        defaultBrowserManager.setAsDefault { _ in
            Task { @MainActor in
                isDefaultBrowser = defaultBrowserManager.isDefault
            }
        }
    }
}
