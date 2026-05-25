import AppKit
import Foundation
import TrafficWandCore

/// Raw installed-application data for a single http(s) handler candidate.
///
/// This is the plain-data shape the App extracts from `NSWorkspace` (a bundle ID,
/// an app URL, a display name) and hands to the pure `BrowserMerger`. Keeping it a
/// value type lets the merge logic be unit-tested without `NSWorkspace`.
public struct BrowserCandidate: Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let appURL: URL

    public init(bundleID: String, name: String, appURL: URL) {
        self.bundleID = bundleID
        self.name = name
        self.appURL = appURL
    }
}

/// The **pure** merge helper that turns raw `BrowserCandidate`s into the Core
/// `[Browser]` list, attaching discovered profiles. No `NSWorkspace`, no global
/// filesystem assumptions — everything is injected, so this is fully unit-tested.
///
/// Behavior:
///  - Excludes TrafficWand itself (`selfBundleID`).
///  - Filters to **real browsers** by family (`BrowserFamily(bundleID:) != .other`):
///    a random app that merely claims to handle http is dropped.
///  - Does **not** filter by default-ness: a real non-default browser still shows.
///  - Attaches profiles per family via the injected `ProfileReading` (resolved by
///    `profileReaderForFamily`) and the per-family support path from `pathResolver`.
///    A missing support path or a throwing reader yields empty profiles.
///  - Returns browsers sorted by display name for deterministic UI ordering.
public enum BrowserMerger {

    /// Merges raw candidates into Core `Browser`s.
    ///
    /// - Parameters:
    ///   - candidates: Raw installed-app candidates (from `NSWorkspace` at runtime,
    ///     or stub data in tests).
    ///   - selfBundleID: TrafficWand's own bundle identifier, excluded from output.
    ///   - profileReaderForFamily: Supplies the `ProfileReading` for a family
    ///     (injected so tests stub it; the App wires Chrome/Firefox readers).
    ///   - pathResolver: Resolves a bundle ID's Application Support directory.
    /// - Returns: Allowlisted browsers with profiles attached, sorted by name.
    public static func merge(
        candidates: [BrowserCandidate],
        selfBundleID: String,
        profileReaderForFamily: (BrowserFamily) -> ProfileReading,
        pathResolver: ProfilePathResolving
    ) -> [Browser] {
        // De-duplicate by bundle ID (NSWorkspace can list copies), keeping the
        // first occurrence.
        var seen: Set<String> = []
        let browsers: [Browser] = candidates.compactMap { candidate in
            guard candidate.bundleID != selfBundleID else { return nil }
            let family = BrowserFamily(bundleID: candidate.bundleID)
            // The allowlist is derived from `BrowserFamily` (single source of
            // truth): any bundle ID in a known family (Chromium/Firefox/Safari) is
            // a real browser; `.other` is a non-browser http handler and is dropped.
            guard family != .other else { return nil }
            guard seen.insert(candidate.bundleID).inserted else { return nil }

            let profiles = discoverProfiles(
                bundleID: candidate.bundleID,
                family: family,
                profileReaderForFamily: profileReaderForFamily,
                pathResolver: pathResolver
            )

            return Browser(
                bundleID: candidate.bundleID,
                name: candidate.name,
                appURL: candidate.appURL,
                profiles: profiles
            )
        }

        return browsers.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Discovers profiles for one browser; degrades to `[]` on any missing support
    /// path or reader error (discovery must never take down routing).
    private static func discoverProfiles(
        bundleID: String,
        family: BrowserFamily,
        profileReaderForFamily: (BrowserFamily) -> ProfileReading,
        pathResolver: ProfilePathResolving
    ) -> [BrowserProfile] {
        guard let supportDir = pathResolver.applicationSupportDirectory(forBundleID: bundleID) else {
            return []
        }
        let reader = profileReaderForFamily(family)
        return (try? reader.readProfiles(applicationSupportDirectory: supportDir)) ?? []
    }
}

/// The thin `NSWorkspace` adapter that supplies installed browsers to the rest of
/// the app. It enumerates http(s) handlers via `NSWorkspace`, converts them to
/// plain `BrowserCandidate`s, then delegates all decision logic to `BrowserMerger`.
///
/// The single live, untestable line is the `NSWorkspace.urlsForApplications(toOpen:)`
/// call; everything else is the pure helper covered by unit tests.
public final class WorkspaceBrowserProvider {
    /// Sample https URL used only to enumerate candidate handlers.
    private static let sampleURL = URL(string: "https://example.com")!

    private let selfBundleID: String
    private let pathResolver: ProfilePathResolving

    /// - Parameters:
    ///   - selfBundleID: TrafficWand's own bundle ID (defaults to the running
    ///     bundle's identifier), excluded from results.
    ///   - pathResolver: Per-family support-path resolver (defaults to the real
    ///     `~/Library/Application Support`).
    public init(
        selfBundleID: String = Bundle.main.bundleIdentifier ?? "",
        pathResolver: ProfilePathResolving = ProfilePathResolver()
    ) {
        self.selfBundleID = selfBundleID
        self.pathResolver = pathResolver
    }

    /// Returns the installed, allowlisted browsers with profiles attached.
    public func installedBrowsers() -> [Browser] {
        let candidates = workspaceCandidates()
        return BrowserMerger.merge(
            candidates: candidates,
            selfBundleID: selfBundleID,
            profileReaderForFamily: Self.profileReader(for:),
            pathResolver: pathResolver
        )
    }

    /// The live `NSWorkspace` enumeration, converted to plain data. This is the
    /// only part not exercised by unit tests (covered by manual verification).
    private func workspaceCandidates() -> [BrowserCandidate] {
        NSWorkspace.shared.urlsForApplications(toOpen: Self.sampleURL).compactMap { appURL in
            guard let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier else {
                return nil
            }
            let name = FileManager.default.displayName(atPath: appURL.path)
            return BrowserCandidate(bundleID: bundleID, name: name, appURL: appURL)
        }
    }

    /// Maps a family to its concrete `ProfileReading`. Safari/other have no
    /// command-line profiles, so a no-op reader is returned.
    private static func profileReader(for family: BrowserFamily) -> ProfileReading {
        switch family {
        case .chromium:
            return ChromeProfileReader()
        case .firefox:
            return FirefoxProfileReader()
        case .safari, .other:
            return NoProfilesReader()
        }
    }
}

/// A `ProfileReading` for families with no command-line profile support; always
/// returns `[]`.
private struct NoProfilesReader: ProfileReading {
    func readProfiles(applicationSupportDirectory: URL) throws -> [BrowserProfile] { [] }
}
