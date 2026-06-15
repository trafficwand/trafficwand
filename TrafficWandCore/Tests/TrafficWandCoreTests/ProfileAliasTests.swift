import Foundation
import Testing
@testable import TrafficWandCore

@Suite("ProfileAlias")
struct ProfileAliasTests {
    private func roundTrip(_ alias: ProfileAlias) throws -> ProfileAlias {
        let data = try JSONEncoder().encode(alias)
        return try JSONDecoder().decode(ProfileAlias.self, from: data)
    }

    @Test("Round-trips a ProfileAlias")
    func roundTrip() throws {
        let alias = ProfileAlias(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        )
        let decoded = try roundTrip(alias)
        #expect(decoded == alias)
    }

    @Test("Encodes the stable coding keys id, name, target")
    func stableCodingKeys() throws {
        let alias = ProfileAlias(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
            name: "Work",
            target: BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)
        )
        let data = try JSONEncoder().encode(alias)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["id"] as? String == "00000000-0000-0000-0000-0000000000A2")
        #expect(json["name"] as? String == "Work")
        #expect(json["target"] != nil)
        // profileID is nil so the nested target should omit it.
        let target = try #require(json["target"] as? [String: Any])
        #expect(target["bundleID"] as? String == "org.mozilla.firefox")
        #expect(target["profileID"] == nil)
    }

    @Test("Decodes a known on-disk shape")
    func decodesKnownShape() throws {
        let jsonString = """
        {
            "id": "00000000-0000-0000-0000-0000000000A3",
            "name": "Personal",
            "target": { "bundleID": "com.google.Chrome", "profileID": "Profile 1" }
        }
        """
        let decoded = try JSONDecoder().decode(
            ProfileAlias.self,
            from: Data(jsonString.utf8)
        )
        #expect(decoded.id == UUID(uuidString: "00000000-0000-0000-0000-0000000000A3"))
        #expect(decoded.name == "Personal")
        #expect(decoded.target == BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1"))
    }

    @Test("Equatable distinguishes by id, name, and target")
    func equatableIdentity() {
        let id = UUID()
        let base = ProfileAlias(
            id: id,
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        )
        #expect(base == ProfileAlias(
            id: id,
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        ))
        // Different id.
        #expect(base != ProfileAlias(
            id: UUID(),
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        ))
        // Different name.
        #expect(base != ProfileAlias(
            id: id,
            name: "Work",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        ))
        // Different target.
        #expect(base != ProfileAlias(
            id: id,
            name: "Personal",
            target: BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)
        ))
    }

    @Test("Hashable: equal values share a hash; different ids differ")
    func hashableIdentity() {
        let id = UUID()
        let a = ProfileAlias(
            id: id,
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        )
        let b = ProfileAlias(
            id: id,
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        )
        var set = Set<ProfileAlias>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    @Test("Default memberwise init generates a fresh UUID")
    func defaultInitGeneratesID() {
        let a = ProfileAlias(
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: nil)
        )
        let b = ProfileAlias(
            name: "Personal",
            target: BrowserTarget(bundleID: "com.google.Chrome", profileID: nil)
        )
        #expect(a.id != b.id)
    }
}
