import Foundation

/// Matches a URL against an ordered list of routing rules.
///
/// Matching is performed against the URL's **host** only (per `GlobScope.host`):
/// the host is lowercased and any port/userinfo is dropped (`URL.host` already
/// excludes those), then compared against each rule's `GlobPattern`.
///
/// Semantics (locked during planning):
/// - **First match wins** over the ordered `rules` array.
/// - **Disabled** rules (`isEnabled == false`) are skipped.
/// - A URL with **no host** (or an empty host) never matches → `nil`.
/// - No matching rule → `nil`.
public enum RuleMatcher {
    /// Returns the first enabled rule whose pattern matches `url`'s host, or
    /// `nil` if the URL has no usable host or no rule matches.
    ///
    /// - Parameters:
    ///   - url: The link to route. Only its host participates in matching.
    ///   - rules: The ordered rule list; earlier rules take precedence.
    public static func firstMatch(for url: URL, in rules: [Rule]) -> Rule? {
        guard let host = normalizedHost(of: url) else { return nil }
        for rule in rules where rule.isEnabled {
            if GlobPattern(rule.pattern).matches(host) {
                return rule
            }
        }
        return nil
    }

    /// Extracts the lowercased host from `url`, or `nil` when there is no host
    /// (e.g. `mailto:`, `file:///…`) or the host is empty.
    ///
    /// `URL.host` already strips userinfo and port, leaving just the host.
    private static func normalizedHost(of url: URL) -> String? {
        guard let host = url.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }
}
