import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

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
            minWidth: WorkspaceMetrics.effectiveMinimumWindowSize().width,
            minHeight: WorkspaceMetrics.effectiveMinimumWindowSize().height
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SiteForge workspace")
        .accessibilityIdentifier("workspace.shell")
        .background {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                WindowCloseGuard(state: state).frame(width: 0, height: 0)
                WorkspaceWindowTabRouterInstaller(
                    router: tabRouter,
                    focus: $focusedControl,
                    pageIDs: state.pages.map(\.id),
                    layerIDs: state.navigatorTab == .layers ? state.layerTargets.map(\.id) : [],
                    state: state
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
            Label(
                controller.canRestoreRecovery
                    ? "A newer valid recovery candidate is available."
                    : "A recovery artifact needs secure cleanup.",
                systemImage: "clock.arrow.circlepath"
            )
            Spacer()
            Button("Inspect Details") { controller.isRecoveryDetailsPresented = true }
                .accessibilityIdentifier("recovery.inspect")
            Button("Discard") { Task { await controller.discardRecovery() } }
                .accessibilityIdentifier("recovery.discard")
            Button("Restore") { Task { _ = await controller.requestRestoreRecovery() } }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("recovery.restore")
                .disabled(!controller.canRestoreRecovery)
                .accessibilityHint(
                    controller.canRestoreRecovery
                        ? "Restores the newer validated recovery candidate."
                        : "Unavailable until the obsolete recovery artifact is discarded."
                )
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .workspaceChrome(.recoveryBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery.candidate")
    }
}

private struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var state: WorkspaceShellState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.state = state
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var state: WorkspaceShellState
        weak var priorDelegate: NSWindowDelegate?
        weak var window: NSWindow?
        init(state: WorkspaceShellState) { self.state = state }
        func attach(to candidate: NSWindow?) {
            guard let candidate, candidate !== window else { return }
            window = candidate
            priorDelegate = candidate.delegate
            candidate.delegate = self
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            let controller = state.lifecycle
            if controller.consumeCloseAuthorization() {
                return priorDelegate?.windowShouldClose?(sender) ?? true
            }
            state.cancelDragDrop()
            if state.textEditingSession.isActive {
                state.commitTextEditing()
                guard !state.textEditingSession.isActive else { return false }
            }
            Task { @MainActor [weak sender] in
                guard let sender else { return }
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
                .accessibilityValue(state.nextUndoLabel ?? "Unavailable")
                .accessibilityHint(state.undoDisabledReason ?? "Undo the last committed document command")

            Button("Redo", systemImage: "arrow.uturn.forward") {
                state.redo()
            }
                .disabled(!state.canRedo)
                .help(state.redoDisabledReason ?? "Redo the last undone document command")
                .accessibilityIdentifier("toolbar.redo")
                .accessibilityValue(state.nextRedoLabel ?? "Unavailable")
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
    let accessibilityDescription: (Tab) -> String?
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
                .accessibilityHint(accessibilityDescription(tab) ?? "")
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
                accessibilityDescription: { _ in nil },
                focus: focus,
                focusValue: {
                    switch $0 {
                    case .pages: .navigatorPages
                    case .layers: .navigatorLayers
                    case .elements: .navigatorElements
                    case .assets: .navigatorAssets
                    case .components: .navigatorComponents
                    }
                }
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
            } else if state.navigatorTab == .layers {
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
            } else if state.navigatorTab == .elements {
                ElementsCatalogView(state: state)
            } else {
                FutureNavigatorDestinationView(tab: state.navigatorTab)
            }
        }
        .padding(10)
        .workspaceChrome(.navigator)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.navigator.rawValue)
    }
}

private struct ElementsCatalogView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(["Layout", "Basic", "Site"], id: \.self) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(ElementCatalogItem.allCases.filter { $0.category == category }) { item in
                            ElementCatalogRow(item: item, state: state)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Elements catalog")
        .accessibilityIdentifier("navigator.elements.catalog")
    }
}

private struct ElementCatalogRow: View {
    let item: ElementCatalogItem
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        let availability = item.availability
        Button {
            guard case .available(let tool) = availability else { return }
            // Structural catalogue rows have a useful non-pointer equivalent:
            // they commit one validated default insertion. Frame/Text retain
            // their established tool-arming workflow for canvas placement.
            if let kind = item.insertionKind, [.section, .stack, .grid].contains(kind) {
                state.performDefaultInsertion(kind, provenance: .accessibility)
            } else {
                state.selectTool(tool)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    Text(item.keyboardPath).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if case .unavailable = availability {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled({ if case .unavailable = availability { true } else { false } }())
        .accessibilityIdentifier("navigator.elements.\(item.rawValue)")
        .accessibilityLabel(item.title)
        .accessibilityHint(item.accessibilityDescription)
    }
}

private struct FutureNavigatorDestinationView: View {
    let tab: NavigatorTab

    var body: some View {
        ContentUnavailableView {
            Label("\(tab.title) Not Available Yet", systemImage: tab == .assets ? "photo.on.rectangle" : "square.stack.3d.up")
        } description: {
            Text(tab == .assets
                 ? "Asset storage and import are planned for a later SiteForge milestone."
                 : "Component definitions and instances are planned for a later SiteForge milestone.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(tab.title) not available yet")
        .accessibilityIdentifier("navigator.\(tab.rawValue).unavailable")
    }
}

private struct NavigatorLayerRow: View {
    let target: SelectionTargetSnapshot
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    private var isSelected: Bool { state.selectionState.orderedIDs.contains(target.id) }
    private var isPrimary: Bool { state.selectionState.primaryID == target.id }
    private var moveBeforeAvailability: DragDropAvailability? {
        guard let source = state.selectionState.primaryID,
              let destination = state.dragDestination(before: target.id) else { return nil }
        return state.dragDropAvailability(
            sourceID: source,
            destination: destination,
            provenance: .contextualMenu
        )
    }
    private var nestAvailability: DragDropAvailability? {
        guard let source = state.selectionState.primaryID,
              let destination = state.dragDestination(nestingIn: target.id) else { return nil }
        return state.dragDropAvailability(
            sourceID: source,
            destination: destination,
            provenance: .contextualMenu
        )
    }
    private var dragAccessibilityHint: String {
        let base = "Press Return to select. Use Up and Down Arrow to traverse objects. Drag to move, or use accessible actions to place the selected layer."
        let unavailable = [moveBeforeAvailability?.disabledReason, nestAvailability?.disabledReason]
            .compactMap { $0 }
            .sorted()
        if unavailable.isEmpty, state.selectionState.primaryID == nil {
            return base + " Select an available layer before using Move Before or Nest In."
        }
        guard !unavailable.isEmpty else { return base }
        return base + " Unavailable actions: " + unavailable.joined(separator: " ")
    }

    private func performAccessibilityMoveBefore() {
        guard let availability = moveBeforeAvailability,
              availability.isEnabled,
              let destination = state.dragDestination(before: target.id),
              let source = state.selectionState.primaryID else {
            state.announceDragDropUnavailable(
                moveBeforeAvailability?.disabledReason ?? "Select an available layer before moving it."
            )
            return
        }
        state.performDragDrop(sourceID: source, destination: destination, provenance: .accessibility)
    }

    private func performAccessibilityNest() {
        guard let availability = nestAvailability,
              availability.isEnabled,
              let destination = state.dragDestination(nestingIn: target.id),
              let source = state.selectionState.primaryID else {
            state.announceDragDropUnavailable(
                nestAvailability?.disabledReason ?? "Select an available layer before nesting it."
            )
            return
        }
        state.performDragDrop(sourceID: source, destination: destination, provenance: .accessibility)
    }

    var body: some View {
        VStack(spacing: 2) {
            if state.isDragInsertionPreview(before: target.id) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 6)
                    .accessibilityLabel("Valid insertion position before \(target.name)")
                    .accessibilityIdentifier("drag.insertion.indicator.\(target.id.description)")
            }
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
            .accessibilityHint(dragAccessibilityHint)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("navigator.layer.\(target.id.description)")
            .accessibilityAction(named: "Move selected layer before \(target.name)") {
                performAccessibilityMoveBefore()
            }
            .accessibilityAction(named: "Nest selected layer in \(target.name)") {
                performAccessibilityNest()
            }
            .contextMenu {
                Button("Move Before") {
                    guard let destination = state.dragDestination(before: target.id),
                          let source = state.selectionState.primaryID else { return }
                    state.performDragDrop(sourceID: source, destination: destination, provenance: .contextualMenu)
                }
                .disabled(moveBeforeAvailability?.isEnabled != true)
                .accessibilityHint(moveBeforeAvailability?.disabledReason ?? "Select an available layer to move.")
                Button("Nest In") {
                    guard let destination = state.dragDestination(nestingIn: target.id),
                          let source = state.selectionState.primaryID else { return }
                    state.performDragDrop(sourceID: source, destination: destination, provenance: .contextualMenu)
                }
                .disabled(nestAvailability?.isEnabled != true)
                .accessibilityHint(nestAvailability?.disabledReason ?? "Select an available layer to nest.")
                Button("Edit Text") {
                    state.beginTextEditing(nodeID: target.id, provenance: .contextualMenu)
                }
                .disabled(!state.textEditingAvailability(nodeID: target.id).isEnabled)
            }
            if state.isDragNestingPreview(in: target.id) {
                Text("Drop to nest in \(target.name)")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("drag.nesting.indicator.\(target.id.description)")
            }
        }
        // Attach the native source and target to the row container rather than
        // its selection button: AppKit must be able to begin a drag without the
        // button's activation gesture consuming the pointer sequence.
        .onDrag {
            guard let transfer = state.beginPointerDrag(sourceID: target.id) else {
                return NSItemProvider()
            }
            return LayerDragPayload.provider(for: transfer)
        }
        .onDrop(of: [LayerDragPayload.contentType], delegate: LayerDropDelegate(targetID: target.id, state: state))
    }
}

private struct LayerDropDelegate: DropDelegate {
    let targetID: NodeID
    @ObservedObject var state: WorkspaceShellState

