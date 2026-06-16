import XCTest
@testable import TrafficWand

/// Tests for the `LinkIntake` buffer/flush seam (Task 1).
///
/// `LinkIntake` decouples receiving a link (`accept`) from being able to route it
/// (`activate`). These tests drive it directly — no AppKit / no `NSApplication` —
/// covering: buffer-before-ready, flush-in-arrival-order, route-after-ready,
/// empty-buffer no-op, warm-path equivalence, idempotent double-activate, and
/// re-entrant accept during flush.
@MainActor
final class LinkIntakeTests: XCTestCase {

    private func url(_ string: String) -> URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: string)!
    }

    /// `accept(url)` before `activate` buffers the URL (nothing routed yet).
    func testAcceptBeforeActivateBuffers() {
        let intake = LinkIntake()
        var routed: [URL] = []

        intake.accept(url("https://example.com/a"))

        XCTAssertTrue(routed.isEmpty, "Nothing should route before activate")

        intake.activate { routed.append($0) }
        XCTAssertEqual(routed, [url("https://example.com/a")])
    }

    /// `activate(route:)` flushes a single buffered URL to the route closure.
    func testActivateFlushesSingleBufferedURL() {
        let intake = LinkIntake()
        var routed: [URL] = []

        intake.accept(url("https://example.com/one"))
        intake.activate { routed.append($0) }

        XCTAssertEqual(routed, [url("https://example.com/one")])
    }

    /// Multiple buffered URLs flush in arrival order.
    func testMultipleBufferedURLsFlushInArrivalOrder() {
        let intake = LinkIntake()
        var routed: [URL] = []

        intake.accept(url("https://example.com/1"))
        intake.accept(url("https://example.com/2"))
        intake.accept(url("https://example.com/3"))
        intake.activate { routed.append($0) }

        XCTAssertEqual(routed, [
            url("https://example.com/1"),
            url("https://example.com/2"),
            url("https://example.com/3")
        ])
    }

    /// `accept(url)` after `activate` routes immediately (no buffering).
    func testAcceptAfterActivateRoutesImmediately() {
        let intake = LinkIntake()
        var routed: [URL] = []

        intake.activate { routed.append($0) }
        intake.accept(url("https://example.com/warm"))

        XCTAssertEqual(routed, [url("https://example.com/warm")])
    }

    /// `activate` with an empty buffer routes nothing (no-op) and later `accept`s still route.
    func testActivateWithEmptyBufferIsNoOpThenRoutes() {
        let intake = LinkIntake()
        var routed: [URL] = []

        intake.activate { routed.append($0) }
        XCTAssertTrue(routed.isEmpty, "Empty buffer flush should route nothing")

        intake.accept(url("https://example.com/after"))
        XCTAssertEqual(routed, [url("https://example.com/after")])
    }

    /// Warm-path equivalence: after `activate`, N sequential `accept`s each route
    /// immediately, in order, with nothing buffered.
    func testWarmPathEquivalence() {
        let intake = LinkIntake()
        var routed: [URL] = []

        intake.activate { routed.append($0) }
        let urls = (0..<5).map { url("https://example.com/\($0)") }
        for incoming in urls { intake.accept(incoming) }

        XCTAssertEqual(routed, urls)
    }

    /// Double `activate`: a second `activate` after activation is a no-op (does not
    /// re-flush, does not replace routing behavior).
    func testDoubleActivateIsNoOp() {
        let intake = LinkIntake()
        var firstRouted: [URL] = []
        var secondRouted: [URL] = []

        intake.accept(url("https://example.com/buffered"))
        intake.activate { firstRouted.append($0) }
        XCTAssertEqual(firstRouted, [url("https://example.com/buffered")])

        // Second activate must not re-flush nor swap the routing closure.
        intake.activate { secondRouted.append($0) }
        XCTAssertEqual(firstRouted, [url("https://example.com/buffered")],
                       "Second activate must not re-flush the buffer")
        XCTAssertTrue(secondRouted.isEmpty, "Second activate must not install a new route")

        // Subsequent accepts still go through the original closure.
        intake.accept(url("https://example.com/later"))
        XCTAssertEqual(firstRouted, [
            url("https://example.com/buffered"),
            url("https://example.com/later")
        ])
        XCTAssertTrue(secondRouted.isEmpty)
    }

    /// Re-entrant accept during flush: if a flushed route synchronously calls
    /// `accept` again, that URL routes immediately (not lost to the cleared buffer).
    func testReentrantAcceptDuringFlushRoutesImmediately() {
        let intake = LinkIntake()
        var routed: [URL] = []
        let trigger = url("https://example.com/trigger")
        let reentrant = url("https://example.com/reentrant")

        intake.accept(trigger)
        intake.activate { incoming in
            routed.append(incoming)
            // On the first (buffered) URL, synchronously accept another link.
            if incoming == trigger {
                intake.accept(reentrant)
            }
        }

        XCTAssertEqual(routed, [trigger, reentrant],
                       "Re-entrant accept during flush should route immediately")
    }
}
