import Foundation
import Testing
@testable import TrafficWandCore

@Suite("RememberRule.rule(forURL:destination:) — pattern scoping with a browser destination")
struct RememberRuleTests {
    private let target = BrowserTarget(bundleID: "com.example.Browser", profileID: "Profile 1")

    @Test("A URL with a host yields a leading-star registrable-domain rule")
    func hostYieldsRule() throws {
        let url = URL(string: "https://www.x.com/some/path?q=1")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        #expect(rule.pattern == "*x.com")
        #expect(rule.isEnabled)
        #expect(rule.destination == .browser(target))
    }

    @Test("A subdomain URL collapses to the registrable domain pattern")
    func subdomainCollapsesToRegistrable() throws {
        let url = URL(string: "https://news.x.com/article")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        #expect(rule.pattern == "*x.com")
    }

    @Test("A two-level public-suffix host keeps that suffix")
    func twoLevelSuffix() throws {
        let url = URL(string: "https://a.b.x.co.uk/")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        #expect(rule.pattern == "*x.co.uk")
    }

    @Test("The built pattern matches the apex and its subdomains")
    func patternMatchesApexAndSubdomains() throws {
        let url = URL(string: "https://www.x.com/")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        let glob = GlobPattern(rule.pattern)
        #expect(glob.matches("x.com"))
        #expect(glob.matches("www.x.com"))
        #expect(glob.matches("news.x.com"))
    }

    @Test("The leading-star pattern ALSO matches hosts that merely end with the domain")
    func patternBreadthMatchesEndsWithHosts() throws {
        // This pins the *actual* behavior of the project's leading-star glob idiom:
        // "*x.com" compiles to ".*x\\.com", which matches any host ending in "x.com",
        // including unrelated hosts. A single glob cannot express "apex + subdomains
        // but nothing else", so this breadth is an accepted, documented limitation of
        // the "domain + subdomains" idiom (see RememberRule's doc comment), NOT a bug.
        let url = URL(string: "https://www.x.com/")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        let glob = GlobPattern(rule.pattern)
        #expect(glob.matches("notx.com"))
        #expect(glob.matches("evilx.com"))
        #expect(glob.matches("phishing-x.com"))
    }

    @Test("A mixed-case host yields a lowercase registrable-domain pattern")
    func mixedCaseHostLowercasesPattern() throws {
        let url = URL(string: "https://WWW.X.COM/")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        #expect(rule.pattern == "*x.com")
    }

    @Test("An IPv4-literal host yields an exact-host pattern with no leading star")
    func ipv4LiteralExactHost() throws {
        let url = URL(string: "http://192.168.0.1:8080/admin")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        #expect(rule.pattern == "192.168.0.1")
        #expect(rule.isEnabled)
        #expect(rule.destination == .browser(target))
    }

    @Test("An IPv6-literal host yields an exact-host pattern with no leading star")
    func ipv6LiteralExactHost() throws {
        let url = URL(string: "http://[2001:db8::1]/")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        // URL.host strips the bracketing, leaving the bare address.
        #expect(rule.pattern == "2001:db8::1")
    }

    @Test("A single-label host yields an exact-host pattern with no leading star")
    func singleLabelExactHost() throws {
        let url = URL(string: "http://localhost:3000/")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        #expect(rule.pattern == "localhost")
    }

    @Test("A mixed-case single-label host yields a lowercased exact-host pattern")
    func mixedCaseSingleLabelLowercasesPattern() throws {
        let url = URL(string: "http://LOCALHOST:3000/")!
        let rule = try #require(RememberRule.rule(forURL: url, destination: .browser(target)))
        // The exact-host branch lowercases too, so the pattern stays lowercase.
        #expect(rule.pattern == "localhost")
    }

    @Test("A mailto: URL has no host and yields nil")
    func mailtoYieldsNil() {
        let url = URL(string: "mailto:someone@example.com")!
        #expect(RememberRule.rule(forURL: url, destination: .browser(target)) == nil)
    }

    @Test("A file: URL has no host and yields nil")
    func fileYieldsNil() {
        let url = URL(string: "file:///tmp/x")!
        #expect(RememberRule.rule(forURL: url, destination: .browser(target)) == nil)
    }
}

@Suite("RememberRule.rule(forURL:destination:)")
struct RememberRuleDestinationTests {
    private let target = BrowserTarget(bundleID: "com.example.Browser", profileID: "Profile 1")
    private let aliasID = UUID()

    @Test("A browser destination yields a leading-star registrable-domain rule carrying that destination")
    func browserDestinationHostYieldsRule() throws {
        let url = URL(string: "https://www.x.com/some/path?q=1")!
        let destination = RoutingDestination.browser(target)
        let rule = try #require(RememberRule.rule(forURL: url, destination: destination))
        #expect(rule.pattern == "*x.com")
        #expect(rule.isEnabled)
        #expect(rule.destination == destination)
    }

    @Test("An alias destination yields a leading-star registrable-domain rule carrying the alias destination")
    func aliasDestinationHostYieldsRule() throws {
        let url = URL(string: "https://www.x.com/some/path?q=1")!
        let destination = RoutingDestination.alias(aliasID)
        let rule = try #require(RememberRule.rule(forURL: url, destination: destination))
        #expect(rule.pattern == "*x.com")
        #expect(rule.isEnabled)
        #expect(rule.destination == destination)
    }

    @Test("An alias destination on a subdomain collapses to the registrable domain pattern")
    func aliasDestinationSubdomainCollapses() throws {
        let url = URL(string: "https://news.x.com/article")!
        let destination = RoutingDestination.alias(aliasID)
        let rule = try #require(RememberRule.rule(forURL: url, destination: destination))
        #expect(rule.pattern == "*x.com")
        #expect(rule.destination == destination)
    }

    @Test("An alias destination on an IPv4-literal host yields an exact-host pattern")
    func aliasDestinationIPv4ExactHost() throws {
        let url = URL(string: "http://192.168.0.1:8080/admin")!
        let destination = RoutingDestination.alias(aliasID)
        let rule = try #require(RememberRule.rule(forURL: url, destination: destination))
        #expect(rule.pattern == "192.168.0.1")
        #expect(rule.destination == destination)
    }

    @Test("An alias destination on a single-label host yields an exact-host pattern")
    func aliasDestinationSingleLabelExactHost() throws {
        let url = URL(string: "http://localhost:3000/")!
        let destination = RoutingDestination.alias(aliasID)
        let rule = try #require(RememberRule.rule(forURL: url, destination: destination))
        #expect(rule.pattern == "localhost")
        #expect(rule.destination == destination)
    }

    @Test("A mailto: URL has no host and yields nil for an alias destination")
    func aliasDestinationMailtoYieldsNil() {
        let url = URL(string: "mailto:someone@example.com")!
        #expect(RememberRule.rule(forURL: url, destination: .alias(aliasID)) == nil)
    }

    @Test("A file: URL has no host and yields nil for an alias destination")
    func aliasDestinationFileYieldsNil() {
        let url = URL(string: "file:///tmp/x")!
        #expect(RememberRule.rule(forURL: url, destination: .alias(aliasID)) == nil)
    }
}
