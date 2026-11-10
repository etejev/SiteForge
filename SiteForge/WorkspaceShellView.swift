import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

/// Project content, deliberately separate from application appearance settings.
/// The opening identity remains fixed for the entire draft; a changed document
/// is rejected by the registry instead of silently rebasing an old form.
private struct WebsiteSettingsView: View {
    @ObservedObject var state: WorkspaceShellState
    let identity: DesignInspectorOperationIdentity
    @State private var openingDocument: CanonicalDocument
    private var initial: WebsiteMetadata? { openingDocument.websiteMetadata }
    private var pageName: String {
        openingDocument.pages.first { $0.id == identity.pageID }?.name ?? "Page"
    }
    @State private var siteName: String
    @State private var titlePattern: String
    @State private var description: String
    @State private var pageTitle: String
    @State private var pageDescription: String
    @State private var favicon: AssetID?
    @State private var indexing: Bool
    @State private var pageIndexing: Bool?

    init(state: WorkspaceShellState, identity: DesignInspectorOperationIdentity) {
        self.state = state; self.identity = identity
        let document = state.documentSession.document
        _openingDocument = State(initialValue: document)
        let initial = document.websiteMetadata
        let override = initial?.pages.first { $0.pageID == identity.pageID }
        _siteName = State(initialValue: initial?.siteName ?? "")
        _titlePattern = State(initialValue: initial?.titlePattern ?? "")
        _description = State(initialValue: initial?.defaultDescription ?? "")
        _pageTitle = State(initialValue: override?.title ?? "")
        _pageDescription = State(initialValue: override?.description ?? "")
        _favicon = State(initialValue: initial?.faviconAssetID)
        _indexing = State(initialValue: initial?.allowsIndexing ?? true)
        _pageIndexing = State(initialValue: override?.allowsIndexing)
    }

    private func optional(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        return value.isEmpty ? nil : value
    }
    private var draft: WebsiteMetadata {
        let page = PageWebsiteMetadata(pageID: identity.pageID, title: optional(pageTitle),
            description: optional(pageDescription),
            allowsIndexing: pageIndexing)
        return WebsiteMetadata(siteName: optional(siteName), titlePattern: optional(titlePattern),
            defaultDescription: optional(description), faviconAssetID: favicon,
            allowsIndexing: indexing == (initial?.allowsIndexing ?? true) ? initial?.allowsIndexing : indexing,
            pages: initial?.pages ?? []).replacingPageOverride(page)
    }
    private var preview: ResolvedWebsiteMetadata? {
        // Preview the opening document + this local draft. A page/document
        // change cannot silently retarget the snippet or bypass Apply's guard.
        var document = openingDocument
        document.websiteMetadata = draft
        return document.pages.first { $0.id == identity.pageID }.map {
            WebsiteMetadataResolver.resolve(page: $0, document: document)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Site & Page Settings").font(.title2.bold())
            Text("Website content · saved with this project, not SiteForge preferences")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                    Section("Website") {
                        TextField("Site Name", text: $siteName)
                            .accessibilityIdentifier("siteSettings.siteName")
                        TextField("Browser title pattern", text: $titlePattern, prompt: Text("{page}"))
                            .accessibilityIdentifier("siteSettings.titlePattern")
                        Text("Use {page} and {site}, for example {page} | {site}. Blank uses the page name.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Default Description", text: $description, axis: .vertical)
                            .lineLimit(2...4).accessibilityIdentifier("siteSettings.description")
                        Picker("Favicon", selection: $favicon) {
                            Text("None").tag(AssetID?.none)
                            ForEach(openingDocument.imageAssets) { asset in
                                Text(asset.displayName).tag(Optional(asset.id))
                            }
                            if let favicon, !openingDocument.imageAssets.contains(where: { $0.id == favicon }) {
                                Text("Missing image — choose a replacement").tag(Optional(favicon))
                            }
                        }.accessibilityIdentifier("siteSettings.favicon")
                        if let favicon, !openingDocument.imageAssets.contains(where: { $0.id == favicon }) {
                            Text("The favicon reference is retained. Choose an imported image or None to repair it; original files are not modified.")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("siteSettings.faviconMissing")
                        } else {
                            Text("Uses an image from Assets. Import there first; the original bytes remain in the project resources.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Allow search indexing", isOn: $indexing)
                            .accessibilityIdentifier("siteSettings.indexing")
                        Text("A local robots preference, not a guarantee that a search service will index or remove a page.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Current page: \(pageName)") {
                        if let page = openingDocument.pages.first(where: { $0.id == identity.pageID }) {
                            LabeledContent("Route", value: page.route.rawValue)
                                .accessibilityIdentifier("siteSettings.pageRoute")
                            Text("The page name supplies its default navigation label. Rename Page and Edit Route are in Page Actions; authored link labels remain independent.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("Page Title", text: $pageTitle, prompt: Text("Uses website default"))
                            .accessibilityIdentifier("siteSettings.pageTitle")
                        TextField("Page Description", text: $pageDescription, axis: .vertical)
                            .lineLimit(2...4).accessibilityIdentifier("siteSettings.pageDescription")
                        Picker("Page indexing", selection: $pageIndexing) {
                            Text("Inherit website preference").tag(Bool?.none)
                            Text("Allow indexing").tag(Optional(true))
                            Text("Discourage indexing").tag(Optional(false))
                        }.accessibilityIdentifier("siteSettings.pageIndexing")
                        Text("Blank title and description inherit website defaults. Page overrides affect this page only.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Use website defaults") { pageTitle = ""; pageDescription = ""; pageIndexing = nil }
                            .accessibilityIdentifier("siteSettings.pageReset")
                    }
            }.formStyle(.grouped)
            .accessibilityLabel("Website and current page settings")
            .accessibilityIdentifier("siteSettings.form")
            GroupBox("Local Snippet Preview") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview?.title ?? pageName).font(.headline).lineLimit(2)
                        .accessibilityIdentifier("siteSettings.previewTitle")
                    Text(preview?.description ?? "No description").foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityIdentifier("siteSettings.previewDescription")
                    Text("Title: \(preview?.titleSource.presentation ?? "Not set") · Description: \(preview?.descriptionSource.presentation ?? "Not set")")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("siteSettings.previewSources")
                    Text("Draft preview only. Browser/social services choose their own presentation; no account or live indexing check is connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            if !state.websiteSettingsStatus.isEmpty {
                Text(state.websiteSettingsStatus).font(.callout)
                    .accessibilityIdentifier("siteSettings.status")
            }
            HStack {
                Spacer()
                Button("Cancel") { state.isWebsiteSettingsPresented = false }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    if state.commitWebsiteSettings(draft.isEmpty ? nil : draft, identity: identity) {
                        state.isWebsiteSettingsPresented = false
                    }
                }.keyboardShortcut(.defaultAction).accessibilityIdentifier("siteSettings.apply")
            }
        }.padding(24).frame(width: 580, height: 640)
    }
}

private struct WorkspaceKeyboardFocusVisibilityKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var workspaceKeyboardFocusVisible: Bool {
        get { self[WorkspaceKeyboardFocusVisibilityKey.self] }
        set { self[WorkspaceKeyboardFocusVisibilityKey.self] = newValue }
    }
}

struct WorkspaceShellView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var focusedControl: ShellFocus?
    @StateObject private var tabRouter = WorkspaceWindowTabRouter()
    @ScaledMetric(relativeTo: .caption) private var tabLabelSize: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            if state.lifecycle.recoveryCandidate != nil {
                RecoveryCandidateBar(controller: state.lifecycle)
            }
            GeometryReader { geometry in
            let tabGutters = 2 * (SiteForgeVisualSystem.panePadding + SiteForgeVisualSystem.tabStripInset)
            let panes = WorkspaceMetrics.sidePaneAllocation(windowWidth: geometry.size.width,
                navigatorRequired: tabGutters + CGFloat(ShellTabLayoutPolicy.requiredWidth(minimumWidths:
                    ShellTabLayoutPolicy.measuredMinimumWidths(labels: NavigatorTab.allCases.map(\.title), fontSize: tabLabelSize),
                    gap: SiteForgeVisualSystem.hairlineSpacing)),
                inspectorRequired: tabGutters + CGFloat(ShellTabLayoutPolicy.requiredWidth(minimumWidths:
                    ShellTabLayoutPolicy.measuredMinimumWidths(labels: InspectorTab.allCases.map(\.title), fontSize: tabLabelSize),
                    gap: SiteForgeVisualSystem.hairlineSpacing)))
            HSplitView {
                if !state.isFocusModeEnabled {
                    NavigatorView(state: state, focus: $focusedControl)
                        .frame(
                            minWidth: panes.navigatorMinimum,
                            idealWidth: max(panes.navigatorMinimum, min(SiteForgeVisualSystem.navigatorIdealWidth, panes.navigatorMaximum)),
                            maxWidth: panes.navigatorMaximum
                        )
                }

                CanvasPlaceholderView(state: state, focus: $focusedControl, tabRouter: tabRouter)
                    .frame(minWidth: WorkspaceMetrics.minimumCanvasWidth, maxWidth: .infinity)
                    .layoutPriority(1)

                if !state.isFocusModeEnabled {
                    InspectorView(state: state, focus: $focusedControl)
                        .frame(
                            minWidth: panes.inspectorMinimum,
                            idealWidth: max(panes.inspectorMinimum, min(SiteForgeVisualSystem.inspectorIdealWidth, panes.inspectorMaximum)),
                            maxWidth: panes.inspectorMaximum
                        )
                }
            }
            }

            if !state.isFocusModeEnabled {
                Divider()
                StatusBarView(state: state)
            }
        }
        .frame(
            minWidth: WorkspaceMetrics.effectiveMinimumWindowSize().width,
            minHeight: WorkspaceMetrics.effectiveMinimumWindowSize().height
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SiteForge workspace")
        .accessibilityIdentifier("workspace.shell")
        .task(id: state.formattingActionCapture) { await state.prepareFormattingCopies() }
        .onDisappear { state.cancelFormattingTransferIfPending(); state.cancelPageChromeCopyPreparation(); state.cancelBuildFindingReveal(silent: true) }
        .background {
            ZStack {
                SiteForgeVisualSystem.canvasPasteboard
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
        .modifier(WorkspaceDocumentTitle(lifecycle: state.lifecycle))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !state.workspaceActionStatus.isEmpty {
                Text(state.workspaceActionStatus).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SiteForgeVisualSystem.controlInset)
                    .accessibilityIdentifier("workspace.editBoundary.status")
            }
        }
        .environment(\.workspaceKeyboardFocusVisible, tabRouter.keyboardFocusIsVisible)
        .sheet(item: $state.pageEditorRequest) { request in
            PageEditorSheet(state: state, request: request)
        }
        .sheet(item: $state.pageChromeCopySheet, onDismiss: state.cancelPageChromeCopyPreparation) { request in
            PageChromeCopySheet(state: state, request: request)
        }
        .sheet(isPresented: $state.isWebsiteSettingsPresented) {
            if let identity = state.websiteSettingsDraftIdentity {
                WebsiteSettingsView(state: state, identity: identity)
            }
        }
        .sheet(isPresented: $state.isQuickOpenPresented, onDismiss: state.completeQuickOpenDismissal) {
            QuickOpenSheet(state: state)
        }
        .toolbar {
            WorkspaceToolbar(state: state)
        }
        .sheet(isPresented: $state.isPreviewPresented, onDismiss: {
            state.closePreview()
            DispatchQueue.main.async {
                focusedControl = .navigatorPages
            }
        }) {
            LocalPreviewView(state: state)
        }
        .sheet(isPresented: $state.isBuildDiagnosticsPresented, onDismiss: {
            state.cancelStaticBuild(silent: true)
            state.cancelBuildFindingReveal()
            restoreBuildFindingFocus(returnToPages: false)
        }) {
            StaticBuildDiagnosticsView(state: state)
        }
        .sheet(isPresented: $state.isBrowserPreviewPresented, onDismiss: {
            state.cancelBuildFindingReveal()
            restoreBuildFindingFocus()
        }) {
            BrowserPreviewPanel(controller: state.browserPreview,
                                refresh: state.refreshBrowserPreview,
                                dismiss: { state.isBrowserPreviewPresented = false },
                                availability: { state.buildFindingRevealAvailability($0, receipt: $1, source: .browserPreview) },
                                reveal: { _ = state.revealBrowserBuildFinding($0, receipt: $1) },
                                repairStatus: state.buildFindingRevealStatus,
                                isOpeningFinding: state.isOpeningBuildFinding,
                                isAdoptingFinding: state.isAdoptingBuildFinding)
        }
        .sheet(isPresented: $state.isClipboardComponentPreflightPresented, onDismiss: {
            state.cancelCrossProjectComponentPaste()
        }) {
            ClipboardComponentTransferPreflightView(state: state)
        }
        .sheet(isPresented: Binding(
            get: { state.lifecycle.isRecoveryDetailsPresented },
            set: { state.lifecycle.isRecoveryDetailsPresented = $0 }
        )) {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
                Text("Recovery Details").font(.title2)
                Text(state.lifecycle.recoveryCandidate?.summary ?? "No valid recovery candidate is available.")
                Text("Project content and complete file paths are excluded from these details.")
                    .foregroundStyle(.secondary)
                Button("Done") { state.lifecycle.isRecoveryDetailsPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("recovery.details.done")
            }
            .padding(SiteForgeVisualSystem.settingsFormPadding).frame(minWidth: 420)
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
    private func restoreBuildFindingFocus(returnToPages: Bool = true) {
        let requestID = state.buildFindingEditorRequest?.id
        DispatchQueue.main.async {
            guard state.hasCurrentBuildFindingEditorRequest, state.buildFindingEditorRequest?.id == requestID,
                  let request = state.buildFindingEditorRequest else {
                if returnToPages { focusedControl = .navigatorPages }
                return
            }
            focusedControl = switch request.inspectorTab {
            case .design: .inspectorDesign
            case .layout: .inspectorLayout
            case .content: .inspectorContent
            case .interactions: .inspectorInteractions
            case .accessibility: .inspectorAccessibility
            }
        }
    }
}

private struct RecoveryCandidateBar: View {
    @ObservedObject var controller: DocumentLifecycleController

    var body: some View {
        HStack(spacing: SiteForgeVisualSystem.standardSpacing) {
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
            guard state.prepareForWorkspaceAction(.close) else { return false }
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

private struct WorkspaceDocumentTitle: ViewModifier {
    @ObservedObject var lifecycle: DocumentLifecycleController
    func body(content: Content) -> some View {
        // The lifecycle, not the outer shell's layout/selection publications,
        // owns Save As, external rename and Edited title transitions.
        content.navigationTitle(lifecycle.title)
    }
}

private struct WorkspaceToolbar: ToolbarContent {
    @ObservedObject var state: WorkspaceShellState
    @FocusedValue(\.siteforgeNativeTextEditor) private var nativeTextEditor
    private var textEditorIsActive: Bool { nativeTextEditor == true || NSApp.keyWindow?.firstResponder is NSTextView }

    var body: some ToolbarContent {
        if state.isFocusModeEnabled {
            ToolbarItem(placement: .primaryAction) {
                Button("Exit Focus", systemImage: "arrow.down.right.and.arrow.up.left") {
                    state.toggleFocusMode()
                }
                .help("Return to the full editor")
                .accessibilityIdentifier("toolbar.focus.exit")
            }
        } else {
            if #available(macOS 26.0, *) {
                editorToolbar.sharedBackgroundVisibility(.hidden)
            } else {
                editorToolbar
            }
        }
    }

    @ToolbarContentBuilder private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ForEach(CanvasTool.primaryToolbarTools) { tool in
                Button {
                    state.selectTool(tool)
                } label: {
                    Image(systemName: tool.systemImage)
                }
                .accessibilityLabel(tool.title)
                .help("\(tool.title) tool (\(tool.shortcut.character.uppercased()))")
                .accessibilityIdentifier("toolbar.tool.\(tool.rawValue)")
                .accessibilityValue(state.selectedTool == tool ? "Selected" : "Not selected")
            }

            Menu {
                ForEach(CanvasTool.additionalToolbarTools) { tool in
                    Button {
                        state.selectTool(tool)
                    } label: {
                        Label(tool.title, systemImage: tool.systemImage)
                    }
                    .accessibilityIdentifier("toolbar.moreTool.\(tool.rawValue)")
                    .accessibilityValue(state.selectedTool == tool ? "Selected" : "Not selected")
                }
            } label: {
                Label("Insert", systemImage: "plus")
            }
            .help("Section, Stack, Grid, Button, Link, and Form tools")
            .accessibilityLabel("More authoring tools")
            .accessibilityValue(
                CanvasTool.additionalToolbarTools.contains(state.selectedTool)
                    ? "Selected: \(state.selectedTool.title)"
                    : "No additional tool selected"
            )
            .accessibilityIdentifier("toolbar.moreTools")
        }

        ToolbarItemGroup(placement: .automatic) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                if textEditorIsActive { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                else { state.undo() }
            }
                .disabled(!textEditorIsActive && !state.canUndo)
                .help(textEditorIsActive ? "Undo native text editing" : state.undoDisabledReason ?? "Undo the last document command")
                .accessibilityIdentifier("toolbar.undo")
                .accessibilityValue(textEditorIsActive ? "Text editing" : state.nextUndoLabel ?? "Unavailable")
                .accessibilityHint(state.undoDisabledReason ?? "Undo the last committed document command")

            Button("Redo", systemImage: "arrow.uturn.forward") {
                if textEditorIsActive { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                else { state.redo() }
            }
                .disabled(!textEditorIsActive && !state.canRedo)
                .help(textEditorIsActive ? "Redo native text editing" : state.redoDisabledReason ?? "Redo the last undone document command")
                .accessibilityIdentifier("toolbar.redo")
                .accessibilityValue(textEditorIsActive ? "Text editing" : state.nextRedoLabel ?? "Unavailable")
                .accessibilityHint(state.redoDisabledReason ?? "Redo the last undone document command")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                state.openBrowserPreview()
            } label: {
                Label("Preview", systemImage: "play.fill")
            }
            .help("Build the website and open it locally in Safari")
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
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12
    @Environment(\.workspaceKeyboardFocusVisible) private var keyboardFocusVisible
    private var rowHeight: CGFloat { ShellTabLayoutPolicy.rowHeight(fontSize: labelSize) }

    var body: some View {
        GeometryReader { geometry in
            let values = Array(tabs)
            let minimum = ShellTabLayoutPolicy.measuredMinimumWidths(labels: values.map(title), fontSize: labelSize)
            let allocation = ShellTabLayoutPolicy.allocate(width: geometry.size.width,
                minimumWidths: minimum, selected: values.firstIndex(of: selection) ?? 0,
                gap: SiteForgeVisualSystem.hairlineSpacing)
            HStack(spacing: SiteForgeVisualSystem.hairlineSpacing) {
                ForEach(Array(allocation.indices.enumerated()), id: \.element) { offset, index in
                    tabButton(values[index])
                        .frame(width: allocation.widths[offset], height: rowHeight)
                }
                if allocation.overflow {
                    overflowMenu(fullWidth: allocation.indices.isEmpty)
                        .frame(width: allocation.menuWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight,
               maxHeight: rowHeight, alignment: .leading)
        .padding(SiteForgeVisualSystem.tabStripInset)
        .background(SiteForgeVisualSystem.tabStripSurface,
                    in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius, style: .continuous)
                .strokeBorder(SiteForgeVisualSystem.quietBoundary, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifierPrefix + ".bar")
    }

    private func overflowMenu(fullWidth: Bool) -> some View {
        let overflowFocus: ShellFocus = identifierPrefix.hasPrefix("navigator") ? .navigatorOverflow : .inspectorOverflow
        return NativeShellTabOverflow(
            choices: tabs.map { ($0.rawValue, title($0)) }, selected: selection.rawValue,
            selectedTitle: title(selection), fullWidth: fullWidth,
            fontSize: labelSize,
            identifier: identifierPrefix + ".overflow", keyboardFocusVisible: keyboardFocusVisible,
            wantsFocus: focus.wrappedValue == overflowFocus,
            onFocus: { focus.wrappedValue = overflowFocus },
            onSelect: { rawValue in
                guard let tab = tabs.first(where: { $0.rawValue == rawValue }) else { return }
                selection = tab
                focus.wrappedValue = focusValue(tab)
            })
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .layoutPriority(1)
        .help("Show all \(identifierPrefix.hasPrefix("navigator") ? "navigator" : "Inspector") tabs")
        .accessibilityLabel("Show all tabs")
        .accessibilityValue(title(selection))
        .accessibilityIdentifier("\(identifierPrefix).overflow")
    }

    /*
     A second-row fallback is intentionally forbidden. At supported workspace
     widths the direct row fits; below that boundary complete segments and an
     explicit native overflow menu retain keyboard/VoiceOver access.
     */

    @ViewBuilder
    private func tabButton(_ tab: Tab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(title(tab))
                .font(.system(size: labelSize, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, SiteForgeVisualSystem.microSpacing)
                .padding(.vertical, SiteForgeVisualSystem.compactSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SiteForgeRowSurface(selected: selection == tab))
        .focusable()
        // Keep native keyboard ownership; pointer selection uses only the
        // selected segment surface, not a second persistent outer ring.
        .focusEffectDisabled(!keyboardFocusVisible)
        .focused(focus, equals: focusValue(tab))
        .accessibilityIdentifier("\(identifierPrefix).\(tab.rawValue)")
        .accessibilityHint(accessibilityDescription(tab) ?? "")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

/// A real native pull-down menu keeps the overflow affordance in AppKit's key
/// view loop and exposes a focused AX element, unlike SwiftUI's KeyViewProxy.
private struct NativeShellTabOverflow: NSViewRepresentable {
    let choices: [(String, String)]
    let selected: String
    let selectedTitle: String
    let fullWidth: Bool
    let fontSize: CGFloat
    let identifier: String
    let keyboardFocusVisible: Bool
    let wantsFocus: Bool
    let onFocus: () -> Void
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ShellTabOverflowPopUpButton {
        let button = ShellTabOverflowPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.controlSize = .small
        button.setAccessibilityLabel("Show all tabs")
        button.onFocus = { [weak coordinator = context.coordinator] in
            guard let coordinator, !coordinator.adoptingFocus else { return }
            coordinator.onFocus?()
        }
        return button
    }

    func updateNSView(_ button: ShellTabOverflowPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.onFocus = onFocus
        coordinator.onSelect = onSelect
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityValue(selectedTitle)
        button.focusRingType = keyboardFocusVisible ? .default : .none
        let signature = choices.map { $0.0 + ":" + $0.1 }.joined(separator: "|") + selected + String(fullWidth)
        if coordinator.menuSignature != signature {
            let menu = NSMenu(title: "Show all tabs")
            menu.addItem(withTitle: fullWidth ? selectedTitle : "", action: nil, keyEquivalent: "")
            for (value, title) in choices {
                let item = NSMenuItem(title: title, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
                item.target = coordinator
                item.representedObject = value
                item.state = value == selected ? .on : .off
                menu.addItem(item)
            }
            button.menu = menu
            coordinator.menuSignature = signature
        }
        button.updateDisplayedItem(title: selectedTitle, fullWidth: fullWidth, fontSize: fontSize)
        button.setAccessibilityValue(selectedTitle)
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        if wantsFocus, !coordinator.wasFocusRequested, let window = button.window, window.isKeyWindow {
            coordinator.adoptingFocus = true
            _ = window.makeFirstResponder(button)
            coordinator.adoptingFocus = false
        }
        coordinator.wasFocusRequested = wantsFocus
    }

    static func dismantleNSView(_ view: ShellTabOverflowPopUpButton, coordinator: Coordinator) {
        view.onFocus = nil
        coordinator.onFocus = nil
        coordinator.onSelect = nil
    }

    @MainActor final class Coordinator: NSObject {
        var menuSignature = ""
        var adoptingFocus = false
        var wasFocusRequested = false
        var onFocus: (() -> Void)?
        var onSelect: ((String) -> Void)?
        @objc func choose(_ item: NSMenuItem) {
            if let value = item.representedObject as? String { onSelect?(value) }
        }
    }
}

final class ShellTabOverflowPopUpButton: NSPopUpButton {
    var onFocus: (() -> Void)?
    func updateDisplayedItem(title: String, fullWidth: Bool, fontSize: CGFloat) {
        // Pull-down buttons paint their first menu item, not NSButton.image.
        // Setting only the latter leaves a real but completely invisible target.
        guard let displayed = item(at: 0) else { return }
        displayed.title = fullWidth ? title : ""
        let icon = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        icon?.isTemplate = true
        displayed.image = icon
        imagePosition = fullWidth ? .imageTrailing : .imageOnly
        font = .systemFont(ofSize: fontSize)
        menu?.font = .menuFont(ofSize: max(NSFont.systemFontSize, fontSize))
        contentTintColor = .labelColor
    }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
    override func mouseDown(with event: NSEvent) {
        _ = window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

private struct NavigatorView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding

    @ViewBuilder private var pageManagementControls: some View {
        Button("New Page…", systemImage: "doc.badge.plus") { state.presentPageEditor(.create) }
            .disabled(!state.pageEditingIsAvailable).lineLimit(1)
            .accessibilityIdentifier("navigator.pages.new")
        if let page = state.pages.first(where: { $0.id == state.effectiveSelectedPageID }) {
            Button("Site & Page Settings…", systemImage: "globe") { state.presentWebsiteSettings() }
                .disabled(state.websiteSettingsIdentity == nil).lineLimit(1)
                .help("Edit website defaults, this page's browser title and description, and the favicon.")
                .accessibilityIdentifier("navigator.pages.siteSettings")
            Button("Page Background…", systemImage: "paintpalette") { state.revealPageBackground(pageID: page.id) }
                .disabled(!state.pageEditingIsAvailable || state.pageBackgroundUnavailableReason != nil)
                .lineLimit(1)
                .help(state.pageBackgroundUnavailableReason ?? "Edit this page's solid, gradient or token background in Design.")
                .accessibilityValue(state.pageBackgroundSummary)
                .accessibilityIdentifier("navigator.pages.background")
            Menu("Page Actions") { PageActionButtons(state: state, page: page) }
                .disabled(!state.pageEditingIsAvailable).lineLimit(1)
                .accessibilityIdentifier("navigator.pages.actions")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
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

            Button("Quick Open…", systemImage: "magnifyingglass") {
                state.isQuickOpenPresented = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("navigator.quickOpen")

            if state.navigatorTab == .pages {
                HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                    TextField("Search Pages", text: $state.pageSearchText)
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                        .accessibilityLabel("Search pages by name or route")
                        .accessibilityIdentifier("navigator.pages.search")
                        .onSubmit { state.openFirstMatchingPage() }
                        .onExitCommand { state.clearPageSearch() }
                    if !state.pageSearchText.isEmpty {
                        Button("Clear Search", systemImage: "xmark.circle.fill") { state.clearPageSearch() }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("navigator.pages.search.clear")
                    }
                }
                Text(state.pageSearchSummary)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("navigator.pages.search.status")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SiteForgeVisualSystem.compactSpacing) { pageManagementControls }
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) { pageManagementControls }
                }
                ScrollView {
                    LazyVStack(spacing: SiteForgeVisualSystem.microSpacing) {
                        if state.filteredPages.isEmpty {
                            ContentUnavailableView.search(text: state.pageSearchText)
                                .accessibilityIdentifier("navigator.pages.search.empty")
                        }
                        if let selected = state.pages.first(where: { $0.id == state.effectiveSelectedPageID }),
                           !state.filteredPages.contains(where: { $0.id == selected.id }) {
                            Button("Show Selected Page") { state.clearPageSearch() }
                                .accessibilityIdentifier("navigator.pages.search.showSelected")
                        }
                        ForEach(state.filteredPages) { page in
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
                HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                    TextField("Search Layers", text: $state.layerSearchText)
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                        .accessibilityLabel("Search layers by name")
                        .accessibilityIdentifier("navigator.layers.search")
                        .onSubmit { state.selectFirstMatchingLayer() }
                        .onExitCommand { state.clearLayerSearch() }
                    if !state.layerSearchText.isEmpty {
                        Button("Clear Search", systemImage: "xmark.circle.fill") { state.clearLayerSearch() }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("navigator.layers.search.clear")
                    }
                }
                Picker("Layer Type", selection: $state.layerKindFilter) {
                    Text("All Types").tag(nil as NodeKind?)
                    ForEach(NodeKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(Optional(kind))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("navigator.layers.typeFilter")
                if state.layerKindFilter != nil {
                    Button("Clear Layer Filters") { state.clearLayerFilters() }
                        .accessibilityIdentifier("navigator.layers.filters.clear")
                }
                Text(state.layerSearchSummary)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("navigator.layers.search.status")
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
                        LazyVStack(spacing: SiteForgeVisualSystem.microSpacing) {
                            if state.filteredLayerTargets.isEmpty {
                                ContentUnavailableView.search(text: state.layerSearchText)
                                    .accessibilityIdentifier("navigator.layers.search.empty")
                            }
                            if let selectedID = state.selectionState.primaryID,
                               state.layerTargets.contains(where: { $0.id == selectedID }),
                               !state.filteredLayerTargets.contains(where: { $0.id == selectedID }) {
                                Button("Show Selected Layer") { state.clearLayerFilters() }
                                    .accessibilityIdentifier("navigator.layers.search.showSelected")
                            }
                            ForEach(state.filteredLayerTargets, id: \.id) { target in
                                NavigatorLayerRow(target: target, state: state, focus: focus)
                            }
                            if let instance = state.selectedComponent {
                                ForEach(state.componentVisibilityProperties) { property in
                                    let authored = CanonicalComponentVisibility.overrides(on: instance)[property.id]
                                    HStack {
                                        Image(systemName: (authored ?? property.defaultValue) ? "eye" : "eye.slash")
                                        Text(property.label).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text((authored ?? property.defaultValue) ? "Visible" : "Hidden in instance")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, SiteForgeVisualSystem.controlInset).padding(.vertical, 5)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("Component child \(property.label)")
                                    .accessibilityValue("\((authored ?? property.defaultValue) ? "Visible" : "Hidden"); \(authored == nil ? "definition default" : "instance override")")
                                    .accessibilityHint("Select the instance and use Content to show, hide, or reset this child.")
                                    .accessibilityIdentifier("navigator.componentVisibility.\(property.id)")
                                }
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
                ComponentsNavigatorView(state: state)
                    .id(NavigatorTab.components)
            }
        }
        .padding(SiteForgeVisualSystem.panePadding)
        .workspaceChrome(.navigator)
        .groupBoxStyle(SiteForgeInspectorGroupStyle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.navigator.rawValue)
    }
}

private struct QuickOpenSheet: View {
    @ObservedObject var state: WorkspaceShellState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var scope: QuickOpenScope = .all

    private var results: (pages: [DocumentPage], layers: [SelectionTargetSnapshot], actions: [QuickOpenViewAction], insertions: [QuickOpenInsertAction], pageActions: [QuickOpenPageAction], assets: [ImageAsset], components: [DocumentPage]) {
        QuickOpenSearchPolicy.results(
            pages: state.pages, layers: state.layerTargets, query: query, scope: scope,
            hasSelectedImageAsset: state.selectedAssetID != nil,
            assets: state.documentSession.document.imageAssets,
            components: state.componentDefinitions
        )
    }

    private func queueNewPageEditor() {
        guard state.queueQuickOpenNewPage() else { return }
        dismiss()
    }

    private func openFirst() {
        if scope.includesPages, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let recent = state.recentQuickOpenPages.first { state.selectPage(recent.id) }
        else if scope.includesLayers, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let recentLayer = state.recentQuickOpenLayers.first { state.selectLayer(recentLayer.id) }
        else if let page = results.pages.first { state.selectPage(page.id) }
        else if let layer = results.layers.first { state.selectLayer(layer.id) }
        else if let action = results.actions.first { action.perform(on: state) }
        else if results.pageActions.contains(.newPage) {
            queueNewPageEditor()
            return
        }
        else if let action = results.insertions.first(where: { $0.isAvailable(on: state) }) {
            guard action.perform(on: state) else { return }
        }
        else if let asset = results.assets.first {
            guard state.revealImageAsset(asset.id) else { return }
        }
        else if let component = results.components.first {
            guard state.revealComponentDefinition(component.id) else { return }
        }
        else { return }
        dismiss()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Quick Open").font(.title2.weight(.semibold))
            TextField("Find a page, layer, or action", text: $query)
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .accessibilityIdentifier("quickOpen.search")
                .onSubmit(openFirst)
            Picker("Search Scope", selection: $scope) {
                ForEach(QuickOpenScope.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("quickOpen.scope")
            Text("\(results.pages.count) pages · \(results.layers.count) layers · \(results.assets.count) assets · \(results.components.count) components · \(results.actions.count + results.insertions.count + results.pageActions.count) actions")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("quickOpen.status")
            ScrollView {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    if scope.includesPages, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !state.recentQuickOpenPages.isEmpty {
                        Text("Recent Pages").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(state.recentQuickOpenPages) { page in
                            Button {
                                state.selectPage(page.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(page.name)
                                    Spacer()
                                    Text(page.route.rawValue).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("quickOpen.recentPage.\(page.id.description)")
                        }
                    }
                    if scope.includesLayers, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !state.recentQuickOpenLayers.isEmpty {
                        Text("Recent Current-Page Layers")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(state.recentQuickOpenLayers, id: \.id) { layer in
                            Button {
                                state.selectLayer(layer.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(layer.name)
                                    Spacer()
                                    Text(layer.kind.rawValue.capitalized).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("quickOpen.recentLayer.\(layer.id.description)")
                        }
                    }
                    if results.pages.isEmpty && results.layers.isEmpty && results.actions.isEmpty && results.insertions.isEmpty && results.pageActions.isEmpty && results.assets.isEmpty && results.components.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .accessibilityIdentifier("quickOpen.empty")
                    }
                    if !results.pages.isEmpty {
                        Text("Pages").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(results.pages) { page in
                            Button {
                                state.selectPage(page.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(page.name)
                                    Spacer()
                                    Text(page.route.rawValue).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("quickOpen.page.\(page.id.description)")
                        }
                    }
                    if !results.layers.isEmpty {
                        Text("Current Page Layers").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(results.layers, id: \.id) { layer in
                            Button {
                                state.selectLayer(layer.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(layer.name)
                                    Spacer()
                                    Text(layer.kind.rawValue.capitalized).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("quickOpen.layer.\(layer.id.description)")
                        }
                    }
                    if !results.assets.isEmpty {
                        Text("Image Assets").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(results.assets) { asset in
                            HStack {
                                Button {
                                    guard state.revealImageAsset(asset.id) else { return }
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(asset.displayName).lineLimit(1)
                                        Spacer()
                                        Text("Select in Assets").foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityIdentifier("quickOpen.asset.\(asset.id.description)")
                                Button("Insert Image") {
                                    guard state.insertImageAssetFromQuickOpen(asset.id) else { return }
                                    dismiss()
                                }
                                .disabled(!state.pageEditingIsAvailable)
                                .accessibilityIdentifier("quickOpen.asset.insert.\(asset.id.description)")
                                .accessibilityHint("Inserts this image into the current page using the existing Image command")
                            }
                        }
                    }
                    if !results.components.isEmpty {
                        Text("Component Definitions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(results.components) { definition in
                            HStack {
                                Button {
                                    guard state.revealComponentDefinition(definition.id) else { return }
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(definition.name).lineLimit(1)
                                        Spacer()
                                        Text("Reveal in Components").foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityIdentifier("quickOpen.component.\(definition.id.description)")
                                Button("Insert Instance") {
                                    guard state.insertComponentFromQuickOpen(definition.id) else { return }
                                    dismiss()
                                }
                                .disabled(!state.pageEditingIsAvailable)
                                .accessibilityIdentifier("quickOpen.component.insert.\(definition.id.description)")
                                .accessibilityHint("Inserts a linked instance through the existing component command")
                            }
                        }
                    }
                    if !results.pageActions.isEmpty {
                        Text("Page Actions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(results.pageActions) { action in
                            Button(action.title) { queueNewPageEditor() }
                                .disabled(!state.pageEditingIsAvailable)
                                .accessibilityIdentifier("quickOpen.pageAction.\(action.id)")
                        }
                    }
                    if !results.actions.isEmpty {
                        Text("View Actions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(results.actions) { action in
                            Button {
                                action.perform(on: state)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(action.title)
                                    Spacer()
                                    if action == .toggleGrid {
                                        Text(state.isWorldGridVisible ? "On" : "Off")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("quickOpen.action.\(action.id)")
                        }
                    }
                    if !results.insertions.isEmpty {
                        Text("Insert Actions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(results.insertions) { action in
                            Button {
                                guard action.perform(on: state) else { return }
                                dismiss()
                            } label: {
                                HStack {
                                    Text(action.title)
                                    Spacer()
                                    if !action.isAvailable(on: state) {
                                        Text("Unavailable").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(!action.isAvailable(on: state))
                            .accessibilityIdentifier("quickOpen.insert.\(action.id)")
                            .accessibilityHint("Uses the active page and current insertion destination")
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("quickOpen.cancel")
            }
        }
        .padding(SiteForgeVisualSystem.settingsFormPadding)
        .frame(minWidth: 440, minHeight: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickOpen.sheet")
    }
}

/// SF-0902/0905: drafts belong to the selected scene/revision, not the
/// definition or expanded renderer nodes. All actions use the component registry.
private struct ComponentFeedbackText: View {
    let announcement: String
    var body: some View {
        if !announcement.isEmpty, announcement != "Editing component definition; changes update linked instances" {
            Text(announcement)
        }
    }
}

private struct PageStructureInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    let node: DocumentNode
    @State private var height: String = ""
    @State private var padding: String = ""
    @State private var destination: PageID?
    @State private var identity: DesignInspectorOperationIdentity?
    @State private var convertConfirmation = false
    @State private var linksExpanded = false
    @State private var validation: String?
    private var role: PageFlowRole? { CanonicalPageFlow.role(node) }
    private var navigationRole: Bool { role == .header || role == .footer }
    private var computedHeight: Double? {
        if case .computed(let value, _) = state.geometryInspectorValue(for: .height) { return value }
        return nil
    }
    private var bodyPeers: [DocumentNode] {
        guard let page = state.pages.first(where: { $0.id == state.effectiveSelectedPageID }),
              case .node(let parentID) = node.parent, let parent = page.nodes.first(where: { $0.id == parentID }) else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        return parent.childIDs.compactMap { byID[$0] }.filter { CanonicalPageFlow.role($0) == .body }
    }
    var body: some View {
        GroupBox(role == .header ? "Header Settings" : role == .footer ? "Footer Settings" : "Connected Section") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                if navigationRole {
                    Button("Copy Header/Footer to Pages…") { state.presentPageChromeCopy(role: role) }
                        .disabled(!state.canCopyPageChrome)
                        .help("Add independent editable copies to other pages. Existing chrome is never replaced.")
                        .accessibilityIdentifier("page.chrome.copy.context")
                }
                if role == nil {
                    Text("Legacy free-positioned Section. Opening the project does not move it. Conversion derives X/Y/width from its containing area and places it in vertical flow; authored geometry remains available to exact Undo.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button("Convert to Connected Flow…") { convertConfirmation = true }
                        .accessibilityIdentifier("inspector.flow.convert")
                } else {
                    Text(role == .header ? "Top of page content · full available width" : role == .footer
                         ? "After page content · not fixed to the viewport" : "Connected vertical flow · full containing width")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.flow.provenance")
                    Text(state.resolvedSelectedGeometrySummary.map { "Resolved geometry: " + $0 }
                         ?? "No current resolved geometry is available.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .help("Exact size uses the base height. Fill available space and Fit content calculate height without changing that fallback.")
                        .accessibilityIdentifier("inspector.flow.resolved")
                    InspectorField("Height") {
                    TextField("Height", text: Binding(get: {
                        computedHeight.map { GeometryInspectorNumberParser.format($0) } ?? height
                    }, set: { height = $0 })).onSubmit { number(height, isPadding: false) }
                        .focusedValue(\.siteforgeNativeTextEditor, true)
                        .disabled(computedHeight != nil)
                        .accessibilityLabel("\(role?.rawValue.capitalized ?? "Section") height")
                        .accessibilityIdentifier("inspector.flow.height")
                    }
                    Text(computedHeight != nil ? "Height comes from layout. Use Geometry below to override this screen size, or choose Exact size at Desktop."
                         : state.geometryInspectorResponsiveSource(for: .height) ?? "Desktop · authored/defaulted height")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("inspector.flow.height.provenance")
                    InspectorField(AuthoringLanguage.innerSpacing) {
                    TextField(AuthoringLanguage.innerSpacing, text: $padding).onSubmit { number(padding, isPadding: true) }
                        .focusedValue(\.siteforgeNativeTextEditor, true)
                        .disabled(DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding != nil)
                        .accessibilityIdentifier("inspector.flow.padding")
                    }
                    if DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding != nil {
                        Text("Uses inner spacing from Design. Edit that value in Design; this Layout value is retained as its fallback.").font(.caption)
                    }
                    InspectorActionLayout {
                        Button("Apply Height") { number(height, isPadding: false) }
                            .disabled(computedHeight != nil).accessibilityIdentifier("inspector.flow.height.apply")
                        Button("Cancel", action: resetDrafts).accessibilityIdentifier("inspector.flow.cancel")
                    }
                    Button("Apply Inner Spacing") { number(padding, isPadding: true) }
                        .disabled(DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding != nil)
                        .accessibilityIdentifier("inspector.flow.padding.apply")
                    if role == .body {
                        HStack {
                            Button("Move Up") { reorder(-1) }.accessibilityIdentifier("inspector.flow.moveUp")
                                .disabled(bodyPeers.first?.id == node.id)
                            Button("Move Down") { reorder(1) }.accessibilityIdentifier("inspector.flow.moveDown")
                                .disabled(bodyPeers.last?.id == node.id)
                        }
                        Text("Drag the Section body to reorder. The insertion line indicates its new boundary; no X/Y value is written.").font(.caption)
                    }
                    if navigationRole {
                        PageChromeContentsControls(state: state, owner: node, commit: commit)
                        Toggle("Hamburger Menu on Mobile", isOn: Binding(get: {
                            node.insertionProperty(CanonicalPageFlow.hamburgerKey)?.value == .boolean(true)
                        }, set: { commit(.hamburger(node.id, $0)) }))
                            .accessibilityIdentifier("inspector.navigation.hamburger")
                        Text("Wider screens show page links. Narrow screens use Menu when enabled and at least one included page is available. Try it in Preview.")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                        if let navigation = state.pageStructureNavigation {
                            if !navigation.links.contains(where: \.isAvailable) {
                                Text("No included page is available. Open Edit individual links to repair missing pages, or include an existing page.")
                                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("inspector.navigation.destinations.status")
                            }
                        } else {
                            Text("No page links are shown at this screen size. Include a page or add a link to show navigation.")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("inspector.navigation.destinations.status")
                        }
                        InspectorField("Link alignment") {
                        Picker("Navigation Alignment", selection: Binding(get: {
                            state.pageStructureNavigation?.alignment
                                ?? CanonicalPageChrome.navigationAlignment(surface: node, settings: node)
                        }, set: { value in if let alignment = ContainerLayoutAlignment(rawValue: value) { commit(.alignment(node.id, alignment)) } })) {
                            ForEach(ContainerLayoutAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                        }.labelsHidden().accessibilityLabel("Navigation Alignment")
                            .accessibilityIdentifier("inspector.navigation.alignment")
                        }
                        let pages = state.pages.filter { $0.role != .notFound && $0.id != state.effectiveSelectedPageID }
                        InspectorField("Add page link") {
                        Picker("Add Page Link", selection: $destination) {
                            Text("Choose a project page").tag(Optional<PageID>.none)
                            ForEach(pages) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden().accessibilityLabel("Add Page Link")
                            .accessibilityIdentifier("inspector.navigation.add.page")
                        }
                        Button("Add Link") { if let destination { commit(.addLink(owner: node.id, pageID: destination)) } }
                            .disabled(destination == nil).accessibilityIdentifier("inspector.navigation.add")
                        if pages.isEmpty {
                            Text("Create another page in Pages before adding a navigation link.").font(.caption)
                            Button("New Page…") { state.presentPageEditor(.create) }.accessibilityIdentifier("inspector.navigation.newPage")
                        }
                        DisclosureGroup("Edit individual links", isExpanded: $linksExpanded) {
                            ForEach(state.pageStructureNavigation?.links ?? []) { link in
                                PageNavigationLinkFields(state: state, owner: node.id, link: link)
                            }
                        }.disclosureGroupStyle(SiteForgeInspectorDisclosureStyle(identifier: "inspector.navigation.links"))
                    }
                    Text("Background and border use the shared Design Inspector; accessibility remains in Accessibility.").font(.caption)
                }
                if let validation { Text(validation).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("inspector.flow.validation") }
                ComponentFeedbackText(announcement: state.componentAnnouncement).font(.caption).accessibilityValue(state.componentAnnouncement)
                    .accessibilityIdentifier("inspector.flow.status")
            }
        }.onAppear { identity = state.componentTextDraftIdentity; resetDrafts() }
            .onChange(of: state.componentTextInspectorKey) { _, _ in
                identity = state.componentTextDraftIdentity; resetDrafts()
            }
            .onExitCommand(perform: resetDrafts)
            .alert("Convert Section to connected flow?", isPresented: $convertConfirmation) {
                Button("Convert", role: .destructive) { commit(.convert(node.id, confirmed: true)) }
                    .accessibilityIdentifier("inspector.flow.convert.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The Section fills its containing width and moves into connected order. Header/Footer become page anchors. Child data and authored geometry are retained; Undo restores the exact old layout. No responsive constraints or fixed positioning are invented.")
            }
    }
    private func commit(_ edit: PageStructureEdit) { if let identity { _ = state.commitPageStructure(edit, identity: identity) } }
    private func number(_ draft: String, isPadding: Bool) {
        guard case .success(let value) = GeometryInspectorNumberParser.parse(draft) else {
            validation = "Enter a complete finite number; the last committed value is unchanged."; return
        }
        guard isPadding ? (0...10_000).contains(value) : (1...LayoutPolicy.maximumDimension).contains(value) else {
            validation = isPadding ? "Inner spacing must be 0–10,000 points. Nothing changed; enter a valid value or press Escape to cancel." : "Height must be at least 1 point and within the supported dimension limit. Nothing changed; enter a valid value or press Escape to cancel."
            return
        }
        validation = nil
        commit(isPadding ? .padding(node.id, value, state.viewportPreset.responsiveBreakpoint) : .height(node.id, value, state.viewportPreset.responsiveBreakpoint))
    }
    private func resetDrafts() {
        height = GeometryInspectorNumberParser.format(ResponsiveGeometryResolver.value(for: .height, node: node,
            breakpoint: state.viewportPreset.responsiveBreakpoint)?.0 ?? 320)
        padding = GeometryInspectorNumberParser.format(CanonicalPageFlow.padding(node, breakpoint: state.viewportPreset.responsiveBreakpoint,
            width: state.viewportState.contentBounds.size.width))
        validation = nil
    }
    private func reorder(_ direction: Double) {
        let peers = bodyPeers
        guard let index = peers.firstIndex(where: { $0.id == node.id }), peers.indices.contains(index + Int(direction)),
              let page = state.pages.first(where: { $0.id == state.effectiveSelectedPageID }),
              let frame = page.resolvedStructuralGeometry(breakpoint: state.viewportPreset.responsiveBreakpoint,
                viewportWidth: state.viewportState.contentBounds.size.width)[peers[index + Int(direction)].id]?.frame else { return }
        commit(.reorder(node.id, pointerY: frame.minY + frame.size.height / 2 + direction))
    }
}

private struct PageChromeContentsControls: View {
    @ObservedObject var state: WorkspaceShellState
    let owner: DocumentNode
    let commit: (PageStructureEdit) -> Void
    @State private var titleDraft = ""
    @State private var gapDraft = "24"
    @State private var navigationGapDraft = "16"
    @State private var navigationGapScope: ResponsiveBreakpoint = .desktop
    @State private var layoutValidation: String?
    @State private var customizationExpanded = false
    private var page: DocumentPage? { state.pages.first { $0.id == state.effectiveSelectedPageID } }
    private func referenced(_ key: String) -> DocumentNode? {
        guard let id = CanonicalPageChrome.reference(key, on: owner) else { return nil }
        return page?.nodes.first { $0.id == id }
    }
    private func contentImages(_ content: DocumentNode) -> [DocumentNode] {
        guard let page else { return [] }
        let children = Set(content.childIDs)
        let nodes = Dictionary(uniqueKeysWithValues: page.nodes.lazy.filter {
            $0.kind == .image && children.contains($0.id)
        }.map { ($0.id, $0) })
        return content.childIDs.compactMap { nodes[$0] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            if let title = referenced(CanonicalPageChrome.titleKey), let content = referenced(CanonicalPageChrome.contentKey) {
                Toggle("Show Site Title", isOn: Binding(get: { !title.selectionBooleanProperty("hidden") },
                    set: { commit(.showTitle(owner.id, $0)) }))
                    .accessibilityIdentifier("inspector.navigation.title.visible")
                InspectorField("Site title") {
                TextField("Site Title", text: $titleDraft).onSubmit { commit(.title(owner.id, text: titleDraft)) }
                    .focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityLabel("Site Title")
                    .accessibilityIdentifier("inspector.navigation.title")
                }
                InspectorActionLayout {
                    Button("Apply Title") { commit(.title(owner.id, text: titleDraft)) }
                        .accessibilityIdentifier("inspector.navigation.title.apply")
                    Button("Cancel") { titleDraft = CanonicalPageChrome.titleText(title, in: state.documentSession.document) }
                }
                Text(CanonicalPageChrome.resolvedTitle(title, in: state.documentSession.document).provenance)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.navigation.title.provenance")
                if let navigation = referenced(CanonicalPageChrome.navigationKey) {
                    Divider()
                    let breakpoint = state.viewportPreset.responsiveBreakpoint
                    let resolved = ResponsiveContainerLayoutResolver.value(for: .gap, node: navigation,
                        breakpoint: breakpoint, viewportWidth: state.viewportState.contentBounds.size.width)
                    let fluidBase = breakpoint == .desktop && resolved?.2 == .fluid
                    InspectorField("Space between links") {
                        TextField("Space between links", text: $navigationGapDraft)
                            .focusedValue(\.siteforgeNativeTextEditor, true)
                            .onSubmit { applyNavigationGap() }
                            .onExitCommand { resetNavigationGapDraft(); layoutValidation = nil }
                            .disabled(fluidBase)
                            .accessibilityLabel("Space between navigation links")
                            .accessibilityIdentifier("inspector.navigation.linkGap")
                    }
                    InspectorActionLayout {
                        Button("Apply Spacing", action: applyNavigationGap).disabled(fluidBase)
                            .accessibilityIdentifier("inspector.navigation.linkGap.apply")
                        Button("Cancel Spacing") { resetNavigationGapDraft(); layoutValidation = nil }
                            .accessibilityIdentifier("inspector.navigation.linkGap.cancel")
                    }
                    HStack {
                        Button(breakpoint == .desktop ? "Use default spacing" : "Use inherited spacing") {
                            commit(.navigationGap(owner.id, nil, navigationGapScope))
                        }.disabled(fluidBase)
                            .accessibilityIdentifier("inspector.navigation.linkGap.reset")
                    }
                    Text(breakpoint == .desktop && resolved?.2 == .baseDesktop
                         ? "Desktop · \(resolved.map { AuthoringLanguage.propertySource($0.1) } ?? "Default") · space between links"
                         : resolved?.2.label ?? "Default space between links: 16 points")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("inspector.navigation.linkGap.provenance")
                    if fluidBase {
                        Text("Smooth scaling is managed in Layout. Screen-size overrides are retained.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Inline links share this gap, bounded to the available width. The native mobile menu keeps its standard spacing.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                let images = contentImages(content)
                if !images.isEmpty {
                    Divider()
                    Text("Images / Logos").font(.headline)
                    ForEach(images) { image in
                        Toggle("Show \(image.name)", isOn: Binding(get: { !image.selectionBooleanProperty("hidden") },
                            set: { commit(.showContentImage(owner.id, image.id, $0)) }))
                            .fixedSize(horizontal: false, vertical: true).help(image.name)
                            .disabled(image.selectionBooleanProperty("locked"))
                            .accessibilityHint("Base visibility for this actual Contents image. Breakpoint visibility overrides are preserved.")
                            .accessibilityIdentifier("inspector.navigation.image.visible." + image.id.description)
                    }
                    Text("Base image visibility; device overrides remain unchanged. Assets and alt text use the existing Image Inspector.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("To add a logo, select Contents and insert an Image using the existing Image tools.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let page, let plan = state.canvasRenderPlan,
                   plan.identity.documentID == state.documentSession.document.id,
                   plan.identity.sceneID == state.viewportState.sceneID,
                   plan.identity.revision == state.documentSession.document.revision,
                   plan.identity.viewportGeneration == state.viewportState.generation,
                   let navigationID = CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner),
                   let bounds = plan.authoredObjects.first(where: { $0.id == navigationID })?.frame,
                   let guidance = CanonicalPageChrome.narrowMenuGuidance(owner: owner, page: page,
                    document: state.documentSession.document, width: state.viewportLayoutWidth, navigationBounds: bounds) {
                    Text(guidance).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.navigation.narrow.guidance")
                }
                Button("Select Contents") { state.selectLayer(content.id) }
                    .accessibilityIdentifier("inspector.navigation.selectContents")
                DisclosureGroup("Customize Contents", isExpanded: $customizationExpanded) {
                    InspectorField("Direction") {
                    Picker("Direction", selection: Binding(get: { content.insertionStringProperty("layout.axis") ?? "horizontal" },
                        set: { value in if let axis = ContainerLayoutAxis(rawValue: value) { layout(content, axis: axis) } })) {
                        Text("Horizontal").tag("horizontal"); Text("Vertical").tag("vertical")
                    }.labelsHidden().accessibilityLabel("Direction")
                        .accessibilityIdentifier("inspector.navigation.content.direction")
                    }
                    InspectorField("Alignment") {
                    Picker("Alignment", selection: Binding(get: { content.insertionStringProperty("layout.align") ?? "center" },
                        set: { value in if let alignment = ContainerLayoutAlignment(rawValue: value) { layout(content, alignment: alignment) } })) {
                        ForEach(ContainerLayoutAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                    }.labelsHidden().accessibilityLabel("Alignment")
                        .accessibilityIdentifier("inspector.navigation.content.alignment")
                    }
                    InspectorField(AuthoringLanguage.itemSpacing) {
                        TextField(AuthoringLanguage.itemSpacing, text: $gapDraft).onSubmit { layout(content) }
                            .focusedValue(\.siteforgeNativeTextEditor, true)
                            .accessibilityIdentifier("inspector.navigation.content.gap")
                    }
                    Button("Restore Automatic Layout") { commit(.automaticLayout(owner.id)) }
                        .disabled(!CanonicalPageChrome.isCustom(owner))
                        .accessibilityIdentifier("inspector.navigation.content.reset")
                    Text(CanonicalPageChrome.isCustom(owner) ? "Custom layout · your sizes and spacing" : "Automatic layout · keeps room for Menu on narrow screens")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .help("Automatic layout can reduce default title space without changing saved sizes. Your custom sizes, fonts and spacing stay unchanged.")
                        .accessibilityIdentifier("inspector.navigation.content.provenance")
                }.disclosureGroupStyle(SiteForgeInspectorDisclosureStyle(identifier: "inspector.navigation.customize"))
                if let layoutValidation {
                    Text(layoutValidation).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.navigation.content.validation")
                }
                if let page {
                    Text("Included Pages").font(.headline)
                    Button("Include All Pages") { commit(.includeAllPages(owner.id)) }
                        .help("Includes normal pages in this Header or Footer only. Existing labels and order are preserved. Undo reverses the whole change.")
                        .accessibilityIdentifier("inspector.navigation.includeAll")
                    ForEach(state.pages.filter { $0.role != .notFound && $0.role != .componentDefinition }) { destination in
                        Toggle(destination.name, isOn: Binding(get: {
                            CanonicalPageChrome.links(owner: owner, page: page).contains {
                                $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == destination.id.description && !$0.selectionBooleanProperty("hidden")
                            }
                        }, set: { commit(.includePage(owner.id, destination.id, $0)) }))
                        .accessibilityIdentifier("inspector.navigation.include." + destination.id.description)
                    }
                    Text("Excluding a page hides its navigation link, not the page. Its label and identity are retained.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else if CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner) != nil {
                Text("Original title or navigation content is missing. Its identity is retained; restore it with Undo or the original saved project.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Undo Last Edit", action: state.undo).disabled(!state.canUndo)
            } else {
                Button("Add Editable Title and Navigation") { commit(.editableContents(owner.id)) }
                    .accessibilityIdentifier("inspector.navigation.editableContents")
                Text("Existing content and page links are preserved. Undo restores the original structure.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }.onAppear(perform: resetDrafts)
            .onChange(of: owner) { _, _ in resetDrafts() }
            .onChange(of: state.componentTextInspectorKey) { _, _ in resetDrafts() }
            .onChange(of: state.viewportPreset) { _, _ in resetDrafts() }
            .onExitCommand(perform: resetDrafts)
    }
    private func resetDrafts() {
        titleDraft = referenced(CanonicalPageChrome.titleKey).map { CanonicalPageChrome.titleText($0, in: state.documentSession.document) } ?? ""
        gapDraft = GeometryInspectorNumberParser.format(referenced(CanonicalPageChrome.contentKey)?.insertionNumberProperty("layout.gap") ?? 24)
        resetNavigationGapDraft()
        layoutValidation = nil
    }
    private func resetNavigationGapDraft() {
        navigationGapScope = state.viewportPreset.responsiveBreakpoint
        if let navigation = referenced(CanonicalPageChrome.navigationKey) {
            navigationGapDraft = GeometryInspectorNumberParser.format(CanonicalPageChrome.navigationGap(
                surface: navigation, settings: owner, breakpoint: navigationGapScope,
                width: state.viewportState.contentBounds.size.width))
        }
    }
    private func applyNavigationGap() {
        guard case .success(let value) = GeometryInspectorNumberParser.parse(navigationGapDraft),
              (0...10_000).contains(value) else {
            layoutValidation = "Enter a complete inline gap from 0 to 10,000 points. Committed navigation is unchanged."
            return
        }
        layoutValidation = nil
        commit(.navigationGap(owner.id, value, navigationGapScope))
    }
    private func layout(_ content: DocumentNode, axis: ContainerLayoutAxis? = nil, alignment: ContainerLayoutAlignment? = nil) {
        guard case .success(let gap) = GeometryInspectorNumberParser.parse(gapDraft), (0...10_000).contains(gap) else {
            layoutValidation = "Enter a complete gap from 0 to 10,000 points. Committed layout is unchanged."; return
        }
        layoutValidation = nil
        commit(.contentLayout(owner.id, axis: axis ?? ContainerLayoutAxis(rawValue: content.insertionStringProperty("layout.axis") ?? "horizontal") ?? .horizontal,
            gap: gap, alignment: alignment ?? ContainerLayoutAlignment(rawValue: content.insertionStringProperty("layout.align") ?? "center") ?? .center))
    }
}

private struct PageNavigationLinkFields: View {
    @ObservedObject var state: WorkspaceShellState
    let owner: NodeID
    let link: PageNavigationLink
    @State private var label: String
    @State private var pageID: PageID
    @State private var identity: DesignInspectorOperationIdentity?
    init(state: WorkspaceShellState, owner: NodeID, link: PageNavigationLink) {
        self.state = state; self.owner = owner; self.link = link
        _label = State(initialValue: link.label); _pageID = State(initialValue: link.pageID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            if !link.isAvailable { Label("Missing page · destination retained", systemImage: "exclamationmark.triangle").font(.caption) }
            TextField("Link Label", text: $label).onSubmit(apply).accessibilityIdentifier("inspector.navigation.label.\(link.id)")
            Picker("Destination", selection: $pageID) {
                if !link.isAvailable { Text("Missing original page").tag(link.pageID) }
                ForEach(state.pages.filter { $0.role != .notFound }) { Text($0.name).tag($0.id) }
            }.accessibilityIdentifier("inspector.navigation.destination.\(link.id)")
            HStack {
                Button("Apply", action: apply).accessibilityIdentifier("inspector.navigation.apply.\(link.id)")
                Button("Cancel") { label = link.label; pageID = link.pageID }
                Button("Remove", role: .destructive) { commit(.removeLink(owner: owner, link: link.id)) }
            }
            HStack {
                Button("Up") { commit(.reorderLink(owner: owner, link: link.id, offset: -1)) }
                    .disabled(state.pageStructureNavigation?.links.first?.id == link.id)
                Button("Down") { commit(.reorderLink(owner: owner, link: link.id, offset: 1)) }
                    .disabled(state.pageStructureNavigation?.links.last?.id == link.id)
            }
        }.onAppear { identity = state.componentTextDraftIdentity }
            .onChange(of: state.componentTextInspectorKey) { _, _ in
                identity = state.componentTextDraftIdentity; label = link.label; pageID = link.pageID
            }
            .onExitCommand { label = link.label; pageID = link.pageID }
    }
    private func apply() { commit(.editLink(owner: owner, link: link.id, pageID: pageID, label: label)) }
    private func commit(_ edit: PageStructureEdit) { if let identity { _ = state.commitPageStructure(edit, identity: identity) } }
}

private struct ComponentOrganizationInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    var body: some View {
        GroupBox("Property Organization") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                if state.editingComponentID != nil, let node = state.selectedCanonicalNodes.first,
                   state.selectedCanonicalNodes.count == 1 {
                    let entries = state.componentOrganizationEntries
                    ForEach(entries.filter { $0.sourceNodeID == node.id }) { entry in
                        ComponentOrganizationFields(state: state, entry: entry, entries: entries)
                            .disabled(!state.componentTextEditingAvailable)
                    }
                    if !entries.contains(where: { $0.sourceNodeID == node.id }) {
                        Text("Expose a property on this layer before organizing it.").font(.caption)
                    }
                } else {
                    Text("Select one definition layer to edit its property group and position. Instance values and child layout are unchanged.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                ComponentFeedbackText(announcement: state.componentAnnouncement).font(.caption)
                    .accessibilityLabel("Property organization status").accessibilityValue(state.componentAnnouncement)
                    .accessibilityIdentifier("component.organization.status")
            }
        }
    }
}

private struct ComponentOrganizationFields: View {
    @ObservedObject var state: WorkspaceShellState
    let entry: CanonicalComponentOrganization.Entry
    let entries: [CanonicalComponentOrganization.Entry]
    @State private var group: String
    @State private var position: Int
    @State private var identity: DesignInspectorOperationIdentity?
    init(state: WorkspaceShellState, entry: CanonicalComponentOrganization.Entry,
         entries: [CanonicalComponentOrganization.Entry]) {
        self.state = state; self.entry = entry; self.entries = entries
        _group = State(initialValue: entry.group ?? "")
        _position = State(initialValue: entries.firstIndex { $0.id == entry.id } ?? 0)
    }
    private var suffix: String { entry.id.stableDescription }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Text(entry.label).font(.headline).lineLimit(1).help(entry.label)
            Text(entry.rank == nil && entry.group == nil ? "Default · stable binding order" : "Set here · component presentation")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Group (empty = ungrouped)", text: $group).onSubmit(apply)
                .accessibilityLabel("Property group for " + entry.label)
                .accessibilityIdentifier("component.organization.group." + suffix)
            Picker("Position", selection: $position) {
                ForEach(entries.indices, id: \.self) { Text(String($0 + 1)).tag($0) }
            }.accessibilityIdentifier("component.organization.position." + suffix)
            HStack {
                Button("Apply", action: apply).accessibilityIdentifier("component.organization.apply." + suffix)
                Button("Cancel", action: cancel).accessibilityIdentifier("component.organization.cancel." + suffix)
            }
            Button("Reset Organization") {
                if let identity {
                    state.commitComponentOrganization(.resetPropertyOrganization(nodeID: entry.sourceNodeID,
                        property: entry.id), identity: identity)
                }
            }.disabled(entry.rank == nil && entry.group == nil)
                .accessibilityIdentifier("component.organization.reset." + suffix)
        }.onAppear { identity = state.componentTextDraftIdentity }
            .onExitCommand(perform: cancel)
    }
    private func apply() {
        if let identity {
            state.commitComponentOrganization(.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id,
                group: group.isEmpty ? nil : group, position: position), identity: identity)
        }
    }
    private func cancel() {
        group = entry.group ?? ""; position = entries.firstIndex { $0.id == entry.id } ?? 0
    }
}

private struct OrganizedComponentInstanceInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    let instance: DocumentNode
    let reader: ScrollViewProxy
    @State private var query = ""
    @State private var conflictsOnly = false
    @State private var navigationProperty: ComponentOverridePropertyIdentity?
    @State private var resetAllIdentity: DesignInspectorOperationIdentity?
    @FocusState private var focusedProperty: ComponentOverridePropertyIdentity?
    private var discovery: ComponentPropertyDiscovery.Result {
        ComponentPropertyDiscovery.project(state.componentOrganizationEntries, query: query,
            authored: state.componentAuthoredPropertyIdentities,
            conflicts: Set(state.componentOverrideConflicts.map(\.property)), conflictsOnly: conflictsOnly)
    }
    private var groups: [String?] {
        var result: [String?] = []
        for entry in discovery.entries where !result.contains(entry.group) { result.append(entry.group) }
        return result
    }
    var body: some View {
        let sourceContext = state.responsiveInspectorEditContext
        return VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Change this copy").font(.headline)
            Divider().accessibilityHidden(true)
            Text(AuthoringLanguage.componentRelationshipHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inspector.component.provenance")
            if let definition = state.componentOrganizationDefinition {
                InspectorActionLayout {
                Button { state.editComponentDefinition(definition.id) } label: {
                    InspectorActionLabel(title: AuthoringLanguage.editOriginalComponent)
                }
                    .accessibilityIdentifier("inspector.component.edit")
                    .help("Open the original without changing this copy. Back to this copy restores this exact selection.")
                Button(action: state.detachComponent) { InspectorActionLabel(title: "Make independent") }
                    .disabled(!state.pageEditingIsAvailable)
                    .help("Remove this copy's component link using the existing detach command. Later original edits no longer update it; Undo restores the link.")
                    .accessibilityIdentifier("inspector.component.detach")
                }
            }
            }.modifier(SiteForgeInspectorSectionSurface())
            if !state.componentOrganizationEntries.isEmpty {
            // Native text-field bezels extend beyond their layout rect. Keep
            // discovery controls in the same inset section as other Inspector
            // controls, rather than placing a bezel against the scroll clip.
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            TextField("Search component properties", text: Binding(get: { query }, set: { query = String($0.prefix(256)) }))
                .accessibilityLabel("Search component properties by name, type, group or value source")
                .accessibilityIdentifier("component.discovery.search")
                .onSubmit { reveal(discovery.neighbor(of: nil, offset: 1), reader: reader) }
                .onExitCommand { query = ""; conflictsOnly = false }
            Text("\(discovery.entries.count) of \(discovery.total) properties")
                .font(.caption).accessibilityIdentifier("component.discovery.count")
                .accessibilityValue("\(discovery.entries.count) matching of \(discovery.total) exposed properties")
            Toggle("Values needing attention only", isOn: $conflictsOnly)
                .accessibilityIdentifier("component.discovery.conflicts")
            InspectorActionLayout {
                Button("Previous") { reveal(discovery.neighbor(of: navigationProperty, offset: -1), reader: reader) }
                    .accessibilityLabel("Reveal previous matching component property")
                    .accessibilityIdentifier("component.discovery.previous")
                    .disabled(discovery.entries.isEmpty)
                Button("Next") { reveal(discovery.neighbor(of: navigationProperty, offset: 1), reader: reader) }
                    .accessibilityLabel("Reveal next matching component property")
                    .accessibilityIdentifier("component.discovery.next")
                    .disabled(discovery.entries.isEmpty)
                Button("Clear") { query = ""; conflictsOnly = false }
                    .accessibilityIdentifier("component.discovery.clear")
            }.disabled(discovery.entries.isEmpty && query.isEmpty && !conflictsOnly)
            }
            .modifier(SiteForgeInspectorSectionSurface())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Find component properties")
            if discovery.entries.isEmpty {
                Text("No matching properties. Clear search to show the original order. Values needing attention remain available below.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.discovery.empty")
            }
            if discovery.hiddenConflictCount > 0 {
                Text("\(discovery.hiddenConflictCount) custom value(s) needing attention are outside these results. Recovery below is not filtered.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.discovery.hiddenConflicts")
            }
            ForEach(groups, id: \.self) { group in
                GroupBox {
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                        ForEach(discovery.entries.filter { $0.group == group }) { entry in
                            propertyRow(entry, sourceContext: sourceContext)
                        }
                    }
                } label: {
                    Text(group ?? "Ungrouped Properties").fixedSize(horizontal: false, vertical: true).help(group ?? "Ungrouped Properties")
                }.accessibilityElement(children: .contain)
                    .accessibilityLabel(group ?? "Ungrouped Properties")
                    .accessibilityIdentifier("component.organization.instance.group." + (group.map { "named." + $0 } ?? "default"))
            }
            }
            ComponentOverrideRecoveryView(state: state, instance: instance)
                .id(state.componentTextInspectorKey)
                .disabled(!state.componentTextEditingAvailable)
            if state.componentOrganizationEntries.isEmpty {
                Text("No shared properties yet. Edit the original component to make text, visibility, Image Fit, image or link controls available to its copies.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.properties.empty")
                if let id = CanonicalComponentReference.definitionID(for: instance),
                   state.componentDefinitions.contains(where: { $0.id == id }) {
                    Button("Choose properties on original") { state.editComponentDefinition(id) }
                        .accessibilityIdentifier("component.properties.expose")
                }
            }
            Text("Reset copy changes removes custom values, including filtered-out ones. Available original values are used; missing originals stay missing. Undo restores exact values.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Button {
                if let identity = state.componentTextDraftIdentity {
                    if state.componentOverrideConflicts.isEmpty {
                        state.commitComponentText(.resetAllOverrides(instance.id), identity: identity)
                    } else { resetAllIdentity = identity }
                }
            } label: { InspectorActionLabel(title: AuthoringLanguage.componentResetTitle(count: state.componentAuthoredPropertyIdentities.count)) }
            .disabled(!state.componentTextEditingAvailable || !instance.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentReference.namespace) && $0.key.rawValue != CanonicalComponentReference.key })
                .accessibilityIdentifier("component.text.resetAll").help("Removes this copy’s custom values in the named scope, including values outside search results. Missing originals stay missing. Undo restores exact values.")
            Button {
                if let identity = state.componentTextDraftIdentity { state.commitComponentVisibility(.resetAllVisibilityOverrides(instance.id), identity: identity) }
            } label: { InspectorActionLabel(title: AuthoringLanguage.componentResetTitle(count: CanonicalComponentVisibility.overrides(on: instance).count, visibilityOnly: true)) }
            .disabled(!state.componentTextEditingAvailable || CanonicalComponentVisibility.overrides(on: instance).isEmpty)
                .accessibilityIdentifier("component.visibility.resetAll").help("Removes this copy’s custom values in the named scope, including values outside search results. Missing originals stay missing. Undo restores exact values.")
            if !state.componentSlotProperties.isEmpty {
            Text("Default contents come from the original component. Custom contents for one copy are not available.").font(.caption)
                .accessibilityIdentifier("component.slot.supply.unavailable")
            }
            ComponentFeedbackText(announcement: state.componentAnnouncement).font(.caption)
                .accessibilityLabel("Component property status").accessibilityValue(state.componentAnnouncement)
                .accessibilityIdentifier("component.organization.status")
        }.confirmationDialog("Reset all changes on this copy?",
            isPresented: Binding(get: { resetAllIdentity != nil }, set: { if !$0 { resetAllIdentity = nil } })) {
                Button(AuthoringLanguage.componentResetTitle(count: state.componentAuthoredPropertyIdentities.count), role: .destructive) {
                    if let identity = resetAllIdentity {
                        state.commitComponentText(.resetAllOverrides(instance.id), identity: identity)
                    }
                    resetAllIdentity = nil
                }.accessibilityIdentifier("component.properties.resetAll.confirm")
                Button("Cancel", role: .cancel) { resetAllIdentity = nil }
                    .accessibilityIdentifier("component.properties.resetAll.cancel")
            } message: {
                Text("This removes all custom values on this copy, including values needing attention. Available original values are used; missing data is not restored. Undo restores exact values and identities.")
            }
        .onChange(of: discovery.entries.map(\.id)) { _, ids in
            if let focusedProperty, !ids.contains(focusedProperty) { self.focusedProperty = nil }
            if let navigationProperty, !ids.contains(navigationProperty) { self.navigationProperty = nil }
        }.onChange(of: focusedProperty) { _, value in
            if let value { navigationProperty = value }
        }
    }
    @ViewBuilder private func propertyRow(
        _ entry: CanonicalComponentOrganization.Entry,
        sourceContext: ResponsiveInspectorEditContext
    ) -> some View {
        field(entry)
            .id(fieldIdentity(entry))
            .disabled(!state.componentTextEditingAvailable)
            .id(entry.id).focusable().focused($focusedProperty, equals: entry.id)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(entry.label + ", " + entry.id.organizationKind + ", " + (entry.group ?? "ungrouped"))
            .onMoveCommand { direction in movePropertyFocus(direction, from: entry.id) }
        Button("Edit Property Source…") {
            _ = state.revealComponentPropertySource(instanceID: instance.id, property: entry.id,
                expectedContext: sourceContext)
        }
        .controlSize(.small)
        .accessibilityLabel("Edit shared definition source for " + entry.label)
        .accessibilityHint("Selects the property on the original component. Linked copies use its default unless changed separately. Back to this copy restores this selection.")
        .accessibilityIdentifier("component.property.source." + entry.id.stableDescription)
        .disabled(state.componentTextDraftIdentity == nil)
    }

    private func movePropertyFocus(_ direction: MoveCommandDirection, from id: ComponentOverridePropertyIdentity) {
        guard focusedProperty == id else { return }
        let offset: Int
        switch direction {
        case .up: offset = -1
        case .down: offset = 1
        default: return
        }
        reveal(discovery.neighbor(of: id, offset: offset), reader: reader)
    }

    private func reveal(_ id: ComponentOverridePropertyIdentity?, reader: ScrollViewProxy) {
        guard let id else { return }
        reader.scrollTo(id, anchor: .center)
        navigationProperty = id
        focusedProperty = id
    }
    private func fieldIdentity(_ entry: CanonicalComponentOrganization.Entry) -> String {
        // Text commits refresh their adopted command identity in place. Other
        // existing draft editors keep their established revision reset policy.
        if case .text = entry.id { return instance.id.description + ":" + entry.id.stableDescription }
        return state.componentTextInspectorKey + ":" + entry.id.stableDescription
    }
    @ViewBuilder private func field(_ entry: CanonicalComponentOrganization.Entry) -> some View {
        switch entry.id {
        case .text(let id):
            if let p = state.componentTextProperties.first(where: { $0.id == id }) {
                ComponentTextInstanceFields(state: state, instanceID: instance.id, property: p,
                    authored: CanonicalComponentText.overrides(on: instance)[id])
            }
        case .visibility(let id):
            if let p = state.componentVisibilityProperties.first(where: { $0.id == id }) {
                ComponentVisibilityInstanceFields(state: state, instanceID: instance.id, property: p,
                    authored: CanonicalComponentVisibility.overrides(on: instance)[id])
            }
        case .action(let id):
            if let p = state.componentActionProperties.first(where: { $0.id == id }) {
                let value = CanonicalComponentAction.overrides(on: instance)[id]
                ComponentActionDestinationFields(state: state, instance: instance, property: p,
                    committed: value ?? p.defaultValue, isAuthored: value != nil)
            }
        case .slot(let id):
            if let p = state.componentSlotProperties.first(where: { $0.id == id }) {
                ComponentSlotFallbackFields(state: state, instance: instance, property: p)
            }
        case .choice, .media:
            ComponentOrganizedChoiceMediaFields(state: state, instance: instance, entry: entry)
        }
    }
}

private struct ComponentRetainedOverrideValueView: View {
    @ObservedObject var state: WorkspaceShellState
    let value: ComponentOverrideValue
    let identifier: String
    var body: some View {
        // Native selectable text's generic container does not expose AXValue.
        // Preserve pointer text selection while representing the same displayed
        // value as static text for VoiceOver, on one stable semantic element.
        content.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityRepresentation {
            Text(accessibleValue)
                .accessibilityLabel("Custom value kept on this copy")
                .accessibilityValue(accessibleValue)
                .accessibilityIdentifier(identifier)
        }
    }

    private var accessibleValue: String {
        switch value {
        case .text(let text): text
        case .visibility(let visible): visible ? "Visible" : "Hidden"
        case .choice(let mode): mode.rawValue.capitalized
        case .media(let id): state.documentSession.document.imageAssets.first { $0.id == id }?.displayName ?? "Image unavailable · custom reference kept"
        case .action(let target):
            switch target {
            case .none: "None"
            case .external(let url): url
            case .page: "Custom page destination kept"
            case .section: "Custom section destination kept"
            }
        case .slotFallback(let ids): "Default contents: \(ids.count) top-level items"
        }
    }

    @ViewBuilder private var content: some View {
        switch value {
        case .text(let text):
            Text(text).textSelection(.enabled)
        case .visibility(let visible): Text(visible ? "Custom value: Visible" : "Custom value: Hidden")
        case .choice(let mode): Text("Custom image fit: " + mode.rawValue.capitalized)
        case .media(let id): Text(state.documentSession.document.imageAssets.first { $0.id == id }?.displayName ?? "Image unavailable · custom reference kept")
        case .action(let target):
            switch target {
            case .none: Text("Custom destination: None")
            case .external(let url): Text(url).textSelection(.enabled)
            case .page: Text("Custom page destination kept")
            case .section: Text("Custom section destination kept")
            }
        case .slotFallback(let ids): Text("Default contents: \(ids.count) top-level items")
        }
    }
}

private struct ComponentOverrideRecoveryView: View {
    @ObservedObject var state: WorkspaceShellState
    let instance: DocumentNode
    private struct ResetRequest: Identifiable {
        let id = UUID()
        let identity: DesignInspectorOperationIdentity
        let propertyIDs: [PropertyID]
    }
    @State private var request: ResetRequest?
    @State private var operationIdentity: DesignInspectorOperationIdentity?
    private var conflicts: [ComponentOverrideConflictFinding] { state.componentOverrideConflicts }
    private var definitionAvailable: Bool { state.componentOrganizationDefinition != nil }
    var body: some View {
        if !conflicts.isEmpty || !definitionAvailable {
            GroupBox("Custom values needing attention") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    Label(AuthoringLanguage.componentRecoverySummary(count: conflicts.count, originalAvailable: definitionAvailable), systemImage: "exclamationmark.triangle")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityValue(AuthoringLanguage.componentRecoverySummary(count: conflicts.count, originalAvailable: definitionAvailable))
                        .accessibilityIdentifier("component.recovery.summary")
                    if !definitionAvailable {
                        Text("The original component is unavailable. Its reference and your custom values are kept. Removing custom values cannot restore the original.")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("component.recovery.definition.unavailable")
                    }
                    Text("Use Undo or reopen the original saved project to recover missing component data. No replacement is guessed.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button("Inspect original properties") {
                        if let identity = operationIdentity {
                            state.revealComponentRecoverySource(instanceID: instance.id, property: nil, identity: identity)
                        }
                    }.disabled(!definitionAvailable).accessibilityIdentifier("component.recovery.definition.reveal")
                        .help("Open the original's Content Inspector to inspect available properties. This does not restore missing data or choose replacements.")
                    ForEach(conflicts) { conflict in
                        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                            Text(conflict.label ?? AuthoringLanguage.componentValueName(kind: conflict.property.organizationKind))
                                .font(.headline).fixedSize(horizontal: false, vertical: true).help(conflict.property.stableDescription)
                            Text(conflict.reason.explanation).font(.caption).fixedSize(horizontal: false, vertical: true)
                                .accessibilityValue(conflict.reason.explanation)
                                .accessibilityIdentifier("component.recovery.reason." + conflict.property.stableDescription)
                            ComponentRetainedOverrideValueView(state: state, value: conflict.retainedValue,
                                identifier: "component.recovery.value." + conflict.property.stableDescription)
                            if conflict.path != nil {
                                Button("Show property on original") {
                                    if let identity = operationIdentity {
                                        state.revealComponentRecoverySource(instanceID: instance.id, property: conflict.property, identity: identity)
                                    }
                                }.accessibilityIdentifier("component.recovery.source.reveal." + conflict.property.stableDescription)
                            } else {
                                Text("The original property is unavailable. Recover it with Undo or the original saved project before opening it.").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Removes only this custom value; Undo restores it.")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                                .help(AuthoringLanguage.removeCustomValueHelp)
                            Button("Remove custom value…") { prepare([conflict.authoredPropertyID]) }
                                .accessibilityIdentifier("component.recovery.reset." + conflict.property.stableDescription)
                        }
                    }
                    Button("Remove affected values (\(conflicts.count))…") { prepare(conflicts.map(\.authoredPropertyID)) }
                        .disabled(conflicts.isEmpty).accessibilityIdentifier("component.recovery.resetAll")
                    Text("Remove affected values leaves other custom values and the original component unchanged.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            .alert("Remove affected custom values?", isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }), presenting: request) { request in
                Button(AuthoringLanguage.removeCustomValuesTitle(count: request.propertyIDs.count), role: .destructive) {
                    state.resetComponentOverrideConflicts(instanceID: instance.id, expectedPropertyIDs: request.propertyIDs,
                        identity: request.identity)
                    self.request = nil
                }.accessibilityIdentifier("component.recovery.confirm")
                Button("Cancel", role: .cancel) { self.request = nil }.accessibilityIdentifier("component.recovery.cancel")
            } message: { request in
                Text("Remove \(request.propertyIDs.count) affected custom value(s) from this copy? Available original values will be used, so appearance may change. Missing data is not restored. Other custom values, links and geometry stay intact. Undo restores the exact removed values.")
            }
            .onAppear { operationIdentity = state.componentTextDraftIdentity }
        }
    }
    private func prepare(_ propertyIDs: [PropertyID]) {
        guard !propertyIDs.isEmpty, let identity = operationIdentity else { return }
        request = .init(identity: identity, propertyIDs: propertyIDs)
    }
}

private struct ComponentOrganizedChoiceMediaFields: View {
    @ObservedObject var state: WorkspaceShellState
    let instance: DocumentNode
    let entry: CanonicalComponentOrganization.Entry
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            if case .choice(let id) = entry.id, let p = state.componentChoiceProperties.first(where: { $0.id == id }) {
                let authored = CanonicalComponentChoice.overrides(on: instance)[id]
                Picker(p.label, selection: Binding(get: { authored ?? p.defaultValue }, set: { value in
                    if let identity = state.componentTextDraftIdentity {
                        state.commitComponentChoice(.setChoiceOverride(instanceID: instance.id, propertyID: id, value: value), identity: identity)
                    }
                })) { ForEach(ImageFitMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    .accessibilityLabel(p.label + " component choice")
                    .accessibilityValue((authored ?? p.defaultValue).rawValue.capitalized)
                    .accessibilityIdentifier("component.choice.value.\(id)")
                Text(AuthoringLanguage.componentSource(isOverride: authored != nil)).font(.caption)
                Button(AuthoringLanguage.useOriginalValue) {
                    if let identity = state.componentTextDraftIdentity { state.commitComponentChoice(.resetChoiceOverride(instanceID: instance.id, propertyID: id), identity: identity) }
                }.disabled(authored == nil).accessibilityIdentifier("component.choice.reset.\(id)").help(AuthoringLanguage.removeCustomValueHelp)
            } else if case .media(let id) = entry.id, let p = state.componentMediaProperties.first(where: { $0.id == id }) {
                let authored = CanonicalComponentMedia.overrides(on: instance)[id]
                Picker(p.label, selection: Binding(get: { authored ?? p.defaultValue }, set: { value in
                    if let identity = state.componentTextDraftIdentity { state.commitComponentMedia(.setMediaOverride(instanceID: instance.id, propertyID: id, assetID: value), identity: identity) }
                })) { ForEach(state.imageAssetsForReuse(search: "")) { Text($0.displayName).tag($0.id) } }
                    .disabled(state.documentSession.document.imageAssets.isEmpty)
                    .accessibilityLabel(p.label + " component image")
                    .accessibilityValue(state.documentSession.document.imageAssets.first { $0.id == (authored ?? p.defaultValue) }?.displayName ?? "Missing image asset")
                    .accessibilityIdentifier("component.media.value.\(id)")
                Text(AuthoringLanguage.componentSource(isOverride: authored != nil)).font(.caption)
                ImageUseActionsView(state: state, target: .componentMedia(instanceID: instance.id, propertyID: id),
                    currentAssetID: authored ?? p.defaultValue, identifier: "component.media.\(id)")
                Button(AuthoringLanguage.useOriginalValue) {
                    if let identity = state.componentTextDraftIdentity { state.commitComponentMedia(.resetMediaOverride(instanceID: instance.id, propertyID: id), identity: identity) }
                }.disabled(authored == nil).accessibilityIdentifier("component.media.reset.\(id)").help(AuthoringLanguage.removeCustomValueHelp)
            }
        }
    }
}

private struct ComponentTextInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Component Text").font(.headline)
            if let node = state.selectedDefinitionText {
                ComponentTextDefinitionFields(state: state, node: node)
                    .disabled(!state.componentDefinitionTextDraftingAvailable)
            } else if let instance = state.selectedComponent {
                let properties = state.componentTextProperties
                let overrides = CanonicalComponentText.overrides(on: instance)
                if properties.isEmpty {
                    Text("No exposed text properties. Edit the definition, select a Text layer, then expose its content here.")
                        .font(.caption)
                }
                ForEach(properties) { property in
                    ComponentTextInstanceFields(state: state, instanceID: instance.id, property: property,
                        authored: overrides[property.id])
                        .disabled(!state.componentTextEditingAvailable)
                }
                ForEach(overrides.keys.filter { id in !properties.contains { $0.id == id } }.sorted { $0.description < $1.description }, id: \.self) { id in
                    VStack(alignment: .leading) {
                        Text("Original text property unavailable").font(.headline)
                        Text("Your custom text is kept. Recover its original property with Undo or the original project, or remove this custom text.").font(.caption)
                        Text(overrides[id] ?? "").textSelection(.enabled)
                        Button("Remove custom text") {
                            if let identity = state.componentTextDraftIdentity {
                                state.commitComponentText(.resetTextOverride(instanceID: instance.id, propertyID: id), identity: identity)
                            }
                        }.accessibilityIdentifier("component.text.missing.reset.\(id)").help(AuthoringLanguage.removeCustomValueHelp)
                    }
                }
                Button(AuthoringLanguage.componentResetTitle(count: state.componentAuthoredPropertyIdentities.count)) {
                    if let identity = state.componentTextDraftIdentity {
                        state.commitComponentText(.resetAllOverrides(instance.id), identity: identity)
                    }
                }
                .disabled((overrides.isEmpty && CanonicalComponentVisibility.overrides(on: instance).isEmpty
                    && CanonicalComponentChoice.overrides(on: instance).isEmpty
                    && CanonicalComponentMedia.overrides(on: instance).isEmpty
                    && CanonicalComponentAction.overrides(on: instance).isEmpty)
                    || !state.componentTextEditingAvailable)
                .accessibilityIdentifier("component.text.resetAll").help("Removes this copy’s custom values in the named scope, including values outside search results. Missing originals stay missing. Undo restores exact values.")
                Text("Reset copy changes removes custom values and uses available original values. Empty text is a custom value too; missing original data is not restored.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(state.editingComponentID != nil
                     ? "Select one Text layer in this definition to expose a plain-text property. Multiple selection is inspection-only."
                     : "Select one linked instance to edit its text properties. Multiple selection is inspection-only.")
                    .font(.caption)
            }
            if !state.componentTextEditingAvailable {
                Text("Editing requires one available, unlocked, visible canonical object.").font(.caption)
            }
            ComponentFeedbackText(announcement: state.componentAnnouncement)
                .font(.caption).accessibilityLabel("Component text status")
                .accessibilityValue(state.componentAnnouncement)
                .accessibilityIdentifier("component.text.status")
        }
    }
}

private struct ComponentVisibilityInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text("Component Visibility").font(.headline)
            if let node = state.selectedDefinitionVisibilityChild {
                ComponentVisibilityDefinitionFields(state: state, node: node)
                    .disabled(!state.componentVisibilityEditingAvailable)
            } else if let instance = state.selectedComponent {
                let properties = state.componentVisibilityProperties
                let overrides = CanonicalComponentVisibility.overrides(on: instance)
                if properties.isEmpty {
                    Text("No exposed visibility properties. Edit the definition, select a child layer, then expose its visibility here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(properties) { property in
                    ComponentVisibilityInstanceFields(state: state, instanceID: instance.id,
                        property: property, authored: overrides[property.id])
                        .disabled(!state.componentVisibilityEditingAvailable)
                }
                ForEach(overrides.keys.filter { id in !properties.contains { $0.id == id } }
                    .sorted { $0.description < $1.description }, id: \.self) { id in
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                        Text("Original visibility property unavailable").font(.headline)
                        Text("Your visibility choice is kept. Recover its original property with Undo or the original project, or remove this custom choice.")
                            .font(.caption)
                        Button("Remove custom visibility") {
                            if let identity = state.componentTextDraftIdentity {
                                state.commitComponentVisibility(.resetVisibilityOverride(instanceID: instance.id,
                                    propertyID: id), identity: identity)
                            }
                        }.accessibilityIdentifier("component.visibility.missing.reset.\(id)").help(AuthoringLanguage.removeCustomValueHelp)
                    }
                }
                Button(AuthoringLanguage.componentResetTitle(count: CanonicalComponentVisibility.overrides(on: instance).count, visibilityOnly: true)) {
                    if let identity = state.componentTextDraftIdentity {
                        state.commitComponentVisibility(.resetAllVisibilityOverrides(instance.id), identity: identity)
                    }
                }
                .disabled(overrides.isEmpty || !state.componentVisibilityEditingAvailable)
                .accessibilityIdentifier("component.visibility.resetAll").help("Removes this copy’s custom values in the named scope, including values outside search results. Missing originals stay missing. Undo restores exact values.")
            } else {
                Text("Select a child layer on the original or a linked copy to edit visibility. This property cannot control the entire original component.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ComponentFeedbackText(announcement: state.componentAnnouncement)
                .font(.caption).accessibilityLabel("Component visibility status")
                .accessibilityValue(state.componentAnnouncement)
                .accessibilityIdentifier("component.visibility.status")
        }
    }
}

private struct ComponentVisibilityDefinitionFields: View {
    @ObservedObject var state: WorkspaceShellState
    let node: DocumentNode
    @State private var name: String
    @State private var defaultVisible: Bool
    @State private var identity: DesignInspectorOperationIdentity?
    @State private var cancelled = false

    init(state: WorkspaceShellState, node: DocumentNode) {
        self.state = state; self.node = node
        let binding = CanonicalComponentVisibility.property(on: node)
        _name = State(initialValue: binding?.label ?? node.name)
        _defaultVisible = State(initialValue: binding?.defaultValue ?? !node.selectionBooleanProperty("hidden"))
        _identity = State(initialValue: state.componentTextDraftIdentity)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text(CanonicalComponentVisibility.property(on: node) == nil
                ? "Not exposed · canonical child visibility" : "Exposed · Boolean definition default")
                .font(.caption).accessibilityIdentifier("component.visibility.definition.provenance")
            TextField("Property name", text: $name)
                .accessibilityLabel("Component visibility property name")
                .accessibilityIdentifier("component.visibility.definition.name")
            Toggle("Visible by default", isOn: $defaultVisible)
                .accessibilityIdentifier("component.visibility.definition.default")
            HStack {
                Button(CanonicalComponentVisibility.property(on: node) == nil ? "Expose Visibility" : "Apply") { commit() }
                    .accessibilityIdentifier("component.visibility.definition.apply")
                Button("Cancel") { cancel() }.accessibilityIdentifier("component.visibility.definition.cancel")
                Button("Remove Property") {
                    if let identity { state.commitComponentVisibility(.removeVisibilityProperty(node.id), identity: identity) }
                }
                .disabled(CanonicalComponentVisibility.property(on: node) == nil)
                .accessibilityIdentifier("component.visibility.definition.remove")
            }
            if cancelled { Text("Draft cancelled; committed visibility unchanged.").font(.caption) }
        }
        .onSubmit { commit() }
        .onExitCommand { cancel() }
    }
    private func commit() {
        if let identity {
            state.commitComponentVisibility(.exposeVisibility(nodeID: node.id, label: name,
                defaultValue: defaultVisible), identity: identity)
        }
    }
    private func cancel() {
        let binding = CanonicalComponentVisibility.property(on: node)
        name = binding?.label ?? node.name
        defaultVisible = binding?.defaultValue ?? !node.selectionBooleanProperty("hidden")
        cancelled = true
    }
}

private struct ComponentVisibilityInstanceFields: View {
    @ObservedObject var state: WorkspaceShellState
    let instanceID: NodeID
    let property: ExposedComponentVisibilityProperty
    let authored: Bool?
    @State private var identity: DesignInspectorOperationIdentity?

    init(state: WorkspaceShellState, instanceID: NodeID, property: ExposedComponentVisibilityProperty,
         authored: Bool?) {
        self.state = state; self.instanceID = instanceID; self.property = property; self.authored = authored
        _identity = State(initialValue: state.componentTextDraftIdentity)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Toggle(property.label, isOn: Binding(
                get: { authored ?? property.defaultValue },
                set: { value in
                    if let identity {
                        state.commitComponentVisibility(.setVisibilityOverride(instanceID: instanceID,
                            propertyID: property.id, value: value), identity: identity)
                    }
                }
            ))
            .accessibilityLabel("\(property.label) visible in this component instance")
            .accessibilityValue((authored ?? property.defaultValue) ? "Visible" : "Hidden")
            .accessibilityHint(AuthoringLanguage.componentSource(isOverride: authored != nil))
            .accessibilityIdentifier("component.visibility.value.\(property.id)")
            Text(AuthoringLanguage.componentSource(isOverride: authored != nil))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("component.visibility.provenance.\(property.id)")
            Button(AuthoringLanguage.useOriginalValue) {
                if let identity { state.commitComponentVisibility(.resetVisibilityOverride(instanceID: instanceID,
                    propertyID: property.id), identity: identity) }
            }
            .disabled(authored == nil)
            .accessibilityIdentifier("component.visibility.reset.\(property.id)").help(AuthoringLanguage.removeCustomValueHelp)
        }
    }
}

/// SF-0902: a native enum control exposes Image fit without copying asset or
/// geometry state into the component instance.
private struct ComponentChoiceInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text("Component Choice").font(.headline)
            if let node = state.selectedDefinitionChoiceImage {
                ComponentChoiceDefinitionFields(state: state, node: node)
            } else if let instance = state.selectedComponent {
                let overrides = CanonicalComponentChoice.overrides(on: instance)
                ForEach(state.componentChoiceProperties) { property in
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                        Picker(property.label, selection: Binding(
                            get: { overrides[property.id] ?? property.defaultValue },
                            set: { value in
                                if let identity = state.componentTextDraftIdentity {
                                    state.commitComponentChoice(.setChoiceOverride(instanceID: instance.id,
                                        propertyID: property.id, value: value), identity: identity)
                                }
                            })) {
                            ForEach(ImageFitMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .accessibilityLabel(property.label + " component choice")
                        .accessibilityValue((overrides[property.id] ?? property.defaultValue).rawValue.capitalized)
                        .accessibilityHint(overrides[property.id] == nil
                            ? "Uses component default" : "Set here · this instance")
                        .accessibilityIdentifier("component.choice.value.\(property.id)")
                        Text(AuthoringLanguage.componentSource(isOverride: overrides[property.id] != nil))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(AuthoringLanguage.useOriginalValue) {
                            if let identity = state.componentTextDraftIdentity {
                                state.commitComponentChoice(.resetChoiceOverride(instanceID: instance.id,
                                    propertyID: property.id), identity: identity)
                            }
                        }
                        .disabled(overrides[property.id] == nil)
                        .accessibilityIdentifier("component.choice.reset.\(property.id)").help(AuthoringLanguage.removeCustomValueHelp)
                    }
                }
            }
            ComponentFeedbackText(announcement: state.componentAnnouncement)
                .font(.caption).accessibilityLabel("Component choice status")
                .accessibilityValue(state.componentAnnouncement)
                .accessibilityIdentifier("component.choice.status")
        }
    }
}

private struct ComponentChoiceDefinitionFields: View {
    @ObservedObject var state: WorkspaceShellState
    let node: DocumentNode
    @State private var label: String
    @State private var cancelled = false

    init(state: WorkspaceShellState, node: DocumentNode) {
        self.state = state; self.node = node
        _label = State(initialValue: CanonicalComponentChoice.property(on: node)?.label ?? "Image Fit")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Text(CanonicalComponentChoice.property(on: node) == nil
                ? "Not exposed · Image fit" : "Exposed · Image fit · definition default")
                .font(.caption).accessibilityIdentifier("component.choice.definition.provenance")
            TextField("Property name", text: Binding(get: { label }, set: { label = $0; cancelled = false }))
                .accessibilityIdentifier("component.choice.definition.name")
                .onSubmit { commit() }
            HStack {
                Button(CanonicalComponentChoice.property(on: node) == nil ? "Expose Image Fit" : "Apply") { commit() }
                    .accessibilityIdentifier("component.choice.definition.apply")
                Button("Cancel") {
                    label = CanonicalComponentChoice.property(on: node)?.label ?? "Image Fit"
                    cancelled = true
                }.accessibilityIdentifier("component.choice.definition.cancel")
                Button("Remove Property") {
                    if let identity = state.componentTextDraftIdentity {
                        state.commitComponentChoice(.removeChoiceProperty(node.id), identity: identity)
                    }
                }
                .disabled(CanonicalComponentChoice.property(on: node) == nil)
                .accessibilityIdentifier("component.choice.definition.remove")
            }
            if cancelled { Text("Draft cancelled; committed choice unchanged.").font(.caption) }
        }
        .onExitCommand {
            label = CanonicalComponentChoice.property(on: node)?.label ?? "Image Fit"
            cancelled = true
        }
    }
    private func commit() {
        if let identity = state.componentTextDraftIdentity {
            state.commitComponentChoice(.exposeChoice(nodeID: node.id, label: label), identity: identity)
        }
    }
}

/// SF-0902: media overrides select an existing project AssetID. The picker
/// never stores a path or resource bytes in the component instance.
private struct ImageUseActionsView: View {
    @ObservedObject var state: WorkspaceShellState
    let target: ImageAssetUseRequest.Target
    let currentAssetID: AssetID?
    let identifier: String
    @State private var choosing: ImageAssetUseRequest?
    @State private var showingSharedStatus = false
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Button("Choose from Assets…") {
                if state.prepareForWorkspaceAction(.context) { choosing = state.imageAssetUseRequest(target) }
            }
                .accessibilityIdentifier(identifier + ".choose")
            Button("Import Image…") {
                guard state.prepareForWorkspaceAction(.context) else { return }
                if let request = state.imageAssetUseRequest(target) { state.importImageForUse(request) }
            }.accessibilityIdentifier(identifier + ".import")
            if let currentAssetID, state.documentSession.document.imageAssets.contains(where: { $0.id == currentAssetID }) {
                Text(state.imageAssetUsageSummary(currentAssetID)).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(identifier + ".references")
                Menu("Shared Asset Actions") {
                    Button("Reveal Usage") { state.revealImageUsage(currentAssetID) }
                    Button("Replace Asset Everywhere…") { showingSharedStatus = true; state.replaceImageAsset(currentAssetID) }
                }.accessibilityIdentifier(identifier + ".sharedActions")
            } else if currentAssetID != nil {
                Text("Asset definition is missing. Choose or import a replacement for these selected uses; the original reference stays unchanged until you commit.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + ".missingDefinition")
            }
            Text(targetScope).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if showingSharedStatus {
                Text(state.lastAssetAnnouncement).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + ".assetStatus")
            }
            if state.isImportingImages { ProgressView("Importing image…").controlSize(.small) }
        }.disabled(state.isImportingImages || state.imageAssetUseRequest(target) == nil)
            .sheet(item: $choosing) { request in
                ImageUseAssetChooser(state: state, request: request, dismiss: { choosing = nil })
            }
    }
    private var targetScope: String {
        if case .componentMedia = target { return "Change this copy only. Use original value removes its custom image choice; an unavailable original image is not repaired." }
        if state.editingComponentID != nil { return "Definition change: inherited instances update; authored instance overrides stay independent." }
        return "Change selected uses only. Shared Asset Actions affects every reference."
    }
}

private struct ImageUseAssetChooser: View {
    @ObservedObject var state: WorkspaceShellState
    let request: ImageAssetUseRequest
    let dismiss: () -> Void
    @State private var search = ""
    @State private var message = ""
    private var matches: [ImageAsset] {
        state.imageAssetsForReuse(search: search)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Choose Image for Selected Use").font(.title2)
            Text(request.scopeDescription).font(.caption).fixedSize(horizontal: false, vertical: true)
            TextField("Search project images", text: $search).textFieldStyle(.roundedBorder)
                .focusedValue(\.siteforgeNativeTextEditor, true).accessibilityIdentifier("asset.use.search")
            if matches.isEmpty {
                Text(state.documentSession.document.imageAssets.isEmpty ? "No images imported. Import a local raster image to use it here." : "No matching images. Clear the search or import another image.")
                    .font(.caption).accessibilityIdentifier("asset.use.empty")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                    ForEach(matches) { asset in
                        Button {
                            if state.chooseImageAssetForUse(asset.id, request: request) { dismiss() }
                            else { message = state.lastImageInspectorAnnouncement }
                        } label: {
                            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                            if let data = state.imageAssetThumbnail(asset.id), let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 48, height: 36).accessibilityHidden(true)
                            } else { Image(systemName: "photo").frame(width: 48, height: 36).accessibilityHidden(true) }
                            VStack(alignment: .leading) {
                                Text(asset.displayName).lineLimit(1)
                                Text("\(asset.pixelWidth) × \(asset.pixelHeight) · \(state.imageAssetUsageCount(asset.id)) references")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.accessibilityIdentifier("asset.use.choose." + asset.id.description)
                    }
                }
            }.frame(height: 260)
            if !message.isEmpty { Text(message).font(.caption).accessibilityIdentifier("asset.use.validation") }
            HStack {
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction).accessibilityIdentifier("asset.use.cancel")
                Spacer()
                Button("Import Image…") {
                    dismiss()
                    Task { @MainActor in await Task.yield(); state.importImageForUse(request) }
                }.accessibilityIdentifier("asset.use.import")
            }
        }.padding(SiteForgeVisualSystem.sectionSpacing).frame(width: 430)
            .onExitCommand(perform: dismiss)
    }
}

private struct ComponentMediaInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text("Component Image").font(.headline)
            if let node = state.selectedDefinitionMediaImage {
                ComponentMediaDefinitionFields(state: state, node: node)
            } else if let instance = state.selectedComponent {
                let overrides = CanonicalComponentMedia.overrides(on: instance)
                ForEach(state.componentMediaProperties) { property in
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                        Picker(property.label, selection: Binding(
                            get: { overrides[property.id] ?? property.defaultValue },
                            set: { assetID in
                                if let identity = state.componentTextDraftIdentity {
                                    state.commitComponentMedia(.setMediaOverride(instanceID: instance.id,
                                        propertyID: property.id, assetID: assetID), identity: identity)
                                }
                            })) {
                            ForEach(state.imageAssetsForReuse(search: "")) { asset in
                                Text(asset.displayName).tag(asset.id)
                            }
                        }
                        .disabled(state.documentSession.document.imageAssets.isEmpty)
                        .accessibilityLabel(property.label + " component image")
                        .accessibilityValue(state.documentSession.document.imageAssets.first(where: {
                            $0.id == (overrides[property.id] ?? property.defaultValue)
                        })?.displayName ?? "Missing image asset")
                        .accessibilityHint(overrides[property.id] == nil
                            ? "Uses component default" : "Set here · this instance")
                        .accessibilityIdentifier("component.media.value.\(property.id)")
                        Text(AuthoringLanguage.componentSource(isOverride: overrides[property.id] != nil))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(AuthoringLanguage.useOriginalValue) {
                            if let identity = state.componentTextDraftIdentity {
                                state.commitComponentMedia(.resetMediaOverride(instanceID: instance.id,
                                    propertyID: property.id), identity: identity)
                            }
                        }
                        .disabled(overrides[property.id] == nil)
                        .accessibilityIdentifier("component.media.reset.\(property.id)").help(AuthoringLanguage.removeCustomValueHelp)
                    }
                }
            }
            ComponentFeedbackText(announcement: state.componentAnnouncement)
                .font(.caption).accessibilityLabel("Component image status")
                .accessibilityValue(state.componentAnnouncement)
                .accessibilityIdentifier("component.media.status")
        }
    }
}

private struct ComponentMediaDefinitionFields: View {
    @ObservedObject var state: WorkspaceShellState
    let node: DocumentNode
    @State private var label: String
    @State private var cancelled = false

    init(state: WorkspaceShellState, node: DocumentNode) {
        self.state = state; self.node = node
        _label = State(initialValue: CanonicalComponentMedia.property(on: node)?.label ?? "Image")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Text(CanonicalComponentMedia.property(on: node) == nil
                ? "Not exposed · Image asset" : "Exposed · Image asset · definition default")
                .font(.caption).accessibilityIdentifier("component.media.definition.provenance")
            TextField("Property name", text: Binding(get: { label }, set: { label = $0; cancelled = false }))
                .accessibilityLabel("Component image property name")
                .accessibilityIdentifier("component.media.definition.name")
                .onSubmit { commit() }
            HStack {
                Button(CanonicalComponentMedia.property(on: node) == nil ? "Expose Image" : "Apply") { commit() }
                    .accessibilityIdentifier("component.media.definition.apply")
                Button("Cancel") { cancel() }.accessibilityIdentifier("component.media.definition.cancel")
                Button("Remove Property") {
                    if let identity = state.componentTextDraftIdentity {
                        state.commitComponentMedia(.removeMediaProperty(node.id), identity: identity)
                    }
                }
                .disabled(CanonicalComponentMedia.property(on: node) == nil)
                .accessibilityIdentifier("component.media.definition.remove")
            }
            if cancelled { Text("Draft cancelled; committed image unchanged.").font(.caption) }
        }
        .onExitCommand { cancel() }
    }
    private func commit() {
        if let identity = state.componentTextDraftIdentity {
            state.commitComponentMedia(.exposeMedia(nodeID: node.id, label: label), identity: identity)
        }
    }
    private func cancel() {
        label = CanonicalComponentMedia.property(on: node)?.label ?? "Image"
        cancelled = true
    }
}

private struct ComponentActionInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        GroupBox("Component Actions") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                if let control = state.selectedDefinitionActionControl {
                    ComponentActionDefinitionFields(state: state, node: control)
                } else if let instance = state.selectedComponent {
                    let overrides = CanonicalComponentAction.overrides(on: instance)
                    ForEach(state.componentActionProperties) { property in
                        ComponentActionDestinationFields(state: state, instance: instance, property: property,
                            committed: overrides[property.id] ?? property.defaultValue,
                            isAuthored: overrides[property.id] != nil)
                    }
                    let known = Set(state.componentActionProperties.map(\.id))
                    ForEach(overrides.keys.filter { !known.contains($0) }.sorted { $0.description < $1.description }, id: \.self) { id in
                        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                            Label("Original destination property unavailable · custom destination kept", systemImage: "exclamationmark.triangle")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                            Button("Remove custom destination") {
                                if let identity = state.componentTextDraftIdentity {
                                    state.commitComponentAction(.resetActionOverride(instanceID: instance.id, propertyID: id), identity: identity)
                                }
                            }.accessibilityIdentifier("component.action.missing.reset.\(id)").help(AuthoringLanguage.removeCustomValueHelp)
                        }
                    }
                    if state.componentActionProperties.isEmpty && overrides.isEmpty {
                        Text("This definition has no exposed Button or Link destinations.").font(.caption)
                    }
                    Button(AuthoringLanguage.componentResetTitle(count: state.componentAuthoredPropertyIdentities.count)) {
                        if let identity = state.componentTextDraftIdentity {
                            state.commitComponentAction(.resetAllOverrides(instance.id), identity: identity)
                        }
                    }
                    .disabled(!state.componentTextEditingAvailable || (instance.properties.allSatisfy {
                        !$0.key.rawValue.hasPrefix(CanonicalComponentReference.namespace) || $0.key.rawValue == CanonicalComponentReference.key
                    }))
                    .accessibilityIdentifier("component.action.resetAll").help("Removes this copy’s custom values in the named scope, including values outside search results. Missing originals stay missing. Undo restores exact values.")
                } else {
                    Text(state.selectionState.count > 1
                         ? "Mixed selection · component actions are inspection-only. Select one linked instance or one definition control."
                         : "Select a Button or Link in the definition to expose its destination.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("component.action.unavailable")
                }
                ComponentFeedbackText(announcement: state.componentAnnouncement).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Component action status").accessibilityValue(state.componentAnnouncement)
                    .accessibilityIdentifier("component.action.status")
            }
        }
        .disabled(!state.componentTextEditingAvailable)
    }
}

private struct ComponentActionDefinitionFields: View {
    @ObservedObject var state: WorkspaceShellState
    let node: DocumentNode
    @State private var label: String
    @State private var identity: DesignInspectorOperationIdentity?
    @State private var cancelled = false

    init(state: WorkspaceShellState, node: DocumentNode) {
        self.state = state; self.node = node
        _label = State(initialValue: CanonicalComponentAction.property(on: node)?.label ?? "Destination")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text(CanonicalComponentAction.property(on: node) == nil ? "Not exposed · definition destination" : "Exposed · definition destination")
                .font(.caption).accessibilityIdentifier("component.action.definition.provenance")
            TextField("Property name", text: $label)
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .accessibilityLabel("Component action property name")
                .accessibilityIdentifier("component.action.definition.name")
                .onSubmit { apply() }
            Text("The default is this control’s existing Link Target. Edit it in Interactions.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Edit Default Destination") { _ = state.selectInspectorTab(.interactions) }
                .accessibilityHint("Uses the existing native Link Target editor for this definition control")
                .accessibilityIdentifier("component.action.definition.editDefault")
            HStack {
                Button(CanonicalComponentAction.property(on: node) == nil ? "Expose Action" : "Apply", action: apply)
                    .accessibilityIdentifier("component.action.definition.apply")
                Button("Cancel", action: cancel).accessibilityIdentifier("component.action.definition.cancel")
            }
            Button("Remove Property") {
                if let identity { state.commitComponentAction(.removeActionProperty(node.id), identity: identity) }
            }
            .disabled(CanonicalComponentAction.property(on: node) == nil)
            .accessibilityHint("Existing instance values remain inspectable as missing-binding conflicts")
            .accessibilityIdentifier("component.action.definition.remove")
            if cancelled { Text("Draft cancelled; the committed action is unchanged.").font(.caption) }
        }
        .onAppear { identity = state.componentTextDraftIdentity }
        .onExitCommand { cancel() }
    }
    private func apply() {
        guard let identity else { return }
        if state.commitComponentAction(.exposeAction(nodeID: node.id, label: label), identity: identity) { cancelled = false }
    }
    private func cancel() {
        label = CanonicalComponentAction.property(on: node)?.label ?? "Destination"
        identity = state.componentTextDraftIdentity; cancelled = true
    }
}

private struct ComponentActionDestinationFields: View {
    @ObservedObject var state: WorkspaceShellState
    let instance: DocumentNode
    let property: ExposedComponentActionProperty
    let committed: CanonicalLinkTarget
    let isAuthored: Bool
    @State private var kind = "none"
    @State private var page = ""
    @State private var section = ""
    @State private var url = ""
    @State private var identity: DesignInspectorOperationIdentity?
    @State private var message = ""
    @FocusState private var focus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text(property.label).font(.headline).lineLimit(1).help(property.label)
            if let definitionID = CanonicalComponentReference.definitionID(for: instance),
               state.componentDefinitions.first(where: { $0.id == definitionID })?.nodes.first(where: { $0.id == property.sourceNodeID })?.kind == .button {
                Text("Button destination intent is retained. Navigation execution remains unavailable for Buttons; Links use the supported Preview path.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(AuthoringLanguage.componentSource(isOverride: isAuthored))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("component.action.provenance.\(property.id)")
            if committed.isMissing(in: state.documentSession.document) {
                Label("Destination unavailable. Choose another destination, or use the original value if available. This does not restore a deleted page.", systemImage: "exclamationmark.triangle")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.action.missing.\(property.id)")
            }
            NativeLinkDestinationFields(document: state.documentSession.document,
                kind: $kind, page: $page, section: $section, url: $url, focus: $focus,
                allowsMixed: false, identifierPrefix: "component.action.target.\(property.id)", onSubmit: apply)
            HStack {
                Button("Apply", action: apply).accessibilityIdentifier("component.action.apply.\(property.id)")
                Button("Cancel") { refresh(); message = "Draft cancelled; committed action unchanged." }
                    .accessibilityIdentifier("component.action.cancel.\(property.id)")
                Button(AuthoringLanguage.useOriginalValue) {
                    if let identity { state.commitComponentAction(.resetActionOverride(instanceID: instance.id, propertyID: property.id), identity: identity) }
                }.disabled(!isAuthored).accessibilityIdentifier("component.action.reset.\(property.id)").help(AuthoringLanguage.removeCustomValueHelp)
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.action.validation.\(property.id)")
            }
        }
        .onAppear { refresh() }
        .onExitCommand { refresh(); message = "Draft cancelled; committed action unchanged." }
    }
    private func refresh() {
        identity = state.componentTextDraftIdentity; page = ""; section = ""; url = ""; focus = nil
        switch committed {
        case .none: kind = "none"
        case .page(let id): kind = "page"; page = id.description
        case .section(let pageID, let nodeID): kind = "section"; page = pageID.description; section = nodeID.description
        case .external(let value): kind = "external"; url = value
        }
    }
    private func apply() {
        let target: CanonicalLinkTarget
        switch kind {
        case "none": target = .none
        case "page":
            guard let id = PageID(uuidString: page) else { message = "Choose an available page."; return }
            target = .page(id)
        case "section":
            guard let pageID = PageID(uuidString: page), let nodeID = NodeID(uuidString: section) else {
                message = "Choose an available page and section."; return
            }
            target = .section(pageID: pageID, nodeID: nodeID)
        case "external": target = .external(url)
        default: message = "Choose a supported destination."; return
        }
        guard let identity else { message = "Wait for the current component to finish adopting, then retry."; return }
        if state.commitComponentAction(.setActionOverride(instanceID: instance.id, propertyID: property.id, target: target), identity: identity) {
            message = ""; focus = nil
        } else { message = state.componentAnnouncement }
    }
}

private struct ComponentSlotInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        GroupBox("Default contents (slots)") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                if let container = state.selectedDefinitionSlotContainer {
                    ComponentSlotDefinitionFields(state: state, node: container)
                } else if let instance = state.selectedComponent {
                    if let definitionID = CanonicalComponentReference.definitionID(for: instance),
                       !state.componentDefinitions.contains(where: { $0.id == definitionID }) {
                        Label("Original component unavailable. This copy keeps its reference. Recover the original with Undo or the saved project to inspect default contents.", systemImage: "exclamationmark.triangle")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("component.slot.definition.missing")
                    } else if state.componentSlotProperties.isEmpty {
                        Text("No named default contents. Edit the original and choose a container inside it to make its contents available to copies.")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("component.slot.empty")
                    }
                    ForEach(state.componentSlotProperties) { property in
                        ComponentSlotFallbackFields(state: state, instance: instance, property: property)
                    }
                } else {
                    Text(state.selectionState.count > 1
                         ? "Mixed selection · slots are inspection-only. Select one instance or one definition container."
                         : "Select a Frame, Section, Stack or Grid inside the original component to share its existing contents.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("component.slot.unavailable")
                }
                Text("Default contents come from the original component. Custom contents for one copy are not available; edit the original to change shared contents.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.slot.supply.unavailable")
                ComponentFeedbackText(announcement: state.componentAnnouncement).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Component slot status").accessibilityValue(state.componentAnnouncement)
                    .accessibilityIdentifier("component.slot.status")
            }
        }
    }
}

private struct ComponentSlotDefinitionFields: View {
    @ObservedObject var state: WorkspaceShellState
    let node: DocumentNode
    @State private var label: String
    @State private var identity: DesignInspectorOperationIdentity?
    @State private var cancelled = false

    init(state: WorkspaceShellState, node: DocumentNode) {
        self.state = state; self.node = node
        _label = State(initialValue: CanonicalComponentSlot.property(on: node)?.label ?? "Content")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text(CanonicalComponentSlot.property(on: node) == nil ? "Not shared · existing child items" : "Shared default contents · owned by the original")
                .font(.caption).accessibilityIdentifier("component.slot.definition.provenance")
            TextField("Default contents name", text: Binding(get: { label }, set: { label = $0; cancelled = false }))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .accessibilityLabel("Default contents name (component slot)")
                .accessibilityHint("Apply or Return names the existing container. Escape or Cancel keeps the committed slot unchanged.")
                .accessibilityIdentifier("component.slot.definition.name")
                .onSubmit { apply() }
            Text("\(node.childIDs.count) top-level item\(node.childIDs.count == 1 ? "" : "s") in order")
                .font(.caption).accessibilityIdentifier("component.slot.definition.children")
            Text("Use Elements or Insert to add items; use Layers to select and reorder them. This changes default contents on the original component.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(CanonicalComponentSlot.property(on: node) == nil ? "Share default contents" : "Apply", action: apply)
                    .accessibilityIdentifier("component.slot.definition.apply")
                Button("Cancel", action: cancel).accessibilityIdentifier("component.slot.definition.cancel")
            }
            Button("Stop sharing contents property") {
                if let identity { state.commitComponentSlot(.removeSlotProperty(node.id), identity: identity) }
            }
            .disabled(CanonicalComponentSlot.property(on: node) == nil)
            .accessibilityHint("Stops sharing this named contents property; the container and all its child items remain on the original component")
            .accessibilityIdentifier("component.slot.definition.remove")
            if cancelled { Text("Draft cancelled; the committed slot is unchanged.").font(.caption) }
        }
        .disabled(!state.componentTextEditingAvailable)
        .onAppear { identity = state.componentTextDraftIdentity }
        .onExitCommand { cancel() }
    }
    private func apply() {
        guard let identity else { return }
        if state.commitComponentSlot(.exposeSlot(nodeID: node.id, label: label), identity: identity) { cancelled = false }
    }
    private func cancel() {
        label = CanonicalComponentSlot.property(on: node)?.label ?? "Content"
        identity = state.componentTextDraftIdentity; cancelled = true
    }
}

private struct ComponentSlotFallbackFields: View {
    @ObservedObject var state: WorkspaceShellState
    let instance: DocumentNode
    let property: ExposedComponentSlotProperty
    @State private var identity: DesignInspectorOperationIdentity?

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text(property.label).font(.headline).lineLimit(1).help(property.label)
            Text("Default contents · \(property.defaultChildIDs.count) top-level items")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Default contents for \(property.label), from the original component")
                .accessibilityValue("Contents from original; \(property.defaultChildIDs.count) top-level items; custom contents for this copy are unavailable")
                .accessibilityIdentifier("component.slot.provenance.\(property.id)")
            if property.defaultChildIDs.isEmpty {
                Text("No default contents. Edit the original component to add supported items.")
                    .font(.caption).accessibilityIdentifier("component.slot.fallback.empty.\(property.id)")
            } else {
                ForEach(Array(property.defaultChildIDs.prefix(8).enumerated()), id: \.element) { index, childID in
                    let name = state.componentDefinitions.flatMap(\.nodes).first(where: { $0.id == childID })?.name ?? "Default item unavailable"
                    Text("\(index + 1). \(name)").font(.caption).lineLimit(1).help(name)
                        .accessibilityLabel("Default item \(index + 1): \(name)")
                        .accessibilityIdentifier("component.slot.child.\(property.id).\(childID)")
                }
                if property.defaultChildIDs.count > 8 {
                    Text("\(property.defaultChildIDs.count - 8) more top-level items · open the original to inspect all contents")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Edit default contents") {
                if let identity {
                    state.editComponentSlotFallback(property.id, instanceID: instance.id, identity: identity)
                }
            }
            .disabled(!state.componentTextEditingAvailable)
            .accessibilityHint("Opens the contents container on the original component. Changes update linked copies; no custom contents are created on this copy.")
            .accessibilityIdentifier("component.slot.editFallback.\(property.id)")
        }
        .onAppear { identity = state.componentTextDraftIdentity }
    }
}

private struct ComponentTextDefinitionFields: View {
    @ObservedObject var state: WorkspaceShellState
    let node: DocumentNode
    @State private var draft: ComponentDefinitionTextDraft
    @State private var cancelled = false
    @State private var validation = ""
    private enum Field: Hashable { case name, content }
    @FocusState private var focusedField: Field?

    init(state: WorkspaceShellState, node: DocumentNode) {
        self.state = state; self.node = node
        let binding = CanonicalComponentText.property(on: node)
        _draft = State(initialValue: .init(label: binding?.label ?? "Text", content: node.insertionStringProperty("content.text") ?? "",
            bindingID: binding?.id, identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs))
    }
    private var exposed: ExposedComponentTextProperty? { CanonicalComponentText.property(on: node) }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Text(exposed == nil ? "Not exposed · plain text" : "Exposed · plain text · definition default")
                .font(.caption).accessibilityIdentifier("component.text.definition.provenance")
            Text("Shared component default. Linked instances update unless their text was set separately.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Property name").font(.caption)
            TextField("Property name", text: Binding(get: { draft.label.value }, set: { draft.label.value = $0; cancelled = false }))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .focused($focusedField, equals: .name)
                .accessibilityLabel("Component text property name")
                .accessibilityValue(InspectorDraftAccessibility.value(draft: draft.label.isDirty ? draft.label.value : nil,
                    committed: exposed?.label ?? "Text"))
                .accessibilityIdentifier("component.text.definition.name")
            Text("Default text").font(.caption)
            TextField("Default text", text: Binding(get: { draft.content.value }, set: { draft.content.value = $0; cancelled = false }), axis: .vertical).lineLimit(1...4)
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .focused($focusedField, equals: .content)
                .accessibilityLabel("Component default text")
                .accessibilityValue(InspectorDraftAccessibility.value(draft: draft.content.isDirty ? draft.content.value : nil,
                    committed: node.insertionStringProperty("content.text") ?? ""))
                .accessibilityIdentifier("component.text.definition.default")
            InspectorActionLayout {
                Button(exposed == nil ? "Expose Text" : "Apply") { commit(allowExpose: true) }
                    .disabled(draft.identity == nil || (exposed != nil && !draft.isDirty))
                    .accessibilityIdentifier("component.text.definition.apply")
                Button("Cancel") { cancel() }.disabled(!draft.isDirty && !draft.hasConflict)
                    .accessibilityIdentifier("component.text.definition.cancel")
            }
            Button("Remove Text Property") {
                guard let identity = draft.identity else { return }
                if state.commitComponentText(.removeTextProperty(node.id), identity: identity) { cancel() }
            }.disabled(exposed == nil || draft.identity == nil).accessibilityIdentifier("component.text.definition.remove")
            if cancelled { Text("Draft cancelled; committed text unchanged.").font(.caption) }
            if !validation.isEmpty {
                Text(validation).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.text.definition.validation")
            }
        }
        .onSubmit { commit(allowExpose: true) }
        .onExitCommand { cancel() }
        .onChange(of: state.componentTextDraftIdentity) { _, _ in adopt() }
        .onChange(of: node) { _, _ in adopt() }
        .onChange(of: focusedField) { old, current in
            guard old != nil, current == nil, draft.isDirty else { return }
            let expected = draft
            DispatchQueue.main.async {
                guard focusedField == nil, draft == expected else { return }
                commit()
            }
        }
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted else { return }
            if request.requiresCleanEditors {
                if draft.isDirty || draft.hasConflict { request.reject() }
                return
            }
            commit()
            if draft.isDirty || draft.hasConflict { request.reject() }
        }
    }
    private func commit(allowExpose: Bool = false) {
        guard draft.isDirty || (allowExpose && exposed == nil) else { return }
        guard exposed != nil || allowExpose else {
            validation = "Choose Expose Text to create this property, or Cancel the draft before leaving."; return
        }
        guard let identity = draft.identity, !draft.hasConflict else {
            validation = "The definition or binding changed. Your draft is retained; Cancel to load the current source."; return
        }
        if state.commitComponentText(.exposeText(nodeID: node.id, label: draft.label.value,
            defaultValue: draft.content.value), identity: identity) {
            let committed = state.selectedDefinitionText ?? node
            let binding = CanonicalComponentText.property(on: committed)
            draft = .init(label: binding?.label ?? "Text", content: committed.insertionStringProperty("content.text") ?? "",
                bindingID: binding?.id, identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs)
            validation = ""; cancelled = false
        } else { validation = state.componentAnnouncement }
    }
    private func adopt() {
        draft.adopt(label: exposed?.label ?? "Text", content: node.insertionStringProperty("content.text") ?? "",
            bindingID: exposed?.id, identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs)
        if draft.hasConflict { validation = "The definition or binding changed. Cancel to reload; the draft is retained." }
    }
    private func cancel() {
        let committed = state.selectedDefinitionText ?? node
        let binding = CanonicalComponentText.property(on: committed)
        draft = .init(label: binding?.label ?? "Text", content: committed.insertionStringProperty("content.text") ?? "",
            bindingID: binding?.id, identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs)
        validation = ""; cancelled = true
        state.clearWorkspaceActionNotice()
    }
}

private struct ComponentTextInstanceFields: View {
    @ObservedObject var state: WorkspaceShellState
    let instanceID: NodeID
    let property: ExposedComponentTextProperty
    let authored: String?
    @State private var draft: ComponentInstanceTextDraft
    @FocusState private var fieldFocused: Bool
    @State private var cancelled = false
    @State private var validation = ""
    init(state: WorkspaceShellState, instanceID: NodeID, property: ExposedComponentTextProperty, authored: String?) {
        self.state = state; self.instanceID = instanceID; self.property = property; self.authored = authored
        _draft = State(initialValue: .init(committed: authored ?? property.defaultValue,
            identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Text(property.label).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(AuthoringLanguage.componentSource(isOverride: authored != nil))
                .font(.caption).accessibilityIdentifier("component.text.provenance.\(property.id)")
            TextField(property.label, text: Binding(get: { draft.value }, set: { draft.value = $0; cancelled = false; validation = "" }), axis: .vertical).lineLimit(1...4)
                .focused($fieldFocused).focusedValue(\.siteforgeNativeTextEditor, true)
                .accessibilityLabel(property.label + " component text")
                .accessibilityIdentifier("component.text.value.\(property.id)")
                .onSubmit { commit() }
            InspectorActionLayout {
                if draft.isDirty || draft.conflict != nil {
                    Button("Apply") { commit() }.accessibilityIdentifier("component.text.apply.\(property.id)")
                    Button("Cancel") { cancel() }.accessibilityIdentifier("component.text.cancel.\(property.id)")
                }
                Button("Reset") {
                    if let identity = state.componentTextDraftIdentity {
                        // Reset is an explicit alternative to committing a draft;
                        // any subsequent focus loss must remain mutation-neutral.
                        cancel()
                        state.commitComponentText(.resetTextOverride(instanceID: instanceID, propertyID: property.id), identity: identity)
                    }
                }.disabled(authored == nil).accessibilityIdentifier("component.text.reset.\(property.id)").help(AuthoringLanguage.removeCustomValueHelp)
            }
            if cancelled { Text("Draft cancelled; committed text unchanged.").font(.caption) }
            if !validation.isEmpty {
                Text(validation).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("component.text.validation.\(property.id)")
            }
        }.onExitCommand { cancel() }
            .onReceive(state.editCommitRequests) { request in
                guard request.isAccepted else { return }
                if request.requiresCleanEditors {
                    if draft.isDirty || draft.conflict != nil { request.reject() }
                    return
                }
                commit()
                if draft.isDirty || draft.conflict != nil { request.reject() }
            }
            .onChange(of: state.componentTextDraftIdentity) { _, _ in adopt() }
            .onChange(of: authored ?? property.defaultValue) { _, _ in adopt() }
            .onChange(of: fieldFocused) { wasFocused, focused in
                if wasFocused && !focused && draft.isDirty {
                    let expected = draft
                    DispatchQueue.main.async {
                        guard !fieldFocused, draft == expected else { return }
                        commit()
                    }
                }
            }
    }
    private func commit() {
        guard draft.isDirty else { return }
        guard let identity = draft.identity, draft.conflict == nil else {
            validation = draft.conflict == nil ? "Wait for the current canvas, then retry. Your draft is retained."
                : "The definition or editing context changed. Cancel to load the current value; your draft has not been committed."
            return
        }
        if state.commitComponentText(.setTextOverride(instanceID: instanceID, propertyID: property.id, value: draft.value), identity: identity) {
            // Mark the successful event clean before a possible blur event.
            // Renderer adoption will provide the next usable command identity.
            draft.adopt(committed: draft.value, identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs)
            validation = ""
        } else {
            validation = state.componentAnnouncement
        }
    }
    private func adopt() {
        draft.adopt(committed: authored ?? property.defaultValue, identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs)
        if draft.conflict != nil {
            validation = "The definition or editing context changed. Cancel to load the current value; your draft is retained."
        }
    }
    private func cancel() {
        draft.cancel(committed: authored ?? property.defaultValue, identity: state.componentTextDraftIdentity, selectionIDs: state.selectionState.orderedIDs)
        state.clearWorkspaceActionNotice()
        validation = ""; cancelled = true
    }
}

private struct ComponentsNavigatorView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var inspecting: ComponentDependencyRequest?
    @State private var deleting: PageID?
    @State private var renaming: ComponentRenameRequest?
    @State private var creating: ComponentCreationRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Button("Create Component…") {
                if let node = state.selectedCanonicalNodes.first, let identity = state.componentTextDraftIdentity {
                    creating = .init(nodeID: node.id, name: node.name, identity: identity)
                }
            }
                .disabled(!state.canCreateComponent)
                .help(state.componentCreationUnavailableReason ?? "Name this reusable component. Creation preserves the selected object's identity and is one undoable change.")
                .accessibilityIdentifier("components.create")
            HStack {
                TextField("Search Components", text: $state.componentSearchText)
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityIdentifier("components.search")
                    .onSubmit {
                        if let first = state.filteredComponentDefinitions.first {
                            _ = state.revealComponentDefinition(first.id)
                        }
                    }
                    .onExitCommand { state.componentSearchText = "" }
                if !state.componentSearchText.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") {
                        state.componentSearchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("components.search.clear")
                }
            }
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                Picker("Component Filter", selection: $state.componentCollectionFilter) {
                    ForEach(ComponentCollectionFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .accessibilityLabel("Component Filter")
                .accessibilityIdentifier("components.filter")
                Picker("Component Sort", selection: $state.componentCollectionSort) {
                    ForEach(ComponentCollectionSort.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .accessibilityLabel("Component Sort")
                .accessibilityIdentifier("components.sort")
                if state.isComponentDependencyIndexing {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Updating component dependencies")
                }
            }
            Text("\(state.filteredComponentDefinitions.count) of \(state.componentDefinitions.count) component definitions")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("components.search.status")
            if state.componentDefinitions.isEmpty {
                Text(state.componentCreationUnavailableReason ?? "Create a named reusable component from the selected container.")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("components.empty.guidance")
                if !state.canCreateComponent {
                    Button("Insert Frame to Start") { state.performDefaultInsertion(.frame, provenance: .menu) }
                        .disabled(state.editingComponentID != nil || !state.insertionAvailability(.frame).isEnabled)
                        .accessibilityIdentifier("components.empty.insertFrame")
                }
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                        if state.filteredComponentDefinitions.isEmpty && !state.componentDefinitions.isEmpty {
                            ContentUnavailableView.search(text: state.componentSearchText)
                                .accessibilityIdentifier("components.search.empty")
                        }
                        ForEach(state.filteredComponentDefinitions) { definition in
                            componentDefinitionRow(definition)
                        }
                    }
                }
                .onAppear {
                    if let id = state.highlightedComponentDefinitionID { scroll.scrollTo(id, anchor: .center) }
                }
                .onChange(of: state.highlightedComponentDefinitionID) { _, id in
                    if let id { scroll.scrollTo(id, anchor: .center) }
                }
            }
            if let instance = state.selectedComponent {
                Text("Linked copy · uses the original appearance")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                if let id = CanonicalComponentReference.definitionID(for: instance),
                   state.componentDefinitions.contains(where: { $0.id == id }) {
                    Button(AuthoringLanguage.editOriginalComponent) { state.editComponentDefinition(id) }
                        .accessibilityIdentifier("components.edit.selected")
                    Button("Make independent", action: state.detachComponent)
                        .disabled(!state.pageEditingIsAvailable)
                        .accessibilityIdentifier("components.detach")
                } else {
                    Text("Original component unavailable. Recover it with Undo or the original saved project; this copy keeps its identity, placement and custom values.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !state.componentAnnouncement.isEmpty {
                ComponentFeedbackText(announcement: state.componentAnnouncement).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("components.status")
            }
        }
        .confirmationDialog("Delete component? Linked uses will become independent objects.",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let id = deleting {
                    Button(state.componentUsageCount(id) == 0 ? "Delete Component" : "Detach Uses and Delete", role: .destructive) {
                        state.deleteComponent(id, detachUses: true); deleting = nil
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
                    .accessibilityIdentifier("components.delete.cancel")
            }
        .sheet(item: $renaming) { request in
            ComponentRenameView(state: state, request: request) { renaming = nil }
        }
        .sheet(item: $creating) { request in
            ComponentCreationView(state: state, request: request) { creating = nil }
        }
        .sheet(item: $inspecting) { request in
            ComponentDependencyInspectorView(state: state, definitionID: request.id) { inspecting = nil }
        }
        .onAppear { state.refreshComponentDependencies() }
    }

    private func componentDefinitionRow(_ definition: DocumentPage) -> some View {
        let dependency = state.componentDependencyEntry(definition.id)
        let usageCount = dependency?.usages.count ?? state.componentUsageCount(definition.id)
        let isRevealed = state.highlightedComponentDefinitionID == definition.id
        let editingIsDisabled = state.editingComponentID != nil || !state.pageEditingIsAvailable
        return VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Text(definition.name)
                .fontWeight(.semibold)
                .lineLimit(1)
                .help(definition.name)
                .accessibilityLabel(definition.name)
                .accessibilityValue("\(usageCount) linked instances" + (isRevealed ? "; Revealed definition" : ""))
                .accessibilityIdentifier("components.definition." + definition.id.description)
            Text("\(usageCount) linked instances").font(.caption)
            if isRevealed {
                Text("Revealed in Components")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("components.definition.revealed." + definition.id.description)
            }
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                HStack {
                    Button("Insert") { state.insertComponent(definition.id) }
                        .disabled(editingIsDisabled)
                        .accessibilityIdentifier("components.insert." + definition.id.description)
                    Button("Edit") { state.editComponentDefinition(definition.id) }
                        .disabled(state.editingComponentID != nil)
                        .accessibilityIdentifier("components.edit." + definition.id.description)
                    Button("Details…") { inspecting = .init(id: definition.id) }
                        .accessibilityIdentifier("components.details." + definition.id.description)
                }
                HStack {
                    Button("Rename…") {
                        guard state.prepareForWorkspaceAction(.context) else { return }
                        renaming = .init(id: definition.id, name: definition.name, context: state.responsiveInspectorEditContext)
                    }
                        .disabled(editingIsDisabled)
                        .accessibilityIdentifier("components.rename." + definition.id.description)
                    Button("Delete", role: .destructive) { deleting = definition.id }
                        .disabled(editingIsDisabled)
                        .accessibilityIdentifier("components.delete." + definition.id.description)
                }
            }
            if let dependency, !dependency.issues.isEmpty {
                Label("Dependency issue", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("components.issue." + definition.id.description)
            }
        }
        .accessibilityElement(children: .contain)
        .padding(SiteForgeVisualSystem.rowInset)
        .modifier(SiteForgeRowSurface(selected: isRevealed))
        .id(definition.id)
    }
}

private struct ComponentDependencyRequest: Identifiable {
    let id: PageID
}

private struct ComponentCreationRequest: Identifiable {
    let id = UUID()
    let nodeID: NodeID
    let name: String
    let identity: DesignInspectorOperationIdentity
}

private struct ComponentCreationView: View {
    @ObservedObject var state: WorkspaceShellState
    let request: ComponentCreationRequest
    let dismiss: () -> Void
    @State private var name: String
    @State private var message = ""
    init(state: WorkspaceShellState, request: ComponentCreationRequest, dismiss: @escaping () -> Void) {
        self.state = state; self.request = request; self.dismiss = dismiss
        _name = State(initialValue: request.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Create Component").font(.title2)
            Text("The selected container becomes the first linked instance. Definition edits update inherited values; instance overrides stay independent.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            TextField("Component name", text: $name)
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .accessibilityIdentifier("components.create.name").onSubmit(apply)
            if !message.isEmpty { Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("components.create.validation") }
            HStack {
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("components.create.cancel")
                Spacer()
                Button("Create", action: apply).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("components.create.apply")
            }
        }.padding(SiteForgeVisualSystem.sectionSpacing).frame(width: 400)
            .onExitCommand(perform: dismiss)
    }
    private func apply() {
        if state.createComponent(named: name, nodeID: request.nodeID, identity: request.identity) { dismiss() }
        else { message = state.componentAnnouncement }
    }
}

private struct ComponentDependencyInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    let definitionID: PageID
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            HStack {
                Label("Component Details", systemImage: "square.stack.3d.up")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
            }
            if let entry = state.componentDependencyEntry(definitionID) {
                Text(entry.name).font(.headline).lineLimit(1).help(entry.name)
                List {
                    Section("Where Used · \(entry.usages.count)") {
                        if entry.usages.isEmpty {
                            Text("No linked instances. This definition can be removed when its dependency graph is valid.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(entry.usages) { usage in
                                Button {
                                    state.revealComponentUsage(usage); dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(usage.locationLabel).lineLimit(1)
                                            Text(usage.isHidden ? "Hidden instance · inspect in Layers" : "Visible linked instance")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(); Image(systemName: "arrow.right.circle")
                                    }
                                    // The entire visible usage row is its
                                    // button, including the space before the arrow.
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open usage in \(usage.locationLabel)")
                                .accessibilityValue(usage.isHidden ? "Hidden; opens Layers without a canvas ghost" : "Visible")
                                .accessibilityIdentifier("components.usage." + usage.nodeID.description)
                            }
                        }
                    }
                    Section("Dependencies") {
                        dependencyRow("Component definitions", entry.directDefinitionIDs.count)
                        dependencyRow("Image assets", entry.assetIDs.count)
                        dependencyRow("Color tokens", entry.tokenIDs.count)
                        dependencyRow("Reusable styles", entry.styleIDs.count)
                        dependencyRow("Exposed text properties", entry.textProperties.count)
                        dependencyRow("Exposed visibility properties", entry.visibilityProperties.count)
                        dependencyRow("Exposed choice properties", entry.choiceProperties.count)
                        dependencyRow("Exposed media properties", entry.mediaProperties.count)
                        dependencyRow("Exposed action properties", entry.actionProperties.count)
                        dependencyRow("Named default contents", entry.slotProperties.count)
                        dependencyRow("Organized properties", entry.propertyOrganization.filter { $0.group != nil || $0.rank != nil }.count)
                        ForEach(entry.propertyOrganization) { property in
                            LabeledContent(property.label, value: property.group ?? "Ungrouped")
                                .accessibilityValue((property.group ?? "Ungrouped") + "; " + (property.rank == nil ? "default order" : "authored order"))
                        }
                        dependencyRow("Action destination pages", entry.actionPageIDs.count)
                        ForEach(entry.actionPageIDs, id: \.self) { destinationID in
                            LabeledContent("Action destination", value: state.documentSession.document.pages.first {
                                $0.id == destinationID
                            }?.name ?? "Missing destination · intent retained")
                            .accessibilityIdentifier("components.actionDestination.\(destinationID)")
                        }
                        dependencyRow("Custom values on copies", entry.authoredOverrideCount)
                        dependencyRow("Values needing attention", entry.overrideConflictCount)
                        ForEach(entry.overrideConflicts) { conflict in
                            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                                Label(AuthoringLanguage.componentValueName(kind: conflict.property.organizationKind) + " · custom value needs attention",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("components.conflict." + conflict.id)
                                Text(conflict.reason.explanation).font(.caption)
                                if let usage = entry.usages.first(where: { $0.nodeID == conflict.instanceID }) {
                                    Button("Inspect custom value") {
                                        state.revealComponentUsage(usage); _ = state.selectInspectorTab(.content); dismiss()
                                    }.accessibilityIdentifier("components.conflict.reveal." + conflict.id)
                                }
                            }
                        }
                        if entry.issues.isEmpty {
                            Label("Component links are valid", systemImage: "checkmark.circle")
                        } else {
                            ForEach(entry.issues, id: \.rawValue) { issue in
                                Label(issue.presentation, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Compatibility") {
                        Text(entry.transferStatus)
                        Text("Static output: use Build Diagnostics for the current project revision.")
                            .foregroundStyle(.secondary)
                        Text("Replace Definition is unavailable in this bounded model because compatible replacement semantics are not yet specified.")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if entry.canRemoveWithoutDetach {
                        Button("Remove Unused Component", role: .destructive) {
                            state.removeUnusedComponent(definitionID); dismiss()
                        }
                        .accessibilityIdentifier("components.maintenance.remove")
                    } else if entry.canDetachUses {
                        Button("Detach Uses and Delete", role: .destructive) {
                            state.detachUsesAndDeleteComponent(definitionID); dismiss()
                        }
                        .accessibilityIdentifier("components.maintenance.detachDelete")
                    } else {
                        Text("Removal unavailable until usages and dependency issues are resolved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { state.refreshComponentDependencies() }
                        .accessibilityIdentifier("components.dependencies.refresh")
                }
            } else if state.isComponentDependencyIndexing {
                ProgressView("Inspecting component dependencies…")
            } else {
                ContentUnavailableView(
                    "Component Details Unavailable", systemImage: "exclamationmark.triangle",
                    description: Text("The project changed or the definition is unavailable. Refresh and reopen Details.")
                )
                Button("Refresh", action: state.refreshComponentDependencies)
            }
        }
        .padding(SiteForgeVisualSystem.panePadding)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("components.dependencies")
    }

    private func dependencyRow(_ title: String, _ count: Int) -> some View {
        HStack { Text(title); Spacer(); Text(String(count)).foregroundStyle(.secondary) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(count)")
    }
}

private struct ComponentRenameRequest: Identifiable {
    let id: PageID
    let name: String
    let context: ResponsiveInspectorEditContext
}

private struct ComponentRenameView: View {
    @ObservedObject var state: WorkspaceShellState
    let request: ComponentRenameRequest
    let dismiss: () -> Void
    @State private var name: String
    @State private var message = ""
    @FocusState private var focused: Bool

    init(state: WorkspaceShellState, request: ComponentRenameRequest, dismiss: @escaping () -> Void) {
        self.state = state
        self.request = request
        self.dismiss = dismiss
        _name = State(initialValue: request.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Rename Component").font(.headline)
            TextField("Component name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focusedValue(\.siteforgeNativeTextEditor, focused ? true : nil)
                .focused($focused)
                .accessibilityIdentifier("components.rename.name")
                .onSubmit(performRename)
            Text("Linked instances keep their stable identity and update to the new definition name.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                    .accessibilityIdentifier("components.rename.validation")
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Rename", action: performRename).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("components.rename.apply")
            }
        }
        .padding(SiteForgeVisualSystem.settingsFormPadding).frame(width: 360)
        .onAppear { focused = true }
    }

    private func performRename() {
        if state.renameComponent(request.id, to: name, expectedContext: request.context) { close() }
        else { message = state.componentAnnouncement }
    }

    private func close() {
        // End this sheet's native edit context at the user-event boundary.
        // A detached focused field must not keep main-window Undo in text mode.
        focused = false
        dismiss()
    }
}

private struct AssetsNavigatorView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var editingAsset: ImageAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                Text("Images").font(.headline)
                Button("Import Images…", systemImage: "plus") { state.importImages() }
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .help("Import Images…")
                    .accessibilityLabel("Import Images")
                    .accessibilityIdentifier("assets.import")
            }
            TextField("Search Images", text: $state.assetSearchText)
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .accessibilityIdentifier("assets.search")
            Toggle("Favorites", isOn: $state.assetFavoritesOnly)
                .accessibilityIdentifier("assets.filter.favorites")
            Picker("Usage", selection: Binding(
                get: { state.assetUsageFilter },
                set: { filter in
                    // Segmented Picker writes while SwiftUI is reconciling
                    // the filtered rows. Apply the scene-local filter after
                    // that update turn; a newer choice naturally wins.
                    Task { @MainActor in
                        await Task.yield()
                        state.assetUsageFilter = filter
                    }
                }
            )) {
                ForEach(AssetUsageFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                        .accessibilityIdentifier("assets.filter.usage.\(filter.rawValue)")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("assets.filter.usage")
            HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                Picker("Folder", selection: $state.assetFolderFilter) {
                    Text("All folders").tag(String?.none)
                    ForEach(state.imageAssetFolders, id: \.self) { folder in
                        Text(folder).tag(Optional(folder))
                    }
                }
                .accessibilityIdentifier("assets.filter.folder")
                Picker("Tag", selection: $state.assetTagFilter) {
                    Text("All tags").tag(String?.none)
                    ForEach(state.imageAssetTags, id: \.self) { tag in
                        Text(tag).tag(Optional(tag))
                    }
                }
                .accessibilityIdentifier("assets.filter.tag")
            }

            if state.imageAssets.isEmpty {
                ContentUnavailableView {
                    Label(state.documentSession.document.imageAssets.isEmpty ? "No Images" : "No Matching Images",
                          systemImage: "photo.on.rectangle.angled")
                        .accessibilityIdentifier("assets.empty")
                } description: {
                    Text(state.documentSession.document.imageAssets.isEmpty
                         ? "Import local PNG, JPEG, GIF, TIFF, or HEIC images. Originals stay inside this project."
                         : "No image matches the current search or filters.")
                } actions: {
                    if state.documentSession.document.imageAssets.isEmpty {
                        Button("Import Images…") { state.importImages() }
                            .accessibilityIdentifier("assets.empty.import")
                    } else {
                        Button("Clear Search and Filters") { state.clearImageAssetFilters() }
                            .accessibilityIdentifier("assets.empty.clearFilters")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                            ForEach(state.imageAssets) { asset in
                                AssetRow(asset: asset, state: state) {
                                    state.selectedAssetID = asset.id
                                    editingAsset = asset
                                }
                                .id(asset.id)
                            }
                        }
                    }
                    .onAppear {
                        if let id = state.selectedAssetID { scroll.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: state.selectedAssetID) { _, id in
                        guard let id else { return }
                        // Selection publishes while SwiftUI is reconciling the
                        // asset rows. Move the presentation-only scroll to the
                        // next main-actor turn and reject a stale selection
                        // rather than mutating ScrollViewReader during update.
                        Task { @MainActor in
                            await Task.yield()
                            guard state.selectedAssetID == id else { return }
                            scroll.scrollTo(id, anchor: .center)
                        }
                    }
                    .accessibilityLabel("Imported image assets")
                    .accessibilityIdentifier("assets.list")
                }
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
            if let selected = state.documentSession.document.imageAssets.first(where: { $0.id == state.selectedAssetID }) {
                Button("Organize Selected Image…") { editingAsset = selected }
                    .accessibilityIdentifier("assets.organize.selected")
            }
        }
        .sheet(item: $editingAsset) { asset in
            AssetOrganizationEditor(asset: asset, state: state,
                identity: state.assetOrganizationEditIdentity(asset.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assets")
        .accessibilityIdentifier("navigator.assets.library")
    }
}

private struct AssetRow: View {
    let asset: ImageAsset
    @ObservedObject var state: WorkspaceShellState
    let onOrganize: () -> Void
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
        .accessibilityValue("\(asset.originalFilename), \(asset.pixelWidth) by \(asset.pixelHeight) pixels, \(asset.format.rawValue), \(state.imageAssetUsageCount(asset.id)) uses, \(asset.organization?.favorite == true ? "favorite" : "not favorite"), folder \(asset.organization?.folderPath ?? "none"), tags \(asset.organization?.tags.joined(separator: ", ") ?? "none")")
        .accessibilityIdentifier("assets.row.\(asset.id.description)")
        .contextMenu {
            Button("Insert Image") { state.selectedAssetID = asset.id; state.insertSelectedImage() }
            Button("Rename") {
                nameDraft = asset.displayName
                isRenaming = true
                DispatchQueue.main.async { renameFocused = true }
            }
            Button("Organize…", action: onOrganize)
            Button("Replace Asset Everywhere…") { state.replaceImageAsset(asset.id) }
            Button("Reveal Usage") { state.revealImageUsage(asset.id) }
            Divider()
            Button("Delete…", role: .destructive) { state.requestDeleteImageAsset(asset.id) }
        }
    }

    private var rowContent: some View {
        HStack(spacing: SiteForgeVisualSystem.controlInset) {
            Group {
                if let data = state.imageAssetThumbnail(asset.id), let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
            }
            .frame(width: SiteForgeVisualSystem.thumbnailSize, height: SiteForgeVisualSystem.thumbnailSize)
            .background(SiteForgeVisualSystem.fieldSurface,
                        in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.rowCornerRadius))
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.hairlineSpacing) {
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
                if let organization = asset.organization {
                    Text(([organization.folderPath].compactMap { $0 } + organization.tags).joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 2)
            if asset.organization?.favorite == true { Image(systemName: "star.fill").accessibilityHidden(true) }
            if state.selectedAssetID == asset.id { Image(systemName: "checkmark.circle.fill") }
        }
        .padding(SiteForgeVisualSystem.rowInset).contentShape(Rectangle())
        .modifier(SiteForgeRowSurface(selected: state.selectedAssetID == asset.id))
    }

    private func commitRename() {
        state.renameImageAsset(asset.id, to: nameDraft)
        isRenaming = false
    }
}

private struct AssetOrganizationEditor: View {
    let asset: ImageAsset
    @ObservedObject var state: WorkspaceShellState
    let identity: AssetOrganizationEditIdentity
    @Environment(\.dismiss) private var dismiss
    @State private var folder: String
    @State private var tags: String
    @State private var favorite: Bool
    @State private var validation = ""

    init(asset: ImageAsset, state: WorkspaceShellState, identity: AssetOrganizationEditIdentity) {
        self.asset = asset
        self.state = state
        self.identity = identity
        _folder = State(initialValue: asset.organization?.folderPath ?? "")
        _tags = State(initialValue: asset.organization?.tags.joined(separator: ", ") ?? "")
        _favorite = State(initialValue: asset.organization?.favorite ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Organize Image").font(.headline)
            Text(asset.displayName).lineLimit(1).foregroundStyle(.secondary)
            TextField("Project folder", text: $folder)
                .accessibilityIdentifier("assets.organization.folder")
            TextField("Tags (comma-separated)", text: $tags)
                .accessibilityIdentifier("assets.organization.tags")
            Toggle("Favorite", isOn: $favorite)
                .accessibilityIdentifier("assets.organization.favorite")
            if !validation.isEmpty {
                Text(validation).foregroundStyle(SiteForgeVisualSystem.danger)
                    .accessibilityIdentifier("assets.organization.validation")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Organization") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("assets.organization.save")
            }
        }
        .padding(SiteForgeVisualSystem.settingsFormPadding)
        .frame(minWidth: 300, idealWidth: 360)
        .onExitCommand { dismiss() }
    }

    private func commit() {
        let parsedTags = tags.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let requestedTags = tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : parsedTags
        do {
            _ = try AssetOrganization(folderPath: folder, tags: requestedTags, favorite: favorite)
        } catch {
            validation = AssetOrganizationEditError.invalid.message
            return
        }
        state.organizeImageAsset(asset.id, folder: folder, tags: requestedTags,
                                 favorite: favorite, expected: identity)
        dismiss()
    }
}

private struct ElementsCatalogView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var searchText = ""

    private var results: [ElementCatalogItem] {
        ElementCatalogSearchPolicy.results(in: ElementCatalogItem.allCases, query: searchText)
    }

    var body: some View {
        VStack(spacing: SiteForgeVisualSystem.controlInset) {
            HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                TextField("Search Elements", text: $searchText)
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityLabel("Search elements by name or category")
                    .accessibilityIdentifier("navigator.elements.search")
                    .onExitCommand { searchText = "" }
                if !searchText.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { searchText = "" }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("navigator.elements.search.clear")
                }
            }
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "\(results.count) elements"
                 : "\(results.count) of \(ElementCatalogItem.allCases.count) elements match")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("navigator.elements.search.status")
            ScrollView {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .accessibilityIdentifier("navigator.elements.search.empty")
                    }
                    ForEach(["Layout", "Basic", "Site", "Forms"], id: \.self) { category in
                        if results.contains(where: { $0.category == category }) {
                            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                                Text(category).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(results.filter { $0.category == category }) { item in
                                    ElementCatalogRow(item: item, state: state)
                                }
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
}

private struct ElementCatalogRow: View {
    let item: ElementCatalogItem
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        let availability = item.availability
        let fieldTemplate = item.template.flatMap { $0.formFieldKind == nil ? nil : $0 }
        let fieldAvailability = fieldTemplate.map {
            state.insertionAvailability(.text, template: $0)
        }
        Button {
            guard case .available(let tool) = availability else { return }
            if fieldTemplate != nil, fieldAvailability?.isEnabled != true { return }
            if let template = item.template {
                state.performDefaultInsertion(template.insertionKind,
                    provenance: .accessibility, template: template)
                return
            }
            // Structural catalogue rows have a useful non-pointer equivalent:
            // they commit one validated default insertion. Frame/Text retain
            // their established tool-arming workflow for canvas placement.
            if let kind = item.insertionKind, [.section, .stack, .grid, .button, .link, .form].contains(kind) {
                state.performDefaultInsertion(kind, provenance: .accessibility)
            } else {
                state.selectTool(tool)
            }
        } label: {
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                Image(systemName: item.systemImage).frame(width: 16)
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.hairlineSpacing) {
                    Text(item.title)
                    if item.keyboardPath != "No shortcut" {
                        Text(item.keyboardPath).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .unavailable = availability {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, SiteForgeVisualSystem.controlInset).padding(.vertical, SiteForgeVisualSystem.compactSpacing).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled({
            if case .unavailable = availability { return true }
            return fieldTemplate != nil && fieldAvailability?.isEnabled != true
        }())
        .accessibilityIdentifier("navigator.elements.\(item.rawValue)")
        .accessibilityLabel(item.title)
        .accessibilityHint(fieldTemplate != nil && fieldAvailability?.isEnabled != true
            ? "Select an unlocked Form on the active page to insert this field."
            : item.accessibilityDescription)
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
        VStack(spacing: SiteForgeVisualSystem.hairlineSpacing) {
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
                HStack(spacing: SiteForgeVisualSystem.controlInset) {
                    Image(systemName: target.isLocked ? "lock.fill" : !target.isVisible ? "eye.slash.fill" : target.isStructuralRoot ? "rectangle.stack" : "square.dashed")
                        .frame(width: 16)
                    Text(target.name).lineLimit(1)
                    Spacer(minLength: 4)
                    if let description = target.layerVisibilityDescription {
                        Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if isPrimary { Text("Primary").font(.caption2).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, SiteForgeVisualSystem.controlInset)
                .padding(.vertical, SiteForgeVisualSystem.compactSpacing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(SiteForgeRowSurface(selected: isSelected))
            .focusable()
            .focused(focus, equals: .navigatorLayer(target.id))
            .onMoveCommand { direction in
                if direction == .down { state.performSelectionCommand(.next, provenance: .keyboard) }
                if direction == .up { state.performSelectionCommand(.previous, provenance: .keyboard) }
            }
            .accessibilityLabel(target.name)
            .accessibilityValue("\(target.isLocked ? "Locked; " : "")\(target.layerVisibilityDescription.map { $0 + "; " } ?? "")\(isPrimary ? "Primary selection" : isSelected ? "Selected" : "Not selected"); Parent: \(target.parentName ?? "Page")")
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
                NavigatorLayerContextMenu(target: target, state: state)
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

/// The native menu has its own hosting lifetime. Observe the live command state
/// inside that host rather than capturing a row's earlier selection/availability.
private struct NavigatorLayerContextMenu: View {
    let target: SelectionTargetSnapshot
    @ObservedObject var state: WorkspaceShellState

    private var isSelected: Bool { state.selectionState.orderedIDs.contains(target.id) }
    private func availability(nesting: Bool) -> DragDropAvailability? {
        guard let source = state.selectionState.primaryID,
              let destination = nesting ? state.dragDestination(nestingIn: target.id)
                : state.dragDestination(before: target.id) else { return nil }
        return state.dragDropAvailability(sourceID: source, destination: destination,
                                         provenance: .contextualMenu)
    }

    var body: some View {
        Button("Cut") {
            if !isSelected { state.selectLayer(target.id) }
            _ = state.cutSelection(provenance: .contextualMenu)
        }.disabled(target.isLocked)
        Button("Copy") {
            if !isSelected { state.selectLayer(target.id) }
            _ = state.copySelection(provenance: .contextualMenu)
        }
        Button("Duplicate") {
            if !isSelected { state.selectLayer(target.id) }
            _ = state.duplicateSelection(provenance: .contextualMenu)
        }.disabled(target.isLocked)
        Divider()
        Button("Move Before") {
            guard let destination = state.dragDestination(before: target.id),
                  let source = state.selectionState.primaryID else { return }
            state.performDragDrop(sourceID: source, destination: destination, provenance: .contextualMenu)
        }
        .disabled(availability(nesting: false)?.isEnabled != true)
        .accessibilityHint(availability(nesting: false)?.disabledReason ?? "Select an available layer to move.")
        Button("Nest In") {
            guard let destination = state.dragDestination(nestingIn: target.id),
                  let source = state.selectionState.primaryID else { return }
            state.performDragDrop(sourceID: source, destination: destination, provenance: .contextualMenu)
        }
        .disabled(availability(nesting: true)?.isEnabled != true)
        .accessibilityHint(availability(nesting: true)?.disabledReason ?? "Select an available layer to nest.")
        Button("Edit Text") { state.beginTextEditing(nodeID: target.id, provenance: .contextualMenu) }
            .disabled(!state.textEditingAvailability(nodeID: target.id).isEnabled)
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
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                Image(systemName: page.role == .home ? "house" : "doc")
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.hairlineSpacing) {
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
            .padding(.horizontal, SiteForgeVisualSystem.controlInset)
            .padding(.vertical, SiteForgeVisualSystem.compactSpacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SiteForgeRowSurface(selected: isSelected))
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
        .contextMenu {
            PageActionButtons(state: state, page: page)
                .disabled(!state.pageEditingIsAvailable)
        }
    }
}

struct PageEditorRequest: Identifiable {
    enum Mode { case create, rename, route, delete }
    let id = UUID()
    let identity: PageEditIdentity
    let mode: Mode
    let name: String
    let route: String
    let inboundLinks: Int
    let objects: Int
}

private struct PageChromeCopySheet: View {
    @ObservedObject var state: WorkspaceShellState
    let request: PageChromeCopySheetRequest
    @State private var roles: Set<PageFlowRole>
    @State private var targets = Set<PageID>()
    init(state: WorkspaceShellState, request: PageChromeCopySheetRequest) {
        self.state = state; self.request = request; _roles = State(initialValue: request.initialRoles)
    }
    private var stale: Bool { state.formattingActionCapture != request.capture }
    private var selected: [PageChromeCopyTarget] { request.targets.filter { targets.contains($0.id) } }
    private var missingCount: Int { selected.filter { $0.disabledReason == nil }.reduce(0) { $0 + roles.subtracting($1.existingRoles).count } }
    private var skippedCount: Int { selected.count * roles.count - missingCount }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Copy Header/Footer to Pages").font(.headline)
            Text("Source page: " + request.sourceName).lineLimit(1).help(request.sourceName)
                .accessibilityLabel("Source page").accessibilityValue(request.sourceName)
                .accessibilityIdentifier("page.chrome.copy.source")
            Text("Independent editable copies — later source edits do not propagate. Add missing roles only; existing chrome and its inbound links are always kept. No Merge or Replace is performed.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Existing token, style, asset and component links keep their normal shared project definitions.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach(PageChromeCopyRegistry.roles, id: \.rawValue) { role in
                    Toggle(role.rawValue.capitalized, isOn: Binding(get: { roles.contains(role) }, set: { enabled in
                        if enabled { roles.insert(role) } else { roles.remove(role) }
                    }))
                    .disabled(request.sourceRoles[role] == nil)
                    .help(request.sourceRoles[role] == nil ? "This source page has no \(role.rawValue)." : "Copy the complete editable \(role.rawValue) subtree.")
                    .accessibilityIdentifier("page.chrome.copy.role." + role.rawValue)
                }
            }.disabled(state.isPreparingPageChromeCopy || state.isAwaitingPageChromeCopyAdoption || stale)
            Text("Destination pages — nothing selected by default").font(.subheadline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(request.targets) { target in
                        VStack(alignment: .leading, spacing: 3) {
                            Toggle(target.name, isOn: Binding(get: { targets.contains(target.id) }, set: { enabled in
                                if enabled { targets.insert(target.id) } else { targets.remove(target.id) }
                            }))
                            .disabled(target.disabledReason != nil)
                            .accessibilityIdentifier("page.chrome.copy.target." + target.id.description)
                            Text(target.disabledReason ?? (target.existingRoles.isEmpty ? "No Header/Footer — missing roles can be added" : "Existing: " + PageChromeCopyRegistry.roles.filter(target.existingRoles.contains).map { $0.rawValue.capitalized }.joined(separator: ", ") + " (kept)"))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 100, maxHeight: 240)
                .disabled(state.isPreparingPageChromeCopy || state.isAwaitingPageChromeCopyAdoption || stale)
            Text("\(selected.count) selected pages; \(missingCount) missing roles to copy; \(skippedCount) existing/ineligible roles skipped.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("page.chrome.copy.summary")
            if stale && state.pageChromeCopiedTargets.isEmpty {
                Text(PageChromeCopyError.stale.localizedDescription).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if state.isPreparingPageChromeCopy || state.isAwaitingPageChromeCopyAdoption {
                ProgressView(state.isPreparingPageChromeCopy ? "Preparing copies…" : "Adopting committed copies…").controlSize(.small)
            }
            Text(state.pageChromeCopyStatus).font(.callout).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Chrome copy status").accessibilityValue(state.pageChromeCopyStatus)
                .accessibilityIdentifier("page.chrome.copy.status")
            if !state.isAwaitingPageChromeCopyAdoption && !state.pageChromeCopiedTargets.isEmpty {
                Menu("Open copied page") {
                    ForEach(state.pageChromeCopiedTargets, id: \.self) { id in
                        if let page = state.pages.first(where: { $0.id == id }) {
                            Button(page.name) { state.pageChromeCopySheet = nil; state.selectPage(id) }
                        }
                    }
                }.accessibilityIdentifier("page.chrome.copy.openTarget")
            }
            HStack {
                Button(state.isPreparingPageChromeCopy ? "Cancel Preparation" : "Close") {
                    state.cancelPageChromeCopyPreparation(); state.pageChromeCopySheet = nil
                }.keyboardShortcut(.cancelAction).accessibilityIdentifier("page.chrome.copy.cancel")
                Spacer()
                Button("Copy Missing Roles") {
                    state.preparePageChromeCopy(sheet: request, roles: roles, targets: selected.map(\.id))
                }.keyboardShortcut(.defaultAction)
                    .disabled(stale || selected.isEmpty || missingCount == 0 || state.isPreparingPageChromeCopy || state.isAwaitingPageChromeCopyAdoption)
                    .accessibilityIdentifier("page.chrome.copy.commit")
            }
        }.padding().frame(minWidth: 440, idealWidth: 560, maxWidth: 640)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page.chrome.copy.sheet")
    }
}

private struct PageActionButtons: View {
    @ObservedObject var state: WorkspaceShellState
    let page: DocumentPage
    var body: some View {
        Button("Copy Header/Footer to Pages…") { state.presentPageChromeCopy() }
            .disabled(page.id != state.effectiveSelectedPageID || !state.canCopyPageChrome)
            .help(page.id != state.effectiveSelectedPageID ? "Open this page first to copy its Header/Footer."
                : state.canCopyPageChrome ? "Add missing Header/Footer to selected pages as independent editable content."
                : "Add a Header or Footer to this normal website page and wait for the current canvas.")
            .accessibilityIdentifier("page.chrome.copy.menu")
        Button("Site & Page Settings…") { state.presentWebsiteSettings() }
            .disabled(page.id != state.effectiveSelectedPageID || state.websiteSettingsIdentity == nil)
        Button("Page Background…") { state.revealPageBackground(pageID: page.id) }
            .disabled(page.id != state.effectiveSelectedPageID || state.pageBackgroundUnavailableReason != nil)
        Button("Rename Page…") { state.presentPageEditor(.rename, pageID: page.id) }
        Button("Edit Route…") { state.presentPageEditor(.route, pageID: page.id) }
            .disabled(page.role != .standard)
        Button("Duplicate Page") { state.performPageEdit(.duplicate, pageID: page.id) }
        let index = state.pages.firstIndex(where: { $0.id == page.id }) ?? 0
        Button("Move Page Earlier") { state.performPageEdit(.move(index - 1), pageID: page.id) }
            .disabled(index == 0)
        Button("Move Page Later") { state.performPageEdit(.move(index + 1), pageID: page.id) }
            .disabled(index + 1 >= state.pages.count)
        Button("Delete Page…", role: .destructive) { state.presentPageEditor(.delete, pageID: page.id) }
            .disabled(page.role != .standard || state.pages.count == 1)
    }
}

private struct PageEditorSheet: View {
    @ObservedObject var state: WorkspaceShellState
    let request: PageEditorRequest
    @State private var name = ""
    @State private var route = ""
    @State private var error = ""
    @State private var copyCurrentPage = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text(request.mode == .delete ? "Delete Page" : "Page Details").font(.headline)
            if request.mode == .delete {
                Text("Delete \(request.name) and \(request.objects) authored objects? \(request.inboundLinks) incoming links will retain missing targets for repair. Undo restores the page and its links.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if request.mode == .create {
                    Toggle("Copy current page content", isOn: $copyCurrentPage)
                        .accessibilityIdentifier("page.editor.copyCurrent")
                    Text("Creates independent content and page settings. Existing pages stay unchanged; Header and Footer are not live-linked.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                if request.mode != .route {
                    Text("Page name").font(.caption)
                    TextField("Page name", text: $name).accessibilityIdentifier("page.editor.name")
                        .focusedValue(\.siteforgeNativeTextEditor, true)
                }
                if request.mode != .rename {
                    Text("Route").font(.caption)
                    TextField("Route", text: $route).accessibilityIdentifier("page.editor.route")
                        .focusedValue(\.siteforgeNativeTextEditor, true)
                    Text("Static path, for example /about/team. Home and /404 are protected.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(SiteForgeVisualSystem.danger).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("page.editor.validation") }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.mode == .delete ? "Delete Page" : "Apply", role: request.mode == .delete ? .destructive : nil) {
                    let edit: PageEdit = switch request.mode {
                    case .create: copyCurrentPage ? .duplicateNamed(name: name, route: route) : .create(name: name, route: route)
                    case .rename: .rename(name)
                    case .route: .route(route)
                    case .delete: .delete
                    }
                    if state.commitPageEdit(edit, identity: request.identity) { dismiss() }
                    else { error = state.pageAnnouncement }
                }.keyboardShortcut(.defaultAction).accessibilityIdentifier("page.editor.apply")
            }
        }.padding(SiteForgeVisualSystem.settingsFormPadding).frame(width: 360)
            .onAppear { name = request.name; route = request.route; copyCurrentPage = false }
    }
}

private struct CanvasPlaceholderView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding
    let tabRouter: WorkspaceWindowTabRouter

    var body: some View {
        VStack(spacing: 0) {
            if let id = state.editingComponentID {
                HStack {
                    Text("Editing Component: \(state.componentDefinitions.first(where: { $0.id == id })?.name ?? "Unavailable")")
                        .lineLimit(1)
                    Spacer()
                    Button(state.componentReturnActionTitle, action: state.exitComponentDefinition)
                        .accessibilityIdentifier("components.exit")
                }
                .padding(SiteForgeVisualSystem.controlInset)
                .fixedSize(horizontal: false, vertical: true)
                .background(.bar)
                // Like the viewport controls, the edit breadcrumb must
                // composite above the native canvas's backing layers.
                .zIndex(1)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Component definition editing mode. Instance overrides are retained.")
                .accessibilityIdentifier("components.editing.context")
            }
            if state.isolationRootID != nil {
                HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                    Label("Isolated", systemImage: "scope")
                    ForEach(state.isolationBreadcrumb) { node in
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        Text(node.name).lineLimit(1)
                    }
                    Spacer()
                    Button("Exit Isolation") { state.exitIsolation() }
                        .accessibilityIdentifier("canvas.isolation.exit")
                    Button("Exit All") { state.exitIsolation(all: true) }
                        .accessibilityIdentifier("canvas.isolation.exitAll")
                }
                .padding(.horizontal, 10).padding(.vertical, SiteForgeVisualSystem.compactSpacing)
                .background(.bar).zIndex(1)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.isolation.breadcrumb")
            }
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
                            Button("Isolate Selection") {
                                _ = state.enterIsolation(provenance: .contextualMenu)
                            }
                            .disabled(!state.canIsolateSelection)
                            Button("Exit Isolation") { state.exitIsolation() }
                                .disabled(state.isolationRootID == nil)
                            Button("Exit All Isolation") { state.exitIsolation(all: true) }
                                .disabled(state.isolationRootID == nil)
                            Divider()
                            Button("Paste") {
                                _ = state.pasteSiteForgeObjects(provenance: .contextualMenu)
                            }
                            .disabled(!state.canPasteSiteForgeObjects)
                            Button("Paste in Place") {
                                _ = state.pasteSiteForgeObjects(placement: .inPlace, provenance: .contextualMenu)
                            }
                            .disabled(!state.canPasteSiteForgeObjects)
                            Divider()
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

                    if state.canvasRenderPlan != nil && state.isCurrentPageGenuinelyEmpty && state.selectedTool == .select {
                        VStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                            Text("Your canvas is empty").font(.headline)
                            Text("Add an element to start shaping this page.")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Button("Insert Frame") { state.performDefaultInsertion(.frame, provenance: .pointer) }
                                    .disabled(!state.insertionAvailability(.frame).isEnabled)
                                    .accessibilityIdentifier("canvas.empty.insert.frame")
                                Button("Insert Text") { state.performDefaultInsertion(.text, provenance: .pointer) }
                                    .disabled(!state.insertionAvailability(.text).isEnabled)
                                    .accessibilityIdentifier("canvas.empty.insert.text")
                            }
                        }
                        .padding(SiteForgeVisualSystem.controlInset)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: min(geometry.size.width, SiteForgeVisualSystem.emptyHintMaximumWidth))
                        .background(Color(nsColor: .windowBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("canvas.empty.hint")
                        .zIndex(1)
                    }
                    if state.canvasRenderPlan == nil {
                        ProgressView("Preparing canvas…")
                            .controlSize(.small)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(SiteForgeVisualSystem.canvasPasteboard)
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
    @State private var widthDraft: String?
    @State private var widthDraftContext: ResponsiveInspectorEditContext?
    @State private var widthDraftID = UUID()
    @State private var widthValidation: String?
    @State private var committingWidth = false

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
            AdaptiveViewportControlsLayout(
                horizontalSpacing: SiteForgeVisualSystem.standardSpacing,
                verticalSpacing: SiteForgeVisualSystem.microSpacing
            ) {
                // Native small controls can settle to a smaller intrinsic
                // height after their first focus transition. Reserve the
                // shared compact target, not that transient measurement, so
                // Inspector focus does not resize/recenter the canvas.
                primaryControls.frame(minHeight: SiteForgeVisualSystem.compactControlHeight)
                zoomControls.frame(minHeight: SiteForgeVisualSystem.compactControlHeight)
            }
            if let widthValidation {
                Text(widthValidation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("canvas.viewport.width.validation")
            }
            if state.selectionOutsideActiveArtboard {
                HStack(spacing: SiteForgeVisualSystem.controlInset) {
                    Spacer(minLength: 4)
                    Button("Reveal Selection", systemImage: "viewfinder") { state.revealSelection() }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.bordered)
                        .fixedSize()
                        .help("Reveal the selected Desktop geometry without moving it")
                        .accessibilityLabel("Reveal Selection")
                        .accessibilityIdentifier("canvas.selection.reveal")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.viewport.contextControls")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, SiteForgeVisualSystem.panePadding)
        .padding(.vertical, SiteForgeVisualSystem.microSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceChrome(.viewportControls)
        .sheet(isPresented: $state.isResponsiveComparisonPresented) {
            ResponsiveBreakpointComparisonView(state: state)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.viewport.controls")
        .onChange(of: focus.wrappedValue) { old, current in
            guard old == .viewportWidth, current != .viewportWidth, let expected = widthDraftContext,
                  let text = widthDraft else { return }
            let draftID = widthDraftID
            // Native focus reconciliation must finish before publishing a new
            // viewport. A replaced draft/context cannot replay this blur.
            Task { @MainActor in
                await Task.yield()
                guard widthDraftID == draftID, widthDraft == text, widthDraftContext == expected else { return }
                commitWidthDraft()
            }
        }
        .onReceive(state.editCommitRequests) { request in
            guard widthDraft != nil, !committingWidth else { return }
            request.reject()
            widthValidation = "Finish viewport Width with Return, or Escape to restore the current width."
        }
        .onChange(of: state.layoutInspectorViewIdentity) { _, _ in
            widthDraftID = UUID(); widthDraft = nil; widthDraftContext = nil; widthValidation = nil
        }
    }

    private var primaryControls: some View {
        AdaptiveViewportControlsLayout(horizontalSpacing: SiteForgeVisualSystem.controlInset,
            verticalSpacing: SiteForgeVisualSystem.microSpacing) {
        HStack(spacing: SiteForgeVisualSystem.controlInset) {
            Label(AuthoringLanguage.screenSize, systemImage: "display")
                .font(.caption.weight(.semibold))
                .fixedSize()
                .accessibilityHint(AuthoringLanguage.screenSizeHelp)
                .help(AuthoringLanguage.screenSizeHelp)

            NativeViewportPresetControl(
                selection: Binding(get: { state.viewportPreset }, set: { value in
                    state.viewportPreset = value
                }),
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

            HStack(spacing: 3) {
                Text("Width").font(.caption).fixedSize()
                TextField("CSS px", text: Binding(get: {
                    widthDraft ?? GeometryInspectorNumberParser.format(state.viewportLayoutWidth)
                }, set: { value in
                    // AppKit may echo the formatted committed value after
                    // Return. That echo must not create another pending draft.
                    if widthDraft == nil,
                       value == GeometryInspectorNumberParser.format(state.viewportLayoutWidth) { return }
                    if widthDraftContext == nil {
                        widthDraftID = UUID(); widthDraftContext = state.responsiveInspectorEditContext
                    }
                    widthDraft = value
                    widthValidation = nil
                }))
                .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 96)
                .focused(focus, equals: .viewportWidth)
                .focusedValue(\.siteforgeNativeTextEditor, focus.wrappedValue == .viewportWidth)
                .onSubmit { commitWidthDraft() }
                .onExitCommand { cancelWidthDraft() }
                .accessibilityLabel("Viewport width in CSS pixels")
                .accessibilityValue(InspectorDraftAccessibility.value(draft: widthDraft,
                    committed: GeometryInspectorNumberParser.format(state.viewportLayoutWidth))
                    + "; \(state.viewportPreset.title) screen size")
                .help("Scene-local CSS width, independent of zoom/display scale. Mobile below 600; Tablet below 1024; Desktop from 1024. Return or valid focus loss commits; Escape restores. " + state.viewportWidthStatus)
                .accessibilityIdentifier("canvas.viewport.width")
                Text("px").font(.caption).foregroundStyle(.secondary).fixedSize()
            }
        }
        HStack(spacing: SiteForgeVisualSystem.controlInset) {

            Button("Compare") { state.showResponsiveComparison() }
                .buttonStyle(.bordered)
                .fixedSize()
                .focusable()
                .focused(focus, equals: .viewportCompare)
                .help("Compare Desktop, Tablet, and Mobile resolved layout without changing the document")
                .accessibilityLabel("Compare screen sizes")
                .accessibilityIdentifier("canvas.viewport.compare")

            Toggle("Grid", isOn: $state.isWorldGridVisible)
                .toggleStyle(.button)
                .fixedSize()
                .focusable()
                .focused(focus, equals: .viewportGrid)
                .accessibilityIdentifier("canvas.grid.toggle")
                .accessibilityLabel("World grid")
        }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.viewport.primaryControls")
    }

    private func commitWidthDraft() {
        guard let text = widthDraft, let context = widthDraftContext else { return }
        committingWidth = true
        defer { committingWidth = false }
        if state.commitViewportWidthDraft(text, expectedContext: context) {
            widthDraft = nil; widthDraftContext = nil; widthValidation = nil
            state.clearWorkspaceActionNotice()
        } else { widthValidation = state.viewportWidthStatus }
    }

    private func cancelWidthDraft() {
        widthDraftID = UUID()
        widthDraft = nil; widthDraftContext = nil; widthValidation = nil
        state.clearWorkspaceActionNotice()
    }

    private var zoomControls: some View {
        HStack(spacing: SiteForgeVisualSystem.controlInset) {
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

            Button("1:1") { state.performViewportCommand(CanvasViewportCommand(.actualSize)) }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Actual Size")
                .accessibilityLabel("Actual Size")
                .focusable()
                .focused(focus, equals: .viewportReset)
                .accessibilityIdentifier("canvas.zoom.reset")

            Button("Fit Canvas") { state.performViewportCommand(CanvasViewportCommand(.fitWidth)) }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Fit to Canvas")
                .accessibilityLabel("Fit to Canvas")
                .focusable()
                .focused(focus, equals: .viewportFitCanvas)
                .accessibilityIdentifier("canvas.zoom.fitCanvas")

            Button("Fit Document") { state.performViewportCommand(CanvasViewportCommand(.fitDocument)) }
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
    }
}

/// Measures one stable set of native controls and chooses a row or two rows
/// without constructing competing SwiftUI branches. This preserves AppKit
/// first-responder identity while the user tabs through the header.
private struct AdaptiveViewportControlsLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.init(width: proposal.width, height: nil)) }
        guard sizes.count == 2 else { return .zero }
        let rowWidth = sizes[0].width + horizontalSpacing + sizes[1].width
        let availableWidth = proposal.width ?? rowWidth
        if rowWidth <= availableWidth {
            return CGSize(width: min(rowWidth, availableWidth), height: max(sizes[0].height, sizes[1].height))
        }
        return CGSize(
            width: min(max(sizes[0].width, sizes[1].width), availableWidth),
            height: sizes[0].height + verticalSpacing + sizes[1].height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.init(width: bounds.width, height: nil)) }
        guard sizes.count == 2 else { return }
        let rowWidth = sizes[0].width + horizontalSpacing + sizes[1].width
        if rowWidth <= bounds.width {
            let y0 = bounds.minY + (bounds.height - sizes[0].height) / 2
            let y1 = bounds.minY + (bounds.height - sizes[1].height) / 2
            subviews[0].place(at: CGPoint(x: bounds.minX, y: y0), proposal: .init(sizes[0]))
            subviews[1].place(at: CGPoint(x: bounds.minX + sizes[0].width + horizontalSpacing, y: y1),
                              proposal: .init(sizes[1]))
        } else {
            subviews[0].place(at: bounds.origin, proposal: .init(sizes[0]))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + sizes[0].height + verticalSpacing),
                              proposal: .init(sizes[1]))
        }
    }
}

private struct ResponsiveBreakpointComparisonView: View {
    @ObservedObject var state: WorkspaceShellState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                    Text("Compare Screen Sizes").font(.title3.weight(.semibold))
                    Text(state.selectionState.isEmpty
                         ? "Reviewing all positioned objects on the active page."
                         : "Reviewing the current \(state.selectionState.count)-object selection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", action: state.refreshResponsiveComparison)
                    .accessibilityIdentifier("responsive.compare.refresh")
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("responsive.compare.done")
            }
            Divider()
            if state.isPreparingResponsiveComparison {
                HStack {
                    ProgressView("Resolving current width and reference samples…")
                        .accessibilityIdentifier("responsive.compare.preparing")
                    Button("Cancel", action: state.cancelResponsiveComparison)
                        .accessibilityIdentifier("responsive.compare.cancel")
                }
            }
            Text(state.responsiveComparisonStatus).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Responsive comparison status")
                .accessibilityValue(state.responsiveComparisonStatus)
                .accessibilityIdentifier("responsive.compare.status")
            if !state.responsiveLayoutReviewStatus.isEmpty {
                Text(state.responsiveLayoutReviewStatus).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("responsive.compare.reviewStatus")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    ForEach(state.responsiveBreakpointReviews) { review in
                        responsiveReviewCard(review)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("responsive.compare.results")
            Text("Review only; content is unchanged. Counts show custom values, not visual errors; 0 means none in this scope. Boundary checks exclude linked component internals, fixed/sticky content and managed navigation.")
                .help(AuthoringLanguage.reviewCountsHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("responsive.compare.scope")
        }
        .padding(SiteForgeVisualSystem.cardPadding)
        .frame(width: 560, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("responsive.compare.sheet")
    }

    private func responsiveReviewCard(_ review: ResponsiveBreakpointReview) -> some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            HStack {
                Label(review.title, systemImage: review.breakpoint == .desktop ? "desktopcomputer" : "ipad.and.iphone")
                    .font(.headline)
                    .accessibilityLabel("\(review.title) responsive review")
                    .accessibilityValue(review.accessibilityValue)
                    .accessibilityIdentifier("responsive.compare.card.\(review.isCurrentWidthSample ? "current" : review.breakpoint.rawValue)")
                Text("\(number(review.viewportWidth)) px").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if review.isCurrentWidthSample || state.viewportLayoutWidth == review.viewportWidth {
                    Text("Current").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                } else {
                    Button("Review \(review.title)") { state.reviewBreakpoint(review.breakpoint) }
                        .accessibilityIdentifier("responsive.compare.review.\(review.breakpoint.rawValue)")
                }
            }
            Text(review.differenceSummary).font(.callout.weight(.medium))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SiteForgeVisualSystem.standardSpacing) { reviewFacts(review) }
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) { reviewFacts(review) }
            }
            if let name = review.primaryName, let geometry = review.primaryGeometry,
               let visible = review.primaryIsVisible, let provenance = review.primaryProvenance {
                Text("\(name) · \(visible ? "Visible" : "Hidden") · \(provenance)")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Text("X \(number(geometry.origin.x)) · Y \(number(geometry.origin.y)) · W \(number(geometry.size.width)) · H \(number(geometry.size.height))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let summary = review.primaryFluidSummary {
                Text(summary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text("Horizontal layout reviews · \(review.totalLayoutFindingCount)")
                .font(.callout.weight(.semibold))
            if review.totalLayoutFindingCount == 0 {
                Text("No crossed horizontal boundaries in this inspected scope. This does not check collisions, tap targets or glyph truncation.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(review.layoutFindings) { finding in
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                    Label("Review · " + state.responsiveFindingName(finding), systemImage: "ruler")
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.contextDescription).font(.caption.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Intent may be deliberate. " + finding.nextAction)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Review element") { state.reviewResponsiveLayoutFinding(finding) }
                        .accessibilityLabel("Review \(state.responsiveFindingName(finding)) at \(number(finding.id.width)) CSS pixels")
                        .help(finding.contextDescription + " " + finding.nextAction)
                        .accessibilityIdentifier("responsive.finding.\(finding.id.nodeID).\(finding.id.width).\(finding.id.isCurrentSample).\(finding.id.boundary.rawValue).\(finding.id.edge.rawValue)")
                }
                .padding(.vertical, SiteForgeVisualSystem.microSpacing)
            }
            if review.totalLayoutFindingCount > review.layoutFindings.count {
                Text("Showing first \(review.layoutFindings.count) of \(review.totalLayoutFindingCount) reviews. Select a smaller Layers scope, then refresh to inspect the remainder.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SiteForgeVisualSystem.panePadding)
        .background(SiteForgeVisualSystem.elevatedSurface, in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func reviewFacts(_ review: ResponsiveBreakpointReview) -> some View {
        Text("\(review.visibleCount)/\(review.objectCount) visible")
        Text(AuthoringLanguage.reviewCustomizationCount(review.geometryOverrideCount, name: "Custom size/position"))
        Text(AuthoringLanguage.reviewCustomizationCount(review.containerOverrideCount, name: "Custom layout"))
        Text(AuthoringLanguage.reviewCustomizationCount(review.visibilityOverrideCount, name: "Custom visibility"))
        Text("Smooth scaling: \(review.fluidValueCount) ranges")
    }

    private func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
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
    @Published private(set) var keyboardFocusIsVisible = false
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.window {
                let visible = event.type == .keyDown
                if self.keyboardFocusIsVisible != visible { self.keyboardFocusIsVisible = visible }
            }
            return event.type == .keyDown ? self.route(event) : event
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
            button.onFocusChange = { [weak self, weak button] isFocused in
                guard let self, let button, let window = button.window else { return }
                if !isFocused, let request = self.currentRequest {
                    self.gate.markRelinquished(request)
                }
                if !self.isAdoptingRequestedFocus {
                    // Do not reconcile SwiftUI while AppKit is transferring
                    // first responder to an Inspector field. A synchronous
                    // focus publication can interrupt that native transition.
                    let request = self.currentRequest
                    DispatchQueue.main.async { [weak self, weak button, weak window] in
                        guard let self, let button, let window,
                              button.window === window, self.currentRequest == request,
                              (window.firstResponder === button) == isFocused else { return }
                        self.onNativeFocusChange?(isFocused)
                    }
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
            let adopted = selection?.wrappedValue ?? preset
            sender.selectItem(at: ViewportPresetControlContract.index(for: adopted))
            sender.setAccessibilityValue(ViewportPresetControlContract.accessibilityValue(for: adopted))
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

private struct FormInspectorFieldsView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var kind: FormFieldKind?
    @State private var label = ""
    @State private var name = ""
    @State private var help = ""
    @State private var required: Bool?
    @State private var options = "Option=option"
    @State private var maximumLength = ""
    @State private var mixedLabel = false
    @State private var mixedName = false
    @State private var mixedHelp = false
    @State private var mixedOptions = false
    @State private var mixedMaximumLength = false
    @State private var identity: FormInspectorOperationIdentity?
    @State private var status = ""

    private var fields: [DocumentNode] { state.selectedFormFields }
    private var form: DocumentNode? { state.selectedFormContainer }

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            if let form {
                Text("Form").font(.headline)
                Text("Submission, destinations, and visitor data are unavailable in this bounded editor slice.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.form.submission.unavailable")
                Text("\(form.childIDs.count) child object\(form.childIDs.count == 1 ? "" : "s"). Add a Text child, then select it to configure a field.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Local validation").font(.subheadline.weight(.semibold))
                Text(state.formValidationPreviewState.status)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(state.formValidationAccessibilitySummary.label)
                    .accessibilityValue(state.formValidationAccessibilitySummary.value)
                    .accessibilityHint(state.formValidationAccessibilitySummary.hint)
                    .accessibilityIdentifier("inspector.form.validation.status")
                Button("Validate Empty Local Draft") { _ = state.validateSelectedFormLocally() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                    .disabled(!state.canValidateSelectedFormLocally)
                    .accessibilityIdentifier("inspector.form.validation.empty")
                if let result = state.formValidationPreviewState.snapshot,
                   result.identity.formID == form.id {
                    Text(result.isValid ? "All configured fields are valid." : "\(result.fields.filter { !$0.isValid }.count) configured field issue\(result.fields.filter { !$0.isValid }.count == 1 ? "" : "s").")
                        .font(.caption).foregroundStyle(result.isValid ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("inspector.form.validation.result")
                }
            } else if fields.isEmpty {
                ContentUnavailableView("Select a Form Field", systemImage: "list.bullet.rectangle",
                    description: Text("Select a Text child of a Form to configure its field metadata."))
            } else {
                Text("Form Field").font(.headline)
                Text(state.formFieldInspectorPresentation.configurationStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.form.applicability")
                Picker("Field kind", selection: $kind) {
                    if kind == nil { Text("Mixed").tag(FormFieldKind?.none) }
                    ForEach(FormFieldKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .accessibilityIdentifier("inspector.form.kind")
                TextField("Visible label", text: Binding(get: { label }, set: { label = $0; mixedLabel = false }),
                          prompt: Text(mixedLabel ? "Mixed labels" : "Visible label"))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityIdentifier("inspector.form.label")
                TextField("Machine name", text: Binding(get: { name }, set: { name = $0; mixedName = false }),
                          prompt: Text(mixedName ? "Mixed machine names" : "Machine name"))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityIdentifier("inspector.form.name")
                TextField("Help text (optional)", text: Binding(get: { help }, set: { help = $0; mixedHelp = false }),
                          prompt: Text(mixedHelp ? "Mixed help text" : "Help text (optional)"))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityIdentifier("inspector.form.help")
                Picker("Requirement", selection: $required) {
                    if required == nil { Text("Mixed").tag(Bool?.none) }
                    Text("Optional").tag(Optional(false))
                    Text("Required").tag(Optional(true))
                }
                    .accessibilityIdentifier("inspector.form.required")
                if kind.map({ [.text, .email, .textarea].contains($0) }) ?? false {
                    TextField("Maximum length (optional)", text: Binding(get: { maximumLength }, set: {
                        maximumLength = $0; mixedMaximumLength = false
                    }),
                              prompt: Text(mixedMaximumLength ? "Mixed limits" : "Maximum length (optional)"))
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                        .accessibilityIdentifier("inspector.form.maximumLength")
                }
                if kind == .select {
                    TextField("Options: Label=value, one per line", text: Binding(get: { options }, set: {
                        options = $0; mixedOptions = false
                    }),
                              prompt: Text(mixedOptions ? "Mixed ordered options" : "Label=value, one per line"),
                              axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                        .accessibilityIdentifier("inspector.form.options")
                }
                Text("Type: \(state.formFieldInspectorPresentation.kind.displayValue) · \(state.formFieldInspectorPresentation.kind.provenance)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.form.provenance.kind")
                Text("Accessible name: \(state.formFieldInspectorPresentation.accessibleName.displayValue) · \(state.formFieldInspectorPresentation.accessibleName.provenance)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.form.provenance.label")
                HStack {
                    Button("Apply", action: apply)
                        .disabled(!state.formInspectorIsEnabled)
                        .accessibilityIdentifier("inspector.form.apply")
                    Button("Cancel", action: refresh)
                        .accessibilityIdentifier("inspector.form.cancel")
                    Button("Remove Field Metadata") {
                        if state.commitFormInspectorEdit(.removeConfiguration, identity: identity) { refresh() }
                        status = state.lastFormInspectorAnnouncement
                    }
                    .disabled(!state.formInspectorIsEnabled || fields.allSatisfy { $0.properties.allSatisfy { !$0.key.rawValue.hasPrefix("form.field.v1.") } })
                    .accessibilityIdentifier("inspector.form.remove")
                }
                Text(status.isEmpty ? state.lastFormInspectorAnnouncement : status)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Form field Inspector")
        .padding(.horizontal, 4)
        .onAppear(perform: refresh)
        .onChange(of: state.canvasRenderPlan?.identity) { _, _ in refresh() }
        .onExitCommand { refresh(); status = "Draft cancelled; committed metadata is unchanged." }
    }

    private func refresh() {
        identity = state.formInspectorIdentity
        guard !fields.isEmpty else { return }
        let kinds = fields.map { FormFieldKind(rawValue: $0.insertionStringProperty(CanonicalFormField.kindKey) ?? "text") ?? .text }
        kind = common(kinds)
        let labels = fields.map { $0.insertionStringProperty(CanonicalFormField.labelKey) ?? $0.name }
        label = common(labels) ?? ""; mixedLabel = common(labels) == nil
        let names = fields.map { $0.insertionStringProperty(CanonicalFormField.nameKey) ?? "field" }
        name = common(names) ?? ""; mixedName = common(names) == nil
        let helps = fields.map { $0.insertionStringProperty(CanonicalFormField.helpKey) ?? "" }
        help = common(helps) ?? ""; mixedHelp = common(helps) == nil
        required = common(fields.map { $0.insertionBooleanProperty(CanonicalFormField.requiredKey) })
        let limits = fields.map { $0.insertionNumberProperty(CanonicalFormField.maximumLengthKey).map { Int($0) } }
        let commonLimit = common(limits)
        maximumLength = commonLimit.flatMap { $0 }.map { String($0) } ?? ""
        mixedMaximumLength = commonLimit == nil
        let encodedOptions = fields.map { $0.insertionStringProperty(CanonicalFormField.optionsKey) }
        if let shared = common(encodedOptions), let encoded = shared,
           let values = try? CanonicalFormSelectOptions.decode(encoded) {
            options = values.map { "\($0.label)=\($0.value)" }.joined(separator: "\n")
            mixedOptions = false
        } else if common(encodedOptions) == nil {
            options = ""; mixedOptions = true
        } else {
            options = "Option=option"; mixedOptions = false
        }
        status = ""
    }

    private func apply() {
        guard let kind, let required, !mixedLabel, !mixedName, !mixedHelp,
              (!mixedOptions || kind != .select),
              (!mixedMaximumLength || ![.text, .email, .textarea].contains(kind)) else {
            status = "Resolve every Mixed field before applying one shared configuration; committed metadata is unchanged."
            return
        }
        let parsed: [CanonicalFormSelectOption]
        if kind == .select {
            // Values are the canonical uniqueness key. Preserve the existing
            // option identity when an author reorders or relabels a value;
            // create an identity only for a newly authored value.
            let existingOptions: [CanonicalFormSelectOption]
            if let field = fields.first,
               let encoded = field.insertionStringProperty(CanonicalFormField.optionsKey),
               let decoded = try? CanonicalFormSelectOptions.decode(encoded) {
                existingOptions = decoded
            } else {
                existingOptions = []
            }
            let existingByValue = Dictionary(uniqueKeysWithValues: existingOptions.map { ($0.value, $0.id) })
            let lines = options.split(separator: "\n", omittingEmptySubsequences: true)
            let candidates = lines.compactMap { line -> CanonicalFormSelectOption? in
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
                let value = String(parts[1])
                return .init(id: existingByValue[value] ?? FormOptionID(), label: String(parts[0]), value: value)
            }
            guard candidates.count == lines.count else {
                status = "Enter every Select option as a nonempty Label=value line; committed metadata is unchanged."
                return
            }
            parsed = candidates
        } else {
            parsed = []
        }
        let limit: Int?
        if maximumLength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { limit = nil }
        else { limit = Int(maximumLength) }
        let configuration = FormFieldConfiguration(kind: kind, label: label, name: name,
            help: help.isEmpty ? nil : help, required: required, options: parsed, maximumLength: limit)
        if state.commitFormInspectorEdit(.configure(configuration), identity: identity) { refresh() }
        status = state.lastFormInspectorAnnouncement
    }

    private func common<Value: Equatable>(_ values: [Value]) -> Value? {
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

private struct FormAccessibilityInspectorView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        GroupBox("Form Accessibility") {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            if let form = state.formContainerAccessibilityPresentation {
                Text(form.status)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.accessibility.form.status")
                LabeledContent("Fields", value: "\(form.configuredCount) configured of \(form.fieldCount)")
                LabeledContent("Required", value: "\(form.requiredCount)")
                LabeledContent("Submit controls", value: "\(form.submitCount) disabled until destination approval")
                Text(state.formValidationPreviewState.status)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(state.formValidationAccessibilitySummary.label)
                    .accessibilityValue(state.formValidationAccessibilitySummary.value)
                    .accessibilityHint(state.formValidationAccessibilitySummary.hint)
                    .accessibilityIdentifier("inspector.accessibility.form.validation")
                HStack {
                    Button("Validate Empty Local Draft") { _ = state.validateSelectedFormLocally() }
                        .keyboardShortcut("v", modifiers: [.command, .option])
                        .disabled(!state.canValidateSelectedFormLocally)
                        .accessibilityIdentifier("inspector.accessibility.form.validate")
                    Button("Edit in Content") { _ = state.selectInspectorTab(.content) }
                        .accessibilityIdentifier("inspector.accessibility.form.editContent")
                }
            } else if !state.selectedFormFields.isEmpty {
                let presentation = state.formFieldInspectorPresentation
                Text(presentation.configurationStatus)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.accessibility.formField.status")
                accessibilityRow("Control type", presentation.kind,
                                 identifier: "inspector.accessibility.formField.kind")
                accessibilityRow("Accessible name", presentation.accessibleName,
                                 identifier: "inspector.accessibility.formField.name")
                accessibilityRow("Requirement", presentation.required,
                                 identifier: "inspector.accessibility.formField.required")
                accessibilityRow("Description", presentation.help,
                                 identifier: "inspector.accessibility.formField.help")
                accessibilityRow("Machine name", presentation.machineName,
                                 identifier: "inspector.accessibility.formField.machineName")
                accessibilityRow("Options", presentation.options,
                                 identifier: "inspector.accessibility.formField.options")
                accessibilityRow("Maximum length", presentation.maximumLength,
                                 identifier: "inspector.accessibility.formField.maximumLength")
                Button("Edit Field in Content") { _ = state.selectInspectorTab(.content) }
                    .accessibilityHint("Opens the canonical Form field controls. Changes remain transactional and undoable.")
                    .accessibilityIdentifier("inspector.accessibility.formField.editContent")
            } else {
                Text("Select a Form or one of its fields to inspect accessible names, roles, requirements, help, and local validation.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.accessibility.form.empty")
            }
        }
        }
    }

    @ViewBuilder
    private func accessibilityRow(_ label: String, _ value: FormInspectorAggregateValue,
                                  identifier: String) -> some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: SiteForgeVisualSystem.hairlineSpacing) {
                Text(value.displayValue)
                    .accessibilityLabel("\(label): \(value.displayValue), \(value.provenance)")
                    .accessibilityIdentifier(identifier)
                Text(value.provenance).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// General authored accessibility metadata. Image alt text and Form-field
/// semantics intentionally remain in their dedicated Content workflows.
private struct GeneralAccessibilityInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var focused: CanonicalAccessibilityMetadata.Field?
    @State private var drafts: [CanonicalAccessibilityMetadata.Field: String] = [:]
    @State private var message: String?

    var body: some View {
        GroupBox("Accessibility") {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            HStack {
            Text(roleSummary)
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Semantic role: \(roleSummary)")
                .accessibilityIdentifier("inspector.accessibility.role")
                Spacer()
                Button("Reset") {
                    if state.commitAccessibilityMetadata(.reset, operation: "reset") {
                        drafts.removeAll(); message = nil
                    } else { message = state.lastDesignInspectorAnnouncement }
                }
                .disabled(!isAvailable)
                .accessibilityIdentifier("inspector.accessibility.reset")
            }
            ForEach(CanonicalAccessibilityMetadata.Field.allCases, id: \.self) { field in
                let value = state.accessibilityMetadataInspectorValue(field)
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                    HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                        Text(field.title).frame(width: 112, alignment: .leading).lineLimit(1)
                        TextField(field.title, text: Binding(
                            get: { drafts[field] ?? display(value) },
                            set: { drafts[field] = $0; message = nil }
                        ))
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                        .focused($focused, equals: field)
                        .onSubmit { commit(field) }
                        .onChange(of: focused) { previous, current in
                            if previous == field, current != field, drafts[field] != nil {
                                DispatchQueue.main.async { guard focused != field else { return }; commit(field) }
                            }
                        }
                        .disabled(!isEditable(value))
                        .accessibilityLabel(field.title)
                        .accessibilityValue(accessibilityValue(value))
                        .accessibilityHint("Enter a concise value and press Return. Empty removes the authored override; Escape cancels the draft.")
                        .accessibilityIdentifier("inspector.accessibility.\(field.rawValue)")
                    }
                    Text(provenance(value)).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("inspector.accessibility.\(field.rawValue).provenance")
                }
            }
            Button("Edit Semantic Element in Design") { _ = state.selectInspectorTab(.design) }
                .disabled(state.selectionState.isEmpty)
                .accessibilityIdentifier("inspector.accessibility.editSemantic")
            if let message {
                Text(message).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.accessibility.validation")
            }
            Text(state.lastDesignInspectorAnnouncement).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inspector.accessibility.announcement")
        }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.accessibility.general")
        .onExitCommand { drafts.removeAll(); focused = nil; message = nil }
    }

    private var isAvailable: Bool {
        CanonicalAccessibilityMetadata.Field.allCases.contains {
            isEditable(state.accessibilityMetadataInspectorValue($0))
        }
    }

    private var roleSummary: String {
        switch state.semanticElementInspectorValue() {
        case .single(let element, let origin):
            return "Role: <\(element.rawValue)> · \(origin == .authored ? "Authored" : "Defaulted")"
        case .mixed(let applicable, let skipped): return "Role: Mixed · \(applicable) applicable, \(skipped) skipped"
        case .unavailable(let reason): return "Role unavailable · \(reason)"
        }
    }

    private func isEditable(_ value: AccessibilityMetadataInspectorValue) -> Bool {
        if case .unavailable = value { return false }
        return true
    }

    private func display(_ value: AccessibilityMetadataInspectorValue) -> String {
        if case .single(let text?, _) = value { return text }
        return ""
    }

    private func provenance(_ value: AccessibilityMetadataInspectorValue) -> String {
        switch value {
        case .single(nil, _): return "Defaulted · no override"
        case .single(_, let origin): return origin == .authored ? "Authored" : "Defaulted"
        case .mixed(let applicable, let skipped): return "Mixed · \(applicable) editable, \(skipped) skipped"
        case .unavailable(let reason): return reason
        }
    }

    private func accessibilityValue(_ value: AccessibilityMetadataInspectorValue) -> String {
        switch value {
        case .single(nil, _): return "Defaulted, no override"
        case .single(let text?, let origin): return "\(text), \(origin == .authored ? "authored" : "defaulted")"
        case .mixed(let applicable, let skipped): return "Mixed values, \(applicable) editable, \(skipped) skipped"
        case .unavailable(let reason): return reason
        }
    }

    private func commit(_ field: CanonicalAccessibilityMetadata.Field) {
        let source = drafts[field] ?? display(state.accessibilityMetadataInspectorValue(field))
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        guard value?.count ?? 0 <= field.maximumLength else {
            message = "\(field.title) must be \(field.maximumLength) characters or fewer."
            return
        }
        guard state.commitAccessibilityMetadata(.set(field, value), operation: field.rawValue) else {
            message = state.lastDesignInspectorAnnouncement
            return
        }
        drafts[field] = nil; message = nil
    }
}

/// Shared native destination fields. Callers own draft/commit timing; target
/// validation stays in CanonicalLinkTarget and the identity-gated registries.
private struct NativeLinkDestinationFields: View {
    let document: CanonicalDocument
    @Binding var kind: String
    @Binding var page: String
    @Binding var section: String
    @Binding var url: String
    let focus: FocusState<String?>.Binding
    let allowsMixed: Bool
    let identifierPrefix: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Picker("Target type", selection: $kind) {
                Text("No target").tag("none"); Text("Page").tag("page")
                Text("Section").tag("section"); Text("External HTTP(S)").tag("external")
                if allowsMixed { Text("Mixed").tag("mixed") }
            }
            .accessibilityLabel("Destination type").accessibilityIdentifier(identifierPrefix + ".type")
            if kind == "page" || kind == "section" {
                Picker("Page", selection: $page) {
                    Text("Choose a page").tag("")
                    ForEach(document.websitePages, id: \.id) {
                        Text("\($0.name) — \($0.route.rawValue)").tag($0.id.description)
                    }
                    if !page.isEmpty && !document.websitePages.contains(where: { $0.id.description == page }) {
                        Text("Missing page").tag(page)
                    }
                }.accessibilityIdentifier(identifierPrefix + ".page")
            }
            if kind == "section" {
                Picker("Section", selection: $section) {
                    Text("Choose a section").tag("")
                    ForEach(document.websitePages.first(where: { $0.id.description == page })?.nodes.filter { $0.kind == .section } ?? [], id: \.id) {
                        Text($0.name).tag($0.id.description)
                    }
                    if !section.isEmpty && !(document.websitePages.first(where: { $0.id.description == page })?.nodes.contains {
                        $0.id.description == section && $0.kind == .section
                    } ?? false) { Text("Missing section").tag(section) }
                }.accessibilityIdentifier(identifierPrefix + ".section")
            }
            if kind == "external" {
                TextField("https://example.com", text: $url)
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).focused(focus, equals: "url")
                    .accessibilityLabel("External URL")
                    .accessibilityHint("Use an HTTP or HTTPS destination without credentials. Return applies; Escape cancels.")
                    .accessibilityIdentifier(identifierPrefix + ".url")
                    .onSubmit(onSubmit)
            }
        }
    }
}

private struct ControlInspectorFieldsView: View {
    @ObservedObject var state: WorkspaceShellState
    let interactions: Bool
    var presentationID: String? = nil
    @State private var label = ""
    @State private var url = ""
    @State private var kind = "none"
    @State private var page = ""
    @State private var section = ""
    @State private var dirty = false
    @State private var identity: ImageInspectorOperationIdentity?
    @State private var message = ""
    @FocusState private var field: String?
    @State private var presentationRevision: UInt64?
    private var nodes: [DocumentNode] { state.selectedLinkControls }
    private var document: CanonicalDocument { state.documentSession.document }
    private var target: CanonicalLinkTarget? {
        let values = nodes.compactMap { try? CanonicalLinkTarget.resolve($0) }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
    private var mixedLabel: Bool { Set(nodes.map(\.controlLabel)).count > 1 }
    private var context: String {
        let values = Set(nodes.map { $0.controlContext.rawValue })
        return values.count == 1 ? values.first! : "mixed"
    }
    private var provenance: String {
        let key = interactions ? CanonicalLinkTarget.namespace + "kind" : CanonicalLinkTarget.labelKey
        let values = Set(nodes.map { $0.insertionProperty(key)?.origin.rawValue ?? "omitted" })
        return values.count == 1 ? values.first!.capitalized : "Mixed provenance"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            if nodes.isEmpty {
                ContentUnavailableView("Select a Button or Link", systemImage: "link",
                    description: Text("These controls edit Button and Link labels and targets. Other selected objects are unchanged."))
                    .accessibilityIdentifier(interactions ? "inspector.interactions.unavailable" : "inspector.content.unavailable")
                    .accessibilityLabel("\(interactions ? "Interactions" : "Content") unavailable for this selection. Select a Button or Link.")
            } else {
                Text(interactions ? "Link Target" : "Control Label").font(.headline)
                Text("\(nodes.count) applicable; \(state.selectionState.count - nodes.count) incompatible unchanged · \(provenance)")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier(presentationID.map { $0 + ".applicability" } ?? "inspector.control.applicability")
                Group {
                    if interactions { targetFields } else {
                        TextField(mixedLabel ? "Mixed labels" : "Label", text: Binding(get: { label }, set: {
                            if label != $0 { label = $0; dirty = true }
                        }))
                            .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).focused($field, equals: "label")
                            .accessibilityLabel("Control label").accessibilityIdentifier("inspector.content.control.label")
                            .onSubmit { commitDraft("return") }
                        Button("Reset Label") { submit(.label(nil), provenance: "reset") }
                            .accessibilityIdentifier("inspector.content.control.reset")
                    }
                }.disabled(!state.linkInspectorIsEnabled)
                if !state.linkInspectorIsEnabled { Text("Show and unlock the selected controls before editing.").font(.caption) }
                Text(message.isEmpty ? "Editor selection never follows authored navigation." : message)
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Control edit status").accessibilityValue(message)
                    .accessibilityIdentifier(presentationID.map { $0 + ".status" } ?? "inspector.control.status")
            }
        }
        // Native text-field bezels extend beyond their SwiftUI layout rect.
        // Leave room inside the scroll viewport for the bezel and focus ring.
        .padding(.horizontal, 4)
        .onAppear { refresh(); presentationRevision = document.revision }
        .onChange(of: state.canvasRenderPlan?.identity) { _, _ in
            if !dirty && field == nil {
                if presentationRevision != document.revision { message = "" }
                presentationRevision = document.revision
                refresh()
            }
        }
        .onChange(of: field) { old, new in
            if old != nil && dirty {
                DispatchQueue.main.async {
                    guard field != old, dirty else { return }
                    commitDraft("focus-loss")
                }
            }
            if new != nil { identity = state.linkInspectorIdentity }
        }
        .onExitCommand { dirty = false; refresh(); message = "Draft cancelled; committed properties are unchanged."; field = nil }
    }
    private var targetFields: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            if target == nil { Text("Mixed targets").accessibilityIdentifier("inspector.interactions.link.mixed") }
            if nodes.contains(where: { (try? CanonicalLinkTarget.resolve($0).isMissing(in: document)) == true }) {
                Label("Target missing — choose a replacement or remove the target.", systemImage: "exclamationmark.triangle")
                    .font(.caption).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("inspector.interactions.link.missing")
            }
            NativeLinkDestinationFields(document: document,
                kind: Binding(get: { kind }, set: {
                    kind = $0; page = ""; section = ""; dirty = true
                    if $0 == "none" { submit(.target(nil), provenance: "picker") }
                }),
                page: Binding(get: { page }, set: {
                    page = $0; section = ""; dirty = true
                    if kind == "page", let id = PageID(uuidString: $0) { submit(.target(.page(id)), provenance: "picker") }
                }),
                section: Binding(get: { section }, set: {
                    section = $0
                    if let pageID = PageID(uuidString: page), let nodeID = NodeID(uuidString: $0) {
                        submit(.target(.section(pageID: pageID, nodeID: nodeID)), provenance: "picker")
                    }
                }),
                url: Binding(get: { url }, set: { if url != $0 { url = $0; dirty = true } }),
                focus: $field, allowsMixed: target == nil,
                identifierPrefix: "inspector.interactions.link", onSubmit: { commitDraft("return") })
            Picker("Open in", selection: Binding(get: { context }, set: {
                if let value = CanonicalLinkContext(rawValue: $0) { submit(.context(value), provenance: "picker") }
            })) {
                Text("Same context").tag("same"); Text("New context").tag("new")
                if context == "mixed" { Text("Mixed").tag("mixed") }
            }.accessibilityIdentifier("inspector.interactions.link.context")
            Button("Remove Target") { submit(.target(nil), provenance: "reset") }.accessibilityIdentifier("inspector.interactions.link.remove")
            Button("Reset Context") { submit(.context(nil), provenance: "reset") }.accessibilityIdentifier("inspector.interactions.link.resetContext")
        }
    }
    private func refresh() {
        identity = state.linkInspectorIdentity
        label = mixedLabel ? "" : (nodes.first?.controlLabel ?? "")
        page = ""; section = ""; url = ""
        switch target {
        case .none?: kind = "none"
        case .page(let id)?: kind = "page"; page = id.description
        case .section(let pageID, let nodeID)?: kind = "section"; page = pageID.description; section = nodeID.description
        case .external(let value)?: kind = "external"; url = value
        case nil: kind = "mixed"
        }
    }
    private func submit(_ edit: LinkInspectorEdit, provenance: String) {
        let wasDirty = dirty
        dirty = false
        if state.commitLinkEdit(edit, identity: state.linkInspectorIdentity, provenance: provenance) { field = nil; refresh() }
        else { dirty = wasDirty }
        message = state.lastLinkInspectorAnnouncement
        presentationRevision = document.revision
    }
    private func commitDraft(_ provenance: String) {
        guard dirty else { return }
        let edit: LinkInspectorEdit = interactions ? .target(.external(url)) : .label(label)
        // Canonical publication can synchronously end native editing. Consume
        // this draft first so its focus-loss callback cannot commit it twice.
        dirty = false
        if state.commitLinkEdit(edit, identity: identity, provenance: provenance) { field = nil }
        else { dirty = true }
        message = state.lastLinkInspectorAnnouncement
        presentationRevision = document.revision
    }
}

private struct InspectorWorkflowControls: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var toolsExpanded = false
    var body: some View {
        DisclosureGroup("Inspector Tools", isExpanded: $toolsExpanded) {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            HStack {
                TextField("Find Inspector properties", text: Binding(get: { state.inspectorSectionQuery },
                    set: { state.inspectorSectionQuery = String($0.prefix(256)) }))
                    .accessibilityLabel("Find Inspector sections by property name")
                    .accessibilityIdentifier("inspector.workflow.search")
                    .onSubmit { if let first = state.discoveredInspectorSections.first { _ = state.selectInspectorTab(first) } }
                    .onExitCommand { state.inspectorSectionQuery = "" }
                Button("Clear") { state.inspectorSectionQuery = "" }
                    .disabled(state.inspectorSectionQuery.isEmpty)
                    .accessibilityIdentifier("inspector.workflow.clear")
            }
            if !state.inspectorSectionQuery.isEmpty || !state.pinnedInspectorSections.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(state.discoveredInspectorSections) { section in
                        Button { _ = state.selectInspectorTab(section) } label: {
                            Label(section.title, systemImage: state.pinnedInspectorSections.contains(section) ? "pin.fill" : "slider.horizontal.3")
                                .lineLimit(1).fixedSize()
                        }.accessibilityLabel("Reveal " + section.title + " Inspector")
                            .accessibilityValue(state.inspectorTab == section ? "Current section" : "Available section")
                            .accessibilityIdentifier("inspector.workflow.section." + section.rawValue)
                    }
                }
            }
            }
            HStack {
                Text("\(state.discoveredInspectorSections.count) sections").font(.caption)
                    .accessibilityIdentifier("inspector.workflow.count")
                Spacer()
                Button(state.pinnedInspectorSections.contains(state.inspectorTab) ? "Unpin Section" : "Pin Section", action: state.toggleInspectorPin)
                    .accessibilityValue(state.pinnedInspectorSections.contains(state.inspectorTab) ? "Pinned" : "Not pinned")
                    .accessibilityIdentifier("inspector.workflow.pin")
            }
            if state.discoveredInspectorSections.isEmpty {
                Text("No matching section. Clear search; the current Inspector and all tabs remain available.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.workflow.empty")
            }
            if state.inspectorTab == .layout {
                Group {
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                        Picker("Property", selection: $state.inspectorTransferField) {
                            ForEach(GeometryInspectorField.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("inspector.workflow.transfer.field")
                        Text(state.geometryInspectorResponsiveSource(for: state.inspectorTransferField) ?? "Unavailable geometry source")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("inspector.workflow.transfer.provenance")
                        if state.geometryInspectorValue(for: state.inspectorTransferField) == .mixed {
                            Text("Mixed values — Copy is unavailable. Paste explicitly unifies only applicable objects.")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("inspector.workflow.transfer.mixed")
                        }
                        HStack {
                            Button("Copy Value", action: state.copyInspectorGeometry).disabled(!state.canCopyInspectorGeometry)
                                .lineLimit(1)
                                .accessibilityIdentifier("inspector.workflow.copy")
                            Button("Paste Value", action: state.pasteInspectorGeometry)
                                .lineLimit(1)
                                .disabled(!state.pageEditingIsAvailable || state.selectionState.isEmpty)
                                .accessibilityIdentifier("inspector.workflow.paste")
                        }
                    }
                }.help("Copy a consistent geometry value. Paste changes only compatible objects at this screen size in one undoable edit.")
            }
            if !state.inspectorWorkflowAnnouncement.isEmpty,
               state.inspectorWorkflowAnnouncement != "Inspector discovery is local to this window." {
            Text(state.inspectorWorkflowAnnouncement).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Inspector workflow status").accessibilityValue(state.inspectorWorkflowAnnouncement)
                .accessibilityIdentifier("inspector.workflow.status")
            }
        }
        }.disclosureGroupStyle(SiteForgeInspectorDisclosureStyle(identifier: "inspector.workflow.disclosure"))
    }
}

private struct InspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    let focus: FocusState<ShellFocus?>.Binding
    @State private var componentPropertiesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            ShellTabBar(
                tabs: InspectorTab.allCases,
                selection: Binding(get: { state.inspectorTab }, set: { _ = state.selectInspectorTab($0) }),
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

            if state.inspectorTab == .layout,
               state.hasContainerLayoutSelection
                || state.lastContainerLayoutAnnouncement != "Container layout inactive" {
                Text(state.currentContainerLayoutAnnouncement)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Container layout edit status")
                .accessibilityValue(state.currentContainerLayoutAnnouncement)
                .accessibilityIdentifier("inspector.layout.container.announcement")
            } else if state.inspectorTab == .content,
                      state.hasFormInspectorContext
                        || state.lastFormInspectorAnnouncement != "Form field properties" {
                Text(state.lastFormInspectorAnnouncement)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Form field edit status")
                .accessibilityValue(state.lastFormInspectorAnnouncement)
                .accessibilityIdentifier("inspector.form.status")
            }

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
                VStack(spacing: SiteForgeVisualSystem.standardSpacing) {
                ContentUnavailableView(
                    "Nothing Selected",
                    systemImage: "slider.horizontal.3",
                    description: Text("Select an object to inspect its \(state.inspectorTab.title.lowercased()) summary.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Nothing Selected. Select an object to inspect its \(state.inspectorTab.title.lowercased()).")
                .accessibilityIdentifier("inspector.empty")
                if state.inspectorTab == .design, let pageID = state.effectiveSelectedPageID {
                    Button("Page Background…", systemImage: "paintpalette") { state.revealPageBackground(pageID: pageID) }
                        .disabled(!state.pageEditingIsAvailable || state.pageBackgroundUnavailableReason != nil)
                        .accessibilityValue(state.pageBackgroundSummary)
                        .accessibilityIdentifier("inspector.pageBackground.open")
                    if let reason = state.pageBackgroundUnavailableReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
            } else {
                ScrollViewReader { inspectorReader in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                        Label(state.isInspectingPageBackground ? "Page Background" : state.selectionSummary, systemImage: state.isInspectingPageBackground ? "paintpalette" : state.selectionState.count > 1 ? "square.stack.3d.up" : "selection.pin.in.out")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if state.layerTargets.first(where: { $0.id == state.selectionState.primaryID })?.isLocked == true {
                            Label("Locked — inspection only", systemImage: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                        if !state.isInspectingPageBackground {
                            FormattingTransferControls(state: state)
                        }
                        if state.hasCurrentBuildFindingEditorRequest {
                            Text(state.buildFindingRevealStatus).font(.caption).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("inspector.outputRepair.status")
                        }
                        }.modifier(SiteForgeInspectorSectionSurface()).id("inspector.selection.top")
                        if !state.isInspectingPageBackground {
                            InspectorWorkflowControls(state: state)
                        }
                        inspectorDetails(reader: inspectorReader)
                    }
                    // The production minimum-height window can extend under the
                    // Dock on a shorter display. Keep the last native control
                    // scrollable above that occlusion instead of stranding it
                    // against the bottom edge of the Inspector.
                    .padding(.bottom, SiteForgeVisualSystem.inspectorBottomClearance)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Inspector selection summary")
                    .accessibilityValue("\(state.selectionSummary); \(state.transformGeometrySummary)")
                    .accessibilityIdentifier("inspector.selection.summary")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("inspector.selection.scroll")
                .onChange(of: state.responsiveLayoutInspectorRequestID) { _, request in
                    guard request != nil, state.inspectorTab == .layout,
                          state.hasCurrentResponsiveLayoutInspectorRequest else { return }
                    inspectorReader.scrollTo("sizing:" + state.layoutInspectorViewIdentity, anchor: .top)
                }
                .onChange(of: state.buildFindingEditorRequest?.id) { _, _ in
                    if let anchor = state.buildFindingInspectorAnchor { inspectorReader.scrollTo(anchor, anchor: .top) }
                }
                .onAppear {
                    if let anchor = state.buildFindingInspectorAnchor { inspectorReader.scrollTo(anchor, anchor: .top); return }
                    guard state.inspectorTab == .layout, state.hasCurrentResponsiveLayoutInspectorRequest else { return }
                    inspectorReader.scrollTo("sizing:" + state.layoutInspectorViewIdentity, anchor: .top)
                }
                }
            }
        }
        .padding(SiteForgeVisualSystem.panePadding)
        .workspaceChrome(.inspector)
        .groupBoxStyle(SiteForgeInspectorGroupStyle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.inspector.rawValue)
        .onChange(of: state.editingComponentID) { _, id in
            if id != nil { componentPropertiesExpanded = true }
        }
    }

    @ViewBuilder
    private func inspectorDetails(reader: ScrollViewProxy) -> some View {
        switch state.inspectorTab {
        case .design:
            if let instance = state.selectedComponent {
                OrganizedComponentInstanceInspectorView(state: state, instance: instance, reader: reader)
                    .id(state.documentSession.document.id.description + ":" + instance.id.description + ":" +
                        (CanonicalComponentReference.definitionID(for: instance)?.description ?? "missing"))
            } else {
                DesignInspectorFieldsView(state: state)
                    .id(state.selectionState.orderedIDs.map(\.description).joined(separator: ","))
            }
        case .layout:
            if let owner = state.selectedPageChromeOwner {
                Text("Part of \(owner.name). Its containing layout determines the visible position; automatic content/navigation bounds are managed by Header/Footer settings.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Open Header/Footer Settings", action: state.revealPageChromeOwner)
                    .accessibilityIdentifier("inspector.navigation.owner")
            }
            if state.hasMixedPageStructureSelection {
                Text("Mixed page-structure selection. Heights can be edited together; positions/widths and navigation remain managed by their owners.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let node = state.selectedPageStructureNode {
                PageStructureInspectorView(state: state, node: node)
                    .id("page-structure:" + state.documentSession.document.id.description + node.id.description)
            }
            Text(state.transformGeometrySummary)
                .monospacedDigit()
                .accessibilityLabel("Selection geometry")
                .accessibilityValue(state.transformGeometrySummary)
                .accessibilityIdentifier("inspector.transform.geometry")
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                    if !state.responsiveLayoutReviewStatus.isEmpty {
                        Text(state.responsiveLayoutReviewStatus).font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("inspector.layout.responsiveReview")
                    }
                    SizingInspectorFieldsView(state: state)
                }
                    .id("sizing:" + state.layoutInspectorViewIdentity)
                GeometryInspectorFieldsView(state: state)
                    .id("geometry:" + state.layoutInspectorViewIdentity)
                if state.hasContainerLayoutSelection {
                    ContainerLayoutInspectorView(state: state, showFluidValues: {
                        reader.scrollTo("fluid:" + state.fluidValueInspectorIdentity, anchor: .top)
                    })
                        .id("container:" + state.layoutInspectorViewIdentity)
                }
            }.modifier(SiteForgeInspectorSectionSurface())
            if !state.hasManagedPageStructureSelection {
                PositioningInspectorView(state: state).modifier(SiteForgeInspectorSectionSurface())
                    .id("position:" + state.geometryInspectorSelectionKey)
            } else {
                Text("Page flow owns positioning. Free/fixed/sticky offsets are inactive while connected; Undo conversion restores the original data.").font(.caption)
            }
            if !state.supportedFluidValueTargets.isEmpty {
                FluidValueInspectorView(state: state)
                    .modifier(SiteForgeInspectorSectionSurface())
                    .id("fluid:" + state.fluidValueInspectorIdentity)
            }
            if !state.selectionState.isEmpty {
                Divider()
                ResponsiveVisibilityInspectorView(state: state)
                    .modifier(SiteForgeInspectorSectionSurface())
                    .id("visibility:\(state.geometryInspectorSelectionKey)")
            }
            Divider()
            guideAndSnappingDetails.modifier(SiteForgeInspectorSectionSurface())
        case .accessibility:
            if state.hasFormInspectorContext {
                FormAccessibilityInspectorView(state: state)
                    .id("form-accessibility:" + state.geometryInspectorSelectionKey)
            } else {
                GeneralAccessibilityInspectorView(state: state)
                    .id("general-accessibility:" + state.geometryInspectorSelectionKey)
            }
        case .content where state.hasMixedPageStructureSelection || state.hasPageNavigationSelection:
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                Text("Select one Header/Footer to edit navigation, or one Section to organize flow. Navigation links keep their owner's layout and PageID destinations; no primary values are borrowed for mixed selections.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                if state.hasPageNavigationSelection, state.selectedCanonicalNodes.count == 1 {
                    Button("Edit Header/Footer Links", action: state.revealPageNavigationOwner)
                        .disabled(!state.pageEditingIsAvailable)
                        .accessibilityIdentifier("inspector.navigation.revealOwner")
                }
            }
        case .content where state.selectedPageStructureNode != nil:
            if let node = state.selectedPageStructureNode {
                PageStructureInspectorView(state: state, node: node)
                    .id("page-structure-content:" + state.documentSession.document.id.description + node.id.description)
            }
        case .content where state.hasComponentTextInspectorContext:
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
                if let instance = state.selectedComponent {
                    OrganizedComponentInstanceInspectorView(state: state, instance: instance, reader: reader)
                        .id(state.documentSession.document.id.description + ":" + instance.id.description + ":" +
                            (CanonicalComponentReference.definitionID(for: instance)?.description ?? "missing"))
                } else {
                    if let text = state.selectedDefinitionText { plainTextDetails(text) }
                    if !state.componentOrganizationEntries.isEmpty || state.selectedDefinitionText != nil
                        || state.selectedDefinitionVisibilityChild != nil || state.selectedDefinitionChoiceImage != nil
                        || state.selectedDefinitionMediaImage != nil || state.selectedDefinitionActionControl != nil
                        || state.selectedDefinitionSlotContainer != nil {
                    DisclosureGroup("Component Properties", isExpanded: $componentPropertiesExpanded) {
                    if !state.componentOrganizationEntries.isEmpty {
                        ComponentOrganizationInspectorView(state: state)
                            .id("organization:" + state.componentTextInspectorKey)
                    }
                    if state.selectedDefinitionText != nil {
                        ComponentTextInspectorView(state: state)
                    }
                    if state.selectedDefinitionVisibilityChild != nil {
                        ComponentVisibilityInspectorView(state: state).id("visibility:" + state.componentTextInspectorKey)
                    }
                    if state.selectedDefinitionChoiceImage != nil {
                        ComponentChoiceInspectorView(state: state)
                    }
                    if state.selectedDefinitionMediaImage != nil {
                        ComponentMediaInspectorView(state: state)
                    }
                    if state.selectedDefinitionActionControl != nil { ComponentActionInspectorView(state: state) }
                    if state.selectedDefinitionSlotContainer != nil { ComponentSlotInspectorView(state: state) }
                    }.disclosureGroupStyle(SiteForgeInspectorDisclosureStyle(identifier: "component.definition.properties"))
                    }
                }
            }
                // Keep discovery state across edits; only value drafts/recovery
                // capture a new adopted operation identity. Selection or document
                // replacement still creates a fresh discovery context.
                .id(state.selectedComponent == nil ? (state.selectedDefinitionText != nil
                    ? "component-definition-text:" + state.documentSession.document.id.description + ":" + state.selectionState.orderedIDs.map(\.description).joined(separator: ",")
                    : "component-text:" + state.componentTextInspectorKey) :
                    "component-discovery:" + state.documentSession.document.id.description + ":" +
                    state.selectionState.orderedIDs.map(\.description).joined(separator: ",") + ":" +
                    (state.selectedComponent.flatMap { CanonicalComponentReference.definitionID(for: $0) }?.description ?? "missing"))
        case .content where state.selectedCanonicalNodes.count == 1 && state.selectedCanonicalNodes.first?.kind == .text && !state.hasFormInspectorContext:
            if let text = state.selectedCanonicalNodes.first { plainTextDetails(text) }
        case .content where state.hasFormInspectorContext:
            FormInspectorFieldsView(state: state)
                .id("form-field:" + state.geometryInspectorSelectionKey)
        case .content, .interactions:
            ControlInspectorFieldsView(state: state, interactions: state.inspectorTab == .interactions)
                .id(state.selectionState.orderedIDs.map(\.description).joined(separator: ",") + state.inspectorTab.rawValue)
        }
    }

    private func plainTextDetails(_ node: DocumentNode) -> some View {
        GroupBox("Text") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                Text(node.insertionStringProperty("content.text") ?? "")
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Committed text")
                    .accessibilityValue(node.insertionStringProperty("content.text") ?? "")
                    .accessibilityIdentifier("inspector.text.content")
                HStack {
                    Button("Edit Text") { _ = state.beginTextEditing(nodeID: node.id, provenance: .pointer) }
                        .disabled(!state.pageEditingIsAvailable)
                        .accessibilityIdentifier("inspector.text.edit")
                    Button("Typography") { _ = state.selectInspectorTab(.design) }
                        .accessibilityIdentifier("inspector.text.typography")
                }
            }
        }
    }

    private var guideAndSnappingDetails: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
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

private enum PendingReusableStyleAction {
    case update(CanonicalReusableStyleDefinition, ReusableStyleSelectionCapture, ResponsiveInspectorEditContext, Int, Int)
    case inherit(ReusableAppearanceProperty, ResponsiveInspectorEditContext)

    var context: ResponsiveInspectorEditContext {
        switch self { case .update(_, _, let context, _, _), .inherit(_, let context): context }
    }
    var edit: AdvancedStyleEdit {
        switch self {
        case .update(let definition, let capture, _, _, _):
            .updateReusableStyle(id: definition.id, name: definition.name, fill: capture.fill, opacity: capture.opacity)
        case .inherit(let property, _): .useLinkedAppearance(property)
        }
    }
    var title: String {
        switch self {
        case .update: "Update Shared Style"
        case .inherit(.fill, _): "Use Linked Fill"
        case .inherit(.opacity, _): "Use Linked Opacity"
        }
    }
    var explanation: String {
        switch self {
        case .update(let definition, let capture, _, let objects, let pages):
            "Update ‘\(definition.name)’ to \(capture.fill.hexadecimalRGBA), opacity \(Int((capture.opacity * 100).rounded()))%, for \(objects) authored links across \(pages) pages/definitions. Component instances may inherit changes too. Local fills, None, tokens and box styles are retained. The definition stores a color value, not a live source-token binding."
        case .inherit(.fill, _):
            "Remove the selected objects' local fill layers and stops, then use their linked solid fill. Other styles, token definitions, opacity and box styles are retained. Explicit None, image fills and fill-token bindings are protected; Undo restores exact local fill identities."
        case .inherit(.opacity, _):
            "Remove only local opacity on the selection and inherit linked opacity. Fill, None, tokens and box styles are unchanged. Undo restores the exact local property."
        }
    }
}

private struct AdvancedStyleInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var styleName = ""
    @State private var stateFill = ""
    @State private var stateOpacity = ""
    @State private var editedState: CanonicalInteractionStyleState = .hover
    @State private var pendingStyleAction: PendingReusableStyleAction?
    @State private var styleValidation: String?

    var body: some View {
        let context = state.responsiveInspectorEditContext
        let usage = state.reusableStyleUsage
        let linkedCounts = state.selectedReusableStyleLinkCounts
        let captureResult = state.reusableStyleCapture
        let capture: ReusableStyleSelectionCapture? = if case .success(let value) = captureResult { value } else { nil }
        let fillReset = state.linkedAppearanceAvailability(.fill)
        let opacityReset = state.linkedAppearanceAvailability(.opacity)
        return VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            HStack {
                Text("Reusable Styles").font(.headline)
                Spacer()
                Button("Unlink all") {
                    perform(.applyReusableStyles([]), operation: "Reusable style detach", context: context)
                }
                .disabled(linkedCounts.isEmpty)
                .help("Remove style links from compatible selected objects, not their content. Local values, explicit None and token links remain.")
                .accessibilityIdentifier("inspector.design.style.detach")
            }
            Divider().accessibilityHidden(true)
            Text("Reusable styles share solid color and opacity. Later links take priority, unless local values, explicit None, tokens or interaction states override them. SiteForge appearance is separate.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inspector.design.style.scope")
            if state.selectedReusableStyleIDs == nil {
                Text("Mixed links · link/unlink keeps each object's other links and order.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.design.style.mixed")
            }
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                TextField("Style name", text: $styleName)
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityIdentifier("inspector.design.style.name")
                Button("Create Color Style") { createStyle(context: context) }
                    .lineLimit(1).fixedSize()
                    .disabled(styleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || capture == nil)
                    .help(AuthoringLanguage.colorOpacitySampleHelp)
                    .accessibilityHint(AuthoringLanguage.colorOpacitySampleHelp)
                    .accessibilityIdentifier("inspector.design.style.create")
            }
            if let capture {
                Text("Color/opacity sample: \(capture.fill.hexadecimalRGBA) · \(Int((capture.opacity * 100).rounded()))% opacity · \(capture.applicableCount) compatible · \(capture.skippedCount) skipped.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue("\(capture.fill.hexadecimalRGBA); opacity \(Int((capture.opacity * 100).rounded())) percent; \(capture.applicableCount) applicable; \(capture.skippedCount) skipped")
                    .accessibilityIdentifier("inspector.design.style.capture")
                    .help(AuthoringLanguage.colorOpacitySampleHelp)
                Text("Solid color and opacity only. Reuse Formatting transfers fuller formatting.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if capture.boundFillCount > 0 {
                    Text("The source keeps its color-token link. This sample takes the visible color, not that link.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else if case .failure(let error) = captureResult {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.design.style.captureUnavailable")
            }
            HStack {
                Button("Use Linked Fill…") { pendingStyleAction = .inherit(.fill, context) }
                    .disabled(!fillReset.isEnabled).help(fillReset.disabledReason ?? "Remove local fill overrides explicitly.")
                    .accessibilityIdentifier("inspector.design.style.inheritFill")
                Button("Use Linked Opacity…") { pendingStyleAction = .inherit(.opacity, context) }
                    .disabled(!opacityReset.isEnabled).help(opacityReset.disabledReason ?? "Remove only local opacity explicitly.")
                    .accessibilityIdentifier("inspector.design.style.inheritOpacity")
            }.controlSize(.small)
            if let reason = fillReset.disabledReason, !linkedCounts.isEmpty {
                Text(reason).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(reason)
                    .accessibilityIdentifier("inspector.design.style.fillResetStatus")
            }
            ForEach(state.reusableStyleDefinitions, id: \.id) { definition in
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                    HStack {
                        Text(definition.name).lineLimit(1).help(definition.name)
                        Spacer()
                        Text("\(usage[definition.id]?.objects ?? 0) uses · \(linkedCounts[definition.id] ?? 0) selected")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .accessibilityValue("\(usage[definition.id]?.objects ?? 0) uses; \(linkedCounts[definition.id] ?? 0) selected")
                            .accessibilityIdentifier("inspector.design.style.\(definition.id).usage")
                    }
                    HStack {
                    Button("Link") { perform(.linkReusableStyle(definition.id), operation: "Reusable style link", context: context) }
                    .accessibilityLabel("Apply reusable style \(definition.name)")
                    .accessibilityIdentifier("inspector.design.style.\(definition.id).link")
                    Button("Unlink") { perform(.unlinkReusableStyle(definition.id), operation: "Reusable style unlink", context: context) }
                        .disabled(linkedCounts[definition.id] == nil)
                        .accessibilityLabel("Unlink only reusable style \(definition.name)")
                        .accessibilityIdentifier("inspector.design.style.\(definition.id).unlink")
                    Button("Update…") { updateStyle(definition, context: context) }
                        .disabled(capture == nil)
                        .accessibilityLabel("Update reusable style \(definition.name) from the solid-color and opacity sample")
                        .help(AuthoringLanguage.colorOpacitySampleHelp)
                        .accessibilityIdentifier("inspector.design.style.\(definition.id).update")
                    Button("Delete", role: .destructive) {
                        perform(.removeReusableStyle(definition.id), operation: "Reusable style deletion", context: context)
                    }
                    .disabled((usage[definition.id]?.objects ?? 0) > 0)
                    .help("Unlink every authored use before deleting a definition.")
                    .accessibilityLabel("Delete reusable style \(definition.name)")
                    }
                    HStack {
                        Button { perform(.moveReusableStyle(definition.id, offset: -1), operation: "Reusable style earlier", context: context) }
                            label: { Label("Earlier", systemImage: "arrow.up") }
                        .accessibilityLabel("Move \(definition.name) earlier in selected style links")
                        .accessibilityIdentifier("inspector.design.style.\(definition.id).earlier")
                        Button { perform(.moveReusableStyle(definition.id, offset: 1), operation: "Reusable style later", context: context) }
                            label: { Label("Later", systemImage: "arrow.down") }
                        .accessibilityLabel("Move \(definition.name) later in selected style links")
                        .accessibilityIdentifier("inspector.design.style.\(definition.id).later")
                    }.disabled(linkedCounts[definition.id] == nil)
                }
                .controlSize(.small)
            }
            if let styleValidation {
                Text(styleValidation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.design.style.validation")
            }
            Divider()
            Text("Interaction States").font(.headline)
            Picker("Preview state", selection: $state.forcedStyleState) {
                ForEach(CanonicalInteractionStyleState.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .accessibilityIdentifier("inspector.design.state.preview")
            Picker("Edit state", selection: $editedState) {
                ForEach(CanonicalInteractionStyleState.allCases.filter { $0 != .default }, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            HStack {
                TextField("State fill #RRGGBBAA", text: $stateFill).textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .accessibilityIdentifier("inspector.design.state.fill")
                TextField("Opacity 0–100", text: $stateOpacity).textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .frame(width: 92).accessibilityIdentifier("inspector.design.state.opacity")
            }
            HStack {
                Button("Apply State") { commitState() }
                    .accessibilityIdentifier("inspector.design.state.apply")
                Button("Remove State") {
                    _ = state.commitAdvancedStyle(.removeState(editedState), operation: "State style removal")
                }
                .accessibilityIdentifier("inspector.design.state.remove")
            }
            Text("State preview is editor-only; authored variants remain canonical and undoable.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: editedState) { _, _ in restoreStateDraft() }
        .onAppear { restoreStateDraft() }
        .onExitCommand {
            pendingStyleAction = nil; styleValidation = nil
            styleName = ""; restoreStateDraft()
            state.cancelAdvancedStyleDraft()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.design.advancedStyles")
        .confirmationDialog(pendingStyleAction?.title ?? "Shared Styling", isPresented: Binding(
            get: { pendingStyleAction != nil }, set: { if !$0 { pendingStyleAction = nil } }), titleVisibility: .visible) {
                if let request = pendingStyleAction {
                    Button(request.title) {
                        pendingStyleAction = nil
                        perform(request.edit, operation: request.title, context: request.context)
                    }.accessibilityIdentifier("inspector.design.style.confirm")
                    Button("Cancel", role: .cancel) { pendingStyleAction = nil }
                }
            } message: { Text(pendingStyleAction?.explanation ?? "") }
    }

    private func createStyle(context: ResponsiveInspectorEditContext) {
        guard case .success(let capture) = state.reusableStyleCapture else { return }
        let name = styleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.commitAdvancedStyle(.createReusableStyle(id: ReusableStyleID(), name: name,
            fill: capture.fill, opacity: capture.opacity), operation: "Reusable style creation", expectedContext: context) {
            styleName = ""; styleValidation = nil
        } else { styleValidation = state.lastDesignInspectorAnnouncement }
    }

    private func updateStyle(_ definition: CanonicalReusableStyleDefinition, context: ResponsiveInspectorEditContext) {
        guard case .success(let capture) = state.reusableStyleCapture,
              context == state.responsiveInspectorEditContext else { return }
        let usage = state.reusableStyleUsage[definition.id]
        pendingStyleAction = .update(definition, capture, context, usage?.objects ?? 0, usage?.pages ?? 0)
    }

    private func perform(_ edit: AdvancedStyleEdit, operation: String, context: ResponsiveInspectorEditContext) {
        if state.commitAdvancedStyle(edit, operation: operation, expectedContext: context) { styleValidation = nil }
        else { styleValidation = state.lastDesignInspectorAnnouncement }
    }

    private func restoreStateDraft() {
        let value = state.selectedStateVariant(editedState)
        stateFill = value?.fill?.hexadecimalRGBA ?? ""
        stateOpacity = value?.opacity.map { String(Int(($0 * 100).rounded())) } ?? ""
    }

    private func commitState() {
        let fill = stateFill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : CanonicalSolidColor.parse(hexadecimal: stateFill)
        let opacity: Double? = stateOpacity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : Double(stateOpacity).map { $0 / 100 }
        guard (stateFill.isEmpty || fill != nil), opacity.map({ (0...1).contains($0) }) ?? true,
              fill != nil || opacity != nil else { return }
        let id = state.selectedStateVariant(editedState)?.id ?? UUID()
        _ = state.commitAdvancedStyle(.setState(state: editedState, id: id, fill: fill, opacity: opacity),
                                      operation: "\(editedState.rawValue.capitalized) state style")
    }
}

/// Scene-local presentation drafts only. Canonical RGBA/opacity changes are
/// submitted as separate typed transactions so a cancelled picker/text draft
/// can never alter package, history, or editor overlays.
private struct FormattingTransferMenuActions: View {
    @ObservedObject var state: WorkspaceShellState
    var body: some View {
        ForEach(FormattingFamily.allCases, id: \.rawValue) { family in
            Button("Copy " + family.title) { state.copyFormatting(family) }
                .disabled(!state.formattingCopyAvailability(family).isEnabled)
                .help(state.formattingCopyAvailability(family).disabledReason ?? "Copy canonical base formatting; no source content changes.")
                .accessibilityHint(state.formattingCopyAvailability(family).disabledReason ?? "Copies defaults, literals and reference intent, not computed values.")
                .accessibilityIdentifier("formatting.copy." + family.rawValue)
            Button("Paste " + family.title) { state.pasteFormatting(family) }
                .disabled(!state.formattingPasteAvailability(family).isEnabled)
                .help(state.formattingPasteAvailability(family).disabledReason ?? state.formattingTargetSummary(family))
                .accessibilityHint(state.formattingPasteAvailability(family).disabledReason ?? state.formattingTargetSummary(family))
                .accessibilityIdentifier("formatting.paste." + family.rawValue)
        }
    }
}

private struct FormattingTransferControls: View {
    @ObservedObject var state: WorkspaceShellState
    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
            InspectorActionLayout {
                Menu { FormattingTransferMenuActions(state: state) } label: {
                    Label { InspectorActionLabel(title: "Reuse Formatting") } icon: { Image(systemName: "paintbrush") }
                }
                    .accessibilityLabel("Copy and Paste Text Style or Appearance")
                    .accessibilityIdentifier("inspector.formatting.menu")
                    .help("Reuse text style or appearance without changing content or size. Copy identical formatting; paste edits compatible targets only. Style and token links stay intact.")
                if state.isPreparingFormattingCopy { ProgressView().controlSize(.small).accessibilityLabel("Checking common formatting") }
            }
            ForEach(FormattingFamily.allCases, id: \.rawValue) { family in
                if !state.isPreparingFormattingCopy, state.selectedCanonicalNodes.allSatisfy(family.supports),
                   let reason = state.formattingCopyAvailability(family).disabledReason {
                    Text(family.title + ": " + reason).font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.formatting.reason." + family.rawValue)
                }
            }
            if state.selectedCanonicalNodes.count > 1 {
                Text(state.formattingTargetSummary(.textStyle) + " " + state.formattingTargetSummary(.appearance))
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.formatting.subset")
            }
            if state.isPastingFormatting {
                Button("Cancel Formatting Paste", action: state.cancelFormattingTransfer)
                    .accessibilityIdentifier("inspector.formatting.cancel")
            }
            Text(state.formattingTransferStatus).font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Formatting status").accessibilityValue(state.formattingTransferStatus)
                .accessibilityIdentifier("inspector.formatting.status")
        }
        .contextMenu { FormattingTransferMenuActions(state: state) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.formatting.controls")
    }
}

private struct DesignInspectorFieldsView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var hexFocused: Bool
    @FocusState private var opacityFocused: Bool
    @FocusState private var borderWidthFocused: Bool
    @FocusState private var radiusFocused: Bool
    @FocusState private var paddingFocused: Bool
    @FocusState private var shadowFocused: Bool
    @FocusState private var typographyFocusedField: TypographyDraftField?
    private enum LegacyDesignField: CaseIterable, Hashable { case fill, borderWidth, radius, padding, shadow, foreground }
    @State private var legacyDrafts: [LegacyDesignField: InspectorTextDraftState] = [:]
    @State private var opacityDraft = ""
    @State private var opacityEdit: LayoutInspectorNumericDraft?
    @State private var opacityEditContext: ResponsiveInspectorEditContext?
    @State private var fontFamilyDraft = ""
    @State private var fontSizeDraft = ""
    @State private var lineHeightDraft = ""
    @State private var trackingDraft = ""
    @State private var typographyDrafts: [TypographyDraftField: LayoutInspectorNumericDraft] = [:]
    @State private var installedFamilies: [InstalledTypographyFamily] = []
    @State private var choosingFont = false
    @FocusState private var fontSearchFocused: Bool
    @State private var fontSearch = ""
    @State private var fontChoiceContext: ResponsiveInspectorEditContext?
    @State private var message: String?
    @State private var imageFocalXDraft = ""
    @State private var imageFocalYDraft = ""
    @State private var imageAltDraft = ""
    @State private var imageDrafts: [ImageInspectorDraftField: ImageInspectorDraft] = [:]
    @FocusState private var imageFocusedField: ImageInspectorDraftField?
    @State private var tokenNameDraft = ""
    @State private var tokenColorDraft = ""
    @State private var editingTokenID: ColorTokenID?
    @State private var tokenTarget: LocalColorTarget = .fill
    @State private var creatingToken = false
    @State private var tokenDraftRevision: UInt64 = 0

    init(state: WorkspaceShellState) {
        self.state = state
        _tokenTarget = State(initialValue: LocalColorTarget.initialInspectorTarget(
            for: state.selectedCanonicalNodes.map(\.kind)))
    }
    private var usesTextColorContext: Bool {
        LocalColorTarget.initialInspectorTarget(for: state.selectedCanonicalNodes.map(\.kind)) == .textForeground
    }

    /// Includes the current revision and is used to reject a command queued
    /// from a control update after another transaction or selection has won.
    private var selectionContextKey: String { state.geometryInspectorSelectionKey }

    /// Intentionally excludes revision so the successful transaction can
    /// refresh its local draft strings after it advances the document.
    private var selectionIdentityKey: String {
        state.documentSession.document.id.description + ":" + (state.effectiveSelectedPageID?.description ?? "no-page")
            + ":" + state.selectionState.orderedIDs.map(\.description).joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            imageControls
            imageFillControls
            if state.selectedCanonicalNodes.contains(where: { $0.kind.isTextual }) {
                GroupBox("Essentials") {
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                        if state.selectedCanonicalNodes.count == 1,
                           let text = state.selectedCanonicalNodes.first, text.kind == .text {
                            Button("Edit Text") { _ = state.beginTextEditing(nodeID: text.id, provenance: .pointer) }
                                .disabled(!state.pageEditingIsAvailable)
                                .accessibilityHint("Edit on the canvas using the same native editor. Escape cancels without changing committed text.")
                                .accessibilityIdentifier("inspector.essentials.editText")
                        }
                        if !state.selectedLinkControls.isEmpty {
                            ControlInspectorFieldsView(state: state, interactions: false, presentationID: "inspector.essentials.label")
                                .id("essential-label:" + selectionIdentityKey)
                        }
                        GeometryInspectorFieldsView(state: state, dimensionsOnly: true)
                            .id("essential-size:" + state.geometryInspectorSelectionKey)
                    }
                }
                .accessibilityIdentifier("inspector.essentials")
                typographyControls
                if usesTextColorContext {
                    GroupBox("Text Colors") { colorTokenControls }
                }
                if !state.selectedLinkControls.isEmpty {
                    GroupBox("Destination") {
                        ControlInspectorFieldsView(state: state, interactions: true, presentationID: "inspector.essentials.target")
                            .id("essential-target:" + selectionIdentityKey)
                    }
                }
            }
            GroupBox(state.isInspectingPageBackground ? "Page Background" : "Appearance") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            if state.isInspectingPageBackground {
                Text(state.pageBackgroundSummary).font(.caption)
                    .accessibilityValue(state.pageBackgroundSummary)
                    .accessibilityIdentifier("inspector.pageBackground.value")
                Text("Applies to the page, not its child Sections. Use the shared fill layers and color tokens below.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let reason = state.pageBackgroundUnavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Transparent / None") {
                    let expected = selectionContextKey
                    DispatchQueue.main.async {
                        guard selectionContextKey == expected, state.isInspectingPageBackground else { return }
                        _ = state.commitDesignFillLayer(.clearAll, operation: "page-background-none")
                    }
                }
                .help("Remove this Root's fill layers and fill-token binding in one undoable edit. Other styles and child fills stay unchanged.")
                .accessibilityIdentifier("inspector.pageBackground.none")
                Divider()
            }
            let fill = state.designInspectorFillValue()
            let fillIsApplicable = state.canEditDesignSolidFill
            let fillIsEditable = fillIsApplicable && !state.hasBoundColorTokenSelection
            InspectorField("Solid fill") {
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                NativeDesignColorWell(
                    color: resolvedColor(fill),
                    isEnabled: fillIsEditable,
                    accessibilityValue: fillAccessibility(fill),
                    accessibilityHint: state.hasBoundColorTokenSelection
                        ? "Unbind the color token before editing a literal fill."
                        : fillIsApplicable
                        ? "Open the native color panel to commit a solid fill."
                        : unavailableHint(fill),
                    onCommit: { color in scheduleFillCommit(color, provenance: .picker) }
                )
                .frame(width: 48, height: 26)
                TextField("Hexadecimal fill", text: legacyDraftBinding(.fill))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .disabled(!fillIsEditable)
                    .focused($hexFocused)
                    .onSubmit { commitHex() }
                    .onChange(of: hexFocused) { old, current in
                        if old && !current { DispatchQueue.main.async { guard !hexFocused else { return }; commitHex() } }
                    }
                    .accessibilityLabel("Solid fill hexadecimal RGBA")
                    .accessibilityValue(InspectorDraftAccessibility.value(draft: legacyDrafts[.fill]?.text, committed: fillAccessibility(fill)))
                    .accessibilityHint(state.hasBoundColorTokenSelection ? "Unbind the color token before editing a literal fill." : fillIsApplicable ? "Enter #RRGGBB or #RRGGBBAA and press Return to commit." : unavailableHint(fill))
                    .accessibilityIdentifier("inspector.design.fillHex")
            }
                Button("Remove") {
                    scheduleFillCommit(nil, provenance: .picker)
                }
                    .disabled(!fillIsEditable)
                    .accessibilityLabel("Remove solid fill")
                    .accessibilityHint(state.hasBoundColorTokenSelection ? "Unbind the color token before removing the literal fill." : fillIsApplicable ? "Remove the authored fill without restoring a legacy default." : unavailableHint(fill))
                    .accessibilityIdentifier("inspector.design.fillRemove")
            }
            Text(provenanceText(fill))
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.design.fillProvenance")
            if !usesTextColorContext { colorTokenControls }
            Text(state.reusableAppearanceSource(.fill)).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(state.reusableAppearanceSource(.fill))
                .accessibilityIdentifier("inspector.design.fillSource")
            let opacity = state.designInspectorOpacityValue()
            let opacityIsApplicable = !isUnavailable(opacity)
            InspectorField("Opacity (%)") {
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                TextField("Opacity", text: Binding(get: { opacityDraft }, set: { next in
                    guard next != opacityDraft else { return }
                    if opacityEdit == nil {
                        opacityEdit = .init(text: next, committed: opacityDraft, scope: state.layoutInspectorDraftScope)
                        opacityEditContext = state.responsiveInspectorEditContext
                    } else { opacityEdit?.text = next }
                    opacityDraft = next
                }))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit()
                    .disabled(!opacityIsApplicable)
                    .focused($opacityFocused)
                    .onSubmit { commitOpacity() }
                    .onChange(of: opacityFocused) { old, current in
                        if old && !current, let draft = opacityEdit {
                            let context = opacityEditContext
                            DispatchQueue.main.async {
                                guard !opacityFocused, opacityEdit == draft, opacityEditContext == context else { return }
                                commitOpacity()
                            }
                        }
                    }
                    .accessibilityLabel("Opacity percent")
                    .accessibilityValue(InspectorDraftAccessibility.value(draft: opacityEdit?.text, committed: opacityAccessibility(opacity)))
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
            }
            Text(state.reusableAppearanceSource(.opacity)).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(state.reusableAppearanceSource(.opacity))
                .accessibilityIdentifier("inspector.design.opacitySource")
            if let message { Text(message).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("inspector.design.validation") }
            Text(state.lastDesignInspectorAnnouncement).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("inspector.design.announcement")
            if state.hasBoundColorTokenSelection {
                Text("Unbind the color token to edit fill layers.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            }
            }
            FillLayerListInspectorView(state: state)
                .disabled(state.hasBoundColorTokenSelection)
            if !state.isInspectingPageBackground {
            AdvancedStyleInspectorView(state: state).modifier(SiteForgeInspectorSectionSurface())
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) { semanticElementControls }
                .modifier(SiteForgeInspectorSectionSurface())
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) { boxStyleControls }
                .modifier(SiteForgeInspectorSectionSurface())
                .id("inspector.design.boxStyle")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Design appearance")
        .accessibilityIdentifier("inspector.design.fields")
        .disabled(state.isInspectingPageBackground && state.pageBackgroundUnavailableReason != nil)
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted else { return }
            if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true {
                request.reject(); return
            }
            if request.requiresCleanEditors {
                if !imageDrafts.isEmpty || !typographyDrafts.isEmpty || opacityEdit != nil
                    || choosingFont || creatingToken || editingTokenID != nil
                    || legacyDrafts.values.contains(where: { $0.isDirty || $0.isConflicted }) { request.reject() }
                return
            }
            if legacyDrafts.values.contains(where: \.isConflicted) {
                message = AuthoringLanguage.staleDraft; request.reject(); return
            }
            // Save/Preview may commit a valid owned draft; clean-only repair
            // navigation above must never take this path.
            for field in LegacyDesignField.allCases where legacyDrafts[field]?.isDirty == true {
                switch field {
                case .fill: commitHex(immediately: true)
                case .borderWidth: commitBorder(currentBoxStyle)
                case .radius: commitRadius()
                case .padding: commitPadding()
                case .shadow: commitShadow(currentBoxStyle)
                case .foreground: commitTextForeground(provenance: .focusLoss)
                }
                if legacyDrafts[field]?.isDirty == true || legacyDrafts[field]?.isConflicted == true {
                    request.reject(); return
                }
            }
            if opacityEdit != nil, !commitOpacityForWorkspaceAction() { request.reject(); return }
            if imageDrafts[.alt] != nil { commitImageDraft(.alt) }
            if imageDrafts[.focalX] != nil || imageDrafts[.focalY] != nil { commitImageDraft(.focalX) }
            if !imageDrafts.isEmpty { request.reject(); return }
            if typographyDrafts[.family] != nil { commitFontFamily(provenance: .focusLoss) }
            for field in [TypographyDraftField.size, .lineHeight, .tracking] where typographyDrafts[field] != nil {
                commitTypographyNumber(field, provenance: .focusLoss)
            }
            if !typographyDrafts.isEmpty { request.reject() }
        }
        .onAppear { resetDrafts() }
        .onChange(of: selectionContextKey) { _, _ in
            // A selection command may run while the inspector is being
            // reconciled. Refresh local draft strings on the next event turn
            // and only for the current selection/revision, rather than
            // publishing view state during that reconciliation.
            scheduleDraftRefresh(for: selectionIdentityKey)
        }
        .onChange(of: state.layoutInspectorDraftScope) { _, _ in adoptTypographyDrafts() }
        .onChange(of: state.documentSession.document.revision) { _, _ in adoptTypographyDrafts() }
        .onExitCommand { legacyDrafts.removeAll(); typographyDrafts.removeAll(); opacityEdit = nil; opacityEditContext = nil; if !imageDrafts.isEmpty { state.cancelImageInspectorDraft() }; imageDrafts.removeAll(); imageFocusedField = nil; resetDrafts(); cancelTokenDraft(); state.cancelDesignInspectorDraft(); state.clearWorkspaceActionNotice() }
    }

    @ViewBuilder private var colorTokenControls: some View {
        Divider()
        HStack {
            Text("Color Tokens").font(.headline)
            Spacer()
            Button("New Color Token") {
                editingTokenID = nil; creatingToken = true
                tokenNameDraft = "New Color"; tokenColorDraft = "#4060A0FF"
                tokenDraftRevision = state.localColorTokenRevision
            }
            .accessibilityIdentifier("inspector.tokens.new")
        }
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
            Text("Appearance color").font(.caption).foregroundStyle(.secondary)
            Picker("Appearance color", selection: $tokenTarget) {
                Text("Fill").tag(LocalColorTarget.fill)
                Text("Border").tag(LocalColorTarget.border)
                Text("Outer Shadow").tag(LocalColorTarget.outerShadow)
                Text("Text Foreground").tag(LocalColorTarget.textForeground)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("inspector.tokens.target")
        }
        Text(state.colorTokenTargetStatus(tokenTarget))
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("inspector.tokens.targetStatus")
        if state.localColorTokens.isEmpty {
            Text("No project color tokens. Create one to reuse a solid fill.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("inspector.tokens.empty")
        }
        ForEach(state.localColorTokens) { token in
            Button {
                editingTokenID = token.id; creatingToken = false
                tokenNameDraft = token.name; tokenColorDraft = token.color.hexadecimalRGBA
                tokenDraftRevision = state.localColorTokenRevision
            } label: {
                HStack {
                    Circle().fill(Color(red: token.color.red, green: token.color.green, blue: token.color.blue, opacity: token.color.alpha))
                        .frame(width: 14, height: 14)
                    Text(token.name).lineLimit(1)
                    Spacer()
                    Text(token.color.hexadecimalRGBA).monospacedDigit().font(.caption2)
                }
                // Plain-button spacer pixels must activate the same token
                // as its text and accessibility action, not fall through.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color token \(token.name)")
            .accessibilityValue(token.color.hexadecimalRGBA)
            .accessibilityIdentifier("inspector.tokens.row.\(token.id.description)")
        }
        if creatingToken || editingTokenID != nil {
            HStack {
                TextField("Token name", text: $tokenNameDraft)
                    .accessibilityIdentifier("inspector.tokens.name")
                TextField("RGBA", text: $tokenColorDraft)
                    .accessibilityIdentifier("inspector.tokens.color")
            }
            HStack {
                Button("Apply") { applyTokenDraft() }
                    .accessibilityIdentifier("inspector.tokens.apply")
                Button("Cancel") { cancelTokenDraft() }
                    .accessibilityIdentifier("inspector.tokens.cancel")
                if let id = editingTokenID {
                    Button("Delete") {
                        if state.commitLocalColorToken(.delete(id), expectedRevision: state.localColorTokenRevision) {
                            cancelTokenDraft()
                        }
                    }.accessibilityIdentifier("inspector.tokens.delete")
                }
            }
        }
        if let id = editingTokenID {
            HStack {
                Button("Bind Token") {
                    _ = state.commitLocalColorToken(.bindTarget(id, tokenTarget), expectedRevision: state.localColorTokenRevision)
                }
                .disabled(state.colorTokenTargetStatus(tokenTarget).hasPrefix("No applicable") || state.selectionState.isEmpty)
                .accessibilityLabel("Bind token to \(tokenTarget.rawValue) color")
                .accessibilityIdentifier("inspector.tokens.bind")
                Button("Unbind") {
                    _ = state.commitLocalColorToken(.unbindTarget(tokenTarget), expectedRevision: state.localColorTokenRevision)
                }
                .disabled(state.selectedColorTokenStatus(target: tokenTarget) == nil)
                .accessibilityLabel("Unbind \(tokenTarget.rawValue) color token")
                .accessibilityIdentifier("inspector.tokens.unbind")
            }
        }
        if let status = state.selectedColorTokenStatus(target: tokenTarget) {
            Text(status).font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.tokens.bindingStatus")
        }
    }

    private func applyTokenDraft() {
        guard let color = CanonicalSolidColor.parse(hexadecimal: tokenColorDraft),
              tokenColorDraft.hasPrefix("#") else {
            message = LocalColorTokenCommandError.invalid.localizedDescription
            return
        }
        let edit: LocalColorTokenEdit = if let id = editingTokenID {
            .update(id, name: tokenNameDraft, color: color)
        } else { .create(name: tokenNameDraft, color: color) }
        guard state.commitLocalColorToken(edit, expectedRevision: tokenDraftRevision) else {
            message = state.lastDesignInspectorAnnouncement
            return
        }
        tokenDraftRevision = state.localColorTokenRevision
        if creatingToken { editingTokenID = state.localColorTokens.last?.id; creatingToken = false }
        message = nil
    }

    private func cancelTokenDraft() {
        editingTokenID = nil; creatingToken = false
        tokenNameDraft = ""; tokenColorDraft = ""
        message = nil
    }

    private func resolvedColor(_ value: DesignInspectorValue) -> CanonicalSolidColor {
        if case .single(let color, _) = value { return color }
        return .legacySurface
    }

    private func resolvedOpacityPercent(_ value: DesignInspectorOpacityValue) -> Double {
        if case .single(let opacity, _) = value { return opacity * 100 }
        return 100
    }
    private var currentBoxStyle: CanonicalBoxStyle? {
        if case .single(let style, _) = state.designInspectorBoxStyleValue() { return style }
        return nil
    }
    private func committedLegacyText(_ field: LegacyDesignField) -> String {
        switch field {
        case .fill:
            if case .single(let color, _) = state.designInspectorFillValue() { return color.hexadecimalRGBA }
            return ""
        case .foreground: return state.textForegroundInspectorColor()?.hexadecimalRGBA ?? ""
        case .borderWidth: return currentBoxStyle?.border.map { String(format: "%.1f", $0.width) } ?? ""
        case .radius: return currentBoxStyle?.cornerRadius.map { String(format: "%.1f", $0) } ?? ""
        case .padding: return currentBoxStyle?.padding.map { String(format: "%.1f", $0) } ?? ""
        case .shadow:
            guard let shadow = currentBoxStyle?.shadow else { return "" }
            return String(format: "%.0f, %.0f, %.0f, %.0f", shadow.offsetX, shadow.offsetY, shadow.blur, shadow.spread)
        }
    }
    private func legacyText(_ field: LegacyDesignField) -> String {
        legacyDrafts[field]?.text ?? committedLegacyText(field)
    }
    private var hexDraft: String { legacyText(.fill) }
    private var borderWidthDraft: String { legacyText(.borderWidth) }
    private var radiusDraft: String { legacyText(.radius) }
    private var paddingDraft: String { legacyText(.padding) }
    private var shadowDraft: String { legacyText(.shadow) }
    private var textForegroundDraft: String { legacyText(.foreground) }
    private func legacyDraftBinding(_ field: LegacyDesignField) -> Binding<String> {
        Binding(get: { legacyText(field) }, set: { text in
            if var draft = legacyDrafts[field] { draft.text = text; legacyDrafts[field] = draft }
            else if text != committedLegacyText(field) {
                legacyDrafts[field] = .init(text: text, committed: committedLegacyText(field),
                    context: state.responsiveInspectorEditContext)
            }
        })
    }
    private func validatedLegacyDraft(_ field: LegacyDesignField) -> InspectorTextDraftState? {
        guard var draft = legacyDrafts[field], draft.isDirty || draft.isConflicted else { return nil }
        guard (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true else {
            message = "Finish composing text, or press Escape to cancel, before applying this value."; return nil
        }
        draft.adopt(committed: committedLegacyText(field), context: state.responsiveInspectorEditContext)
        legacyDrafts[field] = draft
        guard draft.canCommit(in: state.responsiveInspectorEditContext) else {
            message = AuthoringLanguage.staleDraft; return nil
        }
        return draft
    }

    private func resetDrafts() {
        if imageDrafts.isEmpty {
            let image = state.imageInspectorSelection
            imageFocalXDraft = (image?.focalX).map { String(format: "%.0f", $0 * 100) } ?? ""
            imageFocalYDraft = (image?.focalY).map { String(format: "%.0f", $0 * 100) } ?? ""
            imageAltDraft = image?.altText ?? ""
        }
        if opacityEdit == nil {
            switch state.designInspectorOpacityValue() {
            case .single(let value, _): opacityDraft = String(format: "%.0f", value * 100)
            case .mixed, .unavailable: opacityDraft = ""
            }
        }
        if let opacityEditContext, opacityEditContext != state.responsiveInspectorEditContext {
            message = "Opacity draft belongs to an earlier selection or revision. Press Escape to reload the current value."
        } else if imageDrafts.values.contains(where: { !$0.canCommit(in: state.responsiveInspectorEditContext) }) {
            message = "Image draft belongs to an earlier selection or revision. Press Escape to reload the current values."
        } else if !imageDrafts.isEmpty || legacyDrafts.values.contains(where: { $0.isDirty || $0.isConflicted }) {
            // Invalid/incomplete drafts remain visible until corrected/cancelled.
        } else if opacityEdit == nil { message = nil }
        switch state.typographyInspectorValue() {
        case .single(let typography, _):
            fontFamilyDraft = typography.family
            fontSizeDraft = Self.formatTypographyNumber(typography.size)
            lineHeightDraft = Self.formatTypographyNumber(typography.lineHeight)
            trackingDraft = Self.formatTypographyNumber(typography.tracking)
        case .mixed, .unavailable:
            fontFamilyDraft = ""; fontSizeDraft = ""; lineHeightDraft = ""; trackingDraft = ""
        }
        for field in LegacyDesignField.allCases {
            legacyDrafts[field]?.adopt(committed: committedLegacyText(field), context: state.responsiveInspectorEditContext)
        }
        if legacyDrafts.values.contains(where: \.isConflicted) { message = AuthoringLanguage.staleDraft }
    }

    @ViewBuilder
    private var imageFillControls: some View {
        if !state.imageFillSelection.isEmpty {
            GroupBox("Image Fill") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                Text(state.imageFillInspectorStatus())
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.imageFill.status")
                    .accessibilityValue(state.imageFillInspectorStatus())
                ImageUseActionsView(state: state, target: .fill,
                    currentAssetID: state.selectedCanonicalNodes.first.flatMap(CanonicalImageFill.resolve)?.assetID,
                    identifier: "inspector.imageFill")
                HStack {
                    Picker("Mode", selection: Binding(
                        get: { state.imageFillMode() ?? .fill },
                        set: { _ = state.commitImageFillEdit(.setMode($0)) }
                    )) {
                        Text("Fill").tag(ImageFitMode.fill)
                        Text("Fit").tag(ImageFitMode.fit)
                    }
                    .disabled(state.imageFillMode() == nil)
                    .accessibilityIdentifier("inspector.imageFill.mode")
                    Button("Remove") { _ = state.commitImageFillEdit(.remove) }
                        .disabled(state.imageFillMode() == nil)
                        .accessibilityIdentifier("inspector.imageFill.remove")
                }
            }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inspector.imageFill")
        }
    }

    @ViewBuilder
    private var imageControls: some View {
        if let image = state.imageInspectorSelection {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                Text("Image").font(.headline)
                if image.applicableCount > 1 || image.skippedCount > 0 {
                    Text("\(image.applicableCount) Images · \(image.skippedCount) incompatible skipped. Mixed fields stay blank; edits apply only to selected Images.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.image.mixed")
                }
                if let asset = state.documentSession.document.imageAssets.first(where: { $0.id == image.assetID }) {
                HStack(spacing: SiteForgeVisualSystem.controlInset) {
                    Group {
                        if let data = state.imageAssetThumbnail(asset.id), let thumbnail = NSImage(data: data) {
                            Image(nsImage: thumbnail).resizable().scaledToFit()
                        } else {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .frame(width: 48, height: 40)
                    .background(SiteForgeVisualSystem.fieldSurface, in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.rowCornerRadius))
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.hairlineSpacing) {
                        Text(asset.displayName).lineLimit(1)
                        Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(asset.originalFilename).font(.caption2).lineLimit(1).help(asset.originalFilename)
                            .accessibilityIdentifier("inspector.image.source.filename")
                    }
                    Spacer()
                }
                } else {
                    Text(image.assetID == nil ? "Mixed image assets" : "Missing image asset metadata; reference retained")
                        .font(.caption).accessibilityIdentifier("inspector.image.assetSummary")
                }
                Text(state.imageInspectorResourceStatus).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(state.imageInspectorResourceStatus)
                    .accessibilityIdentifier("inspector.image.resourceStatus")
                ImageUseActionsView(state: state, target: .image, currentAssetID: image.assetID, identifier: "inspector.image")
                Text("Fit Mode")
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("inspector.image.fit.label")
                Picker("Fit Mode", selection: Binding(
                    get: { image.fit },
                    set: { if let value = $0 { scheduleImageInspectorEdit(.fit(value)) } }
                )) {
                    if image.fit == nil { Text("Mixed").tag(ImageFitMode?.none) }
                    ForEach(ImageFitMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("inspector.image.fit")
                Text("Fit preserves the whole image; Fill crops at the focal point; Stretch fills the bounds. Original bytes and layout are unchanged.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                    Text("Focal").frame(width: 42, alignment: .leading)
                    TextField(image.focalX == nil ? "Mixed X %" : "X %", text: imageDraftBinding(.focalX))
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit()
                        .focused($imageFocusedField, equals: .focalX)
                        .onSubmit { commitImageDraft(.focalX) }
                        .accessibilityLabel("Image focal point X percent")
                        .accessibilityValue(InspectorDraftAccessibility.value(draft: imageDrafts[.focalX]?.text,
                            committed: image.focalX.map { String(format: "%.0f", $0 * 100) } ?? "Mixed values"))
                        .accessibilityIdentifier("inspector.image.focalX")
                    TextField(image.focalY == nil ? "Mixed Y %" : "Y %", text: imageDraftBinding(.focalY))
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit()
                        .focused($imageFocusedField, equals: .focalY)
                        .onSubmit { commitImageDraft(.focalY) }
                        .accessibilityLabel("Image focal point Y percent")
                        .accessibilityValue(InspectorDraftAccessibility.value(draft: imageDrafts[.focalY]?.text,
                            committed: image.focalY.map { String(format: "%.0f", $0 * 100) } ?? "Mixed values"))
                        .accessibilityIdentifier("inspector.image.focalY")
                    Button("Reset") {
                        scheduleImageInspectorEdit(.focal(x: 0.5, y: 0.5))
                    }
                    .fixedSize().accessibilityIdentifier("inspector.image.focalReset")
                }
                Text(image.fit == .fill ? "Focal point is active in Fill mode." : "Focal point is retained and used in Fill mode.")
                    .font(.caption2).foregroundStyle(.secondary)
                TextField(image.altText == nil ? "Mixed alternative text" : "Alternative text", text: imageDraftBinding(.alt))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                    .disabled(image.decorative != false)
                    .focused($imageFocusedField, equals: .alt)
                    .onSubmit { commitImageDraft(.alt) }
                    .accessibilityLabel("Image alternative text")
                    .accessibilityValue(InspectorDraftAccessibility.value(draft: imageDrafts[.alt]?.text,
                        committed: image.altText ?? "Mixed values"))
                    .accessibilityIdentifier("inspector.image.alt")
                if let decorative = image.decorative {
                    Toggle("Decorative image", isOn: Binding(
                        get: { decorative }, set: { scheduleImageInspectorEdit(.decorative($0)) }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityHint("Decorative images use empty authored alt text; the stored description is retained for restoration.")
                    .accessibilityIdentifier("inspector.image.decorative")
                } else {
                    Picker("Image meaning", selection: Binding<Bool?>(get: { nil }, set: {
                        if let value = $0 { scheduleImageInspectorEdit(.decorative(value)) }
                    })) {
                        Text("Mixed").tag(Bool?.none)
                        Text("Informative").tag(Optional(false))
                        Text("Decorative").tag(Optional(true))
                    }.accessibilityIdentifier("inspector.image.decorative")
                }
                Text(image.decorative == false
                     ? "Describe informative images. Empty text is not the same as explicitly marking an image decorative."
                     : "Choose Informative to edit descriptions. Decorative status does not delete the stored description.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !imageDrafts.isEmpty {
                    HStack {
                        Button("Apply Image Draft") { commitImageDraft(imageDrafts[.alt] != nil ? .alt : .focalX) }
                            .accessibilityIdentifier("inspector.image.applyDraft")
                        Button("Cancel Image Draft") { imageDrafts.removeAll(); state.cancelImageInspectorDraft(); resetDrafts() }
                            .accessibilityIdentifier("inspector.image.cancelDraft")
                    }.controlSize(.small)
                }
                Text(state.lastImageInspectorAnnouncement)
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.image.status")
                Divider()
            }
            .padding(.horizontal, SiteForgeVisualSystem.controlInset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inspector.image.fields")
            .onChange(of: imageFocusedField) { old, current in
                guard let old, old != current, let draft = imageDrafts[old] else { return }
                DispatchQueue.main.async {
                    guard imageFocusedField != old, imageDrafts[old] == draft else { return }
                    // X/Y comprise one edit; allow native traversal between
                    // the two fields without committing half of a mixed pair.
                    if old != .alt, (current == .focalX || current == .focalY) { return }
                    commitImageDraft(old)
                }
            }
        }
    }

    private func imageDraftBinding(_ field: ImageInspectorDraftField) -> Binding<String> {
        Binding(get: {
            switch field { case .focalX: imageFocalXDraft; case .focalY: imageFocalYDraft; case .alt: imageAltDraft }
        }, set: { text in
            let previous: String = switch field { case .focalX: imageFocalXDraft; case .focalY: imageFocalYDraft; case .alt: imageAltDraft }
            guard text != previous else { return }
            if imageDrafts[field] == nil {
                imageDrafts[field] = .init(text: text, openingText: previous, context: state.responsiveInspectorEditContext)
            } else { imageDrafts[field]?.text = text }
            switch field { case .focalX: imageFocalXDraft = text; case .focalY: imageFocalYDraft = text; case .alt: imageAltDraft = text }
        })
    }

    private func commitImageDraft(_: ImageInspectorDraftField) {
        let fields: [ImageInspectorDraftField] = [.focalX, .focalY, .alt]
        let drafts = fields.compactMap { imageDrafts[$0] }
        guard let first = drafts.first else { return }
        guard drafts.allSatisfy({ $0.context == first.context && $0.canCommit(in: state.responsiveInspectorEditContext) }) else {
            message = "Image draft is stale. Press Escape to reload the current selection."
            return
        }
        if drafts.allSatisfy(\.isUnchanged) {
            for field in fields { imageDrafts[field] = nil }; resetDrafts(); return
        }
        guard let selection = state.imageInspectorSelection else { return }
        let edit: ImageInspectorEdit
        do {
            edit = try selection.detailsEdit(focalXDraft: imageDrafts[.focalX]?.text,
                focalYDraft: imageDrafts[.focalY]?.text, altDraft: imageDrafts[.alt]?.text)
        } catch {
            message = ImageInspectorError.invalidFocalPoint.localizedDescription; return
        }
        if state.commitImageInspectorEdit(edit, expectedContext: first.context) {
            for field in fields { imageDrafts[field] = nil }
            scheduleDraftRefresh(for: selectionIdentityKey)
        } else {
            message = state.imageInspectorFailure?.localizedDescription
        }
    }

    /// Native segmented controls publish their new selection during SwiftUI's
    /// control reconciliation. Compile the canonical command on the next
    /// main-actor turn and only if the selected scene/revision is unchanged.
    private func scheduleImageInspectorEdit(_ edit: ImageInspectorEdit) {
        guard imageDrafts.isEmpty else {
            message = "Apply or cancel the Image draft before changing another image property."; return
        }
        let expectedContext = state.responsiveInspectorEditContext
        Task { @MainActor in
            await Task.yield()
            guard state.commitImageInspectorEdit(edit, expectedContext: expectedContext) else {
                message = state.imageInspectorFailure?.localizedDescription; return
            }
            scheduleDraftRefresh(for: selectionIdentityKey)
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
        provenance: DesignInspectorProvenance,
        draft: InspectorTextDraftState? = nil
    ) {
        let expectedContext = selectionContextKey
        let expectedSelection = selectionIdentityKey
        DispatchQueue.main.async {
            guard selectionContextKey == expectedContext else { return }
            if let draft {
                guard legacyDrafts[.fill] == draft, draft.canCommit(in: state.responsiveInspectorEditContext) else { return }
            }
            guard state.commitDesignFill(color, provenance: provenance) else {
                message = state.designInspectorFailure?.localizedDescription
                return
            }
            if draft != nil { legacyDrafts[.fill] = nil }
            scheduleDraftRefresh(for: expectedSelection)
        }
    }

    private func scheduleOpacityCommit(
        _ percent: Double,
        provenance: DesignInspectorProvenance,
        draft: LayoutInspectorNumericDraft? = nil,
        context: ResponsiveInspectorEditContext? = nil
    ) {
        let expectedContext = selectionContextKey
        let expectedSelection = selectionIdentityKey
        let commandContext = context ?? state.responsiveInspectorEditContext
        DispatchQueue.main.async {
            guard selectionContextKey == expectedContext else { return }
            if let draft { guard opacityEdit == draft, opacityEditContext == commandContext else { return } }
            guard state.commitDesignOpacity(percent: percent, provenance: provenance, expectedContext: commandContext) else {
                message = state.designInspectorFailure?.localizedDescription
                return
            }
            opacityEdit = nil; opacityEditContext = nil
            scheduleDraftRefresh(for: expectedSelection)
        }
    }
    private func commitHex(immediately: Bool = false) {
        guard let draft = validatedLegacyDraft(.fill) else { return }
        guard !hexDraft.isEmpty else { message = DesignInspectorError.invalidColor.localizedDescription; return }
        guard let color = CanonicalSolidColor.parse(hexadecimal: hexDraft) else { message = DesignInspectorError.invalidColor.localizedDescription; return }
        if immediately {
            guard state.commitDesignFill(color, provenance: .hexadecimal) else {
                message = state.designInspectorFailure?.localizedDescription; return
            }
            legacyDrafts[.fill] = nil
            scheduleDraftRefresh(for: selectionIdentityKey)
        } else { scheduleFillCommit(color, provenance: .hexadecimal, draft: draft) }
    }
    private func commitOpacityForWorkspaceAction() -> Bool {
        guard let draft = opacityEdit, let context = opacityEditContext else { return opacityEdit == nil }
        guard context == state.responsiveInspectorEditContext,
              draft.canCommit(in: state.layoutInspectorDraftScope) else {
            message = AuthoringLanguage.staleDraft; return false
        }
        if draft.hasUnchangedNumericValue {
            opacityEdit = nil; opacityEditContext = nil; return true
        }
        guard let value = Double(draft.text),
              state.commitDesignOpacity(percent: value, provenance: .focusLoss, expectedContext: context) else {
            message = state.designInspectorFailure?.localizedDescription ?? DesignInspectorError.invalidOpacity.localizedDescription
            return false
        }
        opacityEdit = nil; opacityEditContext = nil
        scheduleDraftRefresh(for: selectionIdentityKey)
        return true
    }
    private func commitOpacity() {
        // Merely leaving an unchanged field must not bake a linked style into
        // a local literal. Only actual typing owns a captured opacity draft.
        guard let draft = opacityEdit, let context = opacityEditContext else { return }
        guard context == state.responsiveInspectorEditContext,
              draft.canCommit(in: state.layoutInspectorDraftScope) else {
            message = DesignInspectorError.stale.localizedDescription
            return
        }
        if draft.hasUnchangedNumericValue {
            opacityEdit = nil; opacityEditContext = nil; resetDrafts()
            return
        }
        guard let value = Double(opacityDraft) else {
            message = DesignInspectorError.invalidOpacity.localizedDescription
            return
        }
        scheduleOpacityCommit(value, provenance: opacityFocused ? .keyboard : .focusLoss,
                              draft: draft, context: context)
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

    private enum TypographyDraftField: Hashable { case family, size, lineHeight, tracking, foreground }

    @ViewBuilder private var typographyControls: some View {
        let value = state.typographyInspectorValue()
        let typography: CanonicalTypography? = if case .single(let style, _) = value { style } else { nil }
        let enabled: Bool = if case .unavailable = value { false } else { true }
        GroupBox("Typography") {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
        Text(state.typographyRoleSummary)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help("Set heading level in Semantic HTML. Layout provides Exact size, Fill available space and Fit content. Font changes can reflow automatic text without changing saved geometry.")
            .accessibilityLabel("Text semantic role")
            .accessibilityValue(state.typographyRoleSummary)
            .accessibilityIdentifier("inspector.design.typography.role")
        InspectorActionLayout {
            Button("Reset") { typographyDrafts.removeAll(); commitTypography(.reset, operation: "reset") }
                .disabled(!enabled)
                .accessibilityIdentifier("inspector.design.typography.reset")
        }
        InspectorField("Font family") {
        TextField("Font family", text: typographyDraftBinding(.family, fallback: fontFamilyDraft))
            .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).disabled(!enabled)
            .focused($typographyFocusedField, equals: .family)
            .onSubmit { commitFontFamily() }
            .onChange(of: typographyFocusedField) { old, current in
                if old == .family && current != .family { DispatchQueue.main.async { commitFontFamily(provenance: .focusLoss) } }
            }
            .accessibilityLabel("Font family")
            .accessibilityValue(InspectorDraftAccessibility.value(draft: typographyDrafts[.family]?.text,
                committed: typographyAccessibility(value, component: "family")))
            .accessibilityHint(typographyHint(value))
            .accessibilityIdentifier("inspector.design.typography.family")
        }
        Button("Choose Installed Font…") {
            guard state.prepareForWorkspaceAction(.context) else {
                message = state.workspaceActionStatus
                return
            }
            message = nil
            fontChoiceContext = state.responsiveInspectorEditContext; choosingFont = true
        }.disabled(!enabled).accessibilityIdentifier("inspector.design.typography.chooseFont")
            .popover(isPresented: $choosingFont) {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    Text("Installed Font Families").font(.headline)
                    Text("Uses local installed faces only. Nothing is downloaded or packaged in website output.").font(.caption)
                    TextField("Search installed fonts", text: $fontSearch).textFieldStyle(.roundedBorder)
                        .focused($fontSearchFocused)
                        .focusedValue(\.siteforgeNativeTextEditor, fontSearchFocused ? true : nil)
                        .accessibilityIdentifier("typography.font.search")
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(InstalledTypographyCatalog.matching(fontSearch, in: installedFamilies)) { family in
                                InspectorActionLayout {
                                    Button { chooseInstalledFont(family.name, weight: nil) } label: {
                                        InspectorActionLabel(title: family.name)
                                    }
                                        .help("Use \(family.name) and retain the authored weight. Choose Weights to set both explicitly.")
                                        .accessibilityIdentifier("typography.font.choose." + family.name)
                                    Menu("Weights") {
                                        ForEach(family.weights, id: \.rawValue) { weight in
                                            Button(weight.rawValue.capitalized) { chooseInstalledFont(family.name, weight: weight) }
                                                .accessibilityLabel("Use \(family.name) \(weight.rawValue)")
                                                .accessibilityIdentifier("typography.font.face.\(family.name).\(weight.rawValue)")
                                        }
                                    }
                                    .fixedSize().disabled(family.weights.isEmpty)
                                    .accessibilityLabel("Installed upright weights for \(family.name)")
                                    .accessibilityHint("Choose a weight to apply this family and weight as one undoable edit.")
                                    .accessibilityIdentifier("typography.font.weights." + family.name)
                                }
                            }
                        }
                    }.frame(height: 240)
                    if installedFamilies.isEmpty { Text("Loading installed font metadata…").font(.caption) }
                    else if InstalledTypographyCatalog.matching(fontSearch, in: installedFamilies).isEmpty { Text("No matching installed family. The authored family field remains available.").font(.caption) }
                    Text("Family keeps the current weight. Weights applies the chosen family and installed upright weight together. Fonts are not imported or embedded.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let message {
                        Text(message).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("typography.font.validation")
                    }
                    Button("Cancel") { fontSearchFocused = false; choosingFont = false; fontChoiceContext = nil }.keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("typography.font.cancel")
                }.padding().frame(width: 320)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Installed font chooser")
                    .accessibilityIdentifier("typography.font.chooser")
                    .onExitCommand { fontSearchFocused = false; choosingFont = false; fontChoiceContext = nil }
                    .onDisappear { fontSearchFocused = false }
            }
        Text(installedWeightSummary).font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("inspector.design.typography.faces")
        InspectorColumnsLayout(minimumColumnWidth: 160, maximumColumns: 2) {
            InspectorField("Weight") {
            Picker("Weight", selection: Binding<CanonicalFontWeight?>(
                get: { typography?.weight },
                set: { if let value = $0 { commitTypography(.weight(value), operation: "weight", provenance: .picker) } }
            )) {
                if typography == nil { Text("Mixed").tag(Optional<CanonicalFontWeight>.none) }
                ForEach(CanonicalFontWeight.allCases, id: \.rawValue) { weight in
                    Text(weight.rawValue.capitalized).tag(Optional(weight)).disabled(!availableTypographyWeights.contains(weight))
                }
            }
            .labelsHidden().disabled(!enabled).accessibilityLabel("Weight")
            .accessibilityIdentifier("inspector.design.typography.weight")
            }
            InspectorField("Alignment") {
            Picker("Alignment", selection: Binding<CanonicalTextAlignment?>(
                get: { typography?.alignment },
                set: { if let value = $0 { commitTypography(.alignment(value), operation: "alignment", provenance: .picker) } }
            )) {
                if typography == nil { Text("Mixed").tag(Optional<CanonicalTextAlignment>.none) }
                ForEach(CanonicalTextAlignment.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag(Optional($0)) }
            }
            .labelsHidden().disabled(!enabled)
            .accessibilityLabel("Paragraph alignment")
            .accessibilityIdentifier("inspector.design.typography.alignment")
            }
        }
        InspectorColumnsLayout {
            typographyNumberField("Size", text: $fontSizeDraft, field: .size, value: typography?.size)
            typographyNumberField("Line height", text: $lineHeightDraft, field: .lineHeight, value: typography?.lineHeight)
            typographyNumberField("Tracking", text: $trackingDraft, field: .tracking, value: typography?.tracking)
        }
        if state.selectedCanonicalNodes.contains(where: {
            CanonicalFluidValueCodec.value(for: .fontSize, node: $0) != nil || CanonicalFluidValueCodec.value(for: .lineHeight, node: $0) != nil
        }) {
            Text("Base typography values. Existing fluid size/line-height rules still win where authored; this edit does not remove them.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inspector.design.typography.responsiveSource")
        }
        Text(state.effectiveTypographySummary)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Effective responsive typography")
            .accessibilityValue(state.effectiveTypographySummary)
            .accessibilityIdentifier("inspector.design.typography.effective")
        Button("Smooth Scaling in Layout…") { _ = state.selectInspectorTab(.layout) }
            .disabled(!enabled)
            .help("In Smooth scaling, choose Font Size or Line Height. Values change gradually with screen width; exact typography remains the fallback.")
            .accessibilityIdentifier("inspector.design.typography.fluid")
        Text(typographyProvenance(value))
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("inspector.design.typography.status")
        InspectorField("Text color") {
        HStack(spacing: SiteForgeVisualSystem.controlInset) {
            NativeDesignColorWell(
                color: state.textForegroundInspectorColor() ?? CanonicalSolidColor(red: 0, green: 0, blue: 0, alpha: 1),
                isEnabled: enabled && !state.hasBoundColorTokenSelection(target: .textForeground),
                accessibilityValue: state.textForegroundInspectorStatus(),
                accessibilityHint: "Choose an authored whole-object foreground color; unbind a token before editing its literal.",
                accessibilityIdentifier: "inspector.design.typography.foregroundWell",
                accessibilityLabel: "Text foreground color",
                onCommit: { commitTypography(.foreground($0), operation: "foreground", provenance: .picker) }
            )
            .frame(width: 48, height: 26)
            TextField("#RRGGBBAA", text: legacyDraftBinding(.foreground))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .disabled(!enabled || state.hasBoundColorTokenSelection(target: .textForeground))
                .focused($typographyFocusedField, equals: .foreground)
                .onSubmit { commitTextForeground() }
                .onChange(of: typographyFocusedField) { old, current in
                    if old == .foreground && current != .foreground { commitTextForeground(provenance: .focusLoss) }
                }
                .onExitCommand { legacyDrafts[.foreground] = nil; message = nil }
                .accessibilityLabel("Text foreground hexadecimal color")
                .accessibilityValue(InspectorDraftAccessibility.value(draft: legacyDrafts[.foreground]?.text,
                    committed: state.textForegroundInspectorStatus()))
                .accessibilityIdentifier("inspector.design.typography.foregroundHex")
        }
            Button("Reset Color") { commitTypography(.foreground(nil), operation: "foreground reset") }
                .disabled(!enabled || state.hasBoundColorTokenSelection(target: .textForeground)
                    || state.textForegroundInspectorColor() == nil)
                .accessibilityIdentifier("inspector.design.typography.foregroundReset")
        }
        Text(state.textForegroundInspectorStatus())
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityIdentifier("inspector.design.typography.foregroundStatus")
        if let fallback = state.typographyResolutionStatus {
            Text(fallback).font(.caption2).foregroundStyle(SiteForgeVisualSystem.warning)
                .accessibilityIdentifier("inspector.design.typography.fallback")
        }
        }
        }
        .task {
            let catalog = await Task.detached(priority: .utility) { InstalledTypographyCatalog.load() }.value
            guard !Task.isCancelled else { return }
            installedFamilies = catalog
        }
    }

    private func typographyNumberField(
        _ label: String,
        text: Binding<String>,
        field: TypographyDraftField,
        value: Double?
    ) -> some View {
        let available: Bool = if case .unavailable = state.typographyInspectorValue() { false } else { true }
        return InspectorField(label) {
            TextField(label, text: typographyDraftBinding(field, fallback: text.wrappedValue))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit().disabled(!available)
                .focused($typographyFocusedField, equals: field)
                .onSubmit { commitTypographyNumber(field) }
                .onChange(of: typographyFocusedField) { old, current in
                    if old == field && current != field { DispatchQueue.main.async { commitTypographyNumber(field, provenance: .focusLoss) } }
                }
                .accessibilityLabel(label)
                .accessibilityValue(InspectorDraftAccessibility.value(draft: typographyDrafts[field]?.text,
                    committed: value.map(Self.formatTypographyNumber) ?? "Mixed or unavailable"))
                .accessibilityIdentifier("inspector.design.typography.\(String(describing: field))")
        }
    }

    private var availableTypographyWeights: [CanonicalFontWeight] {
        guard !installedFamilies.isEmpty else { return [] }
        let families = state.selectedCanonicalNodes.filter { $0.kind.isTextual }.compactMap {
            TypographyCommandRegistry.resolvedTypography(for: $0)?.family
        }
        guard !families.isEmpty else { return [] }
        return CanonicalFontWeight.allCases.filter { weight in
            families.allSatisfy { name in
                // Missing authored intent resolves to System without rewriting it.
                (installedFamilies.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.weights
                    ?? installedFamilies.first { $0.name == CanonicalTypography.defaultFamily }?.weights ?? []).contains(weight)
            }
        }
    }
    private var installedWeightSummary: String {
        guard !installedFamilies.isEmpty else { return "Loading local font families and installed upright weights…" }
        guard case .single(let style, _) = state.typographyInspectorValue() else { return "Mixed typography. Weight choices are common installed traits, not the primary object's values." }
        guard let family = installedFamilies.first(where: { $0.name.caseInsensitiveCompare(style.family) == .orderedSame }) else {
            return "Authored family unavailable; name retained. Native rendering uses System fallback. Choosing an installed family is an explicit edit."
        }
        let weights = family.weights.map { $0.rawValue.capitalized }.joined(separator: ", ")
        return "Installed upright weights: \(weights)." + (family.weights.contains(style.weight) ? "" : " Authored \(style.weight.rawValue) is not a listed face; choose a listed weight explicitly. Native resolution may use a nearest face.")
    }

    private func chooseInstalledFont(_ name: String, weight: CanonicalFontWeight?) {
        guard let context = fontChoiceContext,
              let family = installedFamilies.first(where: { $0.name == name }),
              weight.map({ family.weights.contains($0) }) ?? true else {
            message = "That installed font choice is unavailable. Close the chooser and review the current selection."
            return
        }
        let edit: TypographyEdit = weight.map { .fontFace(family: name, weight: $0) } ?? .family(name)
        if commitTypography(edit, operation: weight == nil ? "font family" : "font family and weight",
            provenance: .picker, expectedContext: context) {
            typographyDrafts.removeValue(forKey: .family)
            fontSearchFocused = false
            choosingFont = false
            fontChoiceContext = nil
        }
    }
    private func typographyCommittedString(_ field: TypographyDraftField) -> String? {
        switch state.typographyInspectorValue() {
        case .single(let style, _):
            switch field {
            case .family: style.family
            case .size: Self.formatTypographyNumber(style.size)
            case .lineHeight: Self.formatTypographyNumber(style.lineHeight)
            case .tracking: Self.formatTypographyNumber(style.tracking)
            case .foreground: nil
            }
        case .mixed: ""
        case .unavailable: nil
        }
    }
    private func typographyDraftBinding(_ field: TypographyDraftField, fallback: String) -> Binding<String> {
        Binding(get: { typographyDrafts[field]?.text ?? typographyCommittedString(field) ?? fallback }, set: { value in
            let committed = typographyCommittedString(field) ?? fallback
            guard typographyDrafts[field] != nil || value != committed else { return }
            if typographyDrafts[field] == nil { typographyDrafts[field] = .init(text: value, committed: committed, scope: state.layoutInspectorDraftScope) }
            else { typographyDrafts[field]?.text = value }
            message = nil
        })
    }
    private func validatedTypographyDraft(_ field: TypographyDraftField) -> LayoutInspectorNumericDraft? {
        guard var draft = typographyDrafts[field] else { return nil }
        draft.adopt(committed: typographyCommittedString(field), scope: state.layoutInspectorDraftScope)
        typographyDrafts[field] = draft
        guard draft.canCommit(in: state.layoutInspectorDraftScope) else {
            message = AuthoringLanguage.staleDraft
            return nil
        }
        return draft
    }
    private func adoptTypographyDrafts() {
        for field in Array(typographyDrafts.keys) {
            typographyDrafts[field]?.adopt(committed: typographyCommittedString(field), scope: state.layoutInspectorDraftScope)
        }
        if typographyDrafts.values.contains(where: { $0.conflict != nil }) {
            message = AuthoringLanguage.staleDraft
        }
    }

    private func commitFontFamily(provenance: DesignInspectorProvenance = .keyboard) {
        guard let draft = validatedTypographyDraft(.family) else { return }
        if draft.text == draft.committed { typographyDrafts.removeValue(forKey: .family); return }
        let value = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value == draft.text else {
            message = TypographyCommandError.invalidValue.localizedDescription; return
        }
        if commitTypography(.family(value), operation: "font family", provenance: provenance, draftScope: draft.scope) { typographyDrafts.removeValue(forKey: .family) }
    }

    private func commitTypographyNumber(_ field: TypographyDraftField, provenance: DesignInspectorProvenance = .keyboard) {
        guard field != .foreground else { return }
        guard let draft = validatedTypographyDraft(field) else { return }
        if draft.hasUnchangedNumericValue { typographyDrafts.removeValue(forKey: field); return }
        guard case .success(let number) = GeometryInspectorNumberParser.parse(draft.text), number.isFinite else {
            message = TypographyCommandError.invalidValue.localizedDescription; return
        }
        let edit: TypographyEdit = switch field { case .size: .size(number); case .lineHeight: .lineHeight(number); case .tracking: .tracking(number); case .family: .family(draft.text); case .foreground: preconditionFailure("Foreground uses its color parser") }
        if commitTypography(edit, operation: String(describing: field), provenance: provenance, draftScope: draft.scope) { typographyDrafts.removeValue(forKey: field) }
    }

    private func commitTextForeground(provenance: DesignInspectorProvenance = .keyboard) {
        guard let draft = validatedLegacyDraft(.foreground) else { return }
        guard textForegroundDraft.hasPrefix("#"),
              let color = CanonicalSolidColor.parse(hexadecimal: textForegroundDraft) else {
            message = "Enter #RRGGBB or #RRGGBBAA; committed foreground is unchanged."
            return
        }
        if commitTypography(.foreground(color), operation: "foreground", provenance: provenance,
                            expectedContext: draft.context) { legacyDrafts[.foreground] = nil }
    }

    @discardableResult private func commitTypography(
        _ edit: TypographyEdit,
        operation: String,
        provenance: DesignInspectorProvenance = .keyboard,
        draftScope: LayoutInspectorDraftScope? = nil,
        expectedContext: ResponsiveInspectorEditContext? = nil
    ) -> Bool {
        guard state.commitTypography(edit, operation: operation, provenance: provenance,
            draftScope: draftScope, expectedContext: expectedContext) else {
            message = state.lastDesignInspectorAnnouncement
            return false
        }
        message = nil
        scheduleDraftRefresh(for: selectionIdentityKey)
        return true
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

    @ViewBuilder private var semanticElementControls: some View {
        let value = state.semanticElementInspectorValue()
        let element: SemanticHTMLElement? = if case .single(let element, _) = value { element } else { nil }
        let enabled: Bool = if case .unavailable = value { false } else { true }
        Divider()
        HStack {
            Text("Semantic HTML").font(.headline)
            Spacer()
            Button("Reset") { _ = state.commitSemanticElement(.reset, operation: "reset") }
                .disabled(!enabled)
                .accessibilityIdentifier("inspector.semantic.reset")
        }
        Picker("Element", selection: Binding(
            get: { element ?? .div },
            set: { selected in _ = state.commitSemanticElement(.set(selected), operation: "element") }
        )) {
            let choices = element.map { CanonicalSemanticElement.supportedElements(for: semanticElementKind(for: $0)) } ?? SemanticHTMLElement.allCases
            ForEach(choices, id: \.rawValue) { tag in Text("<\(tag.rawValue)>").tag(tag) }
        }
        .disabled(!enabled || isMixedSemantic(value))
        .accessibilityLabel("Semantic HTML element")
        .accessibilityValue(semanticElementAccessibility(value))
        .accessibilityHint("Choose the canonical HTML element for the selected authored object.")
        .accessibilityIdentifier("inspector.semantic.element")
        Text(semanticElementProvenance(value))
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityIdentifier("inspector.semantic.status")
    }

    // The selected element itself determines the compatible picker list. The
    // default mapping is intentionally conservative for an unavailable/mixed
    // selection; commits still revalidate each stable target in the registry.
    private func semanticElementKind(for element: SemanticHTMLElement) -> NodeKind {
        switch element {
        case .p, .h1, .h2, .h3, .h4, .h5, .h6: .text
        case .img: .image
        case .button: .button
        case .a: .link
        default: .frame
        }
    }

    private func isMixedSemantic(_ value: SemanticElementInspectorValue) -> Bool {
        if case .mixed = value { return true }
        return false
    }

    private func semanticElementAccessibility(_ value: SemanticElementInspectorValue) -> String {
        switch value {
        case .single(let element, let origin): return "<\(element.rawValue)>, \(origin == .authored ? "authored" : "defaulted")"
        case .mixed: return "Mixed values"
        case .unavailable(let reason): return reason
        }
    }

    private func semanticElementProvenance(_ value: SemanticElementInspectorValue) -> String {
        switch value {
        case .single(let element, let origin): return "\(origin == .authored ? "Authored" : "Defaulted") · <\(element.rawValue)>"
        case .mixed(let applicable, let skipped): return "Mixed semantic elements · \(applicable) editable, \(skipped) skipped"
        case .unavailable(let reason): return reason
        }
    }

    @ViewBuilder private var boxStyleControls: some View {
        let value = state.designInspectorBoxStyleValue()
        let style: CanonicalBoxStyle? = if case .single(let style, _) = value { style } else { nil }
        let enabled: Bool = if case .unavailable = value { false } else { true }
        Divider()
        Text("Border, Radius & Shadow").font(.headline)
        HStack(spacing: SiteForgeVisualSystem.controlInset) {
            NativeDesignColorWell(
                color: style?.border?.color ?? CanonicalSolidColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1),
                isEnabled: enabled && !state.hasBoundColorTokenSelection(target: .border),
                accessibilityValue: style?.border?.color.hexadecimalRGBA ?? "No border",
                accessibilityHint: state.hasBoundColorTokenSelection(target: .border)
                    ? "Unbind the border token before editing the literal color." : "Choose the authored border color.",
                accessibilityIdentifier: "inspector.design.borderColor",
                accessibilityLabel: "Border color",
                onCommit: { color in
                    let width = style?.border?.width ?? 1
                    _ = state.commitDesignBoxStyle(.border(.init(color: color, width: width, style: style?.border?.style ?? .solid)), operation: "border", provenance: .picker)
                }
            ).frame(width: 38, height: 24)
            TextField("Border width", text: legacyDraftBinding(.borderWidth))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).focused($borderWidthFocused).disabled(!enabled)
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
        HStack(spacing: SiteForgeVisualSystem.controlInset) {
            Text("Radius").frame(width: 52, alignment: .leading)
            TextField("Uniform radius", text: legacyDraftBinding(.radius))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).focused($radiusFocused).disabled(!enabled)
                .onSubmit { commitRadius() }
                .onChange(of: radiusFocused) { old, current in if old && !current { commitRadius(provenance: .focusLoss) } }
                .accessibilityLabel("Uniform corner radius in points")
                .accessibilityIdentifier("inspector.design.cornerRadius")
            Button(style?.cornerRadius == nil ? "Add" : "Remove") {
                _ = state.commitDesignBoxStyle(.cornerRadius(style?.cornerRadius == nil ? 8 : nil), operation: "corner radius", provenance: .picker)
                resetDrafts()
            }.disabled(!enabled).accessibilityIdentifier("inspector.design.cornerRadiusToggle")
        }
        if state.hasContentBoxSelection {
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                Text(AuthoringLanguage.innerSpacing).fixedSize()
                TextField("Inner spacing", text: legacyDraftBinding(.padding))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).focused($paddingFocused).disabled(!enabled)
                    .onSubmit { commitPadding() }
                    .onChange(of: paddingFocused) { old, current in if old && !current { commitPadding(provenance: .focusLoss) } }
                    .accessibilityLabel("Inner spacing on all sides in points")
                    .accessibilityIdentifier("inspector.design.contentPadding")
                Button(style?.padding == nil ? "Add" : "Reset") {
                    _ = state.commitDesignBoxStyle(.padding(style?.padding == nil ? 24 : nil), operation: "content padding", provenance: .picker)
                    resetDrafts()
                }.disabled(!enabled).accessibilityIdentifier("inspector.design.contentPaddingToggle")
            }
            Toggle("Clip content", isOn: Binding(
                get: { style?.clipsContent ?? false },
                set: { _ = state.commitDesignBoxStyle(.clipsContent($0), operation: "clip content", provenance: .accessibility) }
            ))
            .toggleStyle(.checkbox)
            .disabled(!enabled)
            .accessibilityHint("Clip child content to the selected Frame or Section bounds.")
            .accessibilityIdentifier("inspector.design.clipContent")
        }
        HStack(spacing: SiteForgeVisualSystem.controlInset) {
            NativeDesignColorWell(
                color: style?.shadow?.color ?? CanonicalSolidColor(red: 0, green: 0, blue: 0, alpha: 0.25),
                isEnabled: enabled && !state.hasBoundColorTokenSelection(target: .outerShadow),
                accessibilityValue: style?.shadow?.color.hexadecimalRGBA ?? "No shadow",
                accessibilityHint: state.hasBoundColorTokenSelection(target: .outerShadow)
                    ? "Unbind the outer-shadow token before editing the literal color." : "Choose the authored shadow color.",
                accessibilityIdentifier: "inspector.design.shadowColor",
                accessibilityLabel: "Shadow color",
                onCommit: { color in
                    let old = style?.shadow ?? .init(color: color, offsetX: 0, offsetY: 8, blur: 18, spread: 0)
                    _ = state.commitDesignBoxStyle(.shadow(.init(color: color, offsetX: old.offsetX, offsetY: old.offsetY, blur: old.blur, spread: old.spread)), operation: "shadow", provenance: .picker)
                }
            ).frame(width: 38, height: 24)
            TextField("X, Y, Blur, Spread", text: legacyDraftBinding(.shadow))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).focused($shadowFocused).disabled(!enabled)
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
        if style?.shadow != nil, state.hasContentBoxSelection {
            Toggle("Shadow enabled", isOn: Binding(
                get: { style?.shadowEnabled != false },
                set: { _ = state.commitDesignBoxStyle(.shadowEnabled($0), operation: "shadow enabled", provenance: .accessibility) }
            ))
            .toggleStyle(.checkbox)
            .disabled(!enabled)
            .accessibilityHint("Temporarily show or hide the authored outer shadow without removing its values.")
            .accessibilityIdentifier("inspector.design.shadowEnabled")
            HStack {
                Text(style?.shadowEnabled == false ? "Outer shadow disabled" : "Outer shadow enabled")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if style?.shadowEnabled != nil {
                    Button("Reset") {
                        _ = state.commitDesignBoxStyle(.shadowEnabled(nil), operation: "shadow enabled reset", provenance: .picker)
                    }
                    .disabled(!enabled)
                    .accessibilityIdentifier("inspector.design.shadowEnabledReset")
                }
            }
        }
        switch value {
        case .mixed(let applicable, let skipped): Text("Mixed box appearance across \(applicable) compatible objects; \(skipped) incompatible unchanged.").font(.caption2).foregroundStyle(.secondary)
        case .unavailable(let reason): Text(reason).font(.caption2).foregroundStyle(.secondary)
        case .single(_, let origin): Text(origin == .authored ? "Authored box appearance" : "Defaulted box appearance").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func commitBorder(_ style: CanonicalBoxStyle?, provenance: DesignInspectorProvenance = .keyboard) {
        guard validatedLegacyDraft(.borderWidth) != nil else { return }
        guard let width = Double(borderWidthDraft), width.isFinite, (0...100).contains(width) else { message = DesignBoxStyleError.invalidValue.localizedDescription; return }
        let border = CanonicalBorder(color: style?.border?.color ?? .init(red: 0.18, green: 0.20, blue: 0.24, alpha: 1), width: width, style: style?.border?.style ?? .solid)
        guard state.commitDesignBoxStyle(.border(width == 0 ? nil : border), operation: "border", provenance: provenance) else { message = state.lastDesignInspectorAnnouncement; return }
        legacyDrafts[.borderWidth] = nil
        resetDrafts()
    }

    private func commitRadius(provenance: DesignInspectorProvenance = .keyboard) {
        guard validatedLegacyDraft(.radius) != nil else { return }
        guard let radius = Double(radiusDraft), radius.isFinite, (0...10_000).contains(radius) else { message = DesignBoxStyleError.invalidValue.localizedDescription; return }
        guard state.commitDesignBoxStyle(.cornerRadius(radius), operation: "corner radius", provenance: provenance) else { message = state.lastDesignInspectorAnnouncement; return }
        legacyDrafts[.radius] = nil
        resetDrafts()
    }

    private func commitPadding(provenance: DesignInspectorProvenance = .keyboard) {
        guard validatedLegacyDraft(.padding) != nil else { return }
        guard let padding = Double(paddingDraft), padding.isFinite, (0...10_000).contains(padding) else {
            message = DesignBoxStyleError.invalidValue.localizedDescription; return
        }
        guard state.commitDesignBoxStyle(.padding(padding), operation: "content padding", provenance: provenance) else {
            message = state.lastDesignInspectorAnnouncement; return
        }
        legacyDrafts[.padding] = nil
        resetDrafts()
    }

    private func commitShadow(_ style: CanonicalBoxStyle?, provenance: DesignInspectorProvenance = .keyboard) {
        guard validatedLegacyDraft(.shadow) != nil else { return }
        guard let shadow = ShadowInspectorDraftParser.parse(shadowDraft,
            color: style?.shadow?.color ?? .init(red: 0, green: 0, blue: 0, alpha: 0.25)) else {
            message = DesignBoxStyleError.invalidValue.localizedDescription; return
        }
        guard state.commitDesignBoxStyle(.shadow(shadow), operation: "shadow", provenance: provenance) else { message = state.lastDesignInspectorAnnouncement; return }
        legacyDrafts[.shadow] = nil
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

/// Incomplete sizing input lives only in this scene. The model receives one
/// validated identity-gated transaction after Return or native focus loss.
private struct SizingInspectorFieldsView: View {
    @ObservedObject var state: WorkspaceShellState
    @FocusState private var focusedField: SizingConstraintField?
    @State private var drafts: [SizingConstraintField: LayoutInspectorNumericDraft] = [:]
    @State private var showsBounds = false
    @State private var message: String?
    @State private var conversionContext: String?
    @State private var confirmingConversion = false

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            HStack {
                Text("Size & Responsiveness").font(.headline)
                Spacer()
                Button("Reset") {
                    if state.commitSizingConstraint(.reset) { drafts.removeAll(); message = nil }
                    else { message = state.lastSizingConstraintAnnouncement }
                }
                .disabled(!state.sizingModeAvailability.isEnabled)
                .accessibilityLabel("Reset sizing constraints")
                .accessibilityIdentifier("inspector.sizing.reset")
            }
            ForEach(SizingDimension.allCases, id: \.self) { dimension in
                Picker("Base \(dimension.rawValue) mode", selection: Binding<CanonicalSizingMode?>(
                    get: { state.sizingMode(for: dimension) },
                    set: { mode in
                        guard let mode else { return }
                        if state.commitSizingConstraint(.setMode(dimension, mode)) { drafts.removeAll(); message = nil }
                        else { message = state.lastSizingConstraintAnnouncement }
                    }
                )) {
                    if state.sizingMode(for: dimension) == nil { Text("Mixed").tag(Optional<CanonicalSizingMode>.none) }
                    Text(AuthoringLanguage.sizing(.fixed)).tag(Optional(CanonicalSizingMode.fixed))
                        .disabled(!state.sizingModeAvailability(dimension, .fixed).isEnabled)
                    Text(AuthoringLanguage.sizing(.fill)).tag(Optional(CanonicalSizingMode.fill))
                        .disabled(!state.sizingModeAvailability(dimension, .fill).isEnabled)
                    if dimension == .height {
                        Text(AuthoringLanguage.sizing(.hug)).tag(Optional(CanonicalSizingMode.hug))
                            .disabled(!state.sizingModeAvailability(dimension, .hug).isEnabled)
                    }
                }
                .disabled(!state.sizingModeAvailability.isEnabled)
                .accessibilityIdentifier("inspector.sizing.\(dimension.rawValue)Mode")
                .help(state.sizingModeSource(for: dimension))
                Text(state.sizingModeSource(for: dimension)).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.sizing.\(dimension.rawValue)Mode.source")
                if let source = state.sizingDimensionResolution(dimension)?.numericSource {
                    Button(source == .fluid ? "Remove smooth \(dimension.rawValue) scaling" : "Use inherited \(dimension.rawValue)") {
                        focusedField = nil; drafts.removeAll()
                        if state.resetSizingDimensionOverride(dimension, expectedScope: state.layoutInspectorDraftScope) { message = nil }
                        else { message = "Wait for the current canvas, then retry the exact dimension reset." }
                    }.accessibilityIdentifier("inspector.sizing.\(dimension.rawValue).resetOverride")
                        .help("Remove only this custom dimension or scaling range. The next available source takes effect; other dimensions and base sizing stay unchanged.")
                }
            }
            if let reason = state.sizingModeAvailability.disabledReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            Button("Use automatic sizing…") {
                conversionContext = state.responsiveConversionContext
                confirmingConversion = true
            }
            .disabled(!state.sizingModeAvailability.isEnabled || state.responsiveConversionScope?.applicableNodeIDs.isEmpty != false)
            .accessibilityIdentifier("inspector.sizing.convertContent")
            .confirmationDialog("Change sizing for selected content and its children?", isPresented: $confirmingConversion) {
                Button("Convert to automatic sizing") {
                    guard let conversionContext else { return }
                    if state.commitSizingConstraint(.convertContent, expectedContext: conversionContext) {
                        drafts.removeAll(); message = nil
                    } else { message = state.lastSizingConstraintAnnouncement }
                    self.conversionContext = nil
                }
                Button("Cancel", role: .cancel) { conversionContext = nil }
            } message: {
                Text(state.responsiveConversionSummary + " Text and containers will Fit content and Fill available space. Maximum widths keep their current base width. This removes Width/Height screen-size customizations and Smooth scaling only on converted objects; X/Y, content, styles, links and IDs stay unchanged. Images, exact-size Buttons/Links, managed Header/Footer, empty Frames and aspect-locked objects are skipped. This is a document change, not a preview; one Undo restores exact prior values.")
            }
            DisclosureGroup("Bounds & Aspect Ratio", isExpanded: $showsBounds) {
            if let reason = state.sizingConstraintAvailability.disabledReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.sizing.availability")
            }
            ForEach(SizingConstraintField.allCases, id: \.self) { field in
                let value = state.sizingConstraintValue(for: field)
                HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                    Text(field.title).frame(width: 82, alignment: .leading).lineLimit(1)
                    TextField(field.title, text: Binding(
                        get: { drafts[field]?.text ?? display(value) },
                        set: {
                            if drafts[field] == nil && $0 == display(value) { return }
                            if drafts[field] == nil { drafts[field] = .init(text: $0, committed: display(value), scope: state.layoutInspectorDraftScope) }
                            else { drafts[field]?.text = $0 }
                            message = nil
                        }
                    ))
                    .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit()
                    .focused($focusedField, equals: field)
                    .onSubmit { commit(field) }
                    .onChange(of: focusedField) { previous, current in
                        if previous == field, current != field, drafts[field] != nil {
                            DispatchQueue.main.async { guard focusedField != field else { return }; commit(field) }
                        }
                    }
                    .disabled(!state.sizingConstraintAvailability.isEnabled)
                    .accessibilityLabel(field.title)
                    .accessibilityValue(InspectorDraftAccessibility.value(draft: drafts[field]?.text,
                        committed: accessibilityValue(value)))
                    .accessibilityHint("Enter a finite value and press Return. Empty removes this bound; Escape cancels the draft.")
                    .accessibilityIdentifier("inspector.sizing.\(field.rawValue)")
                    Text(provenance(value)).font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .trailing).lineLimit(1)
                }
            }
            Toggle("Lock aspect ratio", isOn: Binding(
                get: { state.sizingAspectEnabled ?? false },
                set: { enabled in
                    if !state.commitSizingConstraint(.setAspectEnabled(enabled)) {
                        message = state.lastSizingConstraintAnnouncement
                    } else { drafts.removeAll(); message = nil }
                }
            ))
            .disabled(!state.sizingConstraintAvailability.isEnabled)
            .accessibilityValue(state.sizingAspectEnabled.map { $0 ? "Locked" : "Unlocked" } ?? "Mixed or unavailable")
            .accessibilityIdentifier("inspector.sizing.aspectLock")
            if state.sizingAspectEnabled == nil, state.sizingConstraintAvailability.isEnabled {
                Text("Mixed aspect-lock values").font(.caption2).foregroundStyle(.secondary)
            }
            }.disclosureGroupStyle(SiteForgeInspectorDisclosureStyle(identifier: "inspector.sizing.boundsDisclosure"))
            if let message { Text(message).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                .accessibilityIdentifier("inspector.sizing.validation") }
            Text(state.lastSizingConstraintAnnouncement).font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.sizing.announcement")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sizing constraints")
        .accessibilityIdentifier("inspector.sizing.fields")
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted else { return }
            if request.requiresCleanEditors { if !drafts.isEmpty { request.reject() }; return }
            for field in SizingConstraintField.allCases where drafts[field] != nil { commit(field) }
            if !drafts.isEmpty { request.reject() }
        }
        .onExitCommand { drafts.removeAll(); focusedField = nil; message = nil; state.clearWorkspaceActionNotice() }
        .onChange(of: state.documentSession.document.revision) { _, _ in adoptDrafts() }
        .onChange(of: state.layoutInspectorDraftScope) { _, _ in adoptDrafts() }
    }

    private func display(_ value: SizingConstraintPresentation) -> String {
        if case .single(let number?, _) = value { return GeometryInspectorNumberParser.format(number) }
        return ""
    }
    private func provenance(_ value: SizingConstraintPresentation) -> String {
        switch value {
        case .single(nil, _): "Default"
        case .single(_, let origin): origin == .authored ? "Authored" : "Default"
        case .mixed: "Mixed"
        case .unavailable: "Unavailable"
        }
    }
    private func accessibilityValue(_ value: SizingConstraintPresentation) -> String {
        switch value {
        case .single(nil, _): "Default, no constraint"
        case .single(let number?, let origin): "\(GeometryInspectorNumberParser.format(number)); \(origin == .authored ? "authored" : "defaulted")"
        case .mixed: "Mixed values"
        case .unavailable(let reason): reason
        }
    }
    private func commit(_ field: SizingConstraintField) {
        guard var draft = drafts[field] else { return }
        draft.adopt(committed: display(state.sizingConstraintValue(for: field)), scope: state.layoutInspectorDraftScope)
        drafts[field] = draft
        guard draft.canCommit(in: state.layoutInspectorDraftScope) else {
            message = "Sizing context or value changed. Your draft is retained; Escape cancels it before editing the new context."
            return
        }
        if draft.hasUnchangedNumericValue { drafts.removeValue(forKey: field); message = nil; return }
        let source = draft.text
        let value: Double?
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value = nil }
        else {
            switch GeometryInspectorNumberParser.parse(source) {
            case .success(let parsed): value = parsed
            case .failure: message = "\(field.title) needs a finite numeric value."; return
            }
        }
        guard state.commitSizingConstraint(.set(field, value), draftScope: draft.scope) else {
            message = state.lastSizingConstraintAnnouncement; return
        }
        drafts.removeValue(forKey: field)
        message = nil
    }
    private func adoptDrafts() {
        for field in Array(drafts.keys) {
            drafts[field]?.adopt(committed: display(state.sizingConstraintValue(for: field)), scope: state.layoutInspectorDraftScope)
        }
        if drafts.values.contains(where: { $0.conflict != nil }) {
            message = AuthoringLanguage.staleDraft
        }
    }
}

/// Scene-local string drafts for canonical fixed-geometry fields. The view is
/// intentionally the only owner of incomplete locale input; `WorkspaceShellState`
/// receives one validated number only at the native commit boundary.
private struct PositioningInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var drafts: [PositionInsetEdge: String] = [:]
    @State private var zDraft = ""

    var body: some View {
        let value = state.selectedPositioning
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            Divider()
            Text("Positioning").font(.headline)
            Picker("Mode", selection: Binding(
                get: { value?.mode ?? .static },
                set: { _ = state.commitAdvancedStyle(.positionMode($0), operation: "Position mode", provenance: .picker) }
            )) {
                ForEach(CanonicalPositionMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .disabled(value == nil)
            .accessibilityIdentifier("inspector.layout.position.mode")
            Text("Containing block: \(state.selectedPositioningContainingBlock)")
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Containing block")
                .accessibilityValue(state.selectedPositioningContainingBlock)
                .accessibilityIdentifier("inspector.layout.position.containingBlock")
            if let value, value.mode != .static {
                ForEach(PositionInsetEdge.allCases, id: \.self) { edge in
                    HStack {
                        Text(edge.rawValue.capitalized).frame(width: 52, alignment: .leading)
                        TextField(edge.rawValue.capitalized, text: Binding(
                            get: { drafts[edge] ?? inset(edge, value: value).map { GeometryInspectorNumberParser.format($0) } ?? "" },
                            set: { drafts[edge] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit()
                        .onSubmit { commit(edge) }
                        .accessibilityHint("Enter a finite inset and press Return. Empty removes the authored inset.")
                        .accessibilityIdentifier("inspector.layout.position.\(edge.rawValue)")
                    }
                }
            }
            HStack {
                Text("Layer").frame(width: 52, alignment: .leading)
                TextField("Stacking layer", text: Binding(
                    get: { zDraft.isEmpty ? String(value?.zIndex ?? 0) : zDraft }, set: { zDraft = $0 }
                ))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit().onSubmit { commitZ() }
                .disabled(value == nil)
                .accessibilityLabel("Stacking layer")
                .accessibilityIdentifier("inspector.layout.position.zIndex")
            }
            Text(positioningProvenance(value))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onExitCommand { drafts.removeAll(); zDraft = ""; state.cancelAdvancedStyleDraft() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.layout.positioning")
    }

    private func inset(_ edge: PositionInsetEdge, value: CanonicalPositioning) -> Double? {
        switch edge { case .top: value.top; case .right: value.right; case .bottom: value.bottom; case .left: value.left }
    }

    private func positioningProvenance(_ value: CanonicalPositioning?) -> String {
        guard let value else { return "Mixed or unavailable positioning" }
        return value.origin == .authored ? "Authored positioning" : "Default static positioning"
    }

    private func commit(_ edge: PositionInsetEdge) {
        let raw = drafts[edge] ?? ""
        let value: Double?
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value = nil }
        else { guard let parsed = Double(raw), parsed.isFinite else { return }; value = parsed }
        if state.commitAdvancedStyle(.positionInset(edge, value), operation: "Position inset") { drafts[edge] = nil }
    }

    private func commitZ() {
        guard let value = Int(zDraft), state.commitAdvancedStyle(.zIndex(value), operation: "Stacking layer") else { return }
        zDraft = ""
    }
}

private struct GeometryInspectorFieldsView: View {
    @ObservedObject var state: WorkspaceShellState
    var dimensionsOnly = false
    @FocusState private var focusedField: GeometryInspectorField?
    @State private var drafts: [GeometryInspectorField: LayoutInspectorNumericDraft] = [:]
    @State private var validationMessage: String?

    var body: some View {
        GroupBox(dimensionsOnly ? "Size" : "Position & Dimensions") {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            InspectorColumnsLayout(maximumColumns: 2) {
            ForEach(GeometryInspectorField.allCases.filter { field in
                (!dimensionsOnly || field.requiresPositiveValue)
                    && ((state.selectedPageStructureNode.flatMap(CanonicalPageFlow.role) == nil && !state.hasMixedPageStructureSelection) || field == .height)
            }, id: \.self) { field in
                fieldRow(field)
            }
            }
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                Text(AuthoringLanguage.screenSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.viewportPreset.title)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("inspector.layout.breakpoint")
            }
            if state.viewportPreset != .desktop {
                Button("Use inherited size and position") {
                    _ = state.resetGeometryOverrides(provenance: .pointer)
                    restoreDrafts()
                }
                .disabled(!state.hasGeometryOverridesAtCurrentBreakpoint)
                .accessibilityLabel("Use inherited size and position at \(state.viewportPreset.title)")
                .accessibilityHint("Remove only custom size and position for this screen size. Uses Smooth scaling where set, otherwise Desktop values. Other screen sizes stay unchanged.")
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
                    .foregroundStyle(SiteForgeVisualSystem.danger)
                    .accessibilityIdentifier("inspector.layout.validation")
            }
            Text(state.lastGeometryInspectorAnnouncement)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.layout.announcement")
        }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout geometry")
        .accessibilityIdentifier("inspector.layout.geometryFields")
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted else { return }
            if request.requiresCleanEditors { if !drafts.isEmpty { request.reject() }; return }
            for field in GeometryInspectorField.allCases where drafts[field] != nil { commit(field, provenance: .pointer) }
            if !drafts.isEmpty { request.reject() }
        }
        .onChange(of: state.documentSession.document.revision) { _, _ in adoptDrafts() }
        .onChange(of: state.layoutInspectorDraftScope) { _, _ in adoptDrafts() }
        .onChange(of: state.canvasRenderPlan?.identity) { _, _ in adoptDrafts() }
        .onExitCommand {
            guard focusedField != nil || !drafts.isEmpty else { return }
            restoreDrafts()
            focusedField = nil
            state.cancelGeometryInspectorDraft()
            state.clearWorkspaceActionNotice()
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: GeometryInspectorField) -> some View {
        let value = state.geometryInspectorValue(for: field)
        let availability = state.geometryInspectorAvailability(for: field)
        InspectorField(field.title) {
            TextField(field.title, text: draftBinding(for: field, value: value))
                .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
                .monospacedDigit()
                .focused($focusedField, equals: field)
                .onSubmit { commit(field, provenance: .keyboard, useCurrentValue: true) }
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
        }
    }

    private func draftBinding(
        for field: GeometryInspectorField,
        value: GeometryInspectorValue
    ) -> Binding<String> {
        Binding(
            get: { drafts[field]?.text ?? displayValue(for: value) },
            set: {
                // Native field-editor reconciliation can write back the
                // displayed string when focus changes without any typing.
                guard drafts[field] != nil || $0 != displayValue(for: value) else { return }
                if drafts[field] == nil {
                    drafts[field] = .init(text: $0, committed: displayValue(for: value), scope: state.layoutInspectorDraftScope)
                } else { drafts[field]?.text = $0 }
                validationMessage = nil
            }
        )
    }

    @ViewBuilder
    private func provenanceLabel(for value: GeometryInspectorValue, field: GeometryInspectorField) -> some View {
        switch value {
        case .single(_, let origin):
            Text(state.geometryInspectorResponsiveSource(for: field)
                 ?? AuthoringLanguage.propertySource(origin))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel(state.geometryInspectorResponsiveSource(for: field)
                    ?? AuthoringLanguage.propertySource(origin))
        case .mixed:
            Text("Mixed").font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Mixed values")
        case .computed(_, let source):
            Text(source).font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel(source)
        case .unavailable:
            Text("Unavailable").font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Unavailable")
        }
    }

    private func displayValue(for value: GeometryInspectorValue) -> String {
        switch value {
        case .single(let value, _), .computed(let value, _): GeometryInspectorNumberParser.format(value)
        case .mixed, .unavailable: ""
        }
    }

    private func accessibilityValue(for value: GeometryInspectorValue, field: GeometryInspectorField) -> String {
        let committed: String = switch value {
        case .single(let value, let origin):
            "\(GeometryInspectorNumberParser.format(value)); \(state.geometryInspectorResponsiveSource(for: field) ?? AuthoringLanguage.propertySource(origin))"
        case .computed(let value, let source): "\(GeometryInspectorNumberParser.format(value)); \(source)"
        case .mixed: "Mixed values"
        case .unavailable(let reason): reason
        }
        return InspectorDraftAccessibility.value(draft: drafts[field]?.text, committed: committed)
    }

    private func commit(_ field: GeometryInspectorField, provenance: GeometryInspectorProvenance,
                        useCurrentValue: Bool = false) {
        // Traversing an untouched field is not authoring intent. In
        // particular, it must not promote a default to authored, advance the
        // revision or disable the next field while the renderer adopts it.
        let current = displayValue(for: state.geometryInspectorValue(for: field))
        guard var draft = drafts[field] ?? (useCurrentValue ? .init(text: current, committed: current, scope: state.layoutInspectorDraftScope) : nil) else { return }
        draft.adopt(committed: committedDisplay(for: state.geometryInspectorValue(for: field)), scope: state.layoutInspectorDraftScope)
        drafts[field] = draft
        guard draft.canCommit(in: state.layoutInspectorDraftScope) else {
            validationMessage = AuthoringLanguage.staleDraft
            return
        }
        if draft.hasUnchangedNumericValue { drafts.removeValue(forKey: field); validationMessage = nil; return }
        switch GeometryInspectorNumberParser.parse(draft.text) {
        case .success(let value):
            guard GeometryInspectorCommandRegistry.isValid(value, for: field) else {
                validationMessage = "\(field.title) must be finite and within the supported range\(field.requiresPositiveValue ? ", with a minimum of 1" : "")."
                return
            }
            guard state.commitGeometryInspectorValue(value, field: field, provenance: provenance, draftScope: draft.scope) else {
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
    private func adoptDrafts() {
        for field in Array(drafts.keys) {
            drafts[field]?.adopt(committed: committedDisplay(for: state.geometryInspectorValue(for: field)), scope: state.layoutInspectorDraftScope)
        }
        if drafts.values.contains(where: { $0.conflict != nil }) {
            validationMessage = AuthoringLanguage.staleDraft
        }
    }
    private func committedDisplay(for value: GeometryInspectorValue) -> String? {
        switch value {
        case .single, .computed: displayValue(for: value)
        case .unavailable, .mixed: nil
        }
    }
}

private enum FluidValueDraftField: Hashable { case minimum, preferred, maximum }

/// SF-0604 drafts are scene-local strings. Only a complete, monotonic triple
/// reaches the central identity-gated registry; Escape never changes content.
private struct FluidValueInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var target: FluidValueTarget = .width
    @State private var minimum = ""
    @State private var preferred = ""
    @State private var maximum = ""
    @State private var validation: String?
    @State private var draftContext: ResponsiveInspectorEditContext?
    @FocusState private var focused: FluidValueDraftField?

    var body: some View {
        let context = state.responsiveInspectorEditContext
        return VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                Text(AuthoringLanguage.smoothScaling).font(.headline)
                Picker("Smooth scaling property", selection: $target) {
                    ForEach(state.supportedFluidValueTargets, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                .accessibilityLabel("Smooth scaling property")
                .accessibilityIdentifier("inspector.layout.fluid.target")
            }
            Text(AuthoringLanguage.smoothScalingHelp)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inspector.layout.fluid.scope")
            Text(state.fluidValueEffectiveSummary(for: target))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Effective \(target.title.lowercased())")
                .accessibilityValue(state.fluidValueEffectiveSummary(for: target))
                .accessibilityIdentifier("inspector.layout.fluid.current")
            switch state.fluidValue(for: target) {
            case .single(let value, let origin, let applicable, let skipped):
                Text("\(AuthoringLanguage.propertySource(origin)) · \(applicable) compatible\(skipped == 0 ? "" : " · \(skipped) skipped")")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.layout.fluid.provenance")
                fluidFields(value, context: context)
                Button("Remove Smooth Scaling") { remove(context: context) }
                    .accessibilityHint("Remove only the scaling range. Screen-size overrides remain; otherwise the saved exact value is restored.")
                    .accessibilityIdentifier("inspector.layout.fluid.remove")
            case .mixed(let applicable, let skipped):
                Text("Mixed scaling ranges · \(applicable) compatible\(skipped == 0 ? "" : " · \(skipped) skipped")")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Use One Scaling Range…") { seedDrafts(context: context) }
                        .accessibilityIdentifier("inspector.layout.fluid.unify")
                    Button("Remove") { remove(context: context) }
                        .accessibilityLabel("Remove mixed scaling ranges")
                        .accessibilityIdentifier("inspector.layout.fluid.removeMixed")
                }
                draftFields
            case .unavailable(let reason):
                Text(reason).font(.caption).foregroundStyle(.secondary)
                Button("Add Smooth Scaling…") { seedDrafts(context: context) }
                    .accessibilityIdentifier("inspector.layout.fluid.enable")
                if draftContext != nil { draftFields }
            }
            if let validation {
                Text(validation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                    .accessibilityIdentifier("inspector.layout.fluid.validation")
            }
            Text(state.currentFluidValueAnnouncement(for: target)).font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.layout.fluid.announcement")
        }
        .onChange(of: target) { _, _ in resetDrafts() }
        .onAppear {
            if !state.supportedFluidValueTargets.contains(target), let first = state.supportedFluidValueTargets.first {
                target = first
            }
        }
        .onChange(of: focused) { previous, current in
            if previous != nil, current == nil,
               !minimum.isEmpty, !preferred.isEmpty, !maximum.isEmpty, let capturedContext = draftContext {
                let capturedTarget = target
                let capturedFields = [minimum, preferred, maximum]
                DispatchQueue.main.async {
                    guard focused == nil, draftContext == capturedContext, target == capturedTarget,
                          [minimum, preferred, maximum] == capturedFields else { return }
                    commit(.focusLoss)
                }
            }
        }
        .onChange(of: state.responsiveInspectorEditContext) { _, current in
            if let draftContext, draftContext != current {
                validation = AuthoringLanguage.staleDraft
            }
        }
        .onExitCommand { resetDrafts(); focused = nil; state.cancelFluidValueDraft(target: target) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AuthoringLanguage.smoothScaling)
        .help(AuthoringLanguage.smoothScalingHelp)
        .accessibilityIdentifier("inspector.layout.fluid")
    }

    @ViewBuilder private func fluidFields(_ value: CanonicalFluidValue, context: ResponsiveInspectorEditContext) -> some View {
        let hasDraft = draftContext != nil
        if hasDraft { draftFields }
        else {
            HStack(spacing: SiteForgeVisualSystem.controlInset) {
                valueLabel("Min", value.minimum)
                valueLabel("Preferred", value.preferred)
                valueLabel("Max", value.maximum)
            }
            Button("Edit Scaling Range…") {
                guard context == state.responsiveInspectorEditContext else { return }
                draftContext = context
                minimum = format(value.minimum); preferred = format(value.preferred); maximum = format(value.maximum)
                focused = .minimum
            }
            .accessibilityIdentifier("inspector.layout.fluid.edit")
        }
        Text("Changes gradually from 390 px through 768 px to 1440 px; stays within the minimum and maximum.")
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityIdentifier("inspector.layout.fluid.range")
    }

    private var draftFields: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            fluidField("Minimum", text: $minimum, focus: .minimum)
            fluidField("Preferred", text: $preferred, focus: .preferred)
            fluidField("Maximum", text: $maximum, focus: .maximum)
            if let preview = draftPreview {
            Text("Draft preview — Mobile \(format(preview.minimum)), Tablet \(format(preview.preferred)), Desktop \(format(preview.maximum)); not saved")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.layout.fluid.draftPreview")
            }
            HStack {
                Button("Cancel") { resetDrafts(); state.cancelFluidValueDraft(target: target) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("inspector.layout.fluid.cancel")
                Spacer()
                Button("Apply") { commit(.keyboard) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("inspector.layout.fluid.apply")
            }
        }
    }

    private func fluidField(_ label: String, text: Binding<String>, focus: FluidValueDraftField) -> some View {
        let context = state.responsiveInspectorEditContext
        return HStack {
            Text(label).frame(width: 72, alignment: .leading)
            TextField(label, text: Binding(get: { text.wrappedValue }, set: {
                if draftContext == nil { draftContext = context }
                text.wrappedValue = $0
            })).textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true).monospacedDigit()
                .focused($focused, equals: focus)
                .onSubmit { commit(.keyboard) }
                .accessibilityLabel("Smooth scaling \(target.title) \(label.lowercased())")
                .accessibilityIdentifier("inspector.layout.fluid.\(String(describing: focus))")
        }
    }

    private func valueLabel(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.hairlineSpacing) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(format(value)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seedDrafts(context: ResponsiveInspectorEditContext) {
        guard context == state.responsiveInspectorEditContext else { return }
        draftContext = context
        if let fixed = state.fluidFixedValue(for: target) {
            minimum = format(max(target == .padding || target == .gap ? 0 : 1, fixed * 0.75))
            preferred = format(fixed)
            let upper = min(1_000_000_000, max(fixed, fixed * 1.25))
            maximum = format(target.accepts(upper) ? upper : fixed)
            validation = nil
        } else {
            // Mixed fixed fallbacks have no legitimate primary value to seed.
            // Let the user explicitly author one range rather than disabling
            // the workflow or silently borrowing the first object's numbers.
            minimum = ""; preferred = ""; maximum = ""
            validation = "Mixed fixed values. Enter one complete range for the applicable objects; nothing has changed yet."
        }
        focused = .minimum
    }

    private var draftPreview: CanonicalFluidValue? {
        guard case .success(let min) = GeometryInspectorNumberParser.parse(minimum),
              case .success(let preferred) = GeometryInspectorNumberParser.parse(preferred),
              case .success(let max) = GeometryInspectorNumberParser.parse(maximum) else { return nil }
        let value = CanonicalFluidValue(minimum: min, preferred: preferred, maximum: max)
        return value.isValid && target.accepts(min) && target.accepts(preferred) && target.accepts(max)
            ? value : nil
    }

    private func commit(_ provenance: FluidValueProvenance) {
        guard let draftContext else { return }
        let parsed = [minimum, preferred, maximum].map { GeometryInspectorNumberParser.parse($0) }
        guard case .success(let min) = parsed[0], case .success(let preferred) = parsed[1],
              case .success(let max) = parsed[2] else {
            validation = "Enter three complete finite numbers."
            return
        }
        let value = CanonicalFluidValue(minimum: min, preferred: preferred, maximum: max)
        guard value.isValid, target.accepts(min), target.accepts(preferred), target.accepts(max) else {
            validation = "Minimum must be no greater than preferred, preferred no greater than maximum, and all values must be in range."
            return
        }
        guard state.commitFluidValue(value, target: target, provenance: provenance, expectedContext: draftContext) else {
            validation = state.fluidValueFailure?.localizedDescription; return
        }
        resetDrafts()
    }

    private func remove(context: ResponsiveInspectorEditContext) {
        if state.commitFluidValue(nil, target: target, provenance: .pointer, expectedContext: context) { resetDrafts() }
        else { validation = state.fluidValueFailure?.localizedDescription }
    }

    private func resetDrafts() { minimum = ""; preferred = ""; maximum = ""; validation = nil; draftContext = nil }
    private func format(_ value: Double) -> String { GeometryInspectorNumberParser.format(value) }
}

/// Scene-local drafts and native controls for canonical Section/Stack/Grid
/// layout properties. Every committed path converges on the typed registry in
/// `WorkspaceShellState`; incomplete strings never enter the document model.
private struct ContainerLayoutInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    let showFluidValues: () -> Void
    @FocusState private var focusedField: ContainerLayoutField?
    @State private var drafts: [ContainerLayoutField: LayoutInspectorNumericDraft] = [:]
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
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
                    .foregroundStyle(SiteForgeVisualSystem.danger)
                    .accessibilityIdentifier("inspector.layout.container.validation")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Container layout")
        .accessibilityIdentifier("inspector.layout.container")
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted else { return }
            if request.requiresCleanEditors { if !drafts.isEmpty { request.reject() }; return }
            for field in ContainerLayoutField.allCases where drafts[field] != nil { commitNumeric(field, provenance: .focusLoss) }
            if !drafts.isEmpty { request.reject() }
        }
        .onChange(of: state.documentSession.document.revision) { _, _ in adoptDrafts() }
        .onChange(of: state.layoutInspectorDraftScope) { _, _ in adoptDrafts() }
        .onExitCommand {
            guard let cancelledField = focusedField ?? drafts.keys.first else { return }
            drafts.removeAll()
            validationMessage = nil
            focusedField = nil
            state.cancelContainerLayoutDraft(field: cancelledField)
            state.clearWorkspaceActionNotice()
        }
    }

    @ViewBuilder
    private func numericRow(_ field: ContainerLayoutField) -> some View {
        let selection = state.containerLayoutValue(for: field)
        let availability = state.containerLayoutAvailability(for: field)
        if case .unavailable = selection {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                Text(field.title).font(.caption).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: SiteForgeVisualSystem.controlInset) {
                    TextField(field.title, text: numericBinding(field, selection: selection))
                        .textFieldStyle(.roundedBorder).focusedValue(\.siteforgeNativeTextEditor, true)
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
                            ? "Use default \(field.title)" : "Use inherited \(field.title) at \(state.viewportPreset.title)")
                        .help(state.viewportPreset == .desktop
                            ? "Return this field to its default; an active Smooth scaling range can still take priority."
                            : "Remove only this screen size's custom value. Uses base or Smooth scaling values; other screen sizes stay unchanged.")
                        .accessibilityIdentifier("inspector.layout.container.\(field.rawValue).reset")
                }
                subsetLabel(selection)
                sourceLabel(field)
                if state.containerLayoutHasFluidValue(for: field) {
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                        Text(state.viewportPreset.responsiveBreakpoint == .desktop
                            ? "Smooth scaling is active. Edit or remove its range instead of changing the exact-size fallback."
                            : state.hasContainerLayoutOverride(field)
                                ? "A custom screen-size value takes priority. Reset uses the Smooth scaling range again."
                                : "Uses smooth scaling. An edit here overrides this screen size without changing the scaling range.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Edit Smooth Scaling…", action: showFluidValues)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit smooth scaling for \(field.title.lowercased())")
                            .help("Open Smooth scaling, then choose \(field.title) to edit or remove its range.")
                            .accessibilityIdentifier("inspector.layout.container.\(field.rawValue).fluid")
                    }
                }
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
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                    HStack(spacing: SiteForgeVisualSystem.controlInset) {
                        Text("Direction").fixedSize()
                            .accessibilityIdentifier("inspector.layout.container.axis.label")
                        Spacer()
                        Button("Reset") { reset(.axis) }
                            .buttonStyle(.borderless)
                            .fixedSize()
                            .disabled(!availability.isEnabled || !canReset(selection, field: .axis))
                            .accessibilityLabel("Reset Direction to default")
                            .accessibilityIdentifier("inspector.layout.container.axis.reset")
                    }
                        Picker("Direction", selection: axisBinding(selection)) {
                            ForEach(ContainerLayoutAxis.allCases, id: \.self) { axis in
                                Text(axis.rawValue.capitalized).tag(axis as ContainerLayoutAxis?)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!availability.isEnabled)
                        .accessibilityLabel("Stack direction")
                        .accessibilityValue(accessibilityValue(selection, field: .axis))
                        .accessibilityIdentifier("inspector.layout.container.axis")
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
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                    // Four intrinsic-width segments must not compress the label
                    // into a column at the supported compact Inspector width.
                    Text("Alignment")
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("inspector.layout.container.alignment.label")
                    Picker("Alignment", selection: alignmentBinding(selection)) {
                        ForEach(ContainerLayoutAlignment.allCases, id: \.self) { alignment in
                            Text(alignment.rawValue.capitalized).tag(alignment as ContainerLayoutAlignment?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
            get: { drafts[field]?.text ?? displayNumber(selection) },
            set: {
                guard drafts[field] != nil || $0 != displayNumber(selection) else { return }
                if drafts[field] == nil { drafts[field] = .init(text: $0, committed: displayNumber(selection), scope: state.layoutInspectorDraftScope) }
                else { drafts[field]?.text = $0 }
                validationMessage = nil
            }
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
                schedulePickerCommit(.axis, value: .axis(value), operation: "direction")
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
                schedulePickerCommit(.alignment, value: .alignment(value), operation: "alignment")
            }
        )
    }

    /// A segmented Picker publishes its binding while SwiftUI is reconciling
    /// the native control. Defer the document mutation to the next main-actor
    /// event and retain the canonical edit identity so a changed selection,
    /// revision, document, or breakpoint makes the edit neutral. The registry
    /// captures the live immutable renderer generation when it prepares the
    /// command after this guard.
    private func schedulePickerCommit(
        _ field: ContainerLayoutField,
        value: ContainerLayoutValue,
        operation: String
    ) {
        let documentID = state.documentSession.document.id
        let revision = state.documentSession.document.revision
        let selection = state.selectionState.orderedIDs
        let breakpoint = state.viewportPreset
        let scope = state.layoutInspectorDraftScope
        Task { @MainActor in
            guard state.documentSession.document.id == documentID,
                  state.documentSession.document.revision == revision,
                  state.selectionState.orderedIDs == selection,
                  state.viewportPreset == breakpoint, state.layoutInspectorDraftScope == scope else { return }
            commit(field, value: value, operation: operation, provenance: .picker)
        }
    }

    private func commitNumeric(
        _ field: ContainerLayoutField,
        provenance: ContainerLayoutProvenance
    ) {
        guard var draft = drafts[field] else { return }
        draft.adopt(committed: displayNumber(state.containerLayoutValue(for: field)), scope: state.layoutInspectorDraftScope)
        drafts[field] = draft
        guard draft.canCommit(in: state.layoutInspectorDraftScope) else {
            validationMessage = AuthoringLanguage.staleDraft
            return
        }
        if draft.hasUnchangedNumericValue { drafts.removeValue(forKey: field); validationMessage = nil; return }
        switch GeometryInspectorNumberParser.parse(draft.text) {
        case .success(let value):
            let canonical = ContainerLayoutValue.number(value)
            do { try ContainerLayoutCommandRegistry.validate(canonical, field: field) }
            catch {
                validationMessage = field == .columns
                    ? "Columns must be a whole number from 1 through 64."
                    : "\(field.title) must be from 0 through 10,000."
                return
            }
            if state.commitContainerLayout(field: field, value: canonical, provenance: provenance, draftScope: draft.scope) {
                drafts.removeValue(forKey: field); validationMessage = nil
            } else {
                validationMessage = state.containerLayoutFailure?.localizedDescription ?? "Wait for the current canvas, then retry."
            }
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
        drafts.removeValue(forKey: field)
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
    private func adoptDrafts() {
        for field in Array(drafts.keys) {
            drafts[field]?.adopt(committed: displayNumber(state.containerLayoutValue(for: field)), scope: state.layoutInspectorDraftScope)
        }
        if drafts.values.contains(where: { $0.conflict != nil }) {
            validationMessage = AuthoringLanguage.staleDraft
        }
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
        let provenance = AuthoringLanguage.propertySource(origin)
        guard applicable > 1 || skipped > 0 else { return provenance }
        return "\(provenance) · \(applicable) applicable\(skipped > 0 ? " · \(skipped) skipped" : "")"
    }

    @ViewBuilder
    private func sourceLabel(_ field: ContainerLayoutField) -> some View {
        if let source = state.containerLayoutResponsiveSource(for: field) {
            Text(source).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .help(source)
                .accessibilityLabel("\(field.title) source")
                .accessibilityValue(source)
                .accessibilityIdentifier("inspector.layout.container.\(field.rawValue).source")
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
        let context = state.responsiveInspectorEditContext
        return VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
            Text("Visibility at this screen size").font(.headline)
            switch state.responsiveVisibilityValue {
            case .single(let visible, let origin, let source, let applicable, let skipped):
                Toggle("Visible at \(state.viewportPreset.title)", isOn: Binding(
                    get: { visible },
                    set: { _ = state.commitResponsiveVisibility($0, provenance: .pointer, expectedContext: context) }
                ))
                .accessibilityValue("\(visible ? "Visible" : "Hidden"); \(source.label(at: state.viewportPreset.responsiveBreakpoint)); \(AuthoringLanguage.propertySource(origin))")
                .accessibilityIdentifier("inspector.layout.visibility")
                Text("\(source.label(at: state.viewportPreset.responsiveBreakpoint)) · \(origin.rawValue.capitalized) · \(applicable) applicable\(skipped > 0 ? " · \(skipped) skipped" : "")")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            case .mixed(let applicable, let skipped):
                Text("Visible at \(state.viewportPreset.title): Mixed")
                    .accessibilityIdentifier("inspector.layout.visibility.mixed")
                HStack(spacing: SiteForgeVisualSystem.controlInset) {
                    Button("Show") {
                        _ = state.commitResponsiveVisibility(true, provenance: .pointer, expectedContext: context)
                    }
                    .accessibilityLabel("Show selected objects at \(state.viewportPreset.title)")
                    .accessibilityIdentifier("inspector.layout.visibility.show")
                    Button("Hide") {
                        _ = state.commitResponsiveVisibility(false, provenance: .pointer, expectedContext: context)
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
                Button("Use Desktop visibility") {
                    _ = state.commitResponsiveVisibility(nil, provenance: .pointer, expectedContext: context)
                }
                .disabled(!state.hasVisibilityOverrideAtCurrentBreakpoint)
                .help("Remove only the visibility choice for this screen size. Desktop visibility is used; a hidden parent can still hide this object.")
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
        HStack(spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
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
            if [.frame, .text, .button, .link].contains(state.selectedTool) {
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
            if state.lastClipboardAnnouncement != "Clipboard editing inactive" {
                Divider().frame(height: 14)
                Label(state.lastClipboardAnnouncement, systemImage: "doc.on.clipboard")
                    .accessibilityLabel(state.lastClipboardAnnouncement)
                    .accessibilityIdentifier("status.clipboard")
            }
            Spacer()
            if lifecycle.phase == .saving || lifecycle.phase == .autosaving {
                ProgressView().controlSize(.small).accessibilityLabel(lifecycle.statusText)
            }
            Label(lifecycle.statusText,
                  systemImage: lifecycle.phase == .failed || lifecycle.phase == .conflicted ? "exclamationmark.triangle.fill" : "doc.badge.clock")
                .foregroundStyle(lifecycle.phase == .failed || lifecycle.phase == .conflicted ? SiteForgeVisualSystem.danger : Color.secondary)
                .accessibilityLabel("Document status: \(lifecycle.statusText)")
                .accessibilityValue(lifecycle.statusText)
                .accessibilityIdentifier("status.document")
            if let notice = lifecycle.fileActionNotice {
                Text(notice).font(.caption).lineLimit(1).help(notice)
                    .accessibilityLabel(notice).accessibilityIdentifier("status.fileActionNotice")
            }
            Divider().frame(height: 14)
            Text("Tool: \(state.selectedTool.title)")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("status.activeTool")
            Divider().frame(height: 14)
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(SiteForgeVisualSystem.success)
                .accessibilityLabel("Diagnostics status: Ready")
                .accessibilityIdentifier("status.diagnostics")
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, SiteForgeVisualSystem.panePadding)
        .frame(height: SiteForgeVisualSystem.statusBarHeight)
        .workspaceChrome(.statusBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ShellRegion.statusBar.rawValue)
    }
}


private struct LocalPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Local Preview", systemImage: "play.rectangle.fill")
                    .font(.headline)
                Button { state.previewBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!state.previewState.canGoBack)
                    .accessibilityLabel("Preview Back")
                    .accessibilityIdentifier("preview.back")
                Button { state.previewForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!state.previewState.canGoForward)
                    .accessibilityLabel("Preview Forward")
                    .accessibilityIdentifier("preview.forward")
                if let page = state.previewState.currentPage {
                    Menu {
                        ForEach(state.previewState.runtime?.pages ?? []) { destination in
                            Button(destination.name) {
                                state.followPreviewLink(.init(
                                    target: .page(destination.id), context: .same, isMissing: false))
                            }
                        }
                    } label: {
                        Label(page.name, systemImage: page.role == .notFound ? "exclamationmark.triangle" : "doc")
                    }
                    .accessibilityLabel("Preview page")
                    .accessibilityValue("\(page.name), \(page.route.rawValue)")
                    .accessibilityIdentifier("preview.page")
                }
                Spacer()
                Text(state.previewState.snapshot.map { "Revision \($0.revision)" } ?? "Unavailable")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("preview.revision")
                Button("Refresh") { state.refreshPreview() }
                    .accessibilityIdentifier("preview.refresh")
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("preview.done")
            }
            .padding(SiteForgeVisualSystem.toolbarGroupSpacing)
            Divider()
            if let snapshot = state.previewState.snapshot {
                LocalPreviewCanvas(
                    snapshot: snapshot,
                    viewportBounds: state.previewState.currentPage?.viewportBounds,
                    onFollow: { state.followPreviewLink($0) }
                )
                // Website paper has a neutral light default independent of
                // dark editor chrome; native visitor controls stay readable.
                .environment(\.colorScheme, .light)
            } else {
                ContentUnavailableView(
                    "Preview unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(state.previewState.status)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Text(state.previewState.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.previewState.status)
                .accessibilityIdentifier("preview.status")
        }
        .frame(minWidth: 620, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview.local")
    }
}

private struct StaticBuildDiagnosticsView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            HStack {
                Label(AuthoringLanguage.checkWebsite, systemImage: "wrench.and.screwdriver")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { state.isBuildDiagnosticsPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(state.isAdoptingBuildFinding)
            }
            ScrollView {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Check your website before creating local HTML, CSS and image files. Nothing is published.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help("Unsupported output is reported without changing your document or running custom code.")

            InspectorActionLayout {
                Picker("Profile", selection: $state.staticBuildProfile) {
                    ForEach(LocalBuildProfile.allCases) { profile in Text(profile.title).tag(profile) }
                }
                .pickerStyle(.menu)
                .frame(width: 260)
                .accessibilityLabel("Build profile")
                .accessibilityValue(state.staticBuildProfile.title)
                .accessibilityIdentifier("build.profile")
                .disabled(state.isOpeningBuildFinding)
                Button(AuthoringLanguage.checkWebsite) { state.runStaticBuildPreflight() }
                    .disabled(state.staticBuildPhase == .preflighting || state.staticBuildPhase == .writing || state.isOpeningBuildFinding)
                    .accessibilityIdentifier("build.preflight")
                Button("Cancel") { state.cancelStaticBuild() }
                    .disabled(state.staticBuildPhase != .preflighting && state.staticBuildPhase != .writing)
                    .accessibilityIdentifier("build.cancel")
            }
            .onChange(of: state.staticBuildProfile) { _, _ in state.runStaticBuildPreflight() }

            GroupBox("Status") {
                HStack(alignment: .top, spacing: SiteForgeVisualSystem.standardSpacing) {
                    if state.staticBuildPhase == .preflighting || state.staticBuildPhase == .writing {
                        ProgressView().controlSize(.small)
                    }
                    Text(state.staticBuildStatus).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("build.status")
            }

            GroupBox("Compatibility findings") {
                if let receipt = state.staticBuildFindingReceipt, !receipt.findings.isEmpty {
                    Text(receipt.documentID == state.documentSession.document.id && receipt.revision == state.documentSession.document.revision
                         ? "Results for committed revision \(receipt.revision)."
                         : "Earlier results. Choose Check Website for the current project and revision.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    LazyVStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    ForEach(receipt.findings) { finding in
                        StaticBuildFindingRepairRow(finding: finding,
                            availability: state.buildFindingRevealAvailability(finding, receipt: receipt, source: .checkWebsite),
                            identifierPrefix: "build.finding", reveal: { _ = state.revealStaticBuildFinding(finding, receipt: receipt) })
                        Divider().accessibilityHidden(true)
                    }
                    }
                    .frame(minHeight: 210)
                } else {
                    ContentUnavailableView("No findings yet", systemImage: "checkmark.shield",
                                           description: Text("Choose Check Website for the current revision."))
                        .frame(minHeight: 180)
                }
            }

            if !state.buildFindingRevealStatus.isEmpty {
                Text(state.buildFindingRevealStatus).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("build.repair.status")
            }
            }.frame(maxWidth: .infinity, alignment: .leading)
            }

            InspectorActionLayout {
                Button("Copy Redacted Summary") { state.copyStaticBuildSummary() }
                    .disabled(state.staticBuildCompilation == nil)
                    .accessibilityIdentifier("build.copySummary")
                Button("Choose Destination and Build…") { chooseDestination() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.staticBuildCompilation?.canWrite != true || state.staticBuildPhase != .ready
                        || state.staticBuildCompilation?.documentID != state.documentSession.document.id
                        || state.staticBuildCompilation?.revision != state.documentSession.document.revision
                        || state.isOpeningBuildFinding)
                    .accessibilityIdentifier("build.write")
            }
        }
        .padding(SiteForgeVisualSystem.sectionSpacing)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 640)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.diagnostics")
    }

    private func chooseDestination() {
        guard let compilation = state.staticBuildCompilation, compilation.canWrite,
              compilation.documentID == state.documentSession.document.id,
              compilation.revision == state.documentSession.document.revision,
              state.staticBuildPhase == .ready, !state.isOpeningBuildFinding else { return }
        let panel = NSSavePanel()
        panel.title = "Create Local Static Output"
        panel.prompt = "Build"
        panel.nameFieldStringValue = "SiteForge Static Build"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let exists = FileManager.default.fileExists(atPath: destination.path)
        state.writeStaticBuild(to: destination, replacingExisting: exists, expectedCompilation: compilation)
    }

}

private struct ClipboardComponentTransferPreflightView: View {
    @ObservedObject var state: WorkspaceShellState

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            Label("Import Component Dependencies", systemImage: "square.stack.3d.up")
                .font(.title2.weight(.semibold))
            Text("This paste includes local component definitions from another project. Review the complete transfer before changing this project.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = state.pendingClipboardComponentSummary {
                List(summary.entries, id: \.sourceDefinitionID) { entry in
                    HStack(spacing: SiteForgeVisualSystem.standardSpacing) {
                        Image(systemName: icon(for: entry.resolution))
                            .foregroundStyle(color(for: entry.resolution))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.hairlineSpacing) {
                            Text(entry.displayName).lineLimit(1)
                            Text(label(for: entry.resolution)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(entry.displayName), \(label(for: entry.resolution))")
                }
                .frame(minHeight: 180)
                Text(summary.accessibilitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clipboard.component.summary")
            }
            HStack {
                Button("Cancel") { state.cancelCrossProjectComponentPaste() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("clipboard.component.cancel")
                Spacer()
                Button("Import and Paste") { state.confirmCrossProjectComponentPaste() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("clipboard.component.confirm")
            }
        }
        .padding(SiteForgeVisualSystem.panePadding)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 330)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clipboard.component.preflight")
    }

    private func label(for resolution: ClipboardComponentTransferSummary.Entry.Resolution) -> String {
        switch resolution {
        case .imported: "New local definition will be imported"
        case .reused: "Equivalent local definition will be reused"
        case .renamed: "Name conflict; a deterministic Copy name will be used"
        }
    }

    private func icon(for resolution: ClipboardComponentTransferSummary.Entry.Resolution) -> String {
        switch resolution {
        case .imported: "square.and.arrow.down"
        case .reused: "equal.circle"
        case .renamed: "character.cursor.ibeam"
        }
    }

    private func color(for resolution: ClipboardComponentTransferSummary.Entry.Resolution) -> Color {
        switch resolution {
        case .imported: .accentColor
        case .reused: .secondary
        case .renamed: .orange
        }
    }
}

private struct LocalPreviewCanvas: View {
    let snapshot: CanvasPreviewSceneSnapshot
    let viewportBounds: WorldRect?
    let onFollow: (CanvasPreviewLink) -> Void

    var body: some View {
        GeometryReader { proxy in
            let bounds = viewportBounds ?? previewBounds(snapshot.objects)
            if let geometry = CanvasPreviewPresentationGeometry(bounds: bounds,
                available: .init(width: Double(proxy.size.width), height: Double(proxy.size.height))) {
            let inset = CanvasPreviewPresentationGeometry.inset
            let scale = geometry.scale
            ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                Color.white.allowsHitTesting(false)
                if let background = snapshot.pageBackground {
                    LocalPreviewObject(object: background, scale: scale, onFollow: onFollow)
                        .frame(width: background.frame.size.width * scale, height: background.frame.size.height * scale)
                        .offset(x: inset + (background.frame.origin.x - bounds.origin.x) * scale,
                                y: inset + (background.frame.origin.y - bounds.origin.y) * scale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ForEach(CanvasPreviewPresentationGroup.resolve(snapshot.objects)) { group in
                    if let owner = group.container {
                        ZStack(alignment: .topLeading) {
                            ForEach(group.objects, id: \.id) { object in
                                positioned(object, relativeTo: owner.frame, scale: scale, pageChrome: true)
                            }
                        }
                        .frame(width: owner.frame.size.width * scale, height: owner.frame.size.height * scale, alignment: .topLeading)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(owner.accessibilityLabel)
                        .offset(x: inset + (owner.frame.minX - bounds.minX) * scale,
                                y: inset + (owner.frame.minY - bounds.minY) * scale)
                    } else {
                        ForEach(group.objects, id: \.id) { object in
                            positioned(object, relativeTo: bounds, scale: scale)
                                .offset(x: inset, y: inset)
                        }
                    }
                }
            }
            .frame(width: geometry.contentSize.width, height: geometry.contentSize.height)
            .clipShape(Rectangle())
            }
            .accessibilityLabel("Preview page, revision \(snapshot.revision), \(snapshot.objects.count) authored objects")
            .accessibilityIdentifier("preview.canvas")
            }
        }
        .background(Color.white)
    }

    private func positioned(_ object: CanvasRenderObject, relativeTo bounds: WorldRect, scale: Double, pageChrome: Bool = false) -> some View {
        LocalPreviewObject(object: object, scale: scale, onFollow: onFollow, hidesDecorativeAccessibility: pageChrome)
            .frame(width: object.frame.size.width * scale, height: object.frame.size.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: object.cornerRadius * scale))
            .offset(x: (object.frame.minX - bounds.minX) * scale, y: (object.frame.minY - bounds.minY) * scale)
    }

    private func previewBounds(_ objects: [CanvasRenderObject]) -> WorldRect {
        guard let first = objects.first else {
            return .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900))
        }
        let minX = objects.dropFirst().reduce(first.frame.minX) { min($0, $1.frame.minX) }
        let minY = objects.dropFirst().reduce(first.frame.minY) { min($0, $1.frame.minY) }
        let maxX = objects.dropFirst().reduce(first.frame.maxX) { max($0, $1.frame.maxX) }
        let maxY = objects.dropFirst().reduce(first.frame.maxY) { max($0, $1.frame.maxY) }
        return .init(origin: .init(x: minX, y: minY),
                     size: .init(width: maxX - minX, height: maxY - minY))
    }
}

struct NativePageNavigationPreview: View {
    let navigation: PageNavigationSnapshot
    let availableWidth: Double
    let onFollow: (CanvasPreviewLink) -> Void
    var body: some View {
        let layout = CanonicalPageFlow.navigationLayout(availableWidth: availableWidth,
            count: navigation.links.count, alignment: navigation.alignment)
        HStack(spacing: layout.gap) {
            if navigation.usesHamburger {
                NativePageNavigationMenu(navigation: navigation, onFollow: onFollow)
                    .frame(width: max(1, availableWidth), height: navigation.rowHeight ?? 32)
            } else if !navigation.itemFrames.isEmpty {
                ZStack(alignment: .topLeading) {
                    ForEach(navigation.links) { link in
                        if let frame = navigation.itemFrames.first(where: { $0.id == link.id }) {
                            Button { follow(link) } label: { Text(link.label).lineLimit(1).help(link.label) }
                                .disabled(!link.isAvailable).buttonStyle(.plain)
                                .frame(width: frame.width, height: frame.height, alignment: .leading)
                                .offset(x: frame.x, y: frame.y)
                                .accessibilityLabel(link.label + " page link")
                                .accessibilityValue(link.pageID == navigation.currentPageID ? "Current page" : link.isAvailable ? "Available" : "Missing original page")
                                .accessibilityIdentifier("preview.navigation.link.\(link.id)")
                        }
                    }
                }.frame(width: availableWidth, height: navigation.rowHeight ?? 32, alignment: .topLeading)
            } else {
                ForEach(navigation.links) { link in
                    Button { follow(link) } label: { Text(link.label).lineLimit(1).help(link.label) }
                        .disabled(!link.isAvailable).buttonStyle(.plain)
                        .frame(width: layout.width, height: navigation.rowHeight ?? 32, alignment: .leading)
                        .accessibilityLabel(link.label + " page link")
                        .accessibilityValue(link.pageID == navigation.currentPageID ? "Current page" : link.isAvailable ? "Available" : "Missing original page")
                        .accessibilityIdentifier("preview.navigation.link.\(link.id)")
                }
            }
        }.font(.system(size: 14))
            .frame(width: max(1, availableWidth), alignment: navigation.alignment == "end" ? .trailing : navigation.alignment == "center" ? .center : .leading)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Website page navigation")
    }
    private func follow(_ link: PageNavigationLink) { onFollow(.init(target: .page(link.pageID), context: link.context ?? .same, isMissing: !link.isAvailable)) }
}

/// The native popup itself owns keyboard focus. A separate SwiftUI focus proxy
/// can show a ring without delivering the menu-opening key to the control.
struct NativePageNavigationMenu: NSViewRepresentable {
    let navigation: PageNavigationSnapshot
    let onFollow: (CanvasPreviewLink) -> Void
    func makeNSView(context: Context) -> NativePreviewNavigationButton {
        NativePreviewNavigationButton(frame: .zero, pullsDown: true)
    }
    func updateNSView(_ view: NativePreviewNavigationButton, context: Context) {
        view.configure(navigation, onFollow: onFollow)
    }
    static func dismantleNSView(_ view: NativePreviewNavigationButton, coordinator: ()) { view.detach() }
}

@MainActor
private final class NativePreviewNavigationCell: NSPopUpButtonCell {
    override func accessibilityActivationPoint() -> NSPoint {
        guard let view = controlView, let window = view.window else { return super.accessibilityActivationPoint() }
        return window.convertPoint(toScreen: view.convert(
            NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil))
    }
}

@MainActor
final class NativePreviewNavigationButton: NSPopUpButton, NSMenuDelegate {
    private var navigation: PageNavigationSnapshot?
    private var onFollow: ((CanvasPreviewLink) -> Void)?
    private var pending: (PageNavigationSnapshot, (CanvasPreviewLink) -> Void)?
    private var tracking = false
    private var detached = false
    override var acceptsFirstResponder: Bool { isEnabled && !detached }
    override var canBecomeKeyView: Bool { acceptsFirstResponder && !isHidden }

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        cell = NativePreviewNavigationCell(textCell: "Menu", pullsDown: flag)
    }
    required init?(coder: NSCoder) { return nil }


    func configure(_ navigation: PageNavigationSnapshot, onFollow: @escaping (CanvasPreviewLink) -> Void) {
        detached = false
        guard self.navigation != navigation else { self.onFollow = onFollow; return }
        if tracking { pending = (navigation, onFollow); return }
        self.navigation = navigation
        self.onFollow = onFollow
        controlSize = .small
        font = .systemFont(ofSize: 14)
        // AppKit exposes the popup cell as the accessible control, not the
        // NSControl view. Label the genuine hit target, without inventing a
        // second accessible button or overriding its frame/role/window.
        cell?.setAccessibilityLabel("Page navigation menu")
        cell?.setAccessibilityIdentifier("preview.navigation.menu.\(navigation.ownerID)")
        cell?.setAccessibilityHelp("Choose a project page. Escape closes the native menu and restores focus.")
        let next = NSMenu()
        next.autoenablesItems = false
        let label = NSMenuItem(title: "Menu", action: nil, keyEquivalent: "")
        label.isHidden = true
        next.addItem(label)
        for link in navigation.links {
            let item = NSMenuItem(title: link.label, action: #selector(follow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = link.id.description
            item.isEnabled = link.isAvailable
            item.state = link.pageID == navigation.currentPageID ? .on : .off
            item.toolTip = link.isAvailable ? link.label : "Missing original page. Repair this link in Header/Footer settings."
            next.addItem(item)
        }
        next.delegate = self
        menu?.delegate = nil
        menu = next
        selectItem(at: 0)
        title = "Menu"
        isEnabled = navigation.links.contains(where: \.isAvailable)
    }

    @objc private func follow(_ item: NSMenuItem) {
        guard !detached, pending == nil, item.menu === menu,
              let id = item.representedObject as? String,
              let link = navigation?.links.first(where: { $0.id.description == id }), link.isAvailable else { return }
        onFollow?(.init(target: .page(link.pageID), context: link.context ?? .same, isMissing: false))
    }

    func menuWillOpen(_ menu: NSMenu) { tracking = true }
    func menuDidClose(_ menu: NSMenu) {
        tracking = false
        if let update = pending { pending = nil; configure(update.0, onFollow: update.1) }
        guard !detached, let window, window.isKeyWindow else { return }
        window.makeFirstResponder(self)
    }

    func detach() {
        detached = true
        isEnabled = false
        pending = nil
        onFollow = nil
        navigation = nil
        menu?.delegate = nil
        menu?.cancelTracking()
        menu = nil
        tracking = false
    }
}

private struct LocalPreviewAuthoredText: NSViewRepresentable {
    let object: CanvasRenderObject
    let scale: Double
    func makeNSView(context: Context) -> CanvasPreviewTextView { CanvasPreviewTextView() }
    func updateNSView(_ view: CanvasPreviewTextView, context: Context) {
        view.configure(object: object, scale: scale)
    }
}

/// Preview fits world geometry, so its text must fit by that same scale rather
/// than inheriting the native Inspector font and truncating an authored title.
/// The shared live-canvas factory owns all font, inset and baseline decisions.
final class CanvasPreviewTextView: NSView {
    private var object: CanvasRenderObject?
    private var presentationScale = 1.0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(object: CanvasRenderObject, scale: Double) {
        self.object = object
        presentationScale = scale
        wantsLayer = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer?.sublayers = []
        guard let object, bounds.width > 0, bounds.height > 0,
              let text = CanvasAuthoredTextLayerFactory.makeLayer(for: object,
                viewportObjectRect: bounds, zoom: presentationScale,
                contentsScale: window?.backingScaleFactor ?? 2) else { return }
        // LocalPreviewObject composites the complete authored object once.
        // Applying object opacity again on its text child would square alpha.
        text.opacity = 1
        layer?.addSublayer(text)
    }
}

private struct LocalPreviewObject: View {
    let object: CanvasRenderObject
    let scale: Double
    let onFollow: (CanvasPreviewLink) -> Void
    var hidesDecorativeAccessibility = false

    var body: some View {
        if let link = object.previewLink {
            Button { onFollow(link) } label: {
                // Native raster text deliberately does not intercept input.
                // The authored link rectangle, including transparent text
                // space, remains the real SwiftUI button's pointer surface.
                renderedContent.contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .disabled(link.isMissing)
                .help(link.isMissing ? "Missing link target" : "Follow \(object.plainText ?? "link")")
                .accessibilityLabel(object.accessibilityLabel)
                .accessibilityHint(link.isMissing ? "Target missing" : "Activates the authored link in Preview")
                .accessibilityIdentifier("preview.object.\(object.id.description)")
        } else {
            renderedContent
                .allowsHitTesting(object.navigation != nil)
        }
    }

    private var renderedContent: some View {
        ZStack(alignment: .topLeading) {
            previewFill
            if let navigation = object.navigation,
               let geometry = CanvasPreviewNavigationGeometry(frame: object.frame, padding: navigation.padding,
                    rowHeight: navigation.rowHeight ?? 32, scale: scale) {
                NativePageNavigationPreview(navigation: navigation, availableWidth: geometry.worldSize.width, onFollow: onFollow)
                    .frame(width: geometry.worldSize.width, height: geometry.worldSize.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geometry.displaySize.width, height: geometry.displaySize.height, alignment: .topLeading)
                    .offset(x: geometry.displayOrigin.x, y: geometry.displayOrigin.y)
            }
            if object.paintsStandalonePreviewText {
                LocalPreviewAuthoredText(object: object, scale: scale)
                    .accessibilityLabel(object.accessibilityLabel)
            } else if object.imageAssetID != nil {
                if let data = object.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: object.imageFitMode == .fill ? .fill : .fit)
                } else {
                    Text("Missing image resource")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .opacity(object.opacity)
        .shadow(
            color: previewShadowColor,
            radius: previewShadowRadius,
            x: previewShadowX,
            y: previewShadowY
        )
        .overlay {
            if let border = object.border, border.rgba.count == 4 {
                RoundedRectangle(cornerRadius: object.cornerRadius).stroke(
                    Color(red: border.rgba[0], green: border.rgba[1], blue: border.rgba[2], opacity: border.rgba[3]),
                    style: StrokeStyle(
                        lineWidth: border.width,
                        dash: previewBorderDash(border.style)
                    )
                )
            }
        }
        .accessibilityElement(children: object.navigation == nil ? .ignore : .contain)
        .accessibilityLabel(object.accessibilityLabel)
        .accessibilityHidden(hidesDecorativeAccessibility && object.isNativePreviewDecoration)
    }

    private func previewBorderDash(_ style: CanvasBorderStyle) -> [CGFloat] {
        switch style {
        case .solid: []
        case .dashed: [6, 4]
        case .dotted: [1, 3]
        }
    }

    private var previewShadowColor: Color {
        guard let shadow = object.shadow, shadow.rgba.count == 4 else { return .clear }
        return Color(red: shadow.rgba[0], green: shadow.rgba[1], blue: shadow.rgba[2], opacity: shadow.rgba[3])
    }
    private var previewShadowRadius: CGFloat { CGFloat(object.shadow?.blur ?? 0) }
    private var previewShadowX: CGFloat { CGFloat(object.shadow?.offsetX ?? 0) }
    private var previewShadowY: CGFloat { CGFloat(object.shadow?.offsetY ?? 0) }

    @ViewBuilder private var previewFill: some View {
        if let rgba = CanvasAuthoredFillCompositor.resolvedColor(layers: object.fillLayers, atNormalizedPoint: (0.5, 0.5)) ?? object.fillRGBA,
           rgba.count == 4 {
            Color(red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3])
        } else if object.plainText != nil {
            // Ordinary text has no background just because Preview is hosted
            // in a dark native window. Only authored fills may paint one.
            Color.clear
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
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

private struct NativeTextEditorFocusKey: FocusedValueKey { typealias Value = Bool }
extension FocusedValues {
    var siteforgeNativeTextEditor: Bool? {
        get { self[NativeTextEditorFocusKey.self] }
        set { self[NativeTextEditorFocusKey.self] = newValue }
    }
}

struct SiteForgeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.siteforgeNativeTextEditor) private var focusedNativeTextEditor
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

    private var nativeTextResponderIsActive: Bool {
        // Modern SwiftUI input can use AppKitWindow as its responder rather
        // than a classic field editor. Its focus value is the native draft
        // context; NSTextView remains the inline-editor compatibility path.
        // The command body can update before AppKit's deferred inline-editor
        // focus transfer. Keep native editing commands enabled for the live
        // scene's active editor rather than freezing the pre-focus snapshot.
        focusedNativeTextEditor == true || NSApp.keyWindow?.firstResponder is NSTextView
            || commandState?.textEditingSession.isActive == true
    }

    private func routePasteboardAction(_ selector: Selector, objectAction: (WorkspaceShellState) -> Void) {
        if nativeTextResponderIsActive {
            NSApp.sendAction(selector, to: nil, from: nil)
        } else if let state = commandState {
            objectAction(state)
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                guard commandState?.prepareForWorkspaceAction(.context) != false else { return }
                if let launchExperience { launchExperience.createBlankProject() }
                else if WorkspaceLaunchRequestQueue.shared.enqueue(.new) { openWindow(id: "workspace") }
            }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") {
                guard commandState?.prepareForWorkspaceAction(.context) != false else { return }
                if let launchExperience { launchExperience.presentOpenPanel() }
                else if let url = NativeProjectOpenPanel.chooseProject(),
                        WorkspaceLaunchRequestQueue.shared.enqueue(.open(url)) { openWindow(id: "workspace") }
            }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Close Window") {
                // Native responder ownership closes Settings/sheets correctly;
                // document windows still pass through their unsaved guard.
                NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Site & Page Settings…") { commandState?.presentWebsiteSettings() }
                .disabled(launchExperience?.isWorkspaceVisible != true || commandState?.websiteSettingsIdentity == nil)
            Divider()
            Button("Save") {
                // Resolve at the native menu action boundary. SwiftUI can
                // retain a pre-menu FocusedObject snapshot while AppKit clears
                // the key responder for menu tracking; the registry is bound
                // to the actual workspace window and therefore owns this
                // command deterministically.
                guard let target = commandState else { return }
                guard target.prepareForWorkspaceAction(.save) else { return }
                if target.lifecycle.fileURL == nil { target.lifecycle.presentSavePanel() }
                else { Task { _ = await target.lifecycle.save() } }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(launchExperience?.isWorkspaceVisible != true || commandState?.lifecycle.phase == .saving
                || (commandState?.lifecycle.canSave != true && !nativeTextResponderIsActive))
            Button("Save As…") {
                guard let target = commandState, target.prepareForWorkspaceAction(.saveAs) else { return }
                target.lifecycle.presentSavePanel()
            }
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
                if nativeTextResponderIsActive { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                else { commandState?.undo() }
            }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(launchExperience?.isWorkspaceVisible != true || (!nativeTextResponderIsActive && commandState?.canUndo != true))
            Button("Redo") {
                if nativeTextResponderIsActive { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                else { commandState?.redo() }
            }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(launchExperience?.isWorkspaceVisible != true || (!nativeTextResponderIsActive && commandState?.canRedo != true))
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Select All") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(!nativeTextResponderIsActive)
            Button("Cut") {
                routePasteboardAction(#selector(NSText.cut(_:))) {
                    _ = $0.cutSelection(provenance: .menu)
                }
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(!nativeTextResponderIsActive && commandState?.canCutSelection != true)
            Button("Copy") {
                routePasteboardAction(#selector(NSText.copy(_:))) {
                    _ = $0.copySelection(provenance: .menu)
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!nativeTextResponderIsActive && commandState?.canCopySelection != true)
            Button("Paste") {
                routePasteboardAction(#selector(NSText.paste(_:))) {
                    _ = $0.pasteSiteForgeObjects(provenance: .menu)
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!nativeTextResponderIsActive && commandState?.canPasteSiteForgeObjects != true)
            Button("Paste in Place") {
                _ = commandState?.pasteSiteForgeObjects(placement: .inPlace, provenance: .menu)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(nativeTextResponderIsActive || commandState?.canPasteSiteForgeObjects != true)
            Button("Duplicate") {
                _ = commandState?.duplicateSelection(provenance: .menu)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(nativeTextResponderIsActive || commandState?.canCopySelection != true)
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
            Button("Insert Heading at Center") {
                commandState?.performDefaultInsertion(.text, provenance: .menu, template: .heading)
            }
            .disabled(commandState?.insertionAvailability(.text, template: .heading).isEnabled != true)
            Button("Insert Button at Center") { commandState?.performDefaultInsertion(.button, provenance: .menu) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(commandState?.insertionAvailability(.button).isEnabled != true)
            Button("Insert Link at Center") { commandState?.performDefaultInsertion(.link, provenance: .menu) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(commandState?.insertionAvailability(.link).isEnabled != true)
            Button("Insert Form at Center") { commandState?.performDefaultInsertion(.form, provenance: .menu) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(commandState?.insertionAvailability(.form).isEnabled != true)
            Button("Insert Input into Selected Form") {
                commandState?.performDefaultInsertion(.text, provenance: .menu, template: .input)
            }
            .disabled(commandState?.insertionAvailability(.text, template: .input).isEnabled != true)
            Button("Insert Email into Selected Form") {
                commandState?.performDefaultInsertion(.text, provenance: .menu, template: .emailInput)
            }
            .disabled(commandState?.insertionAvailability(.text, template: .emailInput).isEnabled != true)
            Button("Insert Text Area into Selected Form") {
                commandState?.performDefaultInsertion(.text, provenance: .menu, template: .textArea)
            }
            .disabled(commandState?.insertionAvailability(.text, template: .textArea).isEnabled != true)
            Button("Insert Checkbox into Selected Form") {
                commandState?.performDefaultInsertion(.text, provenance: .menu, template: .checkbox)
            }
            .disabled(commandState?.insertionAvailability(.text, template: .checkbox).isEnabled != true)
            Button("Insert Select into Selected Form") {
                commandState?.performDefaultInsertion(.text, provenance: .menu, template: .selectField)
            }
            .disabled(commandState?.insertionAvailability(.text, template: .selectField).isEnabled != true)
            Button("Insert Submit into Selected Form") {
                commandState?.performDefaultInsertion(.text, provenance: .menu, template: .submit)
            }
            .disabled(commandState?.insertionAvailability(.text, template: .submit).isEnabled != true)
            Button("Insert Divider at Center") {
                commandState?.performDefaultInsertion(.frame, provenance: .menu, template: .divider)
            }
            .disabled(commandState?.insertionAvailability(.frame).isEnabled != true)
            Divider()
            Button("Insert Section in Flow") {
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
            Button("Insert Header at Page Top") {
                commandState?.performDefaultInsertion(.section, provenance: .menu, template: .header)
            }
            .disabled(commandState?.insertionAvailability(.section, template: .header).isEnabled != true)
            Button("Insert Navigation at Center") {
                commandState?.performDefaultInsertion(.section, provenance: .menu, template: .navigation)
            }
            .disabled(commandState?.insertionAvailability(.section, template: .navigation).isEnabled != true)
            Button("Insert Footer after Page Content") {
                commandState?.performDefaultInsertion(.section, provenance: .menu, template: .footer)
            }
            .disabled(commandState?.insertionAvailability(.section, template: .footer).isEnabled != true)
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

        CommandGroup(after: .pasteboard) {
            Divider()
            if let state = commandState { FormattingTransferMenuActions(state: state) }
        }

        CommandMenu("Page") {
            Button("New Page…") { commandState?.presentPageEditor(.create) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(commandState?.pageEditingIsAvailable != true)
            if let state = commandState,
               let page = state.pages.first(where: { $0.id == state.effectiveSelectedPageID }) {
                PageActionButtons(state: state, page: page)
                    .disabled(!state.pageEditingIsAvailable)
            }
        }

        CommandMenu("Component") {
            Button("Create Component from Selection") { commandState?.createComponent() }
                .disabled(commandState?.canCreateComponent != true)
            if let state = commandState {
                Menu("Insert Component") {
                    ForEach(state.componentDefinitions) { definition in
                        Button("Insert \(definition.name) Component") { state.insertComponent(definition.id) }
                            .accessibilityIdentifier("components.menu.insert." + definition.id.description)
                    }
                }.disabled(state.editingComponentID != nil || state.componentDefinitions.isEmpty || !state.pageEditingIsAvailable)
                if let instance = state.selectedComponent,
                   let id = CanonicalComponentReference.definitionID(for: instance) {
                    Button(AuthoringLanguage.editOriginalComponent) { state.editComponentDefinition(id) }
                    Button("Make independent", action: state.detachComponent)
                        .disabled(!state.pageEditingIsAvailable)
                }
                Button(state.componentReturnActionTitle, action: state.exitComponentDefinition)
                    .disabled(state.editingComponentID == nil)
            }
        }

        CommandMenu("Selection") {
            Button("Isolate Selection") {
                _ = commandState?.enterIsolation(provenance: .menu)
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(commandState?.canIsolateSelection != true)
            Button("Exit Isolation") { commandState?.exitIsolation() }
                .keyboardShortcut(.escape, modifiers: [.command, .option])
                .disabled(commandState?.isolationRootID == nil)
            Button("Exit All Isolation") { commandState?.exitIsolation(all: true) }
                .disabled(commandState?.isolationRootID == nil)
            Divider()
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

        supplementaryAndViewportCommands
    }

    // Keep the outer builder at ten children for toolchains with fixed-arity
    // CommandsBuilder overloads. The command groups retain their native slots.
    @CommandsBuilder private var supplementaryAndViewportCommands: some Commands {
        SiteForgeSupplementaryCommands(state: commandState)
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Quick Open…") { commandState?.isQuickOpenPresented = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(commandState == nil)
            Button("Compare Breakpoints…") { commandState?.showResponsiveComparison() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(commandState == nil)
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

/// Keeps the top-level command builder within the arity supported by the
/// oldest Xcode toolchain used by hosted verification without changing the
/// native Form or Preview menu hierarchy.
private struct SiteForgeSupplementaryCommands: Commands {
    let state: WorkspaceShellState?

    var body: some Commands {
        CommandMenu("Form") {
            Button("Validate Selected Form Locally") {
                _ = state?.validateSelectedFormLocally()
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            .disabled(state?.canValidateSelectedFormLocally != true)
        }

        CommandMenu("Preview") {
            Button("Preview Website in Safari") { state?.openBrowserPreview() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(state == nil)
            Button("Canvas Device Preview") {
                state?.openPreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(state == nil)
            // Commands are installed once for the native menu bar while the
            // focused workspace can continue publishing presentation state.
            // Keep the menu title stable so AppKit never exposes a stale
            // Enter/Exit label during menu tracking; the action remains the
            // same reversible focus-mode toggle for pointer and keyboard use.
            Button("Toggle Focus Mode") {
                state?.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .option, .shift])
            .disabled(state == nil)
            Button("Presentation Mode") { state?.openPresentationMode() }
                .keyboardShortcut("p", modifiers: [.command, .option, .shift])
                .disabled(state == nil)
        }

        CommandMenu("Build") {
            Button("Build Diagnostics…") { state?.openBuildDiagnostics() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(state == nil)
            Button(AuthoringLanguage.checkWebsite) { state?.runStaticBuildPreflight() }
                .disabled(state == nil)
            Button("Cancel Static Build") { state?.cancelStaticBuild() }
                .disabled(state?.staticBuildPhase != .preflighting && state?.staticBuildPhase != .writing)
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
        view.selectionMarqueePresentation = state.selectionMarqueePresentation
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
        view.selectionMarqueePresentation = state.selectionMarqueePresentation
        view.insertionPreviewOverlay = state.insertionPreviewOverlay
        view.transformOverlays = state.transformOverlays
        view.authoredGuides = state.activeGuides
        view.guidePreview = state.guidePreview
        view.snapResolution = state.snapResolution
        view.selectedGuideID = state.selectedGuideID
        view.isWorldGridVisible = state.isWorldGridVisible
        view.textEditingPresentation = state.textEditingPresentation
        view.onInteraction = { state.noteCanvasInteraction() }
        view.onPointerSelectionStart = { point, modifier in
            state.beginCanvasSelectionGesture(point, modifier: modifier)
        }
        view.onPointerSelectionUpdate = { point in state.updateCanvasSelectionMarquee(to: point) }
        view.onPointerSelectionCommit = { state.commitCanvasSelectionMarquee() }
        view.onPointerSelectionCancel = { state.cancelCanvasSelectionMarquee() }
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
        view.onCopySelection = { state.copySelection(provenance: .accessibility) }
        view.onCutSelection = { state.cutSelection(provenance: .accessibility) }
        view.onPasteSelection = { state.pasteSiteForgeObjects(provenance: .accessibility) }
        view.onDuplicateSelection = { state.duplicateSelection(provenance: .accessibility) }
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
        guard let origin = try? viewport.transform.worldToViewport(object.frame.origin) else { return nil }
        return makeLayer(for: object,
            viewportObjectRect: CGRect(x: origin.x, y: origin.y,
                width: object.frame.size.width * viewport.zoom.value,
                height: object.frame.size.height * viewport.zoom.value),
            zoom: viewport.zoom.value, contentsScale: contentsScale)
    }

    static func makeLayer(
        for object: CanvasRenderObject,
        viewportObjectRect: CGRect,
        zoom: Double,
        contentsScale: CGFloat
    ) -> CATextLayer? {
        guard object.plainText != nil,
              object.isVisible,
              object.opacity.isFinite,
              (0...1).contains(object.opacity),
              zoom.isFinite, zoom > 0,
              viewportObjectRect.width.isFinite, viewportObjectRect.height.isFinite,
              viewportObjectRect.minX.isFinite, viewportObjectRect.minY.isFinite,
              viewportObjectRect.width > 0, viewportObjectRect.height > 0,
              let text = object.plainText,
              !text.isEmpty else {
            return nil
        }
        let layout = CanvasTextLayout(
            viewportObjectRect: viewportObjectRect,
            zoom: zoom,
            text: text,
            typography: object.typography
        )
        let layer = CATextLayer()
        layer.name = "renderer.authored-text.\(object.id.description)"
        layer.isGeometryFlipped = true
        layer.frame = layout.glyphBounds
        // Button labels are authored text over a filled surface, not editor
        // chrome. Resolve a readable neutral foreground from that same
        // immutable fill snapshot instead of the application's dark-mode ink.
        let foreground: NSColor
        if let rgba = object.typography?.foregroundRGBA, rgba.count == 4 {
            foreground = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        } else if object.style == .frameSurface,
           let rgba = CanvasAuthoredFillCompositor.resolvedColor(layers: object.fillLayers, atNormalizedPoint: (0.5, 0.5)) ?? object.fillRGBA,
           rgba.count == 4, rgba[3] >= 0.5 {
            foreground = 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2] > 0.5 ? .black : .white
        } else { foreground = layout.foregroundColor }
        layer.string = NSAttributedString(string: text, attributes: [
            .font: layout.font,
            .foregroundColor: foreground,
            .kern: layout.tracking,
            .paragraphStyle: layout.paragraphStyle,
        ])
        layer.font = layout.font
        layer.fontSize = layout.fontSize
        layer.foregroundColor = foreground.cgColor
        layer.opacity = Float(object.opacity)
        layer.alignmentMode = switch layout.alignment { case .center: .center; case .right: .right; default: .left }
        layer.truncationMode = .end
        layer.isWrapped = true
        layer.contentsScale = max(1, contentsScale)
        return layer
    }
}

final class NativeCanvasViewportView: NSView {
    var viewportState = try! CanvasViewportState() {
        didSet {
            // Pan/zoom do not alter world layout. Recompose the last valid
            // immutable raster while its sharper replacement is prepared;
            // breakpoint/artboard changes cannot reuse that layout snapshot.
            discardRasterIfViewportGenerationChanged()
            applyArtboardClipMask()
            rebuildOverlay()
            updateTextEditor()
            if let renderPlan { rebuildAccessibility(renderPlan) }
        }
    }
    var renderPlan: CanvasRenderPlan? {
        didSet {
            if oldValue?.identity.documentID != renderPlan?.identity.documentID { discardRaster() }
            adoptRenderPlan()
        }
    }
    var selectionOverlayPlan: SelectionOverlayPlan? {
        didSet {
            rebuildOverlay()
            if let renderPlan { rebuildAccessibility(renderPlan) }
        }
    }
    var selectionMarqueePresentation: SelectionMarqueePresentation? {
        didSet { rebuildOverlay() }
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
    var onPointerSelectionStart: ((WorldPoint, SelectionPointerModifier) -> Bool)?
    var onPointerSelectionUpdate: ((WorldPoint) -> Void)?
    var onPointerSelectionCommit: (() -> Void)?
    var onPointerSelectionCancel: (() -> Void)?
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
    var onCopySelection: (() -> Bool)?
    var onCutSelection: (() -> Bool)?
    var onPasteSelection: (() -> Bool)?
    var onDuplicateSelection: (() -> Bool)?
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
    private var marqueePointerActive = false
    private var inlineTextView: InlineCanvasTextView?
    private var isApplyingTextPresentation = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentContainer.name = "renderer.authored-content"
        textContainer.name = "renderer.authored-text"
        overlayContainer.name = "renderer.editor-overlays"
        // Reprojection matrices are top-left coordinate transforms, not
        // center-anchored animations. Otherwise scaling adds an unintended
        // (1 - scale) * half-viewport displacement before replacement adopts.
        contentContainer.anchorPoint = .zero
        textContainer.anchorPoint = .zero
        // AppKit already flips this view's backing layer. Flipping an owned
        // container again reflects its child coordinates around its height:
        // pointer Y=80 would paint at height-80. Keep composition containers
        // unflipped; only leaf raster/text APIs own their drawing conversion.
        contentContainer.isGeometryFlipped = false
        textContainer.isGeometryFlipped = false
        overlayContainer.isGeometryFlipped = false
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
    // A document-modal sheet owns interaction without disabling other windows.
    private var isAccessibilityModalBlocked: Bool { window?.attachedSheet != nil }
    override func isAccessibilityElement() -> Bool { !isAccessibilityModalBlocked }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard !isAccessibilityModalBlocked else { return nil }
        return super.accessibilityHitTest(point)
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Canvas viewport" }
    override func accessibilityValue() -> Any? {
        var value = "\(accessibilityViewportValue); rendered objects \(renderPlan?.authoredObjects.count ?? 0)"
        if let marquee = selectionMarqueePresentation {
            value += "; \(marquee.rule.rawValue) marquee; \(marquee.candidateCount) candidates"
        }
        return value
    }
    override func accessibilityChildren() -> [Any]? {
        guard !isAccessibilityModalBlocked else { return [] }
        return virtualAccessibilityElements + selectionContextAccessibilityElements + TransformHandle.allCases.compactMap {
            transformHandleViews[$0.rawValue]
        } + [inlineTextView].compactMap { $0 }
    }
    override func accessibilityHelp() -> String? {
        "Scroll to pan. Pinch to zoom around the pointer. Use the View menu for keyboard controls."
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard !isAccessibilityModalBlocked else { return [] }
        let actions = [
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
            NSAccessibilityCustomAction(name: "Copy Selected Objects") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onCopySelection)
            },
            NSAccessibilityCustomAction(name: "Cut Selected Objects") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onCutSelection)
            },
            NSAccessibilityCustomAction(name: "Paste SiteForge Objects") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onPasteSelection)
            },
            NSAccessibilityCustomAction(name: "Duplicate Selected Objects") { [weak self] in
                CanvasAccessibilityActionDispatcher.perform(self?.onDuplicateSelection)
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
        for action in actions {
            let invoke = action.handler
            action.handler = { [weak self] in
                guard let self, !self.isAccessibilityModalBlocked else { return false }
                return invoke?() ?? false
            }
        }
        return actions
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
        if window == nil, marqueePointerActive {
            marqueePointerActive = false
            onPointerSelectionCancel?()
        }
        notifyResize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // CALayer.frame is derived from bounds/position/transform. Assigning
        // it under the retained pan/zoom transform changes the layer's local
        // coordinates, displacing its pixels from the live selection overlay.
        // Resize in identity coordinates, then restore the shared reprojection.
        contentContainer.setAffineTransform(.identity)
        textContainer.setAffineTransform(.identity)
        contentContainer.frame = bounds
        textContainer.frame = bounds
        overlayContainer.frame = bounds
        CATransaction.commit()
        applyCompositorTransformIfPossible()
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
        marqueePointerActive = onPointerSelectionStart?(world, modifier) ?? false
    }

    override func mouseDragged(with event: NSEvent) {
        if marqueePointerActive {
            let point = convert(event.locationInWindow, from: nil)
            if let world = try? viewportState.transform.viewportToWorld(
                ViewportPoint(x: point.x, y: point.y)
            ) {
                onPointerSelectionUpdate?(world)
            }
            return
        }
        guard updateTransformGesture(with: event) else {
            super.mouseDragged(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        if marqueePointerActive {
            marqueePointerActive = false
            onPointerSelectionCommit?()
            return
        }
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
            if marqueePointerActive {
                marqueePointerActive = false
                onPointerSelectionCancel?()
                return
            }
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
        let pasteboard = window?.isKeyWindow == false
            ? (SiteForgeVisualSystem.canvasPasteboardNSColor.blended(withFraction: 0.10, of: .windowBackgroundColor)
                ?? SiteForgeVisualSystem.canvasPasteboardNSColor)
            : SiteForgeVisualSystem.canvasPasteboardNSColor
        pasteboard.setFill()
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
            context.setFillColor(SiteForgeVisualSystem.artboardSurfaceNSColor.cgColor)
            context.fill(artboard)
            context.setShadow(offset: .zero, blur: 0)
            context.setStrokeColor(SiteForgeVisualSystem.artboardBoundaryNSColor.cgColor)
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
                context.setStrokeColor(
                    (isMajor ? SiteForgeVisualSystem.gridMajorNSColor : SiteForgeVisualSystem.gridMinorNSColor).cgColor
                )
                context.setLineWidth(1 / scale)
                context.move(to: .init(x: aligned(point.x), y: 0)); context.addLine(to: .init(x: aligned(point.x), y: bounds.height)); context.strokePath()
            }
            x += minor
        }
        var y = floor(visible.minY / minor) * minor
        while y <= visible.maxY {
            if let point = try? viewportState.transform.worldToViewport(.init(x: 0, y: y)) {
                let isMajor = abs((y / major).rounded() - y / major) < 0.000_001
                context.setStrokeColor(
                    (isMajor ? SiteForgeVisualSystem.gridMajorNSColor : SiteForgeVisualSystem.gridMinorNSColor).cgColor
                )
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
        guard let plan = renderPlan else { discardRaster(); return }
        // SwiftUI can deliver the state values in separate reconciliation
        // passes.  A plan from an earlier pan/zoom/fit/preset generation must
        // not be transformed to look current: the tile's local origin would
        // no longer share the exact world-to-viewport rect used by overlays.
        // Drop it and wait for the already-scheduled matching generation.
        guard plan.viewport == viewportState else {
            discardRasterIfViewportGenerationChanged()
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
        let objectMap = Dictionary(uniqueKeysWithValues: plan.paintObjects.map { ($0.id, $0) })
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
        for object in plan.authoredObjects where object.plainText != nil && object.isVisible {
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
        applyArtboardClipMask()
        rebuildOverlay()
        rebuildAccessibility(plan)
        CATransaction.commit()
    }

    private func discardRasterIfViewportGenerationChanged() {
        guard let rasterViewportState, rasterViewportState != viewportState else { return }
        if rasterViewportState.sceneID == viewportState.sceneID,
           rasterViewportState.contentBounds == viewportState.contentBounds {
            applyCompositorTransformIfPossible()
            return
        }
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
        func makeMask(for container: CALayer) -> CAShapeLayer {
            let mask = CAShapeLayer()
            mask.frame = container.bounds
            // The clip is specified in live viewport coordinates, while a
            // retained raster/text subtree may still have a pan/zoom transform.
            // Convert once into that subtree or its transform moves the clip
            // a second time, leaving authored slivers over the pasteboard.
            mask.path = CGPath(rect: container.convert(rect, from: layer), transform: nil)
            mask.fillColor = NSColor.white.cgColor
            return mask
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentContainer.mask = makeMask(for: contentContainer)
        textContainer.mask = makeMask(for: textContainer)
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
        if let marquee = selectionMarqueePresentation,
           let origin = try? viewportState.transform.worldToViewport(marquee.frame.origin) {
            let layer = CAShapeLayer()
            layer.name = "renderer.overlay.selection-marquee"
            layer.frame = CGRect(
                x: origin.x, y: origin.y,
                width: marquee.frame.size.width * viewportState.zoom.value,
                height: marquee.frame.size.height * viewportState.zoom.value
            )
            layer.path = CGPath(rect: layer.bounds, transform: nil)
            layer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            layer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor
            layer.lineWidth = 1.5
            layer.lineDashPattern = marquee.rule == .contains ? nil : [4, 3]
            overlayContainer.addSublayer(layer)
        }
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
            layer.path = preview.kind == "flow-insertion-boundary"
                ? CGPath(rect: layer.bounds, transform: nil)
                : CGPath(rect: CanvasViewportDrawGeometry.inset(layer.bounds, dx: 1, dy: 1) ?? .zero, transform: nil)
            layer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            layer.strokeColor = NSColor.controlAccentColor.cgColor
            layer.lineWidth = 2
            layer.lineDashPattern = preview.kind == "flow-insertion-boundary" ? nil : [6, 4]
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
                // Settled selection must not tint the authored color. A live
                // transform has only a restrained, noncanonical preview wash.
                layer.fillColor = overlay.kind == "transform-preview"
                    ? NSColor.controlAccentColor.withAlphaComponent(0.025).cgColor : nil
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
            if let help = item.help { element.setAccessibilityHelp(help) }
            var values = item.textContent.map { ["Text: " + $0] } ?? []
            if let context = selectedOverlays[item.objectID]?.label {
                values.append(context)
                let prefix = item.help.map { $0 + " " } ?? ""
                element.setAccessibilityHelp(prefix + "Selection context: \(context)")
            }
            if !values.isEmpty { element.setAccessibilityValue(values.joined(separator: "; ")) }
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
        textColor = layout.foregroundColor
        textContainerInset = layout.textContainerInset
        textContainer?.lineFragmentPadding = 0
        alignment = layout.alignment
        typingAttributes = [
            .font: layout.font,
            .foregroundColor: layout.foregroundColor,
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
            // A legacy text-placeholder style identifies plain text, not an
            // authored background. Editor selection/focus owns its own chrome.
            case .textPlaceholder: .clear
            }
            // Object opacity applies once to the complete authored layer
            // stack. Individual layer alpha remains part of normal source-over
            // compositing; editor overlays are painted by separate layers.
            context.setAlpha(CGFloat(object.opacity))
            // When an image sits above canonical solid/gradient layers, the
            // authored surface is one group. Applying alpha to each source
            // independently would make a 50% image-over-fill object 75% opaque.
            let groupsImageWithFill = object.imageAssetID != nil
            if groupsImageWithFill { context.beginTransparencyLayer(auxiliaryInfo: nil) }
            let renderedSurface: NSColor
            if !object.fillLayers.isEmpty {
                // Composite the authored stack into one transparency group.
                // The current alpha is applied when that completed group is
                // drawn back into the tile, rather than once per layer.
                if !groupsImageWithFill { context.beginTransparencyLayer(auxiliaryInfo: nil) }
                for layer in object.fillLayers where layer.isEnabled {
                    drawAuthoredFillLayer(layer, in: rect, context: context)
                }
                if !groupsImageWithFill { context.endTransparencyLayer() }
                renderedSurface = CanvasAuthoredFillCompositor.resolvedColor(
                    layers: object.fillLayers,
                    atNormalizedPoint: (x: 0.5, y: 0.5)
                ).flatMap { self.nsColor($0) } ?? fallback
            } else if let rgba = object.fillRGBA, rgba.count == 4 {
                // Compatibility for pre-v1 render snapshots only. Workspace
                // preparation always supplies `fillLayers` for canonical data.
                renderedSurface = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
                context.setFillColor(renderedSurface.cgColor)
                context.fill(rect)
            } else {
                renderedSurface = fallback
                context.setFillColor(fallback.cgColor)
                context.fill(rect)
            }
            var didDrawImage = false
            if object.imageAssetID != nil,
               let data = object.imageData,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, [
                   kCGImageSourceShouldCache: false,
                   kCGImageSourceShouldAllowFloat: true,
               ] as CFDictionary) {
                let mode = object.imageFitMode ?? .fit
                if let resolvedDestination = CanvasImageLayout.destinationRect(
                    source: .init(width: Double(image.width), height: Double(image.height)),
                    bounds: .init(
                        origin: .init(x: rect.origin.x, y: rect.origin.y),
                        size: .init(width: rect.width, height: rect.height)
                    ),
                    mode: mode, focalX: object.imageFocalX, focalY: object.imageFocalY
                ) {
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
            if groupsImageWithFill { context.endTransparencyLayer() }
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
            } else if object.style != .textPlaceholder && (object.style != .imagePlaceholder || !didDrawImage) {
                let baseStroke = object.style == .frameSurface
                    ? NSColor.separatorColor.withAlphaComponent(0.85)
                    : NSColor.separatorColor
                context.setStrokeColor(baseStroke.cgColor)
                context.setLineWidth(1 / max(1, viewportState.pixelRatio.value))
                context.addPath(objectPath)
                context.strokePath()
            }
            // Names belong to Layers and editor selection badges, never to
            // authored surface pixels. Header/Footer/Section role names are
            // not website text and must not survive export or deselection.
            // Plain text is composed once by `textContainer` from the same
            // resolved viewport rect. Tile layers deliberately raster only
            // surfaces so a line crossing a tile boundary cannot duplicate,
            // flip, or drift relative to its selection frame.
            context.restoreGState()
        }
    }

    private func nsColor(_ rgba: [Double]) -> NSColor? {
        guard rgba.count == 4 else { return nil }
        // Canonical normalized channels and CSS output are sRGB, not Generic RGB.
        return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
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
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(
                    colorsSpace: colorSpace,
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
            // SF-0508-003: normalized sampling and CSS extend the first/last
            // stop beyond the interpolation segment. Core Graphics does not
            // do so by default, leaving transparent diagonal corner wedges.
            // The existing authored-shape clip still bounds these endpoint caps.
            context.drawLinearGradient(gradient, start: start, end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
                .foregroundColor: layout.foregroundColor,
                .paragraphStyle: paragraph,
            ]
        )
        drawAppKitText(attributed, in: layout.lineFragmentRect, context: context)
    }

    /// Converts AppKit text drawing at the tile boundary. The canonical world,
    /// viewport, device, Core Animation, overlay, event, hit-test, and
    /// snapshot convention is top-left origin with Y increasing down.
    private func drawAppKitText(_ attributed: NSAttributedString, in rect: CGRect, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.saveGState()
        defer { context.restoreGState() }
        // The enclosing tile already converted Core Graphics to top-left.
        // Tell AppKit the actual basis so it lays out upright glyphs from the
        // top of this rect. This flag describes the CTM; it does not add a
        // second container transform.
        context.clip(to: rect)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
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
    static let baseHorizontalInset: CGFloat = CGFloat(CanvasTextLayoutPolicy.horizontalInset)

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
    var visibleLineCapacity: Int {
        CanvasTextLayoutPolicy.visibleLineCapacity(height: viewportObjectRect.height, lineHeight: lineHeight)
    }
    var foregroundColor: NSColor {
        // Website paper ink must not inherit the editor's dark appearance.
        guard let rgba = typographyForegroundRGBA, rgba.count == 4 else { return .black }
        return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    }
    private let typographyForegroundRGBA: [Double]?

    init(viewportObjectRect: CGRect, zoom: Double, text: String, typography: CanvasTypography? = nil) {
        self.viewportObjectRect = viewportObjectRect
        typographyForegroundRGBA = typography?.foregroundRGBA
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
        return ResponsiveTextMetrics.platformFont(family: typography.authoredFamily,
            weight: typography.weight, size: Double(size), opticalSize: typography.size) as NSFont
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
