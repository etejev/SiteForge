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
        case .frame: "square.dashed"
        case .text: "textformat"
        case .image: "photo"
        case .component: "square.stack.3d.up"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .select: "v"
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

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case layout
    case style
    case advanced
    case accessibility

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
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
    case navigatorPage(PageID)
    case navigatorLayer(NodeID)
    case viewportPreset
    case viewportZoomOut
    case viewportZoomIn
    case viewportReset
    case viewportFit
    case viewportCanvas
    case inspectorLayout
    case inspectorStyle
    case inspectorAdvanced
    case inspectorAccessibility
}

enum ShellFocusDirection {
    case forward
    case reverse
}

enum ShellFocusTraversal {
    static func order(pageIDs: [PageID], layerIDs: [NodeID] = []) -> [ShellFocus] {
        [
            .navigatorPages, .navigatorLayers,
        ] + pageIDs.map(ShellFocus.navigatorPage) + layerIDs.map(ShellFocus.navigatorLayer) + [
            .viewportPreset, .viewportZoomOut, .viewportZoomIn,
            .viewportReset, .viewportFit, .viewportCanvas,
            .inspectorLayout, .inspectorStyle, .inspectorAdvanced, .inspectorAccessibility,
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

    static func usesDeterministicUITestPlacement(
        composition: DebugTestComposition = .current()
    ) -> Bool {
        composition.boolValue(after: "-SiteForgeUITestMode") == true
    }

    static func requestedWindowSize(arguments: [String]) -> CGSize? {
        requestedWindowSize(composition: .current(arguments: arguments))
    }
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
        "SF-0405-001", "SF-0405-002", "SF-0405-003", "SF-0405-004",
        "SF-0405-005", "SF-0405-006", "SF-0405-007", "SF-0405-008",
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
    @Published private(set) var viewportFailure: CanvasViewportError?
    @Published private(set) var lastViewportAnnouncement = "Canvas viewport at 100 percent"
    @Published private(set) var canvasInteractionCount = 0
    @Published var isPreviewPresented = false {
        didSet {
            if isPreviewPresented { cancelInsertion(resetTool: true) }
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
    private let renderSurfaceID = CanvasRenderSurfaceID()
    let canvasRenderDiagnostics = CanvasRenderDiagnostics()
    let selectionDiagnostics = SelectionDiagnostics()
    let insertionDiagnostics = InsertionDiagnostics()
    let viewportDiagnostics: CanvasViewportDiagnostics
    private let announcementPoster: AccessibilityAnnouncementPoster
    private var viewportDocumentID: DocumentID
    private var preparationTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var previousRenderScene: CanvasRenderSceneSnapshot?
    private var selectionScene: SelectionSceneSnapshot?
    private var pendingSelectionAfterInsertion: NodeID?

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
    var undoDisabledReason: String? { documentSession.undoAvailability.disabledReason }
    var redoDisabledReason: String? { documentSession.redoAvailability.disabledReason }

    func selectTool(_ tool: CanvasTool) {
        if selectedTool != tool { cancelInsertion(resetTool: false) }
        selectedTool = tool
        switch tool {
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
        cancelInsertion(resetTool: true)
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
        guard selectedTool == .frame || selectedTool == .text,
              insertionValidationContext.isLifecycleAvailable else { return }
        insertionSession.preview(at: point)
        objectWillChange.send()
    }

    func performDefaultInsertion(_ kind: InsertionKind, provenance: InsertionProvenance) {
        if selectedTool != (kind == .frame ? .frame : .text) {
            selectedTool = kind == .frame ? .frame : .text
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
        switch insertionSession.phase {
        case .armed, .previewing, .committing, .failed:
            cancelInsertion(resetTool: true)
        case .inactive, .cancelled:
            performSelectionCommand(.escape, provenance: .keyboard)
        }
    }

    private var defaultInsertionPoint: WorldPoint {
        let visible = viewportState.visibleWorldRect
        let size = selectedTool == .text
            ? WorldSize(width: 120, height: 24)
            : WorldSize(width: 240, height: 160)
        return WorldPoint(
            x: visible.origin.x + max(0, (visible.size.width - size.width) / 2),
            y: visible.origin.y + max(0, (visible.size.height - size.height) / 2)
        )
    }

    private var insertionValidationContext: InsertionValidationContext {
        let page = pages.first(where: { $0.id == effectiveSelectedPageID })
        let available = selectionScene.map { Set($0.targets.filter(\.isAvailable).map(\.id)) }
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
           page.nodes.first(where: { $0.id == primaryID })?.kind == .frame {
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
        guard let identity = insertionSession.identity,
              let parentID = insertionParentID,
              let page = pages.first(where: { $0.id == identity.pageID }),
              let parent = page.nodes.first(where: { $0.id == parentID }) else { return nil }
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
        cancelInsertion(resetTool: true)
        try? documentSession.undo()
        refreshSelectionScene(boundary: .undo)
    }

    func redo() {
        cancelInsertion(resetTool: true)
        try? documentSession.redo()
        refreshSelectionScene(boundary: .redo)
    }

    private func updateViewportContentBounds() {
        let bounds = WorldRect(
            origin: WorldPoint(x: 0, y: 0),
            size: WorldSize(width: Double(viewportPreset.width), height: 900)
        )
        try? viewportState.setContentBounds(bounds)
        scheduleScenePreparation()
    }

    private func synchronizeViewportDocumentBoundary(_ document: CanonicalDocument) {
        if case .committing = insertionSession.phase {
            // The synchronous transaction owns this revision transition.
        } else if let identity = insertionSession.identity,
                  identity.documentID != document.id || identity.revision != document.revision {
            cancelInsertion(resetTool: true)
        }
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
        pendingSelectionAfterInsertion = nil
        canvasRendererFailure = nil
        viewportFailure = nil
        lastViewportAnnouncement = "Canvas viewport reset for the opened document"
        announcementPoster.post(lastViewportAnnouncement)
        scheduleScenePreparation()
    }

    private func scheduleScenePreparation() {
        preparationTask?.cancel()
        let activeNodes = documentSession.document.pages.first(where: { $0.id == effectiveSelectedPageID })?.nodes ?? []
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
        let activeNodes = documentSession.document.pages.first(where: { $0.id == effectiveSelectedPageID })?.nodes ?? []
        let objects = activeNodes.enumerated().map { index, node in
            let column = index % 10
            let row = index / 10
            let fallback = WorldRect(
                origin: WorldPoint(x: 48 + Double(column * 120), y: 48 + Double(row * 88)),
                size: WorldSize(width: 104, height: 68)
            )
            let frame = node.insertionGeometry?.frame ?? fallback
            let style: CanvasPaintStyle = switch node.kind {
            case .frame: node.parent == .page(effectiveSelectedPageID ?? PageID()) ? .page : .container
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
                plainText: node.kind == .text ? node.insertionStringProperty("content.text") : nil
            )
        }
        guard !objects.isEmpty else { return }
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
            page.nodes.map { node -> SelectionTargetSnapshot in
                let object = rendered[node.id]
                defer { fallbackOrder += 1 }
                let parentID: NodeID? = if case .node(let id) = node.parent { id } else { nil }
                return SelectionTargetSnapshot(
                    id: node.id,
                    pageID: page.id,
                    parentID: parentID,
                    name: node.name,
                    frame: object?.frame ?? viewportState.contentBounds,
                    clipRect: object?.clipRect,
                    paintOrder: object?.paintOrder ?? fallbackOrder,
                    isVisible: object?.isVisible == true,
                    isLocked: node.selectionBooleanProperty("locked"),
                    isAvailable: object != nil
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
