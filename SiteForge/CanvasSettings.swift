import AppKit
import Combine
import SwiftUI

// SF-0206: this default belongs to the application. A workspace's Grid toggle
// remains scene-local, and neither value enters a project package.
struct CanvasGridPreferenceRecord: Codable, Equatable {
    let version: Int
    let preferenceID: String
    let origin: String
    let visibleByDefault: Bool

    init(visibleByDefault: Bool) {
        version = 1
        preferenceID = "application.canvas.gridVisibleByDefault"
        origin = "authored"
        self.visibleByDefault = visibleByDefault
    }

    static func decode(_ data: Data?) -> Self? {
        guard let data, let record = try? JSONDecoder().decode(Self.self, from: data),
              record.version == 1,
              record.preferenceID == "application.canvas.gridVisibleByDefault",
              record.origin == "authored" else { return nil }
        return record
    }
}

struct CanvasSettingsTransaction {
    let id = UUID()
    let timestamp = Date()
    let preferenceID = "application.canvas.gridVisibleByDefault"
    let operation: String
    let before: Data?
    let after: Data?
}

struct CanvasSettingsDiagnostic: Encodable {
    let requirementID = "SF-0206-008"
    let preferenceID = "application.canvas.gridVisibleByDefault"
    let operation: String
    let failureCategory: String
}

@MainActor
final class CanvasSettingsStore: NSObject, ObservableObject {
    static let storageKey = "SiteForge.application.canvas.gridVisibleByDefault.v1"

    @Published private(set) var draft: CanvasGridPreferenceRecord?
    @Published private(set) var status = ""
    @Published private(set) var revision: UInt64 = 0
    private(set) var transactions: [CanvasSettingsTransaction] = []
    private(set) var lastDiagnostic = CanvasSettingsDiagnostic(operation: "load", failureCategory: "none")

