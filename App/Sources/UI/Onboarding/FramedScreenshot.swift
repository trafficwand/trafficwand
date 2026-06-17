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

    /// Aspect ratio of the card. Matches `MenuBarIllustration.renderSize`
    /// (480×300 = 1.6) so the rasterized illustration fills the frame exactly;
    /// real screenshots are fit (letterboxed) inside the same consistent shape.
    private static let aspect: CGFloat = 1.6
    private static let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            // Single card background, shared by both the image and placeholder
            // cases so every page reads as the same shape.
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color(nsColor: .windowBackgroundColor))

            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(1)
            } else {
                placeholderContent
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .accessibilityElement()
        .accessibilityLabel(caption ?? "Screenshot")
    }

    /// Drawn placeholder content shown until a real screenshot asset is added.
    /// Sits on the shared card background (no second rounded rect).
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
