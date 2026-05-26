import AppKit
import Foundation
import TrafficWandCore

/// Supplies a browser's real macOS app icon to the picker UI.
///
/// A narrow App-side seam over `NSWorkspace` so the picker view can render a
/// concrete browser icon at runtime while still being previewable/testable with a
/// stub provider (`#Preview` doesn't depend on which browsers happen to be
/// installed). Keeping the `NSWorkspace` call behind this protocol matches the
/// other App seams (`InstalledBrowsersProviding`, `LastUsedRecording`).
protocol BrowserIconProviding {
    /// Returns the display icon for `browser` (its bundle's app icon).
    func icon(for browser: Browser) -> NSImage
}

/// Concrete `BrowserIconProviding` backed by `NSWorkspace`.
///
/// Loads the icon for the browser's app bundle on disk via
/// `NSWorkspace.shared.icon(forFile:)` — which always returns an image (a generic
/// document/app icon if the path is missing), so no optionality is needed.
struct WorkspaceBrowserIconProvider: BrowserIconProviding {
    /// Point size icons are rendered at. 32pt suits a single list row at standard
    /// and Retina scales: large enough to read the browser's mark, small enough to
    /// keep rows compact.
    private static let iconSize = NSSize(width: 32, height: 32)

    func icon(for browser: Browser) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: browser.appURL.path)
        image.size = Self.iconSize
        return image
    }
}
