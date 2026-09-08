import AppKit
import SwiftUI

// SF-0206: application convenience state, never project content (ADR-0006).
enum ApplicationAppearance: String, Codable, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "Follow macOS"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct ApplicationAppearanceRecord: Codable, Equatable {
    let version: Int
    let preferenceID: String
    let origin: String
    let appearance: ApplicationAppearance

    init(_ appearance: ApplicationAppearance) {
        version = 1
        preferenceID = "application.appearance"
        origin = "authored"
        self.appearance = appearance
    }

    static func decode(_ data: Data?) -> ApplicationAppearanceRecord? {
        guard let data, let record = try? JSONDecoder().decode(Self.self, from: data),
              record.version == 1, record.preferenceID == "application.appearance",
              record.origin == "authored" else { return nil }
        return record
    }
}

struct AppearanceSettingsTransaction {
    let id = UUID()
    let timestamp = Date()
    let actor = "local-user"
    let preferenceID = "application.appearance"
    let operation: String
    let before: Data?
    let after: Data?
}

struct AppearanceSettingsDiagnostic: Encodable {
    let requirementID = "SF-0206-008"
    let preferenceID = "application.appearance"
    let operation: String
    let failureCategory: String
    let durationSeconds: TimeInterval
}

@MainActor
final class AppearanceSettingsStore: NSObject, ObservableObject {
    static let storageKey = "SiteForge.application.appearance.v1"
    @Published private(set) var draft: ApplicationAppearanceRecord?
    @Published private(set) var status = ""
    @Published private(set) var revision: UInt64 = 0
    private(set) var transactions: [AppearanceSettingsTransaction] = []
    private(set) var lastDiagnostic = AppearanceSettingsDiagnostic(
        operation: "load", failureCategory: "none", durationSeconds: 0)
    private let defaults: UserDefaults
    private let present: (ApplicationAppearance) -> Void
    private var committedData: Data?
    private var draftRevision: UInt64 = 0
    private var editing = false
    private weak var settingsWindow: NSWindow?

