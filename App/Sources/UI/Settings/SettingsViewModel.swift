import Foundation
import Observation
import TrafficWandCore
import os

/// The observable state and mutation logic backing the Settings UI.
///
/// This is the fully unit-testable heart of Settings. It depends **only** on the
/// Core `ConfigStore` protocol and the App-side `InstalledBrowsersProviding` seam
/// (both injected) — it makes no `NSWorkspace`/AppKit calls of its own. SwiftUI
/// views observe its `@Observable` state and call its mutation methods.
///
/// Persistence contract (Acceptance Criterion #5): **every** mutation — adding,
/// editing, deleting, reordering, or toggling a rule, and changing the fallback
/// policy — both updates the in-memory `AppConfig` and persists it via
/// `ConfigStore.save`, so changes survive relaunch. The in-memory state is kept in
/// sync with what is persisted so a later `load()` (or relaunch) is consistent.
@MainActor
@Observable
final class SettingsViewModel {
    private static let logger = Logger(subsystem: AppIdentity.subsystem, category: "settings")

    /// The ordered routing rules currently shown in the UI (first match wins).
    private(set) var rules: [Rule] = []

    /// The installed browsers offered in rule editors / fallback selection.
    private(set) var browsers: [Browser] = []

    /// The fallback policy applied to links matching no enabled rule.
    private(set) var fallback: FallbackPolicy = .picker

    /// The reusable profile aliases shown in the Aliases tab and offered as
    /// rule/fallback destinations.
    private(set) var aliases: [ProfileAlias] = []

    /// The schema version of the most recently loaded config. `persist()` stamps
    /// `max(this, AppConfig.currentSchemaVersion)` so a load-then-save always
    /// migrates a legacy document forward to the current schema (matching the
    /// "new writes always use schema v2" contract documented on `AppConfig`),
    /// while never downgrading a document written by a newer build.
    private var loadedSchemaVersion: Int = AppConfig.currentSchemaVersion

    private let configStore: ConfigStore
    private let browserProvider: InstalledBrowsersProviding
    private let updater: UpdaterControlling

    /// Whether Sparkle automatically checks for updates in the background.
    ///
    /// Bound to the "Automatically check for updates" toggle in `GeneralSettingsView`;
    /// get/set forward straight through to the injected `UpdaterControlling` seam, so
    /// the toggle reflects and controls the real updater preference.
    ///
    /// Deliberate design note: this update seam lives in the *view model* rather than
    /// in the view (the way `DefaultBrowserManager` is held by `GeneralSettingsView`).
    /// `SettingsViewModelTests` already exists and `UpdaterControlling` is a pure
    /// `@MainActor` protocol, so threading it through the view model keeps the toggle's
    /// read/write behavior unit-testable with a `MockUpdater`, which the in-view
    /// `DefaultBrowserManager` precedent does not afford.
    ///
    /// Not reactive: this is a computed pass-through to a non-`@Observable` seam, so
    /// SwiftUI won't repaint the toggle if Sparkle flips the preference out of band.
    /// Acceptable here — the toggle is user-driven and the value is read fresh each
    /// time Settings opens; do not add an observation bridge for a single toggle.
    var automaticUpdatesEnabled: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// - Parameters:
    ///   - configStore: Source of the persisted `AppConfig`; every mutation saves
    ///     back through it.
    ///   - browserProvider: Supplies the installed browsers (with profiles) shown
    ///     in the editors. Injected so tests pass a stub list.
    ///   - updater: The in-app update seam backing the "Automatically check for
    ///     updates" toggle. Injected so tests pass a `MockUpdater`.
    init(
        configStore: ConfigStore,
        browserProvider: InstalledBrowsersProviding,
        updater: UpdaterControlling
    ) {
        self.configStore = configStore
        self.browserProvider = browserProvider
        self.updater = updater
    }

    /// Loads the persisted configuration and the installed browser list.
    ///
    /// A corrupt/unreadable config degrades to `AppConfig.default` so the Settings
    /// window always opens to a usable state rather than failing.
    func load() {
        let config = (try? configStore.load()) ?? .default
        loadedSchemaVersion = config.schemaVersion
        rules = config.rules
        fallback = config.fallback
        aliases = config.aliases
        browsers = browserProvider.installedBrowsers()
    }

    // MARK: - Rule mutations

    /// Appends a new rule to the end of the list and persists.
    func addRule(_ rule: Rule) {
        rules.append(rule)
        persist()
    }

    /// Replaces the rule with the same `id` with `rule` and persists.
    ///
    /// No-op (and no save) if no rule with that id exists.
    func updateRule(_ rule: Rule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
    }

    /// Sets the `isEnabled` flag of a rule (by id) and persists.
    func setRule(_ rule: Rule, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled = enabled
        persist()
    }

    /// Deletes the rule with `id` and persists.
    ///
    /// No-op (and no save) if no rule with that id exists. Mirrors `updateRule`'s
    /// by-id + no-op-if-absent shape. This is the single delete path for rules —
    /// the rule editor's "Delete Rule" button routes through here.
    func deleteRule(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules.remove(at: index)
        persist()
    }

