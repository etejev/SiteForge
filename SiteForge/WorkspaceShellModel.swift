import Combine
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
    case section, stack, grid, frame, text, button, link, divider, navbar, footer

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var category: String {
        switch self {
        case .section, .stack, .grid, .frame: "Layout"
        case .text, .button, .link, .divider: "Basic"
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
        guard composition.value(after: "-SiteForgeWindowSize") == "minimum"
                || composition.boolValue(after: "-SiteForgeUITestMode") == true else { return nil }
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
        // display's menu-bar-safe edge. Explicit Debug/UI-test placement
        // therefore permits test content to compress to the fitted frame on
        // both axes;
        // production and Release composition retain the full minimum.
        // A named constrained-display UI test is the sole composition allowed
        // to fit below the product minimum. Fit both axes: retaining the
        // production width on a narrower hosted display leaves trailing
        // status controls in the accessibility tree but outside the visible
        // window, so they cannot be pointer-tested honestly.
        return CGSize(width: 1, height: 1)
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
        // Debug/UI-test windows to the available safe edges before AppKit can
        // apply an origin-dependent constraint of its own.
        let width = min(windowFrame.width, max(1, visibleFrame.width - (inset * 2)))
        let height = min(windowFrame.height, max(1, visibleFrame.height - inset))
        let x = switch placement.horizontal {
        case .left: visibleFrame.minX + inset
        case .right: visibleFrame.maxX - width - inset
        }
        let y = switch placement.vertical {
        case .top: visibleFrame.maxY - height - inset
        case .bottom: visibleFrame.minY + inset
        }
        return CGRect(
            x: x,
            y: y,
            width: width,
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
        // menu bar and Dock while remaining a normal (non-Space) window.
        return visibleFrame
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
        guard var page = document.pages.first else { return document }
        let extraIDs = [
            NodeID(UUID(uuidString: "77777777-7777-4777-8777-777777777701")!),
            NodeID(UUID(uuidString: "77777777-7777-4777-8777-777777777702")!),
        ]
        page.rootNodeIDs.append(contentsOf: extraIDs)
        page.nodes.append(contentsOf: extraIDs.enumerated().map { offset, id in
            DocumentNode(id: id, kind: .frame, name: "Fixture Layer \(offset + 2)", parent: .page(page.id))
        })
        document.pages[0] = page
        return document
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
    @Published private(set) var snapResolution: SnapResolution?
    @Published private(set) var isSnappingSuppressed = false
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
    private let renderWorker = CanvasRenderWorker()
    private let selectionRegistry = SelectionCommandRegistry()
    private let selectionOverlayPlanner = SelectionOverlayPlanner()
    private let insertionRegistry = InsertionCommandRegistry()
    private let dragDropRegistry = DragDropCommandRegistry()
    private let textEditingRegistry = InlineTextCommandRegistry()
    private let transformRegistry = TransformCommandRegistry()
    private let snapResolver = SnapResolver()
    private let guideRegistry = GuideCommandRegistry()
    private let renderSurfaceID = CanvasRenderSurfaceID()
    let canvasRenderDiagnostics = CanvasRenderDiagnostics()
    let selectionDiagnostics = SelectionDiagnostics()
    let insertionDiagnostics = InsertionDiagnostics()
    let dragDropDiagnostics = DragDropDiagnostics()
    let textEditingDiagnostics = TextEditDiagnostics()
    let transformDiagnostics = TransformDiagnostics()
    let snapDiagnostics = SnapDiagnostics()
    let viewportDiagnostics: CanvasViewportDiagnostics
    private let announcementPoster: AccessibilityAnnouncementPoster
    private var viewportDocumentID: DocumentID
    private var preparationTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var previousRenderScene: CanvasRenderSceneSnapshot?
    private var selectionScene: SelectionSceneSnapshot?
    private var pendingSelectionAfterInsertion: NodeID?
    private var retainedTextEditingFrame: WorldRect?
    private var activePointerDragTransfer: LocalLayerDragTransfer?
    private var activePointerDropCallback: LocalLayerDragCallbackToken?
    private var pointerDragCallbackGeneration: UInt64 = 0

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
            self?.objectWillChange.send()
            self?.synchronizeViewportDocumentBoundary(document)
        }
    }

    var canUndo: Bool { documentSession.canUndo }
    var canRedo: Bool { documentSession.canRedo }
    var nextUndoLabel: String? { documentSession.nextUndoLabel }
    var nextRedoLabel: String? { documentSession.nextRedoLabel }
    var undoDisabledReason: String? { documentSession.undoAvailability.disabledReason }
    var redoDisabledReason: String? { documentSession.redoAvailability.disabledReason }

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
        scheduleScenePreparation()
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
        renderTask?.cancel()
        renderTask = nil
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

    func selectCanvasPoint(_ point: WorldPoint, modifier: SelectionPointerModifier) {
        if textEditingSession.isActive {
            commitTextEditing()
        }
        if selectedTool == .frame {
            commitInsertion(.frame, at: point, provenance: .pointer)
            return
        }
        if selectedTool == .text {
            commitInsertion(.text, at: point, provenance: .pointer)
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
        let currentFrame = canvasRenderPlan?.authoredObjects.first(where: {
            $0.id == draft.activation.identity.nodeID
        })?.frame
        guard let frame = currentFrame ?? retainedTextEditingFrame else { return nil }
        return InlineTextEditorPresentation(
            identity: draft.activation.identity,
            text: draft.text,
            selection: draft.selection,
            frame: frame
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
                lifecycleAvailable = false
                reason = "Wait for the current save operation to finish."
            case .conflicted:
                lifecycleAvailable = false
                reason = "Resolve the file conflict before transforming content."
            case .clean, .modified, .failed, .recovered:
                lifecycleAvailable = true
                reason = nil
            }
        }
        return TransformValidationContext(
            activePageID: effectiveSelectedPageID ?? PageID(),
            currentSceneID: canvasRenderPlan?.identity.sceneID ?? CanvasViewportSceneID(),
            rendererGeneration: canvasRenderPlan?.identity.sceneGeneration ?? UInt64.max,
            selectedNodeIDs: selectionState.orderedIDs,
            availableNodeIDs: Set(selectionScene?.targets.filter(\.isAvailable).map(\.id) ?? []),
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
        commitInsertion(kind, at: defaultInsertionPoint, provenance: provenance)
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
        // page. All other parent availability continues to come from the
        // currently adopted renderer/selection scene.
        let available = selectionScene.map {
            Set($0.targets.filter(\.isAvailable).map(\.id))
                .union(page?.rootNodeIDs ?? [])
        }
        let lifecycleAvailable: Bool
        let reason: String?
        if isPreviewPresented {
            lifecycleAvailable = false
            reason = "Close Preview before inserting content."
        } else {
            switch lifecycle.phase {
            case .saving, .autosaving:
                lifecycleAvailable = false
                reason = "Wait for the current save operation to finish."
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
        return .container(ContainerInsertionCommand(
            kind: kind, identity: identity, nodeID: nodeID, parentID: parentID,
            index: parent.childIDs.count, geometry: geometry, provenance: provenance
        ))
    }

    private func commitInsertion(
        _ kind: InsertionKind,
        at point: WorldPoint,
        provenance: InsertionProvenance
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
            // The viewport preparer is an auxiliary accessibility/viewport
            // snapshot. A successful canonical insertion must not wait for
            // that asynchronous preparation before publishing its authored
            // render scene to the live canvas.
            scheduleRendererPreparation()
            lastInsertionAnnouncement = "Inserted \(kind.rawValue)"
            announcementPoster.post(lastInsertionAnnouncement)
            recordInsertionDiagnostic(
                command, start: start, parentRevision: parentRevision,
                resultRevision: documentSession.document.revision, result: .success, failure: nil
            )
            armInsertion(kind)
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
        let bounds = WorldRect(
            origin: WorldPoint(x: 0, y: 0),
            size: WorldSize(width: Double(viewportPreset.width), height: 900)
        )
        try? viewportState.setContentBounds(bounds)
        cancelDragDrop()
        scheduleScenePreparation()
    }

    private func synchronizeViewportDocumentBoundary(_ document: CanonicalDocument) {
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
        canvasRendererFailure = nil
        viewportFailure = nil
        lastViewportAnnouncement = "Canvas viewport reset for the opened document"
        announcementPoster.post(lastViewportAnnouncement)
        scheduleScenePreparation()
    }

    private func scheduleScenePreparation() {
        preparationTask?.cancel()
        let activeNodes = renderableNodesForActivePage()
        let objects = activeNodes.map {
            CanvasViewportSceneObject(id: $0.id, bounds: viewportState.contentBounds)
        }
        preparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await prepareViewportScene(objects: objects)
                scheduleRendererPreparation()
            } catch CanvasViewportError.cancelled {
                // Cancellation and stale completion are deliberately state neutral.
            } catch CanvasViewportError.staleResult {
                // A newer generation owns adoption.
            } catch let error as CanvasViewportError {
                viewportFailure = error
            } catch {}
        }
    }

    private func scheduleRendererPreparation() {
        renderTask?.cancel()
        let start = DispatchTime.now().uptimeNanoseconds
        let identity = CanvasRenderRequestIdentity(
            documentID: documentSession.document.id,
            revision: documentSession.document.revision,
            sceneID: viewportState.sceneID,
            sceneGeneration: documentSession.document.revision,
            viewportGeneration: viewportState.generation,
            scale: viewportState.pixelRatio
        )
        let activeNodes = renderableNodesForActivePage()
        let resolvedGeometry = pages.first(where: { $0.id == effectiveSelectedPageID })?.resolvedStructuralGeometry() ?? [:]
        let objects = activeNodes.enumerated().map { index, node in
            // `renderableNodesForActivePage` excludes structural roots, whose
            // absent geometry is intentional and must never be replaced with a
            // visual/debug fallback rectangle.
            let frame = (resolvedGeometry[node.id] ?? node.insertionGeometry!).frame
            let style: CanvasPaintStyle = switch node.kind {
            case .frame:
                if node.parent == .page(effectiveSelectedPageID ?? PageID()) {
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
            return CanvasRenderObject(
                id: node.id,
                frame: frame,
                clipRect: viewportState.contentBounds,
                paintOrder: index,
                style: style,
                isVisible: !node.selectionBooleanProperty("hidden"),
                accessibilityLabel: node.kind == .text ? "Text object" : node.name,
                plainText: node.kind == .text ? node.insertionStringProperty("content.text") : nil,
                displayName: node.kind == .text ? nil : node.name
            )
        }
        let scene = CanvasRenderSceneSnapshot(identity: identity, surfaceID: renderSurfaceID, objects: objects)
        let overlays = CanvasEditorOverlaySnapshot(identity: identity, overlays: [])
        let viewport = viewportState
        let previous = previousRenderScene
        let signpostID = OSSignpostID(log: CanvasRendererSignposts.log)
        os_signpost(
            .begin,
            log: CanvasRendererSignposts.log,
            name: "CanvasRenderPrepare",
            signpostID: signpostID,
            "generation=%{public}llu",
            identity.viewportGeneration
        )
        renderTask = Task { @MainActor [weak self] in
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
                let plan = try await renderWorker.prepare(
                    scene: scene,
                    overlays: overlays,
                    viewport: viewport,
                    previous: previous
                )
                let expected = CanvasRenderRequestIdentity(
                    documentID: documentSession.document.id,
                    revision: documentSession.document.revision,
                    sceneID: viewportState.sceneID,
                    sceneGeneration: documentSession.document.revision,
                    viewportGeneration: viewportState.generation,
                    scale: viewportState.pixelRatio
                )
                try CanvasRenderAdoptionGate().validate(plan, expected: expected)
                previousRenderScene = scene
                canvasRenderPlan = plan
                canvasRendererFailure = nil
                adoptSelectionScene(from: plan, boundary: .rendererGeneration)
                await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                    operation: "prepare", plan: plan, identity: identity, surfaceID: renderSurfaceID,
                    durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                    result: .success
                ))
            } catch CanvasRendererError.cancelled {
                await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                    operation: "prepare", plan: nil, identity: identity, surfaceID: renderSurfaceID,
                    durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                    result: .cancelled, failureCategory: "cancelled"
                ))
            } catch CanvasRendererError.staleResult {
                await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                    operation: "adopt", plan: nil, identity: identity, surfaceID: renderSurfaceID,
                    durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                    result: .stale, failureCategory: "stale-result"
                ))
            } catch let error as CanvasRendererError {
                canvasRendererFailure = error
                await canvasRenderDiagnostics.append(CanvasRenderDiagnosticFactory.make(
                    operation: "prepare", plan: nil, identity: identity, surfaceID: renderSurfaceID,
                    durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000,
                    result: .failure, failureCategory: String(describing: error)
                ))
            } catch {}
        }
    }

    private func makeSelectionScene(from plan: CanvasRenderPlan) -> SelectionSceneSnapshot? {
        guard let pageID = effectiveSelectedPageID else { return nil }
        let rendered = Dictionary(uniqueKeysWithValues: plan.authoredObjects.map { ($0.id, $0) })
        var fallbackOrder = plan.authoredObjects.count
        let targets = documentSession.document.pages.flatMap { page in
            let names = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0.name) })
            return page.canonicalDepthFirstNodes().compactMap { node -> SelectionTargetSnapshot? in
                let object = rendered[node.id]
                // A one-node blank-project root is never visual or
                // selectable. Legacy/nonblank hierarchy roots remain
                // available to the bounded Layers drag-ownership contract.
                guard object != nil || page.nodes.count > 1 else { return nil }
                defer { fallbackOrder += 1 }
                let parentID: NodeID? = if case .node(let id) = node.parent { id } else { nil }
                return SelectionTargetSnapshot(
                    id: node.id,
                    pageID: page.id,
                    parentID: parentID,
                    name: node.name,
                    kind: node.kind,
                    parentName: parentID.flatMap { names[$0] },
                    frame: object?.frame ?? viewportState.contentBounds,
                    clipRect: object?.clipRect,
                    paintOrder: object?.paintOrder ?? fallbackOrder,
                    isVisible: object?.isVisible ?? true,
                    isLocked: node.selectionBooleanProperty("locked"),
                    isAvailable: object != nil || page.nodes.count > 1
                )
            }
        }
        return SelectionSceneSnapshot(
            identity: plan.identity,
            activePageID: pageID,
            activeContainerID: selectionState.activeContainerID,
            targets: targets
        )
    }

    /// Only nodes with canonical authored geometry enter the viewport scene.
    /// Page roots intentionally have no geometry and therefore remain a
    /// nonvisual ownership boundary for an otherwise empty blank project.
    private func renderableNodesForActivePage() -> [DocumentNode] {
        documentSession.document.pages
            .first(where: { $0.id == effectiveSelectedPageID })?
            .canonicalDepthFirstNodes()
            .filter { $0.insertionGeometry != nil } ?? []
    }

    private func adoptSelectionScene(
        from plan: CanvasRenderPlan,
        boundary: SelectionLifecycleBoundary
    ) {
        guard var scene = makeSelectionScene(from: plan) else { return }
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
            if selectionState != prior || repair != .none { announceSelection() }
        } catch let error as SelectionCommandError {
            selectionState = prior
            selectionFailure = error
        } catch {
            selectionState = prior
        }
    }

    private func refreshSelectionScene(boundary: SelectionLifecycleBoundary) {
        guard let plan = canvasRenderPlan else {
            selectionState = SelectionState()
            selectionScene = nil
            selectionOverlayPlan = nil
            return
        }
        adoptSelectionScene(from: plan, boundary: boundary)
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
        let sceneIdentifier = String(viewportState.sceneID.description.prefix(8))
        let record = CanvasViewportDiagnosticRecord(
            requirementID: "SF-0401-008",
            operation: operation,
            sceneIdentifier: sceneIdentifier,
            generation: viewportState.generation,
            durationMilliseconds: Double(elapsed) / 1_000_000,
            result: result,
            failureCategory: failure
        )
        Task { await viewportDiagnostics.append(record) }
    }

}
