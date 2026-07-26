import SwiftUI
import AppKit
import QuartzCore

struct WorkspaceShellView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var focusedControl: ShellFocus?
    @StateObject private var tabRouter = WorkspaceWindowTabRouter()

    var body: some View {
        VStack(spacing: 0) {
            if state.lifecycle.recoveryCandidate != nil {
                RecoveryCandidateBar(controller: state.lifecycle)
            }
            HSplitView {
                NavigatorView(state: state, focus: $focusedControl)
                    .frame(
                        minWidth: WorkspaceMetrics.navigatorWidth.lowerBound,
                        idealWidth: 240,
                        maxWidth: WorkspaceMetrics.navigatorWidth.upperBound
                    )

                CanvasPlaceholderView(state: state, focus: $focusedControl, tabRouter: tabRouter)
                    .frame(minWidth: WorkspaceMetrics.minimumCanvasWidth, maxWidth: .infinity)

                InspectorView(state: state, focus: $focusedControl)
                    .frame(
                        minWidth: WorkspaceMetrics.inspectorWidth.lowerBound,
                        idealWidth: 300,
                        maxWidth: WorkspaceMetrics.inspectorWidth.upperBound
                    )
            }

            Divider()
            StatusBarView(state: state)
        }
        .frame(
            minWidth: WorkspaceMetrics.minimumWindowSize.width,
            minHeight: WorkspaceMetrics.minimumWindowSize.height
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SiteForge workspace")
        .accessibilityIdentifier("workspace.shell")
        .background {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                WindowCloseGuard(controller: state.lifecycle).frame(width: 0, height: 0)
                WorkspaceWindowConfigurator().frame(width: 0, height: 0)
                WorkspaceWindowTabRouterInstaller(
                    router: tabRouter,
                    focus: $focusedControl,
                    pageIDs: state.pages.map(\.id),
                    layerIDs: state.navigatorTab == .layers ? state.layerTargets.map(\.id) : []
                )
                .frame(width: 0, height: 0)
                if WorkspaceFocusDiagnosticsPolicy.isEnabled {
                    WorkspaceFocusDiagnosticsProbe(router: tabRouter)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .navigationTitle(state.lifecycle.title)
        .toolbar {
            WorkspaceToolbar(state: state)
        }
        .sheet(isPresented: $state.isPreviewPresented) {
            PreviewPlaceholderView {
                focusedControl = .navigatorPages
            }
        }
        .sheet(isPresented: Binding(
            get: { state.lifecycle.isRecoveryDetailsPresented },
            set: { state.lifecycle.isRecoveryDetailsPresented = $0 }
        )) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recovery Details").font(.title2)
                Text(state.lifecycle.recoveryCandidate?.summary ?? "No valid recovery candidate is available.")
                Text("Project content and complete file paths are excluded from these details.")
                    .foregroundStyle(.secondary)
                Button("Done") { state.lifecycle.isRecoveryDetailsPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("recovery.details.done")
            }
            .padding(24).frame(minWidth: 420)
            .accessibilityIdentifier("recovery.details")
        }
        .onExitCommand {
            state.performEscape()
        }
    }
}

private struct RecoveryCandidateBar: View {
    @ObservedObject var controller: DocumentLifecycleController

    var body: some View {
        HStack(spacing: 12) {
            Label("A newer valid recovery candidate is available.", systemImage: "clock.arrow.circlepath")
            Spacer()
            Button("Inspect Details") { controller.isRecoveryDetailsPresented = true }
                .accessibilityIdentifier("recovery.inspect")
            Button("Discard") { Task { await controller.discardRecovery() } }
                .accessibilityIdentifier("recovery.discard")
            Button("Restore") { Task { _ = await controller.requestRestoreRecovery() } }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("recovery.restore")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .workspaceChrome(.recoveryBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery.candidate")
    }
}

private struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var controller: DocumentLifecycleController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.controller = controller
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var controller: DocumentLifecycleController
        weak var priorDelegate: NSWindowDelegate?
        weak var window: NSWindow?
        init(controller: DocumentLifecycleController) { self.controller = controller }
        func attach(to candidate: NSWindow?) {
            guard let candidate, candidate !== window else { return }
            window = candidate
            priorDelegate = candidate.delegate
            candidate.delegate = self
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if controller.consumeCloseAuthorization() {
                return priorDelegate?.windowShouldClose?(sender) ?? true
            }
            Task { @MainActor [weak self, weak sender] in
                guard let self, let sender else { return }
                if await controller.requestCloseTransition() == .completed {
                    controller.closeAfterAuthorization(sender)
                }
            }
            return false
        }
    }
}

private struct WorkspaceToolbar: ToolbarContent {
    @ObservedObject var state: WorkspaceShellState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    state.selectTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                        .symbolVariant(state.selectedTool == tool ? .fill : .none)
                }
                .help("\(tool.title) tool (\(tool.shortcut.character.uppercased()))")
                .accessibilityIdentifier("toolbar.tool.\(tool.rawValue)")
                .accessibilityValue(state.selectedTool == tool ? "Selected" : "Not selected")
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                state.undo()
            }
                .disabled(!state.canUndo)
                .help(state.undoDisabledReason ?? "Undo the last document command")
                .accessibilityIdentifier("toolbar.undo")
                .accessibilityHint(state.undoDisabledReason ?? "Undo the last committed document command")

            Button("Redo", systemImage: "arrow.uturn.forward") {
                state.redo()
            }
                .disabled(!state.canRedo)
                .help(state.redoDisabledReason ?? "Redo the last undone document command")
                .accessibilityIdentifier("toolbar.redo")
                .accessibilityHint(state.redoDisabledReason ?? "Redo the last undone document command")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                state.isPreviewPresented = true
            } label: {
                Label("Preview", systemImage: "play.fill")
            }
            .help("Open a bounded preview placeholder")
            .accessibilityIdentifier("toolbar.preview")
        }
    }
}

private struct ShellTabBar<Tab: CaseIterable & Identifiable & RawRepresentable & Equatable>: View where Tab.RawValue == String, Tab.AllCases: RandomAccessCollection {
    let tabs: Tab.AllCases
    @Binding var selection: Tab
    let identifierPrefix: String
    let title: (Tab) -> String
    let focus: FocusState<ShellFocus?>.Binding
    let focusValue: (Tab) -> ShellFocus

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(title(tab))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    if selection == tab {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.accentColor.opacity(0.55))
                    }
                }
                .focusable()
                .focused(focus, equals: focusValue(tab))
                .accessibilityIdentifier("\(identifierPrefix).\(tab.rawValue)")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct NavigatorView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    var body: some View {
        VStack(spacing: 12) {
            ShellTabBar(
                tabs: NavigatorTab.allCases,
                selection: $state.navigatorTab,
                identifierPrefix: "navigator.tab",
                title: \NavigatorTab.title,
                focus: focus,
                focusValue: { $0 == .pages ? .navigatorPages : .navigatorLayers }
            )

            if state.navigatorTab == .pages {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(state.pages) { page in
                            NavigatorPageRow(
                                page: page,
                                isSelected: state.effectiveSelectedPageID == page.id,
                                state: state,
                                focus: focus
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityLabel("Pages navigator")
                .accessibilityIdentifier("navigator.pages.list")
            } else {
                if state.layerTargets.isEmpty {
                    ContentUnavailableView {
                        Label("No Selectable Layers", systemImage: "square.3.layers.3d")
                    } description: {
                        Text("The active page has no visible selectable objects.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("navigator.empty")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(state.layerTargets, id: \.id) { target in
                                NavigatorLayerRow(target: target, state: state, focus: focus)
                            }
                        }
                    }
                    .accessibilityLabel("Layers navigator")
                    .accessibilityIdentifier("navigator.layers.list")
                }
            }
        }
        .padding(10)
        .workspaceChrome(.navigator)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.navigator.rawValue)
    }
}

