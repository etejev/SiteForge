import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

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
            // Escape that clears a selection returns keyboard ownership to
            // the live canvas rather than leaving first responder on a stale
            // Inspector proxy.
            focusedControl = .viewportCanvas
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
        HStack(spacing: 3) {
            overflowMenu

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
            }
            // The scrolling tab strip is the flexible region. Keep the
            // leading native overflow menu allocated at the practical
            // minimum width, away from a hosted display's potentially
            // clipped trailing edge.
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
        }
        .padding(3)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                    focus.wrappedValue = focusValue(tab)
                } label: {
                    if selection == tab {
                        Label(title(tab), systemImage: "checkmark")
                    } else {
                        Text(title(tab))
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 24, minHeight: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .layoutPriority(1)
        .help("Show all \(identifierPrefix.hasPrefix("navigator") ? "navigator" : "Inspector") tabs")
        .accessibilityLabel("Show all tabs")
        .accessibilityIdentifier("\(identifierPrefix).overflow")
    }

    @ViewBuilder
    private func tabButton(_ tab: Tab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(title(tab))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
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
            } else if state.navigatorTab == .assets {
                AssetsNavigatorView(state: state)
                    .id(NavigatorTab.assets)
            } else if state.navigatorTab == .components {
                FutureNavigatorDestinationView(tab: .components)
                    .id(NavigatorTab.components)
            }
        }
        .padding(10)
        .workspaceChrome(.navigator)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.navigator.rawValue)
    }
}

private struct AssetsNavigatorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Images").font(.headline)
                Spacer()
                Button("Import Images…", systemImage: "plus") { state.importImages() }
                    .labelStyle(.iconOnly)
                    .help("Import Images…")
                    .accessibilityLabel("Import Images")
                    .accessibilityIdentifier("assets.import")
            }
            TextField("Search Images", text: $state.assetSearchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("assets.search")

            if state.imageAssets.isEmpty {
                ContentUnavailableView {
                    Label("No Images", systemImage: "photo.on.rectangle.angled")
                        .accessibilityIdentifier("assets.empty")
                } description: {
                    Text(state.assetSearchText.isEmpty
                         ? "Import local PNG, JPEG, GIF, TIFF, or HEIC images. Originals stay inside this project."
                         : "No imported image matches this search.")
                } actions: {
                    if state.assetSearchText.isEmpty {
                        Button("Import Images…") { state.importImages() }
                            .accessibilityIdentifier("assets.empty.import")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(state.imageAssets) { asset in
                            AssetRow(asset: asset, state: state)
                        }
                    }
                }
                .accessibilityLabel("Imported image assets")
                .accessibilityIdentifier("assets.list")
            }

            if state.isImportingImages { ProgressView().controlSize(.small) }
            Text(state.lastAssetAnnouncement)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(3)
                .accessibilityIdentifier("assets.status")
            HStack {
                Button("Insert Image") { state.insertSelectedImage() }
                    .disabled(state.selectedAssetID == nil)
                    .accessibilityIdentifier("assets.insert.selected")
                Button("Import and Insert…") { state.importImages(insertFirst: true) }
                    .accessibilityIdentifier("assets.import.insert")
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assets")
        .accessibilityIdentifier("navigator.assets.library")
    }
}

