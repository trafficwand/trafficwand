import Foundation
import Testing
@testable import TrafficWandCore

@Suite("AppConfig.upserting(_:) by pattern")
struct AppConfigUpsertTests {
    /// Convenience: a rule with a given pattern/target, optionally disabled.
    private func rule(
        _ pattern: String,
        bundleID: String,
        profileID: String? = nil,
        isEnabled: Bool = true
    ) -> Rule {
        Rule(
            pattern: pattern,
            target: BrowserTarget(bundleID: bundleID, profileID: profileID),
            isEnabled: isEnabled
        )
    }

    @Test("Appends the rule when no existing rule has the same pattern")
    func appendsWhenNoMatch() {
        let existing = rule("*github.com", bundleID: "com.apple.Safari")
        let config = AppConfig(rules: [existing], fallback: .picker)

        let incoming = rule("*google.com", bundleID: "com.google.Chrome")
        let result = config.upserting(incoming)

        #expect(result.rules.count == 2)
        #expect(result.rules[0] == existing)
        #expect(result.rules[1] == incoming)
    }

    @Test("Appends when config has no rules at all")
    func appendsToEmptyConfig() {
        let config = AppConfig(rules: [], fallback: .picker)
        let incoming = rule("*google.com", bundleID: "com.google.Chrome")

        let result = config.upserting(incoming)

        #expect(result.rules.count == 1)
        #expect(result.rules[0] == incoming)
    }

    @Test("Replaces the target and re-enables when an existing rule shares the pattern")
    func replacesTargetAndReEnablesOnMatch() {
        let original = rule(
            "*google.com",
            bundleID: "com.apple.Safari",
            profileID: "old",
            isEnabled: false
        )
        let config = AppConfig(rules: [original], fallback: .picker)

        let incoming = rule(
            "*google.com",
            bundleID: "com.google.Chrome",
            profileID: "Default",
            isEnabled: true
        )
        let result = config.upserting(incoming)

        // No duplicate: same count.
        #expect(result.rules.count == 1)
        // Updated target.
        #expect(result.rules[0].target == BrowserTarget(bundleID: "com.google.Chrome", profileID: "Default"))
        // Re-enabled.
        #expect(result.rules[0].isEnabled == true)
        // Position and identity preserved.
        #expect(result.rules[0].id == original.id)
        #expect(result.rules[0].pattern == "*google.com")
    }

    @Test("Preserves the order of other rules when upserting an existing pattern")
    func preservesOrderOfOtherRules() {
        let first = rule("*github.com", bundleID: "com.apple.Safari")
        let middle = rule("*google.com", bundleID: "com.apple.Safari", isEnabled: false)
        let last = rule("*example.com", bundleID: "org.mozilla.firefox")
        let config = AppConfig(rules: [first, middle, last], fallback: .picker)

        let incoming = rule("*google.com", bundleID: "com.google.Chrome")
        let result = config.upserting(incoming)

        #expect(result.rules.count == 3)
        #expect(result.rules[0] == first)
        #expect(result.rules[2] == last)
        // The matched rule stays in the middle with its id preserved.
        #expect(result.rules[1].id == middle.id)
        #expect(result.rules[1].target == BrowserTarget(bundleID: "com.google.Chrome", profileID: nil))
        #expect(result.rules[1].isEnabled == true)
    }

    @Test("upserting does not mutate the receiver (pure)")
    func doesNotMutateReceiver() {
        let original = rule("*google.com", bundleID: "com.apple.Safari", isEnabled: false)
        let config = AppConfig(rules: [original], fallback: .picker)

        _ = config.upserting(rule("*google.com", bundleID: "com.google.Chrome"))

        #expect(config.rules.count == 1)
        #expect(config.rules[0] == original)
    }
}
