import AppKit
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

    var resolved: Bool { Self.committedGridVisibility(defaults: defaults) }
    var choice: Bool { draft?.visibleByDefault ?? true }
    var isDirty: Bool { draft != CanvasGridPreferenceRecord.decode(committedData) }
    var canApply: Bool { isDirty || (committedData != nil && CanvasGridPreferenceRecord.decode(committedData) == nil) }
    var canRestore: Bool { !transactions.isEmpty }
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
        guard editing, let previous = transactions.last, revision < UInt64.max,
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
        draft = CanvasGridPreferenceRecord.decode(committedData)
        draftRevision = revision
        status = "Canvas default draft cancelled. Saved preference retained."
        lastDiagnostic = CanvasSettingsDiagnostic(operation: "cancel", failureCategory: "none")
    }

    func close() { cancel(); editing = false }
}

struct CanvasSettingsView: View {
    @ObservedObject var store: CanvasSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Canvas").font(.title2).bold()
            Text("Application default · This Mac").font(.headline)
            Text("Use the Grid button in each workspace to change that window. This setting chooses how new workspaces start.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Show grid in new workspaces", isOn: Binding(
                get: { store.choice }, set: { store.choose($0) }
            ))
            .accessibilityIdentifier("settings.canvas.gridDefault")
            Text(store.provenance)
                .accessibilityIdentifier("settings.canvas.provenance")
            Text(store.status).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.canvas.status")
            Divider()
            HStack {
                Button("Reset to Default") { store.reset() }
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
        .padding(24)
        .frame(width: 460)
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
        init(store: CanvasSettingsStore) { self.store = store; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { store.attach(to: window) }
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
            status = "Application defaults already follow macOS and show Grid in new workspaces."
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
        status = "Application defaults reset. Appearance follows macOS; new workspaces show Grid. Projects are unchanged."
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Application Defaults").font(.title2).bold()
            Text("This Mac · Not stored in projects").font(.headline)
            Text("Reset the Appearance and new-workspace Grid defaults together. Open workspaces keep their Grid state.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LabeledContent("Appearance", value: store.appearanceSummary)
            LabeledContent("New workspace Grid", value: store.canvasSummary)
            Text(store.status).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.group.status")
            Divider()
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
        .padding(24)
        .frame(width: 460)
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .onDisappear {
            if store.isPending { store.cancel() }
        }
    }
}
