import Foundation
import Testing
@testable import TrafficWandCore

@Suite("RuleMatcher against URLs")
struct RuleMatcherTests {
    /// Convenience: a rule with a given pattern, a throwaway target, optionally disabled.
    private func rule(_ pattern: String, isEnabled: Bool = true) -> Rule {
        Rule(
            pattern: pattern,
            destination: .browser(BrowserTarget(bundleID: "test.\(pattern)", profileID: nil)),
            isEnabled: isEnabled
        )
    }

    @Test("Matches against the URL host")
    func matchesAgainstHost() {
        let rules = [rule("*.github.com")]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://gist.github.com/foo")!, in: rules)
        #expect(match == rules[0])
    }

    @Test("Host extraction lowercases the host before matching")
    func uppercaseHostMatchedCaseInsensitively() {
        // The pattern is lowercase; the URL host is uppercase. Lowercasing the
        // host (and the case-insensitive glob) means it still matches.
        let rules = [rule("example.com")]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://EXAMPLE.COM/path")!, in: rules)
        #expect(match == rules[0])
    }

    @Test("Port is stripped from the host before matching")
    func portStrippedFromHost() {
        let rules = [rule("example.com")]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://example.com:8443/path")!, in: rules)
        #expect(match == rules[0])
    }

    @Test("Userinfo and port in the URL do not affect host extraction")
    func userinfoAndPortStripped() {
        let rules = [rule("example.com")]
        let match = RuleMatcher.firstMatch(
            for: URL(string: "https://user:pass@example.com:9000/path?q=1")!,
            in: rules
        )
        #expect(match == rules[0])
    }

    @Test("First matching rule wins over later matches (ordered)")
    func firstMatchWins() {
        let first = rule("*.github.com")
        let second = rule("gist.github.com")
        let rules = [first, second]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://gist.github.com")!, in: rules)
        #expect(match == first)
    }

    @Test("Earlier non-matching rules are skipped to find a later match")
    func skipsEarlierNonMatches() {
        let first = rule("*.example.com")
        let second = rule("*.github.com")
        let rules = [first, second]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://gist.github.com")!, in: rules)
        #expect(match == second)
    }

    @Test("Disabled rules are skipped even if their pattern matches")
    func disabledRulesSkipped() {
        let disabled = rule("*.github.com", isEnabled: false)
        let enabled = rule("gist.github.com")
        let rules = [disabled, enabled]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://gist.github.com")!, in: rules)
        #expect(match == enabled)
    }

    @Test("A disabled rule that is the only match yields nil")
    func onlyDisabledMatchYieldsNil() {
        let rules = [rule("*.github.com", isEnabled: false)]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://gist.github.com")!, in: rules)
        #expect(match == nil)
    }

    @Test("No matching rule returns nil")
    func noMatchReturnsNil() {
        let rules = [rule("*.example.com"), rule("*.github.com")]
        let match = RuleMatcher.firstMatch(for: URL(string: "https://www.apple.com")!, in: rules)
        #expect(match == nil)
    }

    @Test("An empty rule list returns nil")
    func emptyRulesReturnsNil() {
        let match = RuleMatcher.firstMatch(for: URL(string: "https://github.com")!, in: [])
        #expect(match == nil)
    }

    @Test("A URL with no host returns nil")
    func noHostReturnsNil() {
        // A scheme-only / file-style URL with no host component.
        let rules = [rule("*")]
        let match = RuleMatcher.firstMatch(for: URL(string: "mailto:someone@example.com")!, in: rules)
        #expect(match == nil)
    }

    @Test("A URL with an empty host returns nil")
    func emptyHostReturnsNil() {
        let rules = [rule("*")]
        // file:///path has no host.
        let match = RuleMatcher.firstMatch(for: URL(string: "file:///tmp/x")!, in: rules)
        #expect(match == nil)
    }
}
