import Foundation

/// The browser-launch seam.
///
/// A `BrowserLaunching` opens `url` in `browser`, honoring `target`'s optional
/// profile selection. The concrete mechanism (per the launch-mechanism spike §3)
/// is `Process` → `/usr/bin/open -n -a <app path> --args <argv tail>`, where the
/// argv tail comes from `LaunchArguments.build(for:url:)`. That mechanism lives in
/// the App layer (`BrowserLauncher`) because it spawns a subprocess; this protocol
/// keeps routing logic free of any launching concern and stays Foundation-only so
/// it can live in Core (no AppKit).
///
/// `target` and `browser` are passed separately: `target` carries the bundle ID +
/// optional profile that drives the argv tail, while `browser` supplies the
/// resolved `appURL` that `open -a` needs. Callers are expected to pass a `browser`
/// whose `bundleID` matches `target.bundleID`.
public protocol BrowserLaunching: Sendable {
    /// Opens `url` in `browser`, selecting `target`'s profile if any.
    ///
    /// - Parameters:
    ///   - target: The browser + optional profile to route to; drives the argv tail.
    ///   - browser: The resolved installed browser, supplying its `appURL`.
    ///   - url: The link to open.
    /// - Throws: If the launch subprocess cannot be started.
    func launch(target: BrowserTarget, browser: Browser, url: URL) throws
}
