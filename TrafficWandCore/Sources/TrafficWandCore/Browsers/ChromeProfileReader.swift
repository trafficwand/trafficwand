import Foundation

/// Reads Chromium-family profiles from the `Local State` JSON file.
///
/// Chromium browsers (Chrome, Edge, Brave, Vivaldi, Chromium, …) store a
/// `Local State` file at the root of their Application Support directory. Its
/// `profile.info_cache` object maps each profile's **directory name** (e.g.
/// `"Default"`, `"Profile 1"`) to metadata including a display `name`. Each entry
/// becomes a `BrowserProfile` whose `id` is the directory name (the value
/// `--profile-directory=` expects) and whose `name` is the display name.
///
/// Behavior:
/// - Missing `Local State` → `[]`.
/// - Present but unparseable / wrong shape → `[]` (best effort, never crashes).
/// - Profiles are returned sorted by directory name for deterministic ordering.
public struct ChromeProfileReader: ProfileReading {
    /// Name of the Chromium state file inside the Application Support directory.
    private static let fileName = "Local State"

    public init() {}

    public func readProfiles(applicationSupportDirectory: URL) throws -> [BrowserProfile] {
        let url = applicationSupportDirectory.appendingPathComponent(
            Self.fileName,
            isDirectory: false
        )

        // Missing file is not an error: the browser may be installed without any
        // profile state yet, or not installed at all.
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return Self.parse(data)
    }

    /// Parses `Local State` JSON contents into profiles. Pure: input is the raw
    /// file data. Any structural surprise resolves to `[]`.
    static func parse(_ data: Data) -> [BrowserProfile] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let infoCache = profile["info_cache"] as? [String: Any]
        else {
            return []
        }

        var profiles: [BrowserProfile] = []
        for (directoryName, rawEntry) in infoCache {
            guard let entry = rawEntry as? [String: Any] else { continue }
            // Prefer the display name; fall back to the directory name when the
            // display name is missing or blank so a profile is never nameless.
            let displayName: String
            if let name = entry["name"] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayName = name
            } else {
                displayName = directoryName
            }
            profiles.append(BrowserProfile(id: directoryName, name: displayName))
        }

        // Deterministic ordering by directory name (info_cache is an unordered map).
        return profiles.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }
}
