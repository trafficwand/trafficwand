import Foundation
import Testing
@testable import TrafficWandCore

@Suite("FileConfigStore")
struct FileConfigStoreTests {
    /// Creates a unique, empty temporary directory for a single test and returns
    /// its URL. The directory is the caller's responsibility to clean up.
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileConfigStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Removes a temporary directory, first restoring write permissions so a
    /// read-only directory left over from a failure test can still be deleted.
    private func cleanUp(_ directory: URL) {
        // Restore permissions in case a test made the directory read-only.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleConfig() -> AppConfig {
        AppConfig(
            schemaVersion: 1,
            rules: [
                Rule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    pattern: "*.github.com",
                    target: BrowserTarget(bundleID: "com.google.Chrome", profileID: "Default"),
                    isEnabled: true
                ),
                Rule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    pattern: "*example.com",
                    target: BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "Personal"),
                    isEnabled: false
                )
            ],
            fallback: .defaultBrowser(BrowserTarget(bundleID: "com.apple.Safari", profileID: nil))
        )
    }

    @Test("save then load round-trips the config")
    func saveLoadRoundTrip() throws {
        let directory = try makeTempDirectory()
        defer { cleanUp(directory) }

        let store = FileConfigStore(directory: directory)
        let config = sampleConfig()
        try store.save(config)
        let loaded = try store.load()
        #expect(loaded == config)
    }

    @Test("save creates the target directory on a clean install (round-trips)")
    func saveCreatesMissingDirectory() throws {
        // Simulate a clean install: the store's directory does not exist yet (and
        // neither does an intermediate parent). `Data.write(.atomic)` does NOT
        // create directories, so save must create them itself or the first save
        // throws (NSCocoaErrorDomain 4) — the regression this test guards.
        let parent = try makeTempDirectory()
        defer { cleanUp(parent) }
        let directory = parent
            .appendingPathComponent("not-yet-created", isDirectory: true)
            .appendingPathComponent("TrafficWand", isDirectory: true)
        // Sanity: the directory really is absent before the first save.
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        let store = FileConfigStore(directory: directory)
        let config = sampleConfig()
        try store.save(config)
        let loaded = try store.load()
        #expect(loaded == config)
    }

    @Test("missing file returns AppConfig.default and does not throw")
    func missingFileReturnsDefault() throws {
        let directory = try makeTempDirectory()
        defer { cleanUp(directory) }

        let store = FileConfigStore(directory: directory)
        let loaded = try store.load()
        #expect(loaded == AppConfig.default)
        #expect(loaded.rules.isEmpty)
        #expect(loaded.fallback == .picker)
    }

    @Test("corrupt JSON surfaces a recoverable error")
    func corruptJSONThrowsRecoverableError() throws {
        let directory = try makeTempDirectory()
        defer { cleanUp(directory) }

        let store = FileConfigStore(directory: directory)
        let fileURL = directory.appendingPathComponent("config.json")
        try Data("this is not valid json {{{".utf8).write(to: fileURL)

        #expect {
            _ = try store.load()
        } throws: { error in
            guard let storeError = error as? ConfigStoreError,
                  case .corruptConfiguration = storeError else {
                return false
            }
            return true
        }
    }

    @Test("corrupt JSON load backs up the corrupt file")
    func corruptJSONBacksUpFile() throws {
        let directory = try makeTempDirectory()
        defer { cleanUp(directory) }

        let store = FileConfigStore(directory: directory)
        let fileURL = directory.appendingPathComponent("config.json")
        let garbage = "not valid json {{{"
        try Data(garbage.utf8).write(to: fileURL)

        #expect(throws: ConfigStoreError.self) {
            _ = try store.load()
        }

        // After a corrupt-load, the original file is moved aside so recovery can
        // proceed (write a fresh default on the next save) without losing the bad
        // data for inspection.
        let backupURL = directory.appendingPathComponent("config.json.corrupt")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        let backedUp = try String(contentsOf: backupURL, encoding: .utf8)
        #expect(backedUp == garbage)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("a failed save leaves the previously-saved file intact")
    func failedSaveLeavesPriorFileIntact() throws {
        let directory = try makeTempDirectory()
        defer { cleanUp(directory) }

        let store = FileConfigStore(directory: directory)

        // Save a known-good config first.
        let good = sampleConfig()
        try store.save(good)

        // Make the directory read-only so the atomic write (which creates a temp
        // file in the directory and renames it) cannot succeed.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )

        // Attempt to save a different config; it must fail.
        let mutated = AppConfig(schemaVersion: 1, rules: [], fallback: .lastUsed)
        #expect(throws: (any Error).self) {
            try store.save(mutated)
        }

        // Restore write permission so we can read/clean up, then assert the prior
        // file is still the original good config (atomic rename never happened).
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let loaded = try store.load()
        #expect(loaded == good)
    }

    @Test("saved JSON is pretty-printed with sorted keys")
    func savedJSONIsPrettyAndSorted() throws {
        let directory = try makeTempDirectory()
        defer { cleanUp(directory) }

        let store = FileConfigStore(directory: directory)
        try store.save(sampleConfig())

        let fileURL = directory.appendingPathComponent("config.json")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        // Pretty-printing introduces newlines and indentation.
        #expect(contents.contains("\n"))
        #expect(contents.contains("  "))
        // Sorted keys: within the rules array, "id" precedes "isEnabled".
        if let idIndex = contents.range(of: "\"id\""),
           let isEnabledIndex = contents.range(of: "\"isEnabled\"") {
            #expect(idIndex.lowerBound < isEnabledIndex.lowerBound)
        } else {
            Issue.record("expected both id and isEnabled keys in the output")
        }
    }

    @Test("save overwrites an existing file")
    func saveOverwritesExisting() throws {
        let directory = try makeTempDirectory()
        defer { cleanUp(directory) }

        let store = FileConfigStore(directory: directory)
        try store.save(sampleConfig())

        let replacement = AppConfig(schemaVersion: 1, rules: [], fallback: .picker)
        try store.save(replacement)
        let loaded = try store.load()
        #expect(loaded == replacement)
    }
}
