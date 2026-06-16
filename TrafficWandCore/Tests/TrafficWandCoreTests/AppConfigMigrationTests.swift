import Foundation
import Testing
@testable import TrafficWandCore

/// A `.browser` destination wrapping a `BrowserTarget`, for terse assertions.
private func browser(_ bundleID: String, _ profileID: String? = nil) -> RoutingDestination {
    .browser(BrowserTarget(bundleID: bundleID, profileID: profileID))
}

// MARK: - Rule backward-compatible decode (schema v1 → v2)

@Suite("Rule legacy/v2 Codable")
struct RuleCodableMigrationTests {
    private func decodeRule(_ json: String) throws -> Rule {
        try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
    }

    @Test("Decoding legacy JSON with a bare `target` yields a .browser destination")
    func decodeLegacyTargetYieldsBrowser() throws {
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "pattern": "*.github.com",
          "target": { "bundleID": "com.google.Chrome", "profileID": "Default" },
          "isEnabled": true
        }
        """
        let rule = try decodeRule(json)
        #expect(rule.pattern == "*.github.com")
        #expect(rule.isEnabled)
        #expect(rule.destination == browser("com.google.Chrome", "Default"))
    }

    @Test("Decoding v2 JSON with a `destination` round-trips")
    func decodeV2DestinationRoundTrips() throws {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "pattern": "*example.com",
          "destination": { "type": "browser", "target": { "bundleID": "com.apple.Safari" } },
          "isEnabled": false
        }
        """
        let rule = try decodeRule(json)
        #expect(rule.destination == browser("com.apple.Safari"))
        #expect(rule.isEnabled == false)
    }

    @Test("Decoding v2 JSON with an alias destination preserves the reference")
    func decodeV2AliasDestination() throws {
        let aliasID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let json = """
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "pattern": "*work.com",
          "destination": { "type": "alias", "id": "\(aliasID.uuidString)" },
          "isEnabled": true
        }
        """
        let rule = try decodeRule(json)
        #expect(rule.destination == .alias(aliasID))
    }

    @Test("Encoding a Rule always emits `destination`, never the legacy `target`")
    func encodeAlwaysEmitsDestination() throws {
        let rule = Rule(
            pattern: "*.github.com",
            destination: browser("com.google.Chrome", "Default"),
            isEnabled: true
        )
        let data = try JSONEncoder().encode(rule)
        let string = try #require(String(bytes: data, encoding: .utf8))
        #expect(string.contains("\"destination\""))
        // Re-decoding the encoded form must reproduce the same rule (it would
        // fail if the legacy top-level `target` key were emitted instead).
        let decoded = try decodeRule(string)
        #expect(decoded == rule)
    }
}

// MARK: - FallbackPolicy backward-compatible decode (schema v1 → v2)

@Suite("FallbackPolicy legacy/v2 Codable")
struct FallbackPolicyMigrationTests {
    private func decodeFallback(_ json: String) throws -> FallbackPolicy {
        try JSONDecoder().decode(FallbackPolicy.self, from: Data(json.utf8))
    }

    @Test("Legacy defaultBrowser with a bare BrowserTarget decodes to .defaultBrowser(.browser)")
    func legacyDefaultBrowserDecodes() throws {
        let json = """
        { "type": "defaultBrowser", "target": { "bundleID": "org.mozilla.firefox", "profileID": "Work" } }
        """
        let fallback = try decodeFallback(json)
        #expect(fallback == .defaultBrowser(browser("org.mozilla.firefox", "Work")))
    }

    @Test("v2 defaultBrowser with an alias RoutingDestination round-trips")
    func v2DefaultBrowserAliasRoundTrips() throws {
        let aliasID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let json = """
        { "type": "defaultBrowser", "target": { "type": "alias", "id": "\(aliasID.uuidString)" } }
        """
        let fallback = try decodeFallback(json)
        #expect(fallback == .defaultBrowser(.alias(aliasID)))
    }