    private let defaults: UserDefaults
    private var committedData: Data?
    private var draftRevision: UInt64 = 0
    private var editing = false
    private weak var settingsWindow: NSWindow?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        committedData = defaults.data(forKey: Self.storageKey)
        draft = CanvasGridPreferenceRecord.decode(committedData)
        super.init()
        status = committedData != nil && draft == nil
            ? "Stored canvas default is unavailable. New workspaces show Grid; Apply or Reset to replace it."
            : "Canvas default loaded. Open workspaces and projects are unchanged."
        if committedData != nil && draft == nil {
            lastDiagnostic = CanvasSettingsDiagnostic(operation: "load", failureCategory: "unsupported-record")
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    static func committedGridVisibility(defaults: UserDefaults = .standard) -> Bool {
        CanvasGridPreferenceRecord.decode(defaults.data(forKey: storageKey))?.visibleByDefault ?? true
    }

    /// SF-0206-003: the authored application record, or `nil` when this Mac
    /// uses the SiteForge default (or holds an unsupported record).
    static func committedGridRecord(defaults: UserDefaults = .standard) -> CanvasGridPreferenceRecord? {
        CanvasGridPreferenceRecord.decode(defaults.data(forKey: storageKey))
    }

    var resolved: Bool { Self.committedGridVisibility(defaults: defaults) }
    var choice: Bool { draft?.visibleByDefault ?? true }
    var isDirty: Bool { draft != CanvasGridPreferenceRecord.decode(committedData) }
    var canApply: Bool { isDirty || (committedData != nil && CanvasGridPreferenceRecord.decode(committedData) == nil) }
    var canRestore: Bool {
        editing && !isDirty && transactions.last?.after == committedData
            && !transactions.isEmpty && defaults.data(forKey: Self.storageKey) == committedData
            && !defaults.objectIsForced(forKey: Self.storageKey)
    }
    var provenance: String {
        if isDirty { return "Draft — Apply to use this default for new workspaces." }
        return draft == nil ? "Default — Grid shown in new workspaces." : "Authored — this Mac only."
    }

    func attach(to window: NSWindow) {
        if settingsWindow !== window {
            NotificationCenter.default.removeObserver(self)
            settingsWindow = window
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)),
                name: NSWindow.didBecomeKeyNotification, object: window)
        }
        if !editing { begin() }
    }

    @objc private func windowWillClose(_ notification: Notification) { close() }
    @objc private func windowBecameKey(_ notification: Notification) {
        if !editing { begin() }
    }

    func begin() {
        let stored = defaults.data(forKey: Self.storageKey)
        if stored != committedData {
            committedData = stored
            if revision < UInt64.max { revision += 1 }
        }
        draftRevision = revision
        draft = CanvasGridPreferenceRecord.decode(committedData)
        editing = true
    }

    func choose(_ visible: Bool) {
        guard editing else { return }
        draft = CanvasGridPreferenceRecord(visibleByDefault: visible)
        status = "Canvas default draft. Apply to affect new workspaces; open workspaces are unchanged."
    }

    func reset() {
        guard editing else { return }
        draft = nil
        status = "Reset draft. Apply to show Grid in new workspaces by default."
    }

    @discardableResult
    func apply() -> Bool {
        guard !defaults.objectIsForced(forKey: Self.storageKey) else {
            lastDiagnostic = CanvasSettingsDiagnostic(operation: "apply", failureCategory: "managed-preference")
            status = "SF-0206-004: canvas default is managed by your administrator. Cancel to restore."
            return false
        }
        guard editing, draftRevision == revision, revision < UInt64.max,
              defaults.data(forKey: Self.storageKey) == committedData else {
            lastDiagnostic = CanvasSettingsDiagnostic(operation: "apply", failureCategory: "stale-context")
            status = "SF-0206-004: canvas default changed elsewhere. Cancel and reopen Settings."
            return false
        }
        guard canApply else { status = "No canvas default change to save."; return true }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = draft.flatMap { try? encoder.encode($0) }
        return commit(data, operation: draft == nil ? "reset-grid-default" : "set-grid-default")
    }

    private func commit(_ data: Data?, operation: String) -> Bool {
        let transaction = CanvasSettingsTransaction(operation: operation, before: committedData, after: data)
        if let data { defaults.set(data, forKey: Self.storageKey) }
        else { defaults.removeObject(forKey: Self.storageKey) }
        guard defaults.data(forKey: Self.storageKey) == data else {
            lastDiagnostic = CanvasSettingsDiagnostic(operation: operation, failureCategory: "storage-rejected")
            status = "SF-0206-004: canvas default could not be saved. Retry Apply or Cancel."
            return false
        }
        committedData = data
        revision += 1
        draftRevision = revision
        draft = CanvasGridPreferenceRecord.decode(data)
        transactions.append(transaction)
        if transactions.count > 32 { transactions.removeFirst() }
        lastDiagnostic = CanvasSettingsDiagnostic(operation: operation, failureCategory: "none")
        status = "Canvas default saved for new workspaces. Open workspaces and projects are unchanged."
        return true
    }

    func restorePrevious() {
        guard canRestore, let previous = transactions.last, revision < UInt64.max,
              !defaults.objectIsForced(forKey: Self.storageKey),
              defaults.data(forKey: Self.storageKey) == committedData else {
            status = "SF-0206-004: canvas default cannot be restored. Cancel and reopen Settings."
            return
        }
        if commit(previous.before, operation: "restore-grid-default") {
            status = "Previous canvas default restored for new workspaces."
        }
    }

    func cancel() {
        let stored = defaults.data(forKey: Self.storageKey)
        if stored != committedData {
            committedData = stored
            if revision < UInt64.max { revision += 1 }
        }
        draft = CanvasGridPreferenceRecord.decode(committedData)
        draftRevision = revision
        status = committedData != nil && draft == nil
            ? "Canvas draft cancelled. Stored default is unavailable; new workspaces show Grid. Apply or Reset explicitly to replace it."
            : "Canvas default draft cancelled. Latest saved preference retained."
        lastDiagnostic = CanvasSettingsDiagnostic(operation: "cancel", failureCategory: "none")
    }

    func close() { cancel(); editing = false }
}

struct CanvasSettingsView: View {
    @ObservedObject var store: CanvasSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            SiteForgeSettingsHeader(
                title: "Canvas",
                scope: AuthoringLanguage.appPreferencesScope,
                detail: "Choose how new workspaces begin. Each open workspace keeps its own Grid state."
            )
            GroupBox("New workspace") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    Toggle("Show grid in new workspaces", isOn: Binding(
                        get: { store.choice }, set: { store.choose($0) }
                    ))
                    .accessibilityIdentifier("settings.canvas.gridDefault")
                    Text(store.status).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.canvas.status")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Reset to Default") { store.reset() }
                    .accessibilityValue(store.draft == nil ? "Already default" : "Reset available")
                    .accessibilityIdentifier("settings.canvas.reset")
                Button("Restore Previous") { store.restorePrevious() }
                    .disabled(!store.canRestore)
                    .accessibilityIdentifier("settings.canvas.restore")
                Spacer()
            }
            HStack {
                Spacer()
                Button("Cancel") { store.cancel() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings.canvas.cancel")
                Button("Apply") { store.apply() }.keyboardShortcut(.defaultAction)
                    .disabled(!store.canApply)
                    .accessibilityIdentifier("settings.canvas.apply")
            }
        }
        .frame(maxWidth: SiteForgeVisualSystem.settingsContentMaxWidth, alignment: .topLeading)
        .background(CanvasSettingsWindowHost(store: store).frame(width: 0, height: 0))
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
}

private struct CanvasSettingsWindowHost: NSViewRepresentable {
    let store: CanvasSettingsStore
    func makeNSView(context: Context) -> Host { Host(store: store) }
    func updateNSView(_ view: Host, context: Context) {}

