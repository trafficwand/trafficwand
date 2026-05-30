import Foundation
import Sparkle

/// Concrete `UpdaterControlling` backed by Sparkle's standard updater controller.
///
/// `SPUStandardUpdaterController(startingUpdater: true, …)` boots Sparkle with its
/// default user driver (the standard download / release-notes / install / relaunch
/// flow), reading `SUFeedURL` and `SUPublicEDKey` from the app's Info.plist. All
/// seam members forward to `controller.updater`.
///
/// This adapter is intentionally not unit-tested: its behavior is Sparkle's, and the
/// live update flow is validated manually. Tests exercise the seam via `MockUpdater`.
@MainActor
final class SparkleUpdater: UpdaterControlling {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
