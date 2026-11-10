import AppKit
import SwiftUI
import XCTest
@testable import SiteForge

final class WorkspaceMaterialPolicyTests: XCTestCase {
    // SF-LOCAL-BUILDER-014 / SF-0201-009, SF-0701-006.
    @MainActor
    func testMeasuredSidebarTabsHonorActualPaneBudgetAtNormalCompactAndIncreasedText() {
        let gutters = 2 * (SiteForgeVisualSystem.panePadding + SiteForgeVisualSystem.tabStripInset)
        let gap = Double(SiteForgeVisualSystem.hairlineSpacing)
        for window in [CGFloat(1100), 1182, 1200, 1278, 1280, 1440, 1710, 2560] {
            for font in [CGFloat(12), 18, 24] {
                let face = NSFont.systemFont(ofSize: font, weight: .semibold)
                let height = ShellTabLayoutPolicy.rowHeight(fontSize: font)
                XCTAssertGreaterThanOrEqual(height, ceil(face.ascender - face.descender + face.leading)
                    + 2 * SiteForgeVisualSystem.compactSpacing)
                if font == 12 { XCTAssertEqual(height, SiteForgeVisualSystem.tabStripHeight) }
                let nav = ShellTabLayoutPolicy.measuredMinimumWidths(labels: NavigatorTab.allCases.map(\.title), fontSize: font)
                let inspector = ShellTabLayoutPolicy.measuredMinimumWidths(labels: InspectorTab.allCases.map(\.title), fontSize: font)
                let panes = WorkspaceMetrics.sidePaneAllocation(windowWidth: window,
                    navigatorRequired: gutters + CGFloat(ShellTabLayoutPolicy.requiredWidth(minimumWidths: nav, gap: gap)),
                    inspectorRequired: gutters + CGFloat(ShellTabLayoutPolicy.requiredWidth(minimumWidths: inspector, gap: gap)))
                XCTAssertLessThanOrEqual(panes.navigatorMinimum, panes.navigatorMaximum)
                XCTAssertLessThanOrEqual(panes.inspectorMinimum, panes.inspectorMaximum)
                XCTAssertGreaterThanOrEqual(window - panes.navigatorMaximum - panes.inspectorMaximum - 2,
                    WorkspaceMetrics.minimumCanvasWidth.nextDown) // one floating-point ULP, not a visual-point tolerance
                for (labels, lower, upper) in [(nav, panes.navigatorMinimum, panes.navigatorMaximum),
                                               (inspector, panes.inspectorMinimum, panes.inspectorMaximum)] {
                    for pane in [lower, (lower + upper) / 2, upper] {
                        let available = Double(pane - gutters)
                        for selected in labels.indices {
                            let result = ShellTabLayoutPolicy.allocate(width: available, minimumWidths: labels, selected: selected, gap: gap)
                            XCTAssertEqual(result.overflow, ShellTabLayoutPolicy.requiredWidth(minimumWidths: labels, gap: gap) > available)
                            if window >= 1280, font == 12 { XCTAssertFalse(result.overflow) }
                            XCTAssertTrue(result.indices.contains(selected) || (result.overflow && result.indices.isEmpty))
                            XCTAssertEqual(result.indices, result.indices.sorted())
                            for (offset, index) in result.indices.enumerated() {
                                XCTAssertGreaterThanOrEqual(result.widths[offset], labels[index])
                            }
                            let gaps = max(0, result.indices.count - 1) + (result.overflow && !result.indices.isEmpty ? 1 : 0)
                            XCTAssertEqual(result.widths.reduce(0, +) + Double(gaps) * gap + result.menuWidth, available, accuracy: 0.001)
                        }
                    }
                }
            }
        }
        let invalid = WorkspaceMetrics.sidePaneAllocation(windowWidth: .nan, navigatorRequired: .infinity, inspectorRequired: .nan)
        XCTAssertTrue(invalid.navigatorMinimum.isFinite && invalid.inspectorMinimum.isFinite)
    }

