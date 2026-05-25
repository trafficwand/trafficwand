import Foundation

/// Pure routing policy: turns a link plus the current configuration and state
/// into a `RoutingDecision`.
///
/// Decision logic (locked during planning):
/// 1. If an enabled rule matches the URL's host (`RuleMatcher.firstMatch`),
///    open in that rule's target.
/// 2. Otherwise consult `config.fallback`:
///    - `.defaultBrowser(target)` → open in that target.
///    - `.picker` → prompt with the available browsers.
///    - `.lastUsed` → open the recorded last-used target if there is one;
///      otherwise prompt. The picker is always the ultimate fallback, so
///      `.lastUsed` with nothing recorded resolves to `.prompt`.
public enum Router {
    /// Decides where a link should go.
    ///
    /// - Parameters:
    ///   - url: The link to route.
    ///   - config: The current rule list and fallback policy.
    ///   - lastUsed: The most recently used target, if any (used by `.lastUsed`).
    ///   - availableBrowsers: Browsers offered when the decision is `.prompt`.
    /// - Returns: The routing decision for the App layer to carry out.
    public static func decide(
        url: URL,
        config: AppConfig,
        lastUsed: BrowserTarget?,
        availableBrowsers: [Browser]
    ) -> RoutingDecision {
        if let rule = RuleMatcher.firstMatch(for: url, in: config.rules) {
            return .open(rule.target)
        }

        switch config.fallback {
        case .defaultBrowser(let target):
            return .open(target)
        case .picker:
            return .prompt(url: url, browsers: availableBrowsers)
        case .lastUsed:
            if let lastUsed {
                return .open(lastUsed)
            }
            return .prompt(url: url, browsers: availableBrowsers)
        }
    }
}