    final class Host: NSView {
        private let store: CanvasSettingsStore
        private var attachmentGeneration: UInt64 = 0
        init(store: CanvasSettingsStore) { self.store = store; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard attachmentGeneration < UInt64.max else { return }
            attachmentGeneration += 1
            let generation = attachmentGeneration
            guard let targetWindow = window else { return }
            Task { @MainActor [weak self, weak targetWindow] in
                guard let self, let targetWindow,
                      self.attachmentGeneration == generation,
                      self.window === targetWindow else { return }
                self.store.attach(to: targetWindow)
            }
        }
    }
}

/// One reversible application-only operation across the two implemented
/// preference records. Project files and scene-local viewport state are not
/// participants; an unknown future record is removed only after confirmation.
@MainActor
final class ApplicationSettingsGroupStore: ObservableObject {
    struct Snapshot: Equatable {
        let appearance: Data?
        let canvas: Data?
    }

    struct Transaction {
        let id = UUID()
        let operation: String
        let before: Snapshot
        let after: Snapshot
    }

    @Published private(set) var status = "Application defaults are unchanged."
    @Published private(set) var isPending = false
    private(set) var transactions: [Transaction] = []
    private(set) var failureCategory = "none"

    private let defaults: UserDefaults
    let appearance: AppearanceSettingsStore
    let canvas: CanvasSettingsStore
    private var pendingBefore: Snapshot?

    init(defaults: UserDefaults = .standard, appearance: AppearanceSettingsStore,
         canvas: CanvasSettingsStore) {
        self.defaults = defaults
        self.appearance = appearance
        self.canvas = canvas
    }

    var canRestore: Bool {
        guard let previous = transactions.last else { return false }
        return !isPending && !isManaged && !appearance.isDirty && !canvas.isDirty
            && current == previous.after
    }
    var appearanceSummary: String {
        AppearanceSettingsStore.committedAppearance(defaults: defaults).title
    }
    var canvasSummary: String {
        CanvasSettingsStore.committedGridVisibility(defaults: defaults) ? "On" : "Off"
    }

    private var current: Snapshot {
        Snapshot(appearance: defaults.data(forKey: AppearanceSettingsStore.storageKey),
                 canvas: defaults.data(forKey: CanvasSettingsStore.storageKey))
    }

    private var isManaged: Bool {
        defaults.objectIsForced(forKey: AppearanceSettingsStore.storageKey)
            || defaults.objectIsForced(forKey: CanvasSettingsStore.storageKey)
    }

    func stageReset() {
        guard !appearance.isDirty && !canvas.isDirty else {
            failureCategory = "unsaved-draft"
            status = "Apply or cancel the current Settings draft before resetting application defaults."
            return
        }
        guard !isManaged else {
            failureCategory = "managed-preference"
            status = "Application defaults are managed by your administrator and cannot be reset here."
            return
        }
        guard current != Snapshot(appearance: nil, canvas: nil) else {
            failureCategory = "none"
            status = "Application defaults already use the Dark editor and show Grid in new workspaces."
            return
        }
        pendingBefore = current
        isPending = true
        failureCategory = "none"
        status = "Confirm to reset Appearance and new-workspace Grid defaults. Projects and open workspaces are unchanged."
    }

    func cancel() {
        pendingBefore = nil
        isPending = false
        failureCategory = "none"
        status = "Application-default reset cancelled. Saved preferences are unchanged."
    }

    @discardableResult
    func commitReset() -> Bool {
        guard let before = pendingBefore, isPending, !isManaged,
              !appearance.isDirty, !canvas.isDirty, current == before else {
            failureCategory = "stale-or-unavailable"
            status = "Application defaults changed. Cancel and review Settings before retrying."
            return false
        }
        let after = Snapshot(appearance: nil, canvas: nil)
        guard write(after, restoring: before) else { return false }
        record(Transaction(operation: "reset-application-defaults", before: before, after: after))
        pendingBefore = nil
        isPending = false
        failureCategory = "none"
        synchronizeTabs()
        status = "Application defaults reset. Dark editor; new workspaces show Grid. Projects are unchanged."
        return true
    }

    @discardableResult
    func restorePrevious() -> Bool {
        guard !isPending, let previous = transactions.last, !isManaged,
              !appearance.isDirty, !canvas.isDirty, current == previous.after else {
            failureCategory = "stale-or-unavailable"
            status = "Previous defaults cannot be restored. Review Settings before retrying."
            return false
        }
        guard write(previous.before, restoring: previous.after) else { return false }
        record(Transaction(operation: "restore-application-defaults",
                           before: previous.after, after: previous.before))
        failureCategory = "none"
        synchronizeTabs()
        status = "Previous application defaults restored. Projects are unchanged."
        return true
    }