    func testInspectorActionFlowKeepsLongActionsOrderedContainedAndNonoverlapping() {
        for width in [CGFloat(208), 232, 280, 308, 336, 372] {
            for scale in [CGFloat(1), 1.5, 2] {
                let sizes = [CGSize(width: 140 * scale, height: 24 * scale),
                             CGSize(width: 105 * scale, height: 24 * scale),
                             CGSize(width: 330 * scale, height: 48 * scale),
                             CGSize(width: 80 * scale, height: 24 * scale)]
                let frames = InspectorControlLayoutPolicy.actionFrames(sizes: sizes, width: width, spacing: 8)
                XCTAssertEqual(frames.count, sizes.count)
                for index in frames.indices {
                    XCTAssertGreaterThanOrEqual(frames[index].minX, 0)
                    XCTAssertLessThanOrEqual(frames[index].maxX, width)
                    XCTAssertEqual(frames[index].height, sizes[index].height)
                    for previous in frames.indices where previous < index {
                        XCTAssertFalse(frames[index].intersects(frames[previous]))
                        XCTAssertTrue(frames[index].minY > frames[previous].minY || frames[index].minX > frames[previous].minX)
                    }
                }
            }
        }
        XCTAssertTrue(InspectorControlLayoutPolicy.actionFrames(sizes: [.init(width: CGFloat.infinity, height: 20)], width: 232, spacing: 8).isEmpty)
    }

    func testInspectorFieldColumnsUseCompleteMinimumsInsteadOfSqueezingOrTinyType() {
        for minimum in [CGFloat(96), 144, 192] {
            for width in [CGFloat(208), 232, 280, 308, 336, 372] {
                let count = InspectorControlLayoutPolicy.columnCount(width: width, minimum: minimum, count: 3, maximum: 3, spacing: 12)
                XCTAssertTrue((1...3).contains(count))
                let fieldWidth = (width - CGFloat(count - 1) * 12) / CGFloat(count)
                XCTAssertGreaterThanOrEqual(fieldWidth, min(width, minimum))
                if count < 3 { XCTAssertGreaterThan(CGFloat(count + 1) * minimum + CGFloat(count) * 12, width) }
            }
        }
        XCTAssertEqual(InspectorControlLayoutPolicy.columnCount(width: .nan, minimum: 96, count: 3, maximum: 3, spacing: 12), 1)
    }

    @MainActor
    func testNativeOverflowPaintsTheDisplayedPullDownItemAndRetainsAccessibleControl() throws {
        let button = ShellTabOverflowPopUpButton(frame: .init(x: 0, y: 0, width: 28, height: 28), pullsDown: true)
        button.addItems(withTitles: ["", "Pages", "Layers"])
        button.updateDisplayedItem(title: "Pages", fullWidth: false, fontSize: 12)
        let displayed = try XCTUnwrap(button.item(at: 0))
        XCTAssertNotNil(displayed.image, "A pull-down menu must paint the first item's icon, not a hidden NSButton.image")
        XCTAssertTrue(displayed.image?.isTemplate == true)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertTrue(button.acceptsFirstResponder)
        XCTAssertTrue(button.canBecomeKeyView)
        button.updateDisplayedItem(title: "Layers", fullWidth: true, fontSize: 24)
        XCTAssertEqual(displayed.title, "Layers")
        XCTAssertEqual(button.imagePosition, .imageTrailing)
        XCTAssertEqual(button.font?.pointSize, 24)
        XCTAssertEqual(button.menu?.font.pointSize, 24)
        XCTAssertEqual(button.numberOfItems, 3)
    }

    func testSelectedReferencePaneAllocationKeepsCanvasDominantAtMinimumAndMaximizedWidths() {
        for width in [CGFloat(1100), 1280, 1536, 1710, 2560] {
            let navigator = WorkspaceMetrics.navigatorMaximumWidth(for: width)
            let inspector = WorkspaceMetrics.inspectorMaximumWidth(for: width)
            XCTAssertTrue(WorkspaceMetrics.navigatorWidth.contains(navigator))
            XCTAssertTrue(WorkspaceMetrics.inspectorWidth.contains(inspector))
            XCTAssertGreaterThanOrEqual(width - navigator - inspector - 2, WorkspaceMetrics.minimumCanvasWidth)
            XCTAssertGreaterThanOrEqual(inspector, navigator)
        }
        XCTAssertEqual(WorkspaceMetrics.navigatorMaximumWidth(for: 1536), 360, accuracy: 0.001)
        XCTAssertEqual(WorkspaceMetrics.inspectorMaximumWidth(for: 1536), 420, accuracy: 0.001)
    }

