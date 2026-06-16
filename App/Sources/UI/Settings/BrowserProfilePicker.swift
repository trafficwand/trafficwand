import SwiftUI
import TrafficWandCore

/// A reusable browser + profile picker pair binding a `BrowserTarget`.
///
/// Renders a "Browser" dropdown over `browsers` and — only when the selected
/// browser exposes profiles — a "Profile" dropdown (with a leading "Default"
/// entry meaning "no profile"). Switching browsers resets the profile whenever
/// the newly-chosen browser can't honor it, so the bound target never carries a
/// profile the browser doesn't have. This is the single home of that reset rule,
/// shared by the rule editor, the alias editor, and the fallback editor.
///
/// The control writes through a `Binding<BrowserTarget>`, so each call site keeps
/// its own commit model: the editors bind local working-copy `@State`, while the
/// fallback editor binds a computed binding that persists immediately.
struct BrowserProfilePicker: View {
    /// The browsers available as targets (with discovered profiles).
    let browsers: [Browser]

    /// The concrete target being edited (bundle + optional profile).
    @Binding var target: BrowserTarget

    /// The browser currently selected (if it is among the available browsers).
    private var selectedBrowser: Browser? {
        browsers.first { $0.bundleID == target.bundleID }
    }

    /// Selecting a browser resets the profile unless the new browser still offers
    /// it, so we never persist a profile the new browser can't honor.
    private var bundleBinding: Binding<String> {
        Binding(
            get: { target.bundleID },
            set: { bundleID in
                let newBrowser = browsers.first { $0.bundleID == bundleID }
                let keepProfile = newBrowser?.profiles.contains { $0.id == target.profileID } ?? false
                target = BrowserTarget(
                    bundleID: bundleID,
                    profileID: keepProfile ? target.profileID : nil
                )
            }
        )
    }

    private var profileBinding: Binding<String?> {
        Binding(
            get: { target.profileID },
            set: { profileID in
                target = BrowserTarget(bundleID: target.bundleID, profileID: profileID)
            }
        )
    }

    var body: some View {
        Picker("Browser", selection: bundleBinding) {
            ForEach(browsers) { browser in
                Text(browser.name).tag(browser.bundleID)
            }
        }

        if let selectedBrowser, !selectedBrowser.profiles.isEmpty {
            Picker("Profile", selection: profileBinding) {
                Text("Default").tag(String?.none)
                ForEach(selectedBrowser.profiles) { profile in
                    Text(profile.name).tag(String?.some(profile.id))
                }
            }
        }
    }
}