    private func write(_ target: Snapshot, restoring original: Snapshot) -> Bool {
        set(target.appearance, forKey: AppearanceSettingsStore.storageKey)
        set(target.canvas, forKey: CanvasSettingsStore.storageKey)
        guard current == target else {
            set(original.appearance, forKey: AppearanceSettingsStore.storageKey)
            set(original.canvas, forKey: CanvasSettingsStore.storageKey)
            failureCategory = current == original ? "storage-rejected" : "rollback-failed"
            if failureCategory == "rollback-failed" { synchronizeTabs() }
            status = current == original
                ? "Application defaults could not be saved; the prior values were restored."
                : "Application defaults need review; storage rejected the reset and rollback."
            return false
        }
        return true
    }

    private func set(_ data: Data?, forKey key: String) {
        if let data { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    private func synchronizeTabs() {
        appearance.begin()
        appearance.cancel()
        canvas.begin()
        canvas.cancel()
    }

    private func record(_ transaction: Transaction) {
        transactions.append(transaction)
        if transactions.count > 32 { transactions.removeFirst() }
    }
}

struct ApplicationSettingsGroupView: View {
    @ObservedObject var store: ApplicationSettingsGroupStore
    @ObservedObject private var appearance: AppearanceSettingsStore
    @ObservedObject private var canvas: CanvasSettingsStore

    init(store: ApplicationSettingsGroupStore) {
        self.store = store
        _appearance = ObservedObject(wrappedValue: store.appearance)
        _canvas = ObservedObject(wrappedValue: store.canvas)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            SiteForgeSettingsHeader(
                title: "Application Defaults",
                scope: AuthoringLanguage.appPreferencesScope,
                detail: "Review or reset the Appearance and new-workspace Grid defaults together."
            )
            GroupBox("Current defaults") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    LabeledContent("Appearance", value: store.appearanceSummary)
                    LabeledContent("New workspace Grid", value: store.canvasSummary)
                    Text(store.status).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.group.status")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Restore Previous") { store.restorePrevious() }
                    .disabled(!store.canRestore || store.isPending)
                    .accessibilityIdentifier("settings.group.restore")
                Spacer()
                if store.isPending {
                    Button("Cancel") { store.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("settings.group.cancel")
                    Button("Confirm Reset") { store.commitReset() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("settings.group.confirm")
                } else {
                    Button("Reset Application Defaults…") { store.stageReset() }
                        .accessibilityIdentifier("settings.group.stage")
                }
            }
        }
        .frame(maxWidth: SiteForgeVisualSystem.settingsContentMaxWidth, alignment: .topLeading)
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .onDisappear {
            if store.isPending { store.cancel() }
        }
    }
}


// MARK: - SF-0206 project-scoped preferences

/// SF-0206-001/002/003/004/006/008: the Settings Project pane edits the active
/// project's canonical preferences. The draft is Settings UI state only. Apply
/// commits one document transaction through that workspace's session, so Undo,
/// autosave, recovery and save/reopen follow ordinary project history. A
/// different or closed project, a concurrent change or a busy lifecycle never
/// receives a stale draft. This Mac's application preferences are untouched.
@MainActor
final class ProjectSettingsStore: NSObject, ObservableObject {
    /// Value-free record: requirement IDs, operation, sanitized document
    /// identity, stable preference identities, duration and failure category.
    struct Diagnostic: Equatable {
        let requirementIDs: [String]
        let operation: String
        let sanitizedDocumentID: String?
        let preferenceIDs: [String]
        let durationMilliseconds: Int
        let failureCategory: String
    }

    @Published private(set) var draft: ProjectPreferences?
    @Published private(set) var committed: ProjectPreferences?
    @Published private(set) var hasProject = false
    @Published private(set) var projectTitle = ""
    @Published private(set) var isStale = false
    /// SF-0206-004 read-only state: why the open project cannot accept edits now.
    @Published private(set) var unavailableReason: String?
    @Published private(set) var status = "Open or create a project in a SiteForge window to edit its preferences. Appearance and Canvas hold this Mac's preferences."
    private(set) var lastDiagnostic = Diagnostic(requirementIDs: ["SF-0206-003", "SF-0206-008"], operation: "load",
        sanitizedDocumentID: nil, preferenceIDs: [], durationMilliseconds: 0, failureCategory: "none")

    nonisolated static let noProjectStatus = "Open or create a project in a SiteForge window to edit its preferences. Appearance and Canvas hold this Mac's preferences."

    private let defaults: UserDefaults
    private let resolveTarget: @MainActor () -> WorkspaceShellState?
    private weak var target: WorkspaceShellState?
    private var documentID: DocumentID?
    private var observations: Set<AnyCancellable> = []
    private weak var settingsWindow: NSWindow?

