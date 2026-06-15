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

    /// Issue #13 end-to-end: re-pointing a single alias propagates to *every*
    /// referencing rule at once. Two distinct rules (matching two distinct URLs)
    /// share one `.alias` destination; mutating the alias's target re-routes both
    /// in lockstep through `Router.decide` — the live-reference semantics that
    /// distinguish an alias from a frozen copy.
    @Test("Re-pointing an alias re-routes every rule that references it")
    func repointingAliasPropagatesToAllReferencingRules() {
        let aliasID = UUID()
        let oldTarget = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        let newTarget = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "Work")

        let githubURL = URL(string: "https://gist.github.com/foo")!
        let exampleURL = URL(string: "https://docs.example.com/bar")!

        var config = AppConfig(
            aliases: [ProfileAlias(id: aliasID, name: "Personal", target: oldTarget)],
            rules: [
                Rule(pattern: "*.github.com", destination: .alias(aliasID), isEnabled: true),
                Rule(pattern: "*.example.com", destination: .alias(aliasID), isEnabled: true)
            ],
            fallback: .picker
        )

        // Before re-pointing: both matching URLs resolve to the alias's old target.
        #expect(
            Router.decide(url: githubURL, config: config, lastUsed: nil, availableBrowsers: [])
                == .open(oldTarget)
        )
        #expect(
            Router.decide(url: exampleURL, config: config, lastUsed: nil, availableBrowsers: [])
                == .open(oldTarget)
        )

        // Re-point the single alias at a different browser.
        config.aliases[0].target = newTarget

        // After re-pointing: both referencing rules now resolve to the new target,
        // with no per-rule edits.
        #expect(
            Router.decide(url: githubURL, config: config, lastUsed: nil, availableBrowsers: [])
                == .open(newTarget)
        )
        #expect(
            Router.decide(url: exampleURL, config: config, lastUsed: nil, availableBrowsers: [])
                == .open(newTarget)
        )
    }
}
