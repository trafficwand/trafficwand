import Testing
@testable import TrafficWandCore

@Suite("Smoke")
struct SmokeTests {
    @Test("Core module is importable and exposes its real types")
    func moduleIsImportable() {
        // Touch a real public type so the smoke test fails to compile if the
        // module ever stops exporting its domain model.
        let config = AppConfig.default
        #expect(config.fallback == .picker)
    }
}
