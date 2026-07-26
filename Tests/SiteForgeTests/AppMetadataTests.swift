import AppKit
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

    // SF-0201-006, SF-0201-008, SF-1902-006, SF-1902-008
    @MainActor
    func testViewportPresetFocusGateAdoptsOnlyCurrentSceneWindowAndRequest() {
        let scene = ViewportPresetFocusSceneID(
            UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        )
        let otherScene = ViewportPresetFocusSceneID(
            UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        )
        let window = ViewportPresetWindowIdentity(window: NSWindow())
        let otherWindow = ViewportPresetWindowIdentity(window: NSWindow())
        let request = ViewportPresetFocusRequest(
            sceneID: scene,
            requestID: UUID(uuidString: "42000000-0000-0000-0000-000000000001")!
        )
        let staleRequest = ViewportPresetFocusRequest(
            sceneID: scene,
            requestID: UUID(uuidString: "42000000-0000-0000-0000-000000000002")!
        )
        let wrongSceneRequest = ViewportPresetFocusRequest(
            sceneID: otherScene,
            requestID: request.requestID
        )
        var gate = ViewportPresetFocusGate(sceneID: scene)

        gate.activate(request, in: window)
        XCTAssertEqual(gate.decision(for: request, in: window, isFirstResponder: false), .adopt)
        XCTAssertEqual(gate.decision(for: request, in: window, isFirstResponder: true), .alreadyFocused)
        XCTAssertEqual(gate.decision(for: staleRequest, in: window, isFirstResponder: false), .ignoreStaleRequest)
        XCTAssertEqual(gate.decision(for: wrongSceneRequest, in: window, isFirstResponder: false), .ignoreWrongScene)
        XCTAssertEqual(gate.decision(for: request, in: otherWindow, isFirstResponder: false), .ignoreWrongWindow)

        gate.cancel()
        XCTAssertEqual(gate.decision(for: request, in: window, isFirstResponder: false), .ignoreStaleRequest)
    }

    // SF-0201-006, SF-0201-008, SF-1902-006
    @MainActor
    func testViewportPresetFocusLossDoesNotReclaimWithoutANewRequest() {
        let scene = ViewportPresetFocusSceneID(
            UUID(uuidString: "43000000-0000-0000-0000-000000000001")!
        )
        let window = ViewportPresetWindowIdentity(window: NSWindow())
        let request = ViewportPresetFocusRequest(
            sceneID: scene,
            requestID: UUID(uuidString: "43000000-0000-0000-0000-000000000003")!
        )
        let nextRequest = ViewportPresetFocusRequest(
            sceneID: scene,
            requestID: UUID(uuidString: "43000000-0000-0000-0000-000000000004")!
        )
        var gate = ViewportPresetFocusGate(sceneID: scene)

        gate.activate(request, in: window)
        gate.markAdopted(request)
        gate.markRelinquished(request)
        XCTAssertEqual(
            gate.decision(for: request, in: window, isFirstResponder: false),
            .ignoreRelinquishedRequest
        )

        gate.activate(nextRequest, in: window)
        XCTAssertEqual(gate.decision(for: nextRequest, in: window, isFirstResponder: false), .adopt)
    }

    // SF-0201-006, SF-0201-008, SF-1902-006
    func testViewportPresetNativeContractSynchronizesSelectionAndAccessibility() {
        XCTAssertEqual(ViewportPresetControlContract.accessibilityIdentifier, "canvas.viewport.preset")
        XCTAssertEqual(ViewportPresetControlContract.accessibilityLabel, "Viewport preset")
        for (index, preset) in ViewportPreset.allCases.enumerated() {
            XCTAssertEqual(ViewportPresetControlContract.index(for: preset), index)
            XCTAssertEqual(ViewportPresetControlContract.preset(at: index), preset)
            XCTAssertEqual(ViewportPresetControlContract.accessibilityValue(for: preset), preset.title)
        }
        XCTAssertNil(ViewportPresetControlContract.preset(at: -1))
        XCTAssertNil(ViewportPresetControlContract.preset(at: ViewportPreset.allCases.count))
    }

    // SF-0201-006, SF-0201-008, SF-1902-006, SF-1902-008
    func testWindowNativeTabPolicyRoutesOnlyBothMixedFrameworkBoundaries() {
        let home = PageID(UUID(uuidString: "44000000-0000-0000-0000-000000000001")!)
        let notFound = PageID(UUID(uuidString: "44000000-0000-0000-0000-000000000002")!)
        let context = WorkspaceTabRoutingContext(
            isWorkspaceWindowEvent: true,
            isKeyWindow: true,
            hasAttachedSheet: false,
            isTextEditing: false,
            hasTransientPresentation: false
        )

        XCTAssertEqual(
            WorkspaceTabRoutingPolicy.decision(
                from: .navigatorPage(notFound),
                direction: .forward,
                pageIDs: [home, notFound],
                context: context
            ),
            .route(.viewportPreset)
        )
        XCTAssertEqual(
            WorkspaceTabRoutingPolicy.decision(
                from: .viewportPreset,
                direction: .forward,
                pageIDs: [home, notFound],
                context: context
            ),
            .route(.viewportZoomOut)
        )
        XCTAssertEqual(
            WorkspaceTabRoutingPolicy.decision(
                from: .viewportZoomOut,
                direction: .reverse,
                pageIDs: [home, notFound],
                context: context
            ),
            .route(.viewportPreset)
        )
        XCTAssertEqual(
            WorkspaceTabRoutingPolicy.decision(
                from: .viewportPreset,
                direction: .reverse,
                pageIDs: [home, notFound],
                context: context
            ),
            .route(.navigatorPage(notFound))
        )
        XCTAssertEqual(
            WorkspaceTabRoutingPolicy.decision(
                from: .navigatorPages,
                direction: .forward,
                pageIDs: [home, notFound],
                context: context
            ),
            .passThrough(.notMixedFrameworkBoundary)
        )
    }

    // SF-0201-006, SF-0201-008, SF-1902-008
    func testWindowNativeTabPolicyRejectsEveryUnsafePresentationContext() {
        let page = PageID(UUID(uuidString: "45000000-0000-0000-0000-000000000001")!)
        let safe = WorkspaceTabRoutingContext(
            isWorkspaceWindowEvent: true,
            isKeyWindow: true,
            hasAttachedSheet: false,
            isTextEditing: false,
            hasTransientPresentation: false
        )

        let cases: [(WorkspaceTabRoutingContext, WorkspaceTabRoutingPassReason)] = [
            (.init(
                isWorkspaceWindowEvent: false,
                isKeyWindow: true,
                hasAttachedSheet: false,
                isTextEditing: false,
                hasTransientPresentation: false
            ), .wrongWindow),
            (.init(
                isWorkspaceWindowEvent: true,
                isKeyWindow: false,
                hasAttachedSheet: false,
                isTextEditing: false,
                hasTransientPresentation: false
            ), .inactiveWindow),
            (.init(
                isWorkspaceWindowEvent: true,
                isKeyWindow: true,
                hasAttachedSheet: true,
                isTextEditing: false,
                hasTransientPresentation: false
            ), .attachedSheet),
            (.init(
                isWorkspaceWindowEvent: true,
                isKeyWindow: true,
                hasAttachedSheet: false,
                isTextEditing: true,
                hasTransientPresentation: false
            ), .textEditing),
            (.init(
                isWorkspaceWindowEvent: true,
                isKeyWindow: true,
                hasAttachedSheet: false,
                isTextEditing: false,
                hasTransientPresentation: true
            ), .transientPresentation),
        ]
        for (context, reason) in cases {
            XCTAssertEqual(
                WorkspaceTabRoutingPolicy.decision(
                    from: .navigatorPage(page),
                    direction: .forward,
                    pageIDs: [page],
                    context: context
                ),
                .passThrough(reason)
            )
        }
        XCTAssertEqual(
            WorkspaceTabRoutingPolicy.decision(
                from: nil,
                direction: .forward,
                pageIDs: [page],
                context: safe
            ),
            .passThrough(.noLogicalFocus)
        )
    }

    // SF-0201-008, SF-1902-008
    @MainActor
    func testWindowNativeTabRouterLifecycleRejectsStaleAndWrongWindowIdentity() {
        let first = NSWindow()
        let second = NSWindow()
        let firstID = WorkspaceTabRouterWindowIdentity(window: first)
        let secondID = WorkspaceTabRouterWindowIdentity(window: second)
        var lifecycle = WorkspaceTabRouterLifecycle()

        lifecycle.bind(to: firstID)
        let firstGeneration = lifecycle.generation
        XCTAssertTrue(lifecycle.accepts(firstID, generation: firstGeneration))
        XCTAssertFalse(lifecycle.accepts(secondID, generation: firstGeneration))

        lifecycle.bind(to: secondID)
        let secondGeneration = lifecycle.generation
        XCTAssertFalse(lifecycle.accepts(firstID, generation: firstGeneration))
        XCTAssertFalse(lifecycle.accepts(secondID, generation: firstGeneration))
        XCTAssertTrue(lifecycle.accepts(secondID, generation: secondGeneration))

        lifecycle.unbind(from: firstID)
        XCTAssertTrue(lifecycle.accepts(secondID, generation: secondGeneration))
        lifecycle.unbind(from: secondID)
        XCTAssertFalse(lifecycle.accepts(secondID, generation: secondGeneration))
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
                "SF-0402-001", "SF-0402-002", "SF-0402-003", "SF-0402-004",
                "SF-0402-005", "SF-0402-006", "SF-0402-007", "SF-0402-008",
                "SF-0403-001", "SF-0403-002", "SF-0403-003", "SF-0403-004",
                "SF-0403-005", "SF-0403-006", "SF-0403-007", "SF-0403-008",
                "SF-0405-001", "SF-0405-002", "SF-0405-003", "SF-0405-004",
                "SF-0405-005", "SF-0405-006", "SF-0405-007", "SF-0405-008",
            ]
        )
    }
}
