import Foundation

/// Buffer-and-flush seam for incoming links, decoupling *receiving* a link from
/// *being able to route* it.
///
/// On a cold start, macOS can deliver the open-URL event before
/// `applicationDidFinishLaunching` has finished wiring the routing pipeline. To
/// uphold the project's "never drop a link" principle at the intake boundary,
/// `LinkIntake` buffers links that arrive before routing is ready and flushes
/// them, in arrival order, once `activate(route:)` installs the routing closure.
///
/// Lock-free by design: `@MainActor` isolation (Swift 6, compiler-enforced) plus
/// both call sites (`application(_:open:)` and `applicationDidFinishLaunching`)
/// being main-thread AppKit delegate callbacks means `pending` is only ever
/// touched on the main thread.
@MainActor
final class LinkIntake {
    private var route: ((URL) -> Void)?
    private var pending: [URL] = []

    /// `nonisolated` so the instance can be created as a default value of a
    /// stored property in a nonisolated context (e.g. `AppMain`'s synthesized
    /// initializer). The init touches no main-actor state.
    nonisolated init() {}

    /// Accept a link: route now if ready, otherwise buffer until `activate`.
    func accept(_ url: URL) {
        if let route { route(url) } else { pending.append(url) }
    }

    /// Install the routing handler and flush any buffered links, in arrival order.
    /// Idempotent: a second call after activation is a no-op (the handler is already
    /// installed and the buffer is empty), so callers needn't track activation state.
    func activate(route: @escaping (URL) -> Void) {
        guard self.route == nil else { return }   // already activated
        self.route = route
        let buffered = pending
        pending.removeAll()
        buffered.forEach(route)
    }
}