private struct AssetRow: View {
    let asset: ImageAsset
    @ObservedObject var state: WorkspaceShellState
    @State private var nameDraft = ""
    @State private var isRenaming = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                rowContent
            } else {
                Button { state.selectedAssetID = asset.id } label: { rowContent }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(asset.displayName)
        .accessibilityValue("\(asset.originalFilename), \(asset.pixelWidth) by \(asset.pixelHeight) pixels, \(asset.format.rawValue), \(state.imageAssetUsageCount(asset.id)) uses")
        .accessibilityIdentifier("assets.row.\(asset.id.description)")
        .contextMenu {
            Button("Insert Image") { state.selectedAssetID = asset.id; state.insertSelectedImage() }
            Button("Rename") {
                nameDraft = asset.displayName
                isRenaming = true
                DispatchQueue.main.async { renameFocused = true }
            }
            Button("Replace…") { state.replaceImageAsset(asset.id) }
            Button("Reveal Usage") { state.revealImageUsage(asset.id) }
            Divider()
            Button("Delete…", role: .destructive) { state.requestDeleteImageAsset(asset.id) }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Group {
                if let data = state.imageAssetThumbnail(asset.id), let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 42, height: 42)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Asset name", text: $nameDraft)
                        .focused($renameFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { isRenaming = false; renameFocused = false }
                        .accessibilityIdentifier("assets.rename.field.\(asset.id.description)")
                } else {
                    Text(asset.displayName).lineLimit(1)
                }
                Text(asset.originalFilename)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text("\(asset.pixelWidth) × \(asset.pixelHeight) · \(asset.format.rawValue.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(asset.byteCount), countStyle: .file))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text("\(state.imageAssetUsageCount(asset.id)) use\(state.imageAssetUsageCount(asset.id) == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if state.selectedAssetID == asset.id { Image(systemName: "checkmark.circle.fill") }
        }
        .padding(6).contentShape(Rectangle())
        .background(state.selectedAssetID == asset.id ? Color.accentColor.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
    }

    private func commitRename() {
        state.renameImageAsset(asset.id, to: nameDraft)
        isRenaming = false
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
        VStack {
            ContentUnavailableView {
                Label("\(tab.title) Not Available Yet", systemImage: tab == .assets ? "photo.on.rectangle" : "square.stack.3d.up")
            } description: {
                Text(tab == .assets
                     ? "Asset storage and import are planned for a later SiteForge milestone."
                     : "Component definitions and instances are planned for a later SiteForge milestone.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tab.title) not available yet")
        .accessibilityIdentifier("navigator.\(tab.rawValue).unavailable")
        // Assets and Components deliberately share this view type. Give each
        // destination its own accessibility subtree so a rapid native tab
        // change cannot retain the prior destination's AX identity.
        .id(tab)
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
                // A Layers selection is a real pointer event. Prefer the
                // event being delivered to this control over the process-wide
                // snapshot so an additive click cannot accidentally become a
                // replacement selection while SwiftUI is reconciling views.
                let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                let modifier: SelectionPointerModifier = flags.contains(.command)
                    ? .toggle : flags.contains(.shift) ? .add : .replace
                state.selectLayer(target.id, modifier: modifier)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: target.isLocked ? "lock.fill" : target.isVisible ? "square.dashed" : "eye.slash.fill")
                        .frame(width: 16)
                    Text(target.name).lineLimit(1)
                    Spacer(minLength: 4)
                    if !target.isVisible { Text("Hidden here").font(.caption2).foregroundStyle(.secondary) }
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
            .accessibilityValue("\(target.isLocked ? "Locked; " : "")\(!target.isVisible ? "Hidden at current breakpoint; " : "")\(isPrimary ? "Primary selection" : isSelected ? "Selected" : "Not selected")")
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
                // The header owns its intrinsic one-, two-, or three-row
                // height. A fixed 40-point band clipped the second empty-state
                // row and let accessibility expose controls that users could
                // not see at the supported minimum window size.
                .fixedSize(horizontal: false, vertical: true)
                .zIndex(1)
            Divider()

            GeometryReader { geometry in
                ZStack(alignment: .center) {
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
                            Text("Start with a Frame, plain Text, or an imported Image. Blank-project roots are structural and are not rendered.")
                                .multilineTextAlignment(.center)
                                .font(.callout)
                            Text("Use the visible Frame or Text actions, or import and insert an Image from Assets.")
                                .multilineTextAlignment(.center)
                        }
                        // Keep the central world-space canvas available to the
                        // real Frame/Text pointer workflow; these named start
                        // actions intentionally live above that interaction
                        // area rather than becoming an invisible click shield.
                        .frame(maxWidth: 360)
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("canvas.empty.state")
                    }
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.viewport.surface")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Breakpoint", systemImage: "display")
                    .font(.caption.weight(.semibold))
                    .fixedSize()
                    .accessibilityHint("Selects the responsive geometry breakpoint authored by the Layout Inspector.")

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
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("canvas.viewport.width")

                Spacer(minLength: 4)

                Toggle("Grid", isOn: $state.isWorldGridVisible)
                    .toggleStyle(.button)
                    .fixedSize()
                    .accessibilityIdentifier("canvas.grid.toggle")
                    .accessibilityLabel("World grid")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("canvas.viewport.primaryControls")

            HStack(spacing: 8) {
                Button {
                    state.performViewportCommand(CanvasViewportCommand(.zoomOut))
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .help("Zoom Out")
                .accessibilityLabel("Zoom Out")
                .disabled(state.zoomPercent == 25)
                .focusable()
                .focused(focus, equals: .viewportZoomOut)
                .accessibilityIdentifier("canvas.zoom.out")

                Text("\(state.zoomPercent)%")
                    .monospacedDigit()
                    .frame(minWidth: 42)
                    .accessibilityIdentifier("canvas.zoom.value")

                Button {
                    state.performViewportCommand(CanvasViewportCommand(.zoomIn))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Zoom In")
                .accessibilityLabel("Zoom In")
                .disabled(state.viewportState.zoom == .maximum)
                .focusable()
                .focused(focus, equals: .viewportZoomIn)
                .accessibilityIdentifier("canvas.zoom.in")

                Button("1:1") {
                    state.performViewportCommand(CanvasViewportCommand(.actualSize))
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Actual Size")
                .accessibilityLabel("Actual Size")
                .focusable()
                .focused(focus, equals: .viewportReset)
                .accessibilityIdentifier("canvas.zoom.reset")

                Spacer(minLength: 4)

                Button("Fit Canvas") {
                    state.performViewportCommand(CanvasViewportCommand(.fitWidth))
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Fit to Canvas")
                .accessibilityLabel("Fit to Canvas")
                .focusable()
                .focused(focus, equals: .viewportFitCanvas)
                .accessibilityIdentifier("canvas.zoom.fitCanvas")

                Button("Fit Document") {
                    state.performViewportCommand(CanvasViewportCommand(.fitDocument))
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Fit to Document")
                .accessibilityLabel("Fit to Document")
                .focusable()
                .focused(focus, equals: .viewportFit)
                .accessibilityIdentifier("canvas.zoom.fit")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("canvas.viewport.zoomControls")

            if state.canvasRenderPlan?.authoredObjects.isEmpty == true
                || state.selectionOutsideActiveArtboard {
                HStack(spacing: 8) {
                    if state.canvasRenderPlan?.authoredObjects.isEmpty == true {
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
                    Spacer(minLength: 4)
                    if state.selectionOutsideActiveArtboard {
                        Button("Reveal Selection", systemImage: "viewfinder") {
                            state.revealSelection()
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.bordered)
                        .fixedSize()
                        .help("Reveal the selected Desktop geometry without moving it")
                        .accessibilityLabel("Reveal Selection")
                        .accessibilityIdentifier("canvas.selection.reveal")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.viewport.contextControls")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
    private var diagnosticPublicationGeneration: UInt64 = 0

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
        scheduleLifecycleDiagnostics(outcome: "attached")
    }

    func unbind(from candidate: NSWindow?) {
        guard let candidate, window === candidate else { return }
        lifecycle.unbind(from: WorkspaceTabRouterWindowIdentity(window: candidate))
        detachMonitor()
        window = nil
        presetControl = nil
        scheduleLifecycleDiagnostics(outcome: "detached")
    }

    fileprivate func registerPresetControl(_ control: FocusableViewportPresetPopUpButton) {
        presetControl = control
        scheduleLifecycleDiagnostics(outcome: "preset-attached")
    }

    fileprivate func unregisterPresetControl(_ control: FocusableViewportPresetPopUpButton) {
        guard presetControl === control else { return }
        presetControl = nil
        scheduleLifecycleDiagnostics(outcome: "preset-detached")
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

    /// Window/preset attachment occurs from NSViewRepresentable creation and
    /// reconciliation. Publishing its diagnostic synchronously there mutates
    /// the observed diagnostics probe during a SwiftUI update. Publish only
    /// the resulting lifecycle snapshot on the next event turn; key-routing
    /// diagnostics remain synchronous because they originate from a native
    /// keyboard event, not view construction.
    private func scheduleLifecycleDiagnostics(outcome: String) {
        diagnosticPublicationGeneration &+= 1
        let generation = diagnosticPublicationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.diagnosticPublicationGeneration == generation else { return }
            self.updateDiagnostics(outcome: outcome)
        }
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
        view.updateCommandState(state)
        configureRouter()
        return view
    }

    func updateNSView(_ view: WorkspaceWindowTabRouterHostView, context: Context) {
        view.router = router
        view.updateCommandState(state)
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
    weak var commandState: WorkspaceShellState?
    private weak var boundWindow: NSWindow?

    func updateCommandState(_ state: WorkspaceShellState) {
        if commandState === state {
            // SwiftUI can update this representable after AppKit has made the
            // window visible without moving the host view again. Reaffirm the
            // existing binding so it becomes the menu-tracking owner even
            // when the original viewDidMoveToWindow occurred before key/main
            // window state was established.
            if let boundWindow {
                WorkspaceCommandTargetRegistry.shared.bind(state, to: boundWindow)
                WorkspaceCommandTargetRegistry.shared.markActive(boundWindow)
            }
            return
        }
        if let boundWindow, let commandState {
            WorkspaceCommandTargetRegistry.shared.unbind(commandState, from: boundWindow)
        }
        commandState = state
        if let boundWindow {
            WorkspaceCommandTargetRegistry.shared.bind(state, to: boundWindow)
            WorkspaceCommandTargetRegistry.shared.markActive(boundWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let boundWindow, boundWindow !== window {
            router?.unbind(from: boundWindow)
            WorkspaceCommandTargetRegistry.shared.unbind(commandState, from: boundWindow)
        }
        boundWindow = window
        router?.bind(to: window)
        if let window, let commandState {
            WorkspaceCommandTargetRegistry.shared.bind(commandState, to: window)
        }
    }

    func detach() {
        if let boundWindow {
            router?.unbind(from: boundWindow)
            WorkspaceCommandTargetRegistry.shared.unbind(commandState, from: boundWindow)
        }
        boundWindow = nil
        router = nil
        commandState = nil
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
                ScrollView(.vertical) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Inspector selection summary")
                    .accessibilityValue("\(state.selectionSummary); \(state.transformGeometrySummary)")
                    .accessibilityIdentifier("inspector.selection.summary")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("inspector.selection.scroll")
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
            DesignInspectorFieldsView(state: state)
                .id(state.geometryInspectorSelectionKey)
        case .layout:
            Text(state.transformGeometrySummary)
                .monospacedDigit()
                .accessibilityLabel("Selection geometry")
                .accessibilityValue(state.transformGeometrySummary)
                .accessibilityIdentifier("inspector.transform.geometry")
            Text("Fixed geometry edits are authored values. Sizing modes, constraints, and automatic sizing remain unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryInspectorFieldsView(state: state)
                .id(state.geometryInspectorSelectionKey)
            if state.hasContainerLayoutSelection {
                Divider()
                ContainerLayoutInspectorView(state: state)
                    .id("container:\(state.geometryInspectorSelectionKey)")
            }
            if !state.selectionState.isEmpty {
                Divider()
                ResponsiveVisibilityInspectorView(state: state)
                    .id("visibility:\(state.geometryInspectorSelectionKey)")
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

/// Scene-local presentation drafts only. Canonical RGBA/opacity changes are
/// submitted as separate typed transactions so a cancelled picker/text draft
/// can never alter package, history, or editor overlays.
private struct DesignInspectorFieldsView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var hexFocused: Bool
    @FocusState private var opacityFocused: Bool
    @FocusState private var borderWidthFocused: Bool
    @FocusState private var radiusFocused: Bool
    @FocusState private var shadowFocused: Bool
    @FocusState private var typographyFocusedField: TypographyDraftField?
    @State private var hexDraft = ""
    @State private var opacityDraft = ""
    @State private var borderWidthDraft = ""
    @State private var radiusDraft = ""
    @State private var shadowDraft = ""
    @State private var fontFamilyDraft = ""
    @State private var fontSizeDraft = ""
    @State private var lineHeightDraft = ""
    @State private var trackingDraft = ""
    @State private var message: String?
    @State private var imageFocalXDraft = ""
    @State private var imageFocalYDraft = ""
    @State private var imageAltDraft = ""

    /// Includes the current revision and is used to reject a command queued
    /// from a control update after another transaction or selection has won.
    private var selectionContextKey: String { state.geometryInspectorSelectionKey }

    /// Intentionally excludes revision so the successful transaction can
    /// refresh its local draft strings after it advances the document.
    private var selectionIdentityKey: String {
        state.selectionState.orderedIDs.map(\.description).joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            imageControls
            Text("Appearance").font(.headline)
            let fill = state.designInspectorFillValue()
            let fillIsApplicable = !isUnavailable(fill)
            HStack(spacing: 8) {
                NativeDesignColorWell(
                    color: resolvedColor(fill),
                    isEnabled: fillIsApplicable,
                    accessibilityValue: fillAccessibility(fill),
                    accessibilityHint: fillIsApplicable
                        ? "Open the native color panel to commit a solid fill."
                        : unavailableHint(fill),
                    onCommit: { color in scheduleFillCommit(color, provenance: .picker) }
                )
                .frame(width: 48, height: 26)
                TextField("Hexadecimal fill", text: $hexDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!fillIsApplicable)
                    .focused($hexFocused)
                    .onSubmit { commitHex() }
                    .onChange(of: hexFocused) { old, current in
                        if old && !current { DispatchQueue.main.async { guard !hexFocused else { return }; commitHex() } }
                    }
                    .accessibilityLabel("Solid fill hexadecimal RGBA")
                    .accessibilityValue(fillAccessibility(fill))
                    .accessibilityHint(fillIsApplicable ? "Enter #RRGGBB or #RRGGBBAA and press Return to commit." : unavailableHint(fill))
                    .accessibilityIdentifier("inspector.design.fillHex")
                Button("Remove") {
                    scheduleFillCommit(nil, provenance: .picker)
                }
                    .disabled(!fillIsApplicable)
                    .accessibilityLabel("Remove solid fill")
                    .accessibilityHint(fillIsApplicable ? "Remove the authored fill without restoring a legacy default." : unavailableHint(fill))
                    .accessibilityIdentifier("inspector.design.fillRemove")
            }
            Text(provenanceText(fill))
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.design.fillProvenance")
            let opacity = state.designInspectorOpacityValue()
            let opacityIsApplicable = !isUnavailable(opacity)
            HStack(spacing: 8) {
                Text("Opacity").frame(width: 56, alignment: .leading)
                TextField("Opacity", text: $opacityDraft)
                    .textFieldStyle(.roundedBorder).monospacedDigit()
                    .disabled(!opacityIsApplicable)
                    .focused($opacityFocused)
                    .onSubmit { commitOpacity() }
                    .onChange(of: opacityFocused) { old, current in
                        if old && !current { DispatchQueue.main.async { guard !opacityFocused else { return }; commitOpacity() } }
                    }
                    .accessibilityLabel("Opacity percent")
                    .accessibilityValue(opacityAccessibility(opacity))
                    .accessibilityHint(opacityIsApplicable ? "Enter a value from 0 through 100 percent and press Return to commit." : unavailableHint(opacity))
                    .accessibilityIdentifier("inspector.design.opacity")
                NativeDesignOpacityStepper(
                    value: resolvedOpacityPercent(opacity),
                    isEnabled: opacityIsApplicable,
                    accessibilityValue: opacityAccessibility(opacity),
                    accessibilityHint: opacityIsApplicable
                        ? "Use the visible increment and decrement arrows to change opacity by one percent."
                        : unavailableHint(opacity),
                    onCommit: { percent in scheduleOpacityCommit(percent, provenance: .stepper) }
                )
                .frame(width: 22, height: 26)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("inspector.design.validation") }
            Text(state.lastDesignInspectorAnnouncement).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("inspector.design.announcement")
            FillLayerListInspectorView(state: state)
            typographyControls
            boxStyleControls
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Design appearance")
        .accessibilityIdentifier("inspector.design.fields")
        .onAppear { resetDrafts() }
        .onChange(of: selectionContextKey) { _, _ in
            // A selection command may run while the inspector is being
            // reconciled. Refresh local draft strings on the next event turn
            // and only for the current selection/revision, rather than
            // publishing view state during that reconciliation.
            scheduleDraftRefresh(for: selectionIdentityKey)
        }
        .onExitCommand { resetDrafts(); state.cancelDesignInspectorDraft() }
    }

    private func resolvedColor(_ value: DesignInspectorValue) -> CanonicalSolidColor {
        if case .single(let color, _) = value { return color }
        return .legacySurface
    }

    private func resolvedOpacityPercent(_ value: DesignInspectorOpacityValue) -> Double {
        if case .single(let opacity, _) = value { return opacity * 100 }
        return 100
    }
    private func resetDrafts() {
        if case .single(let image, _) = state.imageInspectorPresentation() {
            imageFocalXDraft = String(format: "%.0f", image.focalX * 100)
            imageFocalYDraft = String(format: "%.0f", image.focalY * 100)
            imageAltDraft = image.altText
        } else {
            imageFocalXDraft = ""; imageFocalYDraft = ""; imageAltDraft = ""
        }
        switch state.designInspectorFillValue() {
        case .single(let color, _): hexDraft = color.hexadecimalRGBA
        case .mixed: hexDraft = ""
        case .unavailable: hexDraft = ""
        }
        switch state.designInspectorOpacityValue() {
        case .single(let value, _): opacityDraft = String(format: "%.0f", value * 100)
        case .mixed, .unavailable: opacityDraft = ""
        }
        message = nil
        switch state.designInspectorBoxStyleValue() {
        case .single(let style, _):
            borderWidthDraft = style.border.map { String(format: "%.1f", $0.width) } ?? ""
            radiusDraft = style.cornerRadius.map { String(format: "%.1f", $0) } ?? ""
            if let shadow = style.shadow {
                shadowDraft = String(format: "%.0f, %.0f, %.0f, %.0f", shadow.offsetX, shadow.offsetY, shadow.blur, shadow.spread)
            } else { shadowDraft = "" }
        case .mixed, .unavailable:
            borderWidthDraft = ""; radiusDraft = ""; shadowDraft = ""
        }
        switch state.typographyInspectorValue() {
        case .single(let typography, _):
            fontFamilyDraft = typography.family
            fontSizeDraft = Self.formatTypographyNumber(typography.size)
            lineHeightDraft = Self.formatTypographyNumber(typography.lineHeight)
            trackingDraft = Self.formatTypographyNumber(typography.tracking)
        case .mixed, .unavailable:
            fontFamilyDraft = ""; fontSizeDraft = ""; lineHeightDraft = ""; trackingDraft = ""
        }
    }

    @ViewBuilder
    private var imageControls: some View {
        switch state.imageInspectorPresentation() {
        case .unavailable:
            EmptyView()
        case .mixed(let applicable, let skipped):
            VStack(alignment: .leading, spacing: 5) {
                Text("Image").font(.headline)
                Text("Mixed image properties across \(applicable) Image\(applicable == 1 ? "" : "s")\(skipped > 0 ? "; \(skipped) incompatible object\(skipped == 1 ? "" : "s") will be skipped" : "").")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.image.mixed")
            }
        case .single(let image, let asset):
            VStack(alignment: .leading, spacing: 8) {
                Text("Image").font(.headline)
                HStack(spacing: 8) {
                    Group {
                        if let data = state.imageAssetThumbnail(asset.id), let thumbnail = NSImage(data: data) {
                            Image(nsImage: thumbnail).resizable().scaledToFit()
                        } else {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .frame(width: 48, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.displayName).lineLimit(1)
                        Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Replace…") { state.replaceImageAsset(asset.id) }
                        .fixedSize()
                        .accessibilityIdentifier("inspector.image.replace")
                }
                Picker("Fit Mode", selection: Binding(
                    get: { image.fitMode },
                    set: { _ = state.commitImageInspectorEdit(.fit($0)) }
                )) {
                    ForEach(ImageFitMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.image.fit")
                HStack(spacing: 6) {
                    Text("Focal").frame(width: 42, alignment: .leading)
                    TextField("X %", text: $imageFocalXDraft)
                        .textFieldStyle(.roundedBorder).monospacedDigit()
                        .onSubmit { commitImageFocal() }
                        .accessibilityLabel("Image focal point X percent")
                        .accessibilityIdentifier("inspector.image.focalX")
                    TextField("Y %", text: $imageFocalYDraft)
                        .textFieldStyle(.roundedBorder).monospacedDigit()
                        .onSubmit { commitImageFocal() }
                        .accessibilityLabel("Image focal point Y percent")
                        .accessibilityIdentifier("inspector.image.focalY")
                    Button("Reset") {
                        imageFocalXDraft = "50"; imageFocalYDraft = "50"
                        _ = state.commitImageInspectorEdit(.focal(x: 0.5, y: 0.5))
                    }
                    .fixedSize().accessibilityIdentifier("inspector.image.focalReset")
                }
                TextField("Alternative text", text: $imageAltDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(image.isDecorative)
                    .onSubmit { _ = state.commitImageInspectorEdit(.altText(imageAltDraft)) }
                    .accessibilityLabel("Image alternative text")
                    .accessibilityIdentifier("inspector.image.alt")
                Toggle("Decorative image", isOn: Binding(
                    get: { image.isDecorative },
                    set: { _ = state.commitImageInspectorEdit(.decorative($0)) }
                ))
                .toggleStyle(.checkbox)
                .accessibilityHint("Decorative Images are ignored by authored-site assistive semantics; editor metadata remains available.")
                .accessibilityIdentifier("inspector.image.decorative")
                Text(state.lastImageInspectorAnnouncement)
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.image.status")
                Divider()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inspector.image.fields")
        }
    }

    private func commitImageFocal() {
        guard let x = Double(imageFocalXDraft), let y = Double(imageFocalYDraft),
              x.isFinite, y.isFinite, (0...100).contains(x), (0...100).contains(y) else {
            message = ImageInspectorError.invalidFocalPoint.localizedDescription
            return
        }
        if !state.commitImageInspectorEdit(.focal(x: x / 100, y: y / 100)) {
            message = state.imageInspectorFailure?.localizedDescription
        }
    }

    /// The command registry commits synchronously so undo/redo and renderer
    /// adoption remain immediate. Only the view-owned draft mirror waits for
    /// the next event turn; the identity key prevents an old edit from
    /// overwriting a newer selection's draft.
    private func scheduleDraftRefresh(for expectedSelectionKey: String) {
        DispatchQueue.main.async {
            guard selectionIdentityKey == expectedSelectionKey else { return }
            resetDrafts()
        }
    }

    /// Native ColorPicker and TextField bindings are evaluated while SwiftUI
    /// is reconciling their controls. Commit at the following main-event
    /// boundary, not from the binding setter itself. The exact document /
    /// selection context is checked before mutation, so a stale UI callback
    /// is neutral instead of applying to a later selection.
    private func scheduleFillCommit(
        _ color: CanonicalSolidColor?,
        provenance: DesignInspectorProvenance
    ) {
        let expectedContext = selectionContextKey
        let expectedSelection = selectionIdentityKey
        DispatchQueue.main.async {
            guard selectionContextKey == expectedContext else { return }
            guard state.commitDesignFill(color, provenance: provenance) else {
                message = state.designInspectorFailure?.localizedDescription
                return
            }
            scheduleDraftRefresh(for: expectedSelection)
        }
    }

    private func scheduleOpacityCommit(
        _ percent: Double,
        provenance: DesignInspectorProvenance
    ) {
        let expectedContext = selectionContextKey
        let expectedSelection = selectionIdentityKey
        DispatchQueue.main.async {
            guard selectionContextKey == expectedContext else { return }
            guard state.commitDesignOpacity(percent: percent, provenance: provenance) else {
                message = state.designInspectorFailure?.localizedDescription
                return
            }
            scheduleDraftRefresh(for: expectedSelection)
        }
    }
    private func commitHex() {
        guard !hexDraft.isEmpty else { message = DesignInspectorError.invalidColor.localizedDescription; return }
        guard let color = CanonicalSolidColor.parse(hexadecimal: hexDraft) else { message = DesignInspectorError.invalidColor.localizedDescription; return }
        scheduleFillCommit(color, provenance: .hexadecimal)
    }
    private func commitOpacity() {
        guard let value = Double(opacityDraft) else {
            message = DesignInspectorError.invalidOpacity.localizedDescription
            return
        }
        scheduleOpacityCommit(value, provenance: opacityFocused ? .keyboard : .focusLoss)
    }
    private func fillAccessibility(_ value: DesignInspectorValue) -> String { switch value { case .single(let color, let origin): "\(color.hexadecimalRGBA), \(origin == .authored ? "authored" : "defaulted")"; case .mixed: "Mixed values"; case .unavailable(let reason): reason } }
    private func opacityAccessibility(_ value: DesignInspectorOpacityValue) -> String { switch value { case .single(let opacity, let origin): "\(Int((opacity * 100).rounded())) percent, \(origin == .authored ? "authored" : "defaulted")"; case .mixed: "Mixed values"; case .unavailable(let reason): reason } }
    private func provenanceText(_ value: DesignInspectorValue) -> String { switch value { case .single(_, let origin): origin == .authored ? "Authored solid fill" : "Defaulted solid fill"; case .mixed: "Mixed fill values"; case .unavailable(let reason): reason } }
    private func isUnavailable(_ value: DesignInspectorValue) -> Bool {
        if case .unavailable = value { return true }
        return false
    }
    private func isUnavailable(_ value: DesignInspectorOpacityValue) -> Bool {
        if case .unavailable = value { return true }
        return false
    }
    private func unavailableHint(_ value: DesignInspectorValue) -> String {
        if case .unavailable(let reason) = value { return reason }
        return ""
    }
    private func unavailableHint(_ value: DesignInspectorOpacityValue) -> String {
        if case .unavailable(let reason) = value { return reason }
        return ""
    }

    private enum TypographyDraftField: Hashable { case family, size, lineHeight, tracking }

    @ViewBuilder private var typographyControls: some View {
        let value = state.typographyInspectorValue()
        let typography: CanonicalTypography? = if case .single(let style, _) = value { style } else { nil }
        let enabled: Bool = if case .unavailable = value { false } else { true }
        Divider()
        HStack {
            Text("Typography").font(.headline)
            Spacer()
            Button("Reset") { commitTypography(.reset, operation: "reset") }
                .disabled(!enabled)
                .accessibilityIdentifier("inspector.design.typography.reset")
        }
        TextField("Font family", text: $fontFamilyDraft)
            .textFieldStyle(.roundedBorder).disabled(!enabled)
            .focused($typographyFocusedField, equals: .family)
            .onSubmit { commitFontFamily() }
            .onChange(of: typographyFocusedField) { old, current in
                if old == .family && current != .family { commitFontFamily(provenance: .focusLoss) }
            }
            .accessibilityLabel("Font family")
            .accessibilityValue(typographyAccessibility(value, component: "family"))
            .accessibilityHint(typographyHint(value))
            .accessibilityIdentifier("inspector.design.typography.family")
        HStack(spacing: 7) {
            Picker("Weight", selection: Binding(
                get: { typography?.weight ?? .regular },
                set: { commitTypography(.weight($0), operation: "weight", provenance: .picker) }
            )) {
                ForEach(CanonicalFontWeight.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
            }
            .disabled(!enabled)
            .accessibilityIdentifier("inspector.design.typography.weight")
            Picker("Alignment", selection: Binding(
                get: { typography?.alignment ?? .leading },
                set: { commitTypography(.alignment($0), operation: "alignment", provenance: .picker) }
            )) {
                ForEach(CanonicalTextAlignment.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
            }
            .labelsHidden().disabled(!enabled)
            .accessibilityLabel("Paragraph alignment")
            .accessibilityIdentifier("inspector.design.typography.alignment")
        }
        HStack(alignment: .top, spacing: 7) {
            typographyNumberField("Size", text: $fontSizeDraft, field: .size, value: typography?.size)
            typographyNumberField("Line height", text: $lineHeightDraft, field: .lineHeight, value: typography?.lineHeight)
            typographyNumberField("Tracking", text: $trackingDraft, field: .tracking, value: typography?.tracking)
        }
        Text(typographyProvenance(value))
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityIdentifier("inspector.design.typography.status")
        if let fallback = state.typographyResolutionStatus {
            Text(fallback).font(.caption2).foregroundStyle(.orange)
                .accessibilityIdentifier("inspector.design.typography.fallback")
        }
    }

    private func typographyNumberField(
        _ label: String,
        text: Binding<String>,
        field: TypographyDraftField,
        value: Double?
    ) -> some View {
        let available: Bool = if case .unavailable = state.typographyInspectorValue() { false } else { true }
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder).monospacedDigit().disabled(!available)
                .focused($typographyFocusedField, equals: field)
                .onSubmit { commitTypographyNumber(field) }
                .onChange(of: typographyFocusedField) { old, current in
                    if old == field && current != field { commitTypographyNumber(field, provenance: .focusLoss) }
                }
                .accessibilityLabel(label)
                .accessibilityValue(value.map(Self.formatTypographyNumber) ?? "Mixed or unavailable")
                .accessibilityIdentifier("inspector.design.typography.\(String(describing: field))")
        }
    }

    private func commitFontFamily(provenance: DesignInspectorProvenance = .keyboard) {
        let value = fontFamilyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value == fontFamilyDraft else {
            message = TypographyCommandError.invalidValue.localizedDescription; return
        }
        commitTypography(.family(value), operation: "font family", provenance: provenance)
    }

    private func commitTypographyNumber(_ field: TypographyDraftField, provenance: DesignInspectorProvenance = .keyboard) {
        let draft: String = switch field { case .size: fontSizeDraft; case .lineHeight: lineHeightDraft; case .tracking: trackingDraft; case .family: fontFamilyDraft }
        guard let number = Double(draft), number.isFinite else {
            message = TypographyCommandError.invalidValue.localizedDescription; return
        }
        let edit: TypographyEdit = switch field { case .size: .size(number); case .lineHeight: .lineHeight(number); case .tracking: .tracking(number); case .family: .family(draft) }
        commitTypography(edit, operation: String(describing: field), provenance: provenance)
    }

    private func commitTypography(
        _ edit: TypographyEdit,
        operation: String,
        provenance: DesignInspectorProvenance = .keyboard
    ) {
        guard state.commitTypography(edit, operation: operation, provenance: provenance) else {
            message = state.lastDesignInspectorAnnouncement
            return
        }
        message = nil
        scheduleDraftRefresh(for: selectionIdentityKey)
    }

    private static func formatTypographyNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func typographyHint(_ value: TypographyInspectorValue) -> String {
        if case .unavailable(let reason) = value { return reason }
        return "Edit typography for the selected plain Text object. Missing fonts use the system fallback without changing the authored family."
    }

    private func typographyAccessibility(_ value: TypographyInspectorValue, component: String) -> String {
        switch value {
        case .single(let style, let origin):
            let detail = component == "family" ? style.family : "Typography"
            return "\(detail), \(origin == .authored ? "authored" : "defaulted")"
        case .mixed: return "Mixed values"
        case .unavailable(let reason): return reason
        }
    }

    private func typographyProvenance(_ value: TypographyInspectorValue) -> String {
        switch value {
        case .single(let style, let origin): return "\(origin == .authored ? "Authored" : "Defaulted") · \(style.family) · \(Self.formatTypographyNumber(style.size)) pt"
        case .mixed(let applicable, let skipped): return "Mixed typography · \(applicable) editable, \(skipped) skipped"
        case .unavailable(let reason): return reason
        }
    }

    @ViewBuilder private var boxStyleControls: some View {
        let value = state.designInspectorBoxStyleValue()
        let style: CanonicalBoxStyle? = if case .single(let style, _) = value { style } else { nil }
        let enabled: Bool = if case .unavailable = value { false } else { true }
        Divider()
        Text("Border, Radius & Shadow").font(.headline)
        HStack(spacing: 7) {
            NativeDesignColorWell(
                color: style?.border?.color ?? CanonicalSolidColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1),
                isEnabled: enabled,
                accessibilityValue: style?.border?.color.hexadecimalRGBA ?? "No border",
                accessibilityHint: "Choose the authored border color.",
                accessibilityIdentifier: "inspector.design.borderColor",
                accessibilityLabel: "Border color",
                onCommit: { color in
                    let width = style?.border?.width ?? 1
                    _ = state.commitDesignBoxStyle(.border(.init(color: color, width: width, style: style?.border?.style ?? .solid)), operation: "border", provenance: .picker)
                }
            ).frame(width: 38, height: 24)
            TextField("Border width", text: $borderWidthDraft)
                .textFieldStyle(.roundedBorder).focused($borderWidthFocused).disabled(!enabled)
                .onSubmit { commitBorder(style) }
                .onChange(of: borderWidthFocused) { old, current in if old && !current { commitBorder(style, provenance: .focusLoss) } }
                .accessibilityLabel("Border width in points")
                .accessibilityIdentifier("inspector.design.borderWidth")
            Picker("Style", selection: Binding(
                get: { style?.border?.style ?? .solid },
                set: { newValue in
                    let border = CanonicalBorder(color: style?.border?.color ?? .legacySurface, width: style?.border?.width ?? 1, style: newValue)
                    _ = state.commitDesignBoxStyle(.border(border), operation: "border style", provenance: .picker)
                }
            )) { ForEach(CanonicalBorderStyle.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) } }
                .labelsHidden().disabled(!enabled)
                .accessibilityLabel("Border style")
                .accessibilityIdentifier("inspector.design.borderStyle")
            Button(style?.border == nil ? "Add" : "Remove") {
                if style?.border == nil {
                    _ = state.commitDesignBoxStyle(.border(.init(color: .init(red: 0.18, green: 0.20, blue: 0.24, alpha: 1), width: 1, style: .solid)), operation: "border", provenance: .picker)
                } else { _ = state.commitDesignBoxStyle(.border(nil), operation: "border removal", provenance: .picker) }
                resetDrafts()
            }.disabled(!enabled).accessibilityIdentifier("inspector.design.borderToggle")
        }
        HStack(spacing: 7) {
            Text("Radius").frame(width: 52, alignment: .leading)
            TextField("Uniform radius", text: $radiusDraft)
                .textFieldStyle(.roundedBorder).focused($radiusFocused).disabled(!enabled)
                .onSubmit { commitRadius() }
                .onChange(of: radiusFocused) { old, current in if old && !current { commitRadius(provenance: .focusLoss) } }
                .accessibilityLabel("Uniform corner radius in points")
                .accessibilityIdentifier("inspector.design.cornerRadius")
            Button(style?.cornerRadius == nil ? "Add" : "Remove") {
                _ = state.commitDesignBoxStyle(.cornerRadius(style?.cornerRadius == nil ? 8 : nil), operation: "corner radius", provenance: .picker)
                resetDrafts()
            }.disabled(!enabled).accessibilityIdentifier("inspector.design.cornerRadiusToggle")
        }
        HStack(spacing: 7) {
            NativeDesignColorWell(
                color: style?.shadow?.color ?? CanonicalSolidColor(red: 0, green: 0, blue: 0, alpha: 0.25),
                isEnabled: enabled,
                accessibilityValue: style?.shadow?.color.hexadecimalRGBA ?? "No shadow",
                accessibilityHint: "Choose the authored shadow color.",
                accessibilityIdentifier: "inspector.design.shadowColor",
                accessibilityLabel: "Shadow color",
                onCommit: { color in
                    let old = style?.shadow ?? .init(color: color, offsetX: 0, offsetY: 8, blur: 18, spread: 0)
                    _ = state.commitDesignBoxStyle(.shadow(.init(color: color, offsetX: old.offsetX, offsetY: old.offsetY, blur: old.blur, spread: old.spread)), operation: "shadow", provenance: .picker)
                }
            ).frame(width: 38, height: 24)
            TextField("X, Y, Blur, Spread", text: $shadowDraft)
                .textFieldStyle(.roundedBorder).focused($shadowFocused).disabled(!enabled)
                .onSubmit { commitShadow(style) }
                .onChange(of: shadowFocused) { old, current in if old && !current { commitShadow(style, provenance: .focusLoss) } }
                .accessibilityLabel("Shadow X, Y, blur, and spread in points")
                .accessibilityIdentifier("inspector.design.shadowValues")
            Button(style?.shadow == nil ? "Add" : "Remove") {
                let next: CanonicalShadow? = style?.shadow == nil ? .init(color: .init(red: 0, green: 0, blue: 0, alpha: 0.25), offsetX: 0, offsetY: 8, blur: 18, spread: 0) : nil
                _ = state.commitDesignBoxStyle(.shadow(next), operation: "shadow", provenance: .picker)
                resetDrafts()
            }.disabled(!enabled).accessibilityIdentifier("inspector.design.shadowToggle")
        }
        switch value {
        case .mixed(let applicable, let skipped): Text("Mixed box appearance across \(applicable) compatible objects; \(skipped) incompatible unchanged.").font(.caption2).foregroundStyle(.secondary)
        case .unavailable(let reason): Text(reason).font(.caption2).foregroundStyle(.secondary)
        case .single(_, let origin): Text(origin == .authored ? "Authored box appearance" : "Defaulted box appearance").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func commitBorder(_ style: CanonicalBoxStyle?, provenance: DesignInspectorProvenance = .keyboard) {
        guard let width = Double(borderWidthDraft), width.isFinite, (0...100).contains(width) else { message = DesignBoxStyleError.invalidValue.localizedDescription; return }
        let border = CanonicalBorder(color: style?.border?.color ?? .init(red: 0.18, green: 0.20, blue: 0.24, alpha: 1), width: width, style: style?.border?.style ?? .solid)
        guard state.commitDesignBoxStyle(.border(width == 0 ? nil : border), operation: "border", provenance: provenance) else { message = state.lastDesignInspectorAnnouncement; return }
        resetDrafts()
    }

    private func commitRadius(provenance: DesignInspectorProvenance = .keyboard) {
        guard let radius = Double(radiusDraft), radius.isFinite, (0...10_000).contains(radius) else { message = DesignBoxStyleError.invalidValue.localizedDescription; return }
        guard state.commitDesignBoxStyle(.cornerRadius(radius), operation: "corner radius", provenance: provenance) else { message = state.lastDesignInspectorAnnouncement; return }
        resetDrafts()
    }

    private func commitShadow(_ style: CanonicalBoxStyle?, provenance: DesignInspectorProvenance = .keyboard) {
        let values = shadowDraft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.compactMap(Double.init)
        guard values.count == 4 else { message = DesignBoxStyleError.invalidValue.localizedDescription; return }
        let shadow = CanonicalShadow(color: style?.shadow?.color ?? .init(red: 0, green: 0, blue: 0, alpha: 0.25), offsetX: values[0], offsetY: values[1], blur: values[2], spread: values[3])
        guard shadow.isValid, state.commitDesignBoxStyle(.shadow(shadow), operation: "shadow", provenance: provenance) else { message = state.lastDesignInspectorAnnouncement; return }
        resetDrafts()
    }
}

/// Production AppKit bridge for the system colour experience.  It remains a
/// real `NSColorWell`/standard `NSColorPanel`, but makes its role, value, and
/// press semantics stable for VoiceOver, Full Keyboard Access, and UI tests.
/// The bridge has no knowledge of automation and owns no canonical style.
struct NativeDesignColorWell: NSViewRepresentable {
    let color: CanonicalSolidColor
    let isEnabled: Bool
    let accessibilityValue: String
    let accessibilityHint: String
    var accessibilityIdentifier = "inspector.design.fillPicker"
    var accessibilityLabel = "Solid fill color"
    let onCommit: (CanonicalSolidColor) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit) }

    func makeNSView(context: Context) -> AccessibleDesignColorWell {
        let well = AccessibleDesignColorWell(frame: .zero)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.focusRingType = .default
        well.setAccessibilityIdentifier(accessibilityIdentifier)
        well.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.attach(well)
        return well
    }

    func updateNSView(_ well: AccessibleDesignColorWell, context: Context) {
        context.coordinator.onCommit = onCommit
        well.isEnabled = isEnabled
        well.setAccessibilityIdentifier(accessibilityIdentifier)
        well.setAccessibilityLabel(accessibilityLabel)
        well.setAccessibilityValue(accessibilityValue)
        well.setAccessibilityHelp(accessibilityHint)
        let next = NSColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
        if !well.color.isEqual(next) {
            context.coordinator.isSynchronizing = true
            well.color = next
            context.coordinator.isSynchronizing = false
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onCommit: (CanonicalSolidColor) -> Void
        var isSynchronizing = false

        init(onCommit: @escaping (CanonicalSolidColor) -> Void) {
            self.onCommit = onCommit
        }

        func attach(_ well: AccessibleDesignColorWell) {
            well.onPanelDeactivated = { [weak well] in
                // The standard Colors panel can leave its well as first
                // responder after it closes. Relinquish only that responder;
                // a subsequent genuine click/Tab chooses the next control.
                guard let well, well.window?.firstResponder === well else { return }
                well.window?.makeFirstResponder(nil)
            }
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            guard !isSynchronizing,
                  let rgb = sender.color.usingColorSpace(.deviceRGB) else { return }
            let color = CanonicalSolidColor(
                red: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: rgb.alphaComponent
            )
            guard color.isValid else { return }
            onCommit(color)
        }
    }
}

final class AccessibleDesignColorWell: NSColorWell {
    var onPanelDeactivated: (() -> Void)?

    override var acceptsFirstResponder: Bool { isEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        activate(true)
        return true
    }

    override func deactivate() {
        super.deactivate()
        onPanelDeactivated?()
    }
}

/// Production `NSStepper` bridge.  Both visible arrow clicks and standard
/// accessibility increment/decrement actions execute its target-action, so
/// every mutation continues through the Design Inspector command registry.
private struct NativeDesignOpacityStepper: NSViewRepresentable {
    let value: Double
    let isEnabled: Bool
    let accessibilityValue: String
    let accessibilityHint: String
    let onCommit: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit) }

    func makeNSView(context: Context) -> AccessibleDesignOpacityStepper {
        let stepper = AccessibleDesignOpacityStepper(frame: .zero)
        stepper.minValue = 0
        stepper.maxValue = 100
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.autorepeat = true
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.valueChanged(_:))
        stepper.focusRingType = .default
        stepper.setAccessibilityIdentifier("inspector.design.opacityStepper")
        stepper.setAccessibilityLabel("Adjust opacity percent")
        return stepper
    }

    func updateNSView(_ stepper: AccessibleDesignOpacityStepper, context: Context) {
        context.coordinator.onCommit = onCommit
        stepper.isEnabled = isEnabled
        stepper.setAccessibilityValue(accessibilityValue)
        stepper.setAccessibilityHelp(accessibilityHint)
        if abs(stepper.doubleValue - value) > 0.000_001 {
            context.coordinator.isSynchronizing = true
            stepper.doubleValue = value
            context.coordinator.isSynchronizing = false
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onCommit: (Double) -> Void
        var isSynchronizing = false

        init(onCommit: @escaping (Double) -> Void) { self.onCommit = onCommit }

        @objc func valueChanged(_ sender: NSStepper) {
            guard !isSynchronizing else { return }
            onCommit(sender.doubleValue)
        }
    }
}

private final class AccessibleDesignOpacityStepper: NSStepper {
    override var acceptsFirstResponder: Bool { isEnabled }

    override func mouseDown(with event: NSEvent) {
        // Make an ordinary visible click establish the native first responder
        // before AppKit processes the arrow hit region. This preserves normal
        // mouse behavior and makes subsequent standard keyboard adjustment
        // belong to this scene-local control.
        if isEnabled { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }

    /// `NSStepper` is a genuine native control, but its arrow-key handling is
    /// not consistently adopted when embedded through SwiftUI on current
    /// macOS releases. Keep the visible arrows and target-action semantics,
    /// while making the focused production control operable through the
    /// standard Up/Down keyboard convention used by VoiceOver and Full
    /// Keyboard Access.
    override func keyDown(with event: NSEvent) {
        guard isEnabled else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 126: // Up Arrow
            _ = accessibilityPerformIncrement()
        case 125: // Down Arrow
            _ = accessibilityPerformDecrement()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        adjustAccessibilityValue(by: increment)
    }

    override func accessibilityPerformDecrement() -> Bool {
        adjustAccessibilityValue(by: -increment)
    }

    private func adjustAccessibilityValue(by delta: Double) -> Bool {
        guard isEnabled else { return false }
        let next = min(maxValue, max(minValue, doubleValue + delta))
        guard abs(next - doubleValue) > 0.000_001 else { return false }
        doubleValue = next
        _ = sendAction(action, to: target)
        NSAccessibility.post(element: self, notification: .valueChanged)
        return true
    }
}

/// Scene-local string drafts for canonical fixed-geometry fields. The view is
/// intentionally the only owner of incomplete locale input; `WorkspaceShellState`
/// receives one validated number only at the native commit boundary.
private struct GeometryInspectorFieldsView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var focusedField: GeometryInspectorField?
    @State private var drafts: [GeometryInspectorField: String] = [:]
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Geometry").font(.headline)
            ForEach(GeometryInspectorField.allCases, id: \.self) { field in
                fieldRow(field)
            }
            HStack(spacing: 8) {
                Text("Breakpoint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.viewportPreset.title)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("inspector.layout.breakpoint")
            }
            if state.viewportPreset != .desktop {
                Button("Reset \(state.viewportPreset.title) Overrides") {
                    _ = state.resetGeometryOverrides(provenance: .pointer)
                    restoreDrafts()
                }
                .disabled(!state.hasGeometryOverridesAtCurrentBreakpoint)
                .accessibilityLabel("Reset \(state.viewportPreset.title) geometry overrides")
                .accessibilityHint("Remove authored geometry at this breakpoint and inherit Desktop values.")
                .accessibilityIdentifier("inspector.layout.resetBreakpointOverrides")
            }
            if let applicability = state.geometryInspectorApplicabilityMessage {
                Text(applicability)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.layout.applicability")
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("inspector.layout.validation")
            }
            Text(state.lastGeometryInspectorAnnouncement)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.layout.announcement")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout geometry")
        .accessibilityIdentifier("inspector.layout.geometryFields")
        .onExitCommand {
            guard focusedField != nil else { return }
            restoreDrafts()
            focusedField = nil
            state.cancelGeometryInspectorDraft()
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: GeometryInspectorField) -> some View {
        let value = state.geometryInspectorValue(for: field)
        let availability = state.geometryInspectorAvailability(for: field)
        HStack(spacing: 8) {
            Text(field.title)
                .frame(width: 44, alignment: .leading)
            TextField(field.title, text: draftBinding(for: field, value: value))
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focusedField, equals: field)
                .onSubmit { commit(field, provenance: .keyboard) }
                .onChange(of: focusedField) { previous, current in
                    if previous == field, current != field {
                        // FocusState changes are applied while SwiftUI is
                        // reconciling this view. Defer only to the next main
                        // event turn so the native focus transfer completes
                        // before the atomic model publication; this is not a
                        // timer or retry, and the typed identity check keeps a
                        // stale selection/document state neutral.
                        DispatchQueue.main.async {
                            guard focusedField != field else { return }
                            commit(field, provenance: .pointer)
                        }
                    }
                }
                .disabled(!availability.isEnabled)
                .accessibilityLabel("\(field.title) geometry")
                .accessibilityValue(accessibilityValue(for: value, field: field))
                .accessibilityHint(availability.disabledReason ?? "Enter a finite value and press Return to commit. Escape restores the committed value.")
                .accessibilityIdentifier("inspector.layout.\(field.rawValue)")
            provenanceLabel(for: value, field: field)
                .frame(width: 104, alignment: .trailing)
        }
    }

    private func draftBinding(
        for field: GeometryInspectorField,
        value: GeometryInspectorValue
    ) -> Binding<String> {
        Binding(
            get: { drafts[field] ?? displayValue(for: value) },
            set: {
                drafts[field] = $0
                validationMessage = nil
            }
        )
    }

    @ViewBuilder
    private func provenanceLabel(for value: GeometryInspectorValue, field: GeometryInspectorField) -> some View {
        switch value {
        case .single(_, let origin):
            Text(state.geometryInspectorResponsiveSource(for: field)
                 ?? (origin == .authored ? "Authored" : "Default"))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel(state.geometryInspectorResponsiveSource(for: field)
                    ?? (origin == .authored ? "Authored value" : "Defaulted value"))
        case .mixed:
            Text("Mixed").font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Mixed values")
        case .unavailable:
            Text("Unavailable").font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Unavailable")
        }
    }

    private func displayValue(for value: GeometryInspectorValue) -> String {
        switch value {
        case .single(let value, _): GeometryInspectorNumberParser.format(value)
        case .mixed, .unavailable: ""
        }
    }

    private func accessibilityValue(for value: GeometryInspectorValue, field: GeometryInspectorField) -> String {
        switch value {
        case .single(let value, let origin):
            "\(GeometryInspectorNumberParser.format(value)); \(state.geometryInspectorResponsiveSource(for: field) ?? (origin == .authored ? "authored" : "defaulted"))"
        case .mixed: "Mixed values"
        case .unavailable(let reason): reason
        }
    }

    private func commit(_ field: GeometryInspectorField, provenance: GeometryInspectorProvenance) {
        let text = drafts[field] ?? displayValue(for: state.geometryInspectorValue(for: field))
        switch GeometryInspectorNumberParser.parse(text) {
        case .success(let value):
            guard GeometryInspectorCommandRegistry.isValid(value, for: field) else {
                validationMessage = "\(field.title) must be finite and within the supported range\(field.requiresPositiveValue ? ", with a minimum of 1" : "")."
                return
            }
            guard state.commitGeometryInspectorValue(value, field: field, provenance: provenance) else {
                validationMessage = state.geometryInspectorFailure?.localizedDescription
                return
            }
            drafts.removeValue(forKey: field)
            validationMessage = nil
        case .failure(let error):
            validationMessage = error.localizedDescription
        }
    }

    private func restoreDrafts() {
        drafts.removeAll()
        validationMessage = nil
    }
}

/// Scene-local drafts and native controls for canonical Section/Stack/Grid
/// layout properties. Every committed path converges on the typed registry in
/// `WorkspaceShellState`; incomplete strings never enter the document model.
private struct ContainerLayoutInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var focusedField: ContainerLayoutField?
    @State private var drafts: [ContainerLayoutField: String] = [:]
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Container Layout").font(.headline)
                Spacer()
                Text(state.viewportPreset.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Container layout values for \(state.viewportPreset.title)")
            }
            numericRow(.padding)
            numericRow(.gap)
            numericRow(.columns)
            axisRow
            alignmentRow
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("inspector.layout.container.validation")
            }
            Text(state.currentContainerLayoutAnnouncement)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.layout.container.announcement")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Container layout")
        .accessibilityIdentifier("inspector.layout.container")
        .onExitCommand {
            guard let cancelledField = focusedField else { return }
            drafts.removeAll()
            validationMessage = nil
            focusedField = nil
            state.cancelContainerLayoutDraft(field: cancelledField)
        }
    }

    @ViewBuilder
    private func numericRow(_ field: ContainerLayoutField) -> some View {
        let selection = state.containerLayoutValue(for: field)
        let availability = state.containerLayoutAvailability(for: field)
        if case .unavailable = selection {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(field.title).frame(width: 62, alignment: .leading)
                    TextField(field.title, text: numericBinding(field, selection: selection))
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        // Keep the intrinsic-width Reset action inside the
                        // practical Inspector width. An unconstrained native
                        // text field otherwise consumes the logical trailing
                        // width when a 1100-point window is clipped by a
                        // narrower display, pushing Reset offscreen.
                        .frame(minWidth: 64, maxWidth: 120)
                        .focused($focusedField, equals: field)
                        .disabled(!availability.isEnabled)
                        .onSubmit { commitNumeric(field, provenance: .keyboard) }
                        .onChange(of: focusedField) { previous, current in
                            if previous == field, current != field {
                                DispatchQueue.main.async {
                                    guard focusedField != field else { return }
                                    commitNumeric(field, provenance: .focusLoss)
                                }
                            }
                        }
                        .accessibilityLabel("Container \(field.title.lowercased())")
                        .accessibilityValue(accessibilityValue(selection, field: field))
                        .accessibilityHint(availability.disabledReason
                            ?? "Enter a value and press Return. Escape cancels the draft.")
                        .accessibilityIdentifier("inspector.layout.container.\(field.rawValue)")
                    Button("Reset") { reset(field) }
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .disabled(!availability.isEnabled || !canReset(selection, field: field))
                        .accessibilityLabel(state.viewportPreset == .desktop
                            ? "Reset \(field.title) to default" : "Reset \(field.title) override")
                        .accessibilityIdentifier("inspector.layout.container.\(field.rawValue).reset")
                }
                subsetLabel(selection)
                sourceLabel(field)
            }
        }
    }

    private var axisRow: some View {
        let selection = state.containerLayoutValue(for: .axis)
        let availability = state.containerLayoutAvailability(for: .axis)
        return Group {
            if case .unavailable = selection {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Picker("Direction", selection: axisBinding(selection)) {
                            ForEach(ContainerLayoutAxis.allCases, id: \.self) { axis in
                                Text(axis.rawValue.capitalized).tag(axis as ContainerLayoutAxis?)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!availability.isEnabled)
                        .accessibilityLabel("Stack direction")
                        .accessibilityValue(accessibilityValue(selection, field: .axis))
                        .accessibilityIdentifier("inspector.layout.container.axis")
                        Button("Reset") { reset(.axis) }
                            .buttonStyle(.borderless)
                            .fixedSize()
                            .disabled(!availability.isEnabled || !canReset(selection, field: .axis))
                            .accessibilityLabel("Reset Direction to default")
                            .accessibilityIdentifier("inspector.layout.container.axis.reset")
                    }
                    subsetLabel(selection)
                    sourceLabel(.axis)
                }
            }
        }
    }

    private var alignmentRow: some View {
        let selection = state.containerLayoutValue(for: .alignment)
        let availability = state.containerLayoutAvailability(for: .alignment)
        return Group {
            if case .unavailable = selection {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Alignment", selection: alignmentBinding(selection)) {
                        ForEach(ContainerLayoutAlignment.allCases, id: \.self) { alignment in
                            Text(alignment.rawValue.capitalized).tag(alignment as ContainerLayoutAlignment?)
                        }
                    }
                    .accessibilityLabel("Stack cross-axis alignment")
                    .disabled(!availability.isEnabled)
                    .accessibilityValue(accessibilityValue(selection, field: .alignment))
                    .accessibilityIdentifier("inspector.layout.container.alignment")
                    HStack {
                        subsetLabel(selection)
                        Spacer()
                        Button("Reset") { reset(.alignment) }
                            .buttonStyle(.borderless)
                            .fixedSize()
                            .disabled(!availability.isEnabled || !canReset(selection, field: .alignment))
                            .accessibilityLabel("Reset Alignment to default")
                            .accessibilityIdentifier("inspector.layout.container.alignment.reset")
                    }
                    sourceLabel(.alignment)
                }
            }
        }
    }

    private func numericBinding(_ field: ContainerLayoutField, selection: ContainerLayoutInspectorValue) -> Binding<String> {
        Binding(
            get: { drafts[field] ?? displayNumber(selection) },
            set: { drafts[field] = $0; validationMessage = nil }
        )
    }

    private func axisBinding(_ selection: ContainerLayoutInspectorValue) -> Binding<ContainerLayoutAxis?> {
        Binding(
            get: {
                guard case .single(.axis(let value), _, _, _) = selection else { return nil }
                return value
            },
            set: { value in
                guard let value else { return }
                commit(.axis, value: .axis(value), operation: "direction", provenance: .picker)
            }
        )
    }

    private func alignmentBinding(_ selection: ContainerLayoutInspectorValue) -> Binding<ContainerLayoutAlignment?> {
        Binding(
            get: {
                guard case .single(.alignment(let value), _, _, _) = selection else { return nil }
                return value
            },
            set: { value in
                guard let value else { return }
                commit(.alignment, value: .alignment(value), operation: "alignment", provenance: .picker)
            }
        )
    }

    private func commitNumeric(
        _ field: ContainerLayoutField,
        provenance: ContainerLayoutProvenance
    ) {
        let selection = state.containerLayoutValue(for: field)
        let text = drafts[field] ?? displayNumber(selection)
        switch GeometryInspectorNumberParser.parse(text) {
        case .success(let value):
            let canonical = ContainerLayoutValue.number(value)
            do { try ContainerLayoutCommandRegistry.validate(canonical, field: field) }
            catch {
                validationMessage = field == .columns
                    ? "Columns must be a whole number from 1 through 64."
                    : "\(field.title) must be from 0 through 10,000."
                return
            }
            commit(field, value: canonical, operation: field.title.lowercased(), provenance: provenance)
        case .failure:
            validationMessage = "Enter a complete finite number for \(field.title.lowercased())."
        }
    }

    private func commit(
        _ field: ContainerLayoutField,
        value: ContainerLayoutValue,
        operation: String,
        provenance: ContainerLayoutProvenance
    ) {
        if state.commitContainerLayout(field: field, value: value, provenance: provenance) {
            drafts.removeValue(forKey: field)
            validationMessage = nil
        } else {
            validationMessage = state.containerLayoutFailure?.localizedDescription
                ?? "The \(operation) edit could not commit."
        }
    }

    private func reset(_ field: ContainerLayoutField) {
        if state.commitContainerLayout(field: field, value: nil, provenance: .pointer) {
            drafts.removeValue(forKey: field)
            validationMessage = nil
        } else {
            validationMessage = state.containerLayoutFailure?.localizedDescription
        }
    }

    private func displayNumber(_ selection: ContainerLayoutInspectorValue) -> String {
        guard case .single(.number(let value), _, _, _) = selection else { return "" }
        return GeometryInspectorNumberParser.format(value)
    }

    private func accessibilityValue(
        _ selection: ContainerLayoutInspectorValue,
        field: ContainerLayoutField
    ) -> String {
        switch selection {
        case .single(let value, let origin, let applicable, let skipped):
            let display: String = switch value {
            case .number(let number): GeometryInspectorNumberParser.format(number)
            case .axis(let axis): axis.rawValue
            case .alignment(let alignment): alignment.rawValue
            }
            let subset = skipped == 0 ? "" : "; applies to \(applicable), skips \(skipped)"
            let source = state.containerLayoutResponsiveSource(for: field).map { "; \($0)" } ?? ""
            return "\(display); \(origin == .authored ? "authored" : "defaulted")\(source)\(subset)"
        case .mixed(let applicable, let skipped):
            return "Mixed values; applies to \(applicable), skips \(skipped)"
        case .unavailable(let reason): return reason
        }
    }

    @ViewBuilder
    private func subsetLabel(_ selection: ContainerLayoutInspectorValue) -> some View {
        switch selection {
        case .single(_, let origin, let applicable, let skipped):
            Text(subsetText(origin: origin, applicable: applicable, skipped: skipped))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .mixed(let applicable, let skipped):
            Text("Mixed · \(applicable) applicable\(skipped > 0 ? " · \(skipped) skipped" : "")")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .unavailable:
            EmptyView()
        }
    }

    private func subsetText(origin: PropertyOrigin, applicable: Int, skipped: Int) -> String {
        let provenance = origin == .authored ? "Authored" : "Default"
        guard applicable > 1 || skipped > 0 else { return provenance }
        return "\(provenance) · \(applicable) applicable\(skipped > 0 ? " · \(skipped) skipped" : "")"
    }

    @ViewBuilder
    private func sourceLabel(_ field: ContainerLayoutField) -> some View {
        if let source = state.containerLayoutResponsiveSource(for: field) {
            Text(source).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func canReset(_ selection: ContainerLayoutInspectorValue, field: ContainerLayoutField) -> Bool {
        if state.viewportPreset != .desktop { return state.hasContainerLayoutOverride(field) }
        switch selection {
        case .single(_, let origin, _, _): return origin == .authored
        case .mixed: return true
        case .unavailable: return false
        }
    }
}

private struct ResponsiveVisibilityInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Breakpoint Visibility").font(.headline)
            switch state.responsiveVisibilityValue {
            case .single(let visible, let origin, let source, let applicable, let skipped):
                Toggle("Visible at \(state.viewportPreset.title)", isOn: Binding(
                    get: { visible },
                    set: { _ = state.commitResponsiveVisibility($0, provenance: .pointer) }
                ))
                .accessibilityValue("\(visible ? "Visible" : "Hidden"); \(source.label(at: state.viewportPreset.responsiveBreakpoint)); \(origin.rawValue)")
                .accessibilityIdentifier("inspector.layout.visibility")
                Text("\(source.label(at: state.viewportPreset.responsiveBreakpoint)) · \(origin.rawValue.capitalized) · \(applicable) applicable\(skipped > 0 ? " · \(skipped) skipped" : "")")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            case .mixed(let applicable, let skipped):
                Text("Visible at \(state.viewportPreset.title): Mixed")
                    .accessibilityIdentifier("inspector.layout.visibility.mixed")
                HStack(spacing: 8) {
                    Button("Show") {
                        _ = state.commitResponsiveVisibility(true, provenance: .pointer)
                    }
                    .accessibilityLabel("Show selected objects at \(state.viewportPreset.title)")
                    .accessibilityIdentifier("inspector.layout.visibility.show")
                    Button("Hide") {
                        _ = state.commitResponsiveVisibility(false, provenance: .pointer)
                    }
                    .accessibilityLabel("Hide selected objects at \(state.viewportPreset.title)")
                    .accessibilityIdentifier("inspector.layout.visibility.hide")
                }
                Text("\(applicable) applicable\(skipped > 0 ? " · \(skipped) skipped" : "")")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            case .unavailable(let reason):
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            if state.viewportPreset != .desktop {
                Button("Reset Visibility Override") {
                    _ = state.commitResponsiveVisibility(nil, provenance: .pointer)
                }
                .disabled(!state.hasVisibilityOverrideAtCurrentBreakpoint)
                .accessibilityIdentifier("inspector.layout.visibility.reset")
            }
            Text(state.currentResponsiveVisibilityAnnouncement)
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.layout.visibility.announcement")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.layout.visibility.section")
    }
}

private struct StatusBarView: View {
    @ObservedObject var state: WorkspaceShellState
    @ObservedObject private var lifecycle: DocumentLifecycleController

    init(state: WorkspaceShellState) {
        _state = ObservedObject(wrappedValue: state)
        _lifecycle = ObservedObject(wrappedValue: state.lifecycle)
    }

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
                .accessibilityValue(state.selectionAccessibilityValue)
                .accessibilityIdentifier("status.selectionPath")
            if let artboardStatus = state.selectionArtboardStatus {
                Divider().frame(height: 14)
                Label(artboardStatus, systemImage: "rectangle.slash")
                    .accessibilityLabel(artboardStatus)
                    .accessibilityIdentifier("status.selection.artboard")
            }
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
            if lifecycle.phase == .saving || lifecycle.phase == .autosaving {
                ProgressView().controlSize(.small).accessibilityLabel(lifecycle.statusText)
            }
            Label(lifecycle.statusText,
                  systemImage: lifecycle.phase == .failed || lifecycle.phase == .conflicted ? "exclamationmark.triangle.fill" : "doc.badge.clock")
                .foregroundStyle(lifecycle.phase == .failed || lifecycle.phase == .conflicted ? .red : .secondary)
                .accessibilityLabel("Document status: \(lifecycle.statusText)")
                .accessibilityValue(lifecycle.statusText)
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

/// Binds a command target to the AppKit window that hosts the SwiftUI scene.
/// FocusedObject remains the preferred route; this keyed fallback keeps native
/// File commands available when an NSColorWell or NSStepper owns focus.
@MainActor
private final class WorkspaceCommandTargetRegistry: NSObject {
    static let shared = WorkspaceCommandTargetRegistry()

    private final class Entry {
        weak var state: WorkspaceShellState?
        weak var window: NSWindow?

        init(_ state: WorkspaceShellState, window: NSWindow) {
            self.state = state
            self.window = window
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private weak var lastActiveWindow: NSWindow?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameActive(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameActive(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var hasBindings: Bool {
        prune()
        return !entries.isEmpty
    }

    func bind(_ state: WorkspaceShellState, to window: NSWindow) {
        // A SwiftUI host view can be replaced during a scene transition before
        // its old AppKit window finishes dismantling. Keep one ownership entry
        // per state and discard only obsolete window bindings; otherwise a
        // native File menu can resolve an old, untitled workspace while its
        // visible document window is tracking the menu.
        entries = entries.filter { _, entry in
            entry.state != nil && entry.window != nil && entry.state !== state
        }
        entries[ObjectIdentifier(window)] = Entry(state, window: window)
        if window.isKeyWindow || window.isMainWindow { markActive(window) }
    }

    func markActive(_ window: NSWindow) {
        prune()
        guard entries[ObjectIdentifier(window)]?.state != nil,
              window.isVisible,
              !window.isMiniaturized else { return }
        lastActiveWindow = window
    }

    @objc private func windowBecameActive(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        markActive(window)
    }

    func unbind(_ state: WorkspaceShellState?, from window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let entry = entries[key] else { return }
        guard state == nil || entry.state === state else { return }
        entries.removeValue(forKey: key)
        if lastActiveWindow === window { lastActiveWindow = nil }
    }

    func activeState() -> WorkspaceShellState? {
        prune()
        // AppKit temporarily clears key/main window while a menu tracks. In a
        // single-scene application there is still exactly one safe command
        // target; returning it prevents a native inspector control from
        // turning File commands into no-ops. Multi-window scenes remain
        // strictly window-keyed and never guess across ambiguous targets.
        for window in [NSApp.keyWindow, NSApp.mainWindow] {
            if let window, let state = entries[ObjectIdentifier(window)]?.state {
                markActive(window)
                return state
            }
        }
        if let window = lastActiveWindow,
           window.isVisible,
           !window.isMiniaturized,
           let state = entries[ObjectIdentifier(window)]?.state {
            return state
        }
        // AppKit clears key/main-window state while a native menu tracks.
        // The visible SiteForge window remains the authoritative command
        // owner; use it only when unambiguous, never across two scenes.
        let visibleEntries = entries.values.filter { entry in
            guard let window = entry.window else { return false }
            return window.isVisible && !window.isMiniaturized
        }
        if visibleEntries.count == 1 {
            return visibleEntries[0].state
        }
        return entries.count == 1 ? entries.values.first?.state : nil
    }

    private func prune() {
        entries = entries.filter { _, entry in
            entry.state != nil && entry.window != nil
        }
        if let lastActiveWindow,
           entries[ObjectIdentifier(lastActiveWindow)] == nil {
            self.lastActiveWindow = nil
        }
    }
}

struct SiteForgeCommands: Commands {
    @FocusedObject private var state: WorkspaceShellState?
    @FocusedObject private var launchExperience: LaunchExperienceController?

    private var commandState: WorkspaceShellState? {
        // Menu tracking and native Inspector controls can leave SwiftUI's
        // FocusedObject snapshot stale even though the AppKit key window is
        // unambiguous. Prefer the window-keyed production registry, then fall
        // back to FocusedObject for view-local command composition.
        let registered = WorkspaceCommandTargetRegistry.shared.activeState()
        // A focused SwiftUI value is valid only before any AppKit window has
        // registered. Once windows exist, ambiguity must disable commands
        // rather than target a dismantling scene.
        return registered ?? (WorkspaceCommandTargetRegistry.shared.hasBindings ? nil : state)
    }

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
                // Resolve at the native menu action boundary. SwiftUI can
                // retain a pre-menu FocusedObject snapshot while AppKit clears
                // the key responder for menu tracking; the registry is bound
                // to the actual workspace window and therefore owns this
                // command deterministically.
                guard let target = commandState else { return }
                if target.lifecycle.fileURL == nil { target.lifecycle.presentSavePanel() }
                else { Task { _ = await target.lifecycle.save() } }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(launchExperience?.isWorkspaceVisible != true || commandState?.lifecycle.canSave != true)
            Button("Save As…") { commandState?.lifecycle.presentSavePanel() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(launchExperience?.isWorkspaceVisible != true || commandState == nil)
            Button("Revert to Saved") {
                guard let state = commandState else { return }
                Task { _ = await state.lifecycle.requestRevert() }
            }
                .disabled(launchExperience?.isWorkspaceVisible != true || commandState?.lifecycle.canRevert != true)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                commandState?.undo()
            }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(launchExperience?.isWorkspaceVisible != true || commandState?.canUndo != true)
            Button("Redo") {
                commandState?.redo()
            }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(launchExperience?.isWorkspaceVisible != true || commandState?.canRedo != true)
        }

        CommandMenu("Insert") {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    commandState?.selectTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
                .keyboardShortcut(tool.shortcut, modifiers: [])
                .disabled(commandState?.textEditingSession.isActive == true)
            }
            Divider()
            Button("Insert Frame at Center") {
                commandState?.performDefaultInsertion(.frame, provenance: .menu)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(commandState?.insertionAvailability(.frame).isEnabled != true)
            Button("Insert Text at Center") {
                commandState?.performDefaultInsertion(.text, provenance: .menu)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(commandState?.insertionAvailability(.text).isEnabled != true)
            Divider()
            Button("Insert Section at Center") {
                commandState?.performDefaultInsertion(.section, provenance: .menu)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(commandState?.insertionAvailability(.section).isEnabled != true)
            Button("Insert Stack at Center") {
                commandState?.performDefaultInsertion(.stack, provenance: .menu)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(commandState?.insertionAvailability(.stack).isEnabled != true)
            Button("Insert Grid at Center") {
                commandState?.performDefaultInsertion(.grid, provenance: .menu)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            .disabled(commandState?.insertionAvailability(.grid).isEnabled != true)
            Divider()
            Button("Insert Selected Image at Center") {
                commandState?.insertSelectedImage()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(commandState?.selectedAssetID == nil)
            Button("Import and Insert Image…") {
                commandState?.importImages(insertFirst: true)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu("Selection") {
            Button("Edit Selected Text") {
                guard let nodeID = commandState?.selectionState.primaryID else { return }
                commandState?.beginTextEditing(nodeID: nodeID, provenance: .menu)
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(
                commandState?.textEditingSession.isActive == true
                    || (commandState?.selectionState.primaryID.map {
                    commandState?.textEditingAvailability(nodeID: $0).isEnabled != true
                } ?? true)
            )
            Button("Commit Text Edit") {
                commandState?.commitTextEditing()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(commandState?.textEditingSession.isActive != true)
            Divider()
            Button("Select Next Object") {
                commandState?.performSelectionCommand(.next, provenance: .menu)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(commandState?.selectionAvailability(.next).isEnabled != true)
            Button("Select Previous Object") {
                commandState?.performSelectionCommand(.previous, provenance: .menu)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(commandState?.selectionAvailability(.previous).isEnabled != true)
            Divider()
            Button("Clear Selection") {
                commandState?.performSelectionCommand(.clear, provenance: .menu)
            }
            .disabled(commandState?.selectionAvailability(.clear).isEnabled != true)
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
            Toggle("Grid", isOn: Binding(
                get: { state?.isWorldGridVisible ?? true },
                set: { state?.isWorldGridVisible = $0 }
            ))
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
        view.isWorldGridVisible = state.isWorldGridVisible
        view.textEditingPresentation = state.textEditingPresentation
        view.accessibilityViewportValue = state.viewportAccessibilityValue
        view.needsDisplay = true
        view.updateKeyboardFocusRequest(
            isKeyboardFocused && state.textEditingPresentation == nil
        )
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
        view.isWorldGridVisible = state.isWorldGridVisible
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
            let revision = state.documentSession.document.revision
            state.performTransform(operation, provenance: .keyboard)
            return state.documentSession.document.revision != revision
        }
        view.onSelectNext = {
            let prior = state.selectionState
            state.performSelectionCommand(.next, provenance: .keyboard)
            return state.selectionState != prior
        }
        view.onSelectPrevious = {
            let prior = state.selectionState
            state.performSelectionCommand(.previous, provenance: .keyboard)
            return state.selectionState != prior
        }
        view.onClearSelection = {
            let prior = state.selectionState
            state.performSelectionCommand(.clear, provenance: .keyboard)
            return state.selectionState != prior
        }
        view.onEscape = { state.performEscape() }
        view.onInsertFrame = {
            guard state.insertionAvailability(.frame).isEnabled else { return false }
            let revision = state.documentSession.document.revision
            state.performDefaultInsertion(.frame, provenance: .accessibility)
            return state.documentSession.document.revision != revision
        }
        view.onInsertText = {
            guard state.insertionAvailability(.text).isEnabled else { return false }
            let revision = state.documentSession.document.revision
            state.performDefaultInsertion(.text, provenance: .accessibility)
            return state.documentSession.document.revision != revision
        }
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
            let prior = state.activeGuides
            state.addGuide(axis: axis, position: position, provenance: .pointer)
            return state.activeGuides != prior
        }
        view.onSelectGuide = { state.selectGuide($0) }
        view.onToggleSnapping = {
            let prior = state.isSnappingSuppressed
            state.setSnappingSuppressed(!state.isSnappingSuppressed)
            return state.isSnappingSuppressed != prior
        }
        view.onPan = { state.panViewport(by: $0) }
        view.onMagnify = { factor, anchor in state.magnify(by: factor, around: anchor) }
        view.onResize = { size, scale in state.resizeViewport(to: size, pixelRatio: scale) }
        view.onZoomIn = {
            let prior = state.viewportState
            state.performViewportCommand(CanvasViewportCommand(.zoomIn))
            return state.viewportState != prior
        }
        view.onZoomOut = {
            let prior = state.viewportState
            state.performViewportCommand(CanvasViewportCommand(.zoomOut))
            return state.viewportState != prior
        }
        view.onReset = {
            let prior = state.viewportState
            state.performViewportCommand(CanvasViewportCommand(.actualSize))
            return state.viewportState != prior
        }
        view.onTabTraversal = onTabTraversal
    }
}

/// A queued native focus adoption is valid only for the newest logical focus
/// request. SwiftUI reconciliation can otherwise leave a delayed canvas task
/// alive after a rapid Tab/Shift-Tab traversal has already moved elsewhere.
struct CanvasFocusAdoptionToken: Equatable, Sendable {
    fileprivate let generation: UInt64
}

struct CanvasFocusAdoptionGate: Sendable {
    private(set) var generation: UInt64 = 0

    mutating func issue(whenRequested requested: Bool) -> CanvasFocusAdoptionToken? {
        generation &+= 1
        return requested ? CanvasFocusAdoptionToken(generation: generation) : nil
    }

    mutating func cancel() { generation &+= 1 }

    func accepts(_ token: CanvasFocusAdoptionToken) -> Bool {
        token.generation == generation
    }
}

enum CanvasAccessibilityActionDispatcher {
    /// VoiceOver must receive the command's real mutation result. A missing,
    /// disabled, rejected, or no-op command is not a successful AX action.
    static func perform(_ action: (() -> Bool)?) -> Bool {
        action?() ?? false
    }
}

enum CanvasAuthoredTextLayerFactory {
    /// Constructs the same native authored-text layer used by the live
    /// viewport. Keeping opacity on this production object (instead of only
    /// on tiled surfaces) ensures glyphs and their authored object share one
    /// compositing contract.
    static func makeLayer(
        for object: CanvasRenderObject,
        viewport: CanvasViewportState,
        contentsScale: CGFloat
    ) -> CATextLayer? {
        guard object.style == .textPlaceholder,
              object.isVisible,
              object.opacity.isFinite,
              (0...1).contains(object.opacity),
              let text = object.plainText,
              !text.isEmpty,
              let origin = try? viewport.transform.worldToViewport(object.frame.origin) else {
            return nil
        }
        let layout = CanvasTextLayout(
            viewportObjectRect: CGRect(
                x: origin.x,
                y: origin.y,
                width: object.frame.size.width * viewport.zoom.value,
                height: object.frame.size.height * viewport.zoom.value
            ),
            zoom: viewport.zoom.value,
            text: text,
            typography: object.typography
        )
        let layer = CATextLayer()
        layer.name = "renderer.authored-text.\(object.id.description)"
        layer.isGeometryFlipped = true
        layer.frame = layout.glyphBounds
        layer.string = NSAttributedString(string: text, attributes: [
            .font: layout.font,
            .foregroundColor: NSColor.labelColor,
            .kern: layout.tracking,
            .paragraphStyle: layout.paragraphStyle,
        ])
        layer.font = layout.font
        layer.fontSize = layout.fontSize
        layer.foregroundColor = NSColor.labelColor.cgColor
        layer.opacity = Float(object.opacity)
        layer.alignmentMode = switch layout.alignment { case .center: .center; case .right: .right; default: .left }
        layer.truncationMode = .end
        layer.isWrapped = true
        layer.contentsScale = max(1, contentsScale)
        return layer
    }
}

private final class NativeCanvasViewportView: NSView {
    var viewportState = try! CanvasViewportState() {
        didSet {
            // A raster plan is defined in one immutable viewport generation.
            // Never visually bridge it into a different generation: doing so
            // can place the tile surface at a different rect than the live
            // selection/hit-test/accessibility geometry.  The model prepares
            // the matching plan asynchronously; until it arrives, keep the
            // editor honest by showing no authored raster for that generation.
            discardRasterIfViewportGenerationChanged()
            applyArtboardClipMask()
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
    var isWorldGridVisible = true
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
    var onSelectNext: (() -> Bool)?
    var onSelectPrevious: (() -> Bool)?
    var onClearSelection: (() -> Bool)?
    var onEscape: (() -> Void)?
    var onInsertFrame: (() -> Bool)?
    var onInsertText: (() -> Bool)?
    var onBeginTextEditingAtPoint: ((WorldPoint) -> Bool)?
    var onBeginSelectedTextEditing: (() -> Bool)?
    var onTextDraftChange: ((String, TextEditRange, TextEditRange?) -> Void)?
    var onTextCommit: (() -> Void)?
    var onTextCancel: (() -> Void)?
    var onCreateGuide: ((GuideAxis, Double) -> Bool)?
    var onSelectGuide: ((GuideID?) -> Void)?
    var onToggleSnapping: (() -> Bool)?
    var onPan: ((ViewportVector) -> Void)?
    var onMagnify: ((Double, ViewportPoint) -> Void)?
    var onResize: ((ViewportSize, Double) -> Void)?
    var onZoomIn: (() -> Bool)?
    var onZoomOut: (() -> Bool)?
    var onReset: (() -> Bool)?
    var onTabTraversal: ((ShellFocusDirection) -> Void)?
    private let contentContainer = CALayer()
    // Text is composed from the same resolved viewport rect as tiles, but it
    // is kept in one non-tiled authored subtree. This avoids drawing the same
    // line fragment through two independently flipped tile contexts when a
    // 24-point text frame crosses a tile edge.
    private let textContainer = CALayer()
    private let overlayContainer = CALayer()
    private var rasterViewportState: CanvasViewportState?
    private var virtualAccessibilityElements: [NSAccessibilityElement] = []
    /// Editor-only selection context mirrors the visible badge.  It is a
    /// real accessibility surface (rather than a UI-test hook), retaining
    /// the complete context when a narrow artboard uses the compact badge.
    private var selectionContextAccessibilityElements: [NSAccessibilityElement] = []
    private struct SelectionContextBadge {
        let objectID: NodeID
        let fullText: String
        let placement: CanvasSelectionBadgePlacement
    }
    private var selectionContextBadges: [SelectionContextBadge] = []
    private var transformHandleViews: [String: TransformHandleControlView] = [:]
    private var focusedAccessibilityObjectID: NodeID?
    private var focusAdoptionGate = CanvasFocusAdoptionGate()
    private var pointerTrackingArea: NSTrackingArea?
    private var transformPointerStart: WorldPoint?
    private var transformDidDrag = false
    private var inlineTextView: InlineCanvasTextView?
    private var isApplyingTextPresentation = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentContainer.name = "renderer.authored-content"
        textContainer.name = "renderer.authored-text"
        overlayContainer.name = "renderer.editor-overlays"
        // The viewport's coordinate contract is top-left-origin. CALayer
        // subtrees do not inherit NSView.isFlipped, so declare it on each
        // owned container to keep tiles, overlays, clipping, and hit-test
        // geometry in the same coordinate system as CanvasViewportState.
        contentContainer.isGeometryFlipped = true
        textContainer.isGeometryFlipped = true
        overlayContainer.isGeometryFlipped = true
        contentContainer.masksToBounds = true
        textContainer.masksToBounds = true
        overlayContainer.masksToBounds = true
        layer?.addSublayer(contentContainer)
        layer?.addSublayer(textContainer)
        layer?.addSublayer(overlayContainer)
        applyArtboardClipMask()
    }

    required init?(coder: NSCoder) { nil }

    func updateKeyboardFocusRequest(_ requested: Bool) {
        guard let token = focusAdoptionGate.issue(whenRequested: requested) else { return }
        guard window?.firstResponder !== self else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.focusAdoptionGate.accepts(token),
                  self.textEditingPresentation == nil,
                  let window = self.window else { return }
            _ = window.makeFirstResponder(self)
        }
    }

    private func cancelPendingKeyboardFocusAdoption() {
        focusAdoptionGate.cancel()
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Canvas viewport" }
    override func accessibilityValue() -> Any? {
        "\(accessibilityViewportValue); rendered objects \(renderPlan?.authoredObjects.count ?? 0)"
    }
    override func accessibilityChildren() -> [Any]? {
        virtualAccessibilityElements + selectionContextAccessibilityElements + TransformHandle.allCases.compactMap {
            transformHandleViews[$0.rawValue]
        } + [inlineTextView].compactMap { $0 }
    }
    override func accessibilityHelp() -> String? {
        "Scroll to pan. Pinch to zoom around the pointer. Use the View menu for keyboard controls."
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(name: "Zoom In") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onZoomIn)
            },
            NSAccessibilityCustomAction(name: "Zoom Out") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onZoomOut)
            },
            NSAccessibilityCustomAction(name: "Reset View") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onReset)
            },
            NSAccessibilityCustomAction(name: "Select Next Object") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onSelectNext)
            },
            NSAccessibilityCustomAction(name: "Select Previous Object") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onSelectPrevious)
            },
            NSAccessibilityCustomAction(name: "Clear Selection") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onClearSelection)
            },
            NSAccessibilityCustomAction(name: "Insert Frame at Center") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onInsertFrame)
            },
            NSAccessibilityCustomAction(name: "Insert Text at Center") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onInsertText)
            },
            NSAccessibilityCustomAction(name: "Edit Selected Text") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onBeginSelectedTextEditing)
            },
            NSAccessibilityCustomAction(name: "Add Horizontal Guide") { [weak self] in
                guard let self else { return false }
                guard let action = self.onCreateGuide else { return false }
                return action(.horizontal, self.viewportState.visibleWorldRect.origin.y + 100)
            },
            NSAccessibilityCustomAction(name: "Add Vertical Guide") { [weak self] in
                guard let self else { return false }
                guard let action = self.onCreateGuide else { return false }
                return action(.vertical, self.viewportState.visibleWorldRect.origin.x + 100)
            },
            NSAccessibilityCustomAction(name: "Toggle Snapping") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onToggleSnapping)
            },
            NSAccessibilityCustomAction(name: "Move Right 1 px") { [weak self] in
                guard let action = self?.onKeyboardMove else { return false }
                return action(WorldVector(dx: 1, dy: 0))
            },
            NSAccessibilityCustomAction(name: "Move Down 1 px") { [weak self] in
                guard let action = self?.onKeyboardMove else { return false }
                return action(WorldVector(dx: 0, dy: 1))
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
        textContainer.frame = bounds
        overlayContainer.frame = bounds
        CATransaction.commit()
        applyArtboardClipMask()
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
            _ = onCreateGuide?(.vertical, world.x)
            return
        }
        if point.x <= SnappingPolicy.rulerThicknessPoints,
           point.y > SnappingPolicy.rulerThicknessPoints,
           let world = try? viewportState.transform.viewportToWorld(
               ViewportPoint(x: point.x, y: point.y)
           ) {
            window?.makeFirstResponder(self)
            _ = onCreateGuide?(.horizontal, world.y)
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
            // Invalidate any delayed SwiftUI-to-AppKit adoption before the
            // logical traversal request leaves the canvas. Without this, the
            // older task can run one event later and steal focus back.
            cancelPendingKeyboardFocusAdoption()
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
            _ = onSelectNext?()
            return
        }
        if event.modifierFlags.contains(.command), event.keyCode == 33 {
            _ = onSelectPrevious?()
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
        if isWorldGridVisible { drawWorldGrid(in: context) }
        let artboardOrigin = (try? transform.worldToViewport(viewportState.contentBounds.origin))
            ?? ViewportPoint(x: 0, y: 0)
        let artboard = CGRect(
            x: artboardOrigin.x,
            y: artboardOrigin.y,
            width: viewportState.contentBounds.size.width * viewportState.zoom.value,
            height: viewportState.contentBounds.size.height * viewportState.zoom.value
        )
        // The page/artboard is an editor decoration backed by the preset's
        // actual content bounds. Give it a native surface that is visibly
        // distinct from the darker infinite pasteboard without pretending an
        // authored Frame/Section is the page itself.
        if artboard.origin.x.isFinite, artboard.origin.y.isFinite,
           artboard.width.isFinite, artboard.height.isFinite,
           artboard.width > 0, artboard.height > 0 {
            context.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: NSColor.black.withAlphaComponent(0.30).cgColor)
            // The artboard deliberately has more contrast than the
            // pasteboard. It remains an editor decoration backed by the
            // preset's actual content bounds, not an authored rectangle.
            let artboardSurface = NSColor.windowBackgroundColor
                .blended(withFraction: 0.16, of: .labelColor) ?? .windowBackgroundColor
            context.setFillColor(artboardSurface.cgColor)
            context.fill(artboard)
            context.setShadow(offset: .zero, blur: 0)
            context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.98).cgColor)
            context.setLineWidth(2 / max(1, viewportState.pixelRatio.value))
            context.stroke(artboard)
        }
        drawRulersAndGuides(in: context)
        if window?.firstResponder === self,
           let focusRect = CanvasViewportDrawGeometry.inset(bounds, dx: 2, dy: 2) {
            context.setStrokeColor(NSColor.keyboardFocusIndicatorColor.cgColor)
            context.setLineWidth(3)
            context.stroke(focusRect)
        }
    }

    /// Editor-only, world-anchored grid. It is deliberately drawn before the
    /// page/artboard surface and has no canonical, hit-test, or export role.
    private func drawWorldGrid(in context: CGContext) {
        let zoom = viewportState.zoom.value
        let minor = CanvasWorldGridPolicy.minorInterval(for: zoom)
        let major = CanvasWorldGridPolicy.majorInterval(for: zoom)
        let visible = viewportState.visibleWorldRect
        let scale = viewportState.pixelRatio.value
        func aligned(_ value: Double) -> CGFloat { CGFloat(CanvasWorldGridPolicy.deviceAligned(value, scale: scale)) }
        context.saveGState(); defer { context.restoreGState() }
        var x = floor(visible.minX / minor) * minor
        while x <= visible.maxX {
            if let point = try? viewportState.transform.worldToViewport(.init(x: x, y: 0)) {
                let isMajor = abs((x / major).rounded() - x / major) < 0.000_001
                context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(isMajor ? 0.28 : 0.13).cgColor)
                context.setLineWidth(1 / scale)
                context.move(to: .init(x: aligned(point.x), y: 0)); context.addLine(to: .init(x: aligned(point.x), y: bounds.height)); context.strokePath()
            }
            x += minor
        }
        var y = floor(visible.minY / minor) * minor
        while y <= visible.maxY {
            if let point = try? viewportState.transform.worldToViewport(.init(x: 0, y: y)) {
                let isMajor = abs((y / major).rounded() - y / major) < 0.000_001
                context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(isMajor ? 0.28 : 0.13).cgColor)
                context.setLineWidth(1 / scale)
                context.move(to: .init(x: 0, y: aligned(point.y))); context.addLine(to: .init(x: bounds.width, y: aligned(point.y))); context.strokePath()
            }
            y += minor
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
        // SwiftUI can deliver the state values in separate reconciliation
        // passes.  A plan from an earlier pan/zoom/fit/preset generation must
        // not be transformed to look current: the tile's local origin would
        // no longer share the exact world-to-viewport rect used by overlays.
        // Drop it and wait for the already-scheduled matching generation.
        guard plan.viewport == viewportState else {
            discardRaster()
            overlayContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
            rebuildAccessibility(plan)
            return
        }
        // A compositor-only *scene* invalidation still carries a distinct
        // viewport snapshot when pan, zoom, Fit, or a preset changed. Reusing
        // the old tiles in that case made the content subtree bridge two
        // viewport generations while overlays used the live generation. That
        // could leave an old Frame raster visible after Fit. Only retain tiles
        // when both the authored scene and their immutable viewport snapshot
        // are exactly unchanged.
        if plan.invalidation == .compositorOnly, rasterViewportState == plan.viewport {
            applyCompositorTransformIfPossible()
            rebuildAccessibility(plan)
            return
        }
        let objectMap = Dictionary(uniqueKeysWithValues: plan.authoredObjects.map { ($0.id, $0) })
        // Tile membership, tile origins, and object raster positions are all
        // defined in the plan's immutable viewport generation. The view may
        // already have received a newer pan/zoom/resize when this asynchronous
        // plan arrives; compose from this snapshot to the live viewport only
        // after the authored layers have been built.
        let rasterViewport = plan.viewport
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        textContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for tile in plan.tiles {
            let scale = rasterViewport.pixelRatio.value
            let tileLayer = CanvasContentTileLayer()
            tileLayer.name = "renderer.tile.\(tile.id.column).\(tile.id.row)"
            tileLayer.contentsScale = scale
            tileLayer.frame = CGRect(
                x: tile.deviceFrame.origin.x / scale,
                y: tile.deviceFrame.origin.y / scale,
                width: tile.deviceFrame.size.width / scale,
                height: tile.deviceFrame.size.height / scale
            )
            tileLayer.viewportState = rasterViewport
            tileLayer.objects = tile.objectIDs.compactMap { objectMap[$0] }
            tileLayer.tileOrigin = tileLayer.frame.origin
            tileLayer.setNeedsDisplay()
            contentContainer.addSublayer(tileLayer)
        }
        for object in plan.authoredObjects where object.style == .textPlaceholder && object.isVisible {
            guard let textLayer = CanvasAuthoredTextLayerFactory.makeLayer(
                for: object,
                viewport: rasterViewport,
                contentsScale: window?.backingScaleFactor ?? CGFloat(rasterViewport.pixelRatio.value)
            ) else { continue }
            textContainer.addSublayer(textLayer)
        }
        contentContainer.setAffineTransform(.identity)
        textContainer.setAffineTransform(.identity)
        rasterViewportState = rasterViewport
        rebuildOverlay()
        rebuildAccessibility(plan)
        CATransaction.commit()
    }

    private func discardRasterIfViewportGenerationChanged() {
        guard let rasterViewportState, rasterViewportState != viewportState else { return }
        discardRaster()
    }

    private func discardRaster() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        textContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        contentContainer.setAffineTransform(.identity)
        textContainer.setAffineTransform(.identity)
        rasterViewportState = nil
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
        textContainer.setAffineTransform(CGAffineTransform(
            a: ratio, b: 0, c: 0, d: ratio,
            tx: (raster.worldOrigin.x - viewportState.worldOrigin.x) * viewportState.zoom.value,
            ty: (raster.worldOrigin.y - viewportState.worldOrigin.y) * viewportState.zoom.value
        ))
        CATransaction.commit()
    }

    /// Authored layers are always clipped by the live preset artboard. The
    /// renderer plan may briefly be from an older viewport generation during
    /// an asynchronous preset adoption; applying this single shared mask
    /// prevents those stale tiles or text layers escaping into pasteboard
    /// space. Editor overlays use their own resolved intersection contract.
    private func applyArtboardClipMask() {
        guard bounds.width > 0, bounds.height > 0,
              let origin = try? viewportState.transform.worldToViewport(viewportState.contentBounds.origin) else {
            contentContainer.mask = nil
            textContainer.mask = nil
            return
        }
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: viewportState.contentBounds.size.width * viewportState.zoom.value,
            height: viewportState.contentBounds.size.height * viewportState.zoom.value
        )
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else {
            contentContainer.mask = nil
            textContainer.mask = nil
            return
        }
        func makeMask() -> CAShapeLayer {
            let mask = CAShapeLayer()
            mask.frame = bounds
            mask.path = CGPath(rect: rect, transform: nil)
            mask.fillColor = NSColor.white.cgColor
            return mask
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentContainer.mask = makeMask()
        textContainer.mask = makeMask()
        CATransaction.commit()
    }

    private func rebuildOverlay() {
        overlayContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        selectionContextBadges = []
        var retainedHandleNames: Set<String> = []
        let artboardRect: CGRect? = {
            guard let origin = try? viewportState.transform.worldToViewport(
                viewportState.contentBounds.origin
            ) else { return nil }
            return CGRect(
                x: origin.x,
                y: origin.y,
                width: viewportState.contentBounds.size.width * viewportState.zoom.value,
                height: viewportState.contentBounds.size.height * viewportState.zoom.value
            )
        }()
        // Selection is canonical and survives a breakpoint change, but its
        // visual plan is tied to one render/viewport generation.  Do not
        // reinterpret a Desktop overlay against Tablet/Mobile geometry while
        // the matching renderer plan is still being adopted.
        let hasCurrentSelectionGeometry = selectionOverlayPlan.map { overlay in
            guard let renderPlan else { return false }
            return overlay.identity == renderPlan.identity && renderPlan.viewport == viewportState
        } ?? false
        if let selectionOverlayPlan, hasCurrentSelectionGeometry {
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
                // Rendered authored bounds and selection both consume the
                // same resolved viewport rect. A centered stroke may extend
                // half a device pixel, but selection must not shrink that
                // contract with an independent inset.
                layer.path = CGPath(rect: layer.bounds, transform: nil)
                layer.fillColor = nil
                layer.strokeColor = NSColor.controlAccentColor.cgColor
                layer.lineWidth = overlay.kind.contains("primary") ? 3 : 1.5
                if overlay.kind.contains("locked") { layer.lineDashPattern = [4, 3] }
                overlayContainer.addSublayer(layer)
                if let label = overlay.label, let artboardRect {
                    let labelLayer = CATextLayer()
                    labelLayer.name = "renderer.overlay.selection-context.\(overlay.objectID.description)"
                    let badgeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                    labelLayer.font = badgeFont
                    labelLayer.fontSize = 11
                    labelLayer.foregroundColor = NSColor.white.cgColor
                    labelLayer.backgroundColor = NSColor.controlAccentColor.cgColor
                    labelLayer.cornerRadius = 4
                    labelLayer.alignmentMode = .center
                    // The placement must reflect the real font advance, and
                    // the layer must remain a final artboard-safe boundary if
                    // a future font/rendering change differs by a fraction.
                    labelLayer.truncationMode = .end
                    labelLayer.masksToBounds = true
                    labelLayer.contentsScale = window?.backingScaleFactor ?? 2
                    let compact = label.split(separator: "·").prefix(2)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .joined(separator: " · ")
                    let attributes: [NSAttributedString.Key: Any] = [.font: badgeFont]
                    let placement = CanvasSelectionChromeLayout.badgePlacement(
                        selectionRect: layer.frame,
                        artboardRect: artboardRect,
                        fullText: label,
                        fullWidth: max(120, (label as NSString).size(withAttributes: attributes).width + 12),
                        compactText: compact,
                        compactWidth: max(64, (compact as NSString).size(withAttributes: attributes).width + 12)
                    )
                    if let placement {
                        labelLayer.string = placement.text
                        labelLayer.frame = placement.frame
                        overlayContainer.addSublayer(labelLayer)
                        selectionContextBadges.append(.init(
                            objectID: overlay.objectID,
                            fullText: label,
                            placement: placement
                        ))
                    }
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
            layer.path = CGPath(rect: CanvasViewportDrawGeometry.inset(layer.bounds, dx: 1, dy: 1) ?? .zero, transform: nil)
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
            layer.path = CGPath(rect: CanvasViewportDrawGeometry.inset(layer.bounds, dx: 0.5, dy: 0.5) ?? .zero, transform: nil)
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
        focus.path = CGPath(rect: CanvasViewportDrawGeometry.inset(bounds, dx: 2, dy: 2) ?? .zero, transform: nil)
        focus.fillColor = nil
        focus.strokeColor = NSColor.keyboardFocusIndicatorColor.cgColor
        focus.lineWidth = 3
        focus.isHidden = window?.firstResponder !== self
        overlayContainer.addSublayer(focus)
    }


    private func rebuildAccessibility(_ plan: CanvasRenderPlan) {
        // Off-artboard objects are deliberately virtualized.  Equally, an
        // older render plan must not expose an accessibility frame in the
        // live viewport generation while its raster is withheld.
        guard plan.viewport == viewportState else {
            virtualAccessibilityElements = []
            selectionContextAccessibilityElements = []
            focusedAccessibilityObjectID = nil
            NSAccessibility.post(element: self, notification: .layoutChanged)
            return
        }
        let repairedFocus = CanvasAccessibilityFocusPolicy.repairedFocus(
            previousObjectID: focusedAccessibilityObjectID,
            elements: plan.accessibilityElements
        )
        let focusChanged = repairedFocus != focusedAccessibilityObjectID
        focusedAccessibilityObjectID = repairedFocus
        let selectedOverlays = Dictionary(
            uniqueKeysWithValues: (selectionOverlayPlan?.overlays ?? []).map { ($0.objectID, $0) }
        )
        let selectedIDs = Set(selectedOverlays.keys)
        virtualAccessibilityElements = plan.accessibilityElements.map { item in
            let local = CGPoint(x: item.frame.origin.x, y: item.frame.origin.y)
            let screenOrigin = window?.convertPoint(toScreen: convert(local, to: nil)) ?? .zero
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.group)
            element.setAccessibilityFrame(NSRect(
                x: screenOrigin.x,
                // SiteForge canvas coordinates are top-left/Y-down while AX
                // screen rectangles use a bottom-left origin. The converted
                // point is the authored top-left, so lower the AX origin by
                // the exact authored height rather than introducing a second
                // geometry source.
                y: screenOrigin.y - item.frame.size.height,
                width: item.frame.size.width,
                height: item.frame.size.height
            ))
            element.setAccessibilityLabel(item.label)
            if let context = selectedOverlays[item.objectID]?.label {
                element.setAccessibilityValue(context)
                element.setAccessibilityHelp("Selection context: \(context)")
            }
            element.setAccessibilityParent(self)
            element.setAccessibilityIdentifier("canvas.object.\(item.objectID.description)")
            element.setAccessibilitySelected(selectedIDs.contains(item.objectID))
            return element
        }
        selectionContextAccessibilityElements = selectionContextBadges.map { badge in
            let local = badge.placement.frame.origin
            let screenOrigin = window?.convertPoint(toScreen: convert(local, to: nil)) ?? .zero
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityFrame(NSRect(
                x: screenOrigin.x,
                y: screenOrigin.y - badge.placement.frame.height,
                width: badge.placement.frame.width,
                height: badge.placement.frame.height
            ))
            element.setAccessibilityLabel(badge.fullText)
            element.setAccessibilityValue(badge.placement.text)
            element.setAccessibilityHelp(
                badge.placement.usesCompactText
                    ? "Compact selection context badge. Full context: \(badge.fullText)"
                    : "Selection context badge."
            )
            element.setAccessibilityParent(self)
            element.setAccessibilityIdentifier("canvas.selection.context.\(badge.objectID.description)")
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
        let layout = CanvasTextLayout(
            viewportObjectRect: CGRect(
                x: origin.x,
                y: origin.y,
                width: presentation.frame.size.width * viewportState.zoom.value,
                height: presentation.frame.size.height * viewportState.zoom.value
            ),
            zoom: viewportState.zoom.value,
            text: presentation.text,
            typography: presentation.typography
        )
        // The editor and editor-only selection outline consume the exact same
        // object rectangle. Text insets and baseline are supplied by the
        // shared layout below, not by an editor-only offset or minimum size.
        editor.frame = layout.viewportObjectRect
        editor.applyCanvasTextLayout(layout)
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
        drawsBackground = false
        backgroundColor = .clear
        textColor = .labelColor
        insertionPointColor = .controlAccentColor
        font = .systemFont(ofSize: CanvasTextLayout.baseFontSize)
        textContainerInset = NSSize(width: CanvasTextLayout.baseHorizontalInset, height: 0)
        textContainer?.lineFragmentPadding = 0
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

    func applyCanvasTextLayout(_ layout: CanvasTextLayout) {
        font = layout.font
        textContainerInset = layout.textContainerInset
        textContainer?.lineFragmentPadding = 0
        alignment = layout.alignment
        typingAttributes = [
            .font: layout.font,
            .foregroundColor: NSColor.labelColor,
            .kern: layout.tracking,
            .paragraphStyle: layout.paragraphStyle,
        ]
        if textStorage?.length ?? 0 > 0 {
            textStorage?.setAttributes(typingAttributes, range: NSRange(location: 0, length: textStorage?.length ?? 0))
        }
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
        // `CanvasViewportState`, tile frames, overlays, event conversion, and
        // accessibility all use a top-left/Y-down viewport. Core Animation
        // hands tile drawing a bottom-left Core Graphics context, so establish
        // the one boundary conversion here before any authored rect is drawn.
        // Every rect below is therefore the same local viewport rect used by
        // selection and hit testing; tile origin is applied exactly once.
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        defer { context.restoreGState() }
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
            var ancestorClip = bounds
            if let clip = object.clipRect,
               let clipOrigin = try? viewportState.transform.worldToViewport(clip.origin) {
                ancestorClip = ancestorClip.intersection(CGRect(
                    x: clipOrigin.x - tileOrigin.x,
                    y: clipOrigin.y - tileOrigin.y,
                    width: clip.size.width * viewportState.zoom.value,
                    height: clip.size.height * viewportState.zoom.value
                ))
            }
            guard !ancestorClip.isNull, !ancestorClip.isEmpty else {
                context.restoreGState()
                continue
            }
            context.clip(to: ancestorClip)
            let radius = min(
                CGFloat(object.cornerRadius * viewportState.zoom.value),
                min(rect.width, rect.height) / 2
            )
            let objectPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if let shadow = object.shadow, let color = nsColor(shadow.rgba) {
                context.saveGState()
                // Clip the opaque shadow source out of the authored interior.
                // This leaves a true exterior drop shadow even when the
                // object's own fill is translucent or absent.
                let exclusion = CGMutablePath()
                exclusion.addRect(ancestorClip)
                exclusion.addPath(objectPath)
                context.addPath(exclusion)
                context.clip(using: .evenOdd)
                context.setShadow(
                    offset: CGSize(
                        width: shadow.offsetX * viewportState.zoom.value,
                        height: shadow.offsetY * viewportState.zoom.value
                    ),
                    blur: shadow.blur * viewportState.zoom.value,
                    color: color.cgColor
                )
                let spread = shadow.spread * viewportState.zoom.value
                let shadowRect = rect.insetBy(dx: -spread, dy: -spread)
                let shadowRadius = max(0, radius + spread)
                context.addPath(CGPath(roundedRect: shadowRect, cornerWidth: shadowRadius, cornerHeight: shadowRadius, transform: nil))
                context.setFillColor(NSColor.black.cgColor)
                context.fillPath()
                context.restoreGState()
            }
            context.addPath(objectPath)
            context.clip()
            let fallback: NSColor = switch object.style {
            case .canvas: .underPageBackgroundColor
            case .page: .controlAccentColor.withAlphaComponent(0.16)
            case .container: .controlAccentColor.withAlphaComponent(0.28)
            case .frameSurface: .controlBackgroundColor.withAlphaComponent(0.92)
            case .sectionSurface: .systemIndigo.withAlphaComponent(0.12)
            case .stackSurface: .systemTeal.withAlphaComponent(0.12)
            case .gridSurface: .systemOrange.withAlphaComponent(0.12)
            // Valid images must not inherit editor placeholder color through
            // transparent source pixels. Missing-resource treatment is drawn
            // explicitly only after native decode fails below.
            case .imagePlaceholder: .clear
            case .textPlaceholder: .labelColor.withAlphaComponent(0.12)
            }
            // Object opacity applies once to the complete authored layer
            // stack. Individual layer alpha remains part of normal source-over
            // compositing; editor overlays are painted by separate layers.
            context.setAlpha(CGFloat(object.opacity))
            let renderedSurface: NSColor
            if !object.fillLayers.isEmpty {
                // Composite the authored stack into one transparency group.
                // The current alpha is applied when that completed group is
                // drawn back into the tile, rather than once per layer.
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                for layer in object.fillLayers where layer.isEnabled {
                    drawAuthoredFillLayer(layer, in: rect, context: context)
                }
                context.endTransparencyLayer()
                renderedSurface = CanvasAuthoredFillCompositor.resolvedColor(
                    layers: object.fillLayers,
                    atNormalizedPoint: (x: 0.5, y: 0.5)
                ).flatMap { self.nsColor($0) } ?? fallback
            } else if let rgba = object.fillRGBA, rgba.count == 4 {
                // Compatibility for pre-v1 render snapshots only. Workspace
                // preparation always supplies `fillLayers` for canonical data.
                renderedSurface = NSColor(calibratedRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
                context.setFillColor(renderedSurface.cgColor)
                context.fill(rect)
            } else {
                renderedSurface = fallback
                context.setFillColor(fallback.cgColor)
                context.fill(rect)
            }
            var didDrawImage = false
            if object.style == .imagePlaceholder,
               let data = object.imageData,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, [
                   kCGImageSourceShouldCache: false,
                   kCGImageSourceShouldAllowFloat: true,
               ] as CFDictionary) {
                let mode = object.imageFitMode ?? .fit
                guard let resolvedDestination = CanvasImageLayout.destinationRect(
                    source: .init(width: Double(image.width), height: Double(image.height)),
                    bounds: .init(
                        origin: .init(x: rect.origin.x, y: rect.origin.y),
                        size: .init(width: rect.width, height: rect.height)
                    ),
                    mode: mode, focalX: object.imageFocalX, focalY: object.imageFocalY
                ) else { continue }
                let destination = CGRect(
                    x: resolvedDestination.origin.x, y: resolvedDestination.origin.y,
                    width: resolvedDestination.size.width, height: resolvedDestination.size.height
                )
                context.saveGState()
                context.clip(to: rect)
                // SiteForge's tile context is top-left/Y-down. CGImage draw is
                // bottom-left/Y-up, so reflect exactly once around the resolved
                // destination midpoint. Selection and hit testing keep using
                // the unchanged authored rect.
                context.translateBy(x: 0, y: 2 * destination.midY)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(image, in: destination)
                context.restoreGState()
                didDrawImage = true
            }
            if object.style == .imagePlaceholder, !didDrawImage {
                context.setFillColor(NSColor.systemPurple.withAlphaComponent(0.14).cgColor)
                context.fill(rect)
                let inset = rect.insetBy(dx: max(8, 10 * viewportState.zoom.value), dy: max(8, 10 * viewportState.zoom.value))
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let missing = NSAttributedString(
                    string: "Missing image\nUse Replace… in the Image Inspector",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: max(10, 12 * viewportState.zoom.value), weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: paragraph,
                    ]
                )
                drawAppKitText(missing, in: inset, context: context)
            }
            if let border = object.border, let color = nsColor(border.rgba), border.width > 0 {
                context.saveGState()
                context.addPath(objectPath)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(border.width * viewportState.zoom.value)
                switch border.style {
                case .solid: context.setLineDash(phase: 0, lengths: [])
                case .dashed: context.setLineDash(phase: 0, lengths: [6, 4].map { $0 * viewportState.zoom.value })
                case .dotted: context.setLineDash(phase: 0, lengths: [1, 3].map { $0 * viewportState.zoom.value })
                }
                context.strokePath()
                context.restoreGState()
            } else if object.style != .imagePlaceholder || !didDrawImage {
                let baseStroke = object.style == .frameSurface
                    ? NSColor.separatorColor.withAlphaComponent(0.85)
                    : NSColor.separatorColor
                context.setStrokeColor(baseStroke.cgColor)
                context.setLineWidth(1 / max(1, viewportState.pixelRatio.value))
                context.addPath(objectPath)
                context.strokePath()
            }
            if [.frameSurface, .sectionSurface, .stackSurface, .gridSurface].contains(object.style), let name = object.displayName {
                drawFrameName(
                    name,
                    in: rect,
                    zoom: viewportState.zoom.value,
                    backgroundColor: renderedSurface,
                    context: context
                )
            }
            // Plain text is composed once by `textContainer` from the same
            // resolved viewport rect. Tile layers deliberately raster only
            // surfaces so a line crossing a tile boundary cannot duplicate,
            // flip, or drift relative to its selection frame.
            context.restoreGState()
        }
    }

    private func nsColor(_ rgba: [Double]) -> NSColor? {
        guard rgba.count == 4 else { return nil }
        return NSColor(calibratedRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    }

    private func drawAuthoredFillLayer(_ layer: CanvasAuthoredFillLayer, in rect: CGRect, context: CGContext) {
        switch layer.kind {
        case .solid:
            guard let rgba = layer.rgba, let color = nsColor(rgba) else { return }
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .linearGradient:
            guard let angle = layer.angleDegrees else { return }
            let ordered = CanvasAuthoredFillCompositor.interpolationStops(for: layer)
            let colors = ordered.compactMap { nsColor($0.rgba)?.cgColor }
            guard ordered.count >= 2,
                  colors.count == ordered.count,
                  let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors as CFArray,
                    locations: ordered.map { CGFloat($0.position) }
                  ) else { return }
            let line = CanvasAuthoredFillCompositor.normalizedGradientLine(angleDegrees: angle)
            let start = CGPoint(
                x: rect.minX + rect.width * line.start.x,
                y: rect.minY + rect.height * line.start.y
            )
            let end = CGPoint(
                x: rect.minX + rect.width * line.end.x,
                y: rect.minY + rect.height * line.end.y
            )
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
    }

    private func drawCommittedPlainText(
        _ text: String,
        in rect: CGRect,
        zoom: Double,
        context: CGContext
    ) {
        let layout = CanvasTextLayout(viewportObjectRect: rect, zoom: zoom, text: text)
        guard !layout.lineFragmentRect.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: layout.fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        drawAppKitText(attributed, in: layout.lineFragmentRect, context: context)
    }

    private func drawFrameName(
        _ name: String,
        in rect: CGRect,
        zoom: Double,
        backgroundColor: NSColor,
        context: CGContext
    ) {
        let labelRect = rect.insetBy(dx: max(6, 8 * zoom), dy: max(5, 7 * zoom))
        guard labelRect.width > 20, labelRect.height > 12 else { return }
        let deviceColor = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor
        let luminance = 0.2126 * deviceColor.redComponent
            + 0.7152 * deviceColor.greenComponent
            + 0.0722 * deviceColor.blueComponent
        // This label is native-editor chrome rather than a document property.
        // Choose its contrast from the resolved surface so it remains useful
        // with both the default pale Frame and authored dark fills.
        let foreground = luminance > 0.52
            ? NSColor.black.withAlphaComponent(0.74)
            : NSColor.white.withAlphaComponent(0.88)
        let attributed = NSAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: max(10, 12 * zoom), weight: .medium),
                .foregroundColor: foreground,
            ]
        )
        drawAppKitText(attributed, in: labelRect, context: context)
    }

    /// Converts AppKit text drawing at the tile boundary. The canonical world,
    /// viewport, device, Core Animation, overlay, event, hit-test, and
    /// snapshot convention is top-left origin with Y increasing down.
    private func drawAppKitText(_ attributed: NSAttributedString, in rect: CGRect, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.saveGState()
        defer { context.restoreGState() }
        // The enclosing tile already converted Core Graphics to SiteForge's
        // top-left coordinate space. AppKit must see that pre-flipped Core
        // Graphics basis (rather than apply a second flipped-view contract),
        // otherwise frame labels are painted upside down while their surface
        // and selection outline remain correct.
        context.clip(to: rect)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }
}

