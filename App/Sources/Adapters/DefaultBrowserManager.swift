import AppKit
import Foundation

/// Manages TrafficWand's status as the system default `http`/`https` handler.
///
/// The interesting, untrustworthy part — *which* app currently handles web links —
/// is a thin `NSWorkspace` query. The **decision** ("is that app us?") is a pure,
/// unit-tested helper. Becoming the default (`setAsDefault()`) triggers a macOS
/// system prompt that cannot be automated; it is covered by Post-Completion manual
/// verification.
public struct DefaultBrowserManager {
    /// The URL schemes a web browser must own to be the default browser.
    private static let handledSchemes = ["http", "https"]

    /// A sample `http` URL used only to query the current default handler.
    private static let sampleURL = URL(string: "http://example.com")!

    private let ourBundleID: String

    /// - Parameter ourBundleID: TrafficWand's own bundle identifier (defaults to
    ///   the running bundle's identifier).
    public init(ourBundleID: String = Bundle.main.bundleIdentifier ?? "") {
        self.ourBundleID = ourBundleID
    }

    /// Whether TrafficWand is currently the default browser.
    ///
    /// Combines the live query (untested adapter) with the pure comparison helper.
    public var isDefault: Bool {
        Self.isCurrentDefault(
            currentDefaultBundleID: currentDefaultBrowserBundleID(),
            ourBundleID: ourBundleID
        )
    }

    /// The **pure** decision: is `currentDefaultBundleID` our bundle?
    ///
    /// Bundle IDs are compared case-insensitively (Launch Services is not
    /// case-sensitive about them). A `nil` or empty current default is never us.
    ///
    /// - Parameters:
    ///   - currentDefaultBundleID: Bundle ID of the app currently handling web
    ///     links, or `nil` if none/unknown.
    ///   - ourBundleID: TrafficWand's own bundle identifier.
    /// - Returns: `true` iff the two identifiers match case-insensitively.
    public static func isCurrentDefault(currentDefaultBundleID: String?, ourBundleID: String) -> Bool {
        guard let current = currentDefaultBundleID, !current.isEmpty else { return false }
        return current.caseInsensitiveCompare(ourBundleID) == .orderedSame
    }

    /// Requests that TrafficWand become the default handler for `http` and `https`.
    ///
    /// On macOS 12+ this presents a system confirmation prompt — the live call and
    /// its prompt are not automatable and are covered by Post-Completion manual
    /// verification.
    ///
    /// - Parameter completion: Optional callback invoked **once**, after both
    ///   scheme requests have resolved, with the first error reported (if any).
    public func setAsDefault(completion: ((Error?) -> Void)? = nil) {
        guard let appURL = Bundle.main.bundleURL as URL? else {
            completion?(nil)
            return
        }

        // Coalesce the two per-scheme callbacks into a single completion so callers
        // refresh once, not twice. `NSWorkspace` invokes these on a background
        // queue, so guard the shared counters/first-error with a small lock.
        let group = SchemeCompletion(remaining: Self.handledSchemes.count, completion: completion)
        for scheme in Self.handledSchemes {
            NSWorkspace.shared.setDefaultApplication(
                at: appURL,
                toOpenURLsWithScheme: scheme
            ) { error in
                group.recordResult(error)
            }
        }
    }

    /// Aggregates the per-scheme `setDefaultApplication` callbacks into one. Fires
    /// the caller's completion exactly once, after the last scheme resolves, with
    /// the first error seen (if any). Thread-safe (callbacks arrive off-main).
    private final class SchemeCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        private var firstError: Error?
        private let completion: ((Error?) -> Void)?

        init(remaining: Int, completion: ((Error?) -> Void)?) {
            self.remaining = remaining
            self.completion = completion
        }

        func recordResult(_ error: Error?) {
            lock.lock()
            if firstError == nil { firstError = error }
            remaining -= 1
            let done = remaining <= 0
            let reportedError = firstError
            lock.unlock()

            if done {
                completion?(reportedError)
            }
        }
    }

    /// The live `NSWorkspace` query for the current default web-link handler. The
    /// only untested line; everything downstream routes through the pure helper.
    private func currentDefaultBrowserBundleID() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: Self.sampleURL) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }
}
