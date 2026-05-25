import Foundation
import Testing
@testable import TrafficWandCore

@Suite("ChromeProfileReader")
struct ChromeProfileReaderTests {
    @Test("valid Local State yields a BrowserProfile per info_cache entry")
    func validLocalStateParsesProfiles() throws {
        let directory = try FixtureLoader.materialize(group: "chrome")
        defer { FixtureLoader.cleanUp(directory) }

        let reader = ChromeProfileReader()
        let profiles = try reader.readProfiles(applicationSupportDirectory: directory)

        // Sorted by directory name: Default, Profile 1, Profile 2.
        #expect(profiles == [
            BrowserProfile(id: "Default", name: "Personal"),
            BrowserProfile(id: "Profile 1", name: "Work"),
            BrowserProfile(id: "Profile 2", name: "Side Project"),
        ])
    }

    @Test("the id is the profile directory name, name is the display name")
    func idIsDirectoryName() throws {
        let directory = try FixtureLoader.materialize(group: "chrome")
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try ChromeProfileReader().readProfiles(applicationSupportDirectory: directory)
        let work = try #require(profiles.first { $0.name == "Work" })
        #expect(work.id == "Profile 1")
    }

    @Test("missing Local State returns an empty array, not an error")
    func missingFileReturnsEmpty() throws {
        let directory = try FixtureLoader.emptyDirectory()
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try ChromeProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.isEmpty)
    }

    @Test("garbled JSON returns an empty array, never crashes")
    func garbledJSONReturnsEmpty() throws {
        let directory = try FixtureLoader.directory(
            withFile: "Local State",
            contents: "this is not json {{{ "
        )
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try ChromeProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.isEmpty)
    }

    @Test("empty file returns an empty array")
    func emptyFileReturnsEmpty() throws {
        let directory = try FixtureLoader.directory(withFile: "Local State", contents: "")
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try ChromeProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.isEmpty)
    }

    @Test("valid JSON without profile.info_cache returns an empty array")
    func missingInfoCacheReturnsEmpty() throws {
        let directory = try FixtureLoader.directory(
            withFile: "Local State",
            contents: #"{ "profile": { "last_used": "Default" } }"#
        )
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try ChromeProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.isEmpty)
    }

    @Test("an entry without a name falls back to the directory name")
    func missingNameFallsBackToDirectory() throws {
        let directory = try FixtureLoader.directory(
            withFile: "Local State",
            contents: #"{ "profile": { "info_cache": { "Default": {} } } }"#
        )
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try ChromeProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles == [BrowserProfile(id: "Default", name: "Default")])
    }
}
