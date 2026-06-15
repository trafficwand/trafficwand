import Foundation
import TrafficWandCore

/// The seam through which `RoutingService` hands off a `.prompt` decision to the
/// picker UI.
///
/// `RoutingService` makes no UI decisions — when `Router.decide` returns
/// `.prompt(url:browsers:)`, the service simply forwards the URL and the available
/// browsers to a `PickerPresenting`. The concrete floating-panel implementation
/// (`PickerPanelController`) conforms to this protocol; tests inject a mock that
/// records the call.
@MainActor
protocol PickerPresenting {
    /// Presents the interactive browser/profile picker for `url`.
    ///
    /// - Parameters:
    ///   - url: The link awaiting a destination.
    ///   - browsers: The browsers (with profiles) to offer.
    ///   - aliases: The reusable aliases to offer at the top of the picker. The
    ///     picker filters out aliases whose target browser isn't installed.
    func presentPicker(url: URL, browsers: [Browser], aliases: [ProfileAlias])
}
