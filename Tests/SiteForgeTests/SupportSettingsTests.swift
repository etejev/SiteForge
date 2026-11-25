import XCTest
import Combine
import AppKit
@testable import SiteForge

final class SupportSettingsTests: XCTestCase {
    private var toolingInputRoot: URL {
        if let prepared = Bundle.main.object(forInfoDictionaryKey: "SiteForgeTestToolingRoot") as? String {
            return URL(fileURLWithPath: prepared, isDirectory: true)
        }
        // Hosted/direct XCTest remains supported; its checkout is not in Documents.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    // SF-1902-007/008: tooling runs through the same native Start/collector.
    func testAffectedScopeToolingGitAndInventoryRegressions() throws {
        let root = toolingInputRoot
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ledger = folder.appendingPathComponent("scope-tooling-ledger.json")
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.currentDirectoryURL = root
        process.arguments = [root.appendingPathComponent("Tests/Tooling/run_scope_acceptance.py").path, ledger.path]
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let log = XCTAttachment(data: output, uniformTypeIdentifier: "public.plain-text")
        log.name = "Affected scope tooling log"; log.lifetime = .keepAlways; add(log)
        if let data = try? Data(contentsOf: ledger) {
            let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            receipt.name = "Affected scope exact nested tooling ledger"; receipt.lifetime = .keepAlways; add(receipt)
        }
        XCTAssertEqual(process.terminationStatus, 0, String(data: output, encoding: .utf8) ?? "Tooling failed")
        let data = try Data(contentsOf: ledger)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(result["failed"] as? Int, 0)
        XCTAssertEqual(result["total"] as? Int, (result["cases"] as? [[String: Any]])?.count)
        XCTAssertGreaterThan(result["passed"] as? Int ?? 0, 50)
    }

    @MainActor func testAffectedScopeRequestedBaseAndUnresolvedChoice() async throws {
        let files = FileManager.default, root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let file = root.appendingPathComponent(path)
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        let source = toolingInputRoot
        for path in ["SiteForge.xcodeproj/project.pbxproj", "sf", "scripts/check-repository.sh", "AGENTS.md",
                     "SiteForge/DocumentLifecycle.swift", "Tests/SiteForgeTests/DocumentLifecycleTests.swift",
                     "Tests/SiteForgeTests/DocumentLifecycleRaceTests.swift"] { try write(path, "fixture") }
        try write("scripts/select-test-scope.py", String(contentsOf: source.appendingPathComponent("scripts/select-test-scope.py"), encoding: .utf8))
        func git(_ arguments: [String]) throws -> String {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.currentDirectoryURL = root
            process.arguments = ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false"] + arguments
            var env = ProcessInfo.processInfo.environment
            for key in ["GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"] { env[key] = "Fixture" }
            for key in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"] { env[key] = "fixture@example.invalid" }
            env["GIT_CONFIG_GLOBAL"] = "/dev/null"; env["GIT_CONFIG_NOSYSTEM"] = "1"
            process.environment = env; process.standardOutput = pipe; process.standardError = pipe
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            return String(data: data, encoding: .utf8) ?? ""
        }
        _ = try git(["init", "-q"]); _ = try git(["add", "."]); _ = try git(["commit", "-qm", "baseline"])
        let resources = root.appendingPathComponent("resources")
        try write("resources/OwnerTesting/installation.json", "{\"version\":1,\"sourceRoot\":\"\(root.path)\",\"sourceFingerprint\":\"\(String(repeating: "a", count: 64))\"}")
        try write("resources/OwnerTesting/unattended-verification.py", "fixture")
        try write("resources/OwnerTesting/SiteForgeTestingProgress", "fixture")
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resources.appendingPathComponent("OwnerTesting/SiteForgeTestingProgress").path)
        _ = try git(["add", "."]); _ = try git(["commit", "-qm", "provision fixture"])
        let store = ExperimentalTestingStore(resources: resources, reportsRoot: root.appendingPathComponent("reports"))
        let base = try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        store.affectedBase = base; store.scopePolicy = .affected
        try files.removeItem(at: root.appendingPathComponent("SiteForge/DocumentLifecycle.swift"))
        _ = try git(["add", "-A"]); _ = try git(["commit", "-qm", "delete production input"])
        await store.prepareScope()
        XCTAssertTrue(store.canStart(mode: "code"), store.scopeDescription)
        XCTAssertTrue(store.scopeDescription.contains("SiteForgeTests/DocumentLifecycleTests"))
        XCTAssertFalse(store.canStart(mode: "ui"))
        try files.removeItem(at: root.appendingPathComponent("Tests/SiteForgeTests/DocumentLifecycleTests.swift"))
        await store.prepareScope()
        XCTAssertFalse(store.canStart(mode: "code"))
        XCTAssertTrue(store.scopeDescription.contains("Choose exact selectors"))
        XCTAssertTrue(store.scopeDescription.contains(base))
    }

