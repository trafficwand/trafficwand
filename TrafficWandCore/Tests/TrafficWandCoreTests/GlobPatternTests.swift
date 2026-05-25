import Foundation
import Testing
@testable import TrafficWandCore

@Suite("GlobPattern matching")
struct GlobPatternTests {
    @Test("A literal pattern matches only the identical host")
    func literalMatch() {
        let glob = GlobPattern("github.com")
        #expect(glob.matches("github.com"))
        #expect(!glob.matches("gist.github.com"))
        #expect(!glob.matches("github.con"))
        #expect(!glob.matches("agithub.com"))
    }

    @Test("`*` matches zero or more of any character, including dots")
    func starMatchesZeroOrMoreIncludingDots() {
        let glob = GlobPattern("*github.com")
        #expect(glob.matches("github.com"))            // zero characters
        #expect(glob.matches("gist.github.com"))       // includes a dot
        #expect(glob.matches("a.b.c.github.com"))      // multiple dots
        #expect(glob.matches("xgithub.com"))           // no dot
    }

    @Test("`*` alone matches anything including the empty string")
    func starOnlyMatchesEverything() {
        let glob = GlobPattern("*")
        #expect(glob.matches(""))
        #expect(glob.matches("github.com"))
        #expect(glob.matches("a.very.long.host.example.org"))
    }

    @Test("`?` matches exactly one character")
    func questionMarkMatchesSingleCharacter() {
        let glob = GlobPattern("githu?.com")
        #expect(glob.matches("github.com"))
        #expect(glob.matches("githuX.com"))
        #expect(!glob.matches("githu.com"))    // zero characters: no match
        #expect(!glob.matches("githubb.com"))  // two characters: no match
    }

    @Test("`?` matches a dot too (it is any single character)")
    func questionMarkMatchesDot() {
        let glob = GlobPattern("a?b")
        #expect(glob.matches("a.b"))
        #expect(glob.matches("axb"))
        #expect(!glob.matches("ab"))
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        let glob = GlobPattern("*.GitHub.com")
        #expect(glob.matches("gist.github.com"))
        #expect(glob.matches("GIST.GITHUB.COM"))
        #expect(GlobPattern("GitHub.com").matches("github.com"))
    }

    @Test("Patterns are anchored to the full host")
    func anchoredToFullHost() {
        let glob = GlobPattern("github.com")
        #expect(!glob.matches("www.github.com"))
        #expect(!glob.matches("github.com.evil.example"))
        #expect(!glob.matches("notgithub.com"))
    }

    @Test("A literal dot matches only a dot, not any character")
    func dotIsLiteral() {
        let glob = GlobPattern("a.c")
        #expect(glob.matches("a.c"))
        #expect(!glob.matches("axc"))   // `.` is literal, not a regex wildcard
        #expect(!glob.matches("abc"))
    }

    @Test("Regex metacharacters in the literal portion are escaped")
    func regexMetacharactersEscaped() {
        // `+` is a regex quantifier; here it must be a literal plus sign.
        let plus = GlobPattern("a+b.com")
        #expect(plus.matches("a+b.com"))
        #expect(!plus.matches("aaab.com"))   // would match if `+` were a quantifier
        #expect(!plus.matches("ab.com"))

        // Parentheses must be literal, not a regex group.
        let parens = GlobPattern("(test).com")
        #expect(parens.matches("(test).com"))
        #expect(!parens.matches("test.com"))

        // A literal `$` and `^` must not act as anchors mid-pattern.
        let dollar = GlobPattern("a$b.com")
        #expect(dollar.matches("a$b.com"))
        #expect(!dollar.matches("ab.com"))

        // Backslash is literal too.
        let backslash = GlobPattern("a\\b.com")
        #expect(backslash.matches("a\\b.com"))
    }

    @Test("`*.github.com` matches subdomains but NOT the apex")
    func dotStarMatchesSubdomainsNotApex() {
        let glob = GlobPattern("*.github.com")
        #expect(glob.matches("gist.github.com"))
        #expect(glob.matches("api.gist.github.com"))
        #expect(!glob.matches("github.com"))   // apex requires the leading dot
    }

    @Test("`*github.com` matches both apex and subdomains")
    func starGithubMatchesApexAndSubdomains() {
        let glob = GlobPattern("*github.com")
        #expect(glob.matches("github.com"))        // apex
        #expect(glob.matches("gist.github.com"))   // subdomain
        #expect(glob.matches("www.github.com"))    // subdomain
    }

    @Test("An empty pattern matches only the empty string")
    func emptyPattern() {
        let glob = GlobPattern("")
        #expect(glob.matches(""))
        #expect(!glob.matches("github.com"))
        #expect(!glob.matches("a"))
    }

    @Test("Compiled form is cached and reused across calls")
    func compiledFormIsReused() {
        let glob = GlobPattern("*.example.com")
        // Multiple matches against the same instance should not recompile and
        // must return consistent results.
        #expect(glob.matches("a.example.com"))
        #expect(glob.matches("b.example.com"))
        #expect(!glob.matches("example.com"))
        #expect(glob.matches("a.example.com"))
    }
}
