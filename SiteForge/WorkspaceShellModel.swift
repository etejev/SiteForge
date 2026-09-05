import Combine
import AppKit
import os
import SwiftUI

private enum CanvasRendererSignposts {
    static let log = OSLog(subsystem: "app.siteforge.SiteForge", category: "canvas-renderer")
}

private enum InsertionSignposts {
    static let log = OSLog(subsystem: "app.siteforge.SiteForge", category: "insertion")
}

enum CanvasTool: String, CaseIterable, Identifiable {
    case select
    case section
    case stack
    case grid
    case frame
    case text
    case image
    case component

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .select: "pointer.arrow"
        case .section: "rectangle.split.3x1"
        case .stack: "square.3.layers.3d"
        case .grid: "square.grid.2x2"
        case .frame: "square.dashed"
        case .text: "textformat"
        case .image: "photo"
        case .component: "square.stack.3d.up"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .select: "v"
        case .section: "1"
        case .stack: "2"
        case .grid: "3"
        case .frame: "f"
        case .text: "t"
        case .image: "i"
        case .component: "c"
        }
    }
}

enum NavigatorTab: String, CaseIterable, Identifiable {
    case pages
    case layers
    case elements
    case assets
    case components

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ElementCatalogAvailability: Equatable {
    case available(CanvasTool)
    case unavailable(String)
}

enum ElementCatalogItem: String, CaseIterable, Identifiable {
    case section, stack, grid, frame, text, image, button, link, divider, navbar, footer

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var category: String {
        switch self {
        case .section, .stack, .grid, .frame: "Layout"
        case .text, .image, .button, .link, .divider: "Basic"
        case .navbar, .footer: "Site"
        }
    }
    var systemImage: String {
        switch self {
        case .section: "rectangle.split.3x1"
        case .stack: "square.3.layers.3d"
        case .grid: "square.grid.2x2"
        case .frame: "rectangle.dashed"
        case .text: "textformat"
        case .image: "photo"
        case .button: "capsule"
        case .link: "link"
        case .divider: "minus"
        case .navbar: "rectangle.topthird.inset.filled"
        case .footer: "rectangle.bottomthird.inset.filled"
        }
    }
    var keyboardPath: String {
        switch self {
        case .frame: "F"
        case .text: "T"
        case .image: "I"
        default: "No shortcut"
        }
    }
    var availability: ElementCatalogAvailability {
        switch self {
        case .section: .available(.section)
        case .stack: .available(.stack)
        case .grid: .available(.grid)
        case .frame: .available(.frame)
        case .text: .available(.text)
        case .image: .available(.image)
        case .button, .link, .divider:
            .unavailable("This basic element is not available until its canonical content command is implemented.")
        case .navbar, .footer:
            .unavailable("Site sections are not available until responsive site structure is implemented.")
        }
    }

    var insertionKind: InsertionKind? {
        switch self {
        case .section: .section
        case .stack: .stack
        case .grid: .grid
        case .frame: .frame
        case .text: .text
        case .image: .image
        case .button, .link, .divider, .navbar, .footer: nil
        }
    }
    /// The precise bounded behavior this row is allowed to expose.  This is
    /// editor-catalogue metadata, never an authored node or package member.
    var capabilityContract: String {
        switch availability {
        case .available(.section): "Arms the transactional Section insertion path."
        case .available(.stack): "Arms the transactional Stack insertion path."
        case .available(.grid): "Arms the transactional Grid insertion path."
        case .available(.frame): "Arms the existing transactional Frame insertion path."
        case .available(.text): "Arms the existing transactional plain-Text insertion path."
        case .available(.image): "Inserts the selected local image asset through the transactional Image path."
        case .available: "No other insertion capability is currently available."
        case .unavailable(let reason): reason
        }
    }
    var accessibilityDescription: String {
        switch availability {
        case .available: "\(title), \(category) element. Shortcut \(keyboardPath). Inserts through the verified command registry."
        case .unavailable: "\(title), \(category) element. Not available yet. \(capabilityContract)"
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case design
    case layout
    case content
    case interactions
    case accessibility

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var availability: InspectorTabAvailability {
        switch self {
        case .design, .layout, .accessibility:
            .available
        case .content:
            .unavailable(
                reason: "General content properties are not available yet.",
                nextStep: "Edit supported plain text directly on the canvas; broader content editing requires a later canonical property-editing milestone."
            )
        case .interactions:
            .unavailable(
                reason: "Interaction authoring is not available yet.",
                nextStep: "Interaction data will require a later canonical interaction-model milestone."
            )
        }
    }

    var accessibilityDescription: String {
        switch availability {
        case .available:
            "\(title) inspector tab."
        case let .unavailable(reason, nextStep):
            "\(title) inspector tab. Not available yet. \(reason) \(nextStep)"
        }
    }
}

enum InspectorTabAvailability: Equatable {
    case available
    case unavailable(reason: String, nextStep: String)
}

enum ViewportPreset: String, CaseIterable, Identifiable {
    case desktop
    case tablet
    case mobile

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var width: Int {
        switch self {
        case .desktop: 1_440
        case .tablet: 768
        case .mobile: 390
        }
    }

    var responsiveBreakpoint: ResponsiveBreakpoint {
        switch self { case .desktop: .desktop; case .tablet: .tablet; case .mobile: .mobile }
    }
}

enum ShellRegion: String, CaseIterable {
    case navigator = "shell.navigator"
    case canvas = "shell.canvas"
    case inspector = "shell.inspector"
    case statusBar = "shell.status"
}

enum ShellFocus: Hashable {
    case navigatorPages
    case navigatorLayers
    case navigatorElements
    case navigatorAssets
    case navigatorComponents
    case navigatorPage(PageID)
    case navigatorLayer(NodeID)
    case viewportPreset
    case viewportZoomOut
    case viewportZoomIn
    case viewportReset
    case viewportFitCanvas
    case viewportFit
    case viewportCanvas
    case inspectorDesign
    case inspectorLayout
    case inspectorContent
    case inspectorInteractions
    case inspectorAccessibility
}

enum ShellFocusDirection {
    case forward
    case reverse
}

enum ShellFocusTraversal {
    static func order(pageIDs: [PageID], layerIDs: [NodeID] = []) -> [ShellFocus] {
        [
            .navigatorPages, .navigatorLayers, .navigatorElements, .navigatorAssets, .navigatorComponents,
        ] + pageIDs.map(ShellFocus.navigatorPage) + layerIDs.map(ShellFocus.navigatorLayer) + [
            .viewportPreset, .viewportZoomOut, .viewportZoomIn,
            .viewportReset, .viewportFitCanvas, .viewportFit, .viewportCanvas,
            .inspectorDesign, .inspectorLayout, .inspectorContent, .inspectorInteractions, .inspectorAccessibility,
        ]
    }

    static func adjacent(
        to current: ShellFocus?,
        direction: ShellFocusDirection,
        pageIDs: [PageID],
        layerIDs: [NodeID] = []
    ) -> ShellFocus? {
        let values = order(pageIDs: pageIDs, layerIDs: layerIDs)
        guard !values.isEmpty else { return nil }
        guard let current, let index = values.firstIndex(of: current) else {
            return direction == .forward ? values.first : values.last
        }
        let offset = direction == .forward ? 1 : -1
        return values[(index + offset + values.count) % values.count]
    }
}

extension ShellFocus {
    var diagnosticIdentifier: String {
        switch self {
        case .navigatorPages: "navigator.tab.pages"
        case .navigatorLayers: "navigator.tab.layers"
        case .navigatorElements: "navigator.tab.elements"
        case .navigatorAssets: "navigator.tab.assets"
        case .navigatorComponents: "navigator.tab.components"
        case let .navigatorPage(id): NavigatorPageAccessibility.identifier(for: id)
        case let .navigatorLayer(id): "navigator.layer.\(id.description)"
        case .viewportPreset: "canvas.viewport.preset"
        case .viewportZoomOut: "canvas.zoom.out"
        case .viewportZoomIn: "canvas.zoom.in"
        case .viewportReset: "canvas.zoom.reset"
        case .viewportFitCanvas: "canvas.zoom.fitCanvas"
        case .viewportFit: "canvas.zoom.fit"
        case .viewportCanvas: "canvas.interaction"
        case .inspectorDesign: "inspector.tab.design"
        case .inspectorLayout: "inspector.tab.layout"
        case .inspectorContent: "inspector.tab.content"
        case .inspectorInteractions: "inspector.tab.interactions"
        case .inspectorAccessibility: "inspector.tab.accessibility"
        }
    }
}

struct WorkspaceTabRoutingContext: Equatable {
    let isWorkspaceWindowEvent: Bool
    let isKeyWindow: Bool
    let hasAttachedSheet: Bool
    let isTextEditing: Bool
    let hasTransientPresentation: Bool
}

enum WorkspaceTabRoutingPassReason: Equatable {
    case wrongWindow
    case inactiveWindow
    case attachedSheet
    case textEditing
    case transientPresentation
    case noLogicalFocus
    case notMixedFrameworkBoundary
}

enum WorkspaceTabRoutingDecision: Equatable {
    case route(ShellFocus)
    case passThrough(WorkspaceTabRoutingPassReason)
}

enum WorkspaceTabRoutingPolicy {
    static func decision(
        from current: ShellFocus?,
        direction: ShellFocusDirection,
        pageIDs: [PageID],
        layerIDs: [NodeID] = [],
        context: WorkspaceTabRoutingContext
    ) -> WorkspaceTabRoutingDecision {
        guard context.isWorkspaceWindowEvent else { return .passThrough(.wrongWindow) }
        guard context.isKeyWindow else { return .passThrough(.inactiveWindow) }
        guard !context.hasAttachedSheet else { return .passThrough(.attachedSheet) }
        guard !context.isTextEditing else { return .passThrough(.textEditing) }
        guard !context.hasTransientPresentation else {
            return .passThrough(.transientPresentation)
        }
        guard let current else { return .passThrough(.noLogicalFocus) }
        guard let target = ShellFocusTraversal.adjacent(
            to: current,
            direction: direction,
            pageIDs: pageIDs,
            layerIDs: layerIDs
        ) else {
            return .passThrough(.noLogicalFocus)
        }
        guard current == .viewportPreset || target == .viewportPreset else {
            return .passThrough(.notMixedFrameworkBoundary)
        }
        return .route(target)
    }
}

enum NavigatorPageAccessibility {
    static func identifier(for pageID: PageID) -> String {
        "navigator.page.\(pageID.description)"
    }

    static func roleValue(for role: PageRole) -> String {
        switch role {
        case .home: "Home page"
        case .notFound: "Not Found page"
        case .standard: "Standard page"
        }
    }
}

enum WorkspaceMetrics {
    static let minimumWindowSize = CGSize(width: 1_100, height: 700)
    static let defaultWindowSize = CGSize(width: 1_280, height: 800)
    static let navigatorWidth: ClosedRange<CGFloat> = 210...300
    static let inspectorWidth: ClosedRange<CGFloat> = 280...360
    static let minimumCanvasWidth: CGFloat = 500
    static let uiTestScreenEdgeInset: CGFloat = 16

    static func supportsLayout(at size: CGSize) -> Bool {
        size.width >= minimumWindowSize.width
            && size.height >= minimumWindowSize.height
            && navigatorWidth.lowerBound + minimumCanvasWidth + inspectorWidth.lowerBound < size.width
    }

    static func requestedWindowSize(composition: DebugTestComposition = .current()) -> CGSize? {
        guard composition.value(after: "-SiteForgeWindowSize") == "minimum" else { return nil }
        return minimumWindowSize
    }

    static func requestedWindowFrameSize(
        contentSize: CGSize,
        currentFrameSize: CGSize,
        currentContentLayoutSize: CGSize
    ) -> CGSize {
        CGSize(
            width: contentSize.width
                + max(0, currentFrameSize.width - currentContentLayoutSize.width),
            height: contentSize.height
                + max(0, currentFrameSize.height - currentContentLayoutSize.height)
        )
    }

    static func effectiveMinimumWindowSize(
        composition: DebugTestComposition = .current()
    ) -> CGSize {
        guard requestedUITestWindowPlacement(composition: composition) != nil else {
            return minimumWindowSize
        }
        // A titled AppKit window cannot move its title bar above the hosted
        // display's menu-bar-safe edge. An explicit Debug/UI-test placement
        // may therefore fit vertically, while retaining the 1100-point
        // product width. Right alignment intentionally lets the window extend
        // beyond the leading display edge so trailing toolbar/status controls
        // remain genuinely pointer-accessible.
        return CGSize(width: minimumWindowSize.width, height: 1)
    }

    static func usesDeterministicUITestPlacement(
        composition: DebugTestComposition = .current()
    ) -> Bool {
        requestedUITestWindowPlacement(composition: composition) != nil
    }

    /// Normal production presentation is the default for both release and
    /// generic automation composition. A named placement is the sole opt-in
    /// escape hatch for constrained-display pointer tests.
    static func usesNormalVisibleFramePresentation(
        composition: DebugTestComposition = .current()
    ) -> Bool {
        requestedUITestWindowPlacement(composition: composition) == nil
    }

    static func requestedUITestWindowPlacement(
        composition: DebugTestComposition = .current()
    ) -> WorkspaceUITestWindowPlacement? {
        guard composition.boolValue(after: "-SiteForgeUITestMode") == true else {
            return nil
        }
        let horizontal = composition.value(after: "-SiteForgeUITestWindowAlignment")
            .flatMap(WorkspaceUITestWindowAlignment.init(rawValue:))
        let vertical = composition.value(after: "-SiteForgeUITestWindowVerticalAlignment")
            .flatMap(WorkspaceUITestWindowVerticalAlignment.init(rawValue:))
        // Window placement is an explicit Debug/UI-test geometry override,
        // not a side effect of enabling the general automation composition.
        // Generic keyboard and accessibility journeys exercise the production
        // minimum and window behavior; only pointer journeys that name an
        // edge receive the AppKit fitting bridge.
        guard horizontal != nil || vertical != nil else { return nil }
        return WorkspaceUITestWindowPlacement(
            horizontal: horizontal ?? .left,
            vertical: vertical ?? .top
        )
    }

    static func uiTestWindowFrame(
        windowFrame: CGRect,
        visibleFrame: CGRect,
        placement: WorkspaceUITestWindowPlacement,
        inset: CGFloat = uiTestScreenEdgeInset
    ) -> CGRect {
        // AppKit keeps a titled window's title bar on screen. Fit explicit
        // Debug/UI-test windows vertically before AppKit can apply a smaller,
        // origin-dependent constraint of its own. Width is deliberately not
        // fitted: the named trailing-edge tests need the real product width
        // with its leading edge outside a narrower hosted display.
        // Preserve a safe boundary at *both* vertical display edges.  The
        // bottom-aligned text-edit journey operates real status-bar controls,
        // so placing the window's lower edge at the visible-frame edge would
        // still leave those controls beneath the automation-safe area.
        let height = min(windowFrame.height, max(1, visibleFrame.height - (2 * inset)))
        let x = switch placement.horizontal {
        case .left: visibleFrame.minX + inset
        case .right: visibleFrame.maxX - windowFrame.width - inset
        }
        let y = switch placement.vertical {
        case .top: visibleFrame.maxY - height - inset
        case .bottom: visibleFrame.minY + inset
        }
        return CGRect(
            x: x,
            y: y,
            width: windowFrame.width,
            height: height
        )
    }

    static func requestedWindowSize(arguments: [String]) -> CGSize? {
        requestedWindowSize(composition: .current(arguments: arguments))
    }
}

/// A small, value-only policy for the normal macOS window. It deliberately
/// has no relationship to canonical project state: AppKit owns restoration,
/// while the policy only decides whether a restored frame is safe to retain.
enum WorkspaceWindowPresentation {
    static let frameAutosaveName = "SiteForge.workspace.window"

    static func acceptsRestoredFrame(
        _ frame: CGRect,
        visibleFrame: CGRect,
        minimumFrameSize: CGSize
    ) -> Bool {
        guard frame.isFiniteRect,
              visibleFrame.isFiniteRect,
              frame.width >= minimumFrameSize.width,
              frame.height >= minimumFrameSize.height,
              frame.intersects(visibleFrame) else { return false }

        // A restored frame must retain a meaningful visible title-bar/pointer
        // target. This rejects an old display's completely off-screen frame
        // without unnecessarily recentering a user-positioned workspace.
        return frame.intersection(visibleFrame).width >= 96
            && frame.intersection(visibleFrame).height >= 96
    }

    static func initialFrame(
        visibleFrame: CGRect,
        restoredFrame: CGRect?,
        minimumFrameSize: CGSize
    ) -> CGRect {
        if let restoredFrame,
           acceptsRestoredFrame(
            restoredFrame,
            visibleFrame: visibleFrame,
            minimumFrameSize: minimumFrameSize
           ) {
            return restoredFrame
        }
        // `visibleFrame` is AppKit's usable display area: it excludes the
        // menu bar and Dock while remaining a normal (non-Space) window. A
        // display narrower than the supported production minimum cannot fit
        // the complete workspace. Preserve the minimum and its trailing
        // controls by aligning that oversized frame to the usable right edge.
        let width = max(visibleFrame.width, minimumFrameSize.width)
        return CGRect(
            x: visibleFrame.maxX - width,
            y: visibleFrame.minY,
            width: width,
            height: visibleFrame.height
        )
    }
}

private extension CGRect {
    var isFiniteRect: Bool {
        [minX, minY, width, height].allSatisfy(\.isFinite)
            && width > 0 && height > 0
    }
}

enum WorkspaceUITestWindowAlignment: String {
    case left
    case right
}

enum WorkspaceUITestWindowVerticalAlignment: String {
    case top
    case bottom
}

struct WorkspaceUITestWindowPlacement: Equatable {
    let horizontal: WorkspaceUITestWindowAlignment
    let vertical: WorkspaceUITestWindowVerticalAlignment
}

enum WorkspaceFixtureScale: String {
    case standard
    case large

    static func from(composition: DebugTestComposition = .current()) -> Self? {
        composition.value(after: "-SiteForgeWorkspaceFixture").flatMap(Self.init)
    }

    var pageCount: Int { self == .standard ? 100 : 10_000 }

    func document() -> CanonicalDocument {
        var document = ProjectCreation.blank()
        guard pageCount > document.pages.count else { return document }
        for index in document.pages.count..<pageCount {
            document.pages.append(DocumentPage(
                name: "Fixture Page \(index + 1)",
                route: PageRoute(rawValue: "/fixture-\(index + 1)")
            ))
        }
        return document
    }
}

enum WorkspaceSelectionFixture: String {
    case multiple

    static func from(composition: DebugTestComposition = .current()) -> Self? {
        composition.value(after: "-SiteForgeSelectionFixture").flatMap(Self.init)
    }

    func document() -> CanonicalDocument {
        var document = ProjectCreation.blank()
        guard var page = document.pages.first,
              let structuralRootID = page.rootNodeIDs.first,
              let structuralRootIndex = page.nodes.firstIndex(where: { $0.id == structuralRootID }) else {
            return document
        }
        let extraIDs = [
            NodeID(UUID(uuidString: "77777777-7777-4777-8777-777777777701")!),
            NodeID(UUID(uuidString: "77777777-7777-4777-8777-777777777702")!),
        ]
        page.nodes[structuralRootIndex].childIDs.append(contentsOf: extraIDs)
        page.nodes.append(contentsOf: extraIDs.enumerated().map { offset, id in
            let x = Double(80 + (offset * 280))
            return DocumentNode(
                id: id,
                kind: .frame,
                name: "Fixture Layer \(offset + 1)",
                parent: .node(structuralRootID),
                properties: [
                    NodeProperty(key: .init(rawValue: "layout.x"), value: .number(x), origin: .defaulted),
                    NodeProperty(key: .init(rawValue: "layout.y"), value: .number(120), origin: .defaulted),
                    NodeProperty(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
                    NodeProperty(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
                    NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted),
                ]
            )
        })
        document.pages[0] = page
        return document
    }
}

/// Immutable input for the production workspace-scene projection. Copying the
/// canonical value here is cheap (its arrays are copy-on-write); all tree
/// traversal, geometry resolution, and renderer/selection projection happens
/// on `WorkspaceScenePreparationWorker`, away from the main actor.
struct WorkspaceScenePreparationRequest: Sendable {
    let document: CanonicalDocument
    let activePageID: PageID?
    let activeContainerID: NodeID?
    let viewport: CanvasViewportState
    let surfaceID: CanvasRenderSurfaceID
    let breakpoint: ResponsiveBreakpoint
    let imageResourceData: [AssetID: Data]

    init(document: CanonicalDocument, activePageID: PageID?, activeContainerID: NodeID?,
         viewport: CanvasViewportState, surfaceID: CanvasRenderSurfaceID,
         breakpoint: ResponsiveBreakpoint = .desktop,
         imageResourceData: [AssetID: Data] = [:]) {
        self.document = document; self.activePageID = activePageID; self.activeContainerID = activeContainerID
        self.viewport = viewport; self.surfaceID = surfaceID; self.breakpoint = breakpoint
        self.imageResourceData = imageResourceData
    }
}

struct WorkspaceScenePreparationResult: Sendable {
    let viewportRequest: CanvasViewportPreparationRequest
    let renderScene: CanvasRenderSceneSnapshot
    let overlays: CanvasEditorOverlaySnapshot
    let selectionScene: SelectionSceneSnapshot?
}

struct WorkspaceScenePreparationProgress: Sendable {
    let checkpoint: @Sendable (Int) -> Void

    static let none = WorkspaceScenePreparationProgress(checkpoint: { _ in })
}

enum WorkspaceScenePreparationError: Error, Equatable, Sendable {
    case cancelled
}

/// SF-0407-006 / SF-1502-001: the projection is deliberately actor-isolated
/// so a 10,000-object/page fixture cannot monopolize AppKit's main actor. The
/// returned snapshots retain the exact document, scene, viewport generation,
/// and stable identities that adoption validates later on the main actor.
actor WorkspaceScenePreparationWorker {
    func prepare(
        _ request: WorkspaceScenePreparationRequest,
        progress: WorkspaceScenePreparationProgress = .none
    ) throws -> WorkspaceScenePreparationResult {
        var completed = 0
        func checkpoint() throws {
            completed += 1
            if completed.isMultiple(of: 64) {
                progress.checkpoint(completed)
                guard !Task.isCancelled else { throw WorkspaceScenePreparationError.cancelled }
            }
        }

        guard !Task.isCancelled else { throw WorkspaceScenePreparationError.cancelled }
        let identity = CanvasRenderRequestIdentity(
            documentID: request.document.id,
            revision: request.document.revision,
            sceneID: request.viewport.sceneID,
            sceneGeneration: request.document.revision,
            viewportGeneration: request.viewport.generation,
            scale: request.viewport.pixelRatio
        )

        let activePage = request.document.pages.first { $0.id == request.activePageID }
        let orderedActiveNodes = activePage?.canonicalDepthFirstNodes() ?? []
        let resolvedGeometry = activePage?.resolvedStructuralGeometry(breakpoint: request.breakpoint) ?? [:]
        let effectivelyVisible = activePage?.effectiveVisibleNodeIDs(breakpoint: request.breakpoint) ?? []
        var renderObjects: [CanvasRenderObject] = []
        renderObjects.reserveCapacity(orderedActiveNodes.count)

        for node in orderedActiveNodes {
            try checkpoint()
            guard effectivelyVisible.contains(node.id) else { continue }
            // Structural roots intentionally have no authored geometry and
            // never receive a fabricated fallback rectangle.
            guard let authoredGeometry = node.insertionGeometry else { continue }
            let frame = (resolvedGeometry[node.id] ?? authoredGeometry).frame
            let style: CanvasPaintStyle = switch node.kind {
            case .frame:
                if case .page(let pageID) = node.parent, pageID == request.activePageID {
                    .page
                } else if node.insertionStringProperty("style.fill") == "surface" {
                    .frameSurface
                } else {
                    .container
                }
            case .section: .sectionSurface
            case .stack: .stackSurface
            case .grid: .gridSurface
            case .text: .textPlaceholder
            case .image: .imagePlaceholder
            case .component: .container
            }
            let fillLayers = DesignInspectorCommandRegistry.resolvedLayers(for: node).map { layer in
                switch layer.kind {
                case .solid:
                    return CanvasAuthoredFillLayer(
                        id: layer.id.rawValue,
                        kind: .solid,
                        isEnabled: layer.isEnabled,
                        rgba: layer.solidColor.map { [$0.red, $0.green, $0.blue, $0.alpha] },
                        angleDegrees: nil,
                        stops: []
                    )
                case .linearGradient:
                    return CanvasAuthoredFillLayer(
                        id: layer.id.rawValue,
                        kind: .linearGradient,
                        isEnabled: layer.isEnabled,
                        rgba: nil,
                        angleDegrees: layer.normalizedAngleDegrees,
                        stops: layer.stops.map {
                            .init(
                                id: $0.id.rawValue,
                                position: $0.position,
                                rgba: [$0.color.red, $0.color.green, $0.color.blue, $0.color.alpha]
                            )
                        }
                    )
                }
            }
            let boxStyle = DesignBoxStyleCommandRegistry.resolvedStyle(for: node)
            let border = boxStyle?.border.map {
                CanvasAuthoredBorder(
                    rgba: [$0.color.red, $0.color.green, $0.color.blue, $0.color.alpha],
                    width: $0.width,
                    style: CanvasBorderStyle(rawValue: $0.style.rawValue) ?? .solid
                )
            }
            let shadow = boxStyle?.shadow.map {
                CanvasAuthoredShadow(
                    rgba: [$0.color.red, $0.color.green, $0.color.blue, $0.color.alpha],
                    offsetX: $0.offsetX, offsetY: $0.offsetY, blur: $0.blur, spread: $0.spread
                )
            }
            let typography: CanvasTypography? = TypographyCommandRegistry.resolvedTypography(for: node).map { authored in
                let installed = Set(NSFontManager.shared.availableFontFamilies)
                let systemFamily = NSFont.systemFont(ofSize: CGFloat(authored.size)).familyName ?? "System"
                let resolvedFamily: String
                let usesFallback: Bool
                if authored.family == CanonicalTypography.defaultFamily {
                    resolvedFamily = systemFamily; usesFallback = false
                } else if installed.contains(authored.family) {
                    resolvedFamily = authored.family; usesFallback = false
                } else {
                    resolvedFamily = systemFamily; usesFallback = true
                }
                return CanvasTypography(
                    authoredFamily: authored.family, resolvedFamily: resolvedFamily,
                    weight: authored.weight.rawValue, size: authored.size,
                    lineHeight: authored.lineHeight, tracking: authored.tracking,
                    alignment: CanvasTextAlignment(rawValue: authored.alignment.rawValue) ?? .leading,
                    usesFallback: usesFallback
                )
            }
            let imageAssetID = node.kind == .image
                ? node.insertionStringProperty(CanonicalImageStyle.namespace + "assetID").flatMap(AssetID.init(uuidString:))
                : nil
            let imageAsset = imageAssetID.flatMap { id in
                request.document.imageAssets.first(where: { $0.id == id })
            }
            let imageFit = node.insertionStringProperty(CanonicalImageStyle.namespace + "fit")
                .flatMap(CanvasImageFitMode.init(rawValue:))
            let imageFocalX = node.insertionNumberProperty(CanonicalImageStyle.namespace + "focal.x") ?? 0.5
            let imageFocalY = node.insertionNumberProperty(CanonicalImageStyle.namespace + "focal.y") ?? 0.5
            let imageAlt = node.insertionStringProperty(CanonicalImageStyle.namespace + "alt") ?? ""
            let imageDecorative = node.insertionBooleanProperty(CanonicalImageStyle.namespace + "decorative")
            let imageAccessibilityLabel: String? = if node.kind == .image {
                if imageDecorative {
                    "Decorative image: \(imageAsset?.displayName ?? node.name)"
                } else if imageAlt.isEmpty {
                    "Image: \(imageAsset?.displayName ?? node.name); alternative text is empty"
                } else {
                    imageAlt
                }
            } else { nil }
            renderObjects.append(CanvasRenderObject(
                id: node.id,
                frame: frame,
                clipRect: request.viewport.contentBounds,
                paintOrder: renderObjects.count,
                style: style,
                isVisible: !node.selectionBooleanProperty("hidden"),
                accessibilityLabel: node.kind == .text ? "Text object" : (imageAccessibilityLabel ?? node.name),
                plainText: node.kind == .text ? node.insertionStringProperty("content.text") : nil,
                displayName: node.kind == .text ? nil : node.name,
                fillRGBA: nil,
                fillLayers: fillLayers,
                opacity: DesignInspectorCommandRegistry.resolvedOpacity(for: node)?.0 ?? 1,
                border: border,
                cornerRadius: boxStyle?.cornerRadius ?? 0,
                shadow: shadow,
                typography: typography,
                imageAssetID: imageAssetID,
                imageData: imageAssetID.flatMap { request.imageResourceData[$0] },
                imagePixelWidth: imageAsset?.pixelWidth,
                imagePixelHeight: imageAsset?.pixelHeight,
                imageFitMode: imageFit,
                imageFocalX: imageFocalX,
                imageFocalY: imageFocalY
            ))
        }

        let rendered = Dictionary(uniqueKeysWithValues: renderObjects.map { ($0.id, $0) })
        var fallbackOrder = renderObjects.count
        var selectionTargets: [SelectionTargetSnapshot] = []
        selectionTargets.reserveCapacity(activePage?.nodes.count ?? 0)
        if let page = activePage {
            let names = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0.name) })
            let structuralRootIDs = Set(page.rootNodeIDs.filter { rootID in
                page.nodes.first(where: { $0.id == rootID })?.insertionGeometry == nil
            })
            for node in page.canonicalDepthFirstNodes() {
                try checkpoint()
                let object = rendered[node.id]
                // The implicit ownership root remains available to Layers once
                // authored children exist, but it never enters canvas traversal
                // or receives a fabricated editor overlay. Its direct children
                // behave as page-level visible objects for selection scope.
                guard object != nil || page.nodes.count > 1 else { continue }
                let canonicalParentID: NodeID? = if case .node(let id) = node.parent { id } else { nil }
                let selectionParentID = canonicalParentID.flatMap {
                    structuralRootIDs.contains($0) ? nil : $0
                }
                selectionTargets.append(SelectionTargetSnapshot(
                    id: node.id,
                    pageID: page.id,
                    parentID: selectionParentID,
                    name: node.name,
                    kind: node.kind,
                    parentName: canonicalParentID.flatMap { names[$0] },
                    frame: object?.frame ?? resolvedGeometry[node.id]?.frame ?? request.viewport.contentBounds,
                    clipRect: nil,
                    paintOrder: object?.paintOrder ?? fallbackOrder,
                    isVisible: effectivelyVisible.contains(node.id),
                    isLocked: node.selectionBooleanProperty("locked"),
                    isAvailable: object != nil || page.nodes.count > 1,
                    participatesInCanvasTraversal: object != nil
                ))
                fallbackOrder += 1
            }
        }
        progress.checkpoint(completed)
        guard !Task.isCancelled else { throw WorkspaceScenePreparationError.cancelled }

        let scene = CanvasRenderSceneSnapshot(
            identity: identity,
            surfaceID: request.surfaceID,
            objects: renderObjects
        )
        let viewportObjects = renderObjects.map {
            CanvasViewportSceneObject(id: $0.id, bounds: request.viewport.contentBounds)
        }
        let viewportIdentity = CanvasViewportOperationIdentity(
            documentID: request.document.id,
            revision: request.document.revision,
            sceneID: request.viewport.sceneID,
            generation: request.viewport.generation
        )
        let selectionScene = request.activePageID.map {
            SelectionSceneSnapshot(
                identity: identity,
                activePageID: $0,
                activeContainerID: request.activeContainerID,
                targets: selectionTargets
            )
        }
        return WorkspaceScenePreparationResult(
            viewportRequest: CanvasViewportPreparationRequest(
                identity: viewportIdentity,
                viewport: request.viewport,
                objects: viewportObjects
            ),
            renderScene: scene,
            overlays: CanvasEditorOverlaySnapshot(identity: identity, overlays: []),
            selectionScene: selectionScene
        )
    }
}

private struct InspectorAnnouncementContext {
    let breakpoint: ResponsiveBreakpoint
    let orderedNodeIDs: [NodeID]