private struct NavigatorLayerRow: View {
    let target: SelectionTargetSnapshot
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    private var isSelected: Bool { state.selectionState.orderedIDs.contains(target.id) }
    private var isPrimary: Bool { state.selectionState.primaryID == target.id }

    var body: some View {
        Button {
            let flags = NSEvent.modifierFlags
            let modifier: SelectionPointerModifier = flags.contains(.command)
                ? .toggle : flags.contains(.shift) ? .add : .replace
            state.selectLayer(target.id, modifier: modifier)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: target.isLocked ? "lock.fill" : "square.dashed")
                    .frame(width: 16)
                Text(target.name).lineLimit(1)
                Spacer(minLength: 4)
                if isPrimary { Text("Primary").font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .focusable()
        .focused(focus, equals: .navigatorLayer(target.id))
        .onMoveCommand { direction in
            if direction == .down { state.performSelectionCommand(.next, provenance: .keyboard) }
            if direction == .up { state.performSelectionCommand(.previous, provenance: .keyboard) }
        }
        .accessibilityLabel(target.name)
        .accessibilityValue("\(target.isLocked ? "Locked; " : "")\(isPrimary ? "Primary selection" : isSelected ? "Selected" : "Not selected")")
        .accessibilityHint("Press Return to select. Use Up and Down Arrow to traverse objects.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("navigator.layer.\(target.id.description)")
    }
}

private struct NavigatorPageRow: View {
    let page: DocumentPage
    let isSelected: Bool
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    var body: some View {
        Button {
            state.selectPage(page.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: page.role == .home ? "house" : "doc")
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(page.name).lineLimit(1)
                    Text(page.route.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if page.role == .notFound {
                    Text("404").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .focusable()
        .focused(focus, equals: .navigatorPage(page.id))
        .onMoveCommand { direction in
            let offset = direction == .down ? 1 : direction == .up ? -1 : 0
            guard offset != 0, let destination = state.adjacentPage(to: page.id, offset: offset) else {
                return
            }
            state.selectPage(destination)
            focus.wrappedValue = .navigatorPage(destination)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.name), route \(page.route.rawValue)")
        .accessibilityValue("\(NavigatorPageAccessibility.roleValue(for: page.role)); \(isSelected ? "Selected" : "Not selected")")
        .accessibilityHint("Use Up and Down Arrow to navigate pages")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(NavigatorPageAccessibility.identifier(for: page.id))
    }
}

private struct CanvasPlaceholderView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding
    let tabRouter: WorkspaceWindowTabRouter

    var body: some View {
        VStack(spacing: 0) {
            ViewportControlsView(state: state, focus: focus, tabRouter: tabRouter)
            Divider()

            GeometryReader { geometry in
                ZStack {
                    NativeCanvasViewport(
                        state: state,
                        isKeyboardFocused: focus.wrappedValue == .viewportCanvas,
                        onTabTraversal: { direction in
                            let next = ShellFocusTraversal.adjacent(
                                to: .viewportCanvas,
                                direction: direction,
                                pageIDs: state.pages.map(\.id),
                                layerIDs: state.navigatorTab == .layers ? state.layerTargets.map(\.id) : []
                            )
                            DispatchQueue.main.async {
                                focus.wrappedValue = next
                            }
                        }
                    )
                        .focusable()
                        .focused(focus, equals: .viewportCanvas)
                        .contextMenu {
                            Button("Insert Frame at Center") {
                                state.performDefaultInsertion(.frame, provenance: .contextualMenu)
                            }
                            .disabled(!state.insertionAvailability(.frame).isEnabled)
                            Button("Insert Text at Center") {
                                state.performDefaultInsertion(.text, provenance: .contextualMenu)
                            }
                            .disabled(!state.insertionAvailability(.text).isEnabled)
                            Divider()
                            Button("Select Next Object") {
                                state.performSelectionCommand(.next, provenance: .contextualMenu)
                            }
                            Button("Select Previous Object") {
                                state.performSelectionCommand(.previous, provenance: .contextualMenu)
                            }
                            Divider()
                            Button("Clear Selection") {
                                state.performSelectionCommand(.clear, provenance: .contextualMenu)
                            }
                            .disabled(state.selectionState.isEmpty)
                        }

                    if state.canvasRenderPlan == nil {
                        ProgressView("Preparing canvas…")
                            .controlSize(.small)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.viewport.surface")
                .onAppear {
                    state.resizeViewport(
                        to: ViewportSize(width: geometry.size.width, height: geometry.size.height),
                        pixelRatio: Double(NSScreen.main?.backingScaleFactor ?? 2)
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.canvas.rawValue)
    }
}

private struct ViewportControlsView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding
    let tabRouter: WorkspaceWindowTabRouter
    @State private var focusSceneID = ViewportPresetFocusSceneID()

    var body: some View {
        HStack(spacing: 10) {
            Label("Viewport", systemImage: "display")
                .font(.caption.weight(.semibold))

            NativeViewportPresetControl(
                selection: $state.viewportPreset,
                sceneID: focusSceneID,
                tabRouter: tabRouter,
                isKeyboardFocusRequested: focus.wrappedValue == .viewportPreset,
                onNativeFocusChange: { isFocused in
                    if isFocused {
                        focus.wrappedValue = .viewportPreset
                    } else if focus.wrappedValue == .viewportPreset {
                        focus.wrappedValue = nil
                    }
                }
            )
            .frame(width: 110)
            .focusable()
            .focused(focus, equals: .viewportPreset)

            Text("\(state.viewportPreset.width) px")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("canvas.viewport.width")

            Spacer(minLength: 8)

            Button("Zoom out", systemImage: "minus") {
                state.performViewportCommand(CanvasViewportCommand(.zoomOut))
            }
            .labelStyle(.iconOnly)
            .disabled(state.zoomPercent == 25)
            .focusable()
            .focused(focus, equals: .viewportZoomOut)
            .accessibilityIdentifier("canvas.zoom.out")

            Text("\(state.zoomPercent)%")
                .monospacedDigit()
                .frame(minWidth: 42)
                .accessibilityIdentifier("canvas.zoom.value")

            Button("Zoom in", systemImage: "plus") {
                state.performViewportCommand(CanvasViewportCommand(.zoomIn))
            }
            .labelStyle(.iconOnly)
            .disabled(state.viewportState.zoom == .maximum)
            .focusable()
            .focused(focus, equals: .viewportZoomIn)
            .accessibilityIdentifier("canvas.zoom.in")

            Button("Actual size", systemImage: "1.magnifyingglass") {
                state.performViewportCommand(CanvasViewportCommand(.actualSize))
            }
            .labelStyle(.iconOnly)
            .focusable()
            .focused(focus, equals: .viewportReset)
            .accessibilityIdentifier("canvas.zoom.reset")

            Button("Fit document", systemImage: "arrow.up.left.and.arrow.down.right") {
                state.performViewportCommand(CanvasViewportCommand(.fitDocument))
            }
            .labelStyle(.iconOnly)
            .focusable()
            .focused(focus, equals: .viewportFit)
            .accessibilityIdentifier("canvas.zoom.fit")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .workspaceChrome(.viewportControls)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.viewport.controls")
    }
}

struct ViewportPresetFocusSceneID: Hashable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct ViewportPresetFocusRequest: Hashable {
    let sceneID: ViewportPresetFocusSceneID
    let requestID: UUID

    init(sceneID: ViewportPresetFocusSceneID, requestID: UUID = UUID()) {
        self.sceneID = sceneID
        self.requestID = requestID
    }
}

struct ViewportPresetWindowIdentity: Hashable {
    private let rawValue: ObjectIdentifier

    init(window: NSWindow) {
        rawValue = ObjectIdentifier(window)
    }
}

enum ViewportPresetFocusDecision: Equatable {
    case adopt
    case alreadyFocused
    case ignoreStaleRequest
    case ignoreWrongScene
    case ignoreWrongWindow
    case ignoreRelinquishedRequest
}

struct ViewportPresetFocusGate {
    let sceneID: ViewportPresetFocusSceneID
    private(set) var activeRequest: ViewportPresetFocusRequest?
    private(set) var expectedWindow: ViewportPresetWindowIdentity?
    private(set) var adoptedRequest: ViewportPresetFocusRequest?
    private(set) var relinquishedRequest: ViewportPresetFocusRequest?

    mutating func activate(
        _ request: ViewportPresetFocusRequest,
        in window: ViewportPresetWindowIdentity
    ) {
        activeRequest = request
        expectedWindow = window
        adoptedRequest = nil
        relinquishedRequest = nil
    }

    mutating func cancel() {
        activeRequest = nil
        expectedWindow = nil
        adoptedRequest = nil
        relinquishedRequest = nil
    }

    func decision(
        for request: ViewportPresetFocusRequest,
        in window: ViewportPresetWindowIdentity,
        isFirstResponder: Bool
    ) -> ViewportPresetFocusDecision {
        guard request.sceneID == sceneID else { return .ignoreWrongScene }
        guard request == activeRequest else { return .ignoreStaleRequest }
        guard window == expectedWindow else { return .ignoreWrongWindow }
        if isFirstResponder { return .alreadyFocused }
        if request == relinquishedRequest { return .ignoreRelinquishedRequest }
        return .adopt
    }

    mutating func markAdopted(_ request: ViewportPresetFocusRequest) {
        guard request == activeRequest else { return }
        adoptedRequest = request
    }

    mutating func markRelinquished(_ request: ViewportPresetFocusRequest) {
        guard request == adoptedRequest else { return }
        relinquishedRequest = request
    }
}

enum ViewportPresetControlContract {
    static let accessibilityIdentifier = "canvas.viewport.preset"
    static let accessibilityLabel = "Viewport preset"

    static func index(for preset: ViewportPreset) -> Int {
        ViewportPreset.allCases.firstIndex(of: preset) ?? 0
    }

    static func preset(at index: Int) -> ViewportPreset? {
        guard ViewportPreset.allCases.indices.contains(index) else { return nil }
        return ViewportPreset.allCases[index]
    }

    static func accessibilityValue(for preset: ViewportPreset) -> String {
        preset.title
    }
}

struct WorkspaceTabRouterWindowIdentity: Hashable {
    private let rawValue: ObjectIdentifier

    init(window: NSWindow) {
        rawValue = ObjectIdentifier(window)
    }
}

struct WorkspaceTabRouterLifecycle {
    private(set) var activeWindow: WorkspaceTabRouterWindowIdentity?
    private(set) var generation: UInt64 = 0

    mutating func bind(to window: WorkspaceTabRouterWindowIdentity) {
        guard activeWindow != window else { return }
        activeWindow = window
        generation &+= 1
    }

    mutating func unbind(from window: WorkspaceTabRouterWindowIdentity) {
        guard activeWindow == window else { return }
        activeWindow = nil
        generation &+= 1
    }

    func accepts(_ window: WorkspaceTabRouterWindowIdentity, generation: UInt64) -> Bool {
        activeWindow == window && self.generation == generation
    }
}

enum WorkspaceFocusDiagnosticsPolicy {
    static var isEnabled: Bool {
        DebugTestComposition.current().boolValue(after: "-SiteForgeUITestMode") == true
    }
}

@MainActor
final class WorkspaceWindowTabRouter: ObservableObject {
    @Published private(set) var diagnosticSnapshot =
        "logical=none; responder=none; window=detached; route=none"

    private weak var window: NSWindow?
    private weak var presetControl: FocusableViewportPresetPopUpButton?
    private var eventMonitor: Any?
    private var lifecycle = WorkspaceTabRouterLifecycle()
    private var pageIDs: [PageID] = []
    private var layerIDs: [NodeID] = []
    private var currentFocus: () -> ShellFocus? = { nil }
    private var setFocus: (ShellFocus?) -> Void = { _ in }

    func configure(
        focus: FocusState<ShellFocus?>.Binding,
        pageIDs: [PageID],
        layerIDs: [NodeID]
    ) {
        self.pageIDs = pageIDs
        self.layerIDs = layerIDs
        currentFocus = { focus.wrappedValue }
        setFocus = { focus.wrappedValue = $0 }
    }

    func bind(to candidate: NSWindow?) {
        guard let candidate else { return }
        if window === candidate, eventMonitor != nil { return }
        detachMonitor()
        window = candidate
        lifecycle.bind(to: WorkspaceTabRouterWindowIdentity(window: candidate))
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.route(event) ?? event
        }
        updateDiagnostics(outcome: "attached")
    }

    func unbind(from candidate: NSWindow?) {
        guard let candidate, window === candidate else { return }
        lifecycle.unbind(from: WorkspaceTabRouterWindowIdentity(window: candidate))
        detachMonitor()
        window = nil
        presetControl = nil
        diagnosticSnapshot = "logical=none; responder=none; window=detached; route=none"
    }

    fileprivate func registerPresetControl(_ control: FocusableViewportPresetPopUpButton) {
        presetControl = control
        updateDiagnostics(outcome: "preset-attached")
    }

    fileprivate func unregisterPresetControl(_ control: FocusableViewportPresetPopUpButton) {
        guard presetControl === control else { return }
        presetControl = nil
        updateDiagnostics(outcome: "preset-detached")
    }

    private func route(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 48 else { return event }
        let unsupportedModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard unsupportedModifiers.isEmpty else { return event }
        guard let window else { return event }

        let windowIdentity = WorkspaceTabRouterWindowIdentity(window: window)
        let generation = lifecycle.generation
        let direction: ShellFocusDirection = event.modifierFlags.contains(.shift) ? .reverse : .forward
        let logicalFocus = window.firstResponder === presetControl ? .viewportPreset : currentFocus()
        let context = WorkspaceTabRoutingContext(
            isWorkspaceWindowEvent: event.window === window
                && lifecycle.accepts(windowIdentity, generation: generation),
            isKeyWindow: window.isKeyWindow && NSApp.keyWindow === window,
            hasAttachedSheet: window.attachedSheet != nil,
            isTextEditing: Self.isTextEditing(window.firstResponder),
            hasTransientPresentation: NSApp.mainMenu?.highlightedItem != nil
        )
        let decision = WorkspaceTabRoutingPolicy.decision(
            from: logicalFocus,
            direction: direction,
            pageIDs: pageIDs,
            layerIDs: layerIDs,
            context: context
        )
        guard case let .route(target) = decision else {
            updateDiagnostics(
                logicalFocus: logicalFocus,
                outcome: "pass-\(String(describing: decision))"
            )
            return event
        }

        if target == .viewportPreset {
            guard let presetControl, presetControl.window === window else {
                updateDiagnostics(logicalFocus: logicalFocus, outcome: "preset-unavailable")
                return event
            }
            guard lifecycle.accepts(windowIdentity, generation: generation),
                  window.makeFirstResponder(presetControl) else {
                updateDiagnostics(logicalFocus: logicalFocus, outcome: "preset-rejected")
                return event
            }
            setFocus(.viewportPreset)
            updateDiagnostics(logicalFocus: .viewportPreset, outcome: "routed-\(target.diagnosticIdentifier)")
            return nil
        }

        if window.firstResponder === presetControl {
            _ = window.makeFirstResponder(nil)
        }
        guard lifecycle.accepts(windowIdentity, generation: generation) else {
            updateDiagnostics(logicalFocus: logicalFocus, outcome: "stale-window")
            return event
        }
        setFocus(target)
        updateDiagnostics(logicalFocus: target, outcome: "routed-\(target.diagnosticIdentifier)")
        return nil
    }

    private func updateDiagnostics(
        logicalFocus: ShellFocus? = nil,
        outcome: String
    ) {
        let logical = (logicalFocus ?? currentFocus())?.diagnosticIdentifier ?? "none"
        let responder = window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
        let windowState: String
        if let window {
            windowState = "key=\(window.isKeyWindow);main=\(window.isMainWindow);sheet=\(window.attachedSheet != nil)"
        } else {
            windowState = "detached"
        }
        diagnosticSnapshot =
            "logical=\(logical); responder=\(responder); window=\(windowState); route=\(outcome)"
    }

    private static func isTextEditing(_ responder: NSResponder?) -> Bool {
        responder is NSTextView || responder is NSTextField
    }

    private func detachMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

private struct WorkspaceWindowTabRouterInstaller: NSViewRepresentable {
    let router: WorkspaceWindowTabRouter
    let focus: FocusState<ShellFocus?>.Binding
    let pageIDs: [PageID]
    let layerIDs: [NodeID]

    func makeNSView(context: Context) -> WorkspaceWindowTabRouterHostView {
        let view = WorkspaceWindowTabRouterHostView()
        view.router = router
        router.configure(focus: focus, pageIDs: pageIDs, layerIDs: layerIDs)
        return view
    }

    func updateNSView(_ view: WorkspaceWindowTabRouterHostView, context: Context) {
        view.router = router
        router.configure(focus: focus, pageIDs: pageIDs, layerIDs: layerIDs)
        router.bind(to: view.window)
    }

    static func dismantleNSView(
        _ view: WorkspaceWindowTabRouterHostView,
        coordinator: Void
    ) {
        view.detach()
    }
}

@MainActor
private final class WorkspaceWindowTabRouterHostView: NSView {
    weak var router: WorkspaceWindowTabRouter?
    private weak var boundWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let boundWindow, boundWindow !== window {
            router?.unbind(from: boundWindow)
        }
        boundWindow = window
        router?.bind(to: window)
    }

    func detach() {
        if let boundWindow {
            router?.unbind(from: boundWindow)
        }
        boundWindow = nil
        router = nil
    }
}

private struct WorkspaceFocusDiagnosticsProbe: NSViewRepresentable {
    @ObservedObject var router: WorkspaceWindowTabRouter

    func makeNSView(context: Context) -> WorkspaceFocusDiagnosticsView {
        let view = WorkspaceFocusDiagnosticsView()
        view.setAccessibilityIdentifier("workspace.focus.diagnostics")
        view.diagnosticValue = router.diagnosticSnapshot
        return view
    }

    func updateNSView(_ view: WorkspaceFocusDiagnosticsView, context: Context) {
        view.diagnosticValue = router.diagnosticSnapshot
    }
}

private final class WorkspaceFocusDiagnosticsView: NSView {
    var diagnosticValue = "" {
        didSet {
            setAccessibilityValue(diagnosticValue)
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Workspace focus diagnostics" }
    override func accessibilityValue() -> Any? { diagnosticValue }
}

private struct NativeViewportPresetControl: NSViewRepresentable {
    @Binding var selection: ViewportPreset
    let sceneID: ViewportPresetFocusSceneID
    let tabRouter: WorkspaceWindowTabRouter
    let isKeyboardFocusRequested: Bool
    let onNativeFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sceneID: sceneID)
    }

    func makeNSView(context: Context) -> FocusableViewportPresetPopUpButton {
        let button = FocusableViewportPresetPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: ViewportPreset.allCases.map(\.title))
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.controlSize = .small
        button.focusRingType = .default
        button.setAccessibilityIdentifier(ViewportPresetControlContract.accessibilityIdentifier)
        button.setAccessibilityLabel(ViewportPresetControlContract.accessibilityLabel)
        context.coordinator.attach(button)
        context.coordinator.tabRouter = tabRouter
        tabRouter.registerPresetControl(button)
        return button
    }

    func updateNSView(_ button: FocusableViewportPresetPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.onNativeFocusChange = onNativeFocusChange
        context.coordinator.tabRouter = tabRouter
        let selectedIndex = ViewportPresetControlContract.index(for: selection)
        if button.indexOfSelectedItem != selectedIndex {
            button.selectItem(at: selectedIndex)
        }
        button.setAccessibilityValue(ViewportPresetControlContract.accessibilityValue(for: selection))
        context.coordinator.synchronizeFocus(
            requested: isKeyboardFocusRequested,
            for: button
        )
    }

    static func dismantleNSView(
        _ button: FocusableViewportPresetPopUpButton,
        coordinator: Coordinator
    ) {
        coordinator.tabRouter?.unregisterPresetControl(button)
        coordinator.tabRouter = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        private let sceneID: ViewportPresetFocusSceneID
        private var gate: ViewportPresetFocusGate
        private var currentRequest: ViewportPresetFocusRequest?
        private var wasFocusRequested = false
        private var isAdoptingRequestedFocus = false
        var selection: Binding<ViewportPreset>?
        var onNativeFocusChange: ((Bool) -> Void)?
        weak var tabRouter: WorkspaceWindowTabRouter?

        init(sceneID: ViewportPresetFocusSceneID) {
            self.sceneID = sceneID
            gate = ViewportPresetFocusGate(sceneID: sceneID)
        }

        func attach(_ button: FocusableViewportPresetPopUpButton) {
            button.onFocusChange = { [weak self] isFocused in
                guard let self else { return }
                if !isFocused, let request = self.currentRequest {
                    self.gate.markRelinquished(request)
                }
                if !self.isAdoptingRequestedFocus {
                    self.onNativeFocusChange?(isFocused)
                }
            }
            button.onWindowChange = { [weak self, weak button] in
                guard let self, let button else { return }
                self.bindRequestAndAdopt(for: button)
            }
        }

        func synchronizeFocus(
            requested: Bool,
            for button: FocusableViewportPresetPopUpButton
        ) {
            if requested, !wasFocusRequested {
                currentRequest = ViewportPresetFocusRequest(sceneID: sceneID)
            } else if !requested, wasFocusRequested {
                currentRequest = nil
                gate.cancel()
            }
            wasFocusRequested = requested
            guard requested else { return }
            bindRequestAndAdopt(for: button)
        }

        private func bindRequestAndAdopt(
            for button: FocusableViewportPresetPopUpButton
        ) {
            guard let request = currentRequest, let window = button.window else { return }
            let windowIdentity = ViewportPresetWindowIdentity(window: window)
            if gate.activeRequest == nil {
                gate.activate(request, in: windowIdentity)
            }
            let decision = gate.decision(
                for: request,
                in: windowIdentity,
                isFirstResponder: window.firstResponder === button
            )
            if decision == .alreadyFocused {
                gate.markAdopted(request)
                return
            }
            guard decision == .adopt else { return }
            isAdoptingRequestedFocus = true
            defer { isAdoptingRequestedFocus = false }
            if window.makeFirstResponder(button) {
                gate.markAdopted(request)
            }
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let preset = ViewportPresetControlContract.preset(at: sender.indexOfSelectedItem) else {
                return
            }
            selection?.wrappedValue = preset
            sender.setAccessibilityValue(ViewportPresetControlContract.accessibilityValue(for: preset))
        }
    }
}

private final class FocusableViewportPresetPopUpButton: NSPopUpButton {
    var onFocusChange: ((Bool) -> Void)?
    var onWindowChange: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            onFocusChange?(false)
        }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        _ = window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 125 || event.keyCode == 126 {
            guard numberOfItems > 0 else { return }
            let offset = event.keyCode == 125 ? 1 : -1
            let destination = max(0, min(numberOfItems - 1, indexOfSelectedItem + offset))
            if destination != indexOfSelectedItem {
                selectItem(at: destination)
                sendAction(action, to: target)
            }
            return
        }
        super.keyDown(with: event)
    }
}

private struct InspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    var body: some View {
        VStack(spacing: 12) {
            ShellTabBar(
                tabs: InspectorTab.allCases,
                selection: $state.inspectorTab,
                identifierPrefix: "inspector.tab",
                title: \InspectorTab.title,
                focus: focus,
                focusValue: {
                    switch $0 {
                    case .layout: .inspectorLayout
                    case .style: .inspectorStyle
                    case .advanced: .inspectorAdvanced
                    case .accessibility: .inspectorAccessibility
                    }
                }
            )

            if state.selectionState.isEmpty {
                ContentUnavailableView(
                    "Nothing Selected",
                    systemImage: "slider.horizontal.3",
                    description: Text("Select an object to inspect its \(state.inspectorTab.title.lowercased()) summary.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("inspector.empty")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label(state.selectionSummary, systemImage: state.selectionState.count > 1 ? "square.stack.3d.up" : "selection.pin.in.out")
                        .font(.headline)
                    Text(state.selectionState.count == 1 ? "Primary selection" : "Multiple selection")
                        .foregroundStyle(.secondary)
                    if state.layerTargets.first(where: { $0.id == state.selectionState.primaryID })?.isLocked == true {
                        Label("Locked — inspection only", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                    Text("Editable properties are intentionally deferred to a later authoring slice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Inspector selection summary")
                .accessibilityValue(state.selectionSummary)
                .accessibilityIdentifier("inspector.selection.summary")
            }
        }
        .padding(10)
        .workspaceChrome(.inspector)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.inspector.rawValue)
    }
}

private struct StatusBarView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        HStack(spacing: 14) {
            Label("Zoom \(state.zoomPercent)%", systemImage: "magnifyingglass")
                .accessibilityValue(state.viewportAccessibilityValue)
                .accessibilityIdentifier("status.zoom")
            Divider().frame(height: 14)
            Label(state.viewportPreset.title, systemImage: "rectangle.split.3x1")
                .accessibilityLabel("Active breakpoint: \(state.viewportPreset.title)")
                .accessibilityIdentifier("status.breakpoint")
            Divider().frame(height: 14)
            Label(state.selectionState.isEmpty ? "No selection" : state.selectionState.count == 1 ? state.selectionSummary : "\(state.selectionState.count) selected", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .accessibilityLabel("Selection path: \(state.selectionPath)")
                .accessibilityIdentifier("status.selectionPath")
            if state.selectedTool == .frame || state.selectedTool == .text {
                Divider().frame(height: 14)
                Label(state.insertionStatus, systemImage: "plus.square.dashed")
                    .accessibilityLabel(state.insertionStatus)
                    .accessibilityIdentifier("status.insertion")
            }
            Spacer()
            if state.lifecycle.phase == .saving || state.lifecycle.phase == .autosaving {
                ProgressView().controlSize(.small).accessibilityLabel(state.lifecycle.statusText)
            }
            Label(state.lifecycle.statusText,
                  systemImage: state.lifecycle.phase == .failed || state.lifecycle.phase == .conflicted ? "exclamationmark.triangle.fill" : "doc.badge.clock")
                .foregroundStyle(state.lifecycle.phase == .failed || state.lifecycle.phase == .conflicted ? .red : .secondary)
                .accessibilityLabel("Document status: \(state.lifecycle.statusText)")
                .accessibilityIdentifier("status.document")
            Divider().frame(height: 14)
            Text("Tool: \(state.selectedTool.title)")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("status.activeTool")
            Divider().frame(height: 14)
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Diagnostics status: Ready")
                .accessibilityIdentifier("status.diagnostics")
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .workspaceChrome(.statusBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.statusBar.rawValue)
    }
}

private struct PreviewPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 42))
                .accessibilityHidden(true)
            Text("Preview Placeholder")
                .font(.title2)
            Text("Live preview is intentionally deferred to a later milestone.")
                .foregroundStyle(.secondary)
            Button("Done") {
                dismiss()
                onDismiss()
            }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("preview.done")
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 240)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview.placeholder")
    }
}

struct SiteForgeCommands: Commands {
    @FocusedObject private var state: WorkspaceShellState?
    @FocusedObject private var launchExperience: LaunchExperienceController?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { launchExperience?.createBlankProject() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(launchExperience == nil)
            Button("Open…") { launchExperience?.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(launchExperience == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                guard let state else { return }
                if state.lifecycle.fileURL == nil { state.lifecycle.presentSavePanel() }
                else { Task { _ = await state.lifecycle.save() } }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(launchExperience?.isWorkspaceVisible != true || state?.lifecycle.canSave != true)
            Button("Save As…") { state?.lifecycle.presentSavePanel() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(launchExperience?.isWorkspaceVisible != true || state == nil)
            Button("Revert to Saved") {
                guard let state else { return }
                Task { _ = await state.lifecycle.requestRevert() }
            }
                .disabled(launchExperience?.isWorkspaceVisible != true || state?.lifecycle.canRevert != true)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                state?.undo()
            }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(launchExperience?.isWorkspaceVisible != true || state?.canUndo != true)
            Button("Redo") {
                state?.redo()
            }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(launchExperience?.isWorkspaceVisible != true || state?.canRedo != true)
        }

        CommandMenu("Tools") {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    state?.selectTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
                .keyboardShortcut(tool.shortcut, modifiers: [])
            }
            Divider()
            Button("Insert Frame at Center") {
                state?.performDefaultInsertion(.frame, provenance: .menu)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(state?.insertionAvailability(.frame).isEnabled != true)
            Button("Insert Text at Center") {
                state?.performDefaultInsertion(.text, provenance: .menu)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(state?.insertionAvailability(.text).isEnabled != true)
        }

        CommandMenu("Selection") {
            Button("Select Next Object") {
                state?.performSelectionCommand(.next, provenance: .menu)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(state?.selectionAvailability(.next).isEnabled != true)
            Button("Select Previous Object") {
                state?.performSelectionCommand(.previous, provenance: .menu)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(state?.selectionAvailability(.previous).isEnabled != true)
            Divider()
            Button("Clear Selection") {
                state?.performSelectionCommand(.clear, provenance: .menu)
            }
            .disabled(state?.selectionAvailability(.clear).isEnabled != true)
        }

        CommandMenu("Preview") {
            Button("Open Preview") {
                state?.isPreviewPresented = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(state == nil)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { state?.performViewportCommand(CanvasViewportCommand(.zoomIn)) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(state?.zoomPercent == CanvasZoom.maximum.percent)
            Button("Zoom Out") { state?.performViewportCommand(CanvasViewportCommand(.zoomOut)) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(state?.zoomPercent == CanvasZoom.minimum.percent)
            Button("Actual Size") { state?.performViewportCommand(CanvasViewportCommand(.actualSize)) }
                .keyboardShortcut("0", modifiers: .command)
            Button("Fit Document") { state?.performViewportCommand(CanvasViewportCommand(.fitDocument)) }
                .keyboardShortcut("1", modifiers: .command)
            Divider()
            Button("Pan Left") { state?.performViewportCommand(CanvasViewportCommand(.panLeft)) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button("Pan Right") { state?.performViewportCommand(CanvasViewportCommand(.panRight)) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
            Button("Pan Up") { state?.performViewportCommand(CanvasViewportCommand(.panUp)) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("Pan Down") { state?.performViewportCommand(CanvasViewportCommand(.panDown)) }
                .keyboardShortcut(.downArrow, modifiers: .option)
        }
    }
}

private struct NativeCanvasViewport: NSViewRepresentable {
    @ObservedObject var state: WorkspaceShellState
    let isKeyboardFocused: Bool
    let onTabTraversal: (ShellFocusDirection) -> Void

    func makeNSView(context: Context) -> NativeCanvasViewportView {
        let view = NativeCanvasViewportView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NativeCanvasViewportView, context: Context) {
        configure(view)
        view.viewportState = state.viewportState
        view.renderPlan = state.canvasRenderPlan
        view.selectionOverlayPlan = state.selectionOverlayPlan
        view.insertionPreviewOverlay = state.insertionPreviewOverlay
        view.accessibilityViewportValue = state.viewportAccessibilityValue
        view.needsDisplay = true
        let width = Double(view.bounds.width)
        let height = Double(view.bounds.height)
        let scale = Double(view.window?.backingScaleFactor ?? 2)
        if isKeyboardFocused, view.window?.firstResponder !== view {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        guard width > 0, height > 0 else { return }
        DispatchQueue.main.async {
            state.resizeViewport(to: ViewportSize(width: width, height: height), pixelRatio: scale)
        }
    }

    private func configure(_ view: NativeCanvasViewportView) {
        view.setAccessibilityIdentifier("canvas.interaction")
        view.viewportState = state.viewportState
        view.renderPlan = state.canvasRenderPlan
        view.selectionOverlayPlan = state.selectionOverlayPlan
        view.insertionPreviewOverlay = state.insertionPreviewOverlay
        view.onInteraction = { state.noteCanvasInteraction() }
        view.onPointerSelection = { point, modifier in state.selectCanvasPoint(point, modifier: modifier) }
        view.onPointerPreview = { point in state.previewInsertion(at: point) }
        view.onSelectNext = { state.performSelectionCommand(.next, provenance: .keyboard) }
        view.onSelectPrevious = { state.performSelectionCommand(.previous, provenance: .keyboard) }
        view.onClearSelection = { state.performSelectionCommand(.clear, provenance: .keyboard) }
        view.onEscape = { state.performEscape() }
        view.onInsertFrame = { state.performDefaultInsertion(.frame, provenance: .accessibility) }
        view.onInsertText = { state.performDefaultInsertion(.text, provenance: .accessibility) }
        view.onPan = { state.panViewport(by: $0) }
        view.onMagnify = { factor, anchor in state.magnify(by: factor, around: anchor) }
        view.onResize = { size, scale in state.resizeViewport(to: size, pixelRatio: scale) }
        view.onZoomIn = { state.performViewportCommand(CanvasViewportCommand(.zoomIn)) }
        view.onZoomOut = { state.performViewportCommand(CanvasViewportCommand(.zoomOut)) }
        view.onReset = { state.performViewportCommand(CanvasViewportCommand(.actualSize)) }
        view.onTabTraversal = onTabTraversal
    }
}

private final class NativeCanvasViewportView: NSView {
    var viewportState = try! CanvasViewportState() {
        didSet {
            applyCompositorTransformIfPossible()
            rebuildOverlay()
            if let renderPlan { rebuildAccessibility(renderPlan) }
        }
    }
    var renderPlan: CanvasRenderPlan? {
        didSet { adoptRenderPlan() }
    }
    var selectionOverlayPlan: SelectionOverlayPlan? {
        didSet {
            rebuildOverlay()
            if let renderPlan { rebuildAccessibility(renderPlan) }
        }
    }
    var insertionPreviewOverlay: CanvasEditorOverlay? {
        didSet { rebuildOverlay() }
    }
    var accessibilityViewportValue = "Zoom 100 percent"
    var onInteraction: (() -> Void)?
    var onPointerSelection: ((WorldPoint, SelectionPointerModifier) -> Void)?
    var onPointerPreview: ((WorldPoint) -> Void)?
    var onSelectNext: (() -> Void)?
    var onSelectPrevious: (() -> Void)?
    var onClearSelection: (() -> Void)?
    var onEscape: (() -> Void)?
    var onInsertFrame: (() -> Void)?
    var onInsertText: (() -> Void)?
    var onPan: ((ViewportVector) -> Void)?
    var onMagnify: ((Double, ViewportPoint) -> Void)?
    var onResize: ((ViewportSize, Double) -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onReset: (() -> Void)?
    var onTabTraversal: ((ShellFocusDirection) -> Void)?
    private let contentContainer = CALayer()
    private let overlayContainer = CALayer()
    private var rasterViewportState: CanvasViewportState?
    private var virtualAccessibilityElements: [NSAccessibilityElement] = []
    private var focusedAccessibilityObjectID: NodeID?
    private var pointerTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentContainer.name = "renderer.authored-content"
        overlayContainer.name = "renderer.editor-overlays"
        contentContainer.masksToBounds = true
        overlayContainer.masksToBounds = true
        layer?.addSublayer(contentContainer)
        layer?.addSublayer(overlayContainer)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Canvas viewport" }
    override func accessibilityValue() -> Any? {
        "\(accessibilityViewportValue); rendered objects \(renderPlan?.authoredObjects.count ?? 0)"
    }
    override func accessibilityChildren() -> [Any]? { virtualAccessibilityElements }
    override func accessibilityHelp() -> String? {
        "Scroll to pan. Pinch to zoom around the pointer. Use the View menu for keyboard controls."
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(name: "Zoom In") { [weak self] in self?.onZoomIn?(); return true },
            NSAccessibilityCustomAction(name: "Zoom Out") { [weak self] in self?.onZoomOut?(); return true },
            NSAccessibilityCustomAction(name: "Reset View") { [weak self] in self?.onReset?(); return true },
            NSAccessibilityCustomAction(name: "Select Next Object") { [weak self] in self?.onSelectNext?(); return true },
            NSAccessibilityCustomAction(name: "Select Previous Object") { [weak self] in self?.onSelectPrevious?(); return true },
            NSAccessibilityCustomAction(name: "Clear Selection") { [weak self] in self?.onClearSelection?(); return true },
            NSAccessibilityCustomAction(name: "Insert Frame at Center") { [weak self] in self?.onInsertFrame?(); return true },
            NSAccessibilityCustomAction(name: "Insert Text at Center") { [weak self] in self?.onInsertText?(); return true },
        ]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let world = try? viewportState.transform.viewportToWorld(
            ViewportPoint(x: point.x, y: point.y)
        ) else { return }
        onPointerPreview?(world)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        rebuildOverlay()
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        rebuildOverlay()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyResize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentContainer.frame = bounds
        overlayContainer.frame = bounds
        CATransaction.commit()
        notifyResize()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onInteraction?()
        guard renderPlan != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let world = try? viewportState.transform.viewportToWorld(
            ViewportPoint(x: point.x, y: point.y)
        ) else { return }
        let modifier: SelectionPointerModifier
        if event.modifierFlags.contains(.command) { modifier = .toggle }
        else if event.modifierFlags.contains(.shift) { modifier = .add }
        else { modifier = .replace }
        onPointerSelection?(world, modifier)
    }

    override func scrollWheel(with event: NSEvent) {
        onPan?(ViewportVector(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY))
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMagnify?(pow(2, event.magnification), ViewportPoint(x: point.x, y: point.y))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            onTabTraversal?(event.modifierFlags.contains(.shift) ? .reverse : .forward)
            return
        }
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.modifierFlags.contains(.command), event.keyCode == 30 {
            onSelectNext?()
            return
        }
        if event.modifierFlags.contains(.command), event.keyCode == 33 {
            onSelectPrevious?()
            return
        }
        let command: CanvasViewportCommandName?
        switch event.keyCode {
        case 123: command = .panLeft
        case 124: command = .panRight
        case 125: command = .panDown
        case 126: command = .panUp
        default: command = nil
        }
        if let command {
            let vector: ViewportVector
            switch command {
            case .panLeft: vector = ViewportVector(dx: CanvasViewportState.keyboardPanStep, dy: 0)
            case .panRight: vector = ViewportVector(dx: -CanvasViewportState.keyboardPanStep, dy: 0)
            case .panUp: vector = ViewportVector(dx: 0, dy: CanvasViewportState.keyboardPanStep)
            case .panDown: vector = ViewportVector(dx: 0, dy: -CanvasViewportState.keyboardPanStep)
            default: return
            }
            onPan?(vector)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let transform = viewportState.transform
        let artboardOrigin = (try? transform.worldToViewport(viewportState.contentBounds.origin))
            ?? ViewportPoint(x: 0, y: 0)
        let artboard = CGRect(
            x: artboardOrigin.x,
            y: artboardOrigin.y,
            width: viewportState.contentBounds.size.width * viewportState.zoom.value,
            height: viewportState.contentBounds.size.height * viewportState.zoom.value
        )
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        context.setFillColor(NSColor.textBackgroundColor.cgColor)
        context.fill(artboard)
        context.setShadow(offset: .zero, blur: 0)
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1 / max(1, viewportState.pixelRatio.value))
        context.stroke(artboard)
        if window?.firstResponder === self {
            context.setStrokeColor(NSColor.keyboardFocusIndicatorColor.cgColor)
            context.setLineWidth(3)
            context.stroke(bounds.insetBy(dx: 2, dy: 2))
        }
    }

    private func notifyResize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let size = ViewportSize(width: bounds.width, height: bounds.height)
        let scale = Double(window?.backingScaleFactor ?? 2)
        DispatchQueue.main.async { [weak self] in self?.onResize?(size, scale) }
    }

    private func adoptRenderPlan() {
        guard let plan = renderPlan else { return }
        if plan.invalidation == .compositorOnly, rasterViewportState != nil {
            applyCompositorTransformIfPossible()
            rebuildAccessibility(plan)
            return
        }
        let objectMap = Dictionary(uniqueKeysWithValues: plan.authoredObjects.map { ($0.id, $0) })
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for tile in plan.tiles {
            let scale = viewportState.pixelRatio.value
            let tileLayer = CanvasContentTileLayer()
            tileLayer.name = "renderer.tile.\(tile.id.column).\(tile.id.row)"
            tileLayer.contentsScale = scale
            tileLayer.frame = CGRect(
                x: tile.deviceFrame.origin.x / scale,
                y: tile.deviceFrame.origin.y / scale,
                width: tile.deviceFrame.size.width / scale,
                height: tile.deviceFrame.size.height / scale
            )
            tileLayer.viewportState = viewportState
            tileLayer.objects = tile.objectIDs.compactMap { objectMap[$0] }
            tileLayer.tileOrigin = tileLayer.frame.origin
            tileLayer.setNeedsDisplay()
            contentContainer.addSublayer(tileLayer)
        }
        contentContainer.setAffineTransform(.identity)
        rasterViewportState = viewportState
        rebuildOverlay()
        rebuildAccessibility(plan)
        CATransaction.commit()
    }

    private func applyCompositorTransformIfPossible() {
        guard let raster = rasterViewportState else { return }
        let ratio = viewportState.zoom.value / raster.zoom.value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentContainer.setAffineTransform(CGAffineTransform(
            a: ratio,
            b: 0,
            c: 0,
            d: ratio,
            tx: (raster.worldOrigin.x - viewportState.worldOrigin.x) * viewportState.zoom.value,
            ty: (raster.worldOrigin.y - viewportState.worldOrigin.y) * viewportState.zoom.value
        ))
        CATransaction.commit()
    }

    private func rebuildOverlay() {
        overlayContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        if let selectionOverlayPlan {
            for overlay in selectionOverlayPlan.overlays {
                guard let origin = try? viewportState.transform.worldToViewport(overlay.frame.origin) else { continue }
                let layer = CAShapeLayer()
                layer.name = "renderer.overlay.selection.\(overlay.objectID.description)"
                layer.frame = CGRect(
                    x: origin.x,
                    y: origin.y,
                    width: overlay.frame.size.width * viewportState.zoom.value,
                    height: overlay.frame.size.height * viewportState.zoom.value
                )
                layer.path = CGPath(rect: layer.bounds.insetBy(dx: 1, dy: 1), transform: nil)
                layer.fillColor = nil
                layer.strokeColor = NSColor.controlAccentColor.cgColor
                layer.lineWidth = overlay.kind.contains("primary") ? 3 : 1.5
                if overlay.kind.contains("locked") { layer.lineDashPattern = [4, 3] }
                overlayContainer.addSublayer(layer)
            }
        }
        if let preview = insertionPreviewOverlay,
           let origin = try? viewportState.transform.worldToViewport(preview.frame.origin) {
            let layer = CAShapeLayer()
            layer.name = "renderer.overlay.insertion-preview"
            layer.frame = CGRect(
                x: origin.x,
                y: origin.y,
                width: preview.frame.size.width * viewportState.zoom.value,
                height: preview.frame.size.height * viewportState.zoom.value
            )
            layer.path = CGPath(rect: layer.bounds.insetBy(dx: 1, dy: 1), transform: nil)
            layer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            layer.strokeColor = NSColor.controlAccentColor.cgColor
            layer.lineWidth = 2
            layer.lineDashPattern = [6, 4]
            overlayContainer.addSublayer(layer)
        }
        let focus = CAShapeLayer()
        focus.name = "renderer.overlay.focus"
        focus.frame = bounds
        focus.path = CGPath(rect: bounds.insetBy(dx: 2, dy: 2), transform: nil)
        focus.fillColor = nil
        focus.strokeColor = NSColor.keyboardFocusIndicatorColor.cgColor
        focus.lineWidth = 3
        focus.isHidden = window?.firstResponder !== self
        overlayContainer.addSublayer(focus)
    }

    private func rebuildAccessibility(_ plan: CanvasRenderPlan) {
        let repairedFocus = CanvasAccessibilityFocusPolicy.repairedFocus(
            previousObjectID: focusedAccessibilityObjectID,
            elements: plan.accessibilityElements
        )
        let focusChanged = repairedFocus != focusedAccessibilityObjectID
        focusedAccessibilityObjectID = repairedFocus
        let selectedIDs = Set(selectionOverlayPlan?.overlays.map(\.objectID) ?? [])
        virtualAccessibilityElements = plan.accessibilityElements.map { item in
            let local = CGPoint(x: item.frame.origin.x, y: item.frame.origin.y)
            let screenOrigin = window?.convertPoint(toScreen: convert(local, to: nil)) ?? .zero
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.group)
            element.setAccessibilityFrame(NSRect(
                x: screenOrigin.x,
                y: screenOrigin.y,
                width: item.frame.size.width,
                height: item.frame.size.height
            ))
            element.setAccessibilityLabel(item.label)
            element.setAccessibilityParent(self)
            element.setAccessibilityIdentifier("canvas.object.\(item.objectID.description)")
            element.setAccessibilitySelected(selectedIDs.contains(item.objectID))
            return element
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
        if focusChanged,
           let focusedAccessibilityObjectID,
           let focusedIndex = plan.accessibilityElements.firstIndex(where: {
               $0.objectID == focusedAccessibilityObjectID
           }) {
            let focusedElement = virtualAccessibilityElements[focusedIndex]
            NSAccessibility.post(element: focusedElement, notification: .focusedUIElementChanged)
        }
    }
}

private final class CanvasContentTileLayer: CALayer {
    var viewportState: CanvasViewportState?
    var objects: [CanvasRenderObject] = []
    var tileOrigin = CGPoint.zero

    override func draw(in context: CGContext) {
        guard let viewportState else { return }
        for object in objects where object.isVisible {
            guard let origin = try? viewportState.transform.worldToViewport(object.frame.origin) else { continue }
            let rect = CGRect(
                x: origin.x - tileOrigin.x,
                y: origin.y - tileOrigin.y,
                width: object.frame.size.width * viewportState.zoom.value,
                height: object.frame.size.height * viewportState.zoom.value
            )
            context.saveGState()
            if let clip = object.clipRect,
               let clipOrigin = try? viewportState.transform.worldToViewport(clip.origin) {
                context.clip(to: CGRect(
                    x: clipOrigin.x - tileOrigin.x,
                    y: clipOrigin.y - tileOrigin.y,
                    width: clip.size.width * viewportState.zoom.value,
                    height: clip.size.height * viewportState.zoom.value
                ))
            }
            let color: NSColor = switch object.style {
            case .canvas: .underPageBackgroundColor
            case .page: .controlAccentColor.withAlphaComponent(0.16)
            case .container: .controlAccentColor.withAlphaComponent(0.28)
            case .imagePlaceholder: .systemPurple.withAlphaComponent(0.22)
            case .textPlaceholder: .labelColor.withAlphaComponent(0.12)
            }
            context.setFillColor(color.cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.separatorColor.cgColor)
            context.setLineWidth(1 / max(1, viewportState.pixelRatio.value))
            context.stroke(rect)
            context.restoreGState()
        }
    }
}