    func validateDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [LayerDragPayload.contentType]).first,
              let callback = state.beginPointerDropCallback() else { return false }
        item.loadDataRepresentation(forTypeIdentifier: LayerDragPayload.contentType.identifier) { data, _ in
            guard let transfer = LayerDragPayload.transfer(from: data) else { return }
            Task { @MainActor in
                guard let destination = state.dragDestination(before: targetID) else { return }
                _ = state.previewPointerDrag(transfer, destination: destination, callback: callback)
            }
        }
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [LayerDragPayload.contentType]).first,
              let callback = state.beginPointerDropCallback() else { return false }
        item.loadDataRepresentation(forTypeIdentifier: LayerDragPayload.contentType.identifier) { data, _ in
            guard let transfer = LayerDragPayload.transfer(from: data) else { return }
            Task { @MainActor in
                guard let destination = state.dragDestination(before: targetID) else { return }
                _ = state.commitPointerDrag(transfer, destination: destination, callback: callback)
            }
        }
        return true
    }

    func dropExited(info: DropInfo) { state.clearPointerDragPreview() }
}

/// The Layers navigator only accepts this process-owned representation. Generic
/// text and Finder payloads cannot accidentally become canonical move commands.
private enum LayerDragPayload {
    static let contentType = UTType(
        exportedAs: "app.siteforge.SiteForge.layer-drag",
        conformingTo: .data
    )