    @Test(".picker and .lastUsed decode unchanged")
    func pickerAndLastUsedUnchanged() throws {
        #expect(try decodeFallback(#"{ "type": "picker" }"#) == .picker)
        #expect(try decodeFallback(#"{ "type": "lastUsed" }"#) == .lastUsed)
    }
}

// MARK: - Full v1 → v2 config migration

@Suite("AppConfig v1 → v2 migration")
struct AppConfigMigrationTests {
    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    @Test("A complete legacy v1 config.json migrates cleanly (no aliases, bare targets)")
    func fullV1Migration() throws {
        // A complete pre-feature config: schemaVersion 1, no `aliases` key, rules
        // with a bare `target`, fallback with a bare `target`.
        let json = """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "id": "77777777-7777-7777-7777-777777777777",
              "pattern": "*.github.com",
              "target": { "bundleID": "com.google.Chrome", "profileID": "Default" },
              "isEnabled": true
            },
            {
              "id": "88888888-8888-8888-8888-888888888888",
              "pattern": "*example.com",
              "target": { "bundleID": "com.apple.Safari" },
              "isEnabled": false
            }
          ],
          "fallback": {
            "type": "defaultBrowser",
            "target": { "bundleID": "org.mozilla.firefox", "profileID": "Personal" }
          }
        }
        """
        let config = try decode(json)

        #expect(config.schemaVersion == 1)
        #expect(config.aliases == [])
        #expect(config.rules.count == 2)
        #expect(config.rules[0].destination == browser("com.google.Chrome", "Default"))
        #expect(config.rules[1].destination == browser("com.apple.Safari"))
        #expect(config.fallback == .defaultBrowser(browser("org.mozilla.firefox", "Personal")))
    }

    @Test("A config without an `aliases` key defaults to an empty alias list")
    func absentAliasesDefaultsToEmpty() throws {
        let json = """
        {
          "schemaVersion": 1,
          "rules": [],
          "fallback": { "type": "picker" }
        }
        """
        let config = try decode(json)
        #expect(config.aliases == [])
    }

    @Test("Re-encoding a decoded v1 config emits the v2 shapes (`aliases`, `destination`)")
    func reEncodingV1EmitsV2Shapes() throws {
        // Decoding a legacy v1 document then re-encoding it must emit the v2 on-disk
        // shapes: an `aliases` array and per-rule/per-fallback `destination`-style
        // `RoutingDestination` payloads (a tagged object with a `type` discriminator),
        // never the bare legacy `target`. This pins the load-then-save migration's
        // written form. (The monotonic schemaVersion bump to currentSchemaVersion
        // happens at the App `SettingsViewModel.persist` layer, which is exercised by
        // SettingsViewModelTests; `AppConfig` itself round-trips the decoded version.)
        let json = """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "id": "77777777-7777-7777-7777-777777777777",
              "pattern": "*.github.com",
              "target": { "bundleID": "com.google.Chrome", "profileID": "Default" },
              "isEnabled": true
            }
          ],
          "fallback": {
            "type": "defaultBrowser",
            "target": { "bundleID": "org.mozilla.firefox", "profileID": "Personal" }
          }
        }
        """
        let config = try decode(json)
        let data = try JSONEncoder().encode(config)
        let string = try #require(String(bytes: data, encoding: .utf8))

        #expect(string.contains("\"aliases\""))
        #expect(string.contains("\"destination\""))

        // Inspect the decoded JSON tree (not fragile substrings): each rule must carry
        // a v2 `destination` and *not* the legacy top-level `target` key.
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let rules = try #require(root["rules"] as? [[String: Any]])
        let rule = try #require(rules.first)
        #expect(rule["destination"] != nil)
        #expect(rule["target"] == nil, "The legacy top-level rule `target` key must not be re-emitted.")

        // Re-decoding the migrated form reproduces the same in-memory config.
        let reDecoded = try decode(string)
        #expect(reDecoded == config)
    }
}
