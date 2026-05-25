import Foundation

/// Test helper that materializes profile-discovery fixtures into hermetic temp
/// directories.
///
/// Fixtures live alongside the tests in `Fixtures/<group>/` as real files. To
/// keep tests independent of SPM resource bundling, the loader resolves the
/// `Fixtures` directory relative to this source file (`#filePath`) and copies a
/// fixture group's files into a fresh UUID temp directory per call. Tests point
/// the readers at that temp directory and clean it up afterwards.
enum FixtureLoader {
    /// The on-disk `Fixtures` directory next to the test sources.
    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    /// Copies the named fixture group's files into a fresh temp directory and
    /// returns the temp directory URL.
    ///
    /// - Parameter group: A subdirectory of `Fixtures` (e.g. `"chrome"`).
    /// - Returns: A unique temp directory containing copies of the group's files.
    static func materialize(group: String) throws -> URL {
        let source = fixturesDirectory.appendingPathComponent(group, isDirectory: true)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrafficWandFixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let contents = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for file in contents {
            let target = destination.appendingPathComponent(file.lastPathComponent, isDirectory: false)
            try FileManager.default.copyItem(at: file, to: target)
        }
        return destination
    }

    /// Creates an empty unique temp directory (for missing-file scenarios).
    static func emptyDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrafficWandFixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `contents` into a fresh temp directory as `fileName` and returns the
    /// directory URL (for garbled/custom-content scenarios).
    static func directory(withFile fileName: String, contents: String) throws -> URL {
        let directory = try emptyDirectory()
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try Data(contents.utf8).write(to: fileURL)
        return directory
    }

    /// Removes a temp directory created by this loader.
    static func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
