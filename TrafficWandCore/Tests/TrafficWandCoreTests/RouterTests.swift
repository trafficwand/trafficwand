import Foundation
import Testing
@testable import TrafficWandCore

@Suite("Router decision logic")
struct RouterTests {
    private let url = URL(string: "https://gist.github.com/foo")!

    /// A rule matching the test URL's host, targeting `bundleID`.
    private func matchingRule(bundleID: String, profileID: String? = nil) -> Rule {
        Rule(
            pattern: "*.github.com",
            destination: .browser(BrowserTarget(bundleID: bundleID, profileID: profileID)),
            isEnabled: true
        )
    }

    /// A throwaway browser for `.prompt` assertions.
    private func browser(_ bundleID: String) -> Browser {
        Browser(
            bundleID: bundleID,
            name: bundleID,
            appURL: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            profiles: []
        )
    }

    @Test("A matching rule yields .open(rule.target)")
    func ruleMatchOpensTarget() {
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Work")
        let config = AppConfig(
            rules: [Rule(pattern: "*.github.com", destination: .browser(target), isEnabled: true)],
            fallback: .picker
        )
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: []
        )
        #expect(decision == .open(target))
    }

    @Test("A matching rule wins over the fallback policy")
    func ruleMatchBeatsFallback() {
        let ruleTarget = BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)
        let fallbackTarget = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)
        let config = AppConfig(
            rules: [Rule(pattern: "*.github.com", destination: .browser(ruleTarget), isEnabled: true)],
            fallback: .defaultBrowser(.browser(fallbackTarget))
        )
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: BrowserTarget(bundleID: "com.brave.Browser", profileID: nil),
            availableBrowsers: [browser("a")]
        )
        #expect(decision == .open(ruleTarget))
    }

    @Test("No match + .defaultBrowser yields .open(target)")
    func noMatchDefaultBrowserOpens() {
        let target = BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)
        let config = AppConfig(rules: [], fallback: .defaultBrowser(.browser(target)))
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: []
        )
        #expect(decision == .open(target))
    }

    @Test("No match + .picker yields .prompt with the available browsers")
    func noMatchPickerPrompts() {
        let browsers = [browser("com.apple.Safari"), browser("org.mozilla.firefox")]
        let config = AppConfig(rules: [], fallback: .picker)
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: browsers
        )
        #expect(decision == .prompt(url: url, browsers: browsers))
    }

    @Test("No match + .lastUsed with a recorded value yields .open(recorded)")
    func noMatchLastUsedRecordedOpens() {
        let recorded = BrowserTarget(bundleID: "com.brave.Browser", profileID: "Personal")
        let config = AppConfig(rules: [], fallback: .lastUsed)
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: recorded,
            availableBrowsers: [browser("a")]
        )
        #expect(decision == .open(recorded))
    }

    @Test("No match + .lastUsed with no recorded value yields .prompt")
    func noMatchLastUsedEmptyPrompts() {
        let browsers = [browser("com.apple.Safari")]
        let config = AppConfig(rules: [], fallback: .lastUsed)
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: browsers
        )
        #expect(decision == .prompt(url: url, browsers: browsers))
    }

    @Test("A non-matching rule falls through to the fallback policy")
    func nonMatchingRuleFallsThrough() {
        let fallbackTarget = BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)
        let config = AppConfig(
            rules: [
                Rule(
                    pattern: "*.example.com",
                    destination: .browser(BrowserTarget(bundleID: "ignored", profileID: nil)),
                    isEnabled: true
                )
            ],
            fallback: .defaultBrowser(.browser(fallbackTarget))
        )
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: []
        )
        #expect(decision == .open(fallbackTarget))
    }

    @Test("A disabled matching rule is skipped and the fallback applies")
    func disabledRuleSkipped() {
        let ruleTarget = BrowserTarget(bundleID: "com.google.Chrome", profileID: nil)
        let config = AppConfig(
            rules: [Rule(pattern: "*.github.com", destination: .browser(ruleTarget), isEnabled: false)],
            fallback: .picker
        )
        let browsers = [browser("a")]
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: browsers
        )
        #expect(decision == .prompt(url: url, browsers: browsers))
    }

    // MARK: - Alias resolution

    @Test("A matching rule with an .alias destination resolves to the alias's target")
    func ruleMatchAliasResolvesToTarget() {
        let aliasID = UUID()
        let aliasTarget = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        let config = AppConfig(
            aliases: [ProfileAlias(id: aliasID, name: "Personal", target: aliasTarget)],
            rules: [Rule(pattern: "*.github.com", destination: .alias(aliasID), isEnabled: true)],
            fallback: .picker
        )
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: []
        )
        #expect(decision == .open(aliasTarget))
    }

    @Test("A matching rule with a dangling .alias destination yields .prompt")
    func ruleMatchDanglingAliasPrompts() {
        let config = AppConfig(
            aliases: [],
            rules: [Rule(pattern: "*.github.com", destination: .alias(UUID()), isEnabled: true)],
            fallback: .picker
        )
        let browsers = [browser("com.apple.Safari")]
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: browsers
        )
        #expect(decision == .prompt(url: url, browsers: browsers))
    }

    @Test("No match + .defaultBrowser(.alias) resolves to the alias's target")
    func noMatchDefaultBrowserAliasResolves() {
        let aliasID = UUID()
        let aliasTarget = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "Work")
        let config = AppConfig(
            aliases: [ProfileAlias(id: aliasID, name: "Work", target: aliasTarget)],
            rules: [],
            fallback: .defaultBrowser(.alias(aliasID))
        )
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: []
        )
        #expect(decision == .open(aliasTarget))
    }

    @Test("No match + .defaultBrowser(.alias) with a dangling alias yields .prompt")
    func noMatchDefaultBrowserDanglingAliasPrompts() {
        let config = AppConfig(
            aliases: [],
            rules: [],
            fallback: .defaultBrowser(.alias(UUID()))
        )
        let browsers = [browser("com.apple.Safari")]
        let decision = Router.decide(
            url: url,
            config: config,
            lastUsed: nil,
            availableBrowsers: browsers
        )
        #expect(decision == .prompt(url: url, browsers: browsers))
    }
}
