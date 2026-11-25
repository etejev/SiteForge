import AppKit
import SwiftUI

// SF-0206: application convenience state, never project content (ADR-0006).
enum ApplicationAppearance: String, Codable, CaseIterable {
    case system, light, dark

    // Owner-selected render-01 editor direction. Explicit saved preferences
    // still win; this default never writes a preference or project property.
    static let editorDefault: ApplicationAppearance = .dark

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
         present: @escaping (ApplicationAppearance) -> Void = { AppearanceSettingsStore.presentNativeAppearance($0) }) {
        self.defaults = defaults
        self.present = present
        committedData = defaults.data(forKey: Self.storageKey)
        draft = ApplicationAppearanceRecord.decode(committedData)
        super.init()
        status = committedData != nil && draft == nil
            ? "Stored appearance is unavailable. Using Dark; Apply or Reset to replace it."
            : "Application appearance loaded. Projects are unchanged."
        if committedData != nil && draft == nil {
            lastDiagnostic = AppearanceSettingsDiagnostic(operation: "load", failureCategory: "unsupported-record", durationSeconds: 0)
        }
        present(resolved)
    }

    private static func presentNativeAppearance(_ appearance: ApplicationAppearance) {
        NSApp.appearance = appearance.nativeAppearance
        if let bundle = Bundle.main.bundleIdentifier {
            DistributedNotificationCenter.default().postNotificationName(
                .init("app.siteforge.testingAppearanceChanged"), object: bundle,
                userInfo: ["appearance": appearance.rawValue], deliverImmediately: true)
        }
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

    var resolved: ApplicationAppearance { ApplicationAppearanceRecord.decode(committedData)?.appearance ?? .editorDefault }
    static func committedAppearance(defaults: UserDefaults = .standard) -> ApplicationAppearance {
        ApplicationAppearanceRecord.decode(defaults.data(forKey: storageKey))?.appearance ?? .editorDefault
    }
    var choice: ApplicationAppearance { draft?.appearance ?? .editorDefault }
    var isDirty: Bool { draft != ApplicationAppearanceRecord.decode(committedData) }
    var canApply: Bool { isDirty || (committedData != nil && ApplicationAppearanceRecord.decode(committedData) == nil) }
    var canRestore: Bool {
        editing && !isDirty && transactions.last?.after == committedData
            && !transactions.isEmpty && defaults.data(forKey: Self.storageKey) == committedData
            && !defaults.objectIsForced(forKey: Self.storageKey)
    }
    var provenance: String {
        if isDirty { return "Preview — not saved. Apply to keep this appearance." }
        return draft == nil ? "Default — Dark editor." : "Set here — this Mac only."
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
        present(.editorDefault)
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
        guard canRestore, let previous = transactions.last, revision < UInt64.max,
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
        // Another Settings owner/managed preference may have saved while the
        // preview was open. Cancel must reveal that value, never replay cache.
        let stored = defaults.data(forKey: Self.storageKey)
        if stored != committedData {
            committedData = stored
            if revision < UInt64.max { revision += 1 }
        }
        draft = ApplicationAppearanceRecord.decode(committedData)
        draftRevision = revision
        present(resolved)
        status = committedData != nil && draft == nil
            ? "Preview cancelled. Stored appearance is unavailable; Dark is shown. Apply or Reset explicitly to replace it."
            : "Preview cancelled. Latest saved appearance restored."
        lastDiagnostic = AppearanceSettingsDiagnostic(operation: "cancel", failureCategory: "none", durationSeconds: 0)
    }

    func close() { cancel(); editing = false }
}

struct AppearanceSettingsView: View {
    @ObservedObject var store: AppearanceSettingsStore

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = SiteForgeChromePalette(scheme: scheme, contrast: contrast)
        VStack(alignment: .leading, spacing: 25) {
            SiteForgeSettingsHeader(title: "Appearance", scope: "", detail: "")
            GroupBox("Theme") {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("App appearance").font(.body.weight(.medium))
                        Spacer(minLength: 8)
                        choices(palette)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App appearance").font(.body.weight(.medium))
                        choices(palette)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .background(AppearanceSettingsWindowHost(store: store).frame(width: 0, height: 0))
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    private func choices(_ palette: SiteForgeChromePalette) -> some View {
        HStack(spacing: 3) {
            ForEach(ApplicationAppearance.allCases, id: \.self) { choice in
                let selected = store.choice == choice
                Button { store.preview(choice) } label: {
                    Text(choice.title == "Follow macOS" ? "System" : choice.title)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(minHeight: 25)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(selected ? palette.text : palette.quiet)
                .accessibilityLabel(choice.title)
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("settings.appearance.choice.\(choice.rawValue)")
            }
        }
        .padding(3)
        .background(palette.inset, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
        .accessibilityIdentifier("settings.appearance.choice")
    }
}

struct AppearanceSettingsActions: View {
    @ObservedObject var store: AppearanceSettingsStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SiteForgeChromePalette { .init(scheme: scheme, contrast: contrast) }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    recoveryActions
                    Spacer(minLength: 8)
                    status
                    commitActions
                }
                VStack(alignment: .trailing, spacing: 8) {
                    status
                    HStack { recoveryActions; Spacer(); commitActions }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 51)
        }
        .background(palette.bar)
    }

    @ViewBuilder private var recoveryActions: some View {
        Button("Reset to Default") { store.reset() }
            .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
            .accessibilityValue(store.draft == nil ? "Already default" : "Reset available")
            .accessibilityIdentifier("settings.appearance.reset")
        if store.canRestore {
            Button("Restore Previous") { store.restorePrevious() }
                .accessibilityIdentifier("settings.appearance.restore")
        }
    }

    private var status: some View {
        Text(store.isDirty ? "Unsaved preview" : store.status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityValue(store.status)
            .accessibilityIdentifier("settings.appearance.status")
    }

    @ViewBuilder private var commitActions: some View {
        Button("Cancel") { store.cancel() }
            .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("settings.appearance.cancel")
        Button("Apply") { store.apply() }
            .buttonStyle(SiteForgeChromeButtonStyle(palette: palette, primary: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!store.canApply)
            .accessibilityIdentifier("settings.appearance.apply")
    }
}

private struct AppearanceSettingsWindowHost: NSViewRepresentable {
    let store: AppearanceSettingsStore
    func makeNSView(context: Context) -> Host { Host(store: store) }
    func updateNSView(_ view: Host, context: Context) {}

    final class Host: NSView {
        private let store: AppearanceSettingsStore
        private var attachmentGeneration: UInt64 = 0
        init(store: AppearanceSettingsStore) { self.store = store; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard attachmentGeneration < UInt64.max else { return }
            attachmentGeneration += 1
            let generation = attachmentGeneration
            guard let targetWindow = window else { return }
            // `viewDidMoveToWindow` can run while SwiftUI is installing the
            // Settings subtree. Publish the initial draft after that native
            // installation boundary, guarded against host reuse or teardown.
            Task { @MainActor [weak self, weak targetWindow] in
                guard let self, let targetWindow,
                      self.attachmentGeneration == generation,
                      self.window === targetWindow else { return }
                self.store.attach(to: targetWindow)
            }
        }
    }
}
