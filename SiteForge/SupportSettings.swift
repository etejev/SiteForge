import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// App-local support state. It is deliberately separate from every canonical
// project and contains no authored content, paths, file names, or raw IDs.
struct ApplicationBuildIdentity: Codable, Equatable, Sendable {
    let product: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let channel: String

    static func current(bundle: Bundle = .main) -> Self {
        Self(
            product: AppMetadata.productName,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            bundleIdentifier: bundle.bundleIdentifier ?? AppMetadata.localBundleIdentifier,
            channel: "Installed distribution"
        )
    }
}

struct RedactedSupportReport: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let application: ApplicationBuildIdentity
    let operatingSystem: String
    let documentSchema: Int
    let diagnosticRetentionLimit: Int
    let recoveryPolicy: String
    let requirementIDs: [String]
    let privacy: String

    init(
        generatedAt: Date,
        application: ApplicationBuildIdentity,
        operatingSystem: String,
        documentSchema: Int = DocumentSerializer.currentSchemaVersion,
        diagnosticRetentionLimit: Int = DiagnosticRetentionPolicy.defaultCapacity
    ) {
        schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.application = application
        self.operatingSystem = operatingSystem
        self.documentSchema = documentSchema
        self.diagnosticRetentionLimit = diagnosticRetentionLimit
        recoveryPolicy = "Recovery snapshots are written only for edited projects and are retired after a durable save."
        requirementIDs = ["SF-0206-004", "SF-0206-006", "SF-0206-008", "SF-1507-003", "SF-1507-004", "SF-1507-006", "SF-1602-004", "SF-1602-006", "SF-1607-002", "SF-1607-003", "SF-1607-004", "SF-1607-006", "SF-1607-008"]
        privacy = "Contains build and compatibility metadata only. Project content, user paths, authored values, credentials, and raw stable identifiers are excluded."
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum SupportReportState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case failed
}

actor RedactedSupportReportCompiler {
    func compile(
        generatedAt: Date,
        application: ApplicationBuildIdentity,
        operatingSystem: String
    ) throws -> Data {
        try Task.checkCancellation()
        let data = try RedactedSupportReport(
            generatedAt: generatedAt,
            application: application,
            operatingSystem: operatingSystem
        ).encoded()
        try Task.checkCancellation()
        return data
    }
}

@MainActor
final class SupportSettingsStore: ObservableObject {
    @Published private(set) var state: SupportReportState = .idle
    @Published private(set) var reportText = ""
    @Published private(set) var status = "Generate a redacted report when you need compatibility or recovery details."
    @Published private(set) var failureCategory = "none"

    let application: ApplicationBuildIdentity
    private let operatingSystem: String
    private let clock: @Sendable () -> Date
    private let compiler = RedactedSupportReportCompiler()
    private var request: UInt64 = 0
    private var task: Task<Void, Never>?

    init(
        application: ApplicationBuildIdentity = .current(),
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.application = application
        self.operatingSystem = operatingSystem
        self.clock = clock
    }

    deinit { task?.cancel() }

    var canCancel: Bool { state == .preparing }
    var canShare: Bool { state == .ready && !reportText.isEmpty }
    var updateSummary: String {
        "Version \(application.version) (\(application.build)) · \(application.channel)"
    }

    func generate() {
        task?.cancel()
        guard request < UInt64.max else {
            state = .failed
            failureCategory = "request-exhausted"
            status = "SF-1607-004: the report request could not start. Reopen Settings and retry."
            return
        }
        request += 1
        let currentRequest = request
        let application = application
        let operatingSystem = operatingSystem
        let generatedAt = clock()
        state = .preparing
        failureCategory = "none"
        status = "Preparing a redacted support report…"
        task = Task(priority: .utility) { [weak self] in
            do {
                guard let compiler = self?.compiler else { return }
                let data = try await compiler.compile(
                    generatedAt: generatedAt,
                    application: application,
                    operatingSystem: operatingSystem
                )
                try Task.checkCancellation()
                guard let text = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                guard let self, self.request == currentRequest else { return }
                reportText = text
                state = .ready
                failureCategory = "none"
                status = "Redacted report ready. Review it before copying or exporting."
            } catch is CancellationError {
                guard let self, self.request == currentRequest else { return }
                state = .idle
                failureCategory = "cancelled"
                status = "Report generation cancelled. The previous project state is unchanged."
            } catch {
                guard let self, self.request == currentRequest else { return }
                state = .failed
                failureCategory = "encoding-failed"
                status = "SF-1607-004: the report could not be prepared. Retry Generate Report."
            }
        }
    }

    func cancel() {
        guard state == .preparing else { return }
        task?.cancel()
    }

    func copyReport() {
        guard canShare else {
            failureCategory = "report-unavailable"
            status = "Generate a report before copying it."
            return
        }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(reportText, forType: .string) else {
            failureCategory = "clipboard-unavailable"
            status = "SF-1607-004: macOS did not accept the report. Retry Copy Report."
            return
        }
        failureCategory = "none"
        status = "Redacted report copied."
    }

    func exportReport() {
        guard canShare else {
            failureCategory = "report-unavailable"
            status = "Generate a report before exporting it."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Redacted Support Report"
        panel.nameFieldStringValue = "SiteForge-Support-Report.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else {
            failureCategory = "cancelled"
            status = "Report export cancelled."
            return
        }
        let data = Data(reportText.utf8)
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    try data.write(to: destination, options: [.atomic])
                }.value
                guard let self else { return }
                self.failureCategory = "none"
                self.status = "Redacted report exported."
            } catch {
                guard let self else { return }
                self.failureCategory = "write-failed"
                self.status = "SF-1607-004: the report could not be written. Choose another location and retry."
            }
        }
    }
}

struct SupportSettingsView: View {
    @ObservedObject var store: SupportSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Support").font(.title2).bold()
                GroupBox("Application & Updates") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Installed", value: store.updateSummary)
                        Text("Updates are provided by the installed distribution. This build does not download or install updates from Settings.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Only a future signed, verified updater may cross the install boundary.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Recovery") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Recovery snapshots are active for edited projects", systemImage: "checkmark.shield")
                        Text("A durable Save retires its recovery snapshot. Launch recovery keeps Restore, Discard, and cancellation explicit.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Diagnostics") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reports contain build, schema, recovery-policy, and bounded-retention metadata. They exclude projects, paths, authored values, credentials, and raw identifiers.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Generate Report") { store.generate() }
                                .disabled(store.state == .preparing)
                                .accessibilityIdentifier("settings.support.generate")
                            Button("Cancel") { store.cancel() }
                                .disabled(!store.canCancel)
                                .accessibilityIdentifier("settings.support.cancel")
                            Spacer()
                            Button("Copy Report") { store.copyReport() }
                                .disabled(!store.canShare)
                                .accessibilityIdentifier("settings.support.copy")
                            Button("Export…") { store.exportReport() }
                                .disabled(!store.canShare)
                                .accessibilityIdentifier("settings.support.export")
                        }
                        if store.canShare {
                            ReviewableSupportReportView(text: store.reportText)
                            .frame(minHeight: 150)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(store.status)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(store.status)
                    .accessibilityIdentifier("settings.support.status")
            }
            .padding(24)
        }
        .frame(minWidth: 560, idealWidth: 560, maxWidth: 560, minHeight: 460)
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
}

@MainActor
private struct ReviewableSupportReportView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityIdentifier("settings.support.report")
        textView.setAccessibilityLabel("Redacted support report")
        textView.setAccessibilityValue(text)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        textView.setAccessibilityValue(text)
    }
}
