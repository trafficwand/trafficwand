import AppKit
import SwiftUI

/// A code-drawn onboarding illustration that can be rasterized to a flat `NSImage`.
///
/// Every onboarding page shows a non-interactive *image* (never a live control), so
/// each illustration is a SwiftUI view baked through `ImageRenderer`. Conformers draw
/// at `renderSize`; the default `rendered(colorScheme:)` bakes them in the requested
/// theme so the visuals follow the system appearance.
@MainActor
protocol OnboardingIllustration: View {
    init()
    static var renderSize: CGSize { get }
}

extension OnboardingIllustration {
    /// Rasterizes the illustration at 2x in the given color scheme.
    @MainActor
    static func rendered(colorScheme: ColorScheme = .light) -> NSImage? {
        let renderer = ImageRenderer(
            content: Self().environment(\.colorScheme, colorScheme)
        )
        renderer.scale = 2
        return renderer.nsImage
    }
}

// MARK: - Shared chrome

/// The desktop backdrop the illustrations float their UI on, so each page reads as a
/// screenshot taken on a real Mac. Shared by all illustrations for a consistent look.
struct DesktopBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// A simplified macOS window: traffic-light dots, an optional centered title, and the
/// content below. Theme-aware. Used to mock TrafficWand's Settings windows.
struct MockWindow<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private var titleBar: some View {
        ZStack {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                trafficLight(Color(red: 1.0, green: 0.37, blue: 0.34))
                trafficLight(Color(red: 1.0, green: 0.74, blue: 0.18))
                trafficLight(Color(red: 0.16, green: 0.79, blue: 0.25))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.93))
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 11, height: 11)
    }
}

/// A small rounded chip showing a browser (and optional profile) the way the rule and
/// alias editors do — a globe glyph plus a label.
private struct BrowserChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.tint)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Page illustrations

/// "Make TrafficWand your default browser" — a Settings General-tab mock showing the
/// not-yet-default state plus a Set-as-Default button (mirrors `GeneralSettingsView`).
struct DefaultBrowserIllustration: OnboardingIllustration {
    static let renderSize = CGSize(width: 480, height: 300)

    var body: some View {
        ZStack {
            DesktopBackdrop()
            MockWindow(title: "General") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default Browser")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("TrafficWand isn’t your default browser")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text("Set as Default")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.9))
                            )
                            .foregroundStyle(.white)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .padding(20)
            }
            .padding(26)
        }
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)
    }
}

/// "Route links automatically with rules" — a Rules-tab mock: a few pattern → browser
/// rows so the concept is concrete.
struct RulesIllustration: OnboardingIllustration {
    static let renderSize = CGSize(width: 480, height: 300)

    private static let rules: [(pattern: String, target: String)] = [
        ("*.github.com", "Chrome · Work"),
        ("figma.com", "Arc"),
        ("*.slack.com", "Safari")
    ]

    var body: some View {
        ZStack {
            DesktopBackdrop()
            MockWindow(title: "Rules") {
                VStack(spacing: 0) {
                    ForEach(Array(Self.rules.enumerated()), id: \.offset) { index, rule in
                        HStack(spacing: 8) {
                            Text(rule.pattern)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            BrowserChip(label: rule.target)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        if index < Self.rules.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(26)
        }
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)
    }
}

/// "Reuse a browser + profile with aliases" — an Aliases-tab mock: named aliases each
/// bound to a browser/profile.
struct AliasesIllustration: OnboardingIllustration {
    static let renderSize = CGSize(width: 480, height: 300)

    private static let aliases: [(name: String, target: String)] = [
        ("Work", "Chrome · Work"),
        ("Personal", "Safari"),
        ("Design", "Arc")
    ]

    var body: some View {
        ZStack {
            DesktopBackdrop()
            MockWindow(title: "Aliases") {
                VStack(spacing: 0) {
                    ForEach(Array(Self.aliases.enumerated()), id: \.offset) { index, alias in
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tint)
                            Text(alias.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            BrowserChip(label: alias.target)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        if index < Self.aliases.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(26)
        }
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)
    }
}
