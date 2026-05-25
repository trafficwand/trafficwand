import Foundation

/// Reads Firefox profiles from `profiles.ini`, honoring the modern
/// `installs.ini` default-profile interaction.
///
/// Firefox stores its profile registry in `profiles.ini` at the root of its
/// Application Support directory. Each `[ProfileN]` section carries a `Name=`,
/// `Path=`, `IsRelative=` and (legacy) `Default=`. Modern Firefox additionally
/// writes `installs.ini`, whose `[<InstallHash>]` sections name a `Default=`
/// **path** per install — the per-install default that takes precedence over the
/// legacy `[ProfileN] Default=1` marker.
///
/// Each discovered profile becomes a `BrowserProfile`. Per the routing contract,
/// the launch flag is `-P <name>`, so the `BrowserProfile.id` is the profile's
/// **`Name`** (not its path), and `name` is the same display name.
///
/// Behavior:
/// - Missing `profiles.ini` → `[]`.
/// - Garbled / no profile sections → `[]` (best effort, never crashes).
/// - A single implicit profile (one `[ProfileN]`) is returned on its own.
/// - When `installs.ini` designates default profile paths, those defaults are
///   honored: the matching profiles are surfaced first (deterministic ordering),
///   but **all** named profiles are returned so the user can still pick any.
public struct FirefoxProfileReader: ProfileReading {
    /// The Firefox profile registry file.
    private static let profilesFileName = "profiles.ini"
    /// The Firefox per-install defaults file (modern Firefox).
    private static let installsFileName = "installs.ini"

    public init() {}

    public func readProfiles(applicationSupportDirectory: URL) throws -> [BrowserProfile] {
        let profilesURL = applicationSupportDirectory.appendingPathComponent(
            Self.profilesFileName,
            isDirectory: false
        )

        // Missing registry is not an error.
        guard FileManager.default.fileExists(atPath: profilesURL.path) else {
            return []
        }

        let profilesContents = (try? String(contentsOf: profilesURL, encoding: .utf8)) ?? ""

        let installsURL = applicationSupportDirectory.appendingPathComponent(
            Self.installsFileName,
            isDirectory: false
        )
        let installsContents: String?
        if FileManager.default.fileExists(atPath: installsURL.path) {
            installsContents = try? String(contentsOf: installsURL, encoding: .utf8)
        } else {
            installsContents = nil
        }

        return Self.parse(profilesContents: profilesContents, installsContents: installsContents)
    }

    /// Parses `profiles.ini` (and optional `installs.ini`) contents into profiles.
    /// Pure: inputs are file contents. Any structural surprise resolves to `[]`.
    static func parse(profilesContents: String, installsContents: String?) -> [BrowserProfile] {
        let profileSections = INIParser.parse(profilesContents)
            .filter { $0.name.lowercased().hasPrefix("profile") }

        // Collect named profiles. A profile without a Name= is unusable for `-P`,
        // so it is skipped.
        struct ParsedProfile {
            let name: String
            let path: String?
            let isLegacyDefault: Bool
        }

        var parsed: [ParsedProfile] = []
        for section in profileSections {
            guard let name = section["Name"],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let path = section["Path"]
            let isLegacyDefault = (section["Default"] ?? "0") == "1"
            parsed.append(ParsedProfile(name: name, path: path, isLegacyDefault: isLegacyDefault))
        }

        guard !parsed.isEmpty else { return [] }

        // Determine which profile *paths* are designated defaults by installs.ini.
        var defaultPaths: Set<String> = []
        if let installsContents {
            for section in INIParser.parse(installsContents) {
                if let defaultPath = section["Default"],
                   !defaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    defaultPaths.insert(defaultPath)
                }
            }
        }

        // Order: installs.ini-designated defaults first, then legacy defaults,
        // then the rest — each group sorted by name for determinism. All profiles
        // are surfaced regardless of default status.
        func priority(_ profile: ParsedProfile) -> Int {
            if let path = profile.path, defaultPaths.contains(path) {
                return 0
            }
            if profile.isLegacyDefault {
                return 1
            }
            return 2
        }

        let ordered = parsed.sorted { lhs, rhs in
            let lp = priority(lhs)
            let rp = priority(rhs)
            if lp != rp { return lp < rp }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return ordered.map { BrowserProfile(id: $0.name, name: $0.name) }
    }
}

/// A minimal INI parser sufficient for Firefox `profiles.ini` / `installs.ini`.
///
/// Foundation has no INI parser, so this is a small hand-rolled one. It supports:
/// - `[Section]` headers,
/// - `key=value` pairs (value may contain `=`; first `=` splits),
/// - `;` and `#` line comments,
/// - blank lines,
/// - CRLF or LF line endings.
///
/// Keys before any section header are ignored (Firefox files always start with a
/// section). Duplicate keys within a section take the last value.
enum INIParser {
    /// One parsed section: its header name plus its key/value pairs.
    struct Section {
        let name: String
        private var values: [String: String]

        init(name: String, values: [String: String]) {
            self.name = name
            self.values = values
        }

        /// Case-insensitive-keyless lookup (Firefox keys are stable-cased, so an
        /// exact match suffices).
        subscript(_ key: String) -> String? { values[key] }
    }

    static func parse(_ contents: String) -> [Section] {
        var sections: [Section] = []
        var currentName: String?
        var currentValues: [String: String] = [:]

        func flush() {
            if let name = currentName {
                sections.append(Section(name: name, values: currentValues))
            }
            currentValues = [:]
        }

        let lines = contents.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                currentName = String(line.dropFirst().dropLast())
                continue
            }
            guard currentName != nil,
                  let equalsIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[line.startIndex..<equalsIndex])
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                currentValues[key] = value
            }
        }
        flush()
        return sections
    }
}
