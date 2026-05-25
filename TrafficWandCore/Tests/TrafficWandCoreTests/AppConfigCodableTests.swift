import Foundation
import Testing
@testable import TrafficWandCore

@Suite("AppConfig Codable")
struct AppConfigCodableTests {
    private func roundTrip(_ config: AppConfig) throws -> AppConfig {
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoder = JSONDecoder()
        return try decoder.decode(AppConfig.self, from: data)
    }

    @Test("Round-trips an AppConfig with a .picker fallback")
    func roundTripPicker() throws {
        let config = AppConfig(
            schemaVersion: 1,
            rules: [
                Rule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    pattern: "*.github.com",
                    target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Default"),
                    isEnabled: true
                )
            ],
            fallback: .picker
        )
        let decoded = try roundTrip(config)
        #expect(decoded == config)
    }

    @Test("Round-trips an AppConfig with a .defaultBrowser fallback")
    func roundTripDefaultBrowser() throws {
        let target = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "Personal")
        let config = AppConfig(
            schemaVersion: 1,
            rules: [],
            fallback: .defaultBrowser(target)
        )
        let decoded = try roundTrip(config)
        #expect(decoded == config)
        #expect(decoded.fallback == .defaultBrowser(target))
    }

    @Test("Round-trips an AppConfig with a .lastUsed fallback")
    func roundTripLastUsed() throws {
        let config = AppConfig(
            schemaVersion: 2,
            rules: [
                Rule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    pattern: "*example.com",
                    target: BrowserTarget(bundleID: "com.apple.Safari", profileID: nil),
                    isEnabled: false
                )
            ],
            fallback: .lastUsed
        )
        let decoded = try roundTrip(config)
        #expect(decoded == config)
        #expect(decoded.fallback == .lastUsed)
    }

    @Test("BrowserTarget round-trips with and without a profileID")
    func browserTargetRoundTrip() throws {
        let withProfile = BrowserTarget(bundleID: "com.brave.Browser", profileID: "Profile 1")
        let withoutProfile = BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let a = try decoder.decode(BrowserTarget.self, from: encoder.encode(withProfile))
        let b = try decoder.decode(BrowserTarget.self, from: encoder.encode(withoutProfile))
        #expect(a == withProfile)
        #expect(b == withoutProfile)
        #expect(b.profileID == nil)
    }

    @Test("Default config has empty rules, .picker fallback, and schemaVersion 1")
    func defaultConfig() {
        let config = AppConfig.default
        #expect(config.rules.isEmpty)
        #expect(config.fallback == .picker)
        #expect(config.schemaVersion == AppConfig.currentSchemaVersion)
        #expect(AppConfig.currentSchemaVersion == 1)
    }

    @Test("Default config round-trips")
    func defaultConfigRoundTrips() throws {
        let decoded = try roundTrip(.default)
        #expect(decoded == .default)
    }
}

@Suite("AppConfig JSON shape")
struct AppConfigJSONShapeTests {
    private func decode(_ json: String) throws -> AppConfig {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    @Test("Decodes a hand-written sample with a .picker fallback (locks on-disk format)")
    func decodePickerSample() throws {
        let json = """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "pattern": "*.github.com",
              "target": {
                "bundleID": "com.google.Chrome",
                "profileID": "Default"
              },
              "isEnabled": true
            }
          ],
          "fallback": {
            "type": "picker"
          }
        }
        """
        let config = try decode(json)
        #expect(config.schemaVersion == 1)
        #expect(config.rules.count == 1)
        #expect(config.rules[0].pattern == "*.github.com")
        #expect(config.rules[0].target.bundleID == "com.google.Chrome")
        #expect(config.rules[0].target.profileID == "Default")
        #expect(config.rules[0].isEnabled == true)
        #expect(config.fallback == .picker)
    }

    @Test("Decodes a hand-written sample with a .defaultBrowser fallback")
    func decodeDefaultBrowserSample() throws {
        let json = """
        {
          "schemaVersion": 1,
          "rules": [],
          "fallback": {
            "type": "defaultBrowser",
            "target": {
              "bundleID": "org.mozilla.firefox",
              "profileID": "Personal"
            }
          }
        }
        """
        let config = try decode(json)
        #expect(config.rules.isEmpty)
        #expect(config.fallback == .defaultBrowser(BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "Personal")))
    }

    @Test("Decodes a hand-written sample with a .lastUsed fallback (no nested payload)")
    func decodeLastUsedSample() throws {
        let json = """
        {
          "schemaVersion": 1,
          "rules": [],
          "fallback": {
            "type": "lastUsed"
          }
        }
        """
        let config = try decode(json)
        #expect(config.fallback == .lastUsed)
    }

    @Test("BrowserTarget omits profileID key entirely when nil")
    func encodeOmitsNilProfileID() throws {
        let target = BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)
        let data = try JSONEncoder().encode(target)
        let string = String(decoding: data, as: UTF8.self)
        #expect(!string.contains("profileID"))
        #expect(string.contains("bundleID"))
    }

    @Test("FallbackPolicy uses the stable discriminator key 'type'")
    func fallbackUsesTypeDiscriminator() throws {
        let encoder = JSONEncoder()
        let pickerData = try encoder.encode(FallbackPolicy.picker)
        let lastUsedData = try encoder.encode(FallbackPolicy.lastUsed)
        let defaultData = try encoder.encode(FallbackPolicy.defaultBrowser(BrowserTarget(bundleID: "x", profileID: nil)))
        #expect(String(decoding: pickerData, as: UTF8.self).contains("\"picker\""))
        #expect(String(decoding: lastUsedData, as: UTF8.self).contains("\"lastUsed\""))
        #expect(String(decoding: defaultData, as: UTF8.self).contains("\"defaultBrowser\""))
    }
}
