import Foundation

/// Builds the persistent `Rule` that "remembering" a routing choice for a URL
/// should create.
///
/// The pattern is scoped to the URL's host:
/// - For a normal host, the rule uses `*<registrableDomain>` (a leading-star
///   glob), which — per `GlobPattern` semantics — matches **both** the apex
///   (`x.com`) and every subdomain (`www.x.com`, `news.x.com`). The registrable
///   domain is computed by `RegistrableDomain.of(host:)`.
/// - For a host with no registrable domain (an IP literal, a single-label host
///   such as `localhost`), the rule uses the **exact host** as its pattern, with
///   no leading star, so it matches only that host. (For IPv6 this matches only
///   the exact textual form the URL carried; alternate textual representations of
///   the same address are not normalized — a documented, accepted limitation.)
/// - For a hostless URL (`mailto:`, `file:///…`), there is nothing to remember
///   and the result is `nil`.
///
/// ## Leading-star idiom: known breadth
///
/// The generated `*<domain>` pattern follows the project's established leading-star
/// glob idiom (documented in `GlobPattern`): `*` matches *any* characters, so
/// `*x.com` also matches any host that merely **ends with** `x.com` — e.g.
/// `notx.com` or `phishing-x.com`, not just `x.com` and its subdomains. This is an
/// accepted, documented limitation of the single-glob "domain + subdomains" idiom
/// (a single glob cannot express "apex + subdomains but nothing else"); it is not a
/// defect of this builder. The exact-host case (IP / single-label) has no such
/// breadth.
public enum RememberRule {
    /// Returns the `Rule` to persist for remembering `destination` for `url`, or
    /// `nil` when `url` has no host to scope a rule to.
    ///
    /// The built rule carries whatever `RoutingDestination` it is given: picking a
    /// concrete browser in the picker yields a `.browser(target)` rule, while an
    /// explicit alias selection yields an `.alias(id)` rule — the reusable,
    /// late-binding binding, so re-pointing the alias later also re-routes this
    /// remembered site.
    ///
    /// - Parameters:
    ///   - url: The link whose destination should be remembered.
    ///   - destination: The routing destination (browser or alias) to route
    ///     matching links to.
    public static func rule(forURL url: URL, destination: RoutingDestination) -> Rule? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let normalizedHost = host.lowercased()

        if let registrable = RegistrableDomain.of(host: normalizedHost) {
            return Rule(pattern: "*\(registrable)", destination: destination, isEnabled: true)
        }

        // No registrable domain (IP literal or single-label host): scope to the
        // exact host so the rule matches only it.
        return Rule(pattern: normalizedHost, destination: destination, isEnabled: true)
    }

    /// Returns the `Rule` to persist for remembering `target` for `url`, or
    /// `nil` when `url` has no host to scope a rule to. This convenience delegates
    /// to ``rule(forURL:destination:)`` with a `.browser(target)` destination, so
    /// a remembered concrete-browser choice behaves exactly as before.
    ///
    /// - Parameters:
    ///   - url: The link whose destination should be remembered.
    ///   - target: The browser/profile to route matching links to.
    public static func rule(forURL url: URL, target: BrowserTarget) -> Rule? {
        rule(forURL: url, destination: .browser(target))
    }
}