    init(defaults: UserDefaults = .standard,
         resolveTarget: @escaping @MainActor () -> WorkspaceShellState? = { ActiveWorkspaceResolver.current() }) {
        self.defaults = defaults
        self.resolveTarget = resolveTarget
        super.init()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var isDirty: Bool { hasProject && draft != committed }
    var availability: (isAvailable: Bool, reason: String?) {
        target?.projectPreferencesAvailability ?? (false, "Open a project to edit its preferences.")
    }
    var canApply: Bool { isDirty && !isStale && availability.isAvailable }
    var gridVisibilityChoice: Bool? { draft?.gridVisibleOnOpen }
    var gridSpacingChoice: Double? { draft?.gridSpacing }
    /// The draft keeps a stored value that breaks its rule (SF-0206-004).
    var draftHasInvalidGridSpacing: Bool { draft?.invalidPreferenceIDs.contains(.gridSpacing) == true }
    /// The draft sets a preference this pane shows, so Reset has something to
    /// remove. Build settings share the record but are edited in Check Website.
    var draftHasGridPreferences: Bool { Self.hasGridPreferences(draft) }
    var applicationGridDefault: Bool? { CanvasSettingsStore.committedGridRecord(defaults: defaults)?.visibleByDefault }
    var gridVisibilityResolution: ProjectPreferenceResolution<Bool> {
        ProjectPreferenceResolver.gridVisibleOnOpen(draft, applicationDefault: applicationGridDefault)
    }
    var gridSpacingResolution: ProjectPreferenceResolution<Double> { ProjectPreferenceResolver.gridSpacing(draft) }

    /// SF-0206-003: names the rule that wins and the effective value.
    var gridVisibilityProvenance: String {
        let resolution = gridVisibilityResolution
        let source: String = switch resolution.source {
        case .project: "Set in this project"
        case .application: "Follows this Mac's Canvas default"
        case .builtIn, .invalidProjectValue: "SiteForge default"
        }
        return "\(source) — Grid \(resolution.value ? "shown" : "hidden") when the project opens\(isDirty ? " · Draft" : "")."
    }

    var gridSpacingProvenance: String {
        let resolution = gridSpacingResolution
        let spacing = "\(ProjectGridSpacingChoice.label(resolution.value)) minor lines, "
            + "\(ProjectGridSpacingChoice.label(resolution.value * 4)) major"
        let draftMark = isDirty ? " · Draft" : ""
        switch resolution.source {
        case .project:
            return "Set in this project — \(spacing)\(draftMark)."
        case .invalidProjectValue:
            let stored = draft?.gridSpacing.map(ProjectGridSpacingChoice.label) ?? "The saved value"
            return "\(stored) breaks the rule: whole points from 4 through 128. Using the SiteForge default, \(spacing), "
                + "until you choose a valid spacing or Use SiteForge Default\(draftMark)."
        case .application, .builtIn:
            return "SiteForge default — \(spacing)\(draftMark)."
        }
    }

    func attach(to window: NSWindow) {
        if settingsWindow !== window {
            NotificationCenter.default.removeObserver(self)
            settingsWindow = window
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)),
                name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window)
        }
        if !isDirty { begin() }
    }

    @objc private func windowBecameKey(_ notification: Notification) { if !isDirty { begin() } }
    @objc private func windowWillClose(_ notification: Notification) { cancel() }

    /// Re-resolves the active project. A clean pane shows the latest committed
    /// values; a dirty draft is never moved to another project.
    func begin() {
        let started = ContinuousClock.now
        observations.removeAll()
        guard let state = resolveTarget() else {
            target = nil; documentID = nil; committed = nil; draft = nil
            hasProject = false; projectTitle = ""; isStale = false; unavailableReason = nil
            status = Self.noProjectStatus
            record("load", started: started, failure: "no-project")
            return
        }
        target = state
        let document = state.documentSession.document
        documentID = document.id
        committed = document.projectPreferences
        draft = committed
        hasProject = true
        isStale = false
        projectTitle = state.projectPreferencesTitle
        status = Self.hasGridPreferences(committed)
            ? "Project preferences loaded. They are saved in the project file."
            : "This project follows this Mac's Canvas default and SiteForge's grid spacing."
        state.documentSession.$document.dropFirst().sink { [weak self] document in
            DispatchQueue.main.async { [weak self] in self?.documentChanged(document) }
        }.store(in: &observations)
        // Preview and file conflicts gate every document edit. Re-read the
        // gate on the next main turn so the pane never publishes mid-update.
        state.$isPreviewPresented.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.refreshAvailability() }
        }.store(in: &observations)
        state.lifecycle.$phase.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.refreshAvailability() }
        }.store(in: &observations)
        refreshAvailability()
        let invalid = committed?.invalidPreferenceIDs ?? []
        if !invalid.isEmpty {
            status = "SF-0206-004: this project stores an invalid grid spacing. It is kept unchanged and the SiteForge default is used until you repair it."
        }
        record("load", started: started, failure: invalid.isEmpty ? "none" : "invalid-stored-value", preferences: invalid)
    }

    func refreshAvailability() {
        let current = availability
        let reason = hasProject && !current.isAvailable
            ? "\(current.reason ?? "The project is busy.") Project preferences can be applied afterwards; your draft is kept."
            : nil
        if unavailableReason != reason { unavailableReason = reason }
    }

    private func documentChanged(_ document: CanonicalDocument) {
        guard let target, target.documentSession.document.id == document.id,
              target.documentSession.document.revision == document.revision else { return }
        guard document.id == documentID else {
            // The workspace opened another project. A clean pane follows it; a
            // draft written for the previous project can only be cancelled.
            if isDirty {
                isStale = true
                status = "SF-0206-004: a different project is now open. Cancel to discard this draft; the open project is unchanged."
            } else {
                begin()
            }
            return
        }
        guard document.projectPreferences != committed else { return }
        if isDirty, Self.sameGridPreferences(document.projectPreferences, committed) {
            // Only the build settings stored with these preferences changed
            // (Check Website or its Undo, ADR-0122). This pane does not show
            // them, so the grid draft is kept on top of the current values
            // instead of being discarded as stale (SF-0206-004, ADR-0140).
            var rebased = draft ?? ProjectPreferences()
            rebased.build = document.projectPreferences?.build
            committed = document.projectPreferences
            draft = rebased.isEmpty ? nil : rebased
            isStale = false
            status = "Build settings changed in Check Website. Your grid draft is kept; Apply saves it with the current build settings."
            record("rebase-draft", started: .now, failure: "none")
            return
        }
        if isDirty {
            isStale = true
            status = "SF-0206-004: this project's preferences changed elsewhere, for example by Undo. Cancel to review the current values."
        } else {
            committed = document.projectPreferences
            draft = committed
            status = "Project preferences updated from the project."
        }
    }

    func chooseGridVisibility(_ value: Bool?) {
        guard hasProject else { return }
        var next = draft ?? ProjectPreferences()
        next.gridVisibleOnOpen = value
        draft = next.isEmpty ? nil : next
        status = Self.draftStatus
    }

    /// Accepts a valid spacing, `nil` (SiteForge default), or re-selecting the
    /// project's own stored value even when it breaks its rule; never a new
    /// invalid value. A rejected choice leaves the draft unchanged.
    func chooseGridSpacing(_ value: Double?) {
        guard hasProject else { return }
        let keepsStored = value != nil && value == committed?.gridSpacing
        guard value.map(ProjectPreferences.isValidGridSpacing) ?? true || keepsStored else {
            status = ProjectPreferencesError.invalidValue.localizedDescription
            record("choose-grid-spacing", started: .now, failure: "invalid-value", preferences: [.gridSpacing])
            return
        }
        var next = draft ?? ProjectPreferences()
        next.gridSpacing = value
        draft = next.isEmpty ? nil : next
        status = Self.draftStatus
    }

    /// SF-0206-004 specific repair: drafts removing an invalid stored spacing
    /// so the project follows the SiteForge default. Apply commits it.
    func repairGridSpacing() {
        guard hasProject, draftHasInvalidGridSpacing else { return }
        chooseGridSpacing(nil)
        status = "Repair draft. Apply to remove the invalid grid spacing; Undo in the project window restores it."
        record("repair-draft", started: .now, failure: "none", preferences: [.gridSpacing])
    }

    /// SF-0206-004 group reset: drafts the removal of every preference this
    /// pane shows. Build settings (ADR-0122) are edited in Check Website, so
    /// they are kept: Reset never removes a value the pane does not display.
    func reset() {
        guard hasProject else { return }
        draft = committed?.build.map { ProjectPreferences(build: $0) }
        status = draft == nil
            ? "Reset draft. Apply to remove this project's preferences; it will follow this Mac and SiteForge defaults."
            : "Reset draft. Apply to remove this project's grid preferences; its build settings stay and are edited in Check Website."
    }

    /// Brings a SiteForge window forward so the user can open or create a
    /// project (the empty state's first action). Returns false when none is open.
    @discardableResult
    func focusProjectWindow() -> Bool {
        guard let window = NSApp.windows.first(where: {
            $0 !== settingsWindow && $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain
        }) else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    @discardableResult
    func apply() -> Bool {
        let started = ContinuousClock.now
        guard let target, let documentID, hasProject else {
            status = "Open a project before applying project preferences."
            record("apply", started: started, failure: "no-project")
            return false
        }
        let changed = draft?.changedPreferenceIDs(from: committed)
            ?? committed?.changedPreferenceIDs(from: nil) ?? []
        guard !isStale else {
            status = "SF-0206-004: this draft no longer matches the open project. Cancel to review the current values."
            record("apply", started: started, failure: "stale-context", preferences: changed)
            return false
        }
        guard isDirty else { status = "No project preference change to save."; return true }
        do {
            try target.commitProjectPreferences(.replace(draft), expectedDocumentID: documentID,
                                                expectedPreferences: committed)
        } catch let error as ProjectPreferencesError {
            if error == .stale { isStale = true }
            status = error.localizedDescription
            refreshAvailability()
            record("apply", started: started, failure: Self.category(error), preferences: changed)
            return false
        } catch {
            status = "SF-0206-004: project preferences could not be saved. The project is unchanged; retry Apply or Cancel."
            record("apply", started: started, failure: "command-rejected", preferences: changed)
            return false
        }
        committed = target.documentSession.document.projectPreferences
        draft = committed
        if committed == nil {
            status = "Project preferences removed. This project follows this Mac and SiteForge defaults; Undo in the project window restores them."
        } else if Self.hasGridPreferences(committed) {
            status = "Project preferences saved in this project. Use Undo in the project window to revert."
        } else {
            status = "Grid preferences removed. This project follows this Mac and SiteForge grid defaults; its build settings stay. Undo in the project window restores them."
        }
        record(committed == nil ? "reset-project-preferences" : "set-project-preferences", started: started,
               failure: "none", preferences: changed)
        return true
    }

    func cancel() {
        let started = ContinuousClock.now
        if let target, let documentID, target.documentSession.document.id == documentID {
            committed = target.documentSession.document.projectPreferences
            draft = committed
            isStale = false
            status = "Project draft cancelled. Saved project preferences retained."
            refreshAvailability()
        } else {
            begin()
        }
        record("cancel", started: started, failure: "none")
    }

    nonisolated private static let draftStatus = "Project draft. Apply to save it in this project; Cancel keeps the saved values."

    private static func hasGridPreferences(_ preferences: ProjectPreferences?) -> Bool {
        preferences?.gridVisibleOnOpen != nil || preferences?.gridSpacing != nil
    }

    private static func sameGridPreferences(_ lhs: ProjectPreferences?, _ rhs: ProjectPreferences?) -> Bool {
        lhs?.gridVisibleOnOpen == rhs?.gridVisibleOnOpen && lhs?.gridSpacing == rhs?.gridSpacing
    }

    private static func category(_ error: ProjectPreferencesError) -> String {
        switch error {
        case .stale: "stale-context"
        case .cancelled: "cancelled"
        case .invalidValue, .invalidBuildBudget: "invalid-value"
        case .unavailable: "lifecycle-unavailable"
        case .noChanges: "no-changes"
        }
    }

    /// Requirement IDs follow the operation: resolution on load, commits on
    /// set/reset, recovery for every failure or repair; SF-0206-008 always.
    nonisolated static func requirementIDs(operation: String, failure: String) -> [String] {
        let specific: [String]
        if failure != "none" || operation == "repair-draft" { specific = ["SF-0206-004"] }
        else if operation == "load" { specific = ["SF-0206-003"] }
        else if operation == "set-project-preferences" || operation == "reset-project-preferences" {
            specific = ["SF-0206-001", "SF-0206-002", "SF-0206-005"]
        } else { specific = ["SF-0206-002"] }
        return specific + ["SF-0206-008"]
    }

    /// SF-0206-008: no preference values or project content are recorded.
    private func record(_ operation: String, started: ContinuousClock.Instant, failure: String,
                        preferences: [ProjectPreferenceID] = []) {
        let elapsed = started.duration(to: .now).components
        let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        lastDiagnostic = Diagnostic(requirementIDs: Self.requirementIDs(operation: operation, failure: failure),
            operation: operation,
            sanitizedDocumentID: documentID.map {
                DiagnosticStableIdentifier.sanitize($0.description, domain: .document, kind: "document")
            },
            preferenceIDs: preferences.map(\.rawValue),
            durationMilliseconds: Int(max(0, milliseconds)), failureCategory: failure)
    }
}

