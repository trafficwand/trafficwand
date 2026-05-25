import Testing
@testable import TrafficWandCore

@Suite("Smoke")
struct SmokeTests {
    @Test("Core module is importable and exposes its name")
    func moduleIsImportable() {
        #expect(TrafficWandCore.name == "TrafficWandCore")
    }
}