    @MainActor
    func testNormalPaneMinimaFitAllFiveMeasuredDestinationLabelsWithoutOverflow() {
        for width in [CGFloat(1280), 1440, 1710, 2560] {
            for (labels, paneWidth) in [
                (NavigatorTab.allCases.map(\.title), WorkspaceMetrics.navigatorMinimumWidth(for: width)),
                (InspectorTab.allCases.map(\.title), WorkspaceMetrics.inspectorMinimumWidth(for: width)),
            ] {
                let minima = labels.map { Double(ceil(($0 as NSString).size(withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                ]).width) + SiteForgeVisualSystem.microSpacing * 2) }
                let available = Double(paneWidth - 2 * SiteForgeVisualSystem.panePadding - 2 * SiteForgeVisualSystem.tabStripInset)
                for selected in minima.indices {
                    let result = ShellTabLayoutPolicy.allocate(width: available, minimumWidths: minima,
                        selected: selected, gap: Double(SiteForgeVisualSystem.hairlineSpacing))
                    XCTAssertFalse(result.overflow, "All normal-size destinations must be directly visible: \(labels)")
                    XCTAssertEqual(result.indices, Array(minima.indices))
                    for index in minima.indices { XCTAssertGreaterThanOrEqual(result.widths[index], minima[index]) }
                }
            }
        }
        XCTAssertEqual(WorkspaceMetrics.navigatorMinimumWidth(for: 1100), 250)
        XCTAssertEqual(WorkspaceMetrics.inspectorMinimumWidth(for: 1100), 280)
    }
    func testConceptAlignedSettingsHasOneSidebarIncludingInheritedAccessibility() {
        XCTAssertEqual(SettingsDestination.allCases.map(\.rawValue),
                       ["appearance", "canvas", "accessibility", "defaults", "updates", "support", "advanced"])
        XCTAssertEqual(Set(SettingsDestination.allCases.map(\.title)).count,
                       SettingsDestination.allCases.count)
        XCTAssertTrue(SettingsDestination.allCases.allSatisfy { !$0.symbol.isEmpty })
        XCTAssertEqual(SiteForgeVisualSystem.navigatorIdealWidth, 344)
        XCTAssertEqual(SiteForgeVisualSystem.inspectorIdealWidth, 384)
        XCTAssertGreaterThanOrEqual(SiteForgeVisualSystem.inspectorBottomClearance, 80)
    }

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
            XCTAssertEqual(style.blending, .withinWindow)
            XCTAssertGreaterThanOrEqual(style.separatorOpacity, 0.5)
            XCTAssertTrue(style.accessibilityDescription.contains("Opaque"))
        }
    }

    // SF-0201-009 — only workspace side panes sample behind the window;
    // the viewport header/status stay bounded inside the document window.
    func testFrostedSidePanesKeepOpaqueAccessibilityFallbackAndCanvasSeparation() {
        for region in WorkspaceChromeRegion.allCases {
            let standardStyle = WorkspaceMaterialPolicy.resolve(region: region, environment: standard)
            let expected: WorkspaceMaterialBlending = region == .navigator || region == .inspector
                ? .behindWindow : .withinWindow
            XCTAssertEqual(standardStyle.blending, expected, "Unexpected blend at \(region)")

            var reduced = standard
            reduced.reduceTransparency = true
            let fallback = WorkspaceMaterialPolicy.resolve(region: region, environment: reduced)
            XCTAssertEqual(fallback.presentation, .opaque)
            XCTAssertEqual(fallback.blending, .withinWindow)
            XCTAssertGreaterThan(fallback.separatorOpacity, standardStyle.separatorOpacity)
        }
    }

    // SF-0201-009 — the native decoration is not an input or AX target.
    @MainActor
    func testNativeMaterialDecorationDoesNotInterceptPointerOrAccessibility() {
        let view = PassthroughVisualEffectView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        view.setAccessibilityElement(false)
        XCTAssertNil(view.hitTest(NSPoint(x: 80, y: 120)))
        XCTAssertFalse(view.isAccessibilityElement())
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

    // SF-0201-006, SF-0203-006, SF-1505-006, SF-1605-006 — the editor
    // workspace is deliberately distinct from its authored artboard in both
    // appearances, and normal pane widths can present five one-line labels.
    @MainActor
    func testDarkEditorialPaletteSeparatesChromeWithoutRecoloringWebsitePaper() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        var colors: [NSColor] = []
        appearance.performAsCurrentDrawingAppearance {
            colors = [SiteForgeVisualSystem.chromeSurfaceNSColor,
                      SiteForgeVisualSystem.elevatedSurfaceNSColor,
                      SiteForgeVisualSystem.canvasPasteboardNSColor,
                      SiteForgeVisualSystem.artboardSurfaceNSColor,
                      SiteForgeVisualSystem.chromeSelectionNSColor].compactMap {
                $0.usingColorSpace(.sRGB)
            }
        }
        XCTAssertEqual(colors.count, 5)
        let chrome = colors[0], elevated = colors[1], pasteboard = colors[2], paper = colors[3]
        XCTAssertLessThan(chrome.redComponent, elevated.redComponent)
        XCTAssertLessThan(elevated.redComponent, pasteboard.redComponent)
        XCTAssertLessThan(pasteboard.blueComponent, 0.30)
        XCTAssertGreaterThan(paper.redComponent, 0.98)
        XCTAssertEqual(paper.redComponent, paper.blueComponent, accuracy: 0.001)
        XCTAssertEqual(colors[4].alphaComponent, 0.20, accuracy: 0.001)
        XCTAssertTrue(colors.prefix(4).allSatisfy { $0.alphaComponent == 1 })
    }

    @MainActor
    func testVisualSystemSeparatesPasteboardArtboardAndSingleRowPaneDestinations() throws {
        func luminance(_ color: NSColor, appearance: NSAppearance.Name) throws -> CGFloat {
            let nativeAppearance = try XCTUnwrap(NSAppearance(named: appearance))
            var resolved: NSColor?
            nativeAppearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.deviceRGB)
            }
            let rgb = try XCTUnwrap(resolved)
            return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let nativeAppearance = try XCTUnwrap(NSAppearance(named: appearance))
            var fallbackAlphas: [CGFloat] = []
            nativeAppearance.performAsCurrentDrawingAppearance {
                fallbackAlphas = [SiteForgeVisualSystem.chromeSurfaceNSColor,
                                  SiteForgeVisualSystem.elevatedSurfaceNSColor].compactMap {
                    $0.usingColorSpace(.deviceRGB)?.alphaComponent
                }
            }
            XCTAssertEqual(fallbackAlphas, [1, 1],
                           "Reduce Transparency fallback surfaces must be opaque in each appearance")
            let chrome = try luminance(SiteForgeVisualSystem.chromeSurfaceNSColor, appearance: appearance)
            let pasteboard = try luminance(SiteForgeVisualSystem.canvasPasteboardNSColor, appearance: appearance)
            let artboard = try luminance(SiteForgeVisualSystem.artboardSurfaceNSColor, appearance: appearance)
            XCTAssertGreaterThan(abs(chrome - pasteboard), 0.03)
            XCTAssertGreaterThan(abs(artboard - pasteboard), 0.06)
        }
        XCTAssertEqual(SiteForgeVisualSystem.hairlineSpacing, 2)
        XCTAssertEqual(SiteForgeVisualSystem.tabStripInset, 3)
        XCTAssertEqual(SiteForgeVisualSystem.microSpacing, 4)
        XCTAssertEqual(SiteForgeVisualSystem.compactSpacing, 6)
        XCTAssertEqual(SiteForgeVisualSystem.controlInset, 8)
        XCTAssertEqual(SiteForgeVisualSystem.standardSpacing, 12)
        XCTAssertEqual(SiteForgeVisualSystem.sectionSpacing, 18)
        XCTAssertEqual(SiteForgeVisualSystem.panePadding, SiteForgeVisualSystem.standardSpacing)
        XCTAssertEqual(SiteForgeVisualSystem.gridUnit, 8)
        XCTAssertEqual(SiteForgeVisualSystem.launchInnerPadding, 32)
        XCTAssertEqual(SiteForgeVisualSystem.launchOuterPadding, 40)
        XCTAssertEqual(SiteForgeVisualSystem.settingsSidebarWidth, 250)
        XCTAssertGreaterThan(SiteForgeVisualSystem.settingsContentMaxWidth,
                             SiteForgeVisualSystem.settingsSidebarWidth)
        XCTAssertEqual(SiteForgeVisualSystem.navigatorIdealWidth, 344)
        XCTAssertEqual(SiteForgeVisualSystem.inspectorIdealWidth, 384)
        XCTAssertLessThan(SiteForgeVisualSystem.navigatorIdealWidth, SiteForgeVisualSystem.inspectorIdealWidth)
        XCTAssertTrue(WorkspaceMetrics.navigatorWidth.contains(SiteForgeVisualSystem.navigatorIdealWidth))
        XCTAssertTrue(WorkspaceMetrics.inspectorWidth.contains(SiteForgeVisualSystem.inspectorIdealWidth))
        XCTAssertLessThanOrEqual(
            SiteForgeVisualSystem.navigatorIdealWidth
                + SiteForgeVisualSystem.inspectorIdealWidth
                + WorkspaceMetrics.minimumCanvasWidth,
            WorkspaceMetrics.defaultWindowSize.width
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
        XCTAssertNil(
            WorkspaceMetrics.requestedWindowSize(arguments: ["SiteForge", "-SiteForgeUITestMode", "YES"]),
            "Generic UI automation must retain normal visible-frame presentation."
        )
        XCTAssertFalse(WorkspaceMetrics.usesDeterministicUITestPlacement(
            composition: DebugTestComposition(
                arguments: ["SiteForge", "-SiteForgeUITestMode", "YES"],
                enabled: true
            )
        ))
        XCTAssertNil(
            WorkspaceMetrics.requestedUITestWindowPlacement(composition: DebugTestComposition(
                arguments: ["SiteForge", "-SiteForgeUITestMode", "YES"],
                enabled: true
            ))
        )
        XCTAssertTrue(WorkspaceMetrics.usesNormalVisibleFramePresentation(
            composition: DebugTestComposition(arguments: ["SiteForge", "-SiteForgeUITestMode", "YES"], enabled: true)
        ))
        XCTAssertEqual(
            WorkspaceMetrics.effectiveMinimumWindowSize(composition: DebugTestComposition(
                arguments: ["SiteForge", "-SiteForgeUITestMode", "YES"],
                enabled: true
            )),
            WorkspaceMetrics.minimumWindowSize
        )
        XCTAssertNil(WorkspaceMetrics.requestedWindowSize(arguments: ["SiteForge"]))
    }

    // SF-0201-002, SF-0201-003, SF-0201-008
    @MainActor
    func testWorkspaceWindowRoleExcludesPanelsChildrenAndUnmarkedAuxiliaryWindows() {
        let workspace = NSWindow()
        XCTAssertFalse(WorkspaceWindowRolePolicy.isWorkspaceDocumentWindow(workspace))
        WorkspaceWindowRolePolicy.register(workspace)
        XCTAssertTrue(WorkspaceWindowRolePolicy.isWorkspaceDocumentWindow(workspace))

        let panel = NSPanel()
        WorkspaceWindowRolePolicy.register(panel)
        XCTAssertFalse(WorkspaceWindowRolePolicy.isWorkspaceDocumentWindow(panel))

        let auxiliary = NSWindow()
        XCTAssertFalse(WorkspaceWindowRolePolicy.isWorkspaceDocumentWindow(auxiliary))

        let child = NSWindow()
        WorkspaceWindowRolePolicy.register(child)
        workspace.addChildWindow(child, ordered: .above)
        XCTAssertFalse(WorkspaceWindowRolePolicy.isWorkspaceDocumentWindow(child))
        workspace.removeChildWindow(child)
    }

    // SF-0201-002, SF-0201-003, SF-0201-008 — presentation cannot lock a
    // genuine title-bar move back to the initial automation placement.
    @MainActor
    func testConstrainedWindowPresentationDoesNotUndoSubsequentNativeMovement() {
        let window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 1100, height: 650),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = WorkspaceWindowConfigurationView(frame: .zero)
        window.contentView?.addSubview(view)
        window.orderFront(nil)
        defer { view.detach(); view.removeFromSuperview(); window.close() }
        let composition = DebugTestComposition(arguments: ["SiteForge", "-SiteForgeUITestMode", "YES",
            "-SiteForgeUITestWindowAlignment", "left"], enabled: true)
        view.configureWindow(composition: composition)
        XCTAssertEqual(window.minSize.width, 1100)
        let moved = window.frame.offsetBy(dx: 80, dy: 0)
        window.setFrame(moved, display: true)
        let accepted = window.frame
        view.configureWindow(composition: composition)
        XCTAssertEqual(window.frame, accepted, "A view update must not reverse the user's move")
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)
        view.configureWindow(composition: composition)
        XCTAssertEqual(window.frame, accepted)
        XCTAssertEqual(window.minSize.width, 1100)
    }

    // SF-0201-002, SF-0201-003, SF-0201-008 — generic UI composition is a
    // normal visible-frame window; only a fresh explicit edge request differs.
    func testGenericAndConstrainedUITestPresentationPoliciesAreIsolated() {
        let generic = DebugTestComposition(arguments: ["SiteForge", "-SiteForgeUITestMode", "YES"], enabled: true)
        let constrained = DebugTestComposition(arguments: ["SiteForge", "-SiteForgeUITestMode", "YES", "-SiteForgeUITestWindowAlignment", "right"], enabled: true)
        XCTAssertTrue(WorkspaceMetrics.usesNormalVisibleFramePresentation(composition: generic))
        XCTAssertFalse(WorkspaceMetrics.usesDeterministicUITestPlacement(composition: generic))
        XCTAssertFalse(WorkspaceMetrics.usesNormalVisibleFramePresentation(composition: constrained))
        XCTAssertTrue(WorkspaceMetrics.usesDeterministicUITestPlacement(composition: constrained))
        // A fresh generic composition owns no state from the prior request.
        XCTAssertTrue(WorkspaceMetrics.usesNormalVisibleFramePresentation(composition: generic))
    }

    // SF-0201-002, SF-0201-003, SF-0201-008
    func testNormalWindowPresentationUsesUsableScreenAndSafelyRetainsRestoration() {
        let visible = CGRect(x: 0, y: 24, width: 1_800, height: 1_076)
        let minimumFrame = CGSize(width: 1_100, height: 752)
        let restored = CGRect(x: 180, y: 120, width: 1_240, height: 820)

        XCTAssertTrue(WorkspaceWindowPresentation.acceptsRestoredFrame(
            restored,
            visibleFrame: visible,
            minimumFrameSize: minimumFrame
        ))
        XCTAssertEqual(
            WorkspaceWindowPresentation.initialFrame(
                visibleFrame: visible,
                restoredFrame: restored,
                minimumFrameSize: minimumFrame
            ),
            restored
        )
        XCTAssertEqual(
            WorkspaceWindowPresentation.initialFrame(
                visibleFrame: visible,
                restoredFrame: CGRect(x: -1_500, y: 0, width: 1_240, height: 820),
                minimumFrameSize: minimumFrame
            ),
            visible,
            "An invalid old-display frame must fall back to the normal usable display, never fullscreen."
        )
    }

    // SF-0201-002, SF-0201-008
    func testNormalWindowPresentationRejectsUndersizedAndMalformedRestoration() {
        let visible = CGRect(x: 0, y: 24, width: 1_600, height: 900)
        let minimumFrame = CGSize(width: 1_100, height: 752)
        XCTAssertFalse(WorkspaceWindowPresentation.acceptsRestoredFrame(
            CGRect(x: 20, y: 20, width: 1_099, height: 752),
            visibleFrame: visible,
            minimumFrameSize: minimumFrame
        ))
        XCTAssertFalse(WorkspaceWindowPresentation.acceptsRestoredFrame(
            CGRect(x: CGFloat.nan, y: 20, width: 1_200, height: 800),
            visibleFrame: visible,
            minimumFrameSize: minimumFrame
        ))
    }

    // SF-0201-002, SF-0201-008 — a narrow display must not compress the
    // production workspace or lose its trailing controls. It remains a normal
    // usable-frame window, aligned to the visible right edge.
    func testNormalWindowPresentationPreservesMinimumWidthOnNarrowDisplay() {
        let visible = CGRect(x: 0, y: 31, width: 1_024, height: 737)
        let minimumFrame = CGSize(width: 1_100, height: 752)
        let frame = WorkspaceWindowPresentation.initialFrame(
            visibleFrame: visible,
            restoredFrame: nil,
            minimumFrameSize: minimumFrame
        )
        XCTAssertEqual(frame, CGRect(x: -76, y: 31, width: 1_100, height: 737))
        XCTAssertEqual(frame.maxX, visible.maxX)
        XCTAssertEqual(frame.height, visible.height)
    }

    // SF-0201-002, SF-0201-006, SF-0201-008 — only the explicit minimum
    // override uses compact geometry; the normal path still consumes the
    // complete AppKit visible frame (menu bar and Dock remain outside it).
    func testExplicitMinimumWindowFrameIsClampedWithoutBecomingNormalPresentation() {
        let visible = CGRect(x: 0, y: 74, width: 1_710, height: 999)
        let explicit = WorkspaceExplicitWindowPresentation.frame(
            requestedFrameSize: CGSize(width: 1_100, height: 752),
            currentOrigin: CGPoint(x: 900, y: 900),
            visibleFrame: visible
        )
        XCTAssertEqual(explicit, CGRect(x: 610, y: 321, width: 1_100, height: 752))
        XCTAssertEqual(
            WorkspaceWindowPresentation.initialFrame(
                visibleFrame: visible,
                restoredFrame: nil,
                minimumFrameSize: explicit.size
            ),
            visible
        )
    }

    // SF-0201-008, SF-1605-008, SF-1902-008
    func testConstrainedDisplayPlacementPreservesProductionMetricsAndExposesEveryRequestedEdge() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_024, height: 768)
        let windowFrame = CGRect(
            origin: .zero,
            size: WorkspaceMetrics.minimumWindowSize
        )

        let leftTop = WorkspaceMetrics.uiTestWindowFrame(
            windowFrame: windowFrame,
            visibleFrame: visibleFrame,
            placement: WorkspaceUITestWindowPlacement(horizontal: .left, vertical: .top)
        )
        let rightTop = WorkspaceMetrics.uiTestWindowFrame(
            windowFrame: windowFrame,
            visibleFrame: visibleFrame,
            placement: WorkspaceUITestWindowPlacement(horizontal: .right, vertical: .top)
        )
        let leftBottom = WorkspaceMetrics.uiTestWindowFrame(
            windowFrame: windowFrame,
            visibleFrame: visibleFrame,
            placement: WorkspaceUITestWindowPlacement(horizontal: .left, vertical: .bottom)
        )
        let rightBottom = WorkspaceMetrics.uiTestWindowFrame(
            windowFrame: windowFrame,
            visibleFrame: visibleFrame,
            placement: WorkspaceUITestWindowPlacement(horizontal: .right, vertical: .bottom)
        )

        XCTAssertEqual(leftTop, CGRect(x: 16, y: 52, width: 1_100, height: 700))
        XCTAssertEqual(rightTop, CGRect(x: -92, y: 52, width: 1_100, height: 700))
        XCTAssertEqual(leftBottom, CGRect(x: 16, y: 16, width: 1_100, height: 700))
        XCTAssertEqual(rightBottom, CGRect(x: -92, y: 16, width: 1_100, height: 700))
        XCTAssertEqual(leftTop.minX, visibleFrame.minX + WorkspaceMetrics.uiTestScreenEdgeInset)
        XCTAssertEqual(
            rightTop.maxX,
            visibleFrame.maxX - WorkspaceMetrics.uiTestScreenEdgeInset
        )
        XCTAssertEqual(
            leftTop.maxY,
            visibleFrame.maxY - WorkspaceMetrics.uiTestScreenEdgeInset
        )
        XCTAssertEqual(
            leftBottom.minY,
            visibleFrame.minY + WorkspaceMetrics.uiTestScreenEdgeInset
        )
        XCTAssertEqual(WorkspaceMetrics.minimumWindowSize, CGSize(width: 1_100, height: 700))
        let topComposition = DebugTestComposition(
            arguments: [
                "SiteForge",
                "-SiteForgeUITestMode", "YES",
                "-SiteForgeUITestWindowVerticalAlignment", "top",
            ],
            enabled: true
        )
        let bottomComposition = DebugTestComposition(
            arguments: [
                "SiteForge",
                "-SiteForgeUITestMode", "YES",
                "-SiteForgeUITestWindowVerticalAlignment", "bottom",
            ],
            enabled: true
        )
        XCTAssertEqual(
            WorkspaceMetrics.effectiveMinimumWindowSize(composition: topComposition),
            CGSize(width: 1_100, height: 1)
        )
        XCTAssertEqual(
            WorkspaceMetrics.effectiveMinimumWindowSize(composition: bottomComposition),
            CGSize(width: 1_100, height: 1)
        )
        XCTAssertEqual(
            WorkspaceMetrics.requestedWindowFrameSize(
                contentSize: WorkspaceMetrics.minimumWindowSize,
                currentFrameSize: CGSize(width: 1_100, height: 677),
                currentContentLayoutSize: CGSize(width: 1_100, height: 625)
            ),
            CGSize(width: 1_100, height: 752)
        )

        let hostedVisibleFrame = CGRect(x: 0, y: 0, width: 1_024, height: 737)
        let productionMinimumWindowFrame = CGRect(x: 0, y: 0, width: 1_100, height: 752)
        let hostedBottom = WorkspaceMetrics.uiTestWindowFrame(
            windowFrame: productionMinimumWindowFrame,
            visibleFrame: hostedVisibleFrame,
            placement: WorkspaceUITestWindowPlacement(horizontal: .left, vertical: .bottom)
        )
        let hostedTop = WorkspaceMetrics.uiTestWindowFrame(
            windowFrame: productionMinimumWindowFrame,
            visibleFrame: hostedVisibleFrame,
            placement: WorkspaceUITestWindowPlacement(horizontal: .left, vertical: .top)
        )
        XCTAssertEqual(hostedBottom, CGRect(x: 16, y: 16, width: 1_100, height: 705))
        XCTAssertEqual(hostedTop, CGRect(x: 16, y: 16, width: 1_100, height: 705))
        XCTAssertEqual(
            hostedBottom.maxY,
            hostedVisibleFrame.maxY - WorkspaceMetrics.uiTestScreenEdgeInset,
            "Only explicit Debug/UI-test frames fit vertically while keeping both safe display edges available."
        )
        XCTAssertEqual(
            hostedTop.height,
            hostedBottom.height,
            "Top and bottom placement must share the same deterministic hosted height."
        )
        let hostedRightBottom = WorkspaceMetrics.uiTestWindowFrame(
            windowFrame: productionMinimumWindowFrame,
            visibleFrame: hostedVisibleFrame,
            placement: WorkspaceUITestWindowPlacement(horizontal: .right, vertical: .bottom)
        )
        XCTAssertEqual(hostedRightBottom.width, WorkspaceMetrics.minimumWindowSize.width)
        XCTAssertEqual(hostedRightBottom.maxX, hostedVisibleFrame.maxX - WorkspaceMetrics.uiTestScreenEdgeInset)
        XCTAssertEqual(hostedRightBottom.minY, hostedVisibleFrame.minY + WorkspaceMetrics.uiTestScreenEdgeInset)
        XCTAssertEqual(
            hostedRightBottom.maxY,
            hostedVisibleFrame.maxY - WorkspaceMetrics.uiTestScreenEdgeInset
        )
    }

    // SF-0201-008, SF-1902-008
    func testReleaseCompositionIgnoresEveryWindowPlacementArgument() {
        let disabled = DebugTestComposition(
            arguments: [
                "SiteForge",
                "-SiteForgeUITestMode", "YES",
                "-SiteForgeUITestWindowAlignment", "right",
                "-SiteForgeUITestWindowVerticalAlignment", "bottom",
            ],
            enabled: false
        )
        XCTAssertNil(WorkspaceMetrics.requestedUITestWindowPlacement(composition: disabled))
        XCTAssertFalse(WorkspaceMetrics.usesDeterministicUITestPlacement(composition: disabled))
        XCTAssertNil(WorkspaceMetrics.requestedWindowSize(composition: disabled))
        XCTAssertEqual(
            WorkspaceMetrics.effectiveMinimumWindowSize(composition: disabled),
            WorkspaceMetrics.minimumWindowSize
        )
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
            "SF-0201-002", "SF-0201-003", "SF-0201-006", "SF-0201-007", "SF-0201-008", "SF-0201-009",
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
