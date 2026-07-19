import SwiftUI
import XCTest
@testable import SiteForge

final class WorkspaceMaterialPolicyTests: XCTestCase {
    private let standard = WorkspaceMaterialEnvironment(
        reduceTransparency: false,
        contrast: .standard,
        appearance: .light,
        activity: .active
    )

    // SF-0201-003, SF-0201-008
    func testEveryChromeRegionHasOneDeterministicNativeMaterialPolicy() {
        let resolved = WorkspaceChromeRegion.allCases.map {
            WorkspaceMaterialPolicy.resolve(region: $0, environment: standard)
        }
        XCTAssertEqual(resolved.map(\.region), WorkspaceChromeRegion.allCases)
        XCTAssertTrue(resolved.allSatisfy { $0.presentation == .translucent })
        XCTAssertEqual(resolved.first { $0.region == .titlebar }?.material, .titlebar)
        XCTAssertEqual(resolved.first { $0.region == .navigator }?.material, .sidebar)
        XCTAssertEqual(resolved.first { $0.region == .inspector }?.material, .sidebar)
        XCTAssertEqual(resolved.first { $0.region == .viewportControls }?.material, .header)
        XCTAssertEqual(resolved.first { $0.region == .statusBar }?.material, .status)
    }

    // SF-0201-003, SF-1605-002
    func testReduceTransparencySelectsIntentionalOpaqueFallbackEverywhere() {
        var environment = standard
        environment.reduceTransparency = true
        for region in WorkspaceChromeRegion.allCases {
            let style = WorkspaceMaterialPolicy.resolve(region: region, environment: environment)
            XCTAssertEqual(style.presentation, .opaque)
            XCTAssertGreaterThanOrEqual(style.separatorOpacity, 0.5)
            XCTAssertTrue(style.accessibilityDescription.contains("Opaque"))
        }
    }

    // SF-0201-006, SF-1505-006, SF-1605-006
    func testIncreasedContrastStrengthensBoundariesWithoutChangingSemantics() {
        var increased = standard
        increased.contrast = .increased
        for region in WorkspaceChromeRegion.allCases {
            let normal = WorkspaceMaterialPolicy.resolve(region: region, environment: standard)
            let strong = WorkspaceMaterialPolicy.resolve(region: region, environment: increased)
            XCTAssertEqual(normal.material, strong.material)
            XCTAssertGreaterThan(strong.separatorOpacity, normal.separatorOpacity)
        }
    }

    // SF-0201-003, SF-0201-006
    func testLightDarkAndAccentIndependentPolicyUsesNativeDynamicAppearance() {
        var dark = standard
        dark.appearance = .dark
        for region in WorkspaceChromeRegion.allCases {
            XCTAssertEqual(
                WorkspaceMaterialPolicy.resolve(region: region, environment: standard).material,
                WorkspaceMaterialPolicy.resolve(region: region, environment: dark).material
            )
        }
        XCTAssertEqual(
            WorkspaceMaterialPolicy.preferredColorScheme(arguments: ["SiteForge", "-SiteForgeAppearance", "light"]),
            .light
        )
        XCTAssertEqual(
            WorkspaceMaterialPolicy.preferredColorScheme(arguments: ["SiteForge", "-SiteForgeAppearance", "dark"]),
            .dark
        )
    }

    // SF-0201-003, SF-0201-006
    func testInactiveWindowDeemphasizesRecoveryAndRetainsReadableBoundary() {
        var inactive = standard
        inactive.activity = .inactive
        let activeStyle = WorkspaceMaterialPolicy.resolve(region: .recoveryBar, environment: standard)
        let inactiveStyle = WorkspaceMaterialPolicy.resolve(region: .recoveryBar, environment: inactive)
        XCTAssertTrue(activeStyle.isEmphasized)
        XCTAssertFalse(inactiveStyle.isEmphasized)
        XCTAssertGreaterThan(inactiveStyle.separatorOpacity, 0)
    }

    // SF-0201-002, SF-0201-007
    func testMinimumAndResizedWindowLayoutsRemainValid() {
        XCTAssertTrue(WorkspaceMetrics.supportsLayout(at: WorkspaceMetrics.minimumWindowSize))
        XCTAssertTrue(WorkspaceMetrics.supportsLayout(at: WorkspaceMetrics.defaultWindowSize))
        XCTAssertTrue(WorkspaceMetrics.supportsLayout(at: CGSize(width: 1_800, height: 1_100)))
        XCTAssertFalse(WorkspaceMetrics.supportsLayout(at: CGSize(width: 1_099, height: 700)))
        XCTAssertEqual(
            WorkspaceMetrics.requestedWindowSize(arguments: ["SiteForge", "-SiteForgeWindowSize", "minimum"]),
            WorkspaceMetrics.minimumWindowSize
        )
        XCTAssertNil(WorkspaceMetrics.requestedWindowSize(arguments: ["SiteForge"]))
    }

    // SF-0201-007, SF-1505-007, SF-1605-007
    func testLargeFixtureAndMaterialResolutionStayWithinFoundationBudget() {
        let clock = ContinuousClock()
        let fixtureElapsed = clock.measure { _ = WorkspaceFixtureScale.large.document() }
        let policyElapsed = clock.measure {
            for index in 0..<10_000 {
                let region = WorkspaceChromeRegion.allCases[index % WorkspaceChromeRegion.allCases.count]
                _ = WorkspaceMaterialPolicy.resolve(region: region, environment: standard)
            }
        }
        XCTAssertLessThan(fixtureElapsed, .seconds(2))
        XCTAssertLessThan(policyElapsed, .seconds(1))
    }

    // SF-0201-008, SF-1505-008, SF-1605-008
    func testRequirementTraceabilityIsExact() {
        XCTAssertEqual(WorkspaceMaterialPolicy.requirementIDs, [
            "SF-0201-002", "SF-0201-003", "SF-0201-006", "SF-0201-007", "SF-0201-008",
            "SF-1505-006", "SF-1505-007", "SF-1505-008",
            "SF-1605-002", "SF-1605-006", "SF-1605-007", "SF-1605-008",
        ])
    }

    // SF-0201-002, SF-0201-006
    @MainActor
    func testCanvasInteractionStateIsUIOnly() {
        let state = WorkspaceShellState()
        let canonical = state.documentSession.document
        state.noteCanvasInteraction()
        XCTAssertEqual(state.canvasInteractionCount, 1)
        XCTAssertEqual(state.documentSession.document, canonical)
    }
}
