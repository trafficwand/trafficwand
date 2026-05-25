import Foundation

/// A `ConfigStore` that persists `AppConfig` as pretty-printed JSON in a single
/// `config.json` inside an injected directory.
///
/// Design notes (locked during planning):
/// - **Location is injected.** In production the App passes
///   `~/Library/Application Support/TrafficWand`; tests pass a temp directory.
///   This keeps the store pure (Foundation only) and side-effect-contained.
/// - **Atomic writes.** `save` writes with `Data.write(options: .atomic)`, which
///   writes to a sibling temp file and renames it into place. The rename never
///   happens if the write fails, so a failed save leaves the previously-saved
///   file intact.
/// - **Stable output.** JSON is `.prettyPrinted` and `.sortedKeys` so the
///   on-disk form is human-diffable and deterministic.
/// - **Missing file → default.** `load` returns `AppConfig.default` when no file
///   exists rather than throwing.
/// - **Corrupt file → recoverable.** A file that fails to decode is moved aside
///   to `config.json.corrupt` and `ConfigStoreError.corruptConfiguration` is
///   thrown, so callers can reset to defaults without silently losing the bad
///   data.
public struct FileConfigStore: ConfigStore {
    /// The directory that holds `config.json`.
    public let directory: URL

    /// File name for the persisted configuration.
    private static let fileName = "config.json"
    /// Suffix appended when a corrupt configuration is backed up aside.
    private static let corruptSuffix = ".corrupt"

    public init(directory: URL) {
        self.directory = directory
    }

    /// The full path to the configuration file.
    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// The path used to back up a corrupt configuration file.
    private var backupURL: URL {
        directory.appendingPathComponent(Self.fileName + Self.corruptSuffix, isDirectory: false)
    }

    public func load() throws -> AppConfig {
        let url = fileURL

        // Missing file is not an error: fall back to the built-in default.
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppConfig.default
        }

        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            // Corrupt configuration: move it aside (best effort) so recovery can
            // proceed, then surface a recoverable error.
            backUpCorruptFile(at: url)
            throw ConfigStoreError.corruptConfiguration
        }
    }

    public func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        // Atomic write: writes to a temp sibling and renames into place. On
        // failure the rename never happens, leaving any prior file intact.
        try data.write(to: fileURL, options: .atomic)
    }

    /// Moves a corrupt configuration file aside, replacing any prior backup.
    /// Best effort: failures here must not mask the recoverable decode error.
    private func backUpCorruptFile(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.moveItem(at: url, to: backupURL)
    }
}
