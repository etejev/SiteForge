import AppKit
import XCTest
@testable import SiteForge

final class AppMetadataTests: XCTestCase {
    // SF-LOCAL-BUILDER-012 / SF-0203-006, SF-0701-002, SF-0702-003.
    // Execution evidence belongs to the bounded 012–016 acceptance receipt.
    func testPlainAuthoringVocabularyPreservesCanonicalKeysAndSizingValues() {
        XCTAssertEqual(ContainerLayoutField.padding.title, "Inner spacing")
        XCTAssertEqual(ContainerLayoutField.padding.propertyKey, "layout.padding")
        XCTAssertEqual(ContainerLayoutField.gap.title, "Space between items")
        XCTAssertEqual(ContainerLayoutField.gap.propertyKey, "layout.gap")
        XCTAssertEqual(FluidValueTarget.padding.title, ContainerLayoutField.padding.title)
        XCTAssertEqual(FluidValueTarget.gap.title, ContainerLayoutField.gap.title)
        XCTAssertEqual(FluidValueTarget.gap.rawValue, "gap")
        XCTAssertEqual(AuthoringLanguage.sizing(.fixed), "Exact size")
        XCTAssertEqual(AuthoringLanguage.sizing(.fill), "Fill available space")
        XCTAssertEqual(AuthoringLanguage.sizing(.hug), "Fit content")
        XCTAssertEqual(CanonicalSizingMode.allCases.map(\.rawValue), ["fixed", "fill", "hug"])
        XCTAssertEqual(ResponsiveGeometrySource.baseDesktop.label, "Uses Desktop")
        XCTAssertEqual(ResponsiveGeometrySource.override(.mobile).label, "Set here · Mobile")
        XCTAssertEqual(ResponsiveGeometrySource.fluid.label, "Smooth scaling")
        XCTAssertEqual(AuthoringLanguage.componentSource(isOverride: false), "Uses component default")
        XCTAssertEqual(AuthoringLanguage.componentSource(isOverride: true), "Set here · this instance")
    }

