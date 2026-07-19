import SwiftUI
import AppKit

struct WorkspaceShellView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var focusedControl: ShellFocus?

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

                CanvasPlaceholderView(state: state, focus: $focusedControl)
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
        .accessibilityIdentifier("workspace.shell")
        .background {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                WindowCloseGuard(controller: state.lifecycle).frame(width: 0, height: 0)
                WorkspaceWindowConfigurator().frame(width: 0, height: 0)
            }
        }
        .navigationTitle(state.lifecycle.title)
        .toolbar {
            WorkspaceToolbar(state: state)
        }
        .sheet(isPresented: $state.isPreviewPresented) {
            PreviewPlaceholderView()
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
        .alert("Save changes before closing?", isPresented: Binding(
            get: { state.lifecycle.isCloseConfirmationPresented },
            set: { state.lifecycle.isCloseConfirmationPresented = $0 }
        )) {
            Button("Save") { Task { await state.lifecycle.saveAndClose() } }
                .keyboardShortcut(.defaultAction)
            Button("Discard Changes", role: .destructive) { state.lifecycle.discardAndClose() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved changes in \(state.lifecycle.displayName) will otherwise be lost.")
        }
        .onKeyPress(.tab) {
            guard focusedControl == .navigatorLayers else { return .ignored }
            focusedControl = .viewportPreset
            return .handled
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
            Button("Restore") { controller.restoreRecovery() }
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
            guard controller.requestClose() else { return false }
            return priorDelegate?.windowShouldClose?(sender) ?? true
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
                ContentUnavailableView {
                    Label("No Layers Yet", systemImage: "square.3.layers.3d")
                } description: {
                    Text("Layers will appear here when document editing is implemented.")
                } actions: {
                    Button("Add Layer") {}
                        .disabled(true)
                        .help("Available after the document editing interface is implemented")
                        .accessibilityIdentifier("navigator.empty.action")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("navigator.empty")
            }
        }
        .padding(10)
        .workspaceChrome(.navigator)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.navigator.rawValue)
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
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Use Up and Down Arrow to navigate pages")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("navigator.page.\(page.role.rawValue)")
    }
}

private struct CanvasPlaceholderView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            ViewportControlsView(state: state, focus: focus)
            Divider()

            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    let availableWidth = max(360, geometry.size.width - 96)
                    let availableHeight = max(300, geometry.size.height - 96)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                        .stroke(.separator, lineWidth: 1)
                        .frame(width: min(680, availableWidth), height: min(440, availableHeight))
                        .overlay {
                            ContentUnavailableView(
                                "Canvas Ready",
                                systemImage: "rectangle.dashed",
                                description: Text("The rendering engine will connect here in a later milestone.")
                            )
                            .padding(20)
                            .accessibilityIdentifier("canvas.empty")
                        }
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                        .padding(48)
                        .contentShape(Rectangle())
                        .onTapGesture { state.noteCanvasInteraction() }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Canvas interaction area")
                        .accessibilityValue("Interactions: \(state.canvasInteractionCount)")
                        .accessibilityAction { state.noteCanvasInteraction() }
                        .accessibilityIdentifier("canvas.interaction")
                }
                .accessibilityIdentifier("canvas.scroll")
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.canvas.rawValue)
    }
}

private struct ViewportControlsView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Label("Viewport", systemImage: "display")
                .font(.caption.weight(.semibold))

            Picker("Viewport preset", selection: $state.viewportPreset) {
                ForEach(ViewportPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .focusable()
            .focused(focus, equals: .viewportPreset)
            .accessibilityIdentifier("canvas.viewport.preset")

            Text("\(state.viewportPreset.width) px")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("canvas.viewport.width")

            Spacer(minLength: 8)

            Button("Zoom out", systemImage: "minus") {
                state.adjustZoom(by: -25)
            }
            .labelStyle(.iconOnly)
            .disabled(state.zoomPercent == 25)
            .accessibilityIdentifier("canvas.zoom.out")

            Text("\(state.zoomPercent)%")
                .monospacedDigit()
                .frame(minWidth: 42)
                .accessibilityIdentifier("canvas.zoom.value")

            Button("Zoom in", systemImage: "plus") {
                state.adjustZoom(by: 25)
            }
            .labelStyle(.iconOnly)
            .disabled(state.zoomPercent == 200)
            .accessibilityIdentifier("canvas.zoom.in")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .workspaceChrome(.viewportControls)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.viewport.controls")
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

            ContentUnavailableView(
                "Nothing Selected",
                systemImage: "slider.horizontal.3",
                description: Text("Select an object to inspect its \(state.inspectorTab.title.lowercased()) properties.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("inspector.empty")
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
                .accessibilityIdentifier("status.zoom")
            Divider().frame(height: 14)
            Label(state.viewportPreset.title, systemImage: "rectangle.split.3x1")
                .accessibilityLabel("Active breakpoint: \(state.viewportPreset.title)")
                .accessibilityIdentifier("status.breakpoint")
            Divider().frame(height: 14)
            Label("No selection", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .accessibilityLabel("Selection path: No selection")
                .accessibilityIdentifier("status.selectionPath")
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 42))
                .accessibilityHidden(true)
            Text("Preview Placeholder")
                .font(.title2)
            Text("Live preview is intentionally deferred to a later milestone.")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
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
    @ObservedObject var state: WorkspaceShellState
    @ObservedObject var launchExperience: LaunchExperienceController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { launchExperience.createBlankProject() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { launchExperience.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                if state.lifecycle.fileURL == nil { state.lifecycle.presentSavePanel() }
                else { Task { _ = await state.lifecycle.save() } }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!launchExperience.isWorkspaceVisible || !state.lifecycle.canSave)
            Button("Save As…") { state.lifecycle.presentSavePanel() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!launchExperience.isWorkspaceVisible)
            Button("Revert to Saved") { Task { await state.lifecycle.revert() } }
                .disabled(!launchExperience.isWorkspaceVisible || !state.lifecycle.canRevert)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                state.undo()
            }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!launchExperience.isWorkspaceVisible || !state.canUndo)
            Button("Redo") {
                state.redo()
            }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!launchExperience.isWorkspaceVisible || !state.canRedo)
        }

        CommandMenu("Tools") {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    state.selectTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
                .keyboardShortcut(tool.shortcut, modifiers: [])
            }
        }

        CommandMenu("Preview") {
            Button("Open Preview") {
                state.isPreviewPresented = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}
