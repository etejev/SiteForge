import XCTest
@testable import SiteForge

@MainActor
final class ArchitectureBoundaryTests: XCTestCase {
    // SF-1801-001, SF-1801-002, SF-1801-003, SF-1801-004, SF-1801-008
    func testEachWorkspaceContextOwnsIndependentCanonicalAndConvenienceState() throws {
        let firstSession = DocumentSession()
        let firstHome = try XCTUnwrap(firstSession.document.pages.first)
        _ = try firstSession.execute(
            .renamePage(RenamePageCommand(pageID: firstHome.id, name: "First Window Home"))
        )
        let first = WorkspaceDocumentContext(session: firstSession)
        let second = WorkspaceDocumentContext(session: DocumentSession())

        XCTAssertFalse(first.shellState === second.shellState)
        XCTAssertFalse(first.shellState.lifecycle === second.shellState.lifecycle)
        XCTAssertFalse(first.shellState.documentSession === second.shellState.documentSession)
        XCTAssertNotEqual(first.shellState.documentSession.document.id, second.shellState.documentSession.document.id)

        first.shellState.selectTool(.text)
        first.shellState.adjustZoom(by: 25)

        XCTAssertEqual(first.shellState.documentSession.document.pages.first?.name, "First Window Home")
        XCTAssertEqual(first.shellState.selectedTool, .text)
        XCTAssertEqual(first.shellState.zoomPercent, 125)
        XCTAssertEqual(second.shellState.documentSession.document.pages.first?.name, "Home")
        XCTAssertEqual(second.shellState.selectedTool, .select)
        XCTAssertEqual(second.shellState.zoomPercent, 100)
        XCTAssertNil(first.shellState.lifecycle.fileURL)
        XCTAssertNil(second.shellState.lifecycle.fileURL)
    }

    // SF-1801-008, SF-1802-008
    func testDisabledCompositionIgnoresEveryDebugOverride() {
        let disabled = DebugTestComposition(
            arguments: [
                "SiteForge", "-SiteForgeWorkspaceFixture", "large",
                "-SiteForgeWindowSize", "minimum", "-SiteForgeStartModified",
            ],
            enabled: false
        )

        XCTAssertNil(disabled.value(after: "-SiteForgeWorkspaceFixture"))
        XCTAssertFalse(disabled.contains("-SiteForgeStartModified"))
        XCTAssertNil(WorkspaceFixtureScale.from(composition: disabled))
        XCTAssertNil(WorkspaceMetrics.requestedWindowSize(composition: disabled))
        XCTAssertNil(LaunchPreviewScenario.from(composition: disabled))
    }

    // SF-1801-008, SF-1802-008
    func testEnabledCompositionProvidesOneExplicitDebugInjectionBoundary() {
        let enabled = DebugTestComposition(
            arguments: [
                "SiteForge", "-SiteForgeWorkspaceFixture", "standard",
                "-SiteForgeWindowSize", "minimum",
                "-SiteForgeLaunchScenario", "loadingDeterminate",
            ],
            enabled: true
        )

        XCTAssertEqual(WorkspaceFixtureScale.from(composition: enabled), .standard)
        XCTAssertEqual(WorkspaceMetrics.requestedWindowSize(composition: enabled), WorkspaceMetrics.minimumWindowSize)
        XCTAssertEqual(LaunchPreviewScenario.from(composition: enabled), .loadingDeterminate)
    }
}