/// Settings choice for the project's Grid-on-open preference.
enum ProjectGridVisibilityChoice: String, CaseIterable, Identifiable {
    case followMac, shown, hidden

    init(_ value: Bool?) { self = value.map { $0 ? .shown : .hidden } ?? .followMac }

    var id: String { rawValue }
    var value: Bool? {
        switch self {
        case .followMac: nil
        case .shown: true
        case .hidden: false
        }
    }
    var title: String {
        switch self {
        case .followMac: "Follow this Mac"
        case .shown: "Show Grid"
        case .hidden: "Hide Grid"
        }
    }
}

/// Settings choice for the project's grid spacing. `nil` is the SiteForge
/// default and stays distinct from an authored 16 pt.
struct ProjectGridSpacingChoice: Hashable, Identifiable {
    let points: Double?

    init(_ points: Double?) { self.points = points }

    var id: String { points.map { "spacing-\($0)" } ?? "default" }
    var title: String {
        guard let points else {
            return "SiteForge default (\(Self.label(ProjectPreferences.defaultGridSpacing)))"
        }
        return ProjectPreferences.isValidGridSpacing(points)
            ? Self.label(points)
            : "\(Self.label(points)) — invalid, using \(Self.label(ProjectPreferences.defaultGridSpacing))"
    }

