import AppKit
import SwiftUI

/// A code-drawn depiction of the macOS menu bar with the TrafficWand icon in it,
/// used by the first onboarding page to point the user at the menu bar.
///
/// Per the onboarding design, every page renders a flat, non-interactive image —
/// so this SwiftUI illustration is **rasterized to an `NSImage` via
/// `ImageRenderer`** (`rendered()`) and shown through `FramedScreenshot`, giving
/// it the same screenshot treatment as the real screenshots on the other pages.
struct MenuBarIllustration: View {
    /// Fixed render size; baked at 2x for a crisp raster (see `rendered()`).
    static let renderSize = CGSize(width: 480, height: 300)

    var body: some View {
        ZStack {
            // Desktop backdrop.
            LinearGradient(
                colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                menuBar
                Spacer()
            }
        }
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)
    }

    /// The fake menu bar strip across the top, with the app icon highlighted.
    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo")
                .font(.system(size: 13, weight: .medium))
            Text("Finder")
                .font(.system(size: 13, weight: .semibold))
            Text("File")
                .font(.system(size: 13))
            Text("Edit")
                .font(.system(size: 13))

            Spacer()

            // The highlighted TrafficWand icon — the thing we're pointing at.
            appIcon
                .frame(width: 18, height: 18)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                )

            Image(systemName: "wifi")
                .font(.system(size: 13))
            Image(systemName: "battery.100")
                .font(.system(size: 13))
            Text("9:41")
                .font(.system(size: 13))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        // A solid, translucent fill rather than `.regularMaterial`: materials don't
        // reliably rasterize through `ImageRenderer` (they can bake out transparent
        // or flat), so use a concrete menu-bar-like color that always renders.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
    }

    /// The TrafficWand **menu-bar** glyph — the same SF Symbol template the real
    /// status item uses (`StatusBarController.statusIconSymbolName`), not the big
    /// application icon, so the illustration matches what the user actually sees in
    /// their menu bar.
    private var appIcon: some View {
        Image(systemName: StatusBarController.statusIconSymbolName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
    }

    /// Rasterizes the illustration to a flat `NSImage` at 2x scale.
    ///
    /// `ImageRenderer` is `@MainActor`, so this must be called on the main actor.
    /// Returns `nil` only if the renderer fails to produce an image.
    @MainActor
    static func rendered() -> NSImage? {
        let renderer = ImageRenderer(content: MenuBarIllustration())
        renderer.scale = 2
        return renderer.nsImage
    }
}
