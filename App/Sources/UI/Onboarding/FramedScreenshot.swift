import AppKit
import SwiftUI

/// A flat, non-interactive framed visual for an onboarding page.
///
/// It shows a pre-rendered `NSImage` — a code-drawn illustration baked via
/// `ImageRenderer` (see `OnboardingIllustration`) — inside a card (backplate,
/// border, shadow). It carries **no controls**: every onboarding visual reads as a
/// screenshot, never a live affordance. Live actions live in `OnboardingRootView`'s
/// footer.
///
/// If the image is `nil` (the renderer failed), it falls back to a drawn placeholder
/// so the flow still renders.
struct FramedScreenshot: View {
    let image: NSImage?
    let caption: String?

    init(image: NSImage?, caption: String? = nil) {
        self.image = image
        self.caption = caption
    }

    /// Aspect ratio of the card. Matches the illustrations' `renderSize`
    /// (480×300 = 1.6) so a baked illustration fills the frame exactly.
    private static let aspect: CGFloat = 1.6
    private static let cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(1)
                    .modifier(CardFrame(cornerRadius: Self.cornerRadius))
            } else {
                placeholderContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(CardFrame(cornerRadius: Self.cornerRadius))
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(caption ?? "Illustration")
    }

    /// Drawn fallback shown only if an illustration fails to rasterize.
    private var placeholderContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(caption ?? "Illustration")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

/// The card chrome (backplate + border + shadow) wrapping each baked illustration.
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