    func matches(breakpoint: ResponsiveBreakpoint, orderedNodeIDs: [NodeID]) -> Bool {
        self.breakpoint == breakpoint && self.orderedNodeIDs == orderedNodeIDs
    }
}

@MainActor
final class WorkspaceShellState: ObservableObject {
    static let requirementIDs: Set<String> = [
        "SF-0201-002",
        "SF-0201-004",
        "SF-0201-006",
        "SF-0201-008",
        "SF-0203-006",
        "SF-0203-008",
        "SF-0602-002",
        "SF-0602-006",
        "SF-1902-006",
        "SF-1902-008",
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
    ]

    @Published var selectedTool: CanvasTool = .select
    @Published var navigatorTab: NavigatorTab = .pages
    @Published var selectedPageID: PageID?
    @Published var inspectorTab: InspectorTab = .layout
    @Published var viewportPreset: ViewportPreset = .desktop {
        didSet {
            guard viewportPreset != oldValue else { return }
            updateViewportContentBounds()
        }
    }
    @Published private(set) var viewportState: CanvasViewportState
    @Published private(set) var preparedViewportScene: PreparedCanvasViewportScene?
    @Published private(set) var canvasRenderPlan: CanvasRenderPlan?
    @Published private(set) var canvasRendererFailure: CanvasRendererError?
    @Published private(set) var selectionState = SelectionState()
    @Published private(set) var selectionOverlayPlan: SelectionOverlayPlan?
    @Published private(set) var selectionFailure: SelectionCommandError?
    @Published private(set) var lastSelectionAnnouncement = "No object selected"
    @Published private(set) var insertionSession = InsertionSession()
    @Published private(set) var insertionFailure: InsertionError?
    @Published private(set) var lastInsertionAnnouncement = "Insertion inactive"
    @Published private(set) var dragDropSession = DragDropSession()
    @Published private(set) var dragDropFailure: DragDropError?
    @Published private(set) var lastDragDropAnnouncement = "Drag and drop inactive"
    @Published private(set) var textEditingSession = InlineTextEditingSession()
    @Published private(set) var textEditingFailure: TextEditError?
    @Published private(set) var lastTextEditingAnnouncement = "Text editing inactive"
    @Published private(set) var transformSession = TransformSession()
    @Published private(set) var transformFailure: TransformError?
    @Published private(set) var lastTransformAnnouncement = "Transform inactive"
    @Published private(set) var geometryInspectorFailure: GeometryInspectorError?
    @Published private(set) var lastGeometryInspectorAnnouncement = "Layout Inspector inactive"
    @Published private(set) var containerLayoutFailure: ContainerLayoutError?
    @Published private(set) var lastContainerLayoutAnnouncement = "Container layout inactive"
    @Published private(set) var responsiveVisibilityFailure: ResponsiveVisibilityError?
    @Published private(set) var lastResponsiveVisibilityAnnouncement = "Breakpoint visibility inactive"
    private var containerLayoutAnnouncementContext: InspectorAnnouncementContext?
    private var responsiveVisibilityAnnouncementContext: InspectorAnnouncementContext?
    @Published private(set) var designInspectorFailure: DesignInspectorError?
    @Published private(set) var lastDesignInspectorAnnouncement = "Design Inspector inactive"
    @Published var assetSearchText = ""
    @Published var selectedAssetID: AssetID?
    @Published private(set) var isImportingImages = false
    @Published private(set) var lastAssetAnnouncement = "No image asset selected"
    @Published private(set) var imageThumbnailData: [AssetID: Data] = [:]
    @Published private(set) var imageInspectorFailure: ImageInspectorError?
    @Published private(set) var lastImageInspectorAnnouncement = "Image Inspector inactive"
    @Published private(set) var snapResolution: SnapResolution?
    @Published private(set) var isSnappingSuppressed = false
    /// Scene-local editor orientation preference; never canonical project data.
    @Published var isWorldGridVisible = true
    @Published private(set) var selectedGuideID: GuideID?
    @Published private(set) var guideEditingSession = GuideEditingSession()
    @Published private(set) var guideFailure: GuideCommandError?
    @Published private(set) var lastGuideAnnouncement = "No authored guide selected"
    @Published private(set) var viewportFailure: CanvasViewportError?
    @Published private(set) var lastViewportAnnouncement = "Canvas viewport at 100 percent"
    @Published private(set) var canvasInteractionCount = 0
    @Published var isPreviewPresented = false {
        didSet {
            if isPreviewPresented {
                cancelDragDrop()
                cancelInsertion(resetTool: true)
                cancelTransform()
                cancelGuideEditing()
                cancelTextEditing()
            }
        }
    }
    let documentSession: DocumentSession
    let lifecycle: DocumentLifecycleController
    private var documentSessionObservation: AnyCancellable?
    private let viewportRegistry = CanvasViewportCommandRegistry()
    private let viewportPreparer: CanvasViewportScenePreparer
    private let scenePreparationWorker = WorkspaceScenePreparationWorker()
    private let renderWorker = CanvasRenderWorker()
    private let selectionRegistry = SelectionCommandRegistry()
    private let selectionOverlayPlanner = SelectionOverlayPlanner()
    private let insertionRegistry = InsertionCommandRegistry()
    private let dragDropRegistry = DragDropCommandRegistry()
    private let textEditingRegistry = InlineTextCommandRegistry()
    private let transformRegistry = TransformCommandRegistry()
    private let geometryInspectorRegistry = GeometryInspectorCommandRegistry()
    private let containerLayoutRegistry = ContainerLayoutCommandRegistry()
    private let responsiveVisibilityRegistry = ResponsiveVisibilityCommandRegistry()
    private let designInspectorRegistry = DesignInspectorCommandRegistry()
    private let designBoxStyleRegistry = DesignBoxStyleCommandRegistry()
    private let typographyRegistry = TypographyCommandRegistry()
    private let imageImportWorker = ImageImportWorker()
    private let imageThumbnailWorker = ImageThumbnailWorker()
    private let imageInspectorRegistry = ImageInspectorCommandRegistry()
    private let snapResolver = SnapResolver()
    private let guideRegistry = GuideCommandRegistry()
    private let renderSurfaceID = CanvasRenderSurfaceID()
    let canvasRenderDiagnostics = CanvasRenderDiagnostics()
    let selectionDiagnostics = SelectionDiagnostics()
    let insertionDiagnostics = InsertionDiagnostics()
    let dragDropDiagnostics = DragDropDiagnostics()
    let textEditingDiagnostics = TextEditDiagnostics()
    let transformDiagnostics = TransformDiagnostics()
    let geometryInspectorDiagnostics = GeometryInspectorDiagnostics()
    let containerLayoutDiagnostics = ContainerLayoutDiagnostics()
    let responsiveVisibilityDiagnostics = ResponsiveVisibilityDiagnostics()
    let snapDiagnostics = SnapDiagnostics()
    let viewportDiagnostics: CanvasViewportDiagnostics
    private let announcementPoster: AccessibilityAnnouncementPoster
    private var viewportDocumentID: DocumentID
    private var preparationTask: Task<Void, Never>?
    private var previousRenderScene: CanvasRenderSceneSnapshot?
    private var selectionScene: SelectionSceneSnapshot?
    private var pendingSelectionLifecycleBoundary: SelectionLifecycleBoundary?
    private var pendingSelectionAfterInsertion: NodeID?
    private var retainedTextEditingFrame: WorldRect?
    // A viewport is editor convenience state. Fit a fresh/adopted document
    // once after the AppKit canvas has a real usable size, then retain that
    // fit on resizes until user navigation changes the policy.
    private var shouldInitialFitViewport = true
    private var activePointerDragTransfer: LocalLayerDragTransfer?
    private var activePointerDropCallback: LocalLayerDragCallbackToken?
    private var pointerDragCallbackGeneration: UInt64 = 0
    private var thumbnailTasks: [AssetID: Task<Void, Never>] = [:]

    init(
        documentSession: DocumentSession = DocumentSession(),
        lifecycle: DocumentLifecycleController? = nil,
        viewportPreparer: CanvasViewportScenePreparer = CanvasViewportScenePreparer(),
        viewportDiagnostics: CanvasViewportDiagnostics = CanvasViewportDiagnostics(),
        announcementPoster: AccessibilityAnnouncementPoster = .native
    ) {
        self.documentSession = documentSession
        viewportState = try! CanvasViewportState()
        viewportDocumentID = documentSession.document.id
        self.viewportPreparer = viewportPreparer
        self.viewportDiagnostics = viewportDiagnostics
        self.announcementPoster = announcementPoster
        selectedPageID = documentSession.document.pages.first?.id
        let lifecycle = lifecycle ?? DocumentLifecycleController(session: documentSession)
        precondition(lifecycle.session === documentSession, "Workspace state and lifecycle must own the same session")
        self.lifecycle = lifecycle
        documentSessionObservation = documentSession.$document.dropFirst().sink { [weak self] document in
            // `DocumentSession` publishes synchronously as a transaction
            // commits. Forwarding that publication directly into the shell
            // can occur while SwiftUI is reconciling the originating control
            // (notably an Inspector or Layers button), which is undefined.
            // Synchronize derived editor state on the next main event turn;
            // the revision guard makes superseded publications neutral.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.documentSession.document.id == document.id,
                      self.documentSession.document.revision == document.revision else {
                    return
                }
                self.synchronizeViewportDocumentBoundary(document)
            }
        }
        refreshImageThumbnails(for: documentSession.document)
    }

    var canUndo: Bool { documentSession.canUndo }
    var canRedo: Bool { documentSession.canRedo }
    var nextUndoLabel: String? { documentSession.nextUndoLabel }
    var nextRedoLabel: String? { documentSession.nextRedoLabel }
    var undoDisabledReason: String? { documentSession.undoAvailability.disabledReason }
    var redoDisabledReason: String? { documentSession.redoAvailability.disabledReason }

