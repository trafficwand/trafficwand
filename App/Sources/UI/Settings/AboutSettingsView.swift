import AppKit
import SwiftUI

/// The About tab: app icon, name, version + build, optional commit hash,
/// copyright notice, license link, and a Sponsor button.
///
/// `BuildInfo` is injected (defaulting to `.current()`) and the URL-opening
/// closure is injected too (defaulting to `NSWorkspace.shared.open`) so the
/// view stays previewable and test-friendly without reaching for the system.
///
/// The license and sponsor links go through `NSWorkspace.shared.open` like any
/// other URL — on a dev box where TrafficWand is the default browser, this
/// honestly loops through the app's own routing (and surfaces the configured
/// fallback for `github.com` if no rule matches).
///
/// Visual rendering is covered by manual verification (Task 8 in the About-tab
/// plan), since this repo has no snapshot-test framework.
struct AboutSettingsView: View {
    /// Two URLs and a copyright string don't justify a separate module —
    /// keep them local to the only view that renders them. Exposed as
    /// `internal` so a smoke test can verify the force-unwrapped URLs
    /// construct successfully (a typo would otherwise crash on first render).
    enum Links {
        static let sponsor = URL(string: "https://github.com/sponsors/tomakado")!
        static let license = URL(string: "https://github.com/trafficwand/trafficwand/blob/main/LICENSE")!
        static let copyright = "© 2026 Ildar Karymov"
    }

    let info: BuildInfo
    let openURL: (URL) -> Void

    init(
        info: BuildInfo = .current(),
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.info = info
        self.openURL = openURL
    }

    var body: some View {
        VStack(spacing: 16) {
            appIcon

            Text(info.name)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("Version \(info.version) (build \(info.build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let commit = info.commit {
                    Text("commit \(commit)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            VStack(spacing: 6) {
                Text(Links.copyright)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    openURL(Links.license)
                } label: {
                    Text("MIT License")
                        .font(.callout)
                }
                .buttonStyle(.link)
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text(
                    "TrafficWand is built in my spare time. It's open-source and free to use — "
                    + "if it's useful to you, sponsoring helps fund continued development."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)

                Button {
                    openURL(Links.sponsor)
                } label: {
                    Label("Sponsor on GitHub", systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    /// The app's real icon if available, else a generic placeholder so the
    /// view stays well-formed in previews / under unusual bundle states.
    private var appIcon: some View {
        Group {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
    }
}