    init(defaults: UserDefaults = .standard,
         present: @escaping (ApplicationAppearance) -> Void = { NSApp.appearance = $0.nativeAppearance }) {
        self.defaults = defaults
        self.present = present
        committedData = defaults.data(forKey: Self.storageKey)
        draft = ApplicationAppearanceRecord.decode(committedData)
        super.init()
        status = committedData != nil && draft == nil
            ? "Stored appearance is unavailable. Following macOS; Apply or Reset to replace it."
            : "Application appearance loaded. Projects are unchanged."
        if committedData != nil && draft == nil {
            lastDiagnostic = AppearanceSettingsDiagnostic(operation: "load", failureCategory: "unsupported-record", durationSeconds: 0)
        }
        present(resolved)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

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

    var resolved: ApplicationAppearance { ApplicationAppearanceRecord.decode(committedData)?.appearance ?? .system }
    var choice: ApplicationAppearance { draft?.appearance ?? .system }
    var isDirty: Bool { draft != ApplicationAppearanceRecord.decode(committedData) }
    var canApply: Bool { isDirty || (committedData != nil && ApplicationAppearanceRecord.decode(committedData) == nil) }
    var canRestore: Bool { !transactions.isEmpty }
    var provenance: String {
        if isDirty { return "Preview — not saved. Apply to keep this appearance." }
        return draft == nil ? "Default — follows macOS." : "Authored — this Mac only."
    }

    func begin() {
        let stored = defaults.data(forKey: Self.storageKey)
        if stored != committedData {
            committedData = stored
            if revision < UInt64.max { revision += 1 }
        }
        draftRevision = revision
        draft = ApplicationAppearanceRecord.decode(committedData)
        editing = true
    }

    func preview(_ value: ApplicationAppearance) {
        guard editing else { return }
        draft = ApplicationAppearanceRecord(value)
        present(value)
        status = "Appearance preview. Apply to save or Cancel to restore."
    }

    func reset() {
        guard editing else { return }
        draft = nil
        present(.system)
        status = "Reset preview. Apply removes the application override."
    }

    @discardableResult
    func apply() -> Bool {
        guard !defaults.objectIsForced(forKey: Self.storageKey) else {
            lastDiagnostic = AppearanceSettingsDiagnostic(operation: "apply", failureCategory: "managed-preference", durationSeconds: 0)
            status = "SF-0206-004: appearance is managed by your administrator. Cancel to restore."
            return false
        }
        guard editing, draftRevision == revision, revision < UInt64.max,
              defaults.data(forKey: Self.storageKey) == committedData else {
            lastDiagnostic = AppearanceSettingsDiagnostic(operation: "apply", failureCategory: "stale-context", durationSeconds: 0)
            status = "SF-0206-004: appearance changed elsewhere. Cancel and reopen Settings."
            return false
        }
        guard canApply else { status = "No appearance change to save."; return true }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = draft.flatMap { try? encoder.encode($0) }
        return commit(data, operation: draft == nil ? "reset-appearance" : "set-appearance")
    }

    private func commit(_ data: Data?, operation: String) -> Bool {
        let start = ProcessInfo.processInfo.systemUptime
        // A single app-local record is the atomic preference boundary. Unknown
        // future records remain untouched until explicit Apply/Reset.
        let transaction = AppearanceSettingsTransaction(operation: operation, before: committedData, after: data)
        if let data { defaults.set(data, forKey: Self.storageKey) }
        else { defaults.removeObject(forKey: Self.storageKey) }
        guard defaults.data(forKey: Self.storageKey) == data else {
            lastDiagnostic = AppearanceSettingsDiagnostic(operation: operation, failureCategory: "storage-rejected",
                durationSeconds: max(0, ProcessInfo.processInfo.systemUptime - start))
            status = "SF-0206-004: appearance could not be saved. Retry Apply or Cancel."
            return false
        }
        committedData = data
        revision += 1
        draftRevision = revision
        draft = ApplicationAppearanceRecord.decode(data)
        transactions.append(transaction)
        // Bounded session restoration, independent of every document's Undo.
        if transactions.count > 32 { transactions.removeFirst() }
        present(resolved)
        lastDiagnostic = AppearanceSettingsDiagnostic(operation: operation, failureCategory: "none",
            durationSeconds: max(0, ProcessInfo.processInfo.systemUptime - start))
        status = "Appearance saved for this Mac. Projects are unchanged."
        return true
    }

    func restorePrevious() {
        guard editing, let previous = transactions.last, revision < UInt64.max,
              !defaults.objectIsForced(forKey: Self.storageKey),
              defaults.data(forKey: Self.storageKey) == committedData else {
            status = "SF-0206-004: appearance cannot be restored. Cancel and reopen Settings."
            return
        }
        if commit(previous.before, operation: "restore-appearance") {
            status = "Previous appearance restored. Projects are unchanged."
        }
    }

    func cancel() {
        draft = ApplicationAppearanceRecord.decode(committedData)
        draftRevision = revision
        present(resolved)
        status = "Preview cancelled. Saved appearance restored."
        lastDiagnostic = AppearanceSettingsDiagnostic(operation: "cancel", failureCategory: "none", durationSeconds: 0)
    }

    func close() { cancel(); editing = false }
    func closeWindow() { settingsWindow?.performClose(nil) }
}

struct AppearanceSettingsView: View {
    @ObservedObject var store: AppearanceSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance").font(.title2).bold()
            Text("Application · This Mac").font(.headline)
            Text("Changes SiteForge’s native appearance, not your website or project files.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Appearance", selection: Binding(get: { store.choice }, set: { store.preview($0) })) {
                ForEach(ApplicationAppearance.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("settings.appearance.choice")
            Text(store.provenance).accessibilityLabel(store.provenance)
                .accessibilityIdentifier("settings.appearance.provenance")
            Text(store.status).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(store.status)
                .accessibilityIdentifier("settings.appearance.status")
            Divider()
            HStack {
                Button("Reset to macOS") { store.reset() }
                    .accessibilityIdentifier("settings.appearance.reset")
                Button("Restore Previous") { store.restorePrevious() }
                    .disabled(!store.canRestore)
                    .accessibilityIdentifier("settings.appearance.restore")
                Spacer()
            }
            HStack {
                Spacer()
                Button("Close") { store.closeWindow() }
                    .keyboardShortcut("w", modifiers: .command)
                    .accessibilityIdentifier("settings.appearance.close")
                Button("Cancel") { store.cancel() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings.appearance.cancel")
                Button("Apply") { store.apply() }.keyboardShortcut(.defaultAction)
                    .disabled(!store.canApply)
                    .accessibilityIdentifier("settings.appearance.apply")
            }
        }
        .padding(24)
        .frame(width: 460)
        // Native close, not SwiftUI appearance-driven view replacement, owns
        // draft rollback. The host never changes window geometry or content.
        .background(AppearanceSettingsWindowHost(store: store).frame(width: 0, height: 0))
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
}

private struct AppearanceSettingsWindowHost: NSViewRepresentable {
    let store: AppearanceSettingsStore
    func makeNSView(context: Context) -> Host { Host(store: store) }
    func updateNSView(_ view: Host, context: Context) {}

    final class Host: NSView {
        private let store: AppearanceSettingsStore
        init(store: AppearanceSettingsStore) { self.store = store; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { store.attach(to: window) }
        }
    }
}