    static func provider(for transfer: LocalLayerDragTransfer) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: contentType.identifier,
            // The capability never leaves this process. A custom UTI and the
            // scene-local session token together reject foreign drag payloads.
            visibility: .ownProcess
        ) { completion in
            completion(try? JSONEncoder().encode(transfer), nil)
            return nil
        }
        return provider
    }

    static func transfer(from data: Data?) -> LocalLayerDragTransfer? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(LocalLayerDragTransfer.self, from: data)
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
                ZStack(alignment: .topLeading) {
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
                            Button("Edit Selected Text") {
                                guard let nodeID = state.selectionState.primaryID else { return }
                                state.beginTextEditing(
                                    nodeID: nodeID,
                                    provenance: .contextualMenu
                                )
                            }
                            .disabled(
                                state.selectionState.primaryID.map {
                                    !state.textEditingAvailability(nodeID: $0).isEnabled
                                } ?? true
                            )
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
                            Divider()
                            Button("Move Right 1 px") {
                                state.performTransform(
                                    .move(delta: .init(dx: 1, dy: 0), constraint: .horizontal),
                                    provenance: .contextualMenu
                                )
                            }
                            .disabled(!state.transformAvailability(
                                .move(delta: .init(dx: 1, dy: 0), constraint: .horizontal)
                            ).isEnabled)
                            Button("Increase Width 1 px") {
                                state.performTransform(
                                    .resize(
                                        handle: .right,
                                        delta: .init(dx: 1, dy: 0),
                                        constraint: .horizontal
                                    ),
                                    provenance: .contextualMenu
                                )
                            }
                            .disabled(!state.transformAvailability(
                                .resize(
                                    handle: .right,
                                    delta: .init(dx: 1, dy: 0),
                                    constraint: .horizontal
                                )
                            ).isEnabled)
                            Divider()
                            Button("Add Horizontal Guide") {
                                state.addGuide(
                                    axis: .horizontal,
                                    position: state.viewportState.visibleWorldRect.origin.y + 100,
                                    provenance: .contextualMenu
                                )
                            }
                            Button("Add Vertical Guide") {
                                state.addGuide(
                                    axis: .vertical,
                                    position: state.viewportState.visibleWorldRect.origin.x + 100,
                                    provenance: .contextualMenu
                                )
                            }
                            Button("Move Selected Guide 1 px") {
                                state.moveSelectedGuide(by: 1, provenance: .contextualMenu)
                            }
                            .disabled(state.selectedGuideID == nil)
                            Button("Remove Selected Guide") {
                                state.removeSelectedGuide(provenance: .contextualMenu)
                            }
                            .disabled(state.selectedGuideID == nil)
                            Button("Suppress Snapping") {
                                state.setSnappingSuppressed(!state.isSnappingSuppressed)
                            }
                        }

                    VStack {
                        HStack {
                            Text("Horizontal ruler")
                                .accessibilityLabel("Horizontal ruler aligned to world X coordinates")
                                .accessibilityValue(state.viewportAccessibilityValue)
                                .accessibilityIdentifier("canvas.ruler.horizontal")
                            Text("Vertical ruler")
                                .accessibilityLabel("Vertical ruler aligned to world Y coordinates")
                                .accessibilityValue(state.viewportAccessibilityValue)
                                .accessibilityIdentifier("canvas.ruler.vertical")
                        }
                        ForEach(state.activeGuides, id: \.id) { guide in
                            Text("\(guide.axis.rawValue.capitalized) guide")
                                .accessibilityLabel("\(guide.axis.rawValue.capitalized) authored guide")
                                .accessibilityValue(String(format: "%.1f points", guide.position))
                                .accessibilityAddTraits(
                                    guide.id == state.selectedGuideID ? .isSelected : []
                                )
                                .accessibilityIdentifier("canvas.guide.\(guide.id.description)")
                        }
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)

                    if state.canvasRenderPlan == nil {
                        ProgressView("Preparing canvas…")
                            .controlSize(.small)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    } else if state.canvasRenderPlan?.authoredObjects.isEmpty == true {
                        // ContentUnavailableView expands to its proposed
                        // canvas size on macOS, which would turn its empty
                        // area into an invisible pointer shield. This bounded
                        // compact form leaves the rest of the real canvas
                        // available for pointer insertion and selection.
                        VStack(spacing: 10) {
                            Label("Your canvas is empty", systemImage: "rectangle.dashed")
                                .font(.headline)
                            Text("Start with a Frame or plain Text. Blank-project roots are structural and are not rendered.")
                                .multilineTextAlignment(.center)
                                .font(.callout)
                            Text("Use the visible Frame or Text actions above the canvas.")
                        }
                        // Keep the central world-space canvas available to the
                        // real Frame/Text pointer workflow; these named start
                        // actions intentionally live above that interaction
                        // area rather than becoming an invisible click shield.
                        .frame(maxWidth: 360)
                        .padding(.top, 24)
                        .accessibilityIdentifier("canvas.empty.state")
                    }
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.viewport.surface")
                .onAppear {
                    // GeometryReader is still composing its SwiftUI update at
                    // this point. Publish viewport state on the next main-run
                    // loop turn so a launch never mutates ObservableObject
                    // state from within the view update transaction.
                    DispatchQueue.main.async {
                        state.resizeViewport(
                            to: ViewportSize(width: geometry.size.width, height: geometry.size.height),
                            pixelRatio: Double(NSScreen.main?.backingScaleFactor ?? 2)
                        )
                    }
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
        VStack(spacing: 4) {
        HStack(spacing: 8) {
            Label("Preview", systemImage: "display")
                .font(.caption.weight(.semibold))
                .accessibilityHint("Preview preset only. Responsive authoring is not available yet.")

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

            Button("Actual Size", systemImage: "1.magnifyingglass") {
                state.performViewportCommand(CanvasViewportCommand(.actualSize))
            }
            .labelStyle(.iconOnly)
            .help("Actual Size")
            .accessibilityLabel("Actual Size")
            .focusable()
            .focused(focus, equals: .viewportReset)
            .accessibilityIdentifier("canvas.zoom.reset")

            Button("Fit to Canvas", systemImage: "arrow.left.and.right") {
                state.performViewportCommand(CanvasViewportCommand(.fitWidth))
            }
            .labelStyle(.iconOnly)
            .help("Fit to Canvas")
            .accessibilityLabel("Fit to Canvas")
            .focusable()
            .focused(focus, equals: .viewportFitCanvas)
            .accessibilityIdentifier("canvas.zoom.fitCanvas")

            Button("Fit to Document", systemImage: "arrow.up.left.and.arrow.down.right") {
                state.performViewportCommand(CanvasViewportCommand(.fitDocument))
            }
            .labelStyle(.iconOnly)
            .help("Fit to Document")
            .accessibilityLabel("Fit to Document")
            .focusable()
            .focused(focus, equals: .viewportFit)
            .accessibilityIdentifier("canvas.zoom.fit")
        }
        if state.canvasRenderPlan?.authoredObjects.isEmpty == true {
            HStack(spacing: 8) {
                Text("Empty canvas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Insert Frame") {
                    state.performDefaultInsertion(.frame, provenance: .accessibility)
                }
                .accessibilityIdentifier("canvas.empty.insert.frame")
                .disabled(!state.insertionAvailability(.frame).isEnabled)
                Button("Insert Text") {
                    state.performDefaultInsertion(.text, provenance: .accessibility)
                }
                .accessibilityIdentifier("canvas.empty.insert.text")
                .disabled(!state.insertionAvailability(.text).isEnabled)
            }
        }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
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
    private var isInlineTextEditing: () -> Bool = { false }
    private var hasMarkedText: () -> Bool = { false }
    private var commitInlineTextEditing: () -> Void = {}
    private var cancelInlineTextEditing: () -> Void = {}

    func configure(
        focus: FocusState<ShellFocus?>.Binding,
        pageIDs: [PageID],
        layerIDs: [NodeID],
        isInlineTextEditing: @escaping () -> Bool,
        hasMarkedText: @escaping () -> Bool,
        commitInlineTextEditing: @escaping () -> Void,
        cancelInlineTextEditing: @escaping () -> Void
    ) {
        self.pageIDs = pageIDs
        self.layerIDs = layerIDs
        currentFocus = { focus.wrappedValue }
        setFocus = { focus.wrappedValue = $0 }
        self.isInlineTextEditing = isInlineTextEditing
        self.hasMarkedText = hasMarkedText
        self.commitInlineTextEditing = commitInlineTextEditing
        self.cancelInlineTextEditing = cancelInlineTextEditing
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
        guard let window,
              window.isKeyWindow,
              NSApp.keyWindow === window,
              window.attachedSheet == nil,
              NSApp.mainMenu?.highlightedItem == nil else { return event }
        let semanticKey: TextEditKey = switch event.keyCode {
        case 36, 76: .returnKey
        case 53: .escape
        default: .other
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let textDecision = TextEditKeyRoutingPolicy.decision(
            key: semanticKey,
            isCommandModified: modifiers.contains(.command),
            hasUnsupportedModifiers: !modifiers.intersection([.control, .option]).isEmpty,
            isEditing: (event.window == nil || event.window === window) && isInlineTextEditing(),
            hasMarkedText: hasMarkedText()
        )
        switch textDecision {
        case .commit:
            commitInlineTextEditing()
            updateDiagnostics(outcome: "text-commit")
            return nil
        case .cancel:
            cancelInlineTextEditing()
            updateDiagnostics(outcome: "text-cancel")
            return nil
        case .passThrough:
            break
        }
        guard event.keyCode == 48 else { return event }
        let unsupportedModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard unsupportedModifiers.isEmpty else { return event }
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
    @ObservedObject var state: WorkspaceShellState

    func makeNSView(context: Context) -> WorkspaceWindowTabRouterHostView {
        let view = WorkspaceWindowTabRouterHostView()
        view.router = router
        configureRouter()
        return view
    }

    func updateNSView(_ view: WorkspaceWindowTabRouterHostView, context: Context) {
        view.router = router
        configureRouter()
        router.bind(to: view.window)
    }

    private func configureRouter() {
        router.configure(
            focus: focus,
            pageIDs: pageIDs,
            layerIDs: layerIDs,
            isInlineTextEditing: { [weak state] in state?.textEditingSession.isActive == true },
            hasMarkedText: { [weak state] in state?.textEditingSession.draft?.markedRange != nil },
            commitInlineTextEditing: { [weak state] in state?.commitTextEditing() },
            cancelInlineTextEditing: { [weak state] in state?.cancelTextEditing() }
        )
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
                accessibilityDescription: { $0.accessibilityDescription },
                focus: focus,
                focusValue: {
                    switch $0 {
                    case .design: .inspectorDesign
                    case .layout: .inspectorLayout
                    case .content: .inspectorContent
                    case .interactions: .inspectorInteractions
                    case .accessibility: .inspectorAccessibility
                    }
                }
            )

            if case let .unavailable(reason, nextStep) = state.inspectorTab.availability {
                ContentUnavailableView(
                    "\(state.inspectorTab.title) Not Available Yet",
                    systemImage: state.inspectorTab == .content ? "text.cursor" : "bolt.slash",
                    description: Text("\(reason) \(nextStep)")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(state.inspectorTab.title) unavailable. Not available yet.")
                .accessibilityValue(reason)
                .accessibilityHint(nextStep)
                .accessibilityIdentifier("inspector.\(state.inspectorTab.rawValue).unavailable")
            } else if state.selectionState.isEmpty {
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
                    inspectorDetails
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Inspector selection summary")
                .accessibilityValue("\(state.selectionSummary); \(state.transformGeometrySummary)")
                .accessibilityIdentifier("inspector.selection.summary")
            }
        }
        .padding(10)
        .workspaceChrome(.inspector)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.inspector.rawValue)
    }

    @ViewBuilder
    private var inspectorDetails: some View {
        switch state.inspectorTab {
        case .design:
            Text("Design summary")
                .font(.headline)
            Text("Current appearance is read-only in this bounded inspector foundation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.design.summary")
        case .layout:
            Text(state.transformGeometrySummary)
                .monospacedDigit()
                .accessibilityLabel("Selection geometry")
                .accessibilityValue(state.transformGeometrySummary)
                .accessibilityIdentifier("inspector.transform.geometry")
            Text("Broader editable properties are intentionally deferred to a later authoring slice.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.selectionState.count == 1 {
                HStack {
                    Button("Move Right 1 px") {
                        state.performTransform(.move(delta: .init(dx: 1, dy: 0), constraint: .horizontal), provenance: .accessibility)
                    }
                    .accessibilityIdentifier("inspector.transform.moveRight")
                    Button("Increase Width 1 px") {
                        state.performTransform(.resize(handle: .right, delta: .init(dx: 1, dy: 0), constraint: .horizontal), provenance: .accessibility)
                    }
                    .accessibilityIdentifier("inspector.transform.increaseWidth")
                }
                .controlSize(.small)
            }
            Divider()
            guideAndSnappingDetails
        case .accessibility:
            Text("Accessibility summary")
                .font(.headline)
            Text("\(state.selectionSummary). \(state.selectionState.count == 1 ? "Primary selection is available for inspection." : "Multiple selection remains inspection-only.")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.accessibility.summary")
        case .content, .interactions:
            EmptyView()
        }
    }

    private var guideAndSnappingDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Guides & Snapping").font(.headline)
            Text(state.snappingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.snapping.status")
            HStack {
                Button("Add H Guide") {
                    state.addGuide(axis: .horizontal, position: state.viewportState.visibleWorldRect.origin.y + 100, provenance: .accessibility)
                }
                .accessibilityLabel("Add horizontal guide")
                .accessibilityIdentifier("inspector.guide.addHorizontal")
                Button("Add V Guide") {
                    state.addGuide(axis: .vertical, position: state.viewportState.visibleWorldRect.origin.x + 100, provenance: .accessibility)
                }
                .accessibilityLabel("Add vertical guide")
                .accessibilityIdentifier("inspector.guide.addVertical")
            }
            .controlSize(.small)
            if state.selectedGuideID != nil {
                Text(state.selectedGuideSummary)
                    .monospacedDigit()
                    .accessibilityIdentifier("inspector.guide.summary")
                HStack {
                    Button("Move +1") { state.moveSelectedGuide(by: 1, provenance: .accessibility) }
                        .accessibilityLabel("Move selected guide one point")
                        .accessibilityIdentifier("inspector.guide.move")
                    Button("Remove") { state.removeSelectedGuide(provenance: .accessibility) }
                        .accessibilityLabel("Remove selected guide")
                        .accessibilityIdentifier("inspector.guide.remove")
                }
                .controlSize(.small)
            }
            Toggle("Suppress snapping", isOn: Binding(
                get: { state.isSnappingSuppressed },
                set: { state.setSnappingSuppressed($0) }
            ))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("inspector.snapping.suppress")
        }
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
            if state.transformSession.phase != .inactive {
                Divider().frame(height: 14)
                Label(state.transformStatus, systemImage: "arrow.up.left.and.arrow.down.right")
                    .accessibilityIdentifier("status.transform")
            }
            if state.textEditingSession.phase != .inactive {
                Divider().frame(height: 14)
                Label(state.textEditingStatus, systemImage: "character.cursor.ibeam")
                    .accessibilityLabel(state.textEditingStatus)
                    .accessibilityValue(state.textEditingStatus)
                    .accessibilityIdentifier("status.textEditing")
                ControlGroup {
                    Button {
                        state.commitTextEditing()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Commit text edit")
                    .accessibilityIdentifier("textEditing.commit")
                    Button {
                        state.cancelTextEditing()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel text edit")
                    .accessibilityIdentifier("textEditing.cancel")
                }
                .controlSize(.mini)
            }
            if state.snapResolution != nil || state.isSnappingSuppressed {
                Divider().frame(height: 14)
                Label(state.snappingStatus, systemImage: "scope")
                    .accessibilityIdentifier("status.snapping")
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

        CommandMenu("Insert") {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    state?.selectTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
                .keyboardShortcut(tool.shortcut, modifiers: [])
                .disabled(state?.textEditingSession.isActive == true)
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
            Divider()
            Button("Insert Section at Center") {
                state?.performDefaultInsertion(.section, provenance: .menu)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(state?.insertionAvailability(.section).isEnabled != true)
            Button("Insert Stack at Center") {
                state?.performDefaultInsertion(.stack, provenance: .menu)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(state?.insertionAvailability(.stack).isEnabled != true)
            Button("Insert Grid at Center") {
                state?.performDefaultInsertion(.grid, provenance: .menu)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            .disabled(state?.insertionAvailability(.grid).isEnabled != true)
        }

        CommandMenu("Selection") {
            Button("Edit Selected Text") {
                guard let nodeID = state?.selectionState.primaryID else { return }
                state?.beginTextEditing(nodeID: nodeID, provenance: .menu)
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(
                state?.textEditingSession.isActive == true
                    || (state?.selectionState.primaryID.map {
                    state?.textEditingAvailability(nodeID: $0).isEnabled != true
                } ?? true)
            )
            Button("Commit Text Edit") {
                state?.commitTextEditing()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state?.textEditingSession.isActive != true)
            Divider()
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
            Button("Fit to Canvas") { state?.performViewportCommand(CanvasViewportCommand(.fitWidth)) }
            Divider()
            Button("Pan Left") { state?.performViewportCommand(CanvasViewportCommand(.panLeft)) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button("Pan Right") { state?.performViewportCommand(CanvasViewportCommand(.panRight)) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
            Button("Pan Up") { state?.performViewportCommand(CanvasViewportCommand(.panUp)) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("Pan Down") { state?.performViewportCommand(CanvasViewportCommand(.panDown)) }
                .keyboardShortcut(.downArrow, modifiers: .option)
            Divider()
            Button("Move Selection Right 1 px") {
                state?.performTransform(
                    .move(delta: .init(dx: 1, dy: 0), constraint: .horizontal),
                    provenance: .menu
                )
            }
            .keyboardShortcut(.rightArrow, modifiers: .control)
            .disabled(state?.transformAvailability(
                .move(delta: .init(dx: 1, dy: 0), constraint: .horizontal)
            ).isEnabled != true)
            Button("Increase Selection Width 1 px") {
                state?.performTransform(
                    .resize(
                        handle: .right,
                        delta: .init(dx: 1, dy: 0),
                        constraint: .horizontal
                    ),
                    provenance: .menu
                )
            }
            .disabled(state?.transformAvailability(
                .resize(
                    handle: .right,
                    delta: .init(dx: 1, dy: 0),
                    constraint: .horizontal
                )
            ).isEnabled != true)
            Divider()
            Button("Add Horizontal Guide") {
                guard let state else { return }
                state.addGuide(
                    axis: .horizontal,
                    position: state.viewportState.visibleWorldRect.origin.y + 100,
                    provenance: .menu
                )
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
            Button("Add Vertical Guide") {
                guard let state else { return }
                state.addGuide(
                    axis: .vertical,
                    position: state.viewportState.visibleWorldRect.origin.x + 100,
                    provenance: .menu
                )
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            Button("Move Selected Guide 1 px") {
                state?.moveSelectedGuide(by: 1, provenance: .menu)
            }
            .disabled(state?.selectedGuideID == nil)
            Button("Remove Selected Guide") {
                state?.removeSelectedGuide(provenance: .menu)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(state?.selectedGuideID == nil)
            Button(state?.isSnappingSuppressed == true ? "Enable Snapping" : "Suppress Snapping") {
                guard let state else { return }
                state.setSnappingSuppressed(!state.isSnappingSuppressed)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
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
        view.transformOverlays = state.transformOverlays
        view.authoredGuides = state.activeGuides
        view.guidePreview = state.guidePreview
        view.snapResolution = state.snapResolution
        view.selectedGuideID = state.selectedGuideID
        view.textEditingPresentation = state.textEditingPresentation
        view.accessibilityViewportValue = state.viewportAccessibilityValue
        view.needsDisplay = true
        let width = Double(view.bounds.width)
        let height = Double(view.bounds.height)
        let scale = Double(view.window?.backingScaleFactor ?? 2)
        if isKeyboardFocused,
           state.textEditingPresentation == nil,
           view.window?.firstResponder !== view {
            DispatchQueue.main.async { [weak view, weak state] in
                guard let view, let state,
                      state.textEditingPresentation == nil,
                      view.window != nil else { return }
                view.window?.makeFirstResponder(view)
            }
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
        view.transformOverlays = state.transformOverlays
        view.authoredGuides = state.activeGuides
        view.guidePreview = state.guidePreview
        view.snapResolution = state.snapResolution
        view.selectedGuideID = state.selectedGuideID
        view.textEditingPresentation = state.textEditingPresentation
        view.onInteraction = { state.noteCanvasInteraction() }
        view.onPointerSelection = { point, modifier in state.selectCanvasPoint(point, modifier: modifier) }
        view.onPointerPreview = { point in state.previewInsertion(at: point) }
        view.onPointerTransformStart = { point in state.beginPointerTransform(at: point) }
        view.onPointerTransformUpdate = { delta, constrain, suppress in
            state.updatePointerTransform(
                delta: delta,
                constrainAxis: constrain,
                suppressSnapping: suppress
            )
        }
        view.onPointerTransformCommit = { state.commitPointerTransform() }
        view.onPointerTransformCancel = { state.cancelTransform() }
        view.onKeyboardMove = { delta in
            let constraint: TransformAxisConstraint = delta.dx == 0 ? .vertical : .horizontal
            let operation = TransformOperation.move(delta: delta, constraint: constraint)
            guard state.transformAvailability(operation).isEnabled else { return false }
            state.performTransform(operation, provenance: .keyboard)
            return true
        }
        view.onSelectNext = { state.performSelectionCommand(.next, provenance: .keyboard) }
        view.onSelectPrevious = { state.performSelectionCommand(.previous, provenance: .keyboard) }
        view.onClearSelection = { state.performSelectionCommand(.clear, provenance: .keyboard) }
        view.onEscape = { state.performEscape() }
        view.onInsertFrame = { state.performDefaultInsertion(.frame, provenance: .accessibility) }
        view.onInsertText = { state.performDefaultInsertion(.text, provenance: .accessibility) }
        view.onBeginTextEditingAtPoint = {
            state.beginTextEditing(at: $0, provenance: .pointer)
        }
        view.onBeginSelectedTextEditing = {
            guard let nodeID = state.selectionState.primaryID else { return false }
            return state.beginTextEditing(nodeID: nodeID, provenance: .keyboard)
        }
        view.onTextDraftChange = { text, selection, markedRange in
            state.updateTextEditingDraft(
                text: text,
                selection: selection,
                markedRange: markedRange
            )
        }
        view.onTextCommit = { state.commitTextEditing() }
        view.onTextCancel = { state.cancelTextEditing() }
        view.onCreateGuide = { axis, position in
            state.addGuide(axis: axis, position: position, provenance: .pointer)
        }
        view.onSelectGuide = { state.selectGuide($0) }
        view.onToggleSnapping = {
            state.setSnappingSuppressed(!state.isSnappingSuppressed)
        }
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
            updateTextEditor()
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
    var transformOverlays: [CanvasEditorOverlay] = [] {
        didSet { rebuildOverlay() }
    }
    var authoredGuides: [AuthoredGuide] = [] { didSet { rebuildOverlay() } }
    var guidePreview: GuidePreview? { didSet { rebuildOverlay() } }
    var snapResolution: SnapResolution? { didSet { rebuildOverlay() } }
    var selectedGuideID: GuideID? { didSet { rebuildOverlay() } }
    var textEditingPresentation: InlineTextEditorPresentation? {
        didSet { updateTextEditor() }
    }
    var accessibilityViewportValue = "Zoom 100 percent"
    var onInteraction: (() -> Void)?
    var onPointerSelection: ((WorldPoint, SelectionPointerModifier) -> Void)?
    var onPointerPreview: ((WorldPoint) -> Void)?
    var onPointerTransformStart: ((WorldPoint) -> Bool)?
    var onPointerTransformUpdate: ((WorldVector, Bool, Bool) -> Void)?
    var onPointerTransformCommit: (() -> Void)?
    var onPointerTransformCancel: (() -> Void)?
    var onKeyboardMove: ((WorldVector) -> Bool)?
    var onSelectNext: (() -> Void)?
    var onSelectPrevious: (() -> Void)?
    var onClearSelection: (() -> Void)?
    var onEscape: (() -> Void)?
    var onInsertFrame: (() -> Void)?
    var onInsertText: (() -> Void)?
    var onBeginTextEditingAtPoint: ((WorldPoint) -> Bool)?
    var onBeginSelectedTextEditing: (() -> Bool)?
    var onTextDraftChange: ((String, TextEditRange, TextEditRange?) -> Void)?
    var onTextCommit: (() -> Void)?
    var onTextCancel: (() -> Void)?
    var onCreateGuide: ((GuideAxis, Double) -> Void)?
    var onSelectGuide: ((GuideID?) -> Void)?
    var onToggleSnapping: (() -> Void)?
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
    private var transformHandleViews: [String: TransformHandleControlView] = [:]
    private var focusedAccessibilityObjectID: NodeID?
    private var pointerTrackingArea: NSTrackingArea?
    private var transformPointerStart: WorldPoint?
    private var transformDidDrag = false
    private var inlineTextView: InlineCanvasTextView?
    private var isApplyingTextPresentation = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentContainer.name = "renderer.authored-content"
        overlayContainer.name = "renderer.editor-overlays"
        // The viewport's coordinate contract is top-left-origin. CALayer
        // subtrees do not inherit NSView.isFlipped, so declare it on each
        // owned container to keep tiles, overlays, clipping, and hit-test
        // geometry in the same coordinate system as CanvasViewportState.
        contentContainer.isGeometryFlipped = true
        overlayContainer.isGeometryFlipped = true
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
    override func accessibilityChildren() -> [Any]? {
        virtualAccessibilityElements + TransformHandle.allCases.compactMap {
            transformHandleViews[$0.rawValue]
        } + [inlineTextView].compactMap { $0 }
    }
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
            NSAccessibilityCustomAction(name: "Edit Selected Text") { [weak self] in
                self?.onBeginSelectedTextEditing?() ?? false
            },
            NSAccessibilityCustomAction(name: "Add Horizontal Guide") { [weak self] in
                guard let self else { return false }
                self.onCreateGuide?(.horizontal, self.viewportState.visibleWorldRect.origin.y + 100)
                return true
            },
            NSAccessibilityCustomAction(name: "Add Vertical Guide") { [weak self] in
                guard let self else { return false }
                self.onCreateGuide?(.vertical, self.viewportState.visibleWorldRect.origin.x + 100)
                return true
            },
            NSAccessibilityCustomAction(name: "Toggle Snapping") { [weak self] in self?.onToggleSnapping?(); return true },
            NSAccessibilityCustomAction(name: "Move Right 1 px") { [weak self] in
                self?.onKeyboardMove?(WorldVector(dx: 1, dy: 0)) ?? false
            },
            NSAccessibilityCustomAction(name: "Move Down 1 px") { [weak self] in
                self?.onKeyboardMove?(WorldVector(dx: 0, dy: 1)) ?? false
            },
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
        updateTextEditor()
        notifyResize()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount >= 2 {
            if let world = try? viewportState.transform.viewportToWorld(
                ViewportPoint(x: point.x, y: point.y)
            ) {
                _ = onBeginTextEditingAtPoint?(world)
            }
            return
        }
        if point.y <= SnappingPolicy.rulerThicknessPoints,
           point.x > SnappingPolicy.rulerThicknessPoints,
           let world = try? viewportState.transform.viewportToWorld(
               ViewportPoint(x: point.x, y: point.y)
           ) {
            window?.makeFirstResponder(self)
            onCreateGuide?(.vertical, world.x)
            return
        }
        if point.x <= SnappingPolicy.rulerThicknessPoints,
           point.y > SnappingPolicy.rulerThicknessPoints,
           let world = try? viewportState.transform.viewportToWorld(
               ViewportPoint(x: point.x, y: point.y)
           ) {
            window?.makeFirstResponder(self)
            onCreateGuide?(.horizontal, world.y)
            return
        }
        if let guide = nearestGuide(at: point) {
            window?.makeFirstResponder(self)
            onSelectGuide?(guide.id)
            return
        }
        if beginTransformGesture(with: event) { return }
        window?.makeFirstResponder(self)
        onInteraction?()
        guard renderPlan != nil else { return }
        guard let world = try? viewportState.transform.viewportToWorld(
            ViewportPoint(x: point.x, y: point.y)
        ) else { return }
        let modifier: SelectionPointerModifier
        if event.modifierFlags.contains(.command) { modifier = .toggle }
        else if event.modifierFlags.contains(.shift) { modifier = .add }
        else { modifier = .replace }
        onPointerSelection?(world, modifier)
    }

    override func mouseDragged(with event: NSEvent) {
        guard updateTransformGesture(with: event) else {
            super.mouseDragged(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        if endTransformGesture() { return }
        super.mouseUp(with: event)
    }

    fileprivate func beginTransformGesture(with event: NSEvent) -> Bool {
        window?.makeFirstResponder(self)
        guard renderPlan != nil else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard let world = try? viewportState.transform.viewportToWorld(
            ViewportPoint(x: point.x, y: point.y)
        ), onPointerTransformStart?(world) == true else {
            return false
        }
        onInteraction?()
        transformPointerStart = world
        transformDidDrag = false
        return true
    }

    @discardableResult
    fileprivate func updateTransformGesture(with event: NSEvent) -> Bool {
        guard let start = transformPointerStart else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard let world = try? viewportState.transform.viewportToWorld(
            ViewportPoint(x: point.x, y: point.y)
        ) else { return true }
        let delta = WorldVector(dx: world.x - start.x, dy: world.y - start.y)
        transformDidDrag = transformDidDrag || abs(delta.dx) > 0.25 || abs(delta.dy) > 0.25
        onPointerTransformUpdate?(
            delta,
            event.modifierFlags.contains(.shift),
            event.modifierFlags.contains(.option)
        )
        return true
    }

    @discardableResult
    fileprivate func endTransformGesture() -> Bool {
        guard transformPointerStart != nil else { return false }
        transformDidDrag ? onPointerTransformCommit?() : onPointerTransformCancel?()
        transformPointerStart = nil
        transformDidDrag = false
        return true
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
        if event.keyCode == 36 || event.keyCode == 76 {
            if onBeginSelectedTextEditing?() == true { return }
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
        if let command, !event.modifierFlags.contains(.option) {
            let step = event.modifierFlags.contains(.shift)
                ? TransformPolicy.keyboardLargeStep
                : TransformPolicy.keyboardStep
            let delta: WorldVector = switch command {
            case .panLeft: WorldVector(dx: -step, dy: 0)
            case .panRight: WorldVector(dx: step, dy: 0)
            case .panUp: WorldVector(dx: 0, dy: -step)
            case .panDown: WorldVector(dx: 0, dy: step)
            default: WorldVector(dx: 0, dy: 0)
            }
            if onKeyboardMove?(delta) == true { return }
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
        drawRulersAndGuides(in: context)
        if window?.firstResponder === self {
            context.setStrokeColor(NSColor.keyboardFocusIndicatorColor.cgColor)
            context.setLineWidth(3)
            context.stroke(bounds.insetBy(dx: 2, dy: 2))
        }
    }

    private func nearestGuide(at point: NSPoint) -> AuthoredGuide? {
        authoredGuides.first { guide in
            let world = guide.axis == .vertical
                ? WorldPoint(x: guide.position, y: viewportState.worldOrigin.y)
                : WorldPoint(x: viewportState.worldOrigin.x, y: guide.position)
            guard let viewport = try? viewportState.transform.worldToViewport(world) else { return false }
            let distance = guide.axis == .vertical
                ? abs(viewport.x - point.x) : abs(viewport.y - point.y)
            return distance <= 5
        }
    }

    private func drawRulersAndGuides(in context: CGContext) {
        let thickness = SnappingPolicy.rulerThicknessPoints
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(NSColor.controlBackgroundColor.withAlphaComponent(0.94).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: thickness))
        context.fill(CGRect(x: 0, y: 0, width: thickness, height: bounds.height))
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1 / max(1, viewportState.pixelRatio.value))
        context.move(to: CGPoint(x: 0, y: thickness))
        context.addLine(to: CGPoint(x: bounds.width, y: thickness))
        context.move(to: CGPoint(x: thickness, y: 0))
        context.addLine(to: CGPoint(x: thickness, y: bounds.height))
        context.strokePath()

        let logicalStep = rulerStep(for: viewportState.zoom.value)
        let visible = viewportState.visibleWorldRect
        var x = floor(visible.minX / logicalStep) * logicalStep
        while x <= visible.maxX {
            if let point = try? viewportState.transform.worldToViewport(WorldPoint(x: x, y: 0)) {
                context.move(to: CGPoint(x: point.x, y: thickness))
                context.addLine(to: CGPoint(x: point.x, y: thickness - 6))
            }
            x += logicalStep
        }
        var y = floor(visible.minY / logicalStep) * logicalStep
        while y <= visible.maxY {
            if let point = try? viewportState.transform.worldToViewport(WorldPoint(x: 0, y: y)) {
                context.move(to: CGPoint(x: thickness, y: point.y))
                context.addLine(to: CGPoint(x: thickness - 6, y: point.y))
            }
            y += logicalStep
        }
        context.strokePath()

        for guide in authoredGuides {
            drawGuide(
                axis: guide.axis,
                position: guide.position,
                color: guide.id == selectedGuideID ? .selectedControlColor : .systemPurple,
                dashed: false,
                in: context
            )
        }
        if let guidePreview {
            drawGuide(
                axis: guidePreview.axis,
                position: guidePreview.position,
                color: .systemPurple,
                dashed: true,
                in: context
            )
        }
        for guide in snapResolution?.smartGuides ?? [] {
            drawGuide(
                axis: guide.axis == .horizontal ? .vertical : .horizontal,
                position: guide.position,
                color: .systemPink,
                dashed: true,
                in: context
            )
        }
        context.setStrokeColor(NSColor.systemPink.cgColor)
        context.setLineDash(phase: 0, lengths: [2, 2])
        for measurement in snapResolution?.measurements ?? [] {
            let start = measurement.axis == .horizontal
                ? WorldPoint(x: measurement.start, y: measurement.crossPosition)
                : WorldPoint(x: measurement.crossPosition, y: measurement.start)
            let end = measurement.axis == .horizontal
                ? WorldPoint(x: measurement.end, y: measurement.crossPosition)
                : WorldPoint(x: measurement.crossPosition, y: measurement.end)
            if let a = try? viewportState.transform.worldToViewport(start),
               let b = try? viewportState.transform.worldToViewport(end) {
                context.move(to: CGPoint(x: a.x, y: a.y))
                context.addLine(to: CGPoint(x: b.x, y: b.y))
            }
        }
        context.strokePath()
    }

    private func rulerStep(for zoom: Double) -> Double {
        var step = 10.0
        while step * zoom < SnappingPolicy.rulerMinimumTickSpacingPoints { step *= 2 }
        return step
    }

    private func drawGuide(
        axis: GuideAxis,
        position: Double,
        color: NSColor,
        dashed: Bool,
        in context: CGContext
    ) {
        let world = axis == .vertical
            ? WorldPoint(x: position, y: viewportState.worldOrigin.y)
            : WorldPoint(x: viewportState.worldOrigin.x, y: position)
        guard let point = try? viewportState.transform.worldToViewport(world) else { return }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: dashed ? [5, 3] : [])
        if axis == .vertical {
            context.move(to: CGPoint(x: point.x, y: 0))
            context.addLine(to: CGPoint(x: point.x, y: bounds.height))
        } else {
            context.move(to: CGPoint(x: 0, y: point.y))
            context.addLine(to: CGPoint(x: bounds.width, y: point.y))
        }
        context.strokePath()
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
        var retainedHandleNames: Set<String> = []
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
                if let label = overlay.label {
                    let labelLayer = CATextLayer()
                    labelLayer.name = "renderer.overlay.selection-context.\(overlay.objectID.description)"
                    labelLayer.string = label
                    labelLayer.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                    labelLayer.fontSize = 11
                    labelLayer.foregroundColor = NSColor.white.cgColor
                    labelLayer.backgroundColor = NSColor.controlAccentColor.cgColor
                    labelLayer.cornerRadius = 4
                    labelLayer.alignmentMode = .center
                    labelLayer.contentsScale = window?.backingScaleFactor ?? 2
                    let width = min(max(120, CGFloat(label.count) * 6.4 + 12), max(120, bounds.width - layer.frame.minX - 4))
                    labelLayer.frame = CGRect(
                        x: layer.frame.minX,
                        y: max(0, layer.frame.minY - 22),
                        width: width,
                        height: 18
                    )
                    overlayContainer.addSublayer(labelLayer)
                }
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
        for overlay in transformOverlays {
            guard let origin = try? viewportState.transform.worldToViewport(overlay.frame.origin) else {
                continue
            }
            let layer = CAShapeLayer()
            layer.name = "renderer.overlay.\(overlay.kind)"
            layer.frame = CGRect(
                x: origin.x,
                y: origin.y,
                width: overlay.frame.size.width * viewportState.zoom.value,
                height: overlay.frame.size.height * viewportState.zoom.value
            )
            layer.path = CGPath(rect: layer.bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            layer.strokeColor = NSColor.controlAccentColor.cgColor
            if overlay.kind.hasPrefix("transform-handle") {
                layer.fillColor = NSColor.controlBackgroundColor.cgColor
                layer.lineWidth = 1
                let handleName = String(overlay.kind.dropFirst("transform-handle-".count))
                retainedHandleNames.insert(handleName)
                let control = transformHandleViews[handleName] ?? {
                    let view = TransformHandleControlView(handleName: handleName, owner: self)
                    transformHandleViews[handleName] = view
                    addSubview(view)
                    return view
                }()
                control.frame = layer.frame.insetBy(dx: -4, dy: -4)
            } else {
                layer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
                layer.lineWidth = 2
                layer.lineDashPattern = overlay.kind == "transform-preview" ? [5, 3] : nil
            }
            overlayContainer.addSublayer(layer)
        }
        for name in Array(transformHandleViews.keys) where !retainedHandleNames.contains(name) {
            transformHandleViews.removeValue(forKey: name)?.removeFromSuperview()
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

    private func updateTextEditor() {
        guard let presentation = textEditingPresentation else {
            if let inlineTextView {
                inlineTextView.suppressEndEditingCallback = true
                if window?.firstResponder === inlineTextView {
                    window?.makeFirstResponder(self)
                }
                inlineTextView.removeFromSuperview()
                self.inlineTextView = nil
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
            return
        }
        let editor = inlineTextView ?? {
            let value = InlineCanvasTextView()
            value.delegate = self
            value.onCommit = { [weak self] in self?.onTextCommit?() }
            value.onCancel = { [weak self] in self?.onTextCancel?() }
            value.setAccessibilityIdentifier("canvas.text.editor")
            value.setAccessibilityLabel("Inline plain-text editor")
            value.setAccessibilityHelp(
                "Type plain text. Press Command-Return to commit or Escape to cancel."
            )
            addSubview(value)
            inlineTextView = value
            NSAccessibility.post(element: self, notification: .layoutChanged)
            return value
        }()
        guard let origin = try? viewportState.transform.worldToViewport(
            presentation.frame.origin
        ) else { return }
        editor.frame = CGRect(
            x: origin.x,
            y: origin.y,
            width: max(44, presentation.frame.size.width * viewportState.zoom.value),
            height: max(24, presentation.frame.size.height * viewportState.zoom.value)
        )
        let preservesNativeDraft = editor.representedSessionIdentity == presentation.identity
            && window?.firstResponder === editor
        editor.representedSessionIdentity = presentation.identity
        if !preservesNativeDraft {
            isApplyingTextPresentation = true
            if editor.string != presentation.text { editor.string = presentation.text }
            let range = NSRange(
                location: presentation.selection.location,
                length: presentation.selection.length
            )
            if editor.selectedRange() != range { editor.setSelectedRange(range) }
            isApplyingTextPresentation = false
        }
        if window?.firstResponder === editor {
            editor.suppressEndEditingCallback = false
        } else {
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, let editor,
                      self.textEditingPresentation?.identity == presentation.identity,
                      editor.window === self.window else { return }
                if editor.window?.makeFirstResponder(editor) == true {
                    editor.suppressEndEditingCallback = false
                }
            }
        }
    }

}

extension NativeCanvasViewportView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        publishTextEditorState()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        publishTextEditorState()
    }

    func textDidEndEditing(_ notification: Notification) {
        guard inlineTextView?.suppressEndEditingCallback != true else { return }
        onTextCommit?()
    }

    private func publishTextEditorState() {
        guard !isApplyingTextPresentation, let editor = inlineTextView else { return }
        guard editor.string.utf8.count <= InlineTextEditingPolicy.maximumTextBytes,
              InlineTextEditingPolicy.validatesContent(editor.string) else {
            guard let presentation = textEditingPresentation else { return }
            isApplyingTextPresentation = true
            editor.string = presentation.text
            editor.setSelectedRange(NSRange(
                location: presentation.selection.location,
                length: presentation.selection.length
            ))
            isApplyingTextPresentation = false
            NSSound.beep()
            return
        }
        let selected = editor.selectedRange()
        let marked = editor.markedRange()
        onTextDraftChange?(
            editor.string,
            TextEditRange(location: selected.location, length: selected.length),
            marked.location == NSNotFound || marked.length == 0
                ? nil
                : TextEditRange(location: marked.location, length: marked.length)
        )
    }
}

final class InlineCanvasTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var suppressEndEditingCallback = true
    var representedSessionIdentity: TextEditOperationIdentity?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        isEditable = true
        isSelectable = true
        isRichText = false
        importsGraphics = false
        allowsUndo = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .labelColor
        insertionPointColor = .controlAccentColor
        font = .systemFont(ofSize: 14)
        textContainerInset = NSSize(width: 4, height: 3)
        setAccessibilityRole(.textArea)
    }

    convenience init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        self.init(frame: .zero, textContainer: textContainer)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            suppressEndEditingCallback = false
            NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
        }
        return resigned
    }

    override func isAccessibilityFocused() -> Bool {
        window?.firstResponder === self
    }

    override func setAccessibilityFocused(_ focused: Bool) {
        guard focused else { return }
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if (event.keyCode == 36 || event.keyCode == 76),
           event.modifierFlags.contains(.command) {
            guard !hasMarkedText() else {
                interpretKeyEvents([event])
                return true
            }
            suppressEndEditingCallback = true
            onCommit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            suppressEndEditingCallback = true
            onCancel?()
            return
        }
        if (event.keyCode == 36 || event.keyCode == 76),
           event.modifierFlags.contains(.command) {
            guard !hasMarkedText() else {
                interpretKeyEvents([event])
                return
            }
            suppressEndEditingCallback = true
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class TransformHandleControlView: NSView {
    private let handleName: String
    private weak var owner: NativeCanvasViewportView?

    init(handleName: String, owner: NativeCanvasViewportView) {
        self.handleName = handleName
        self.owner = owner
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(handleName) resize handle")
        setAccessibilityHelp("Drag to resize the selected object; numeric resize is available in the inspector.")
        setAccessibilityIdentifier("canvas.transform.handle.\(handleName)")
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { _ = owner?.beginTransformGesture(with: event) }
    override func mouseDragged(with event: NSEvent) { owner?.updateTransformGesture(with: event) }
    override func mouseUp(with event: NSEvent) { owner?.endTransformGesture() }
}

/// Native raster presentation only. The authored scene remains the headless
/// source of truth; this layer must not retain editor drafts or diagnostics.
final class CanvasContentTileLayer: CALayer {
    var viewportState: CanvasViewportState?
    var objects: [CanvasRenderObject] = []
    var tileOrigin = CGPoint.zero

    override init() {
        super.init()
        isGeometryFlipped = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        isGeometryFlipped = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isGeometryFlipped = true
    }

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
            // AppKit text drawing can antialias slightly outside its layout
            // rect. The authored render object, not the text subsystem, owns
            // the paint boundary, so always clip to its frame as well as any
            // ancestor/content clip. This keeps committed text truthful to
            // the same visible and hit-testable bounds as every other object.
            var effectiveClip = rect
            if let clip = object.clipRect,
               let clipOrigin = try? viewportState.transform.worldToViewport(clip.origin) {
                effectiveClip = effectiveClip.intersection(CGRect(
                    x: clipOrigin.x - tileOrigin.x,
                    y: clipOrigin.y - tileOrigin.y,
                    width: clip.size.width * viewportState.zoom.value,
                    height: clip.size.height * viewportState.zoom.value
                ))
            }
            guard !effectiveClip.isNull, !effectiveClip.isEmpty else {
                context.restoreGState()
                continue
            }
            context.clip(to: effectiveClip)
            let color: NSColor = switch object.style {
            case .canvas: .underPageBackgroundColor
            case .page: .controlAccentColor.withAlphaComponent(0.16)
            case .container: .controlAccentColor.withAlphaComponent(0.28)
            case .frameSurface: .controlBackgroundColor.withAlphaComponent(0.92)
            case .sectionSurface: .systemIndigo.withAlphaComponent(0.12)
            case .stackSurface: .systemTeal.withAlphaComponent(0.12)
            case .gridSurface: .systemOrange.withAlphaComponent(0.12)
            case .imagePlaceholder: .systemPurple.withAlphaComponent(0.22)
            case .textPlaceholder: .labelColor.withAlphaComponent(0.12)
            }
            context.setFillColor(color.cgColor)
            context.fill(rect)
            context.setStrokeColor(
                (object.style == .frameSurface
                    ? NSColor.separatorColor.withAlphaComponent(0.85)
                    : NSColor.separatorColor).cgColor
            )
            context.setLineWidth(1 / max(1, viewportState.pixelRatio.value))
            context.stroke(rect)
            if [.frameSurface, .sectionSurface, .stackSurface, .gridSurface].contains(object.style), let name = object.displayName {
                drawFrameName(name, in: rect, zoom: viewportState.zoom.value, context: context)
            }
            if object.style == .textPlaceholder, let text = object.plainText, !text.isEmpty {
                drawCommittedPlainText(
                    text,
                    in: rect,
                    zoom: viewportState.zoom.value,
                    context: context
                )
            }
            context.restoreGState()
        }
    }

    private func drawCommittedPlainText(
        _ text: String,
        in rect: CGRect,
        zoom: Double,
        context: CGContext
    ) {
        let inset = max(3, 4 * zoom)
        let textRect = rect.insetBy(dx: inset, dy: inset)
        guard textRect.width > 0, textRect.height > 0 else { return }
        let fontSize = min(max(11 * zoom, 9), max(9, textRect.height - inset))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        drawAppKitText(attributed, in: textRect, context: context)
    }

    private func drawFrameName(
        _ name: String,
        in rect: CGRect,
        zoom: Double,
        context: CGContext
    ) {
        let labelRect = rect.insetBy(dx: max(6, 8 * zoom), dy: max(5, 7 * zoom))
        guard labelRect.width > 20, labelRect.height > 12 else { return }
        let attributed = NSAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: max(10, 12 * zoom), weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        drawAppKitText(attributed, in: labelRect, context: context)
    }

    /// Converts AppKit text drawing once at the tile boundary. The canonical
    /// world, viewport, device, Core Animation, overlay, event, hit-test, and
    /// snapshot convention is top-left origin with Y increasing down. A tile
    /// CGContext is Y-up, so this helper supplies the exact inverse transform
    /// and translated draw rectangle required for upright glyphs at their
    /// authored top-left coordinates. Individual authored labels never apply
    /// bespoke rotations or compensating transforms.
    private func drawAppKitText(_ attributed: NSAttributedString, in rect: CGRect, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let drawingRect = CanvasTileTextCoordinateSpace.drawingRect(for: rect, in: bounds)
        // The outer authored clip was installed before converting this
        // CoreGraphics context. Reinstall its tile-local counterpart after
        // conversion so glyph antialiasing never escapes the canonical frame.
        context.clip(to: drawingRect)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(
            with: drawingRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }
}

enum CanvasTileTextCoordinateSpace {
    static func drawingRect(for topLeftRect: CGRect, in tileBounds: CGRect) -> CGRect {
        CGRect(
            x: topLeftRect.minX,
            y: tileBounds.height - topLeftRect.maxY,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
    }
}
