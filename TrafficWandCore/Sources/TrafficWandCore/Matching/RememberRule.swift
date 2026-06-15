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
    /// Returns the `Rule` to persist for remembering `target` for `url`, or
    /// `nil` when `url` has no host to scope a rule to. "Remember this site" is a
    /// one-off concrete choice, so the built rule always carries a
    /// `.browser(target)` destination — it never invents an alias.
    ///
    /// - Parameters:
    ///   - url: The link whose destination should be remembered.
    ///   - target: The browser/profile to route matching links to.
    public static func rule(forURL url: URL, target: BrowserTarget) -> Rule? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let normalizedHost = host.lowercased()

        if let registrable = RegistrableDomain.of(host: normalizedHost) {
            return Rule(pattern: "*\(registrable)", destination: .browser(target), isEnabled: true)
        }

        // No registrable domain (IP literal or single-label host): scope to the
        // exact host so the rule matches only it.
        return Rule(pattern: normalizedHost, destination: .browser(target), isEnabled: true)
    }
}
