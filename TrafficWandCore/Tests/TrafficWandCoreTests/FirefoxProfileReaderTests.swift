import Foundation
import Testing
@testable import TrafficWandCore

@Suite("FirefoxProfileReader")
struct FirefoxProfileReaderTests {
    @Test("multi-profile profiles.ini yields all profiles, id = profile name")
    func multiProfileParsesAll() throws {
        let directory = try FixtureLoader.materialize(group: "firefox-multi")
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)

        // All three named profiles are surfaced; id == name (the `-P <name>` value).
        let names = Set(profiles.map(\.id))
        #expect(names == ["Personal", "Work", "Archive"])
        for profile in profiles {
            #expect(profile.id == profile.name)
        }
    }

    @Test("installs.ini-designated default profiles are ordered first")
    func installsIniDefaultsComeFirst() throws {
        let directory = try FixtureLoader.materialize(group: "firefox-multi")
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)

        // installs.ini designates Profiles/xyz789.personal (Personal) and
        // Profiles/abc123.work (Work) as install defaults; Archive is not. So the
        // two install-defaults sort ahead of Archive, which lands last.
        #expect(profiles.last?.id == "Archive")
        // The two install-defaults sort ahead of Archive, ordered by name within
        // the group (Personal before Work). Assert the actual order, not a Set.
        #expect(profiles.prefix(2).map(\.id) == ["Personal", "Work"])
    }

    @Test("single implicit profile is returned on its own")
    func singleImplicitProfile() throws {
        let directory = try FixtureLoader.materialize(group: "firefox-single")
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles == [BrowserProfile(id: "default", name: "default")])
    }

    @Test("missing profiles.ini returns an empty array, not an error")
    func missingFileReturnsEmpty() throws {
        let directory = try FixtureLoader.emptyDirectory()
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.isEmpty)
    }

    @Test("garbled profiles.ini returns an empty array")
    func garbledFileReturnsEmpty() throws {
        let directory = try FixtureLoader.directory(
            withFile: "profiles.ini",
            contents: "%%% not an ini file ((( no sections no keys"
        )
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.isEmpty)
    }

    @Test("profile section without a Name is skipped")
    func profileWithoutNameSkipped() throws {
        let ini = """
        [Profile0]
        IsRelative=1
        Path=Profiles/anon.default

        [General]
        StartWithLastProfile=1
        """
        let directory = try FixtureLoader.directory(withFile: "profiles.ini", contents: ini)
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.isEmpty)
    }

    @Test("legacy Default=1 marker orders that profile ahead when no installs.ini")
    func legacyDefaultOrdering() throws {
        let ini = """
        [Profile0]
        Name=Personal
        IsRelative=1
        Path=Profiles/p0.personal

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/p1.work
        Default=1

        [General]
        StartWithLastProfile=1
        """
        let directory = try FixtureLoader.directory(withFile: "profiles.ini", contents: ini)
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles.first?.id == "Work")
        #expect(Set(profiles.map(\.id)) == ["Personal", "Work"])
    }

    // MARK: - INI parser edge cases

    @Test("INI comments (; and #) and keys before any section are ignored")
    func iniIgnoresCommentsAndPreSectionKeys() throws {
        let ini = """
        ; a leading comment
        # another comment style
        StrayKey=ignored before any section
        [Profile0]
        ; inline-style comment line
        Name=Personal
        IsRelative=1
        Path=Profiles/p0.personal
        # trailing comment
        """
        let directory = try FixtureLoader.directory(withFile: "profiles.ini", contents: ini)
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        // The pre-section StrayKey is not attributed to any profile, and comments
        // are skipped, so exactly one named profile is surfaced.
        #expect(profiles == [BrowserProfile(id: "Personal", name: "Personal")])
    }

    @Test("A value containing '=' is split on the first '=' only")
    func iniValueWithEqualsSplitsOnFirst() throws {
        // The Name value itself contains '='; only the first '=' separates key and
        // value, so the full "A=B=C" is preserved as the profile name/id.
        let ini = """
        [Profile0]
        Name=A=B=C
        IsRelative=1
        Path=Profiles/p0.weird
        """
        let directory = try FixtureLoader.directory(withFile: "profiles.ini", contents: ini)
        defer { FixtureLoader.cleanUp(directory) }

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        #expect(profiles == [BrowserProfile(id: "A=B=C", name: "A=B=C")])
    }

    @Test("installs.ini default overrides legacy Default marker for ordering")
    func installsOverridesLegacyDefault() throws {
        let profilesIni = """
        [Profile0]
        Name=Personal
        IsRelative=1
        Path=Profiles/p0.personal

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/p1.work
        Default=1
        """
        let installsIni = """
        [ABC123]
        Default=Profiles/p0.personal
        Locked=1
        """
        let directory = try FixtureLoader.emptyDirectory()
        defer { FixtureLoader.cleanUp(directory) }
        try Data(profilesIni.utf8).write(
            to: directory.appendingPathComponent("profiles.ini")
        )
        try Data(installsIni.utf8).write(
            to: directory.appendingPathComponent("installs.ini")
        )

        let profiles = try FirefoxProfileReader().readProfiles(applicationSupportDirectory: directory)
        // installs.ini elevates Personal above the legacy-default Work.
        #expect(profiles.first?.id == "Personal")
    }
}
