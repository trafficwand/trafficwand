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
///   no leading star, so it matches only that host.
/// - For a hostless URL (`mailto:`, `file:///…`), there is nothing to remember
///   and the result is `nil`.
public enum RememberRule {
    /// Returns the `Rule` to persist for remembering `target` for `url`, or
    /// `nil` when `url` has no host to scope a rule to.
    ///
    /// - Parameters:
    ///   - url: The link whose destination should be remembered.
    ///   - target: The browser/profile to route matching links to.
    public static func rule(forURL url: URL, target: BrowserTarget) -> Rule? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let normalizedHost = host.lowercased()

        if let registrable = RegistrableDomain.of(host: normalizedHost) {
            return Rule(pattern: "*\(registrable)", target: target, isEnabled: true)
        }

        // No registrable domain (IP literal or single-label host): scope to the
        // exact host so the rule matches only it.
        return Rule(pattern: normalizedHost, target: target, isEnabled: true)
    }
}
