import AppKit
import SwiftUI

/// A flat, non-interactive framed visual for an onboarding page.
///
/// It renders either a named image asset (a real screenshot the user drops into
/// `Onboarding.xcassets` later) or a pre-rendered `NSImage` (the rasterized
/// menu-bar illustration). The image is framed with a border, shadow, and an
/// optional caption, and carries **no controls** — every onboarding visual must
/// read as a screenshot, never a live affordance. Live actions live in the
/// footer of `OnboardingRootView`.
///
/// When a named asset has no PNG yet (`NSImage(named:)` returns `nil`), the view
/// falls back to a drawn placeholder (a gray rounded rect with caption text), so
/// the feature builds and runs before the screenshots are captured.
struct FramedScreenshot: View {
    /// What the view should display.
    enum Source {
        /// A named asset to resolve from the bundle's catalogs.
        case asset(String)
        /// A pre-rendered image (e.g. the menu-bar illustration baked via
        /// `ImageRenderer`); `nil` falls back to the placeholder.
        case rendered(NSImage?)
    }

    let source: Source
    let caption: String?

    init(source: Source, caption: String? = nil) {
        self.source = source
        self.caption = caption
    }

    /// Pure resolution decision for a named asset, extracted so the
    /// placeholder-vs-asset branch is unit-testable without rendering SwiftUI.
    /// Returns `nil` when the catalog has no matching image (placeholder branch).
    static func image(forAsset name: String) -> NSImage? {
        NSImage(named: name)
    }

    /// Resolves the source to a concrete image, or `nil` to draw the placeholder.
    private var resolvedImage: NSImage? {
        switch source {
        case .asset(let name):
            return Self.image(forAsset: name)
        case .rendered(let image):
            return image
        }
    }

    /// Aspect ratio of the drawn card (illustration + placeholder). Matches
    /// `MenuBarIllustration.renderSize` (480×300 = 1.6). Real screenshots are *not*
    /// boxed to this — they keep their natural aspect.
    private static let aspect: CGFloat = 1.6
    private static let cornerRadius: CGFloat = 12

    /// How the resolved source should be presented.
    private enum DisplayMode {
        /// A real screenshot asset, carried by **name** so it renders as a SwiftUI
        /// `Image(name)` — which resolves light/dark catalog variants from the
        /// environment color scheme. Shown plain (no backplate/shadow).
        case screenshot(String)
        /// The drawn menu-bar illustration — gets the card backplate + shadow so it
        /// reads as a framed screenshot.
        case illustration(NSImage)
        /// No image yet — drawn placeholder on the card.
        case placeholder
    }

    private var displayMode: DisplayMode {
        switch source {
        case .asset(let name):
            // Existence check via NSImage(named:); render via Image(name) below so
            // light/dark variants follow the system theme.
            if Self.image(forAsset: name) != nil { return .screenshot(name) }
            return .placeholder
        case .rendered(let image):
            if let image { return .illustration(image) }
            return .placeholder
        }
    }

    var body: some View {
        Group {
            switch displayMode {
            case .screenshot(let name):
                // Plain: no backplate, no shadow — the screenshot is its own frame.
                // SwiftUI Image(name) auto-resolves the catalog's light/dark variant.
                Image(name)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))

            case .illustration(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(1)
                    .modifier(CardFrame(cornerRadius: Self.cornerRadius))
                    .aspectRatio(Self.aspect, contentMode: .fit)

            case .placeholder:
                placeholderContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(CardFrame(cornerRadius: Self.cornerRadius))
                    .aspectRatio(Self.aspect, contentMode: .fit)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(caption ?? "Screenshot")
    }

    /// Drawn placeholder content shown until a real screenshot asset is added.
    private var placeholderContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(caption ?? "Screenshot goes here")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

/// The card chrome (backplate + border + shadow) used by the drawn illustration and
/// the placeholder — but *not* by real screenshots, which carry their own framing.
private struct CardFrame: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}
