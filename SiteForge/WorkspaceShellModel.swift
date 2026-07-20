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
    ]

    @Published var selectedTool: CanvasTool = .select
    @Published var navigatorTab: NavigatorTab = .pages
    @Published var selectedPageID: PageID?
    @Published var inspectorTab: InspectorTab = .layout
    @Published var viewportPreset: ViewportPreset = .desktop
    @Published private(set) var zoomPercent = 100
    @Published private(set) var canvasInteractionCount = 0
    @Published var isPreviewPresented = false
    let documentSession: DocumentSession
    let lifecycle: DocumentLifecycleController
    private var documentSessionObservation: AnyCancellable?

    init(
        documentSession: DocumentSession = DocumentSession(),
        lifecycle: DocumentLifecycleController? = nil
    ) {
        self.documentSession = documentSession
        selectedPageID = documentSession.document.pages.first?.id
        let lifecycle = lifecycle ?? DocumentLifecycleController(session: documentSession)
        precondition(lifecycle.session === documentSession, "Workspace state and lifecycle must own the same session")
        self.lifecycle = lifecycle
        documentSessionObservation = documentSession.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
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

    func adjustZoom(by delta: Int) {
        zoomPercent = min(200, max(25, zoomPercent + delta))
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
}
