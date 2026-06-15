import XCTest
@testable import TrafficWand

/// Sanity check for the `SettingsTab` deep-link key.
///
/// The `id == rawValue` mapping is language-derived (the conformance literally
/// says `var id: String { rawValue }`) and would be tautological to test; we
/// instead pin the **set of cases**, since adding/removing a case would be a
/// real behavior change for the Settings window's `TabView` selection.
final class SettingsTabTests: XCTestCase {

    func testAllCasesArePresent() {
        XCTAssertEqual(Set(SettingsTab.allCases), [.general, .rules, .aliases, .about])
    }

    /// The `TabView` renders tabs in `allCases` order; pin it so a reordering is a
    /// deliberate change (general → rules → aliases → about).
    func testCaseOrder() {
        XCTAssertEqual(SettingsTab.allCases, [.general, .rules, .aliases, .about])
    }
}