    func testPlainInspectorDiscoveryRetainsTechnicalSearchAliasesAndMixedScope() {
        for query in ["inner spacing", "space between items", "screen size", "smooth scaling",
                      "exact size", "fit content", "fill available space", "padding", "gap", "breakpoint", "fluid", "hug", "fixed"] {
            XCTAssertEqual(InspectorSectionDiscovery.sections(matching: query, pinned: []), [.layout], query)
        }
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "screen size", pinned: [.design]), [.layout])
        XCTAssertEqual(WebsiteMetadataSource.authored.presentation, "Set here · this page")
        XCTAssertEqual(WebsiteMetadataSource.inherited.presentation, "Uses website default")
        XCTAssertEqual(WebsiteMetadataSource.defaulted.presentation, "Default · page name")
        XCTAssertEqual(WebsiteMetadataSource.omitted.presentation, "Not set")
        XCTAssertEqual(WebsiteMetadataSource.authored.rawValue, "authored")
        XCTAssertEqual(WebsiteMetadataSource.inherited.rawValue, "inherited")
    }

    // SF-0901-003/0902-003/0903-003/0905-004, SF-0510-003. UNRUN.
    func testPlainComponentRecoveryStyleSampleAndReviewCountsNameTheirLimits() {
        XCTAssertEqual(AuthoringLanguage.editOriginalComponent, "Edit original component")
        XCTAssertEqual(AuthoringLanguage.backToCopy, "Back to this copy")
        XCTAssertEqual(AuthoringLanguage.componentResetTitle(count: 5), "Reset copy changes (5)")
        XCTAssertEqual(AuthoringLanguage.componentResetTitle(count: 2, visibilityOnly: true), "Reset visibility changes (2)")
        XCTAssertEqual(AuthoringLanguage.componentRecoverySummary(count: 1), "1 custom value needs attention")
        XCTAssertEqual(AuthoringLanguage.componentRecoverySummary(count: 5), "5 custom values need attention")
        XCTAssertEqual(AuthoringLanguage.componentRecoverySummary(count: 0, originalAvailable: false), "Original component unavailable")
        XCTAssertEqual(AuthoringLanguage.removeCustomValuesTitle(count: 1), "Remove 1 custom value")
        XCTAssertTrue(AuthoringLanguage.removeCustomValueHelp.contains("missing original data is not restored"))
        XCTAssertTrue(AuthoringLanguage.componentRelationshipHelp.contains("independent copy does not stay linked"))
        XCTAssertTrue(AuthoringLanguage.colorOpacitySampleHelp.contains("solid color and opacity"))
        XCTAssertTrue(AuthoringLanguage.colorOpacitySampleHelp.contains("does not copy gradients, tokens"))
        XCTAssertEqual(AuthoringLanguage.reviewCustomizationCount(0, name: "Custom layout"), "Custom layout: 0 objects")
        XCTAssertEqual(AuthoringLanguage.reviewCustomizationCount(1, name: "Custom visibility"), "Custom visibility: 1 object")
        XCTAssertTrue(AuthoringLanguage.reviewCountsHelp.contains("not visual defects"))
        XCTAssertEqual(ComponentOverrideConflict.missingDefinition.rawValue, "missing-definition")
        XCTAssertEqual(ComponentOverrideConflict.missingProperty.rawValue, "missing-property")
        XCTAssertEqual(ComponentOverrideConflict.missingActionDestination.rawValue, "missing-action-destination")
        XCTAssertEqual(AuthoringLanguage.componentValueName(kind: "media"), "Image")
        XCTAssertEqual(AuthoringLanguage.componentValueName(kind: "slot"), "Default contents")
        XCTAssertEqual(ComponentDependencySnapshot.Issue.missingDefinition.rawValue, "Missing component definition")
        XCTAssertEqual(ComponentDependencySnapshot.Issue.missingDefinition.presentation, "Original component unavailable")
        XCTAssertTrue(ComponentOverrideConflict.missingDefinition.explanation.contains("does not restore"))
        XCTAssertTrue(ComponentOverrideConflict.missingActionDestination.explanation.contains("deleted destination is not restored"))
    }

    func testSidebarSegmentsFillBothPaneWidthsWithoutClippingSelectedLabels() {
        for labels in [[42.0, 44, 64, 48, 90], [50.0, 50, 62, 86, 98]] {
            for scale in [1.0, 1.5, 2.0] {
                let minimum = labels.map { $0 * scale }
                for width in [220.0, 300, 352, 416, 600, 900] {
                    for selected in minimum.indices {
                        let plan = ShellTabLayoutPolicy.allocate(width: width, minimumWidths: minimum, selected: selected)
                        XCTAssertTrue(plan.indices.contains(selected) || (plan.overflow && plan.indices.isEmpty))
                        XCTAssertEqual(plan.indices, plan.indices.sorted())
                        XCTAssertEqual(Set(plan.indices).count, plan.indices.count)
                        XCTAssertEqual(plan.widths.count, plan.indices.count)
                        for (offset, index) in plan.indices.enumerated() {
                            XCTAssertGreaterThanOrEqual(plan.widths[offset], minimum[index])
                        }
                        let gaps = max(0, plan.indices.count - 1) + (plan.overflow && !plan.indices.isEmpty ? 1 : 0)
                        let occupied = plan.widths.reduce(0, +) + Double(gaps) + plan.menuWidth
                        XCTAssertEqual(occupied, width, accuracy: 0.001)
                    }
                }
            }
        }
        XCTAssertTrue(ShellTabLayoutPolicy.allocate(width: .nan, minimumWidths: [40], selected: 0).indices.isEmpty)
    }
    func testInspectorSectionDiscoveryPinsOrderAndSceneLocalNeutrality() {
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "", pinned: []), InspectorTab.allCases)
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "PADDING responsive", pinned: []), [.layout])
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "media", pinned: []), [.content])
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "does-not-exist", pinned: [.layout]), [])
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "", pinned: [.layout]).first, .layout)
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "", pinned: []).first, .design)
        // Pins/search are presentation inputs, not canonical property mutations.
        XCTAssertEqual(InspectorSectionDiscovery.sections(matching: "label", pinned: [.accessibility]), [.accessibility])
    }
    // SF-1501-008, SF-1902-008
    func testLocalApplicationIdentityIsStableAndReversible() {
        XCTAssertEqual(AppMetadata.productName, "SiteForge")
        XCTAssertEqual(AppMetadata.localBundleIdentifier, "app.siteforge.SiteForge")
        let configured = Bundle.main.object(forInfoDictionaryKey: "SiteForgeTestApplicationIdentifier") as? String
            ?? AppMetadata.localBundleIdentifier
        XCTAssertTrue([AppMetadata.localBundleIdentifier, "app.siteforge.SiteForge.OwnerTesting"].contains(configured))
        XCTAssertEqual(Bundle.main.bundleIdentifier, configured)
    }

    // SF-0201-009: source catalog integrity is checked by check-app-icon.py;
    // the app-host assertion proves the asset catalog reaches the built bundle.
    func testAppIconCatalogCoversEveryMacSizeAndIsSelectedByBothAppConfigurations() throws {
        XCTAssertNotNil(Bundle.main.url(forResource: "Assets", withExtension: "car"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        XCTAssertTrue(NSApp.applicationIconImage.isValid)
        XCTAssertGreaterThan(NSApp.applicationIconImage.size.width, 0)
        XCTAssertGreaterThan(NSApp.applicationIconImage.size.height, 0)
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

        XCTAssertEqual(CanvasTool.allCases.map(\.title), ["Select", "Section", "Stack", "Grid", "Frame", "Text", "Image", "Button", "Link", "Form", "Component"])
        XCTAssertEqual(CanvasTool.primaryToolbarTools, [.select, .frame, .text, .image, .component])
        XCTAssertEqual(CanvasTool.additionalToolbarTools, [.section, .stack, .grid, .button, .link, .form])
        XCTAssertEqual(
            Set(CanvasTool.primaryToolbarTools + CanvasTool.additionalToolbarTools),
            Set(CanvasTool.allCases)
        )
        XCTAssertTrue(Set(CanvasTool.primaryToolbarTools).isDisjoint(with: CanvasTool.additionalToolbarTools))
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
    func testOverflowTabsHaveDistinctNativeFocusIdentities() {
        XCTAssertEqual(ShellFocus.navigatorOverflow.diagnosticIdentifier, "navigator.tab.overflow")
        XCTAssertEqual(ShellFocus.inspectorOverflow.diagnosticIdentifier, "inspector.tab.overflow")
        XCTAssertNotEqual(ShellFocus.navigatorOverflow, ShellFocus.inspectorOverflow)
    }

    func testShellFocusTraversalIsCompleteBidirectionalAndSceneLocal() {
        let first = PageID(UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)
        let second = PageID(UUID(uuidString: "30000000-0000-0000-0000-000000000002")!)
        let order = ShellFocusTraversal.order(pageIDs: [first, second])
        XCTAssertEqual(order, [
            .navigatorPages, .navigatorLayers, .navigatorElements, .navigatorAssets, .navigatorComponents, .navigatorPage(first),
            .navigatorPage(second), .viewportPreset, .viewportWidth, .viewportCompare, .viewportGrid,
            .viewportZoomOut, .viewportZoomIn,
            .viewportReset, .viewportFitCanvas, .viewportFit, .viewportCanvas,
            .inspectorDesign, .inspectorLayout, .inspectorContent, .inspectorInteractions, .inspectorAccessibility,
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

    // SF-0201-002, SF-0201-006, SF-0201-008, SF-1505-006 through SF-1505-008
    @MainActor
    func testInspectorNavigationIsOrderedTruthfulAndNoncanonical() throws {
        XCTAssertEqual(InspectorTab.allCases, [.design, .layout, .content, .interactions, .accessibility])
        XCTAssertEqual(InspectorTab.design.availability, .available)
        XCTAssertEqual(InspectorTab.layout.availability, .available)
        XCTAssertEqual(InspectorTab.accessibility.availability, .available)

        for tab in [InspectorTab.content, .interactions] {
            XCTAssertEqual(tab.availability, .available)
            XCTAssertFalse(tab.accessibilityDescription.contains("Not available yet"))
        }

        let state = WorkspaceShellState()
        let document = state.documentSession.document
        let revision = document.revision
        for tab in InspectorTab.allCases {
            state.inspectorTab = tab
        }
        XCTAssertEqual(state.documentSession.document, document)
        XCTAssertEqual(state.documentSession.document.revision, revision)
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    // SF-0201-002, SF-0201-006, SF-0201-008
    @MainActor
    func testElementsCatalogIsOrderedTruthfulAndDoesNotCreateCanonicalState() {
        XCTAssertEqual(ElementCatalogItem.allCases.map(\.rawValue), [
            "section", "stack", "grid", "frame", "text", "heading", "image", "button", "link", "form",
            "input", "emailInput", "textArea", "checkbox", "selectField", "submit",
            "divider", "header", "navbar", "footer"
        ])
        XCTAssertEqual(ElementCatalogItem.section.availability, .available(.section))
        XCTAssertEqual(ElementCatalogItem.stack.availability, .available(.stack))
        XCTAssertEqual(ElementCatalogItem.grid.availability, .available(.grid))
        XCTAssertEqual(ElementCatalogItem.frame.availability, .available(.frame))
        XCTAssertEqual(ElementCatalogItem.text.availability, .available(.text))
        XCTAssertEqual(ElementCatalogItem.image.availability, .available(.image))
        XCTAssertEqual(ElementCatalogItem.button.availability, .available(.button))
        XCTAssertEqual(ElementCatalogItem.link.availability, .available(.link))
        XCTAssertEqual(ElementCatalogItem.form.availability, .available(.form))
        for item in [ElementCatalogItem.input, .emailInput, .textArea, .checkbox, .selectField, .submit] {
            XCTAssertEqual(item.category, "Forms")
            XCTAssertEqual(item.availability, .available(.text))
            XCTAssertNotNil(item.template?.formFieldKind)
        }
        XCTAssertEqual(ElementCatalogItem.divider.availability, .available(.frame))
        XCTAssertEqual(ElementCatalogItem.header.availability, .available(.section))
        XCTAssertEqual(ElementCatalogItem.navbar.availability, .available(.section))
        XCTAssertEqual(ElementCatalogItem.footer.availability, .available(.section))
        XCTAssertTrue(ElementCatalogItem.frame.capabilityContract.contains("transactional Frame"))
        XCTAssertTrue(ElementCatalogItem.text.capabilityContract.contains("plain-Text"))
        XCTAssertTrue(ElementCatalogItem.selectField.capabilityContract.contains("selected Form"))
        let state = WorkspaceShellState()
        let document = state.documentSession.document
        for item in ElementCatalogItem.allCases {
            if case .available(let tool) = item.availability { state.selectTool(tool) }
        }
        XCTAssertEqual(state.documentSession.document, document)
        XCTAssertFalse(state.canUndo)
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
            .route(.viewportWidth)
        )
        XCTAssertEqual(
            WorkspaceTabRoutingPolicy.decision(
                from: .viewportWidth,
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
                from: .viewportZoomOut,
                direction: .reverse,
                pageIDs: [home, notFound],
                context: context
            ),
            .passThrough(.notMixedFrameworkBoundary)
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
                "SF-0404-001", "SF-0404-002", "SF-0404-003", "SF-0404-004",
                "SF-0404-005", "SF-0404-006", "SF-0404-007", "SF-0404-008",
                "SF-0405-001", "SF-0405-002", "SF-0405-003", "SF-0405-004",
                "SF-0405-005", "SF-0405-006", "SF-0405-007", "SF-0405-008",
                "SF-0406-001", "SF-0406-002", "SF-0406-003", "SF-0406-004",
                "SF-0406-005", "SF-0406-006", "SF-0406-007", "SF-0406-008",
                "SF-0409-001", "SF-0409-002", "SF-0409-003", "SF-0409-004",
                "SF-0409-005", "SF-0409-006", "SF-0409-007", "SF-0409-008",
                "SF-1102-002", "SF-1102-003", "SF-1102-004", "SF-1102-006",
                "SF-1201-001", "SF-1201-002", "SF-1201-003", "SF-1201-004",
                "SF-1201-006",
            ]
        )
    }
}
