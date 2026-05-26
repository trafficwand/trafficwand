import XCTest
@testable import TrafficWand

/// Tests for the **pure** `BuildInfo` parser.
///
/// `BuildInfo.current()` reads `Bundle.main.infoDictionary` at runtime; here we
/// exercise the pure `init(infoDictionary:)` against synthetic dictionaries so
/// the parsing contract is testable without a live app bundle.
final class BuildInfoTests: XCTestCase {

    func testFullDictionary() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleDisplayName": "TrafficWand",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "GitCommitHash": "abc1234"
        ])

        XCTAssertEqual(info.name, "TrafficWand")
        XCTAssertEqual(info.version, "0.1.0")
        XCTAssertEqual(info.build, "1")
        XCTAssertEqual(info.commit, "abc1234")
    }

    func testMissingCommitKeyYieldsNil() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1"
        ])

        XCTAssertNil(info.commit)
    }

    func testEmptyStringCommitYieldsNil() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "GitCommitHash": ""
        ])

        XCTAssertNil(info.commit)
    }

    /// Whitespace-only commit (e.g. a botched substitution that left
    /// `   ` after trimming the value) must also collapse to `nil` so the
    /// About view doesn't render an obviously-broken `commit  ` line.
    func testWhitespaceOnlyCommitYieldsNil() {
        let info = BuildInfo(infoDictionary: [
            "GitCommitHash": "   \t\n"
        ])

        XCTAssertNil(info.commit)
    }

    func testUnknownSentinelCommitYieldsNil() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "GitCommitHash": "unknown"
        ])

        XCTAssertNil(info.commit)
    }

    func testMissingVersionDefaultsToEmptyString() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleVersion": "1"
        ])

        XCTAssertEqual(info.version, "")
    }

    func testMissingBuildDefaultsToEmptyString() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0"
        ])

        XCTAssertEqual(info.build, "")
    }

    func testDisplayNameWinsOverBundleName() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleDisplayName": "TrafficWand",
            "CFBundleName": "twand"
        ])

        XCTAssertEqual(info.name, "TrafficWand")
    }

    func testBundleNameUsedWhenDisplayNameMissingOrEmpty() {
        XCTAssertEqual(
            BuildInfo(infoDictionary: ["CFBundleName": "twand"]).name,
            "twand"
        )
        XCTAssertEqual(
            BuildInfo(infoDictionary: ["CFBundleDisplayName": "", "CFBundleName": "twand"]).name,
            "twand"
        )
    }

    func testNameFallsBackToDefaultWhenBothKeysMissing() {
        let info = BuildInfo(infoDictionary: [:])

        XCTAssertEqual(info.name, BuildInfo.defaultAppName)
    }
}