/// The one native text geometry contract shared by tile rasterization and the
/// live `NSTextView`. World, viewport, Core Animation, overlays, hit testing,
/// accessibility, and editor frames are top-left/Y-down. Only the tile's
/// Core Graphics draw boundary flips to AppKit's drawing coordinates.
struct CanvasTextLayout: Equatable {
    static let baseFontSize: CGFloat = 14
    static let baseHorizontalInset: CGFloat = 4

    let viewportObjectRect: CGRect
    let textContainerInset: NSSize
    let lineFragmentRect: CGRect
    let glyphBounds: CGRect
    let fontSize: CGFloat
    let font: NSFont
    let lineHeight: CGFloat
    let tracking: CGFloat
    let alignment: NSTextAlignment
    let paragraphStyle: NSParagraphStyle

    init(viewportObjectRect: CGRect, zoom: Double, text: String, typography: CanvasTypography? = nil) {
        self.viewportObjectRect = viewportObjectRect
        let scale = max(0.000_001, CGFloat(zoom))
        let insetX = Self.baseHorizontalInset * scale
        let usableWidth = max(0, viewportObjectRect.width - insetX * 2)
        let usableHeight = max(0, viewportObjectRect.height)
        let authoredSize = CGFloat(typography?.size ?? Double(Self.baseFontSize))
        let scaledFont = max(1, authoredSize * scale)
        fontSize = min(scaledFont, max(1, usableHeight))
        let authoredLineHeight = CGFloat(typography?.lineHeight ?? 17)
        lineHeight = min(max(fontSize * 0.5, authoredLineHeight * scale), max(1, usableHeight))
        tracking = CGFloat(typography?.tracking ?? 0) * scale
        alignment = switch typography?.alignment ?? .leading {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        font = Self.resolveFont(typography, size: fontSize)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraphStyle = paragraph.copy() as! NSParagraphStyle
        let measured = NSAttributedString(
            string: text.isEmpty ? " " : text,
            attributes: [
                .font: font,
                .kern: tracking,
                .paragraphStyle: paragraphStyle,
            ]
        ).boundingRect(
            with: CGSize(width: usableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral
        let glyphHeight = min(usableHeight, max(0, measured.height))
        let glyphY = viewportObjectRect.midY - glyphHeight / 2
        glyphBounds = CGRect(
            x: viewportObjectRect.minX + insetX,
            y: glyphY,
            width: usableWidth,
            height: glyphHeight
        )
        textContainerInset = NSSize(
            width: insetX,
            height: max(0, glyphY - viewportObjectRect.minY)
        )
        lineFragmentRect = glyphBounds
    }

    private static func resolveFont(_ typography: CanvasTypography?, size: CGFloat) -> NSFont {
        guard let typography else { return .systemFont(ofSize: size) }
        let weight: NSFont.Weight = switch typography.weight {
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        default: .regular
        }
        if typography.authoredFamily == CanonicalTypography.defaultFamily || typography.usesFallback {
            return .systemFont(ofSize: size, weight: weight)
        }
        let managerWeight: Int = switch typography.weight {
        case "medium": 6
        case "semibold": 9
        case "bold": 10
        default: 5
        }
        return NSFontManager.shared.font(withFamily: typography.resolvedFamily, traits: [], weight: managerWeight, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }

    var isInsideObjectRect: Bool {
        viewportObjectRect.contains(glyphBounds) || glyphBounds.isEmpty
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