    var imageAssets: [ImageAsset] {
        let query = assetSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return documentSession.document.imageAssets }
        return documentSession.document.imageAssets.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.originalFilename.localizedCaseInsensitiveContains(query)
        }
    }

    func imageAssetUsageCount(_ assetID: AssetID) -> Int {
        let reference = assetID.description
        return documentSession.document.pages.flatMap(\.nodes).filter {
            $0.insertionStringProperty(CanonicalImageStyle.namespace + "assetID") == reference
        }.count
    }

    func imageAssetData(_ assetID: AssetID) -> Data? {
        guard let asset = documentSession.document.imageAssets.first(where: { $0.id == assetID }) else { return nil }
        return try? lifecycle.projectResourceData(for: asset.resourceID)
    }

    func imageAssetThumbnail(_ assetID: AssetID) -> Data? {
        imageThumbnailData[assetID]
    }

    private func refreshImageThumbnails(for document: CanonicalDocument) {
        let liveIDs = Set(document.imageAssets.map(\.id))
        imageThumbnailData = imageThumbnailData.filter { liveIDs.contains($0.key) }
        for (id, task) in thumbnailTasks where !liveIDs.contains(id) {
            task.cancel()
            thumbnailTasks[id] = nil
        }
        for asset in document.imageAssets where imageThumbnailData[asset.id] == nil && thumbnailTasks[asset.id] == nil {
            guard let bytes = try? lifecycle.projectResourceData(for: asset.resourceID) else { continue }
            let expectedResourceID = asset.resourceID
            thumbnailTasks[asset.id] = Task { [weak self] in
                guard let self else { return }
                defer { thumbnailTasks[asset.id] = nil }
                guard let thumbnail = try? await imageThumbnailWorker.thumbnailPNG(from: bytes),
                      !Task.isCancelled,
                      documentSession.document.imageAssets.contains(where: {
                          $0.id == asset.id && $0.resourceID == expectedResourceID
                      }) else { return }
                imageThumbnailData[asset.id] = thumbnail
            }
        }
    }

    func insertSelectedImage() {
        guard selectedAssetID != nil else {
            lastAssetAnnouncement = "Select an imported image first"
            announcementPoster.post(lastAssetAnnouncement)
            return
        }
        performDefaultInsertion(.image, provenance: .accessibility)
    }

    func revealImageUsage(_ assetID: AssetID) {
        let reference = assetID.description
        guard let page = documentSession.document.pages.first(where: { page in
            page.nodes.contains { $0.insertionStringProperty(CanonicalImageStyle.namespace + "assetID") == reference }
        }), let node = page.nodes.first(where: {
            $0.insertionStringProperty(CanonicalImageStyle.namespace + "assetID") == reference
        }) else {
            lastAssetAnnouncement = "This image asset is unused"
            announcementPoster.post(lastAssetAnnouncement)
            return
        }
        if effectiveSelectedPageID != page.id { selectPage(page.id) }
        navigatorTab = .layers
        DispatchQueue.main.async { [weak self] in
            self?.selectLayer(node.id, modifier: .replace)
        }
    }

    func replaceImageAsset(_ assetID: AssetID) {
        guard let url = NativeImageOpenPanel.chooseReplacement() else {
            lastAssetAnnouncement = "Image replacement cancelled; the project is unchanged"
            return
        }
        let expectedRevision = documentSession.document.revision
        isImportingImages = true
        Task { [weak self] in
            guard let self else { return }
            defer { isImportingImages = false }
            do {
                let prepared = try await imageImportWorker.prepare(url: url)
                guard documentSession.document.revision == expectedRevision,
                      var existing = documentSession.document.imageAssets.first(where: { $0.id == assetID }) else {
                    lastAssetAnnouncement = "Replacement ignored because the document changed"
                    return
                }
                if documentSession.document.imageAssets.contains(where: {
                    $0.id != assetID && $0.contentHash == prepared.asset.contentHash
                }) {
                    lastAssetAnnouncement = "That image is already imported as another asset"
                    return
                }
                existing.resourceID = prepared.asset.resourceID
                existing.originalFilename = prepared.asset.originalFilename
                existing.format = prepared.asset.format
                existing.pixelWidth = prepared.asset.pixelWidth
                existing.pixelHeight = prepared.asset.pixelHeight
                existing.byteCount = prepared.asset.byteCount
                existing.contentHash = prepared.asset.contentHash
                _ = try lifecycle.installingProjectResource(prepared.descriptor, data: prepared.data) {
                    try documentSession.execute(.updateImageAsset(.init(asset: existing)))
                }
                imageThumbnailData[assetID] = nil
                refreshImageThumbnails(for: documentSession.document)
                lastAssetAnnouncement = "Replaced image asset and updated \(imageAssetUsageCount(assetID)) use\(imageAssetUsageCount(assetID) == 1 ? "" : "s")"
                announcementPoster.post(lastAssetAnnouncement)
            } catch let error as ImageImportError {
                lastAssetAnnouncement = error.localizedDescription
                announcementPoster.post(lastAssetAnnouncement)
            } catch {
                lastAssetAnnouncement = "The image could not be replaced"
            }
        }
    }

    func importImages(insertFirst: Bool = false) {
        guard let urls = NativeImageOpenPanel.chooseImages(insertFirst: insertFirst) else {
            lastAssetAnnouncement = "Image import cancelled; the project is unchanged"
            announcementPoster.post(lastAssetAnnouncement)
            return
        }
        importImageURLs(urls, insertFirst: insertFirst)
    }

    /// Production import boundary shared by the native panel and document
    /// reopen/recovery tests. URLs are consumed only while importing and are
    /// never retained in canonical state or diagnostics.
    func importImageURLs(_ urls: [URL], insertFirst: Bool = false) {
        guard !urls.isEmpty else { return }
        let expectedDocumentID = documentSession.document.id
        var expectedRevision = documentSession.document.revision
        isImportingImages = true
        lastAssetAnnouncement = "Importing \(urls.count) image\(urls.count == 1 ? "" : "s")…"
        Task { [weak self] in
            guard let self else { return }
            var insertedAssetID: AssetID?
            var imported = 0
            var duplicate = 0
            var lastFailure: ImageImportError?
            for url in urls {
                do {
                    let prepared = try await imageImportWorker.prepare(url: url)
                    guard documentSession.document.id == expectedDocumentID,
                          documentSession.document.revision == expectedRevision else {
                        lastAssetAnnouncement = "Import stopped because the document changed"
                        break
                    }
                    if let existing = documentSession.document.imageAssets.first(where: {
                        $0.contentHash == prepared.asset.contentHash
                    }) {
                        duplicate += 1
                        selectedAssetID = existing.id
                        insertedAssetID = insertedAssetID ?? existing.id
                        continue
                    }
                    _ = try lifecycle.installingProjectResource(prepared.descriptor, data: prepared.data) {
                        try documentSession.execute(.insertImageAsset(.init(
                            asset: prepared.asset,
                            index: documentSession.document.imageAssets.count
                        )))
                    }
                    expectedRevision = documentSession.document.revision
                    refreshImageThumbnails(for: documentSession.document)
                    selectedAssetID = prepared.asset.id
                    insertedAssetID = insertedAssetID ?? prepared.asset.id
                    imported += 1
                } catch is CancellationError {
                    lastFailure = .cancelled
                } catch let error as ImageImportError {
                    lastFailure = error
                } catch {
                    lastFailure = .ioFailure
                }
            }
            isImportingImages = false
            if let lastFailure, imported == 0, duplicate == 0 {
                lastAssetAnnouncement = lastFailure.localizedDescription
            } else {
                var parts = ["Imported \(imported) image\(imported == 1 ? "" : "s")"]
                if duplicate > 0 { parts.append("reused \(duplicate) duplicate") }
                if let lastFailure { parts.append("last failure: \(lastFailure.localizedDescription)") }
                lastAssetAnnouncement = parts.joined(separator: "; ")
            }
            announcementPoster.post(lastAssetAnnouncement)
            if insertFirst, let insertedAssetID {
                selectedAssetID = insertedAssetID
                performDefaultInsertion(.image, provenance: .accessibility)
            }
        }
    }

    func renameImageAsset(_ assetID: AssetID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= ImageAsset.maximumDisplayNameBytes,
              var asset = documentSession.document.imageAssets.first(where: { $0.id == assetID }) else {
            lastAssetAnnouncement = "Asset names cannot be empty"
            return
        }
        asset.displayName = name
        do {
            _ = try documentSession.execute(.updateImageAsset(.init(asset: asset)))
            lastAssetAnnouncement = "Renamed image asset"
            announcementPoster.post(lastAssetAnnouncement)
        } catch { lastAssetAnnouncement = error.localizedDescription }
    }

    func requestDeleteImageAsset(_ assetID: AssetID) {
        let uses = imageAssetUsageCount(assetID)
        if uses > 0 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Delete this image and its uses?"
            alert.informativeText = "This asset is used by \(uses) Image object\(uses == 1 ? "" : "s"). SiteForge can remove those objects and the asset together as one undoable edit, or leave the project unchanged."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Delete Uses and Asset")
            guard alert.runModal() == .alertSecondButtonReturn else {
                lastAssetAnnouncement = "Asset deletion cancelled; the project is unchanged"
                announcementPoster.post(lastAssetAnnouncement)
                return
            }
        }
        deleteImageAssetAndUses(assetID)
    }

    /// Explicit safe resolution for an in-use asset. Referencing Image nodes
    /// are leaves by canonical validation, so their removals and the asset
    /// removal form one exact-inverse batch transaction.
    func deleteImageAssetAndUses(_ assetID: AssetID) {
        let reference = assetID.description
        let nodeRemovals = documentSession.document.pages.flatMap { page in
            page.nodes.filter {
                $0.kind == .image && $0.insertionStringProperty(CanonicalImageStyle.namespace + "assetID") == reference
            }.map { DocumentCommand.removeNode(.init(pageID: page.id, nodeID: $0.id)) }
        }
        let command: DocumentCommand = nodeRemovals.isEmpty
            ? .removeImageAsset(.init(assetID: assetID))
            : .batch(nodeRemovals + [.removeImageAsset(.init(assetID: assetID))])
        do {
            _ = try documentSession.execute(command)
            if selectedAssetID == assetID { selectedAssetID = nil }
            imageThumbnailData[assetID] = nil
            lastAssetAnnouncement = nodeRemovals.isEmpty
                ? "Deleted unused image asset"
                : "Deleted image asset and \(nodeRemovals.count) use\(nodeRemovals.count == 1 ? "" : "s")"
            announcementPoster.post(lastAssetAnnouncement)
        } catch { lastAssetAnnouncement = error.localizedDescription }
    }

    func imageInspectorPresentation() -> ImageInspectorPresentation {
        guard let pageID = effectiveSelectedPageID,
              let page = documentSession.document.pages.first(where: { $0.id == pageID }),
              !selectionState.orderedIDs.isEmpty else {
            return .unavailable("Select an Image to edit image properties.")
        }
        let selected = selectionState.orderedIDs.compactMap { id in page.nodes.first(where: { $0.id == id }) }
        let applicable = selected.filter { $0.kind == .image }
        guard !applicable.isEmpty else { return .unavailable("Image controls apply only to Image elements.") }
        let styles = applicable.compactMap(CanonicalImageStyle.resolve)
        guard styles.count == applicable.count else { return .unavailable("A selected Image has invalid or missing metadata.") }
        if styles.allSatisfy({ $0 == styles[0] }),
           let asset = documentSession.document.imageAssets.first(where: { $0.id == styles[0].assetID }) {
            return .single(styles[0], asset)
        }
        return .mixed(applicable: applicable.count, skipped: selected.count - applicable.count)
    }

    @discardableResult
    func commitImageInspectorEdit(_ edit: ImageInspectorEdit) -> Bool {
        guard let pageID = effectiveSelectedPageID, let plan = canvasRenderPlan else {
            imageInspectorFailure = .staleRenderer
            return false
        }
        let identity = ImageInspectorOperationIdentity(
            documentID: documentSession.document.id, pageID: pageID,
            revision: documentSession.document.revision,
            sceneID: plan.identity.sceneID,
            rendererGeneration: plan.identity.sceneGeneration,
            selectedNodeIDs: selectionState.orderedIDs
        )
        do {
            let prepared = try imageInspectorRegistry.prepare(
                ImageInspectorCommand(identity: identity, edit: edit),
                in: documentSession.document, context: transformValidationContext
            )
            _ = try documentSession.execute(prepared.command)
            imageInspectorFailure = nil
            lastImageInspectorAnnouncement = "Image properties committed for \(prepared.applicableNodeIDs.count) object\(prepared.applicableNodeIDs.count == 1 ? "" : "s")"
            if !prepared.skippedNodeIDs.isEmpty {
                lastImageInspectorAnnouncement += "; skipped \(prepared.skippedNodeIDs.count) incompatible object\(prepared.skippedNodeIDs.count == 1 ? "" : "s")"
            }
            announcementPoster.post(lastImageInspectorAnnouncement)
            return true
        } catch let error as ImageInspectorError {
            imageInspectorFailure = error
            lastImageInspectorAnnouncement = error.localizedDescription
            announcementPoster.post(lastImageInspectorAnnouncement)
            return false
        } catch {
            imageInspectorFailure = .missingTarget
            return false
        }
    }

    func selectTool(_ tool: CanvasTool) {
        if selectedTool != tool {
            cancelDragDrop()
            cancelInsertion(resetTool: false)
            cancelTransform()
            cancelGuideEditing()
            cancelTextEditing()
        }
        selectedTool = tool
        switch tool {
        case .section: armInsertion(.section)
        case .stack: armInsertion(.stack)
        case .grid: armInsertion(.grid)
        case .frame: armInsertion(.frame)
        case .text: armInsertion(.text)
        case .image:
            if selectedAssetID != nil {
                armInsertion(.image)
            } else {
                // Tool selection is a scene-local state transition. Opening a
                // modal import panel here would make programmatic, keyboard,
                // and accessibility tool selection unexpectedly blocking.
                // The visible Assets and Insert commands own native import.
                insertionSession.deactivate()
                navigatorTab = .assets
                lastAssetAnnouncement = "Import or select an image before placing an Image"
                announcementPoster.post(lastAssetAnnouncement)
            }
        default: insertionSession.deactivate()
        }
    }

    var pages: [DocumentPage] { documentSession.document.pages }

    var effectiveSelectedPageID: PageID? {
        guard let selectedPageID, pages.contains(where: { $0.id == selectedPageID }) else {
            return pages.first?.id
        }
        return selectedPageID
    }

    func selectPage(_ pageID: PageID) {
        guard pages.contains(where: { $0.id == pageID }) else { return }
        cancelDragDrop()
        cancelInsertion(resetTool: true)
        cancelTransform()
        cancelGuideEditing()
        cancelTextEditing()
        selectedGuideID = nil
        selectedPageID = pageID
        refreshSelectionScene(boundary: .pageSwitch)
    }

    func adjacentPage(to pageID: PageID, offset: Int) -> PageID? {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else {
            return pages.first?.id
        }
        let destination = min(max(0, index + offset), pages.count - 1)
        return pages[destination].id
    }

    var zoomPercent: Int { viewportState.zoom.percent }

    var viewportAccessibilityValue: String {
        String(
            format: "Zoom %d percent; origin %.1f, %.1f; interactions %d",
            zoomPercent,
            viewportState.worldOrigin.x,
            viewportState.worldOrigin.y,
            canvasInteractionCount
        )
    }

    func adjustZoom(by delta: Int) {
        let command: CanvasViewportCommandName = delta < 0 ? .zoomOut : .zoomIn
        let steps = max(1, abs(delta) / 25)
        for _ in 0..<steps { performViewportCommand(CanvasViewportCommand(command)) }
    }

    func performViewportCommand(_ command: CanvasViewportCommand) {
        let start = DispatchTime.now().uptimeNanoseconds
        let committed = viewportState
        do {
            try viewportRegistry.apply(command, to: &viewportState)
            viewportFailure = nil
            announceViewport(command.name)
            recordViewportDiagnostic(command.name, start: start, result: .success, failure: nil)
            cancelDragDrop()
            scheduleScenePreparation()
        } catch let error as CanvasViewportError {
            viewportState = committed
            viewportFailure = error
            recordViewportDiagnostic(command.name, start: start, result: .failure, failure: String(describing: error))
        } catch {
            viewportState = committed
        }
    }

    func zoom(to value: Double, around anchor: ViewportPoint) {
        let start = DispatchTime.now().uptimeNanoseconds
        let committed = viewportState
        let operation: CanvasViewportCommandName = value >= committed.zoom.value ? .zoomIn : .zoomOut
        do {
            try viewportState.zoom(to: value, around: anchor)
            viewportFailure = nil
            announceViewport(operation)
            recordViewportDiagnostic(operation, start: start, result: .success, failure: nil)
            cancelDragDrop()
            scheduleScenePreparation()
        } catch let error as CanvasViewportError {
            viewportState = committed
            viewportFailure = error
            recordViewportDiagnostic(operation, start: start, result: .failure, failure: String(describing: error))
        } catch {
            viewportState = committed
        }
    }

    func magnify(by factor: Double, around anchor: ViewportPoint) {
        zoom(to: viewportState.zoom.value * factor, around: anchor)
    }

    func panViewport(by delta: ViewportVector) {
        let committed = viewportState
        do {
            try viewportState.pan(by: delta)
            viewportFailure = nil
            cancelDragDrop()
            scheduleScenePreparation()
        } catch let error as CanvasViewportError {
            viewportState = committed
            viewportFailure = error
        } catch {
            viewportState = committed
        }
    }

    func resizeViewport(to size: ViewportSize, pixelRatio: Double) {
        guard size != viewportState.viewportSize || pixelRatio != viewportState.pixelRatio.value else { return }
        let committed = viewportState
        do {
            try viewportState.resize(to: size, pixelRatio: pixelRatio)
            if shouldInitialFitViewport {
                // New documents begin with the actual preset artboard fitted
                // inside the usable canvas. This leaves an honest surrounding
                // pasteboard/grid gutter instead of presenting an oversized
                // Desktop artboard as if it were the entire canvas.
                try viewportState.fit(.fitDocument)
                shouldInitialFitViewport = false
            }
            viewportFailure = nil
            cancelDragDrop()
            scheduleScenePreparation()
        } catch let error as CanvasViewportError {
            viewportState = committed
            viewportFailure = error
        } catch {
            viewportState = committed
        }
    }

    func cancelViewportPreparation() {
        preparationTask?.cancel()
        preparationTask = nil
    }

    func prepareViewportScene(objects: [CanvasViewportSceneObject]) async throws -> PreparedCanvasViewportScene {
        let identity = currentViewportOperationIdentity
        let request = CanvasViewportPreparationRequest(identity: identity, viewport: viewportState, objects: objects)
        let result = try await viewportPreparer.prepare(
            request,
            cancellation: CanvasViewportCancellation(isCancelled: { Task.isCancelled })
        )
        try CanvasViewportAdoptionGate().validate(result, expected: currentViewportOperationIdentity)
        preparedViewportScene = result
        return result
    }

    var currentViewportOperationIdentity: CanvasViewportOperationIdentity {
        CanvasViewportOperationIdentity(
            documentID: documentSession.document.id,
            revision: documentSession.document.revision,
            sceneID: viewportState.sceneID,
            generation: viewportState.generation
        )
    }

    func noteCanvasInteraction() {
        canvasInteractionCount += 1
    }

    var layerTargets: [SelectionTargetSnapshot] {
        guard let scene = selectionScene else { return [] }
        return scene.targets
            .filter { $0.pageID == scene.activePageID && $0.isAvailable }
            .sorted {
                $0.paintOrder == $1.paintOrder
                    ? $0.id.description < $1.id.description
                    : $0.paintOrder < $1.paintOrder
            }
    }

    var selectionSummary: String {
        switch selectionState.count {
        case 0: "Nothing selected"
        case 1:
            layerTargets.first(where: { $0.id == selectionState.primaryID })?.name ?? "One object selected"
        default: "\(selectionState.count) objects selected"
        }
    }

    var selectionPath: String {
        guard let pageID = effectiveSelectedPageID,
              let page = pages.first(where: { $0.id == pageID }) else { return "No selection" }
        guard !selectionState.isEmpty else { return "\(page.name) / No selection" }
        if selectionState.count > 1 { return "\(page.name) / \(selectionState.count) objects" }
        return "\(page.name) / \(selectionSummary)"
    }

    /// A stable, content-independent accessibility value for the status bar.
    /// The visible path remains useful context, while assistive clients can
    /// query the actual selection cardinality without parsing page or layer
    /// names. This is editor convenience state derived solely from the
    /// scene-owned selection model.
    var selectionAccessibilityValue: String {
        guard !selectionState.isEmpty else { return "0 selected" }
        let artboardStatus = selectionOutsideActiveArtboard
            ? "; selection outside \(viewportPreset.title) artboard"
            : ""
        return "\(selectionState.count) selected; primary selection present\(artboardStatus)"
    }

    /// Breakpoint clipping is a renderer-presentation boundary, not a reason
    /// to mutate or clear an otherwise valid active-page selection.
    var selectionOutsideActiveArtboard: Bool {
        guard !selectionState.isEmpty, let plan = canvasRenderPlan else { return false }
        let artboard = viewportState.contentBounds
        return selectionState.orderedIDs.contains { id in
            guard let object = plan.authoredObjects.first(where: { $0.id == id }) else { return false }
            return object.frame.maxX <= artboard.minX || object.frame.minX >= artboard.maxX
                || object.frame.maxY <= artboard.minY || object.frame.minY >= artboard.maxY
        }
    }

    var selectionArtboardStatus: String? {
        selectionOutsideActiveArtboard
            ? "Selection outside \(viewportPreset.title) artboard"
            : nil
    }

    func revealSelection() {
        guard let plan = canvasRenderPlan,
              let primaryID = selectionState.primaryID,
              let object = plan.authoredObjects.first(where: { $0.id == primaryID }) else { return }
        // Desktop is the largest existing preview artboard. This changes only
        // editor presentation and reveals fixed Desktop geometry; it never
        // moves or reflows the canonical document.
        if selectionOutsideActiveArtboard, viewportPreset != .desktop {
            viewportPreset = .desktop
        }
        do {
            try viewportState.reveal(object.frame)
            lastViewportAnnouncement = "Revealed selection without changing authored geometry"
            scheduleScenePreparation()
        } catch {
            viewportFailure = .invalidSize
        }
    }

    var transformGeometrySummary: String {
        guard let primaryID = selectionState.primaryID,
              let geometry = documentSession.document.pages
                .flatMap(\.nodes)
                .first(where: { $0.id == primaryID })?
                .insertionGeometry else {
            return "Geometry unavailable"
        }
        return String(
            format: "X %.0f, Y %.0f, Width %.0f, Height %.0f",
            geometry.origin.x,
            geometry.origin.y,
            geometry.size.width,
            geometry.size.height
        )
    }

    /// Fixed Inspector fields read the same authored values consumed by the
    /// transform, renderer, selection, and package pipelines. Draft strings
    /// remain in the view and never enter this state or the canonical model.
    func geometryInspectorValue(for field: GeometryInspectorField) -> GeometryInspectorValue {
        geometryInspectorRegistry.value(
            for: field,
            in: documentSession.document,
            context: transformValidationContext,
            breakpoint: viewportPreset.responsiveBreakpoint
        )
    }

    func geometryInspectorResponsiveSource(for field: GeometryInspectorField) -> String? {
        if viewportPreset.responsiveBreakpoint == .desktop {
            if case .single(_, let origin) = geometryInspectorValue(for: field) {
                return origin == .authored ? "authored at Desktop" : "defaulted at Desktop"
            }
            return geometryInspectorValue(for: field) == .mixed ? "Mixed Desktop values" : nil
        }
        guard let pageID = effectiveSelectedPageID,
              let page = documentSession.document.pages.first(where: { $0.id == pageID }) else { return nil }
        let nodes = selectionState.orderedIDs.compactMap { id in page.nodes.first(where: { $0.id == id }) }
            .filter { GeometryInspectorCommandRegistry.supportsFixedGeometry($0.kind) }
        guard !nodes.isEmpty else { return nil }
        let sources = nodes.compactMap {
            ResponsiveGeometryResolver.value(for: field, node: $0, breakpoint: viewportPreset.responsiveBreakpoint)?.2
        }
        guard sources.count == nodes.count, let first = sources.first,
              sources.dropFirst().allSatisfy({ $0 == first }) else { return "Mixed breakpoint sources" }
        return first.label
    }

    var hasGeometryOverridesAtCurrentBreakpoint: Bool {
        let breakpoint = viewportPreset.responsiveBreakpoint
        guard breakpoint != .desktop else { return false }
        return selectedCanonicalNodes.contains { node in
            GeometryInspectorField.allCases.contains {
                node.insertionProperty(ResponsiveGeometryResolver.key($0, breakpoint: breakpoint)) != nil
            }
        }
    }

    var geometryInspectorSelectionKey: String {
        selectionState.orderedIDs.map(\.description).joined(separator: ",")
            + ":\(documentSession.document.revision)"
    }

    var hasContainerLayoutSelection: Bool {
        selectedCanonicalNodes.contains { [.section, .stack, .grid].contains($0.kind) }
    }

    /// Operation feedback belongs to the exact selection and breakpoint that
    /// produced it. The Inspector recomputes this presentation instead of
    /// publishing another state mutation while a SwiftUI selection/preset
    /// update is in flight.
    var currentContainerLayoutAnnouncement: String {
        containerLayoutAnnouncementContext?.matches(
            breakpoint: viewportPreset.responsiveBreakpoint,
            orderedNodeIDs: selectionState.orderedIDs
        ) == true ? lastContainerLayoutAnnouncement : "Container layout inactive"
    }

    var currentResponsiveVisibilityAnnouncement: String {
        responsiveVisibilityAnnouncementContext?.matches(
            breakpoint: viewportPreset.responsiveBreakpoint,
            orderedNodeIDs: selectionState.orderedIDs
        ) == true ? lastResponsiveVisibilityAnnouncement : "Breakpoint visibility inactive"
    }

    func containerLayoutValue(for field: ContainerLayoutField) -> ContainerLayoutInspectorValue {
        containerLayoutRegistry.value(
            for: field,
            in: documentSession.document,
            context: transformValidationContext,
            breakpoint: viewportPreset.responsiveBreakpoint
        )
    }

    func containerLayoutResponsiveSource(for field: ContainerLayoutField) -> String? {
        let values = selectedCanonicalNodes.filter { ContainerLayoutCommandRegistry.supports(field, kind: $0.kind) }
            .compactMap { ResponsiveContainerLayoutResolver.value(for: field, node: $0,
                breakpoint: viewportPreset.responsiveBreakpoint)?.2 }
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else {
            return values.isEmpty ? nil : "Mixed breakpoint sources"
        }
        return first == .baseDesktop && viewportPreset == .desktop ? "Desktop base" : first.label
    }

    func hasContainerLayoutOverride(_ field: ContainerLayoutField) -> Bool {
        let breakpoint = viewportPreset.responsiveBreakpoint
        guard breakpoint != .desktop else { return false }
        return selectedCanonicalNodes.contains {
            $0.insertionProperty(ResponsiveContainerLayoutResolver.key(field, breakpoint: breakpoint)) != nil
        }
    }

    func containerLayoutAvailability(for field: ContainerLayoutField) -> TransformAvailability {
        guard let plan = canvasRenderPlan, let pageID = effectiveSelectedPageID else {
            return .disabled("Wait for the canvas, then select a Section, Stack, or Grid.")
        }
        let sample: ContainerLayoutValue = switch field {
        case .padding, .gap: .number(0)
        case .columns: .number(1)
        case .axis: .axis(.vertical)
        case .alignment: .alignment(.start)
        }
        do {
            _ = try containerLayoutRegistry.prepare(.init(
                identity: .init(editID: GeometryInspectorEditID(), documentID: documentSession.document.id,
                    pageID: pageID, revision: documentSession.document.revision,
                    sceneID: plan.identity.sceneID, rendererGeneration: plan.identity.sceneGeneration),
                orderedNodeIDs: selectionState.orderedIDs, field: field, value: sample,
                provenance: .automation, cancelled: false,
                breakpoint: viewportPreset.responsiveBreakpoint
            ), in: documentSession.document, context: transformValidationContext)
            return .enabled
        } catch ContainerLayoutError.noChanges {
            return .enabled
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    @discardableResult
    func commitContainerLayout(
        field: ContainerLayoutField,
        value: ContainerLayoutValue?,
        provenance: ContainerLayoutProvenance
    ) -> Bool {
        guard let plan = canvasRenderPlan, let pageID = effectiveSelectedPageID else { return false }
        let started = DispatchTime.now().uptimeNanoseconds
        let command = ContainerLayoutCommand(
            identity: .init(editID: GeometryInspectorEditID(), documentID: documentSession.document.id,
                pageID: pageID, revision: documentSession.document.revision,
                sceneID: plan.identity.sceneID, rendererGeneration: plan.identity.sceneGeneration),
            orderedNodeIDs: selectionState.orderedIDs,
            field: field,
            value: value,
            provenance: provenance,
            cancelled: false,
            breakpoint: viewportPreset.responsiveBreakpoint,
            removesOverride: value == nil && viewportPreset.responsiveBreakpoint != .desktop
        )
        do {
            let prepared = try containerLayoutRegistry.prepare(
                command, in: documentSession.document, context: transformValidationContext
            )
            _ = try documentSession.execute(prepared.documentCommand)
            containerLayoutFailure = nil
            let reset = value == nil
                ? (viewportPreset.responsiveBreakpoint == .desktop ? " reset to default" : " override removed")
                : " committed for \(viewportPreset.title)"
            let skipped = prepared.skippedNodeIDs.isEmpty
                ? ""
                : "; \(prepared.skippedNodeIDs.count) incompatible selection\(prepared.skippedNodeIDs.count == 1 ? "" : "s") unchanged"
            lastContainerLayoutAnnouncement = "\(field.title)\(reset) for \(prepared.applicableNodeIDs.count) container\(prepared.applicableNodeIDs.count == 1 ? "" : "s")\(skipped)"
            containerLayoutAnnouncementContext = .init(
                breakpoint: viewportPreset.responsiveBreakpoint,
                orderedNodeIDs: selectionState.orderedIDs
            )
            announcementPoster.post(lastContainerLayoutAnnouncement)
            recordContainerLayoutDiagnostic(command, started: started, result: .success, failure: nil)
            return true
        } catch let error as ContainerLayoutError {
            containerLayoutFailure = error
            lastContainerLayoutAnnouncement = error.localizedDescription
            containerLayoutAnnouncementContext = .init(
                breakpoint: viewportPreset.responsiveBreakpoint,
                orderedNodeIDs: selectionState.orderedIDs
            )
            announcementPoster.post(lastContainerLayoutAnnouncement)
            let result: ContainerLayoutDiagnosticResult = error == .cancelled ? .cancelled
                : [.staleDocument, .staleRevision, .staleRenderer, .selectionMismatch].contains(error) ? .stale : .failure
            recordContainerLayoutDiagnostic(command, started: started, result: result, failure: error)
            return false
        } catch {
            containerLayoutFailure = .staleRevision
            lastContainerLayoutAnnouncement = ContainerLayoutError.staleRevision.localizedDescription
            containerLayoutAnnouncementContext = .init(
                breakpoint: viewportPreset.responsiveBreakpoint,
                orderedNodeIDs: selectionState.orderedIDs
            )
            announcementPoster.post(lastContainerLayoutAnnouncement)
            recordContainerLayoutDiagnostic(command, started: started, result: .stale, failure: .staleRevision)
            return false
        }
    }

    private func recordContainerLayoutDiagnostic(
        _ command: ContainerLayoutCommand,
        started: UInt64,
        result: ContainerLayoutDiagnosticResult,
        failure: ContainerLayoutError?
    ) {
        let record = ContainerLayoutDiagnosticFactory.make(
            command: command,
            durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
            resultRevision: result == .success ? documentSession.document.revision : nil,
            result: result,
            failure: failure
        )
        Task { await containerLayoutDiagnostics.append(record) }
    }

    func cancelContainerLayoutDraft(field: ContainerLayoutField) {
        containerLayoutFailure = nil
        lastContainerLayoutAnnouncement = "Container layout draft cancelled; committed layout is unchanged"
        containerLayoutAnnouncementContext = .init(
            breakpoint: viewportPreset.responsiveBreakpoint,
            orderedNodeIDs: selectionState.orderedIDs
        )
        announcementPoster.post(lastContainerLayoutAnnouncement)
        guard let plan = canvasRenderPlan, let pageID = effectiveSelectedPageID else { return }
        let command = ContainerLayoutCommand(
            identity: .init(
                editID: GeometryInspectorEditID(), documentID: documentSession.document.id,
                pageID: pageID, revision: documentSession.document.revision,
                sceneID: plan.identity.sceneID, rendererGeneration: plan.identity.sceneGeneration
            ),
            orderedNodeIDs: selectionState.orderedIDs,
            field: field,
            value: nil,
            provenance: .keyboard,
            cancelled: true,
            breakpoint: viewportPreset.responsiveBreakpoint
        )
        recordContainerLayoutDiagnostic(
            command,
            started: DispatchTime.now().uptimeNanoseconds,
            result: .cancelled,
            failure: .cancelled
        )
    }

    var responsiveVisibilityValue: ResponsiveVisibilityInspectorValue {
        responsiveVisibilityRegistry.value(in: documentSession.document, context: transformValidationContext,
                                           breakpoint: viewportPreset.responsiveBreakpoint)
    }

    var hasVisibilityOverrideAtCurrentBreakpoint: Bool {
        let breakpoint = viewportPreset.responsiveBreakpoint
        guard breakpoint != .desktop else { return false }
        return selectedCanonicalNodes.contains { $0.insertionProperty(ResponsiveVisibilityResolver.key(breakpoint)) != nil }
    }

    @discardableResult
    func commitResponsiveVisibility(_ visible: Bool?, provenance: ResponsiveVisibilityProvenance) -> Bool {
        guard let plan = canvasRenderPlan, let pageID = effectiveSelectedPageID else { return false }
        let started = DispatchTime.now().uptimeNanoseconds
        let command = ResponsiveVisibilityCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: documentSession.document.id, pageID: pageID,
            revision: documentSession.document.revision, sceneID: plan.identity.sceneID,
            rendererGeneration: plan.identity.sceneGeneration), orderedNodeIDs: selectionState.orderedIDs,
            breakpoint: viewportPreset.responsiveBreakpoint, visible: visible,
            provenance: provenance, cancelled: false)
        do {
            let prepared = try responsiveVisibilityRegistry.prepare(command, in: documentSession.document,
                                                                     context: transformValidationContext)
            _ = try documentSession.execute(prepared.documentCommand)
            responsiveVisibilityFailure = nil
            let action = visible.map { $0 ? "shown" : "hidden" } ?? "reset to inherited visibility"
            lastResponsiveVisibilityAnnouncement = "\(prepared.applicableNodeIDs.count) object\(prepared.applicableNodeIDs.count == 1 ? "" : "s") \(action) at \(viewportPreset.title)"
            responsiveVisibilityAnnouncementContext = .init(
                breakpoint: viewportPreset.responsiveBreakpoint,
                orderedNodeIDs: selectionState.orderedIDs
            )
            announcementPoster.post(lastResponsiveVisibilityAnnouncement)
            recordResponsiveVisibilityDiagnostic(command, started: started, result: .success, failure: nil)
            return true
        } catch let error as ResponsiveVisibilityError {
            responsiveVisibilityFailure = error
            lastResponsiveVisibilityAnnouncement = error.localizedDescription
            responsiveVisibilityAnnouncementContext = .init(
                breakpoint: viewportPreset.responsiveBreakpoint,
                orderedNodeIDs: selectionState.orderedIDs
            )
            announcementPoster.post(lastResponsiveVisibilityAnnouncement)
            let result: ResponsiveVisibilityDiagnosticResult = error == .cancelled ? .cancelled
                : [.staleDocument, .staleRevision, .staleRenderer, .selectionMismatch].contains(error) ? .stale : .failure
            recordResponsiveVisibilityDiagnostic(command, started: started, result: result, failure: error)
            return false
        } catch {
            responsiveVisibilityFailure = .staleRevision
            lastResponsiveVisibilityAnnouncement = ResponsiveVisibilityError.staleRevision.localizedDescription
            responsiveVisibilityAnnouncementContext = .init(
                breakpoint: viewportPreset.responsiveBreakpoint,
                orderedNodeIDs: selectionState.orderedIDs
            )
            announcementPoster.post(lastResponsiveVisibilityAnnouncement)
            recordResponsiveVisibilityDiagnostic(command, started: started, result: .stale, failure: .staleRevision)
            return false
        }
    }

    private func recordResponsiveVisibilityDiagnostic(
        _ command: ResponsiveVisibilityCommand,
        started: UInt64,
        result: ResponsiveVisibilityDiagnosticResult,
        failure: ResponsiveVisibilityError?
    ) {
        let record = ResponsiveVisibilityDiagnosticFactory.make(
            command: command,
            durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
            resultRevision: result == .success ? documentSession.document.revision : nil,
            result: result,
            failure: failure
        )
        Task { await responsiveVisibilityDiagnostics.append(record) }
    }

    private var selectedCanonicalNodes: [DocumentNode] {
        guard let pageID = effectiveSelectedPageID,
              let page = documentSession.document.pages.first(where: { $0.id == pageID }) else { return [] }
        return selectionState.orderedIDs.compactMap { id in page.nodes.first(where: { $0.id == id }) }
    }

    func designInspectorFillValue() -> DesignInspectorValue {
        DesignInspectorCommandRegistry.fillValue(nodes: selectedCanonicalNodes)
    }

    func designInspectorOpacityValue() -> DesignInspectorOpacityValue {
        DesignInspectorCommandRegistry.opacityValue(nodes: selectedCanonicalNodes)
    }

    func designInspectorBoxStyleValue() -> DesignBoxStyleValue {
        DesignBoxStyleCommandRegistry.selectionValue(nodes: selectedCanonicalNodes)
    }

    func typographyInspectorValue() -> TypographyInspectorValue {
        TypographyCommandRegistry.selectionValue(nodes: selectedCanonicalNodes)
    }

    var typographyResolutionStatus: String? {
        let selected = Set(selectionState.orderedIDs)
        let missing = canvasRenderPlan?.authoredObjects.compactMap { object -> String? in
            guard selected.contains(object.id), let typography = object.typography,
                  typography.usesFallback else { return nil }
            return typography.authoredFamily
        } ?? []
        guard !missing.isEmpty else { return nil }
        return "Font unavailable: \(missing.sorted().joined(separator: ", ")). Using the system fallback; authored family is preserved."
    }

    @discardableResult
    func commitTypography(_ edit: TypographyEdit, operation: String, provenance: DesignInspectorProvenance = .keyboard) -> Bool {
        guard let pageID = effectiveSelectedPageID, let plan = canvasRenderPlan,
              plan.identity.documentID == documentSession.document.id,
              plan.identity.revision == documentSession.document.revision else {
            lastDesignInspectorAnnouncement = TypographyCommandError.stale.localizedDescription
            return false
        }
        do {
            let prepared = try typographyRegistry.prepare(.init(
                identity: .init(documentID: documentSession.document.id, pageID: pageID,
                    revision: documentSession.document.revision, sceneID: plan.identity.sceneID,
                    rendererGeneration: plan.identity.sceneGeneration),
                orderedNodeIDs: selectionState.orderedIDs, edit: edit,
                provenance: provenance, cancelled: false
            ), in: documentSession.document, context: transformValidationContext)
            _ = try documentSession.execute(prepared.documentCommand)
            let applied = prepared.applicableNodeIDs.count, skipped = prepared.skippedNodeIDs.count
            lastDesignInspectorAnnouncement = skipped == 0
                ? "Typography \(operation) committed for \(applied) object\(applied == 1 ? "" : "s")"
                : "Typography \(operation) committed for \(applied) object\(applied == 1 ? "" : "s"); skipped \(skipped) incompatible object\(skipped == 1 ? "" : "s")"
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return true
        } catch let error as TypographyCommandError {
            lastDesignInspectorAnnouncement = error.localizedDescription
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        } catch {
            lastDesignInspectorAnnouncement = "Typography \(operation) could not commit; text style is unchanged"
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        }
    }

    @discardableResult
    func commitDesignBoxStyle(_ edit: DesignBoxStyleEdit, operation: String, provenance: DesignInspectorProvenance = .keyboard) -> Bool {
        guard let pageID = effectiveSelectedPageID,
              let plan = canvasRenderPlan,
              plan.identity.documentID == documentSession.document.id,
              plan.identity.revision == documentSession.document.revision else {
            lastDesignInspectorAnnouncement = DesignBoxStyleError.stale.localizedDescription
            return false
        }
        do {
            let prepared = try designBoxStyleRegistry.prepare(.init(
                identity: .init(
                    documentID: documentSession.document.id, pageID: pageID,
                    revision: documentSession.document.revision, sceneID: plan.identity.sceneID,
                    rendererGeneration: plan.identity.sceneGeneration
                ),
                orderedNodeIDs: selectionState.orderedIDs,
                edit: edit,
                provenance: provenance,
                cancelled: false
            ), in: documentSession.document, context: transformValidationContext)
            _ = try documentSession.execute(prepared.documentCommand)
            let applied = prepared.applicableNodeIDs.count, skipped = prepared.skippedNodeIDs.count
            lastDesignInspectorAnnouncement = skipped == 0
                ? "Design \(operation) committed for \(applied) object\(applied == 1 ? "" : "s")"
                : "Design \(operation) committed for \(applied) object\(applied == 1 ? "" : "s"); skipped \(skipped) incompatible object\(skipped == 1 ? "" : "s")"
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return true
        } catch let error as DesignBoxStyleError {
            lastDesignInspectorAnnouncement = error.localizedDescription
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        } catch {
            lastDesignInspectorAnnouncement = "Design \(operation) could not commit; appearance is unchanged"
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        }
    }

    /// A scene-facing projection of canonical v1 layers across the complete
    /// selection. Exact shared stacks remain addressable by stable IDs;
    /// differing stacks are presented as mixed instead of borrowing rows from
    /// the primary selection.
    func designInspectorFillLayerSelectionValue() -> DesignFillLayerSelectionValue {
        DesignInspectorCommandRegistry.fillLayerSelectionValue(nodes: selectedCanonicalNodes)
    }

    func designInspectorFillLayers() -> [CanonicalFillLayer] {
        guard case .shared(let layers, _, _) = designInspectorFillLayerSelectionValue() else {
            return []
        }
        return layers
    }

    var designInspectorLayerEditingReason: String? {
        switch designInspectorFillLayerSelectionValue() {
        case .unavailable(let reason):
            return reason
        case .mixed(let count, let skipped):
            let skippedText = skipped == 0
                ? ""
                : " \(skipped) incompatible selection\(skipped == 1 ? " is" : "s are") unchanged."
            return "\(count) selected object\(count == 1 ? " has" : "s have") different fill-layer stacks. Select one object or make their stacks identical before editing ordered rows.\(skippedText)"
        case .shared(_, _, _):
            return nil
        }
    }

    var designInspectorLayerSelectionSummary: String? {
        guard case .shared(_, let applicable, let skipped) = designInspectorFillLayerSelectionValue(),
              applicable > 1 || skipped > 0 else { return nil }
        let shared = "Shared fill-layer stack across \(applicable) compatible object\(applicable == 1 ? "" : "s")."
        guard skipped > 0 else { return shared }
        return "\(shared) \(skipped) incompatible selection\(skipped == 1 ? " remains" : "s remain") unchanged."
    }

    @discardableResult
    func commitDesignFillLayer(_ edit: DesignFillLayerEdit, operation: String, provenance: DesignInspectorProvenance = .picker) -> Bool {
        guard let pageID = effectiveSelectedPageID,
              let plan = canvasRenderPlan,
              plan.identity.documentID == documentSession.document.id,
              plan.identity.revision == documentSession.document.revision else {
            designInspectorFailure = .stale
            return false
        }
        do {
            let prepared = try designInspectorRegistry.prepare(.init(
                identity: .init(
                    documentID: documentSession.document.id,
                    pageID: pageID,
                    revision: documentSession.document.revision,
                    sceneID: plan.identity.sceneID,
                    rendererGeneration: plan.identity.sceneGeneration
                ),
                orderedNodeIDs: selectionState.orderedIDs,
                edit: edit,
                provenance: provenance,
                cancelled: false
            ), in: documentSession.document, context: transformValidationContext)
            _ = try documentSession.execute(prepared.documentCommand)
            designInspectorFailure = nil
            let applied = prepared.applicableNodeIDs.count
            let skipped = prepared.skippedNodeIDs.count
            if skipped == 0 {
                lastDesignInspectorAnnouncement = "Design \(operation) committed for \(applied) object\(applied == 1 ? "" : "s")"
            } else {
                let reasons = Set(prepared.skippedReasons.values).sorted().joined(separator: ", ")
                lastDesignInspectorAnnouncement = "Design \(operation) committed for \(applied) object\(applied == 1 ? "" : "s"); skipped \(skipped) incompatible object\(skipped == 1 ? "" : "s"): \(reasons)"
            }
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return true
        } catch let error as DesignInspectorError {
            designInspectorFailure = error
            lastDesignInspectorAnnouncement = error.localizedDescription
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        } catch {
            designInspectorFailure = .stale
            lastDesignInspectorAnnouncement = "Design \(operation) could not commit; appearance is unchanged"
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        }
    }

    @discardableResult
    func commitDesignFill(_ color: CanonicalSolidColor?, provenance: DesignInspectorProvenance = .picker) -> Bool {
        // The established colour well and hexadecimal path now compile to the
        // v1 layer registry as well. That atomically adapts legacy fill data
        // on first edit and never leaves v4 channels as a competing source.
        commitDesignFillLayer(.replaceSolid(color), operation: "solid-fill", provenance: provenance)
    }

    @discardableResult
    func commitDesignOpacity(percent: Double, provenance: DesignInspectorProvenance = .keyboard) -> Bool {
        guard percent.isFinite, (0...100).contains(percent) else {
            designInspectorFailure = .invalidOpacity
            lastDesignInspectorAnnouncement = DesignInspectorError.invalidOpacity.localizedDescription
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        }
        return commitDesignEdit(.opacity(percent / 100), operation: "opacity", provenance: provenance)
    }

    func cancelDesignInspectorDraft() {
        designInspectorFailure = nil
        lastDesignInspectorAnnouncement = "Design Inspector draft cancelled; committed appearance is unchanged"
        announcementPoster.post(lastDesignInspectorAnnouncement)
    }

    private func commitDesignEdit(_ edit: DesignInspectorEdit, operation: String, provenance: DesignInspectorProvenance) -> Bool {
        guard let pageID = effectiveSelectedPageID,
              let plan = canvasRenderPlan,
              plan.identity.documentID == documentSession.document.id,
              plan.identity.revision == documentSession.document.revision else {
            designInspectorFailure = .stale
            return false
        }
        do {
            let prepared = try designInspectorRegistry.prepare(.init(identity: .init(documentID: documentSession.document.id, pageID: pageID, revision: documentSession.document.revision, sceneID: plan.identity.sceneID, rendererGeneration: plan.identity.sceneGeneration), orderedNodeIDs: selectionState.orderedIDs, edit: edit, provenance: provenance, cancelled: false), in: documentSession.document, context: transformValidationContext)
            _ = try documentSession.execute(prepared.documentCommand)
            designInspectorFailure = nil
            let skipped = prepared.skippedNodeIDs.count
            if skipped == 0 {
                lastDesignInspectorAnnouncement = "Design \(operation) committed for \(prepared.applicableNodeIDs.count) object\(prepared.applicableNodeIDs.count == 1 ? "" : "s")"
            } else {
                // The view owns no canonical styling policy: the registry has
                // already validated and named the inapplicable subset.  Keep
                // the announcement count/reason based (never authored names
                // or values) so mixed selection is truthful and redacted.
                let reasons = Set(prepared.skippedReasons.values)
                    .sorted()
                    .joined(separator: ", ")
                lastDesignInspectorAnnouncement = "Design \(operation) committed for \(prepared.applicableNodeIDs.count) object\(prepared.applicableNodeIDs.count == 1 ? "" : "s"); skipped \(skipped) incompatible object\(skipped == 1 ? "" : "s"): \(reasons)"
            }
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return true
        } catch let error as DesignInspectorError {
            designInspectorFailure = error
            lastDesignInspectorAnnouncement = error.localizedDescription
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        } catch {
            designInspectorFailure = .stale
            lastDesignInspectorAnnouncement = "Design \(operation) could not commit; appearance is unchanged"
            announcementPoster.post(lastDesignInspectorAnnouncement)
            return false
        }
    }

    var geometryInspectorApplicabilityMessage: String? {
        guard let pageID = effectiveSelectedPageID,
              let page = documentSession.document.pages.first(where: { $0.id == pageID }) else {
            return nil
        }
        let unsupported = selectionState.orderedIDs.compactMap { id in
            page.nodes.first(where: { $0.id == id })
        }.filter { !GeometryInspectorCommandRegistry.supportsFixedGeometry($0.kind) }
        guard !unsupported.isEmpty else { return nil }
        return "\(unsupported.count) selected object\(unsupported.count == 1 ? "" : "s") do not support fixed geometry and will remain unchanged."
    }

    func geometryInspectorAvailability(for field: GeometryInspectorField) -> TransformAvailability {
        guard let plan = canvasRenderPlan,
              let pageID = effectiveSelectedPageID,
              !selectionState.isEmpty else {
            return .disabled("Select an object with editable geometry after the canvas is ready.")
        }
        let command = GeometryInspectorCommand(
            identity: .init(
                editID: GeometryInspectorEditID(),
                documentID: documentSession.document.id,
                pageID: pageID,
                revision: documentSession.document.revision,
                sceneID: plan.identity.sceneID,
                rendererGeneration: plan.identity.sceneGeneration
            ),
            orderedNodeIDs: selectionState.orderedIDs,
            field: field,
            value: field.requiresPositiveValue ? TransformPolicy.minimumDimension : 0,
            provenance: .automation,
            breakpoint: viewportPreset.responsiveBreakpoint
        )
        do {
            _ = try geometryInspectorRegistry.prepare(
                command, in: documentSession.document, context: transformValidationContext
            )
            return .enabled
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    @discardableResult
    func commitGeometryInspectorValue(
        _ value: Double,
        field: GeometryInspectorField,
        provenance: GeometryInspectorProvenance
    ) -> Bool {
        guard let plan = canvasRenderPlan, let pageID = effectiveSelectedPageID else { return false }
        let command = GeometryInspectorCommand(
            identity: .init(
                editID: GeometryInspectorEditID(),
                documentID: documentSession.document.id,
                pageID: pageID,
                revision: documentSession.document.revision,
                sceneID: plan.identity.sceneID,
                rendererGeneration: plan.identity.sceneGeneration
            ),
            orderedNodeIDs: selectionState.orderedIDs,
            field: field,
            value: value,
            provenance: provenance,
            breakpoint: viewportPreset.responsiveBreakpoint
        )
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let prepared = try geometryInspectorRegistry.prepare(
                command, in: documentSession.document, context: transformValidationContext
            )
            _ = try documentSession.execute(prepared.documentCommand)
            geometryInspectorFailure = nil
            let subset = prepared.skippedNodeIDs.isEmpty
                ? ""
                : "; \(prepared.skippedNodeIDs.count) unsupported selection\(prepared.skippedNodeIDs.count == 1 ? "" : "s") unchanged"
            lastGeometryInspectorAnnouncement = "\(field.title) committed\(subset)"
            announcementPoster.post(lastGeometryInspectorAnnouncement)
            recordGeometryInspectorDiagnostic(command, started: started, success: true, failure: nil)
            return true
        } catch let error as GeometryInspectorError {
            geometryInspectorFailure = error
            lastGeometryInspectorAnnouncement = error.localizedDescription
            announcementPoster.post(lastGeometryInspectorAnnouncement)
            recordGeometryInspectorDiagnostic(command, started: started, success: false, failure: error)
            return false
        } catch let error as CommandExecutionError {
            let mapped: GeometryInspectorError = switch error {
            case .cancelled: .cancelled
            case .revisionExhausted: .revisionExhausted
            case .disabled: .staleRevision
            case .invalidResult: .invalidValue
            }
            geometryInspectorFailure = mapped
            lastGeometryInspectorAnnouncement = mapped.localizedDescription
            announcementPoster.post(lastGeometryInspectorAnnouncement)
            recordGeometryInspectorDiagnostic(command, started: started, success: false, failure: mapped)
            return false
        } catch {
            return false
        }
    }

    @discardableResult
    func resetGeometryOverrides(provenance: GeometryInspectorProvenance = .keyboard) -> Bool {
        guard viewportPreset != .desktop, let plan = canvasRenderPlan, let pageID = effectiveSelectedPageID else { return false }
        let commands = GeometryInspectorField.allCases.map { field in
            GeometryInspectorCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: documentSession.document.id,
                pageID: pageID, revision: documentSession.document.revision, sceneID: plan.identity.sceneID,
                rendererGeneration: plan.identity.sceneGeneration), orderedNodeIDs: selectionState.orderedIDs,
                field: field, value: 0, provenance: provenance,
                breakpoint: viewportPreset.responsiveBreakpoint, removesOverride: true)
        }
        do {
            let prepared = try commands.compactMap { command -> DocumentCommand? in
                do { return try geometryInspectorRegistry.prepare(command, in: documentSession.document,
                    context: transformValidationContext).documentCommand }
                catch GeometryInspectorError.noApplicableTargets { return nil }
            }
            guard !prepared.isEmpty else { throw GeometryInspectorError.noApplicableTargets }
            _ = try documentSession.execute(.batch(prepared))
            geometryInspectorFailure = nil
            lastGeometryInspectorAnnouncement = "Removed \(viewportPreset.title) geometry overrides; values now inherit from Desktop"
            announcementPoster.post(lastGeometryInspectorAnnouncement)
            return true
        } catch let error as GeometryInspectorError {
            geometryInspectorFailure = error; lastGeometryInspectorAnnouncement = error.localizedDescription
            announcementPoster.post(lastGeometryInspectorAnnouncement); return false
        } catch { return false }
    }

    func cancelGeometryInspectorDraft() {
        geometryInspectorFailure = nil
        lastGeometryInspectorAnnouncement = "Layout Inspector edit cancelled"
        announcementPoster.post(lastGeometryInspectorAnnouncement)
    }

    private func recordGeometryInspectorDiagnostic(
        _ command: GeometryInspectorCommand,
        started: UInt64,
        success: Bool,
        failure: GeometryInspectorError?
    ) {
        let result: GeometryInspectorDiagnosticResult = success ? .success : failure == .cancelled
            ? .cancelled
            : [.staleDocument, .staleRevision, .staleRenderer].contains(failure ?? .invalidValue)
                ? .stale
                : .failure
        let record = GeometryInspectorDiagnosticFactory.make(
            command: command,
            durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
            resultRevision: success ? documentSession.document.revision : nil,
            result: result,
            failure: failure
        )
        Task { await geometryInspectorDiagnostics.append(record) }
    }

    func selectionAvailability(_ name: SelectionCommandName) -> SelectionCommandAvailability {
        guard let scene = selectionScene else { return .disabled("The canvas scene is not ready.") }
        return selectionRegistry.availability(
            for: SelectionCommand(name, expectedIdentity: scene.identity, provenance: .menu),
            state: selectionState,
            scene: scene
        )
    }

    func performSelectionCommand(
        _ name: SelectionCommandName,
        targetID: NodeID? = nil,
        provenance: SelectionProvenance
    ) {
        guard let scene = selectionScene else { return }
        cancelTransform()
        let start = DispatchTime.now().uptimeNanoseconds
        let prior = selectionState
        do {
            let command = SelectionCommand(
                name, targetID: targetID,
                expectedIdentity: scene.identity,
                provenance: provenance
            )
            _ = try selectionRegistry.apply(command, to: &selectionState, scene: scene)
            selectionFailure = nil
            if selectionState != prior {
                resetDesignInspectorContextForSelectionChange()
            }
            rebuildSelectionOverlay()
            announceSelection()
            recordSelectionDiagnostic(name, start: start, result: .success, repair: nil, failure: nil)
        } catch let error as SelectionCommandError {
            selectionState = prior
            selectionFailure = error
            let result: SelectionDiagnosticResult = error == .staleScene ? .stale : .failure
            recordSelectionDiagnostic(name, start: start, result: result, repair: nil, failure: String(describing: error))
        } catch {
            selectionState = prior
        }
    }

    /// Inspector operation feedback is scoped to the exact selection that
    /// produced it. Retaining a mixed-edit announcement after a replacement
    /// selection makes the visible inspector contradict its disabled state.
    /// This is editor presentation state only; it never affects history or
    /// canonical document data.
    private func resetDesignInspectorContextForSelectionChange() {
        designInspectorFailure = nil
        lastDesignInspectorAnnouncement = DesignInspectorSelectionPresentation.contextAnnouncement(
            selectionCount: selectionState.count
        )
    }

    func selectCanvasPoint(_ point: WorldPoint, modifier: SelectionPointerModifier) {
        if textEditingSession.isActive {
            commitTextEditing()
        }
        if selectedTool == .frame {
            commitInsertion(.frame, at: point, provenance: .pointer, keepsToolArmed: true)
            return
        }
        if selectedTool == .text {
            commitInsertion(.text, at: point, provenance: .pointer, keepsToolArmed: true)
            return
        }
        guard selectedTool == .select, let plan = canvasRenderPlan, let scene = selectionScene,
              plan.identity == scene.identity else { return }
        let eligible = Set(scene.orderedSelectableTargets.map(\.id))
        guard let id = CanvasRendererCore().hitTest(point, in: plan, eligibleIDs: eligible) else {
            if !selectionState.isEmpty { performSelectionCommand(.clear, provenance: .pointer) }
            return
        }
        let command: SelectionCommandName = switch modifier {
        case .replace: .replace
        case .add: .add
        case .toggle: .toggle
        }
        performSelectionCommand(command, targetID: id, provenance: .pointer)
    }

    var textEditingPresentation: InlineTextEditorPresentation? {
        guard let draft = textEditingSession.draft else { return nil }
        let renderObject = canvasRenderPlan?.authoredObjects.first(where: {
            $0.id == draft.activation.identity.nodeID
        })
        guard let frame = renderObject?.frame ?? retainedTextEditingFrame else { return nil }
        return InlineTextEditorPresentation(
            identity: draft.activation.identity,
            text: draft.text,
            selection: draft.selection,
            frame: frame,
            typography: renderObject?.typography
        )
    }

    var textEditingStatus: String {
        switch textEditingSession.phase {
        case .inactive: "Text editing inactive"
        case .drafting:
            "Editing text (\(textEditingSession.draft?.text.utf8.count ?? 0) bytes)"
        case .previewing:
            "Previewing text edit (\(textEditingSession.draft?.text.utf8.count ?? 0) bytes)"
        case .composing:
            "Composing text (\(textEditingSession.draft?.text.utf8.count ?? 0) bytes)"
        case .committing: "Committing text edit…"
        case .cancelled: "Text edit cancelled"
        case .failed(let error, _): error.localizedDescription
        }
    }

    func textEditingAvailability(
        nodeID: NodeID,
        provenance: TextEditProvenance = .menu
    ) -> TextEditAvailability {
        guard canvasRenderPlan != nil else {
            return .disabled("The rendered canvas is not ready.")
        }
        return textEditingRegistry.availability(
            nodeID: nodeID,
            provenance: provenance,
            in: documentSession.document,
            context: textEditingValidationContext
        )
    }

    @discardableResult
    func beginTextEditing(
        nodeID: NodeID,
        provenance: TextEditProvenance
    ) -> Bool {
        if textEditingSession.isActive {
            guard textEditingSession.draft?.activation.identity.nodeID != nodeID else {
                return true
            }
            commitTextEditing()
            guard !textEditingSession.isActive else { return false }
        }
        cancelInsertion(resetTool: true)
        cancelTransform()
        cancelGuideEditing()
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let activation = try textEditingRegistry.activate(
                nodeID: nodeID,
                provenance: provenance,
                in: documentSession.document,
                context: textEditingValidationContext
            )
            retainedTextEditingFrame = canvasRenderPlan?.authoredObjects.first(where: {
                $0.id == nodeID
            })?.frame
            textEditingSession.begin(activation)
            textEditingFailure = nil
            if selectionState.orderedIDs != [nodeID] {
                performSelectionCommand(.replace, targetID: nodeID, provenance: .lifecycleRepair)
            }
            lastTextEditingAnnouncement = "Editing plain text"
            announcementPoster.post(lastTextEditingAnnouncement)
            return true
        } catch let error as TextEditError {
            textEditingFailure = error
            lastTextEditingAnnouncement = error.localizedDescription
            announcementPoster.post(lastTextEditingAnnouncement)
            if let draft = textEditingSession.draft {
                recordTextEditingDiagnostic(
                    "activate",
                    draft: draft,
                    start: start,
                    result: [.staleDocument, .stalePage, .staleRevision, .staleRenderer]
                        .contains(error) ? .stale : .failure,
                    failure: error
                )
            } else {
                let record = TextEditDiagnosticFactory.makeActivationFailure(
                    nodeID: nodeID,
                    pageID: effectiveSelectedPageID ?? textEditingValidationContext.activePageID,
                    durationMilliseconds: Double(
                        DispatchTime.now().uptimeNanoseconds - start
                    ) / 1_000_000,
                    failure: error
                )
                Task { await textEditingDiagnostics.append(record) }
            }
            return false
        } catch {
            return false
        }
    }

    @discardableResult
    func beginTextEditing(
        at point: WorldPoint,
        provenance: TextEditProvenance
    ) -> Bool {
        guard let plan = canvasRenderPlan,
              let id = CanvasRendererCore().hitTest(point, in: plan),
              documentSession.document.pages
                .flatMap(\.nodes)
                .first(where: { $0.id == id })?.kind == .text else {
            return false
        }
        return beginTextEditing(nodeID: id, provenance: provenance)
    }

    func updateTextEditingDraft(
        text: String,
        selection: TextEditRange,
        markedRange: TextEditRange?
    ) {
        guard textEditingSession.isActive else { return }
        guard text.utf8.count <= InlineTextEditingPolicy.maximumTextBytes,
              InlineTextEditingPolicy.validatesContent(text),
              selection.isValid(in: text),
              markedRange?.isValid(in: text) != false else {
            textEditingFailure = text.utf8.count > InlineTextEditingPolicy.maximumTextBytes
                ? .textLimitExceeded : .invalidText
            return
        }
        textEditingSession.update(text: text, selection: selection, markedRange: markedRange)
        textEditingFailure = nil
    }

    func commitTextEditing() {
        guard let draft = textEditingSession.draft else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let prepared = try textEditingRegistry.prepare(
                draft,
                in: documentSession.document,
                context: textEditingValidationContext
            )
            textEditingSession.beginCommit()
            if let command = prepared.command {
                _ = try documentSession.execute(command)
            }
            textEditingSession.complete()
            retainedTextEditingFrame = nil
            textEditingFailure = nil
            lastTextEditingAnnouncement = prepared.command == nil
                ? "Text editing ended with no changes"
                : "Text edit committed"
            announcementPoster.post(lastTextEditingAnnouncement)
            recordTextEditingDiagnostic(
                "commit", draft: draft, start: start, result: .success, failure: nil
            )
        } catch let error as TextEditError {
            textEditingSession.fail(error)
            textEditingFailure = error
            let result: TextEditDiagnosticResult =
                [.staleDocument, .stalePage, .staleRevision, .staleRenderer].contains(error)
                ? .stale : error == .cancelled ? .cancelled : .failure
            recordTextEditingDiagnostic(
                "commit", draft: draft, start: start, result: result, failure: error
            )
        } catch let error as CommandExecutionError {
            let mapped: TextEditError = switch error {
            case .cancelled: .cancelled
            case .revisionExhausted: .revisionExhausted
            case .disabled: .staleRevision
            case .invalidResult: .invalidResult
            }
            textEditingSession.fail(mapped)
            textEditingFailure = mapped
            recordTextEditingDiagnostic(
                "commit", draft: draft, start: start,
                result: mapped == .cancelled ? .cancelled : .failure,
                failure: mapped
            )
        } catch {}
    }

    func cancelTextEditing() {
        guard let draft = textEditingSession.draft else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        textEditingSession.cancel()
        retainedTextEditingFrame = nil
        textEditingFailure = nil
        lastTextEditingAnnouncement = "Text edit cancelled; committed text restored"
        announcementPoster.post(lastTextEditingAnnouncement)
        recordTextEditingDiagnostic(
            "cancel", draft: draft, start: start, result: .cancelled, failure: .cancelled
        )
    }

    private var textEditingValidationContext: TextEditValidationContext {
        let plan = canvasRenderPlan
        let lifecycleAvailable: Bool
        let reason: String?
        if isPreviewPresented {
            lifecycleAvailable = false
            reason = "Close Preview before editing text."
        } else {
            switch lifecycle.phase {
            case .saving, .autosaving:
                lifecycleAvailable = true
                reason = nil
            case .conflicted:
                lifecycleAvailable = false
                reason = "Resolve the file conflict before editing text."
            case .clean, .modified, .failed, .recovered:
                lifecycleAvailable = true
                reason = nil
            }
        }
        return TextEditValidationContext(
            activePageID: effectiveSelectedPageID ?? PageID(),
            sceneID: plan?.identity.sceneID ?? viewportState.sceneID,
            rendererGeneration: plan?.identity.sceneGeneration ?? documentSession.document.revision,
            availableNodeIDs: plan.map { Set($0.authoredObjects.map(\.id)) },
            isLifecycleAvailable: lifecycleAvailable,
            lifecycleDisabledReason: reason
        )
    }

    private func recordTextEditingDiagnostic(
        _ operation: String,
        draft: TextEditDraft,
        start: UInt64,
        result: TextEditDiagnosticResult,
        failure: TextEditError?
    ) {
        let record = TextEditDiagnosticFactory.make(
            operation: operation,
            draft: draft,
            durationMilliseconds: Double(
                DispatchTime.now().uptimeNanoseconds - start
            ) / 1_000_000,
            result: result,
            failure: failure
        )
        Task { await textEditingDiagnostics.append(record) }
    }

    func selectLayer(_ id: NodeID, modifier: SelectionPointerModifier = .replace) {
        if let scene = selectionScene,
           let target = scene.targets.first(where: { $0.id == id }),
           target.parentID != scene.activeContainerID {
            let scoped = SelectionSceneSnapshot(
                identity: scene.identity,
                activePageID: scene.activePageID,
                activeContainerID: target.parentID,
                targets: scene.targets
            )
            _ = try? selectionRegistry.adopt(scoped, boundary: .rendererGeneration, state: &selectionState)
            selectionScene = scoped
        }
        let command: SelectionCommandName = switch modifier {
        case .replace: .replace
        case .add: .add
        case .toggle: .toggle
        }
        performSelectionCommand(command, targetID: id, provenance: .layersNavigator)
    }

    var transformStatus: String {
        switch transformSession.phase {
        case .inactive: "Transform inactive"
        case .drafting: "Preparing transform"
        case .previewing(let preview): "Previewing \(preview.operation.name)"
        case .committing(let preview): "Committing \(preview.operation.name)…"
        case .cancelled: "Transform cancelled"
        case .failed(let error): error.localizedDescription
        }
    }

    var activeGuides: [AuthoredGuide] {
        guard let pageID = effectiveSelectedPageID else { return [] }
        return documentSession.document.guides.filter { $0.pageID == pageID }
    }

    var snappingStatus: String {
        if isSnappingSuppressed { return "Snapping suppressed" }
        guard let snapResolution, !snapResolution.winners.isEmpty else {
            return "Snapping ready"
        }
        return snapResolution.winners
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map(\.value.explanation)
            .joined(separator: "; ")
    }

    var selectedGuideSummary: String {
        guard let selectedGuideID,
              let guide = activeGuides.first(where: { $0.id == selectedGuideID }) else {
            return activeGuides.isEmpty
                ? "No authored guides"
                : "\(activeGuides.count) authored guide\(activeGuides.count == 1 ? "" : "s")"
        }
        return String(
            format: "%@ guide at %.0f",
            guide.axis.rawValue.capitalized,
            guide.position
        )
    }

    func setSnappingSuppressed(_ value: Bool) {
        guard value != isSnappingSuppressed else { return }
        isSnappingSuppressed = value
        if value {
            snapResolution = nil
            lastTransformAnnouncement = "Snapping suppressed"
        } else {
            lastTransformAnnouncement = "Snapping enabled"
        }
        announcementPoster.post(lastTransformAnnouncement)
    }

    func toggleSnappingSuppression() {
        setSnappingSuppressed(!isSnappingSuppressed)
    }

    var guidePreview: GuidePreview? {
        switch guideEditingSession.phase {
        case .previewing(let value), .committing(let value): value
        default: nil
        }
    }

    func selectGuide(_ guideID: GuideID?) {
        guard guideID == nil || activeGuides.contains(where: { $0.id == guideID }) else {
            return
        }
        selectedGuideID = guideID
        lastGuideAnnouncement = guideID == nil ? "No authored guide selected" : selectedGuideSummary
        announcementPoster.post(lastGuideAnnouncement)
    }

    func addGuide(
        axis: GuideAxis,
        position: Double,
        provenance: GuideCommandProvenance
    ) {
        let name: GuideCommandName = axis == .horizontal ? .addHorizontal : .addVertical
        performGuideCommand(
            name,
            guideID: GuideID(),
            position: position,
            provenance: provenance
        )
    }

    func moveSelectedGuide(by delta: Double, provenance: GuideCommandProvenance) {
        guard let selectedGuideID,
              let guide = activeGuides.first(where: { $0.id == selectedGuideID }) else {
            guideFailure = .missingGuide
            return
        }
        performGuideCommand(
            .move,
            guideID: selectedGuideID,
            position: guide.position + delta,
            provenance: provenance
        )
    }

    func removeSelectedGuide(provenance: GuideCommandProvenance) {
        guard let selectedGuideID else {
            guideFailure = .missingGuide
            return
        }
        performGuideCommand(
            .remove,
            guideID: selectedGuideID,
            position: nil,
            provenance: provenance
        )
    }

    func performGuideCommand(
        _ name: GuideCommandName,
        guideID: GuideID,
        position: Double?,
        provenance: GuideCommandProvenance
    ) {
        guard let identity = makeGuideIdentity() else {
            guideFailure = .staleRenderer
            return
        }
        let command = GuideCommand(
            identity: identity,
            name: name,
            guideID: guideID,
            position: position,
            provenance: provenance
        )
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let prepared = try guideRegistry.prepare(
                command,
                in: documentSession.document,
                context: guideValidationContext
            )
            let axis: GuideAxis
            switch name {
            case .addHorizontal: axis = .horizontal
            case .addVertical: axis = .vertical
            case .move, .remove:
                axis = activeGuides.first(where: { $0.id == guideID })?.axis ?? .horizontal
            }
            guideEditingSession.begin(identity: identity)
            if let position {
                let preview = GuidePreview(
                    identity: identity,
                    guideID: guideID,
                    axis: axis,
                    position: position
                )
                guideEditingSession.preview(preview)
                guideEditingSession.beginCommit(preview)
            }
            _ = try documentSession.execute(prepared.documentCommand)
            guideEditingSession.complete()
            guideFailure = nil
            selectedGuideID = name == .remove ? nil : guideID
            lastGuideAnnouncement = switch name {
            case .addHorizontal, .addVertical: "\(axis.rawValue.capitalized) guide added"
            case .move: "\(axis.rawValue.capitalized) guide moved"
            case .remove: "Guide removed"
            }
            announcementPoster.post(lastGuideAnnouncement)
            Task {
                await snapDiagnostics.append(SnapDiagnosticFactory.make(
                    operation: "guide.\(name.rawValue)",
                    identities: [guideID.description, identity.pageID.description],
                    durationMilliseconds: Double(
                        DispatchTime.now().uptimeNanoseconds - start
                    ) / 1_000_000,
                    candidateCount: 0,
                    winnerCount: 0,
                    result: .success
                ))
            }
        } catch let error as GuideCommandError {
            guideEditingSession.fail(error)
            guideFailure = error
            Task {
                await snapDiagnostics.append(SnapDiagnosticFactory.make(
                    operation: "guide.\(name.rawValue)",
                    identities: [guideID.description],
                    durationMilliseconds: Double(
                        DispatchTime.now().uptimeNanoseconds - start
                    ) / 1_000_000,
                    candidateCount: 0,
                    winnerCount: 0,
                    result: [.staleDocument, .stalePage, .staleRevision, .staleRenderer]
                        .contains(error) ? .stale : .failure,
                    failureCategory: String(describing: error)
                ))
            }
        } catch let error as CommandExecutionError {
            let mapped: GuideCommandError = switch error {
            case .cancelled: .cancelled
            case .revisionExhausted: .revisionExhausted
            case .disabled, .invalidResult: .staleRevision
            }
            guideEditingSession.fail(mapped)
            guideFailure = mapped
        } catch {}
    }

    func cancelGuideEditing() {
        switch guideEditingSession.phase {
        case .inactive, .cancelled: return
        case .drafting, .previewing, .committing, .failed:
            guideEditingSession.cancel()
            guideFailure = nil
            lastGuideAnnouncement = "Guide operation cancelled"
            announcementPoster.post(lastGuideAnnouncement)
        }
    }

    private func makeGuideIdentity() -> GuideOperationIdentity? {
        guard let pageID = effectiveSelectedPageID, let plan = canvasRenderPlan else {
            return nil
        }
        return GuideOperationIdentity(
            operationID: GuideEditID(),
            documentID: documentSession.document.id,
            pageID: pageID,
            revision: documentSession.document.revision,
            sceneID: plan.identity.sceneID,
            rendererGeneration: plan.identity.sceneGeneration
        )
    }

    private var guideValidationContext: GuideValidationContext {
        let transform = transformValidationContext
        return GuideValidationContext(
            activePageID: transform.activePageID,
            sceneID: transform.currentSceneID,
            rendererGeneration: transform.rendererGeneration,
            isLifecycleAvailable: transform.isLifecycleAvailable,
            lifecycleDisabledReason: transform.lifecycleDisabledReason
        )
    }

    var transformOverlays: [CanvasEditorOverlay] {
        guard let plan = canvasRenderPlan else { return [] }
        let preview: TransformPreview? = switch transformSession.phase {
        case .previewing(let value), .committing(let value): value
        default: nil
        }
        return TransformOverlayPlanner.overlays(
            selection: selectionState,
            renderPlan: plan,
            preview: preview,
            handleWorldSize: 8 / viewportState.zoom.value
        )
    }

    func transformAvailability(_ operation: TransformOperation) -> TransformAvailability {
        guard let plan = canvasRenderPlan,
              let pageID = effectiveSelectedPageID,
              !selectionState.isEmpty else {
            return .disabled("Select a transformable object after the canvas is ready.")
        }
        let identity = TransformOperationIdentity(
            sessionID: TransformSessionID(),
            documentID: documentSession.document.id,
            pageID: pageID,
            revision: documentSession.document.revision,
            sceneID: plan.identity.sceneID,
            rendererGeneration: plan.identity.sceneGeneration
        )
        let command = GeometryTransformCommand(
            identity: identity,
            orderedNodeIDs: selectionState.orderedIDs,
            operation: operation,
            provenance: .menu
        )
        return transformRegistry.availability(
            for: command,
            in: documentSession.document,
            context: transformValidationContext
        )
    }

    @discardableResult
    func beginPointerTransform(at point: WorldPoint) -> Bool {
        guard selectedTool == .select,
              let plan = canvasRenderPlan,
              let primaryID = selectionState.primaryID,
              let frame = plan.authoredObjects.first(where: { $0.id == primaryID })?.frame else {
            return false
        }
        let radius = TransformPolicy.handleHitRadius / viewportState.zoom.value
        let operation: TransformOperation
        if let handle = TransformOverlayPlanner.hitHandle(
            at: point,
            frame: frame,
            worldRadius: radius
        ) {
            operation = .resize(
                handle: handle,
                delta: WorldVector(dx: 0, dy: 0),
                constraint: .none
            )
        } else if point.x >= frame.minX, point.x <= frame.maxX,
                  point.y >= frame.minY, point.y <= frame.maxY {
            operation = .move(
                delta: WorldVector(dx: 0, dy: 0),
                constraint: .none
            )
        } else {
            return false
        }
        return beginTransform(operation, provenance: .pointer)
    }

    func updatePointerTransform(
        delta: WorldVector,
        constrainAxis: Bool,
        suppressSnapping: Bool = false
    ) {
        let operation: TransformOperation
        let constraint: TransformAxisConstraint = constrainAxis
            ? (abs(delta.dx) >= abs(delta.dy) ? .horizontal : .vertical)
            : .none
        switch transformSession.phase {
        case .previewing(let preview):
            switch preview.operation {
            case .move:
                operation = .move(delta: delta, constraint: constraint)
            case .resize(let handle, _, _):
                operation = .resize(handle: handle, delta: delta, constraint: constraint)
            }
        case .drafting:
            return
        default:
            return
        }
        updateTransformPreview(
            operation,
            provenance: .pointer,
            temporarilySuppressSnapping: suppressSnapping
        )
    }

    func commitPointerTransform() {
        commitTransform(provenance: .pointer)
    }

    func performTransform(_ operation: TransformOperation, provenance: TransformProvenance) {
        guard beginTransform(operation, provenance: provenance) else { return }
        commitTransform(provenance: provenance)
    }

    func cancelTransform() {
        let active: Bool
        switch transformSession.phase {
        case .drafting, .previewing, .committing, .failed: active = true
        case .inactive, .cancelled: active = false
        }
        guard active else { return }
        transformSession.cancel()
        snapResolution = nil
        transformFailure = nil
        lastTransformAnnouncement = "Transform cancelled"
        announcementPoster.post(lastTransformAnnouncement)
        objectWillChange.send()
    }

    private var transformValidationContext: TransformValidationContext {
        let lifecycleAvailable: Bool
        let reason: String?
        if isPreviewPresented {
            lifecycleAvailable = false
            reason = "Close Preview before transforming content."
        } else {
            switch lifecycle.phase {
            case .saving, .autosaving:
                // Saves own immutable snapshots. Later edits advance the
                // revision and remain Modified when that snapshot finishes.
                // Disabling Inspector controls here also drops native field
                // focus when autosave starts between pointer and key events.
                lifecycleAvailable = true
                reason = nil
            case .conflicted:
                lifecycleAvailable = false
                reason = "Resolve the file conflict before transforming content."
            case .clean, .modified, .failed, .recovered:
                lifecycleAvailable = true
                reason = nil
            }
        }
        let rendererAvailableIDs = Set(selectionScene?.targets.filter(\.isAvailable).map(\.id) ?? [])
        let selectedCanonicalIDs: Set<NodeID>
        if let pageID = effectiveSelectedPageID,
           let page = documentSession.document.pages.first(where: { $0.id == pageID }) {
            // Viewport clipping controls hit-test/accessibility virtualization,
            // not canonical editability. A retained active-page selection may
            // author or reset breakpoint geometry while temporarily outside a
            // narrower artboard without creating a fabricated visible target.
            selectedCanonicalIDs = Set(selectionState.orderedIDs.filter { id in
                page.nodes.contains(where: { $0.id == id })
            })
        } else {
            selectedCanonicalIDs = []
        }
        return TransformValidationContext(
            activePageID: effectiveSelectedPageID ?? PageID(),
            currentSceneID: canvasRenderPlan?.identity.sceneID ?? CanvasViewportSceneID(),
            rendererGeneration: canvasRenderPlan?.identity.sceneGeneration ?? UInt64.max,
            selectedNodeIDs: selectionState.orderedIDs,
            availableNodeIDs: rendererAvailableIDs.union(selectedCanonicalIDs),
            isLifecycleAvailable: lifecycleAvailable,
            lifecycleDisabledReason: reason
        )
    }

    private func snapContext(
        identity: TransformOperationIdentity,
        temporarilySuppress: Bool
    ) -> SnapResolutionContext {
        let pageID = effectiveSelectedPageID ?? PageID()
        let page = documentSession.document.pages.first(where: { $0.id == pageID })
        let nodesByID = Dictionary(uniqueKeysWithValues: (page?.nodes ?? []).map { ($0.id, $0) })
        let objects = (canvasRenderPlan?.authoredObjects ?? []).map { object in
            let node = nodesByID[object.id]
            let clipped: Bool
            if let clip = object.clipRect {
                clipped = object.frame.minX < clip.minX
                    || object.frame.maxX > clip.maxX
                    || object.frame.minY < clip.minY
                    || object.frame.maxY > clip.maxY
            } else {
                clipped = false
            }
            return SnapSceneObject(
                id: object.id,
                pageID: pageID,
                frame: object.frame,
                isVisible: object.isVisible,
                isLocked: node?.insertionBooleanProperty("locked") ?? false,
                isClipped: clipped,
                isAvailable: selectionScene?.targets.first(where: { $0.id == object.id })?
                    .isAvailable ?? false
            )
        }
        return SnapResolutionContext(
            identity: identity,
            activePageID: pageID,
            selectedNodeIDs: selectionState.orderedIDs,
            objects: objects,
            guides: activeGuides,
            zoom: viewportState.zoom,
            pixelRatio: viewportState.pixelRatio,
            previousWinners: snapResolution?.winners ?? [:],
            isSuppressed: isSnappingSuppressed || temporarilySuppress
        )
    }

    @discardableResult
    private func beginTransform(
        _ operation: TransformOperation,
        provenance: TransformProvenance
    ) -> Bool {
        guard let pageID = effectiveSelectedPageID, let plan = canvasRenderPlan else {
            transformFailure = .staleRenderer
            return false
        }
        let identity = transformSession.begin(
            documentID: documentSession.document.id,
            pageID: pageID,
            revision: documentSession.document.revision,
            sceneID: plan.identity.sceneID,
            rendererGeneration: plan.identity.sceneGeneration
        )
        return prepareTransformPreview(
            operation,
            identity: identity,
            provenance: provenance
        )
    }

    private func updateTransformPreview(
        _ operation: TransformOperation,
        provenance: TransformProvenance,
        temporarilySuppressSnapping: Bool = false
    ) {
        guard let identity = transformSession.currentIdentity else { return }
        _ = prepareTransformPreview(
            operation,
            identity: identity,
            provenance: provenance,
            temporarilySuppressSnapping: temporarilySuppressSnapping
        )
    }

    @discardableResult
    private func prepareTransformPreview(
        _ operation: TransformOperation,
        identity: TransformOperationIdentity,
        provenance: TransformProvenance,
        temporarilySuppressSnapping: Bool = false
    ) -> Bool {
        let snapStart = DispatchTime.now().uptimeNanoseconds
        let command = GeometryTransformCommand(
            identity: identity,
            orderedNodeIDs: selectionState.orderedIDs,
            operation: operation,
            provenance: provenance
        )
        do {
            let raw = try transformRegistry.prepare(
                command,
                in: documentSession.document,
                context: transformValidationContext
            )
            let snap = try snapResolver.resolve(
                raw: raw,
                context: snapContext(
                    identity: identity,
                    temporarilySuppress: temporarilySuppressSnapping
                )
            )
            let resolvedCommand = GeometryTransformCommand(
                identity: identity,
                orderedNodeIDs: selectionState.orderedIDs,
                operation: snap.operation,
                provenance: provenance
            )
            let prepared = try transformRegistry.prepare(
                resolvedCommand,
                in: documentSession.document,
                context: transformValidationContext
            )
            transformSession.preview(TransformPreview(
                identity: identity,
                operation: snap.operation,
                geometries: prepared.geometries
            ))
            snapResolution = snap
            recordSnapDiagnostic(
                operation: operation.name,
                identity: identity,
                start: snapStart,
                candidateCount: snap.candidateCount,
                winnerCount: snap.winners.count,
                result: temporarilySuppressSnapping || isSnappingSuppressed
                    ? .suppressed : .success
            )
            transformFailure = nil
            return true
        } catch let error as TransformError {
            transformSession.fail(error)
            snapResolution = nil
            recordSnapDiagnostic(
                operation: operation.name,
                identity: identity,
                start: snapStart,
                candidateCount: 0,
                winnerCount: 0,
                result: [.staleDocument, .staleRevision, .staleRenderer].contains(error)
                    ? .stale : error == .cancelled ? .cancelled : .failure,
                failure: "transform-validation"
            )
            transformFailure = error
            return false
        } catch let error as SnapError {
            transformSession.fail(error == .cancelled ? .cancelled : .invalidResult)
            snapResolution = nil
            recordSnapDiagnostic(
                operation: operation.name,
                identity: identity,
                start: snapStart,
                candidateCount: 0,
                winnerCount: 0,
                result: error == .cancelled ? .cancelled
                    : error == .staleTransform ? .stale : .failure,
                failure: String(describing: error)
            )
            return false
        } catch {
            return false
        }
    }

    private func recordSnapDiagnostic(
        operation: String,
        identity: TransformOperationIdentity,
        start: UInt64,
        candidateCount: Int,
        winnerCount: Int,
        result: SnapDiagnosticResult,
        failure: String? = nil
    ) {
        let record = SnapDiagnosticFactory.make(
            operation: "transform.\(operation)",
            identities: selectionState.orderedIDs.map(\.description)
                + [identity.pageID.description, identity.sessionID.description],
            durationMilliseconds: Double(
                DispatchTime.now().uptimeNanoseconds - start
            ) / 1_000_000,
            candidateCount: candidateCount,
            winnerCount: winnerCount,
            result: result,
            failureCategory: failure
        )
        Task { await snapDiagnostics.append(record) }
    }

    private func commitTransform(provenance: TransformProvenance) {
        guard case .previewing(let preview) = transformSession.phase else { return }
        let command = GeometryTransformCommand(
            identity: preview.identity,
            orderedNodeIDs: selectionState.orderedIDs,
            operation: preview.operation,
            provenance: provenance
        )
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let prepared = try transformRegistry.prepare(
                command,
                in: documentSession.document,
                context: transformValidationContext
            )
            transformSession.beginCommit(preview)
            _ = try documentSession.execute(prepared.documentCommand)
            transformSession.complete()
            snapResolution = nil
            transformFailure = nil
            lastTransformAnnouncement = "\(preview.operation.name.capitalized) committed"
            announcementPoster.post(lastTransformAnnouncement)
            recordTransformDiagnostic(
                command, start: start, revision: documentSession.document.revision,
                result: .success, failure: nil
            )
        } catch let error as TransformError {
            transformSession.fail(error)
            snapResolution = nil
            transformFailure = error
            recordTransformDiagnostic(
                command, start: start, revision: nil,
                result: error == .cancelled ? .cancelled
                    : [.staleDocument, .staleRevision, .staleRenderer].contains(error) ? .stale : .failure,
                failure: error
            )
        } catch let error as CommandExecutionError {
            let mapped: TransformError = switch error {
            case .cancelled: .cancelled
            case .revisionExhausted: .revisionExhausted
            case .disabled: .staleRevision
            case .invalidResult: .invalidResult
            }
            transformSession.fail(mapped)
            snapResolution = nil
            transformFailure = mapped
            recordTransformDiagnostic(
                command, start: start, revision: nil,
                result: error == .cancelled ? .cancelled : .failure,
                failure: mapped
            )
        } catch {}
    }

    private func recordTransformDiagnostic(
        _ command: GeometryTransformCommand,
        start: UInt64,
        revision: UInt64?,
        result: TransformDiagnosticResult,
        failure: TransformError?
    ) {
        let record = TransformDiagnosticFactory.make(
            command: command,
            durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
            resultRevision: revision,
            result: result,
            failure: failure
        )
        Task { await transformDiagnostics.append(record) }
    }

    var insertionPreviewOverlay: CanvasEditorOverlay? {
        let preview: InsertionPreview
        switch insertionSession.phase {
        case .previewing(let value), .committing(let value): preview = value
        default: return nil
        }
        return CanvasEditorOverlay(
            id: CanvasOverlayID(preview.nodeID.rawValue),
            objectID: preview.nodeID,
            frame: preview.geometry.frame,
            kind: "insertion-preview-\(preview.kind.rawValue)"
        )
    }

    var insertionStatus: String {
        switch insertionSession.phase {
        case .inactive: "Insertion inactive"
        case .armed(let kind): "\(kind.rawValue.capitalized) tool armed"
        case .previewing(let value): "Previewing \(value.kind.rawValue)"
        case .committing(let value): "Inserting \(value.kind.rawValue)…"
        case .cancelled: "Insertion cancelled"
        case .failed(let error): error.localizedDescription
        }
    }

    func insertionAvailability(_ kind: InsertionKind) -> InsertionAvailability {
        guard let command = makeInsertionCommand(
            kind,
            at: defaultInsertionPoint,
            provenance: .menu,
            nodeID: NodeID()
        ) else { return .disabled("The active page has no valid frame destination.") }
        return insertionRegistry.availability(
            for: command,
            in: documentSession.document,
            context: insertionValidationContext
        )
    }

    func previewInsertion(at point: WorldPoint) {
        guard selectedTool != .select && selectedTool != .image && selectedTool != .component,
              insertionValidationContext.isLifecycleAvailable else { return }
        insertionSession.preview(at: point)
        objectWillChange.send()
    }

    func performDefaultInsertion(_ kind: InsertionKind, provenance: InsertionProvenance) {
        let tool = CanvasTool(rawValue: kind.rawValue) ?? .select
        if selectedTool != tool {
            selectedTool = tool
            armInsertion(kind)
        }
        // Named header/menu/accessibility actions are one-shot commands. Do
        // not leave an armed tool behind to create a ghost preview on a later
        // pointer move; explicit canvas tools retain repeat insertion below.
        commitInsertion(kind, at: defaultInsertionPoint, provenance: provenance, keepsToolArmed: false)
    }

    func cancelInsertion(resetTool: Bool) {
        let wasActive: Bool
        switch insertionSession.phase {
        case .inactive, .cancelled: wasActive = false
        default: wasActive = true
        }
        insertionSession.cancel()
        insertionFailure = nil
        if resetTool, selectedTool == .frame || selectedTool == .text { selectedTool = .select }
        if wasActive {
            lastInsertionAnnouncement = "Insertion cancelled"
            announcementPoster.post(lastInsertionAnnouncement)
        }
        objectWillChange.send()
    }

    func performEscape() {
        switch dragDropSession.phase {
        case .drafting, .previewing, .committing, .failed:
            cancelDragDrop(); return
        case .inactive, .cancelled: break
        }
        if textEditingSession.isActive {
            cancelTextEditing()
            return
        }
        switch guideEditingSession.phase {
        case .drafting, .previewing, .committing, .failed:
            cancelGuideEditing()
            return
        case .inactive, .cancelled:
            break
        }
        switch transformSession.phase {
        case .drafting, .previewing, .committing, .failed:
            cancelTransform()
            return
        case .inactive, .cancelled:
            break
        }
        switch insertionSession.phase {
        case .armed, .previewing, .committing, .failed:
            cancelInsertion(resetTool: true)
        case .inactive, .cancelled:
            performSelectionCommand(.escape, provenance: .keyboard)
        }
    }

    var dragDropStatus: String {
        switch dragDropSession.phase {
        case .inactive: "Drag and drop inactive"
        case .drafting: "Preparing move"
        case .previewing: "Previewing move"
        case .committing: "Committing move"
        case .cancelled: "Drag cancelled"
        case .failed(let error): error.localizedDescription
        }
    }

    /// Drag previews belong only to this workspace scene. They are deliberately
    /// exposed as a rendering hint rather than a document mutation.
    var activeDragDropPreview: DragDropPreview? {
        if case .previewing(let preview) = dragDropSession.phase { return preview }
        if case .committing(let preview) = dragDropSession.phase { return preview }
        return nil
    }

    func isDragInsertionPreview(before targetID: NodeID) -> Bool {
        guard let preview = activeDragDropPreview,
              let destination = dragDestination(before: targetID) else { return false }
        // This is a pre-commit hierarchy view, so the visible marker belongs
        // to the requested row boundary. `committedDestination` is the
        // post-removal index used only by the canonical move command.
        return preview.destination == destination
    }

    func isDragNestingPreview(in targetID: NodeID) -> Bool {
        guard let preview = activeDragDropPreview else { return false }
        if case .container(let parentID, _) = preview.destination { return parentID == targetID }
        return false
    }

    func dragDropAvailability(sourceID: NodeID, destination: DragDestination, provenance: DragDropProvenance = .menu) -> DragDropAvailability {
        guard let pageID = effectiveSelectedPageID, let plan = canvasRenderPlan else {
            return .disabled(.pageUnavailable)
        }
        if let selectionError = dragDropSelectionError(for: sourceID) {
            return .disabled(selectionError)
        }
        let identity = DragOperationIdentity(sessionID: DragSessionID(), documentID: documentSession.document.id, pageID: pageID, revision: documentSession.document.revision, sceneID: plan.identity.sceneID, rendererGeneration: plan.identity.sceneGeneration)
        return dragDropRegistry.availability(for: .init(identity: identity, sourceNodeID: sourceID, destination: destination, provenance: provenance), in: documentSession.document, context: dragDropValidationContext)
    }

    /// Named accessibility actions remain discoverable when a row is focused,
    /// but an unavailable action must explain its typed reason rather than
    /// silently doing nothing. This only changes editor convenience state.
    func announceDragDropUnavailable(_ reason: String) {
        lastDragDropAnnouncement = reason
        announcementPoster.post(reason)
    }

    /// Opens the only scene-local capability accepted from an asynchronous
    /// AppKit drag provider. Cancellation and every document boundary clear it.
    func beginPointerDrag(sourceID: NodeID) -> LocalLayerDragTransfer? {
        guard let pageID = effectiveSelectedPageID, let plan = canvasRenderPlan else { return nil }
        cancelDragDrop()
        if let selectionError = dragDropSelectionError(for: sourceID) {
            rejectDragDropStart(
                sourceID: sourceID,
                pageID: pageID,
                plan: plan,
                error: selectionError,
                provenance: .pointer
            )
            return nil
        }
        let identity = dragDropSession.begin(
            documentID: documentSession.document.id,
            pageID: pageID,
            revision: documentSession.document.revision,
            sceneID: plan.identity.sceneID,
            rendererGeneration: plan.identity.sceneGeneration
        )
        let transfer = LocalLayerDragTransfer(sessionID: identity.sessionID, sourceNodeID: sourceID)
        activePointerDragTransfer = transfer
        activePointerDropCallback = nil
        dragDropFailure = nil
        lastDragDropAnnouncement = "Dragging object"
        announcementPoster.post(lastDragDropAnnouncement)
        return transfer
    }

    @discardableResult
    func beginPointerDropCallback() -> LocalLayerDragCallbackToken? {
        guard let transfer = activePointerDragTransfer,
              pointerDragMatchesActiveSession(transfer) else { return nil }
        pointerDragCallbackGeneration &+= 1
        let token = LocalLayerDragCallbackToken(
            sessionID: transfer.sessionID,
            generation: pointerDragCallbackGeneration
        )
        activePointerDropCallback = token
        return token
    }

    @discardableResult
    func previewPointerDrag(
        _ transfer: LocalLayerDragTransfer,
        destination: DragDestination,
        callback: LocalLayerDragCallbackToken
    ) -> Bool {
        guard pointerDragMatchesActiveSession(transfer),
              activePointerDropCallback == callback,
              callback.sessionID == transfer.sessionID,
              let identity = dragDropSession.identity else {
            return false
        }
        return previewDragDrop(DragDropCommand(
            identity: identity,
            sourceNodeID: transfer.sourceNodeID,
            destination: destination,
            provenance: .pointer
        ))
    }

    /// Synchronous automation and unit tests use the same capability path but
    /// acquire their callback token at the call boundary.
    @discardableResult
    func previewPointerDrag(_ transfer: LocalLayerDragTransfer, destination: DragDestination) -> Bool {
        guard let callback = beginPointerDropCallback() else { return false }
        return previewPointerDrag(transfer, destination: destination, callback: callback)
    }

    @discardableResult
    func commitPointerDrag(
        _ transfer: LocalLayerDragTransfer,
        destination: DragDestination,
        callback: LocalLayerDragCallbackToken
    ) -> Bool {
        guard pointerDragMatchesActiveSession(transfer),
              activePointerDropCallback == callback,
              callback.sessionID == transfer.sessionID else { return false }
        if case .drafting = dragDropSession.phase,
           !previewPointerDrag(transfer, destination: destination, callback: callback) {
            return false
        }
        guard case .previewing(let preview) = dragDropSession.phase,
              preview.sourceNodeID == transfer.sourceNodeID,
              preview.destination == destination else {
            return false
        }
        activePointerDragTransfer = nil
        invalidatePointerDropCallbacks()
        return commitDragDrop(provenance: .pointer)
    }

    @discardableResult
    func commitPointerDrag(_ transfer: LocalLayerDragTransfer, destination: DragDestination) -> Bool {
        guard let callback = beginPointerDropCallback() else { return false }
        return commitPointerDrag(transfer, destination: destination, callback: callback)
    }

    /// Moving between layer-row drop targets clears only the visual insertion
    /// hint. The source capability remains valid until explicit cancellation,
    /// completion, or a lifecycle/document boundary.
    func clearPointerDragPreview() {
        guard activePointerDragTransfer != nil else { return }
        invalidatePointerDropCallbacks()
        dragDropSession.clearPreview()
    }

    @discardableResult
    func previewDragDrop(sourceID: NodeID, destination: DragDestination, provenance: DragDropProvenance) -> Bool {
        guard let pageID = effectiveSelectedPageID, let plan = canvasRenderPlan else { return false }
        if let selectionError = dragDropSelectionError(for: sourceID) {
            cancelDragDrop()
            rejectDragDropStart(
                sourceID: sourceID,
                pageID: pageID,
                plan: plan,
                error: selectionError,
                provenance: provenance
            )
            return false
        }
        let identity = dragDropSession.begin(documentID: documentSession.document.id, pageID: pageID, revision: documentSession.document.revision, sceneID: plan.identity.sceneID, rendererGeneration: plan.identity.sceneGeneration)
        let command = DragDropCommand(identity: identity, sourceNodeID: sourceID, destination: destination, provenance: provenance)
        return previewDragDrop(command)
    }

    @discardableResult
    private func previewDragDrop(_ command: DragDropCommand) -> Bool {
        do {
            let prepared = try dragDropRegistry.prepare(command, in: documentSession.document, context: dragDropValidationContext)
            dragDropSession.preview(prepared.preview)
            dragDropFailure = nil
            lastDragDropAnnouncement = "Valid drop position"
            announcementPoster.post(lastDragDropAnnouncement)
            recordDragDropDiagnostic(command, start: DispatchTime.now().uptimeNanoseconds, result: .success, failure: nil)
            return true
        } catch let error as DragDropError {
            dragDropSession.fail(error); dragDropFailure = error
            lastDragDropAnnouncement = error.localizedDescription; announcementPoster.post(lastDragDropAnnouncement)
            recordDragDropDiagnostic(command, start: DispatchTime.now().uptimeNanoseconds, result: error == .cancelled ? .cancelled : .failure, failure: error)
            return false
        } catch { return false }
    }

    @discardableResult
    func commitDragDrop(provenance: DragDropProvenance) -> Bool {
        guard let preview = dragDropSession.commit() else { return false }
        let command = DragDropCommand(identity: preview.identity, sourceNodeID: preview.sourceNodeID, destination: preview.destination, provenance: provenance)
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let prepared = try dragDropRegistry.prepare(command, in: documentSession.document, context: dragDropValidationContext)
            _ = try documentSession.execute(prepared.command)
            dragDropFailure = nil
            lastDragDropAnnouncement = "Moved object"
            announcementPoster.post(lastDragDropAnnouncement)
            recordDragDropDiagnostic(command, start: start, result: .success, failure: nil)
            dragDropSession.deactivate()
            activePointerDragTransfer = nil
            invalidatePointerDropCallbacks()
            refreshSelectionScene(boundary: .rendererGeneration)
            return true
        } catch let error as DragDropError {
            dragDropSession.fail(error); dragDropFailure = error
            recordDragDropDiagnostic(command, start: start, result: error == .cancelled ? .cancelled : .failure, failure: error)
        } catch { dragDropSession.fail(.staleRevision); dragDropFailure = .staleRevision }
        activePointerDragTransfer = nil
        invalidatePointerDropCallbacks()
        return false
    }

    func performDragDrop(sourceID: NodeID, destination: DragDestination, provenance: DragDropProvenance) {
        guard previewDragDrop(sourceID: sourceID, destination: destination, provenance: provenance) else { return }
        commitDragDrop(provenance: provenance)
    }

    func dragDestination(before targetID: NodeID) -> DragDestination? {
        guard let pageID = effectiveSelectedPageID,
              let page = documentSession.document.pages.first(where: { $0.id == pageID }),
              let target = page.nodes.first(where: { $0.id == targetID }) else { return nil }
        switch target.parent {
        case .page:
            guard let index = page.rootNodeIDs.firstIndex(of: targetID) else { return nil }
            return .root(pageID, index: index)
        case .node(let parentID):
            guard let parent = page.nodes.first(where: { $0.id == parentID }),
                  let index = parent.childIDs.firstIndex(of: targetID) else { return nil }
            return .container(parentID, index: index)
        }
    }

    func dragDestination(nestingIn targetID: NodeID) -> DragDestination? {
        guard let pageID = effectiveSelectedPageID,
              let page = documentSession.document.pages.first(where: { $0.id == pageID }),
              let target = page.nodes.first(where: { $0.id == targetID }) else { return nil }
        return .container(targetID, index: target.childIDs.count)
    }

    func cancelDragDrop() {
        let wasActive = dragDropSession.identity != nil || activePointerDragTransfer != nil
        activePointerDragTransfer = nil
        invalidatePointerDropCallbacks()
        guard wasActive else { return }
        dragDropSession.cancel(); dragDropFailure = nil
        lastDragDropAnnouncement = "Drag cancelled; document unchanged"
        announcementPoster.post(lastDragDropAnnouncement)
    }

    private func pointerDragMatchesActiveSession(_ transfer: LocalLayerDragTransfer) -> Bool {
        guard activePointerDragTransfer == transfer,
              let identity = dragDropSession.identity else { return false }
        return identity.sessionID == transfer.sessionID
    }

    /// Dragging is a single-object operation in this slice. The canonical
    /// drag registry remains selection-agnostic; this scene-owned bridge
    /// applies the noncanonical selection contract uniformly to pointer,
    /// keyboard, menu, contextual, accessibility, and automation entry paths.
    private func dragDropSelectionError(for sourceID: NodeID) -> DragDropError? {
        guard selectionState.orderedIDs.contains(sourceID) else {
            return .sourceNotSelected
        }
        guard selectionState.count == 1 else {
            return .multipleSelectionUnsupported
        }
        return nil
    }

    private func rejectDragDropStart(
        sourceID: NodeID,
        pageID: PageID,
        plan: CanvasRenderPlan,
        error: DragDropError,
        provenance: DragDropProvenance
    ) {
        let identity = dragDropSession.begin(
            documentID: documentSession.document.id,
            pageID: pageID,
            revision: documentSession.document.revision,
            sceneID: plan.identity.sceneID,
            rendererGeneration: plan.identity.sceneGeneration
        )
        let command = DragDropCommand(
            identity: identity,
            sourceNodeID: sourceID,
            destination: .root(pageID, index: 0),
            provenance: provenance
        )
        dragDropSession.fail(error)
        dragDropFailure = error
        lastDragDropAnnouncement = error.localizedDescription
        announcementPoster.post(lastDragDropAnnouncement)
        recordDragDropDiagnostic(
            command,
            start: DispatchTime.now().uptimeNanoseconds,
            result: .failure,
            failure: error
        )
    }

    private func invalidatePointerDropCallbacks() {
        pointerDragCallbackGeneration &+= 1
        activePointerDropCallback = nil
    }

    private var dragDropValidationContext: DragDropValidationContext {
        let disabled: String?
        if isPreviewPresented {
            disabled = "Close Preview before moving content."
        } else {
            switch lifecycle.phase {
            case .saving, .autosaving:
                disabled = "Wait for the current save operation to finish."
            case .conflicted:
                disabled = "Resolve the file conflict before moving content."
            case .clean, .modified, .failed, .recovered:
                disabled = nil
            }
        }
        // Layers/drag ownership is canonical and may include nonvisual
        // structural containers. Rendering still excludes geometry-less blank
        // roots, but they must remain valid parents for a typed move command.
        let canonicalIDs = Set(
            documentSession.document.pages
                .first(where: { $0.id == effectiveSelectedPageID })?
                .nodes.map(\.id) ?? []
        )
        return .init(activePageID: effectiveSelectedPageID ?? PageID(), sceneID: canvasRenderPlan?.identity.sceneID ?? CanvasViewportSceneID(), rendererGeneration: canvasRenderPlan?.identity.sceneGeneration ?? UInt64.max, availableNodeIDs: canonicalIDs, isLifecycleAvailable: disabled == nil, lifecycleDisabledReason: disabled)
    }

    private func recordDragDropDiagnostic(_ command: DragDropCommand, start: UInt64, result: DragDropDiagnosticResult, failure: DragDropError?) {
        let record = DragDropDiagnosticFactory.make(command: command, durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000, result: result, failure: failure)
        Task { await dragDropDiagnostics.append(record) }
    }

    private var defaultInsertionPoint: WorldPoint {
        let visible = viewportState.visibleWorldRect
        // Default insertion is a canonical command input, so its placement
        // must use the same v1 dimensions as the eventual node. In
        // particular, a Section is 960×320 rather than the legacy Frame
        // fallback; otherwise the apparent "centre" is its top-left corner.
        let kind = InsertionKind(rawValue: selectedTool.rawValue) ?? .frame
        let size = InsertionGeometry.defaultValue(for: kind, at: .init(x: 0, y: 0)).size
        return WorldPoint(
            x: visible.origin.x + max(0, (visible.size.width - size.width) / 2),
            y: visible.origin.y + max(0, (visible.size.height - size.height) / 2)
        )
    }

    private var insertionValidationContext: InsertionValidationContext {
        let page = pages.first(where: { $0.id == effectiveSelectedPageID })
        // Structural page roots intentionally do not produce render objects,
        // but they remain valid canonical insertion destinations for an empty
        // page. A newly inserted canonical container can also become the
        // selected insertion parent one publication before the selection
        // scene adopts its render target. Eligibility therefore comes from
        // the active page's responsive visibility for that exact parent,
        // while every other target continues to use the adopted scene. This
        // keeps menu validation deterministic without making hidden
        // containers or stale nodes available.
        let available = selectionScene.map { scene in
            var result = Set(scene.targets.filter(\.isAvailable).map(\.id))
                .union(page?.rootNodeIDs ?? [])
            if let page,
               let parentID = insertionParentID,
               page.effectiveVisibleNodeIDs(breakpoint: viewportPreset.responsiveBreakpoint).contains(parentID) {
                result.insert(parentID)
            }
            return result
        }
        let lifecycleAvailable: Bool
        let reason: String?
        if isPreviewPresented {
            lifecycleAvailable = false
            reason = "Close Preview before inserting content."
        } else {
            switch lifecycle.phase {
            case .saving, .autosaving:
                // Durable saves and recovery autosaves operate on immutable
                // document/history snapshots. A later canonical transaction
                // advances the revision, causing the completed write to
                // publish Modified rather than overwriting or claiming the
                // newer state. Insertion therefore remains available just as
                // inline text editing does; blocking it makes ordinary native
                // menu commands timing-dependent on background I/O.
                lifecycleAvailable = true
                reason = nil
            case .conflicted:
                lifecycleAvailable = false
                reason = "Resolve the file conflict before inserting content."
            case .clean, .modified, .failed, .recovered:
                lifecycleAvailable = true
                reason = nil
            }
        }
        return InsertionValidationContext(
            activePageID: page?.id ?? PageID(),
            activeRoute: page?.route ?? PageRoute(rawValue: "/unavailable"),
            operationGeneration: insertionSession.generation,
            availableNodeIDs: available,
            isLifecycleAvailable: lifecycleAvailable,
            lifecycleDisabledReason: reason
        )
    }

    private func armInsertion(_ kind: InsertionKind) {
        guard let pageID = effectiveSelectedPageID else { return }
        insertionSession.arm(
            kind: kind,
            documentID: documentSession.document.id,
            pageID: pageID,
            revision: documentSession.document.revision
        )
        insertionFailure = nil
        lastInsertionAnnouncement = "\(kind.rawValue.capitalized) tool armed. Click the canvas or use Insert at Center."
        announcementPoster.post(lastInsertionAnnouncement)
    }

    private var insertionParentID: NodeID? {
        guard let page = pages.first(where: { $0.id == effectiveSelectedPageID }) else { return nil }
        if let primaryID = selectionState.primaryID,
           page.nodes.first(where: { $0.id == primaryID })?.kind.acceptsAuthoredChildren == true {
            return primaryID
        }
        return page.rootNodeIDs.first
    }

    private func makeInsertionCommand(
        _ kind: InsertionKind,
        at point: WorldPoint,
        provenance: InsertionProvenance,
        nodeID: NodeID
    ) -> AuthoringInsertionCommand? {
        guard let pageID = effectiveSelectedPageID,
              let parentID = insertionParentID,
              let page = pages.first(where: { $0.id == pageID }),
              let parent = page.nodes.first(where: { $0.id == parentID }) else { return nil }
        // Availability queries occur before a tool is armed. They must model
        // the same current document/page/revision boundary as the eventual
        // session, without mutating editor state or falsely disabling a real
        // visible insertion action on an empty canvas.
        let identity = insertionSession.identity ?? InsertionOperationIdentity(
            documentID: documentSession.document.id,
            pageID: pageID,
            revision: documentSession.document.revision,
            generation: insertionSession.generation
        )
        guard page.id == identity.pageID else { return nil }
        let geometry = InsertionGeometry.defaultValue(for: kind, at: point)
        if kind == .frame {
            return .frame(FrameInsertionCommand(
                identity: identity,
                nodeID: nodeID,
                parentID: parentID,
                index: parent.childIDs.count,
                geometry: geometry,
                provenance: provenance
            ))
        }
        if kind == .text {
            return .text(TextInsertionCommand(
                identity: identity,
                nodeID: nodeID,
                parentID: parentID,
                index: parent.childIDs.count,
                geometry: geometry,
                text: InsertionPolicy.defaultText,
                provenance: provenance
            ))
        }
        if kind == .image {
            guard let assetID = selectedAssetID,
                  documentSession.document.imageAssets.contains(where: { $0.id == assetID }) else {
                return nil
            }
            return .image(ImageInsertionCommand(
                identity: identity, nodeID: nodeID, parentID: parentID,
                index: parent.childIDs.count, geometry: geometry,
                assetID: assetID, provenance: provenance
            ))
        }
        return .container(ContainerInsertionCommand(
            kind: kind, identity: identity, nodeID: nodeID, parentID: parentID,
            index: parent.childIDs.count, geometry: geometry, provenance: provenance
        ))
    }

    private func commitInsertion(
        _ kind: InsertionKind,
        at point: WorldPoint,
        provenance: InsertionProvenance,
        keepsToolArmed: Bool
    ) {
        if insertionSession.identity == nil { armInsertion(kind) }
        let nodeID: NodeID
        let geometry: InsertionGeometry
        if case .previewing(let preview) = insertionSession.phase, preview.kind == kind {
            nodeID = preview.nodeID
            geometry = preview.geometry
        } else {
            nodeID = NodeID()
            geometry = .defaultValue(for: kind, at: point)
        }
        guard var command = makeInsertionCommand(kind, at: geometry.origin, provenance: provenance, nodeID: nodeID) else {
            insertionSession.fail(.missingParent)
            insertionFailure = .missingParent
            return
        }
        // Preserve the exact preview geometry rather than regenerating it after a gesture.
        if kind == .frame, case .frame(let value) = command {
            command = .frame(FrameInsertionCommand(
                identity: value.identity, nodeID: value.nodeID, parentID: value.parentID,
                index: value.index, geometry: geometry, provenance: value.provenance
            ))
        } else if kind == .text, case .text(let value) = command {
            command = .text(TextInsertionCommand(
                identity: value.identity, nodeID: value.nodeID, parentID: value.parentID,
                index: value.index, geometry: geometry, text: value.text, provenance: value.provenance
            ))
        } else if kind == .image, case .image(let value) = command {
            command = .image(ImageInsertionCommand(
                identity: value.identity, nodeID: value.nodeID, parentID: value.parentID,
                index: value.index, geometry: geometry, assetID: value.assetID,
                provenance: value.provenance
            ))
        } else if case .container(let value) = command {
            command = .container(ContainerInsertionCommand(
                kind: value.kind, identity: value.identity, nodeID: value.nodeID, parentID: value.parentID,
                index: value.index, geometry: geometry, provenance: value.provenance
            ))
        }
        let parentRevision = documentSession.document.revision
        let start = DispatchTime.now().uptimeNanoseconds
        let preview = InsertionPreview(kind: kind, nodeID: nodeID, geometry: geometry)
        insertionSession.beginCommit(preview)
        let signpost = OSSignpostID(log: InsertionSignposts.log)
        os_signpost(.begin, log: InsertionSignposts.log, name: "InsertionCommit", signpostID: signpost)
        defer { os_signpost(.end, log: InsertionSignposts.log, name: "InsertionCommit", signpostID: signpost) }
        do {
            let prepared = try insertionRegistry.prepare(
                command,
                in: documentSession.document,
                context: insertionValidationContext
            )
            _ = try documentSession.execute(prepared.documentCommand)
            insertionFailure = nil
            pendingSelectionAfterInsertion = prepared.node.id
            // Combine publication is intentionally asynchronous with respect
            // to this synchronous transaction. Start the next render request
            // here as well so post-commit selection adoption is deterministic
            // and never depends on a structural-root fallback scene.
            scheduleScenePreparation()
            lastInsertionAnnouncement = "Inserted \(kind.rawValue)"
            announcementPoster.post(lastInsertionAnnouncement)
            recordInsertionDiagnostic(
                command, start: start, parentRevision: parentRevision,
                resultRevision: documentSession.document.revision, result: .success, failure: nil
            )
            if keepsToolArmed {
                armInsertion(kind)
            } else {
                // This is only scene-local tool state. The canonical mutation
                // and pending selection above remain intact.
                insertionSession.deactivate()
                selectedTool = .select
            }
        } catch let error as InsertionError {
            insertionSession.fail(error)
            insertionFailure = error
            recordInsertionDiagnostic(
                command, start: start, parentRevision: parentRevision,
                resultRevision: nil,
                result: error == .cancelled ? .cancelled : error == .staleDocument || error == .staleRevision || error == .staleGeneration ? .stale : .failure,
                failure: error
            )
        } catch let error as CommandExecutionError {
            let insertionError: InsertionError = error == .cancelled ? .cancelled : .staleRevision
            insertionSession.fail(insertionError)
            insertionFailure = insertionError
            recordInsertionDiagnostic(
                command, start: start, parentRevision: parentRevision,
                resultRevision: nil, result: error == .cancelled ? .cancelled : .failure,
                failure: insertionError
            )
        } catch {}
    }

    private func recordInsertionDiagnostic(
        _ command: AuthoringInsertionCommand,
        start: UInt64,
        parentRevision: UInt64,
        resultRevision: UInt64?,
        result: InsertionDiagnosticResult,
        failure: InsertionError?
    ) {
        let record = InsertionDiagnosticFactory.make(
            kind: command.kind,
            nodeID: command.nodeID,
            parentID: command.parentID,
            durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
            parentRevision: parentRevision,
            resultRevision: resultRevision,
            result: result,
            failure: failure
        )
        Task { await insertionDiagnostics.append(record) }
    }

    func undo() {
        cancelDragDrop()
        cancelTextEditing()
        cancelInsertion(resetTool: true)
        cancelTransform()
        cancelGuideEditing()
        try? documentSession.undo()
        repairSelectedGuide()
        refreshSelectionScene(boundary: .undo)
    }

    func redo() {
        cancelDragDrop()
        cancelTextEditing()
        cancelInsertion(resetTool: true)
        cancelTransform()
        cancelGuideEditing()
        try? documentSession.redo()
        repairSelectedGuide()
        refreshSelectionScene(boundary: .redo)
    }

    private func repairSelectedGuide() {
        if let selectedGuideID, !activeGuides.contains(where: { $0.id == selectedGuideID }) {
            self.selectedGuideID = nil
            lastGuideAnnouncement = "Authored guide selection cleared because the guide is unavailable"
            announcementPoster.post(lastGuideAnnouncement)
        }
    }

    private func updateViewportContentBounds() {
        // The prior selection plan is expressed in the prior immutable
        // viewport snapshot. Do not reinterpret it with the newly selected
        // artboard while asynchronous renderer preparation is in flight: that
        // would draw a stale Desktop outline over the Mobile pasteboard.
        // Canonical selection identity stays intact and is rebuilt only when
        // the matching renderer plan adopts.
        selectionOverlayPlan = nil
        let bounds = WorldRect(
            origin: WorldPoint(x: 0, y: 0),
            size: WorldSize(width: Double(viewportPreset.width), height: 900)
        )
        try? viewportState.setContentBounds(bounds)
        // A preset is presentation state. Fit with a pasteboard gutter so the
        // real artboard boundary remains visible; authored coordinates and
        // selection identity stay unchanged.
        try? viewportState.fit(.fitDocument)
        cancelDragDrop()
        scheduleScenePreparation()
    }

    private func synchronizeViewportDocumentBoundary(_ document: CanonicalDocument) {
        refreshImageThumbnails(for: document)
        if case .committing = dragDropSession.phase {
            // The synchronous drag transaction owns this exact revision transition.
        } else if let identity = dragDropSession.identity,
                  identity.documentID != document.id || identity.revision != document.revision {
            cancelDragDrop()
        }
        if case .committing = textEditingSession.phase {
            // The synchronous text transaction owns this exact revision transition.
        } else if let identity = textEditingSession.draft?.activation.identity,
                  identity.documentID != document.id || identity.revision != document.revision {
            cancelTextEditing()
        }
        if case .committing = insertionSession.phase {
            // The synchronous transaction owns this revision transition.
        } else if let identity = insertionSession.identity,
                  identity.documentID != document.id || identity.revision != document.revision {
            cancelInsertion(resetTool: true)
        }
        if case .committing = transformSession.phase {
            // The synchronous transform transaction owns this exact revision transition.
        } else if let identity = transformSession.currentIdentity,
                  identity.documentID != document.id || identity.revision != document.revision {
            cancelTransform()
        }
        if case .committing = guideEditingSession.phase {
            // The synchronous guide transaction owns this exact revision transition.
        } else if let identity = guideEditingSession.currentIdentity,
                  identity.documentID != document.id || identity.revision != document.revision {
            cancelGuideEditing()
        }
        repairSelectedGuide()
        guard document.id != viewportDocumentID else {
            scheduleScenePreparation()
            return
        }
        cancelViewportPreparation()
        viewportDocumentID = document.id
        viewportState = try! CanvasViewportState(
            viewportSize: viewportState.viewportSize,
            contentBounds: WorldRect(
                origin: WorldPoint(x: 0, y: 0),
                size: WorldSize(width: Double(viewportPreset.width), height: 900)
            ),
            pixelRatio: viewportState.pixelRatio
        )
        shouldInitialFitViewport = true
        preparedViewportScene = nil
        canvasRenderPlan = nil
        previousRenderScene = nil
        selectionState = SelectionState()
        selectionScene = nil
        selectionOverlayPlan = nil
        insertionSession.deactivate()
        insertionFailure = nil
        transformSession.deactivate()
        transformFailure = nil
        snapResolution = nil
        guideEditingSession.deactivate()
        guideFailure = nil
        textEditingSession = InlineTextEditingSession()
        retainedTextEditingFrame = nil
        textEditingFailure = nil
        selectedGuideID = nil
        pendingSelectionAfterInsertion = nil
        pendingSelectionLifecycleBoundary = nil
        canvasRendererFailure = nil
        viewportFailure = nil
        lastViewportAnnouncement = "Canvas viewport reset for the opened document"
        announcementPoster.post(lastViewportAnnouncement)
        scheduleScenePreparation()
    }

    private func scheduleScenePreparation() {
        preparationTask?.cancel()
        let imageResources: [AssetID: Data] = Dictionary(uniqueKeysWithValues: documentSession.document.imageAssets.compactMap { asset -> (AssetID, Data)? in
            guard let data = try? lifecycle.projectResourceData(for: asset.resourceID) else { return nil }
            return (asset.id, data)
        })
        let request = WorkspaceScenePreparationRequest(
            document: documentSession.document,
            activePageID: effectiveSelectedPageID,
            activeContainerID: selectionState.activeContainerID,
            viewport: viewportState,
            surfaceID: renderSurfaceID,
            breakpoint: viewportPreset.responsiveBreakpoint,
            imageResourceData: imageResources
        )
        let expectedIdentity = CanvasRenderRequestIdentity(
            documentID: request.document.id,
            revision: request.document.revision,
            sceneID: request.viewport.sceneID,
            sceneGeneration: request.document.revision,
            viewportGeneration: request.viewport.generation,
            scale: request.viewport.pixelRatio
        )
        let previous = previousRenderScene
        let selectionBoundary = pendingSelectionLifecycleBoundary ?? .rendererGeneration
        let start = DispatchTime.now().uptimeNanoseconds
        let signpostID = OSSignpostID(log: CanvasRendererSignposts.log)
        os_signpost(
            .begin,
            log: CanvasRendererSignposts.log,
            name: "CanvasRenderPrepare",
            signpostID: signpostID,
            "generation=%{public}llu",
            expectedIdentity.viewportGeneration
        )
        // The task remains main-actor owned only for state adoption. Snapshot
        // projection, viewport preparation, and renderer planning each execute
        // on their dedicated actors at user-initiated priority.
        preparationTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            defer {
                os_signpost(
                    .end,
                    log: CanvasRendererSignposts.log,
                    name: "CanvasRenderPrepare",
                    signpostID: signpostID
                )
            }
            guard let self else { return }
            do {
                let prepared = try await scenePreparationWorker.prepare(request)
                async let viewportPreparation = viewportPreparer.prepare(
                    prepared.viewportRequest,
                    cancellation: CanvasViewportCancellation(isCancelled: { Task.isCancelled })
                )

                do {
                    let plan = try await renderWorker.prepare(
                        scene: prepared.renderScene,
                        overlays: prepared.overlays,
                        viewport: request.viewport,
                        previous: previous
                    )
                    let currentIdentity = CanvasRenderRequestIdentity(
                        documentID: documentSession.document.id,
                        revision: documentSession.document.revision,
                        sceneID: viewportState.sceneID,
                        sceneGeneration: documentSession.document.revision,
                        viewportGeneration: viewportState.generation,
                        scale: viewportState.pixelRatio
                    )
                    try CanvasRenderAdoptionGate().validate(plan, expected: currentIdentity)
                    previousRenderScene = prepared.renderScene
                    canvasRenderPlan = plan
                    canvasRendererFailure = nil
                    adoptSelectionScene(
                        prepared.selectionScene,
                        from: plan,
                        boundary: selectionBoundary
                    )
                    pendingSelectionLifecycleBoundary = nil
                    await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                        operation: "prepare",
                        plan: plan,
                        identity: expectedIdentity,
                        surfaceID: renderSurfaceID,
                        durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                        result: .success
                    ))
                } catch CanvasRendererError.cancelled {
                    await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                        operation: "prepare", plan: nil, identity: expectedIdentity, surfaceID: renderSurfaceID,
                        durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                        result: .cancelled, failureCategory: "cancelled"
                    ))
                } catch CanvasRendererError.staleResult {
                    await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                        operation: "adopt", plan: nil, identity: expectedIdentity, surfaceID: renderSurfaceID,
                        durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                        result: .stale, failureCategory: "stale-result"
                    ))
                } catch let error as CanvasRendererError {
                    canvasRendererFailure = error
                    await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                        operation: "prepare", plan: nil, identity: expectedIdentity, surfaceID: renderSurfaceID,
                        durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                        result: .failure, failureCategory: String(describing: error)
                    ))
                } catch {}

                do {
                    let viewportResult = try await viewportPreparation
                    try CanvasViewportAdoptionGate().validate(
                        viewportResult,
                        expected: currentViewportOperationIdentity
                    )
                    preparedViewportScene = viewportResult
                    viewportFailure = nil
                } catch CanvasViewportError.cancelled {
                    // Cancellation and stale completion are state neutral.
                } catch CanvasViewportError.staleResult {
                    // A newer generation owns adoption.
                } catch let error as CanvasViewportError {
                    viewportFailure = error
                } catch {}
            } catch WorkspaceScenePreparationError.cancelled {
                await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                    operation: "prepare", plan: nil, identity: expectedIdentity, surfaceID: renderSurfaceID,
                    durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                    result: .cancelled, failureCategory: "cancelled"
                ))
            } catch {}
        }
    }

    private func adoptSelectionScene(
        _ preparedScene: SelectionSceneSnapshot?,
        from plan: CanvasRenderPlan,
        boundary: SelectionLifecycleBoundary
    ) {
        guard var scene = preparedScene, scene.identity == plan.identity else { return }
        if let pending = pendingSelectionAfterInsertion,
           let target = scene.targets.first(where: { $0.id == pending }) {
            scene = SelectionSceneSnapshot(
                identity: scene.identity,
                activePageID: scene.activePageID,
                activeContainerID: target.parentID,
                targets: scene.targets
            )
        }
        let prior = selectionState
        do {
            let repair = try selectionRegistry.adopt(scene, boundary: boundary, state: &selectionState)
            selectionScene = scene
            selectionFailure = nil
            rebuildSelectionOverlay()
            if let pending = pendingSelectionAfterInsertion,
               scene.orderedSelectableTargets.contains(where: { $0.id == pending }) {
                _ = try selectionRegistry.apply(
                    SelectionCommand(
                        .replace,
                        targetID: pending,
                        expectedIdentity: scene.identity,
                        provenance: .lifecycleRepair
                    ),
                    to: &selectionState,
                    scene: scene
                )
                pendingSelectionAfterInsertion = nil
                rebuildSelectionOverlay()
                announceSelection()
            }
            if selectionState != prior || repair != .none {
                // Renderer adoption advances scene/generation identity even
                // when the user's selected objects have not changed. Design
                // feedback belongs to the semantic selection, not to that
                // transient renderer identity; otherwise a successful style
                // transaction immediately overwrites its own announcement.
                if !hasSameSelectionPresentation(prior, selectionState) {
                    resetDesignInspectorContextForSelectionChange()
                }
                announceSelection()
            }
        } catch let error as SelectionCommandError {
            selectionState = prior
            selectionFailure = error
        } catch {
            selectionState = prior
        }
    }

    private func hasSameSelectionPresentation(
        _ lhs: SelectionState,
        _ rhs: SelectionState
    ) -> Bool {
        lhs.orderedIDs == rhs.orderedIDs
            && lhs.primaryID == rhs.primaryID
            && lhs.anchorID == rhs.anchorID
            && lhs.activePageID == rhs.activePageID
            && lhs.activeContainerID == rhs.activeContainerID
    }

    private func refreshSelectionScene(boundary: SelectionLifecycleBoundary) {
        pendingSelectionLifecycleBoundary = boundary
        let activePageID = effectiveSelectedPageID
        if selectionState.activePageID != nil,
           selectionState.activePageID != activePageID {
            selectionState.setSelection(
                [], primary: nil, anchor: nil,
                provenance: .lifecycleRepair,
                repair: .pageChanged
            )
            selectionState.setContainer(nil)
        } else if let activePageID,
                  let page = documentSession.document.pages.first(where: { $0.id == activePageID }) {
            // Keep the synchronous lifecycle repair proportional to the
            // current selection, not to the whole document. The complete
            // target catalog and renderer projection are rebuilt off-main.
            // The implicit structural root is deliberately projected as the
            // page-level (nil) selection container by scene preparation. Use
            // that same projection here so undo/redo cannot misclassify a
            // surviving page-level node as removed before async adoption.
            let structuralRootIDs = Set(page.rootNodeIDs.filter { rootID in
                page.nodes.first(where: { $0.id == rootID })?.insertionGeometry == nil
            })
            let retained = selectionState.orderedIDs.filter { id in
                guard let node = page.nodes.first(where: { $0.id == id }) else { return false }
                let canonicalParentID: NodeID? = if case .node(let value) = node.parent { value } else { nil }
                let parentID = canonicalParentID.flatMap {
                    structuralRootIDs.contains($0) ? nil : $0
                }
                return parentID == selectionState.activeContainerID
                    && !node.selectionBooleanProperty("hidden")
                    && !node.selectionBooleanProperty("locked")
            }
            let primary = selectionState.primaryID.flatMap { retained.contains($0) ? $0 : nil } ?? retained.last
            let anchor = selectionState.anchorID.flatMap { retained.contains($0) ? $0 : nil } ?? retained.first
            selectionState.setSelection(
                retained,
                primary: primary,
                anchor: anchor,
                provenance: retained == selectionState.orderedIDs ? selectionState.provenance : .lifecycleRepair,
                repair: retained == selectionState.orderedIDs ? .none : .removed
            )
        }
        selectionScene = nil
        selectionOverlayPlan = nil
        scheduleScenePreparation()
    }

    private func rebuildSelectionOverlay() {
        guard let scene = selectionScene, let plan = canvasRenderPlan else {
            selectionOverlayPlan = nil
            return
        }
        do {
            selectionOverlayPlan = try selectionOverlayPlanner.plan(
                selection: selectionState,
                scene: scene,
                renderPlan: plan,
                previous: selectionOverlayPlan
            )
        } catch let error as SelectionCommandError {
            selectionFailure = error
        } catch {}
    }

    private func announceSelection() {
        lastSelectionAnnouncement = selectionState.isEmpty
            ? "Selection cleared"
            : selectionState.count == 1
                ? "Selected \(selectionSummary)"
                : "Selected \(selectionState.count) objects"
        announcementPoster.post(lastSelectionAnnouncement)
    }

    private func recordSelectionDiagnostic(
        _ operation: SelectionCommandName,
        start: UInt64,
        result: SelectionDiagnosticResult,
        repair: SelectionRepairCategory?,
        failure: String?
    ) {
        let record = SelectionDiagnosticFactory.make(
            operation: operation,
            state: selectionState,
            durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
            result: result,
            repair: repair,
            failure: failure
        )
        Task { await selectionDiagnostics.append(record) }
    }

    private func announceViewport(_ operation: CanvasViewportCommandName) {
        switch operation {
        case .zoomIn, .zoomOut, .actualSize, .fitDocument, .fitWidth:
            lastViewportAnnouncement = String(format: "Canvas zoom %d percent", zoomPercent)
        case .panLeft, .panRight, .panUp, .panDown:
            lastViewportAnnouncement = "Canvas panned " + operation.rawValue
        }
        announcementPoster.post(lastViewportAnnouncement)
    }

    private func recordViewportDiagnostic(
        _ operation: CanvasViewportCommandName,
        start: UInt64,
        result: CanvasViewportDiagnosticResult,
        failure: String?
    ) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let sceneIdentifier = DiagnosticStableIdentifier.sanitize(
            viewportState.sceneID.description,
            domain: .viewport,
            kind: "scene"
        )
        let record = CanvasViewportDiagnosticRecord(
            requirementID: "SF-0401-008",
            operation: operation,
            sceneIdentifier: sceneIdentifier,
            generation: viewportState.generation,
            durationMilliseconds: Double(elapsed) / 1_000_000,
            result: result,
            failureCategory: failure.map {
                DiagnosticErrorCategory.closedCategory(forUntrustedValue: $0).rawValue
            }
        )
        Task { await viewportDiagnostics.append(record) }
    }

}
