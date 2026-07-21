import Combine
import SwiftUI

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
    static func order(pageIDs: [PageID]) -> [ShellFocus] {
        [
            .navigatorPages, .navigatorLayers,
        ] + pageIDs.map(ShellFocus.navigatorPage) + [
            .viewportPreset, .viewportZoomOut, .viewportZoomIn,
            .viewportReset, .viewportFit, .viewportCanvas,
            .inspectorLayout, .inspectorStyle, .inspectorAdvanced, .inspectorAccessibility,
        ]
    }

    static func adjacent(
        to current: ShellFocus?,
        direction: ShellFocusDirection,
        pageIDs: [PageID]
    ) -> ShellFocus? {
        let values = order(pageIDs: pageIDs)
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
        guard composition.value(after: "-SiteForgeWindowSize") == "minimum" else { return nil }
        return minimumWindowSize
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
    @Published private(set) var viewportFailure: CanvasViewportError?
    @Published private(set) var lastViewportAnnouncement = "Canvas viewport at 100 percent"
    @Published private(set) var canvasInteractionCount = 0
    @Published var isPreviewPresented = false
    let documentSession: DocumentSession
    let lifecycle: DocumentLifecycleController
    private var documentSessionObservation: AnyCancellable?
    private let viewportRegistry = CanvasViewportCommandRegistry()
    private let viewportPreparer: CanvasViewportScenePreparer
    let viewportDiagnostics: CanvasViewportDiagnostics
    private let announcementPoster: AccessibilityAnnouncementPoster
    private var viewportDocumentID: DocumentID
    private var preparationTask: Task<Void, Never>?

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
        selectedTool = tool
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
        selectedPageID = pageID
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

    func undo() {
        try? documentSession.undo()
    }

    func redo() {
        try? documentSession.redo()
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
        viewportFailure = nil
        lastViewportAnnouncement = "Canvas viewport reset for the opened document"
        announcementPoster.post(lastViewportAnnouncement)
        scheduleScenePreparation()
    }

    private func scheduleScenePreparation() {
        preparationTask?.cancel()
        let objects = documentSession.document.pages.flatMap(\.nodes).map {
            CanvasViewportSceneObject(id: $0.id, bounds: viewportState.contentBounds)
        }
        preparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await prepareViewportScene(objects: objects)
            } catch CanvasViewportError.cancelled {
                // Cancellation and stale completion are deliberately state neutral.
            } catch CanvasViewportError.staleResult {
                // A newer generation owns adoption.
            } catch let error as CanvasViewportError {
                viewportFailure = error
            } catch {}
        }
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
