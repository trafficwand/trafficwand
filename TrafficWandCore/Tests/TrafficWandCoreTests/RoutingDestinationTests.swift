import Foundation
import Testing
@testable import TrafficWandCore

@Suite("RoutingDestination")
struct RoutingDestinationTests {
    private func roundTrip(_ destination: RoutingDestination) throws -> RoutingDestination {
        let data = try JSONEncoder().encode(destination)
        return try JSONDecoder().decode(RoutingDestination.self, from: data)
    }

    private func jsonObject(_ destination: RoutingDestination) throws -> [String: Any] {
        let data = try JSONEncoder().encode(destination)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Encodes .browser as a tagged object with type and nested target")
    func encodesBrowserShape() throws {
        let destination = RoutingDestination.browser(
            BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        )
        let json = try jsonObject(destination)
        #expect(json["type"] as? String == "browser")
        let target = try #require(json["target"] as? [String: Any])
        #expect(target["bundleID"] as? String == "com.google.Chrome")
        #expect(target["profileID"] as? String == "Profile 2")
        #expect(json["id"] == nil)
    }

    @Test("Encodes .alias as a tagged object with type and id")
    func encodesAliasShape() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let destination = RoutingDestination.alias(id)
        let json = try jsonObject(destination)
        #expect(json["type"] as? String == "alias")
        #expect(json["id"] as? String == "00000000-0000-0000-0000-0000000000B1")
        #expect(json["target"] == nil)
    }

    @Test("Round-trips .browser")
    func roundTripsBrowser() throws {
        let destination = RoutingDestination.browser(
            BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)
        )
        #expect(try roundTrip(destination) == destination)
    }

    @Test("Round-trips .alias")
    func roundTripsAlias() throws {
        let destination = RoutingDestination.alias(UUID())
        #expect(try roundTrip(destination) == destination)
    }

    @Test("Decodes a known .browser on-disk shape")
    func decodesBrowserShape() throws {
        let jsonString = """
        {
            "type": "browser",
            "target": { "bundleID": "com.google.Chrome", "profileID": "Profile 1" }
        }
        """
        let decoded = try JSONDecoder().decode(
            RoutingDestination.self,
            from: Data(jsonString.utf8)
        )
        #expect(decoded == .browser(BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")))
    }

    @Test("Decodes a known .alias on-disk shape")
    func decodesAliasShape() throws {
        let jsonString = """
        { "type": "alias", "id": "00000000-0000-0000-0000-0000000000B2" }
        """
        let decoded = try JSONDecoder().decode(
            RoutingDestination.self,
            from: Data(jsonString.utf8)
        )
        #expect(decoded == .alias(UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!))
    }

    @Test("A legacy bare BrowserTarget JSON (no type key) fails to decode")
    func legacyBareTargetFailsToDecode() {
        let jsonString = """
        { "bundleID": "com.google.Chrome", "profileID": "Profile 1" }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                RoutingDestination.self,
                from: Data(jsonString.utf8)
            )
        }
    }

    @Test("An unknown `type` discriminator value fails to decode")
    func unknownTypeFailsToDecode() {
        // Mirrors FallbackPolicy's unknownDiscriminatorThrows: an unrecognized
        // discriminator must throw, not silently produce a value. This pins the
        // contract FallbackPolicy's `try?`-first migration decode relies on.
        let jsonString = """
        { "type": "bogus", "id": "00000000-0000-0000-0000-0000000000B3" }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                RoutingDestination.self,
                from: Data(jsonString.utf8)
            )
        }
    }

    @Test("resolved(in:) returns the target for .browser")
    func resolvesBrowser() {
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        let destination = RoutingDestination.browser(target)
        #expect(destination.resolved(in: []) == target)
    }

    @Test("resolved(in:) returns the looked-up target for a known .alias")
    func resolvesKnownAlias() {
        let id = UUID()
        let target = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)
        let aliases = [ProfileAlias(id: id, name: "Work", target: target)]
        let destination = RoutingDestination.alias(id)
        #expect(destination.resolved(in: aliases) == target)
    }

    @Test("resolved(in:) returns nil for a dangling .alias")
    func resolvesDanglingAliasToNil() {
        let aliases = [
            ProfileAlias(
                id: UUID(),
                name: "Work",
                target: BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)
            )
        ]
        let destination = RoutingDestination.alias(UUID())
        #expect(destination.resolved(in: aliases) == nil)
    }
}
