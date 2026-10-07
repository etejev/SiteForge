import XCTest
@testable import SiteForge

final class SupportSettingsTests: XCTestCase {
    private let identity = ApplicationBuildIdentity(
        product: "SiteForge",
        version: "0.1.0",
        build: "1",
        bundleIdentifier: "app.siteforge.SiteForge",
        channel: "Installed distribution"
    )

    // SF-1607-002/003/008, SF-1507-003/004
    func testRedactedReportIsDeterministicUsefulAndContentFree() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let report = RedactedSupportReport(
            generatedAt: date,
            application: identity,
            operatingSystem: "macOS Test"
        )
        let first = try report.encoded()
        let second = try report.encoded()
        XCTAssertEqual(first, second)

        let text = try XCTUnwrap(String(data: first, encoding: .utf8))
        XCTAssertTrue(text.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(text.contains("SF-1607-008"))
        XCTAssertTrue(text.contains("Installed distribution"))
        XCTAssertTrue(text.contains("Recovery snapshots"))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("file://"))
        XCTAssertFalse(text.contains("password"))
        XCTAssertFalse(text.contains("token"))
    }

    // SF-0206-004/006/008, SF-1607-004/006/008
    @MainActor
    func testSupportStoreAdoptsLatestReportAndExposesTruthfulDistributionBoundary() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = SupportSettingsStore(
            application: identity,
            operatingSystem: "macOS Test",
            clock: { date }
        )
        XCTAssertEqual(store.state, .idle)
        XCTAssertFalse(store.canShare)
        XCTAssertEqual(store.updateSummary, "Version 0.1.0 (1) · Installed distribution")

        store.generate()
        for _ in 0..<100 where store.state == .preparing { await Task.yield() }

        XCTAssertEqual(store.state, .ready)
        XCTAssertTrue(store.canShare)
        XCTAssertEqual(store.failureCategory, "none")
        XCTAssertTrue(store.reportText.contains("macOS Test"))
        XCTAssertTrue(store.status.contains("Review"))
    }

    // SF-1607-004/006
    @MainActor
    func testUnavailableShareIsNeutralAndActionable() {
        let store = SupportSettingsStore(application: identity, operatingSystem: "macOS Test")
        store.copyReport()
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.failureCategory, "report-unavailable")
        XCTAssertTrue(store.status.contains("Generate"))
    }
}