    // SF-0206-002/003/006: one observed global destination owner and a
    // truthful notice, without constructing a workspace or triggering tests.
    @MainActor func testGlobalSettingsNavigationAndDraftNoticeHaveNoProjectScope() async {
        let navigation = SettingsNavigationModel()
        var selected: [SettingsDestination] = []
        let observation = navigation.$selection.sink { selected.append($0) }
        navigation.show(.canvas); navigation.show(.advanced); navigation.show(.appearance)
        XCTAssertEqual(selected, [.appearance, .canvas, .advanced, .appearance])
        XCTAssertEqual(navigation.selection, .appearance)
        XCTAssertEqual(SettingsDraftNotice(appearanceDirty: true, canvasDirty: true).destinations, [.appearance, .canvas])
        XCTAssertTrue(SettingsDraftNotice(appearanceDirty: true, canvasDirty: false).message.contains("Project files are unchanged"))
        XCTAssertTrue(SettingsDraftNotice(appearanceDirty: false, canvasDirty: false).destinations.isEmpty)
        XCTAssertEqual(SettingsDestination.allCases.map(\.rawValue),
            ["appearance", "canvas", "accessibility", "defaults", "updates", "support", "advanced"])
        XCTAssertEqual(SettingsWindowGeometry.preferred.contentSize, .init(width: 860, height: 442))
        navigation.selectFromNativeList(.support)
        navigation.show(.canvas)
        navigation.selectFromNativeList(.appearance)
        navigation.selectFromNativeList(.advanced)
        let deadline = ContinuousClock.now + .seconds(2)
        while navigation.selection != .advanced, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(navigation.selection, .advanced, "Latest native selection wins; old list callbacks cannot overwrite Review")
        withExtendedLifetime(observation) {}
    }

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
            XCTAssertEqual(geometry.sidebarWidth, 201)
            XCTAssertLessThanOrEqual(geometry.formWidth, 570)
            XCTAssertLessThanOrEqual(geometry.formWidth + geometry.sidebarWidth + 77, geometry.contentSize.width)
            XCTAssertTrue(visible.contains(window.frame))
            XCTAssertEqual(window.frame.width, min(860, visible.width - 16), accuracy: 1)
            XCTAssertEqual(window.frame.height, min(470, visible.height - 16), accuracy: 1)
            let frame = window.frame
            XCTAssertEqual(SettingsWindowPolicy.apply(to: window, visibleFrame: visible), geometry)
            XCTAssertEqual(window.frame, frame)
            XCTAssertNil(window.toolbar)
            XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isEnabled ?? false)
        }
        XCTAssertEqual(SettingsWindowGeometry.preferred.contentSize, .init(width: 860, height: 442))
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

    // SF-0206-002/003/006/008, SF-1607-002/004/008, SF-1902-007/008.
    func testTestingSnapshotKeepsExactSelectorAndCodeOnlyInventory() throws {
        let json = """
        {"status":"running","mode":"code","sourceFingerprint":"receipt","stages":{
        "code":{"status":"running","completed":2,"total":4,"currentTest":"SiteForgeTests.Example/testNewRenamedCase","timedCases":2,"timedSeconds":6},
        "ui":{"status":"skipped","completed":0}}}
        """
        let snapshot = try JSONDecoder().decode(TestingRunSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.title, "New Renamed Case")
        XCTAssertEqual(snapshot.currentSelector, "SiteForgeTests/Example/testNewRenamedCase")
        XCTAssertEqual(snapshot.currentEventIdentifier, "SiteForgeTests.Example/testNewRenamedCase")
        XCTAssertEqual(snapshot.total, 4)
        XCTAssertEqual(snapshot.completed, 2)
        XCTAssertEqual(snapshot.remaining(at: .now), 6)
        XCTAssertEqual(snapshot.sourceFingerprint, "receipt")
    }

    func testTestingPausedTimeFreezesAndUnknownInventoryRemainsIndeterminate() throws {
        let json = """
        {"status":"paused","mode":"ui","startedAt":"2026-11-21T12:00:00Z","pauseStartedAt":"2026-11-21T12:00:20Z","pausedSeconds":5,"stages":{
        "ui":{"status":"running","completed":2,"total":4,"inventoryMismatch":true}}}
        """
        let snapshot = try JSONDecoder().decode(TestingRunSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.elapsed(at: .now), 15)
        XCTAssertNil(snapshot.total)
        XCTAssertEqual(snapshot.completed, 2)
        XCTAssertNil(snapshot.remaining(at: .now))
        XCTAssertEqual(TestingRunSnapshot.clock(snapshot.elapsed(at: .now)), "0:15")
    }

    func testTestingPreparationHasDistinctActivityAndMeasuredPhaseEstimate() throws {
        let json = """
        {"status":"running","mode":"code","stages":{
        "build":{"status":"running","completed":0,"startedAt":"2026-11-21T12:00:00Z","estimatedSeconds":80,"phaseDetail":"Compiling TestingWindow.swift"},
        "code":{"status":"waiting","completed":0}}}
        """
        let snapshot = try JSONDecoder().decode(TestingRunSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.isPreparing)
        XCTAssertEqual(snapshot.preparationDetail, "Compiling TestingWindow.swift")
        XCTAssertNotEqual(snapshot.title, snapshot.preparationDetail)
        let time = try XCTUnwrap(TestingRunSnapshot.date("2026-11-21T12:00:20Z"))
        XCTAssertEqual(snapshot.remaining(at: time), 60)
        XCTAssertNil(snapshot.total)
        XCTAssertEqual(snapshot.completed, 0)
    }

    @MainActor func testTestingScopeValidationNeverExpandsInvalidOrEmptySelection() {
        XCTAssertEqual(ExperimentalTestingStore.selectors(in: "SiteForgeTests/Example/testOne SiteForgeTests/Example/testOne"),
                       ["SiteForgeTests/Example/testOne"])
        XCTAssertEqual(ExperimentalTestingStore.selectors(in: "SiteForgeUITests/Example"), ["SiteForgeUITests/Example"])
        XCTAssertNil(ExperimentalTestingStore.selectors(in: ""))
        XCTAssertNil(ExperimentalTestingStore.selectors(in: "OtherTarget/Example/testOne"))
        XCTAssertNil(ExperimentalTestingStore.selectors(in: "SiteForgeTests/Example;anything"))
    }

    @MainActor func testTestingHistoryReopensWithoutRetargetingActiveControls() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first"), second = root.appendingPathComponent("second")
        for path in [first, second] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        let passed = #"{"status":"passed","mode":"code","stages":{"code":{"status":"passed","completed":1,"total":1}}}"#
        let paused = #"{"status":"paused","mode":"code","stages":{"code":{"status":"running","completed":1,"total":2}}}"#
        try Data(passed.utf8).write(to: first.appendingPathComponent("state.json"))
        try Data(paused.utf8).write(to: second.appendingPathComponent("state.json"))
        func point(_ file: String, at path: URL) throws {
            try JSONSerialization.data(withJSONObject: ["run": path.path]).write(to: root.appendingPathComponent(file), options: .atomic)
        }
        try point("current.json", at: first)
        let store = ExperimentalTestingStore(resources: nil, reportsRoot: root)
        store.showRun(first)
        try point("current.json", at: second); try point("active.json", at: second)
        store.refresh()
        XCTAssertEqual(store.report?.standardizedFileURL.path, second.standardizedFileURL.path)
        XCTAssertEqual(store.displayedReport, first)
        store.pauseOrResume()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.appendingPathComponent("resume.request").path))
        store.showRun(nil)
        store.pauseOrResume()
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.appendingPathComponent("resume.request").path))
        await store.reloadHistory()
        XCTAssertEqual(Set(store.history.map { $0.url.standardizedFileURL.path }), Set([first, second].map { $0.standardizedFileURL.path }))
        XCTAssertFalse(store.canStart(mode: "code"))
    }

    // SF-0206-006/008, SF-1607-006/008: terminal and history presentation
    // must retain exact routing without presenting stale activity as progress.
    func testTestingTerminalSummaryAndReadableHistoryPreserveExactIdentity() throws {
        let json = #"{"status":"passed","mode":"code","startedAt":"2026-11-21T20:44:14Z","activity":"Exporting code results","scope":{"mode":"code","selectors":["SiteForgeTests/Example/testLongName"]},"stages":{"code":{"status":"passed","completed":1,"total":1,"currentTest":"Example/testLongName"}}}"#
        let snapshot = try JSONDecoder().decode(TestingRunSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.title, "Testing passed")
        XCTAssertNil(snapshot.preparationDetail)
        XCTAssertNil(snapshot.remaining(at: .now))
        XCTAssertEqual(snapshot.scopeSummary, "1 requested selector · Regular testing")
        XCTAssertEqual(snapshot.scopeLabel, "SiteForgeTests/Example/testLongName")
        let url = URL(fileURLWithPath: "/reports/20261121-204414-92a7e8a0")
        let record = TestingRunRecord(url: url, status: snapshot.status, mode: snapshot.resolvedMode, startedAt: snapshot.startedAt)
        XCTAssertEqual(record.id, url.path)
        XCTAssertFalse(record.title.contains(url.lastPathComponent))
        XCTAssertFalse(record.title.contains("Undated"))
        XCTAssertEqual(record.subtitle, "Regular testing · Passed")
        XCTAssertEqual(TestingRunRecord(url: url, status: "cancelled", mode: "ui").subtitle, "UI testing · Cancelled")
        XCTAssertEqual(TestingRunRecord(url: url, status: "failed", mode: "focused").subtitle, "Combined testing · Failed")
    }

    @MainActor func testTestingExactScopeSummaryDoesNotRepeatEditableSelectors() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ExperimentalTestingStore(resources: missing, reportsRoot: missing)
        store.scopePolicy = .focused
        store.selectorText = "SiteForgeTests/Example/testLongName"
        await store.prepareScope()
        XCTAssertTrue(store.scopeReady)
        XCTAssertTrue(store.scopeDescription.contains("1 requested selector"))
        XCTAssertFalse(store.scopeDescription.contains(store.selectorText))
        store.selectorText = "removed/invalid"
        await store.prepareScope()
        XCTAssertFalse(store.scopeReady)
        XCTAssertTrue(store.scopeDescription.contains("Enter exact"))
    }

    @MainActor func testTestingNoticeKeepsActionableErrorsAndSuppressesDuplicateRunStatus() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let run = root.appendingPathComponent("run")
        try files.createDirectory(at: run, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try Data(#"{"status":"running","mode":"code","stages":{"code":{"status":"running","completed":0}}}"#.utf8).write(to: run.appendingPathComponent("state.json"))
        try JSONSerialization.data(withJSONObject: ["run": run.path]).write(to: root.appendingPathComponent("current.json"))
        try JSONSerialization.data(withJSONObject: ["run": run.path]).write(to: root.appendingPathComponent("active.json"))
        let store = ExperimentalTestingStore(resources: root, reportsRoot: root)
        XCTAssertNil(store.presentationNotice)
        store.pauseOrResume()
        XCTAssertNil(store.presentationNotice)
        store.run(mode: "code")
        XCTAssertEqual(store.presentationNotice, "A testing run is already active.")
        store.showRun(run)
        XCTAssertTrue(try XCTUnwrap(store.presentationNotice).contains("current run continues"))
    }

    @MainActor func testTestingHelperAppearanceEnvironmentIsScopedAndPreservesLaunchInputs() throws {
        let base = ["DEVELOPER_DIR": "/fixture/Xcode", "EXISTING": "value"]
        let dark = ExperimentalTestingStore.progressEnvironment(base: base,
            appearance: try XCTUnwrap(NSAppearance(named: .darkAqua)), sourceBundle: "fixture.siteforge")
        XCTAssertEqual(dark["SITEFORGE_TESTING_APPEARANCE"], "dark")
        XCTAssertEqual(dark["SITEFORGE_TESTING_APPEARANCE_SOURCE"], "fixture.siteforge")
        XCTAssertEqual(dark["DEVELOPER_DIR"], base["DEVELOPER_DIR"])
        XCTAssertEqual(dark["EXISTING"], "value")
        let light = ExperimentalTestingStore.progressEnvironment(base: base,
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)), sourceBundle: "fixture.siteforge")
        XCTAssertEqual(light["SITEFORGE_TESTING_APPEARANCE"], "light")
        let system = ExperimentalTestingStore.progressEnvironment(base: dark, appearance: nil, sourceBundle: nil)
        XCTAssertEqual(system["SITEFORGE_TESTING_APPEARANCE"], "system")
        XCTAssertNil(system["SITEFORGE_TESTING_APPEARANCE_SOURCE"])
        XCTAssertEqual(TestingRunRecord(url: URL(fileURLWithPath: "/fixture/run"), status: "passed", mode: "unknown").subtitle,
                       "Recorded testing · Passed")
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