    /// Moves rules within the ordered list and persists the new order.
    ///
    /// `source`/`destination` follow SwiftUI `onMove` semantics.
    func moveRules(fromOffsets source: IndexSet, toOffset destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Fallback policy

    /// Changes the fallback policy and persists.
    func setFallback(_ policy: FallbackPolicy) {
        fallback = policy
        persist()
    }

    // MARK: - Alias mutations

    /// Appends a new alias to the list and persists.
    func addAlias(_ alias: ProfileAlias) {
        aliases.append(alias)
        persist()
    }

    /// Replaces the alias with the same `id` with `alias` and persists.
    ///
    /// No-op (and no save) if no alias with that id exists. Because rules/fallback
    /// reference aliases by `id`, editing an alias's `name`/`target` re-points every
    /// referencing rule at once — the whole point of aliases.
    func updateAlias(_ alias: ProfileAlias) {
        guard let index = aliases.firstIndex(where: { $0.id == alias.id }) else { return }
        aliases[index] = alias
        persist()
    }

    /// Deletes the alias with `id` and persists — **unless** it is still referenced
    /// by a rule or the fallback policy, in which case this is a no-op (no state
    /// change, no save).
    ///
    /// Referential integrity is enforced in the UI: the Aliases view calls
    /// `referencingRules(aliasID:)` / `isFallbackReferencing(aliasID:)` to block the
    /// delete and explain why. Core stays defensive regardless (a dangling reference
    /// resolves to the picker), but blocking here prevents accidental orphaning.
    func deleteAlias(id: UUID) {
        guard !isReferenced(id) else { return }
        guard let index = aliases.firstIndex(where: { $0.id == id }) else { return }
        aliases.remove(at: index)
        persist()
    }

    /// The alias with `id`, or `nil` if no such alias exists.
    ///
    /// Used by the master-detail Aliases tab to resolve a `selectedAliasID`
    /// (held in view `@State`) to the live alias the detail editor edits, so the
    /// editor always reflects the current persisted value (e.g. after another
    /// edit re-points it). Kept on the view model to give the lookup a unit-test
    /// seam and to keep the view declarative.
    func alias(withID id: UUID) -> ProfileAlias? {
        aliases.first { $0.id == id }
    }

    // MARK: - Referential integrity

    /// The rules whose destination references the alias with `aliasID`.
    func referencingRules(aliasID: UUID) -> [Rule] {
        rules.filter { $0.destination == .alias(aliasID) }
    }

    /// Whether the fallback policy's default destination references `aliasID`.
    func isFallbackReferencing(aliasID: UUID) -> Bool {
        if case .defaultBrowser(.alias(let id)) = fallback {
            return id == aliasID
        }
        return false
    }

    /// Whether any rule or the fallback policy references the alias with `aliasID`.
    func isReferenced(_ aliasID: UUID) -> Bool {
        !referencingRules(aliasID: aliasID).isEmpty || isFallbackReferencing(aliasID: aliasID)
    }

    // MARK: - Destination display

    /// A user-facing label for a routing destination, resolved against the current
    /// aliases.
    ///
    /// - `.alias` → the alias's `name`, or "(deleted alias)" if the reference is
    ///   dangling (the alias was removed by a hand-edit; the router routes such a
    ///   link to the picker).
    /// - `.browser` → the browser's display name, with " — <profile>" appended when
    ///   the target names a profile; falls back to the raw bundle ID if the browser
    ///   is not installed.
    ///
    /// Kept on the view model (not the view) so it has a unit-test seam, consistent
    /// with how the fallback-mode logic is tested. `RulesListView` consumes this.
    func destinationLabel(for destination: RoutingDestination) -> String {
        switch destination {
        case .alias(let id):
            return aliases.first { $0.id == id }?.name ?? "(deleted alias)"
        case .browser(let target):
            return browserLabel(for: target)
        }
    }

    /// Display label for a concrete browser target: browser name + optional profile.
    func browserLabel(for target: BrowserTarget) -> String {
        let name = browsers.first { $0.bundleID == target.bundleID }?.name ?? target.bundleID
        if let profileID = target.profileID {
            let profileName = browsers
                .first { $0.bundleID == target.bundleID }?
                .profiles.first { $0.id == profileID }?
                .name ?? profileID
            return "\(name) — \(profileName)"
        }
        return name
    }

    // MARK: - Persistence

    /// Persists the current in-memory state as an `AppConfig` via `ConfigStore`.
    ///
    /// A failed save is logged but does not mutate the in-memory state further: the
    /// UI already reflects the user's intent, and `FileConfigStore`'s atomic write
    /// leaves any previously-saved file intact on failure.
    private func persist() {
        let config = AppConfig(
            // Migrate a legacy document forward on save, but never downgrade one
            // written by a newer build than this one.
            schemaVersion: max(loadedSchemaVersion, AppConfig.currentSchemaVersion),
            aliases: aliases,
            rules: rules,
            fallback: fallback
        )
        do {
            try configStore.save(config)
        } catch {
            Self.logger.error(
                "Failed to persist settings: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
