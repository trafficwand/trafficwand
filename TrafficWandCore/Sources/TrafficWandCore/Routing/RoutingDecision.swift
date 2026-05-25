import Foundation

/// The outcome of routing a link, produced by `Router.decide`.
///
/// Either a concrete destination to open (`.open`) or a request to present the
/// interactive picker (`.prompt`). The App layer interprets this without any
/// further decision logic — all the policy lives in `Router`.
///
/// `Equatable` so tests can assert decisions directly; not persisted.
public enum RoutingDecision: Equatable, Sendable {
    /// Open the link in this specific browser/profile target.
    case open(BrowserTarget)
    /// Present the picker for this URL over the given available browsers.
    case prompt(url: URL, browsers: [Browser])
}
