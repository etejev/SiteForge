import XCTest
import Combine
import AppKit
@testable import SiteForge

final class SupportSettingsTests: XCTestCase {
    @MainActor
    func testSettingsFixedWindowGeometryFitsDisplaysAndNeverChangesDocumentWindows() throws {
        for visible in [NSRect(x: 0, y: 34, width: 1710, height: 1001),
                        .init(x: -1024, y: 30, width: 1024, height: 680),
                        .init(x: 10, y: 20, width: 800, height: 560)] {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1180, height: 780),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let original = window.styleMask
            XCTAssertNil(SettingsWindowPolicy.apply(to: window, visibleFrame: visible))
            XCTAssertEqual(window.styleMask, original)
            window.identifier = SettingsWindowPolicy.identifier
            let geometry = try XCTUnwrap(SettingsWindowPolicy.apply(to: window, visibleFrame: visible))
            XCTAssertFalse(window.styleMask.contains(.resizable))
            XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
            XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
            XCTAssertEqual(window.contentMinSize, geometry.contentSize)
            XCTAssertEqual(window.contentMaxSize, geometry.contentSize)
            XCTAssertEqual(geometry.sidebarWidth, 250)
            XCTAssertLessThanOrEqual(geometry.formWidth, 680)
            XCTAssertLessThanOrEqual(geometry.formWidth + geometry.sidebarWidth + 40, geometry.contentSize.width)
            XCTAssertTrue(visible.contains(window.frame))
            let frame = window.frame
            XCTAssertEqual(SettingsWindowPolicy.apply(to: window, visibleFrame: visible), geometry)
            XCTAssertEqual(window.frame, frame)
            XCTAssertNil(window.toolbar)
            XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isEnabled ?? false)
        }
        XCTAssertEqual(SettingsWindowGeometry.preferred.contentSize, .init(width: 970, height: 740))
        XCTAssertNil(SettingsWindowGeometry.resolve(visibleFrame: .init(x: 0, y: 0, width: CGFloat.nan, height: 800)))
    }
    // SF-0206-004/006/008: ordinary Settings exposes Advanced without preferences.
    func testAdvancedDestinationIsAlwaysDiscoverableWithoutExperimentalOptions() {
        XCTAssertTrue(SettingsDestination.allCases.contains(.advanced))
        XCTAssertFalse(SettingsDestination.allCases.map(\.rawValue).contains("testing"))
    }

    @MainActor
    func testTestingInstallationAndPersistentRefreshNeedNoWebsiteWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SiteForge-testing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        for relative in ["SiteForge.xcodeproj/project.pbxproj", "sf", "scripts/check-repository.sh", "AGENTS.md"] {
            let file = source.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let resources = root.appendingPathComponent("resources")
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("OwnerTesting"), withIntermediateDirectories: true)
        let configuration = OwnerTestingInstallation(version: 1, sourceRoot: source.path,
            sourceFingerprint: String(repeating: "a", count: 64))
        try JSONEncoder().encode(configuration).write(to: resources.appendingPathComponent("OwnerTesting/installation.json"))
        let reports = root.appendingPathComponent("reports")
        let report = reports.appendingPathComponent("fixture-run")
        try FileManager.default.createDirectory(at: report, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["run": report.path]).write(to: reports.appendingPathComponent("current.json"))
        try JSONSerialization.data(withJSONObject: ["status": "failed"]).write(to: report.appendingPathComponent("state.json"))
        let store = ExperimentalTestingStore(resources: resources, reportsRoot: reports)
        XCTAssertEqual(store.workspace?.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(store.report?.standardizedFileURL, report.standardizedFileURL)
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        store.refresh(); store.refresh()
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(observation) {}
        try JSONSerialization.data(withJSONObject: ["run": report.path]).write(to: reports.appendingPathComponent("active.json"))
        store.refresh()
        XCTAssertTrue(store.running)
        store.run(mode: "full")
        XCTAssertEqual(store.status, "A testing run is already active.")
        store.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.appendingPathComponent("cancel.request").path))
        let restored = ExperimentalTestingStore(resources: resources, reportsRoot: reports)
        XCTAssertEqual(restored.report, store.report)
    }

    @MainActor
    func testTestingMissingHarnessIsTruthfulAndFixedUpdatePolicyIgnoresStaleChoice() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ExperimentalTestingStore(resources: missing, reportsRoot: missing)
        XCTAssertNil(store.workspace)
        store.run(mode: "ui")
        XCTAssertTrue(store.status.contains("unavailable"))
        XCTAssertFalse(store.running)
        XCTAssertFalse(ExperimentalTestingStore.validWorkspace(missing))
        let name = "SiteForge.fixed-update." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("preview", forKey: UpdateSettingsStore.channelKey)
        XCTAssertEqual(UpdateSettingsStore(defaults: defaults).channel, .stable)
    }

    private struct Feed: UpdateFeedChecking {
        let result: Result<UpdateRelease?, UpdateCheckFailure>
        func latestRelease(channel: UpdateChannel) async throws -> UpdateRelease? { try result.get() }
    }
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

    // SF-1507-003/004/006/008
    func testVersionOrderingIsMonotonicAndPrereleaseAware() throws {
        XCTAssertLessThan(try XCTUnwrap(UpdateVersion("1.9.9")), try XCTUnwrap(UpdateVersion("2.0.0")))
        XCTAssertLessThan(try XCTUnwrap(UpdateVersion("2.0.0-preview.1")), try XCTUnwrap(UpdateVersion("2.0.0")))
        XCTAssertEqual(UpdateVersion("v2.4.0"), UpdateVersion("2.4"))
        XCTAssertNil(UpdateVersion("2.latest"))
        XCTAssertNil(UpdateVersion("2..1"))
    }

    // SF-1507-001–008 — source coverage; execution deferred by owner pause.
    @MainActor
    func testUpdateCheckAdoptsCurrentRequestAndSignedInstallRemainsPolicyBlocked() async {
        let release = UpdateRelease(version: "0.2.0", build: "2", channel: .stable,
            notes: "A bounded release.", downloadSize: 1024, provenanceHost: "github.com",
            artifactURL: URL(string: "https://github.com/example/SiteForge/releases/download/v0.2/SiteForge.dmg"),
            signature: nil, sha256: nil, minimumSystemVersion: nil, bundleIdentifier: nil)
        let defaults = UserDefaults(suiteName: "SupportSettingsTests.\(UUID().uuidString)")!
        let store = UpdateSettingsStore(application: identity, defaults: defaults,
            feed: Feed(result: .success(release)))
        store.check()
        for _ in 0..<100 where store.state == .checking { await Task.yield() }
        XCTAssertEqual(store.update, release)
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "none")
        store.requestTrustedInstall()
        XCTAssertEqual(store.state, .policyBlocked)
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "owner-policy-disabled")
    }

    @MainActor
    func testUpdateOfflineCancellationAndRollbackAreNeutral() async {
        let defaults = UserDefaults(suiteName: "SupportSettingsTests.\(UUID().uuidString)")!
        let offline = UpdateSettingsStore(application: identity, defaults: defaults,
            feed: Feed(result: .failure(.offline)))
        offline.check()
        for _ in 0..<100 where offline.state == .checking { await Task.yield() }
        XCTAssertEqual(offline.state, .offline)
        XCTAssertTrue(offline.status.contains("offline"))

        let older = UpdateRelease(version: "0.0.9", build: nil, channel: .stable, notes: "Old",
            downloadSize: nil, provenanceHost: "github.com", artifactURL: nil, signature: nil,
            sha256: nil, minimumSystemVersion: nil, bundleIdentifier: nil)
        let rollback = UpdateSettingsStore(application: identity, defaults: defaults,
            feed: Feed(result: .success(older)))
        rollback.check()
        for _ in 0..<100 where rollback.state == .checking { await Task.yield() }
        XCTAssertEqual(rollback.state, .upToDate)
        XCTAssertEqual(rollback.lastDiagnostic.failureCategory, "rollback-rejected")
    }

    func testUpdateInstallTrustPolicyFailsClosedForEveryMissingTrustFact() throws {
        let base = UpdateRelease(version: "0.2.0", build: "2", channel: .stable,
            notes: "Bounded", downloadSize: 1024, provenanceHost: "github.com",
            artifactURL: URL(string: "https://github.com/example/SiteForge.dmg"),
            signature: "verified-ed25519", sha256: "verified-sha256", minimumSystemVersion: nil,
            bundleIdentifier: identity.bundleIdentifier)
        if case .failure(.ownerPolicyDisabled) = UpdateInstallTrustPolicy(ownerPolicyEnabled: false)
            .validate(base, installed: identity, selectedChannel: .stable) {} else {
            XCTFail("Owner policy must fail closed")
        }
        let enabled = UpdateInstallTrustPolicy(ownerPolicyEnabled: true)
        if case .failure(.unsigned) = enabled.validate(UpdateRelease(version: base.version, build: base.build,
            channel: base.channel, notes: base.notes, downloadSize: base.downloadSize,
            provenanceHost: base.provenanceHost, artifactURL: base.artifactURL, signature: nil,
            sha256: base.sha256, minimumSystemVersion: nil, bundleIdentifier: base.bundleIdentifier),
            installed: identity, selectedChannel: .stable) {} else { XCTFail("Unsigned release must fail closed") }
        if case .failure(.channelMismatch) = enabled.validate(base, installed: identity, selectedChannel: .preview) {} else {
            XCTFail("Channel mismatch must fail closed")
        }
        if case .success = enabled.validate(base, installed: identity, selectedChannel: .stable) {} else {
            XCTFail("Complete trusted metadata should satisfy the pure policy")
        }
    }
}