    static func label(_ points: Double) -> String {
        let format = abs(points) < 100_000 ? "%.0f pt" : "%.3g pt"
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), points)
    }

    /// Keeps the project's own authored value selectable, including a stored
    /// value outside the convenience list or one that breaks its rule.
    static func options(including current: Double?) -> [Self] {
        var values = ProjectPreferences.gridSpacingChoices
        if let current, !values.contains(current) { values.append(current); values.sort() }
        return [Self(nil)] + values.map { Self($0) }
    }
}

struct ProjectSettingsView: View {
    @ObservedObject var store: ProjectSettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            SiteForgeSettingsHeader(
                title: "Project",
                scope: AuthoringLanguage.projectPreferencesScope,
                detail: store.hasProject
                    ? "\(store.projectTitle). These preferences are saved in the project file and win over this Mac's defaults."
                    : "Preferences that travel with a project file appear here while a project is open."
            )
            if store.hasProject {
                GroupBox("Canvas") {
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                        Picker("Grid when the project opens", selection: Binding(
                            get: { ProjectGridVisibilityChoice(store.gridVisibilityChoice) },
                            set: { store.chooseGridVisibility($0.value) }
                        )) {
                            ForEach(ProjectGridVisibilityChoice.allCases) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .accessibilityIdentifier("settings.project.gridVisibility")
                        provenance(store.gridVisibilityProvenance, identifier: "settings.project.gridVisibility.source")
                        Picker("Grid spacing", selection: Binding(
                            get: { ProjectGridSpacingChoice(store.gridSpacingChoice) },
                            set: { store.chooseGridSpacing($0.points) }
                        )) {
                            ForEach(ProjectGridSpacingChoice.options(including: store.gridSpacingChoice)) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .accessibilityIdentifier("settings.project.gridSpacing")
                        provenance(store.gridSpacingProvenance, identifier: "settings.project.gridSpacing.source")
                        if store.draftHasInvalidGridSpacing {
                            Button("Use SiteForge Default") { store.repairGridSpacing() }
                                .help("Remove the invalid saved spacing so this project uses 16 pt.")
                                .accessibilityIdentifier("settings.project.gridSpacing.repair")
                        }
                        if let reason = store.unavailableReason {
                            Text(reason).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityValue(reason)
                                .accessibilityIdentifier("settings.project.availability")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                GroupBox("No project open") {
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                        Text(store.status).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityValue(store.status)
                            .accessibilityIdentifier("settings.project.status")
                        Button("Open or Create a Project…") {
                            if !store.focusProjectWindow() { openWindow(id: "workspace") }
                        }
                        .help("Show the SiteForge window, where you can create a project or open one.")
                        .accessibilityIdentifier("settings.project.showWindow")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: SiteForgeVisualSystem.settingsContentMaxWidth, alignment: .topLeading)
        .background(ProjectSettingsWindowHost(store: store).frame(width: 0, height: 0))
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    private func provenance(_ text: String, identifier: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityValue(text)
            .accessibilityIdentifier(identifier)
    }
}

struct ProjectSettingsActions: View {
    @ObservedObject var store: ProjectSettingsStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = SiteForgeChromePalette(scheme: scheme, contrast: contrast)
        VStack(spacing: 0) {
            Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack {
                    reset
                    Spacer(minLength: 8)
                    status
                    commitActions
                }
                VStack(alignment: .trailing, spacing: 8) {
                    status
                    HStack { reset; Spacer(); commitActions }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 51)
        }
        .background(palette.bar)
    }

    private var reset: some View {
        Button("Reset Project Preferences") { store.reset() }
            .disabled(!store.draftHasGridPreferences)
            .accessibilityValue(store.draftHasGridPreferences ? "Reset available" : "Already following defaults")
            .accessibilityIdentifier("settings.project.reset")
    }

    private var status: some View {
        Text(store.status).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityValue(store.status)
            .accessibilityIdentifier("settings.project.status")
    }

    private var commitActions: some View {
        HStack {
            Button("Cancel") { store.cancel() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("settings.project.cancel")
            Button("Apply") { store.apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canApply)
                .help(store.unavailableReason ?? "Save these preferences in the project.")
                .accessibilityIdentifier("settings.project.apply")
        }
    }
}

private struct ProjectSettingsWindowHost: NSViewRepresentable {
    let store: ProjectSettingsStore
    func makeNSView(context: Context) -> Host { Host(store: store) }
    func updateNSView(_ view: Host, context: Context) {}

    final class Host: NSView {
        private let store: ProjectSettingsStore
        private var attachmentGeneration: UInt64 = 0
        init(store: ProjectSettingsStore) { self.store = store; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard attachmentGeneration < UInt64.max else { return }
            attachmentGeneration += 1
            let generation = attachmentGeneration
            guard let targetWindow = window else { return }
            Task { @MainActor [weak self, weak targetWindow] in
                guard let self, let targetWindow,
                      self.attachmentGeneration == generation,
                      self.window === targetWindow else { return }
                self.store.attach(to: targetWindow)
            }
        }
    }
}
