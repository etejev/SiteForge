import XCTest
@testable import SiteForge

final class AppMetadataTests: XCTestCase {
    // SF-1501-008, SF-1902-008
    func testLocalApplicationIdentityIsStableAndReversible() {
        XCTAssertEqual(AppMetadata.productName, "SiteForge")
        XCTAssertEqual(AppMetadata.localBundleIdentifier, "app.siteforge.SiteForge")
        XCTAssertEqual(Bundle.main.bundleIdentifier, AppMetadata.localBundleIdentifier)
    }

    // SF-1902-008
    func testFoundationRequirementTraceabilityIsComplete() {
        XCTAssertEqual(
            AppMetadata.foundationRequirementIDs,
            ["SF-1501-008", "SF-1802-008", "SF-1902-006", "SF-1902-008"]
        )
    }

    // SF-0201-002, SF-0201-008
    func testShellRegionsAndMinimumWindowMetricsAreStable() {
        XCTAssertEqual(
            ShellRegion.allCases.map(\.rawValue),
            ["shell.navigator", "shell.canvas", "shell.inspector", "shell.status"]
        )
        XCTAssertEqual(WorkspaceMetrics.minimumWindowSize.width, 1_100)
        XCTAssertEqual(WorkspaceMetrics.minimumWindowSize.height, 700)
        XCTAssertGreaterThan(
            WorkspaceMetrics.defaultWindowSize.width,
            WorkspaceMetrics.minimumWindowSize.width
        )
        XCTAssertGreaterThan(
            WorkspaceMetrics.defaultWindowSize.height,
            WorkspaceMetrics.minimumWindowSize.height
        )
    }

    // SF-0201-006, SF-0203-006, SF-0203-008
    @MainActor
    func testShellCommandDefaultsAndBoundariesAreIntentional() {
        let state = WorkspaceShellState()
        let canonicalDocument = state.documentSession.document

        XCTAssertEqual(CanvasTool.allCases.map(\.title), ["Select", "Frame", "Text", "Image", "Component"])
        XCTAssertEqual(state.selectedTool, .select)
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)

        state.selectTool(.component)
        XCTAssertEqual(state.selectedTool, .component)
        XCTAssertEqual(state.documentSession.document, canonicalDocument)

        for _ in 0..<10 { state.adjustZoom(by: -25) }
        XCTAssertEqual(state.zoomPercent, 25)
        for _ in 0..<20 { state.adjustZoom(by: 25) }
        XCTAssertEqual(state.zoomPercent, 800)
        XCTAssertEqual(state.documentSession.document, canonicalDocument)
    }

    // SF-0201-006, SF-0303-006, SF-1505-006
    func testShellFocusTraversalIsCompleteBidirectionalAndSceneLocal() {
        let first = PageID(UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)
        let second = PageID(UUID(uuidString: "30000000-0000-0000-0000-000000000002")!)
        let order = ShellFocusTraversal.order(pageIDs: [first, second])
        XCTAssertEqual(order, [
            .navigatorPages, .navigatorLayers, .navigatorPage(first),
            .navigatorPage(second), .viewportPreset, .viewportZoomOut, .viewportZoomIn,
            .viewportReset, .viewportFit, .viewportCanvas,
            .inspectorLayout, .inspectorStyle, .inspectorAdvanced, .inspectorAccessibility,
        ])
        for (index, value) in order.enumerated() {
            XCTAssertEqual(
                ShellFocusTraversal.adjacent(to: value, direction: .forward, pageIDs: [first, second]),
                order[(index + 1) % order.count]
            )
            XCTAssertEqual(
                ShellFocusTraversal.adjacent(to: value, direction: .reverse, pageIDs: [first, second]),
                order[(index - 1 + order.count) % order.count]
            )
        }
        XCTAssertEqual(ShellFocusTraversal.adjacent(to: nil, direction: .forward, pageIDs: [first]), .navigatorPages)
        XCTAssertEqual(ShellFocusTraversal.adjacent(to: nil, direction: .reverse, pageIDs: [second]), .inspectorAccessibility)
    }

    // SF-0201-008, SF-0203-008, SF-1902-008
    @MainActor
    func testShellRequirementTraceabilityIsComplete() {
        let requirementIDs = WorkspaceShellState.requirementIDs

        XCTAssertEqual(
            requirementIDs,
            [
                "SF-0201-002", "SF-0201-004", "SF-0201-006", "SF-0201-008",
                "SF-0203-006", "SF-0203-008", "SF-0602-002", "SF-0602-006",
                "SF-1902-006", "SF-1902-008",
                "SF-0401-001", "SF-0401-002", "SF-0401-003", "SF-0401-004",
                "SF-0401-005", "SF-0401-006", "SF-0401-007", "SF-0401-008",
            ]
        )
    }
}
