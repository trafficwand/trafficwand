import Foundation
import TrafficWandCore
import os

/// Persists a "remembered" routing choice as a config rule.
///
/// A narrow App-side seam over `ConfigRuleStore` so the picker/controller can
/// remember a choice without reaching for `ConfigStore` directly, keeping the
/// remember-flow testable with a mock.
protocol RulePersisting {
    /// Persists a rule that routes future links for `url`'s domain to `target`.
    ///
    /// A hostless `url` (e.g. `mailto:`) has nothing to remember and is a no-op.
    func remember(url: URL, target: BrowserTarget)
}

/// Concrete `RulePersisting` that upserts a remember-rule into the stored
/// `AppConfig` via a `ConfigStore`.
///
/// `remember(url:target:)` builds the rule with `RememberRule.rule(forURL:target:)`
/// (scoping the pattern to the registrable domain, e.g. `*x.com`), then loads the
/// current config, computes `AppConfig.upserting(_:)`, and saves the result.
/// Load/save errors are logged and swallowed — remembering a choice must never
/// crash or interrupt routing, so a failure simply leaves the config unchanged.
struct ConfigRuleStore: RulePersisting {
    private static let logger = Logger(subsystem: AppIdentity.subsystem, category: "rules")

    private let configStore: ConfigStore

    /// - Parameter configStore: Source/sink of the current `AppConfig`.
    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func remember(url: URL, target: BrowserTarget) {
        guard let rule = RememberRule.rule(forURL: url, target: target) else {
            // Hostless URL: nothing to scope a rule to.
            return
        }

        let config: AppConfig
        do {
            config = try configStore.load()
        } catch {
            let reason = String(describing: error)
            Self.logger.error(
                "Failed to load config while remembering choice: \(reason, privacy: .public)"
            )
            return
        }

        do {
            try configStore.save(config.upserting(rule))
        } catch {
            let reason = String(describing: error)
            Self.logger.error(
                "Failed to save remembered rule \(rule.pattern, privacy: .public): \(reason, privacy: .public)"
            )
        }
    }
}
