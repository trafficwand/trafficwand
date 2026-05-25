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

    /// The current schema version carried through every save (preserved from the
    /// loaded config so a save never silently downgrades the document).
    private var schemaVersion: Int = AppConfig.currentSchemaVersion

    private let configStore: ConfigStore
    private let browserProvider: InstalledBrowsersProviding

    /// - Parameters:
    ///   - configStore: Source of the persisted `AppConfig`; every mutation saves
    ///     back through it.
    ///   - browserProvider: Supplies the installed browsers (with profiles) shown
    ///     in the editors. Injected so tests pass a stub list.
    init(configStore: ConfigStore, browserProvider: InstalledBrowsersProviding) {
        self.configStore = configStore
        self.browserProvider = browserProvider
    }

    /// Loads the persisted configuration and the installed browser list.
    ///
    /// A corrupt/unreadable config degrades to `AppConfig.default` so the Settings
    /// window always opens to a usable state rather than failing.
    func load() {
        let config = (try? configStore.load()) ?? .default
        schemaVersion = config.schemaVersion
        rules = config.rules
        fallback = config.fallback
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

    /// Deletes the rules at `offsets` and persists.
    func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
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

    // MARK: - Persistence

    /// Persists the current in-memory state as an `AppConfig` via `ConfigStore`.
    ///
    /// A failed save is logged but does not mutate the in-memory state further: the
    /// UI already reflects the user's intent, and `FileConfigStore`'s atomic write
    /// leaves any previously-saved file intact on failure.
    private func persist() {
        let config = AppConfig(
            schemaVersion: schemaVersion,
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
