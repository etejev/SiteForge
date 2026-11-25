import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum UpdateChannel: String, CaseIterable, Codable, Sendable, Identifiable {
    case stable, preview
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct UpdateVersion: Equatable, Comparable, Sendable {
    let components: [Int]
    let prerelease: String?

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numeric = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !numeric.isEmpty, numeric.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              numeric.count <= 4 else { return nil }
        var normalizedComponents = numeric.map { Int($0)! }
        while normalizedComponents.count > 1, normalizedComponents.last == 0 {
            normalizedComponents.removeLast()
        }
        components = normalizedComponents
        prerelease = parts.count == 2 && !parts[1].isEmpty ? String(parts[1]) : nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(left), .some(right)): return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

struct UpdateRelease: Equatable, Sendable {
    let version: String
    let build: String?
    let channel: UpdateChannel
    let notes: String
    let downloadSize: Int64?
    let provenanceHost: String
    let artifactURL: URL?
    let signature: String?
    let sha256: String?
    let minimumSystemVersion: String?
    let bundleIdentifier: String?
}

enum UpdateTrustFailure: String, Error, Equatable, Sendable {
    case ownerPolicyDisabled = "owner-policy-disabled"
    case artifactUnavailable = "artifact-unavailable"
    case unsigned = "signature-unverified"
    case integrityUnverified = "integrity-unverified"
    case bundleMismatch = "bundle-mismatch"
    case channelMismatch = "channel-mismatch"
    case rollbackRejected = "rollback-rejected"
    case incompatibleSystem = "incompatible-system"
}

/// Pure fail-closed installation boundary. Feed parsing may discover releases,
/// but only an owner-approved adapter may supply verified trust facts.
struct UpdateInstallTrustPolicy: Sendable {
    let ownerPolicyEnabled: Bool

    func validate(
        _ release: UpdateRelease,
        installed: ApplicationBuildIdentity,
        selectedChannel: UpdateChannel,
        systemVersion: String? = nil
    ) -> Result<Void, UpdateTrustFailure> {
        guard ownerPolicyEnabled else { return .failure(.ownerPolicyDisabled) }
        guard release.channel == selectedChannel else { return .failure(.channelMismatch) }
        guard let installedVersion = UpdateVersion(installed.version),
              let candidateVersion = UpdateVersion(release.version),
              candidateVersion > installedVersion else { return .failure(.rollbackRejected) }
        guard release.artifactURL?.scheme == "https" else { return .failure(.artifactUnavailable) }
        guard release.signature?.isEmpty == false else { return .failure(.unsigned) }
        guard release.sha256?.isEmpty == false else { return .failure(.integrityUnverified) }
        guard release.bundleIdentifier == installed.bundleIdentifier else { return .failure(.bundleMismatch) }
        if let minimum = release.minimumSystemVersion,
           let required = UpdateVersion(minimum),
           let current = UpdateVersion(systemVersion ?? Self.currentSystemVersion) {
            guard current >= required else { return .failure(.incompatibleSystem) }
        }
        return .success(())
    }

    private static var currentSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

enum UpdateCheckFailure: Error, Equatable, Sendable {
    case offline, cancelled, malformedMetadata, incompatible, policyBlocked, transport
}

protocol UpdateFeedChecking: Sendable {
    func latestRelease(channel: UpdateChannel) async throws -> UpdateRelease?
}

/// Public GitHub metadata adapter. It never authenticates and never installs.
/// Signed artifact verification remains behind the typed handoff boundary.
struct GitHubReleaseFeedAdapter: UpdateFeedChecking {
    let releasesURL: URL?

    func latestRelease(channel: UpdateChannel) async throws -> UpdateRelease? {
        guard let releasesURL, releasesURL.scheme == "https" else { throw UpdateCheckFailure.policyBlocked }
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw UpdateCheckFailure.transport
            }
            let records = try JSONDecoder().decode([GitHubReleaseRecord].self, from: data)
            let matching = records.filter { !$0.draft && (channel == .preview || !$0.prerelease) }
            guard let release = matching.first else { return nil }
            guard let version = UpdateVersion(release.tagName) else { throw UpdateCheckFailure.malformedMetadata }
            let artifact = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            return UpdateRelease(
                version: version.components.map(String.init).joined(separator: ".")
                    + (version.prerelease.map { "-\($0)" } ?? ""),
                build: nil,
                channel: release.prerelease ? .preview : .stable,
                notes: release.body ?? "No release notes were provided.",
                downloadSize: artifact?.size,
                provenanceHost: releasesURL.host ?? "github.com",
                artifactURL: artifact?.browserDownloadURL,
                signature: nil,
                sha256: nil,
                minimumSystemVersion: nil,
                bundleIdentifier: nil
            )
        } catch is CancellationError { throw UpdateCheckFailure.cancelled }
        catch let failure as UpdateCheckFailure { throw failure }
        catch let error as URLError where error.code == .notConnectedToInternet { throw UpdateCheckFailure.offline }
        catch is DecodingError { throw UpdateCheckFailure.malformedMetadata }
        catch { throw UpdateCheckFailure.transport }
    }
}

private struct GitHubReleaseRecord: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int64
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name, size; case browserDownloadURL = "browser_download_url" }
    }
    let tagName: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case body, draft, prerelease, assets; case tagName = "tag_name" }
}

enum UpdatePresentationState: Equatable, Sendable {
    case idle, checking, upToDate, available(UpdateRelease), downloading(Double), verifying
    case readyToRelaunch(UpdateRelease), offline, cancelled, failed, incompatible, policyBlocked
}

struct UpdateDiagnostic: Equatable, Sendable {
    let requirementID: String
    let requestID: UInt64
    let operation: String
    let failureCategory: String
}

@MainActor
final class UpdateSettingsStore: ObservableObject {
    static let automaticChecksKey = "SiteForgeUpdateAutomaticChecks.v1"
    static let channelKey = "SiteForgeUpdateChannel.v1"
    @Published private(set) var state: UpdatePresentationState = .idle
    let channel: UpdateChannel = .stable
    @Published var automaticallyChecks: Bool { didSet { defaults.set(automaticallyChecks, forKey: Self.automaticChecksKey) } }
    @Published private(set) var status = "Updates have not been checked in this session."
    @Published private(set) var lastDiagnostic = UpdateDiagnostic(requirementID: "SF-1507-008", requestID: 0, operation: "idle", failureCategory: "none")
    let application: ApplicationBuildIdentity
    private let defaults: UserDefaults
    private let feed: any UpdateFeedChecking
    private let trustPolicy: UpdateInstallTrustPolicy
    private var requestID: UInt64 = 0
    private var task: Task<Void, Never>?

    init(application: ApplicationBuildIdentity = .current(), defaults: UserDefaults = .standard,
         feed: (any UpdateFeedChecking)? = nil,
         trustPolicy: UpdateInstallTrustPolicy = .init(ownerPolicyEnabled: false)) {
        self.application = application
        self.defaults = defaults
        automaticallyChecks = defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        let url = Bundle.main.object(forInfoDictionaryKey: "SiteForgeUpdateFeedURL") as? String
        self.feed = feed ?? GitHubReleaseFeedAdapter(releasesURL: url.flatMap(URL.init(string:)))
        self.trustPolicy = trustPolicy
    }

    deinit { task?.cancel() }
    var canCancel: Bool { state == .checking || state == .verifying || { if case .downloading = state { true } else { false } }() }
    var update: UpdateRelease? { if case .available(let release) = state { release } else if case .readyToRelaunch(let release) = state { release } else { nil } }

    func check() {
        cancel(silent: true)
        guard requestID < UInt64.max else { publish(.failed, operation: "check", failure: "request-exhausted", text: "Update checking is unavailable until Settings is reopened."); return }
        requestID += 1
        let request = requestID
        let channel = channel
        state = .checking
        status = "Checking for a compatible update…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await feed.latestRelease(channel: channel)
                try Task.checkCancellation()
                guard requestID == request else { return }
                guard let release else { publish(.upToDate, operation: "check", failure: "none", text: "No compatible update is available."); return }
                guard let installed = UpdateVersion(application.version), let candidate = UpdateVersion(release.version) else {
                    publish(.failed, operation: "check", failure: "malformed-version", text: "Release metadata contains an invalid version. The installed app is unchanged."); return
                }
                guard candidate > installed else {
                    publish(.upToDate, operation: "check", failure: "rollback-rejected", text: "SiteForge is up to date. Older releases are never installed automatically."); return
                }
                publish(.available(release), operation: "check", failure: "none", text: "SiteForge \(release.version) is available from \(release.provenanceHost).")
            } catch let failure as UpdateCheckFailure {
                guard requestID == request else { return }
                switch failure {
                case .offline: publish(.offline, operation: "check", failure: "offline", text: "You appear to be offline. Keep working and try again later.")
                case .cancelled: publish(.cancelled, operation: "check", failure: "cancelled", text: "Update check cancelled. The installed app is unchanged.")
                case .incompatible: publish(.incompatible, operation: "check", failure: "incompatible", text: "The available update is not compatible with this Mac.")
                case .policyBlocked: publish(.policyBlocked, operation: "check", failure: "feed-unconfigured", text: "Update checking is policy-blocked until the owner approves the signed release feed.")
                case .malformedMetadata: publish(.failed, operation: "check", failure: "malformed-metadata", text: "Release metadata could not be verified. The installed app is unchanged.")
                case .transport: publish(.failed, operation: "check", failure: "transport", text: "The update service could not be reached securely. Try again later.")
                }
            } catch { guard requestID == request else { return }; publish(.failed, operation: "check", failure: "unexpected", text: "The update check failed safely. The installed app is unchanged.") }
        }
    }

    func cancel(silent: Bool = false) {
        guard task != nil else { return }
        if requestID < UInt64.max { requestID += 1 }
        task?.cancel(); task = nil
        if !silent { publish(.cancelled, operation: "cancel", failure: "cancelled", text: "Update check cancelled. The installed app is unchanged.") }
    }

    func requestTrustedInstall() {
        guard let update else { return }
        switch trustPolicy.validate(update, installed: application, selectedChannel: channel) {
        case .success:
            // No installer adapter is enabled in this bounded slice. Reaching
            // this state proves metadata trust only and still fails closed.
            publish(.policyBlocked, operation: "install", failure: "installer-unconfigured",
                    text: "The update metadata is trusted, but no approved installer is configured. The installed app is unchanged.")
        case .failure(let failure):
            publish(.policyBlocked, operation: "install", failure: failure.rawValue,
                    text: "Installation is blocked until a signed, notarized updater and trusted feed are approved. The installed app is unchanged.")
        }
    }

    private func publish(_ state: UpdatePresentationState, operation: String, failure: String, text: String) {
        self.state = state; status = text
        lastDiagnostic = UpdateDiagnostic(requirementID: "SF-1507-008", requestID: requestID,
                                          operation: operation, failureCategory: failure)
    }
}

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
            channel: bundle.object(forInfoDictionaryKey: "SiteForgeSourceFingerprint") != nil
                ? "Owner-local build" : "Installed distribution"
        )
    }
}

/// Bundle provenance is local application metadata, never website content.
enum LocalArtifactProvenance {
    static func summary(bundle: Bundle = .main) -> String? {
        guard let revision = bundle.object(forInfoDictionaryKey: "SiteForgeSourceRevision") as? String,
              let fingerprint = bundle.object(forInfoDictionaryKey: "SiteForgeSourceFingerprint") as? String,
              let date = bundle.object(forInfoDictionaryKey: "SiteForgeLocalBuildTimestamp") as? String,
              revision.count == 40, fingerprint.count == 64,
              revision.allSatisfy({ $0.isHexDigit }), fingerprint.allSatisfy({ $0.isHexDigit }),
              date.count <= 32 else { return nil }
        let dirty = bundle.object(forInfoDictionaryKey: "SiteForgeSourceDirty") as? Bool == true
        return "\(dirty ? "Uncommitted" : "Committed") local source · checkpoint \(revision.prefix(7)) · snapshot \(fingerprint.prefix(12)) · built \(date)"
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
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            SiteForgeSettingsHeader(
                title: "Support",
                scope: AuthoringLanguage.appPreferencesScope,
                detail: "Review updates, recovery policy, and privacy-preserving diagnostics."
            )
            GroupBox("Application & Updates") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    LabeledContent("Installed", value: store.updateSummary)
                    if let provenance = LocalArtifactProvenance.summary() {
                        Text(provenance).font(.caption).textSelection(.enabled)
                            .accessibilityIdentifier("settings.support.buildProvenance")
                    }
                    Text("Updates are provided by the installed distribution. This build does not download or install updates from Settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Only a future signed, verified updater may cross the install boundary.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Recovery") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    Label("Recovery snapshots are active for edited projects", systemImage: "checkmark.shield")
                    Text("A durable Save retires its recovery snapshot. Launch recovery keeps Restore, Discard, and cancellation explicit.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Diagnostics") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
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
                        .background(SiteForgeVisualSystem.fieldSurface, in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.fieldCornerRadius))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(store.status)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(store.status)
                .accessibilityIdentifier("settings.support.status")
        }
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

enum SettingsDestination: String, CaseIterable, Identifiable, Sendable {
    case appearance, canvas, accessibility, defaults, updates, support, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .canvas: "Canvas"
        case .accessibility: "Accessibility"
        case .defaults: "Defaults"
        case .updates: "Updates"
        case .support: "Support"
        case .advanced: "Advanced"
        }
    }
    var symbol: String {
        switch self {
        case .appearance: "paintbrush"
        case .canvas: "grid"
        case .accessibility: "accessibility"
        case .defaults: "slider.horizontal.3"
        case .updates: "arrow.triangle.2.circlepath"
        case .support: "lifepreserver"
        case .advanced: "gearshape.2"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published private(set) var selection: SettingsDestination = .appearance
    private var requestID = UUID()
    func show(_ destination: SettingsDestination) {
        requestID = UUID()
        if selection != destination { selection = destination }
    }
    func selectFromNativeList(_ destination: SettingsDestination) {
        let id = UUID(); requestID = id
        // List writes selection during native/SwiftUI reconciliation. Publish
        // once at the next event turn; a newer row or explicit Review wins.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, requestID == id else { return }
            show(destination)
        }
    }
}

struct SettingsDraftNotice: Equatable, Sendable {
    let destinations: [SettingsDestination]
    init(appearanceDirty: Bool, canvasDirty: Bool) {
        destinations = (appearanceDirty ? [.appearance] : []) + (canvasDirty ? [.canvas] : [])
    }
    var message: String {
        guard !destinations.isEmpty else { return "No unsaved application preferences." }
        return "Unsaved \(destinations.map(\.title).joined(separator: " and ")) changes. Review and Apply to keep them, or cancel drafts. Project files are unchanged."
    }
}

struct SettingsWindowGeometry: Equatable {
    let contentSize: NSSize
    let sidebarWidth: CGFloat
    let formWidth: CGFloat
    static let preferred = Self(contentSize: .init(width: SiteForgeVisualSystem.settingsIdealWidth,
        height: SiteForgeVisualSystem.settingsIdealHeight - 28),
        sidebarWidth: SiteForgeVisualSystem.settingsSidebarWidth, formWidth: SiteForgeVisualSystem.settingsContentMaxWidth)

    static func resolve(visibleFrame: NSRect, titlebarHeight: CGFloat = 28) -> Self? {
        guard [visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height, titlebarHeight].allSatisfy(\.isFinite),
              visibleFrame.width >= 640, visibleFrame.height >= 400, titlebarHeight >= 0 else { return nil }
        let width = min(preferred.contentSize.width, visibleFrame.width - 16)
        let height = min(SiteForgeVisualSystem.settingsIdealHeight, visibleFrame.height - 16) - titlebarHeight
        guard height > 0 else { return nil }
        return .init(contentSize: .init(width: width, height: height), sidebarWidth: preferred.sidebarWidth,
                     formWidth: min(preferred.formWidth, width - preferred.sidebarWidth - 1 - 2 * SiteForgeVisualSystem.settingsHorizontalInset))
    }
}

@MainActor
enum SettingsWindowPolicy {
    static let identifier = NSUserInterfaceItemIdentifier("SiteForge.Settings")
    @discardableResult static func apply(to window: NSWindow, visibleFrame: NSRect) -> SettingsWindowGeometry? {
        guard window.identifier == identifier else { return nil }
        window.styleMask.remove([.resizable, .fullSizeContentView])
        window.toolbar = nil
        window.titlebarAppearsTransparent = false
        window.title = "SiteForge Settings"
        window.collectionBehavior.subtract([.fullScreenPrimary, .fullScreenAuxiliary, .fullScreenAllowsTiling])
        window.collectionBehavior.formUnion([.fullScreenNone, .fullScreenDisallowsTiling])
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let previousAutosaveName = window.frameAutosaveName
        if !previousAutosaveName.isEmpty { NSWindow.removeFrame(usingName: previousAutosaveName) }
        window.setFrameAutosaveName("")
        let titlebar = window.frameRect(forContentRect: .init(x: 0, y: 0, width: 100, height: 100)).height - 100
        guard let geometry = SettingsWindowGeometry.resolve(visibleFrame: visibleFrame, titlebarHeight: titlebar) else { return nil }
        window.contentMinSize = geometry.contentSize
        window.contentMaxSize = geometry.contentSize
        window.setContentSize(geometry.contentSize)
        var frame = window.frame
        frame.origin.x = min(max(frame.minX, visibleFrame.minX + 8), visibleFrame.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.minY, visibleFrame.minY + 8), visibleFrame.maxY - frame.height - 8)
        window.setFrame(frame, display: true)
        return geometry
    }
}

private struct FixedSettingsWindowHost: NSViewRepresentable {
    let onGeometry: @MainActor (SettingsWindowGeometry) -> Void
    func makeNSView(context: Context) -> Host { Host(onGeometry: onGeometry) }
    func updateNSView(_ view: Host, context: Context) { view.onGeometry = onGeometry }
    static func dismantleNSView(_ view: Host, coordinator: ()) { view.detach() }

    final class Host: NSView {
        var onGeometry: @MainActor (SettingsWindowGeometry) -> Void
        private var generation = UUID()
        init(onGeometry: @escaping @MainActor (SettingsWindowGeometry) -> Void) { self.onGeometry = onGeometry; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        deinit { NotificationCenter.default.removeObserver(self) }
        func detach() { generation = UUID(); NotificationCenter.default.removeObserver(self) }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let target = window else { return }
            target.identifier = SettingsWindowPolicy.identifier
            NotificationCenter.default.addObserver(self, selector: #selector(windowEvent(_:)), name: NSWindow.didBecomeKeyNotification, object: target)
            NotificationCenter.default.addObserver(self, selector: #selector(windowEvent(_:)), name: NSWindow.didChangeScreenNotification, object: target)
            let expected = generation
            Task { @MainActor [weak self, weak target] in
                guard let self, let target, self.generation == expected, self.window === target else { return }
                self.configure()
            }
        }
        @objc private func windowEvent(_ notification: Notification) { configure() }
        private func configure() {
            guard let window, window.isVisible, let screen = window.screen ?? NSScreen.main,
                  let geometry = SettingsWindowPolicy.apply(to: window, visibleFrame: screen.visibleFrame) else { return }
            onGeometry(geometry)
        }
    }
}

struct SiteForgeSettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var appearance: AppearanceSettingsStore
    @ObservedObject var canvas: CanvasSettingsStore
    @ObservedObject var defaults: ApplicationSettingsGroupStore
    @ObservedObject var updates: UpdateSettingsStore
    @ObservedObject var support: SupportSettingsStore
    @StateObject private var testing = ExperimentalTestingStore.shared
    @State private var geometry = SettingsWindowGeometry.resolve(visibleFrame: NSScreen.main?.visibleFrame ?? .zero) ?? .preferred

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focusedDestination: SettingsDestination?
    private var palette: SiteForgeChromePalette { .init(scheme: scheme, contrast: contrast) }
    private let destinations = SettingsDestination.allCases
    private var selection: SettingsDestination { navigation.selection }

    init(
        navigation: SettingsNavigationModel,
        appearance: AppearanceSettingsStore,
        canvas: CanvasSettingsStore,
        defaults: ApplicationSettingsGroupStore,
        updates: UpdateSettingsStore,
        support: SupportSettingsStore
    ) {
        self.navigation = navigation
        self.appearance = appearance
        self.canvas = canvas
        self.defaults = defaults
        self.updates = updates
        self.support = support
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                sidebar
                Rectangle().fill(palette.line).frame(width: 1).accessibilityHidden(true)
                ScrollView {
                    destinationForm
                        .frame(width: geometry.formWidth, alignment: .topLeading)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(selection.title + " preferences")
                        .accessibilityIdentifier("settings.form")
                        .padding(.top, 40)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .id(selection)
                .groupBoxStyle(SiteForgeSettingsGroupStyle())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.content")
            }
            if selection == .appearance {
                AppearanceSettingsActions(store: appearance)
            }
            if selection != .appearance || canvas.isDirty {
                pendingDraftNotice

            }
        }
        .frame(width: geometry.contentSize.width, height: geometry.contentSize.height)
        .background(palette.base)
        .background(FixedSettingsWindowHost { updated in if geometry != updated { geometry = updated } }.frame(width: 0, height: 0))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.root")
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(destinations) { destination in
                    SiteForgeSettingsSidebarRow(title: destination.title, symbol: destination.symbol,
                                                 selected: selection == destination) {
                        navigation.show(destination)
                    }
                    .focused($focusedDestination, equals: destination)
                    .onMoveCommand { direction in
                        guard direction == .up || direction == .down,
                              let index = destinations.firstIndex(of: destination) else { return }
                        let next = index + (direction == .up ? -1 : 1)
                        guard destinations.indices.contains(next) else { return }
                        focusedDestination = destinations[next]
                        navigation.show(destinations[next])
                    }
                    .accessibilityIdentifier("settings.sidebar.\(destination.rawValue)")
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 29)
            .padding(.bottom, 19)
        }
        .frame(width: geometry.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(palette.panel)
        .accessibilityLabel("Settings categories")
        .accessibilityIdentifier("settings.sidebar")
    }

    @ViewBuilder private var destinationForm: some View {
        switch selection {
        case .appearance: AppearanceSettingsView(store: appearance)
        case .canvas: CanvasSettingsView(store: canvas)
        case .accessibility: SiteForgeAccessibilitySettingsView()
        case .defaults: ApplicationSettingsGroupView(store: defaults)
        case .updates: UpdateSettingsView(store: updates)
        case .support: SupportSettingsView(store: support)
        case .advanced: ExperimentalTestingView(store: testing)
        }
    }

    @ViewBuilder private var pendingDraftNotice: some View {
        let notice = SettingsDraftNotice(appearanceDirty: appearance.isDirty, canvasDirty: canvas.isDirty)
        if !notice.destinations.isEmpty {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                Divider()
                Text(notice.message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(notice.message).accessibilityIdentifier("settings.drafts.status")
                ViewThatFits(in: .horizontal) {
                    HStack {
                        draftReviewActions(notice)
                        Spacer()
                        cancelDraftsAction
                    }
                    VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) {
                        draftReviewActions(notice)
                        cancelDraftsAction
                    }
                }.controlSize(.small)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Unsaved application preferences")
            .accessibilityIdentifier("settings.drafts")
            .padding(SiteForgeVisualSystem.settingsFormPadding)
            .frame(width: geometry.formWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(.bar)
        }
    }

    @ViewBuilder private func draftReviewActions(_ notice: SettingsDraftNotice) -> some View {
        ForEach(notice.destinations) { destination in
            Button("Review \(destination.title)") { navigation.show(destination) }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("settings.drafts.review." + destination.rawValue)
        }
    }
    private var cancelDraftsAction: some View {
        Button("Cancel Drafts") { appearance.cancel(); canvas.cancel() }
            .fixedSize(horizontal: true, vertical: false)
            .help("Reload the latest saved application preferences without changing project files.")
            .accessibilityIdentifier("settings.drafts.cancel")
    }
}

/// Development targets are available only when the owner-local installer has
/// provisioned a matching harness. Public distributions remain unavailable.
@MainActor
final class ExperimentalTestingStore: ObservableObject {
    static let shared = ExperimentalTestingStore()
    @Published var scopePolicy: TestingScopePolicy = .all
    @Published var selectorText = ""
    @Published var requestDescription: String?
    @Published private(set) var scopeDescription = "All prepared methods in the selected target."
    @Published private(set) var scopeReady = true
    @Published private(set) var snapshot: TestingRunSnapshot?
    @Published private(set) var history: [TestingRunRecord] = []
    @Published private(set) var viewedRun: URL?
    @Published private(set) var controlPending = false
    @Published private(set) var cancellationRequested = false
    var presentationNotice: String? {
        if viewedRun != nil { return "Viewing a retained run" + (running ? " · the current run continues independently." : ".") }
        guard let snapshot else { return status }
        let lifecycle = ["Testing \(snapshot.status). Detailed logs and results are retained locally.",
                         "Starting detached testing. This installed app and your open documents remain untouched.",
                         "Resuming testing…", "Pausing after the current case…", "Cancelling testing…"]
        return lifecycle.contains(status) ? nil : status
    }
    var displayedPhase: String {
        if viewedRun == nil && running {
            if cancellationRequested { return "cancelling" }
            if controlPending { return snapshot?.status == "paused" ? "resuming" : "pausing" }
        }
        return snapshot?.status ?? "preparing"
    }
    @Published var affectedBase = "origin/main"
    private var preparedSelectors: [String] = []
    private var scopeGeneration = UUID()
    private var historyGeneration = UUID()
    private var testingWindow: NSWindow?
    var displayedReport: URL? { viewedRun ?? report }

    func openTestingWindow() {
        refresh()
        if testingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "SiteForge Testing"
            window.identifier = NSUserInterfaceItemIdentifier("SiteForge.Testing")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 720, height: 520)
            window.backgroundColor = .windowBackgroundColor
            window.appearance = nil
            window.contentView = NSHostingView(rootView: SiteForgeTestingWindow(store: self))
            window.setFrameAutosaveName("SiteForge.Testing")
            window.center()
            testingWindow = window
        }
        testingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Task { await reloadHistory() }
    }

    static func selectors(in text: String) -> [String]? {
        let values = Array(Set(text.split(whereSeparator: \.isWhitespace).map(String.init))).sorted()
        guard !values.isEmpty, values.allSatisfy({
            $0.range(of: #"^SiteForge(?:UI)?Tests/[A-Za-z_][A-Za-z0-9_]*(?:/test[A-Za-z0-9_]+)?$"#, options: .regularExpression) != nil
        }) else { return nil }
        return values
    }

    func prepareScope() async {
        let generation = UUID()
        scopeGeneration = generation
        if scopePolicy == .all {
            preparedSelectors = []; scopeDescription = "All prepared methods in the selected target."; scopeReady = true
            return
        }
        if scopePolicy == .focused {
            let values = Self.selectors(in: selectorText)
            preparedSelectors = values ?? []
            scopeReady = values != nil
            scopeDescription = values.map { "\($0.count) requested selector\($0.count == 1 ? "" : "s"). Exact executable methods are validated against the fresh build." } ?? "Enter exact Target/Class or Target/Class/testMethod selectors."
            return
        }
        guard let workspace else { scopeReady = false; scopeDescription = "A provisioned source checkout is required."; return }
        scopeReady = false; scopeDescription = "Resolving affected features…"
        let root = workspace.path
        let base = affectedBase
        let result = await Task.detached { () -> (Int32, String) in
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [root + "/scripts/select-test-scope.py", "--root", root, "--base", base]
            process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run()
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, String(data: output, encoding: .utf8) ?? "")
            } catch { return (1, "Scope resolution unavailable.") }
        }.value
        guard generation == scopeGeneration else { return }
        let values = result.0 == 0 ? Self.selectors(in: result.1) : nil
        preparedSelectors = values ?? []; scopeReady = values != nil
        scopeDescription = values.map { "Affected scope against " + base + ":\n" + $0.joined(separator: "\n") + "\nExact methods are validated against the fresh build before execution." }
            ?? "No bounded affected scope is available against \(base). Choose exact selectors or explicitly start Full Verification."
    }

    var harnessAvailable: Bool {
        guard workspace != nil, let resources else { return false }
        let owner = resources.appendingPathComponent("OwnerTesting")
        return FileManager.default.fileExists(atPath: owner.appendingPathComponent("unattended-verification.py").path)
            && FileManager.default.isExecutableFile(atPath: owner.appendingPathComponent("SiteForgeTestingProgress").path)
    }
    func canStart(mode: String) -> Bool {
        guard !running, harnessAvailable, scopeReady else { return false }
        if scopePolicy == .all { return true }
        let target = mode == "ui" ? "SiteForgeUITests" : "SiteForgeTests"
        return preparedSelectors.contains { $0.hasPrefix(target + "/") }
    }
    func startPrepared(mode: String) {
        guard canStart(mode: mode) else { return }
        let target = mode == "ui" ? "SiteForgeUITests" : "SiteForgeTests"
        run(mode: mode, selectors: preparedSelectors.filter { $0.hasPrefix(target + "/") })
    }
    func showRun(_ url: URL?) {
        if let url, url.deletingLastPathComponent().standardizedFileURL != reportsRoot.standardizedFileURL { return }
        viewedRun = url
        refreshSnapshot()
    }
    private func refreshSnapshot() {
        let next = displayedReport.flatMap { try? Data(contentsOf: $0.appendingPathComponent("state.json")) }
            .flatMap { try? JSONDecoder().decode(TestingRunSnapshot.self, from: $0) }
        if snapshot != next { snapshot = next }
        if let report, viewedRun == nil {
            let files = FileManager.default
            let nextPending = ["pause.request", "resume.request", "cancel.request"].contains {
                files.fileExists(atPath: report.appendingPathComponent($0).path)
            } && running
            if controlPending != nextPending { controlPending = nextPending }
            let cancelling = running && files.fileExists(atPath: report.appendingPathComponent("cancel.request").path)
            if cancellationRequested != cancelling { cancellationRequested = cancelling }
        }
    }
    func reloadHistory() async {
        let generation = UUID(); historyGeneration = generation
        let root = reportsRoot
        let records = await Task.detached { () -> [TestingRunRecord] in
            let files = FileManager.default
            let urls = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? []
            return urls.compactMap { url -> (URL, Date)? in
                guard let properties = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                      properties.isDirectory == true else { return nil }
                return (url, properties.contentModificationDate ?? .distantPast)
            }.sorted { $0.1 > $1.1 }.prefix(100).compactMap { url, _ in
                guard let data = try? Data(contentsOf: url.appendingPathComponent("state.json")),
                      let value = try? JSONDecoder().decode(TestingRunSnapshot.self, from: data) else { return nil }
                return TestingRunRecord(url: url, status: value.status, mode: value.resolvedMode == "full" && value.scope?.selectors.isEmpty == false ? "focused" : value.resolvedMode, startedAt: value.startedAt)
            }
        }.value
        if generation == historyGeneration, history != records { history = records }
    }
    func pauseOrResume() {
        guard running, !controlPending, viewedRun == nil, let snapshot,
              ["running", "paused"].contains(snapshot.status), let report else { return }
        let request = snapshot.status == "paused" ? "resume.request" : "pause.request"
        do {
            try Data().write(to: report.appendingPathComponent(request), options: .atomic)
            controlPending = true
            status = snapshot.status == "paused" ? "Resuming testing…" : "Pausing after the current case…"
        } catch { status = "Testing control request could not be saved. Reveal Logs for this run." }
    }

    @Published private(set) var status = "Owner-local testing is unavailable in this installation."
    @Published private(set) var workspace: URL?
    @Published private(set) var report: URL?
    @Published private(set) var running = false
    private var timer: Timer?
    private var launcher: Process?
    private var output: Pipe?
    private let defaults: UserDefaults
    private let resources: URL?
    private let reportsRoot: URL
    private var expectedFingerprint: String?

    init(defaults: UserDefaults = .standard, resources: URL? = Bundle.main.resourceURL,
         reportsRoot: URL? = nil) {
        self.defaults = defaults
        self.resources = resources
        self.reportsRoot = reportsRoot ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("SiteForge/TestingReports", isDirectory: true)
        if let resources,
           let data = try? Data(contentsOf: resources.appendingPathComponent("OwnerTesting/installation.json")),
           let configuration = try? JSONDecoder().decode(OwnerTestingInstallation.self, from: data),
           configuration.version == 1, configuration.sourceFingerprint.count == 64,
           configuration.sourceFingerprint.allSatisfy({ $0.isHexDigit }) {
            let root = URL(fileURLWithPath: configuration.sourceRoot, isDirectory: true)
            if Self.validWorkspace(root) {
                workspace = root
                expectedFingerprint = configuration.sourceFingerprint
                status = "Ready. Tests use isolated website fixtures; your open documents are not test inputs."
            } else {
                status = "Provisioned test source is missing. Reinstall the owner-local build from the current checkout."
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    static func validWorkspace(_ url: URL) -> Bool {
        let required = ["SiteForge.xcodeproj/project.pbxproj", "sf", "scripts/check-repository.sh", "AGENTS.md"]
        return url.isFileURL && required.allSatisfy { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
    }

    // The owned helper receives presentation only; project and run scope stay
    // with their existing stores. Live preference previews use the same bridge.
    static func progressEnvironment(base: [String: String], appearance: NSAppearance?, sourceBundle: String?) -> [String: String] {
        var environment = base
        environment["SITEFORGE_TESTING_APPEARANCE"] = appearance.map {
            $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        } ?? "system"
        environment["SITEFORGE_TESTING_APPEARANCE_SOURCE"] = sourceBundle
        return environment
    }
    private var progressEnvironment: [String: String] {
        Self.progressEnvironment(base: ProcessInfo.processInfo.environment,
                                 appearance: NSApp.appearance, sourceBundle: Bundle.main.bundleIdentifier)
    }

    func run(mode: String, selectors: [String] = []) {
        refresh()
        guard ["full", "ui", "code"].contains(mode), !running,
              let workspace, Self.validWorkspace(workspace),
              let resources, let expectedFingerprint else {
            status = running ? "A testing run is already active." : "Testing unavailable: install a current owner-local build with its provisioned harness."; return
        }
        let collector = resources.appendingPathComponent("OwnerTesting/unattended-verification.py")
        let progress = resources.appendingPathComponent("OwnerTesting/SiteForgeTestingProgress")
        guard FileManager.default.fileExists(atPath: collector.path),
              FileManager.default.isExecutableFile(atPath: progress.path) else {
            status = "Owner-local testing resources are missing. Reinstall the owner-local build."; return
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["python3", collector.path, "--root", workspace.path, "--mode", mode,
            "--progress", progress.path, "--reports-root", reportsRoot.path,
            "--expected-source-fingerprint", expectedFingerprint, "--source-check-progress"]
        for selector in selectors { process.arguments?.append(contentsOf: ["--selector", selector]) }
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = progressEnvironment
        do {
            try process.run()
            viewedRun = nil
            snapshot = nil
            requestDescription = nil
            launcher = process
            output = pipe
            running = true
            status = "Starting detached testing. This installed app and your open documents remain untouched."
        } catch { status = "Local test collector could not launch. Check Xcode and workspace permissions." }
    }

    func refresh() {
        if let launcher, !launcher.isRunning {
            let text = output.flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) } ?? ""
            if launcher.terminationStatus == 0 {
                let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    let next = URL(fileURLWithPath: path, isDirectory: true)
                    if report != next { report = next }
                }
            } else if text.contains("stale-source") {
                status = "Testing unavailable: the provisioned source has changed. Reinstall the current owner-local build; no stale tests were run."
            } else { status = "Testing did not start. Check the retained report, Xcode authorization, or another active run." }
            self.launcher = nil
            output = nil
        }
        let parent = reportsRoot
        let nextRunning = FileManager.default.fileExists(atPath: parent.appendingPathComponent("active.json").path) || launcher != nil
        if running != nextRunning { running = nextRunning }
        if let data = try? Data(contentsOf: parent.appendingPathComponent("current.json")),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: String], let path = value["run"] {
            let candidate = URL(fileURLWithPath: path).standardizedFileURL
            guard candidate.deletingLastPathComponent() == parent.standardizedFileURL else { return }
            if launcher != nil, candidate == report { return }
            if report != candidate { report = candidate }
            if let data = try? Data(contentsOf: candidate.appendingPathComponent("state.json")),
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outcome = value["status"] as? String {
                let nextStatus = value["failureCategory"] as? String == "scope-unresolved"
                    ? "Testing scope unresolved in the built inventory. Choose surviving exact selectors or explicit Full Verification; no cases launched."
                    : value["failureCategory"] as? String == "stale-source"
                    ? "Testing unavailable: provisioned source changed. Reinstall the current owner-local build. No stale tests ran."
                    : "Testing \(outcome). Detailed logs and results are retained locally."
                if status != nextStatus { status = nextStatus }
            }
        }
        refreshSnapshot()
    }

    func revealReport() { if let report = displayedReport { NSWorkspace.shared.activateFileViewerSelecting([report]) } }
    func openProgress() {
        guard let report, let resources else { return }
        let process = Process()
        process.executableURL = resources.appendingPathComponent("OwnerTesting/SiteForgeTestingProgress")
        process.arguments = [report.path]
        process.environment = progressEnvironment
        do { try process.run() } catch { status = "The progress window could not open. Reveal the report instead." }
    }
    func openReport() { if let report = displayedReport { NSWorkspace.shared.open(report.appendingPathComponent("REPORT.md")) } }
    func cancel() {
        guard running,
              let data = try? Data(contentsOf: reportsRoot.appendingPathComponent("active.json")),
              let ownership = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = ownership["run"] as? String else { return }
        let active = URL(fileURLWithPath: path).standardizedFileURL
        guard active.deletingLastPathComponent() == reportsRoot.standardizedFileURL else { return }
        do {
            try Data().write(to: active.appendingPathComponent("cancel.request"), options: .atomic)
            cancellationRequested = true
            controlPending = true
            status = "Cancelling testing…"
        }
        catch { status = "Cancellation could not be requested. Reveal Logs for the active run." }
    }
}

struct OwnerTestingInstallation: Codable, Equatable {
    let version: Int
    let sourceRoot: String
    let sourceFingerprint: String
}

private struct ExperimentalTestingView: View {
    @ObservedObject var store: ExperimentalTestingStore
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            SiteForgeSettingsHeader(title: "Advanced", scope: "", detail: "")
            GroupBox("Testing") {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Run local testing").font(.body.weight(.medium))
                        Text("Choose a scope, follow progress, and reopen retained results in the Testing window.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Testing") { store.openTestingWindow() }
                        .accessibilityIdentifier("settings.testing.open")
                }.padding(8)
            }
        }
    }
}

/// These values are inherited macOS preferences. The page makes their effect
/// discoverable without presenting a competing application preference store.
private struct SiteForgeAccessibilitySettingsView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            SiteForgeSettingsHeader(title: "Accessibility", scope: "Uses macOS accessibility settings · does not change your website",
                detail: "SiteForge follows your system display preferences and native keyboard navigation.")
            GroupBox("Display preferences") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    LabeledContent("Reduce transparency", value: reduceTransparency ? "On · opaque surfaces" : "Off · native materials")
                        .accessibilityIdentifier("settings.accessibility.transparency")
                    LabeledContent("Increase contrast", value: contrast == .increased ? "On · stronger boundaries" : "Off · standard boundaries")
                        .accessibilityIdentifier("settings.accessibility.contrast")
                    LabeledContent("Reduce motion", value: reduceMotion ? "On · reduced animation" : "Off · system animation")
                        .accessibilityIdentifier("settings.accessibility.motion")
                    Text("Change these inherited preferences in macOS System Settings → Accessibility → Display.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GroupBox("Keyboard and VoiceOver") {
                Text("Native controls retain keyboard focus and accessible names, values, and actions. Scrollable destination strips also provide a Show All Tabs menu. Project content and website styles are unaffected by these editor preferences.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: SiteForgeVisualSystem.settingsContentMaxWidth, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accessibility preferences")
        .accessibilityIdentifier("settings.accessibility")
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var store: UpdateSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.sectionSpacing) {
            SiteForgeSettingsHeader(
                title: "Updates",
                scope: AuthoringLanguage.appPreferencesScope,
                detail: "Check for SiteForge updates. Installation is unavailable until an approved, trusted signed updater is configured. Your website is unchanged."
            )
            GroupBox("Installed version") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    LabeledContent("Version", value: store.application.version)
                    LabeledContent("Build", value: store.application.build)
                    LabeledContent("Distribution", value: store.application.channel)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Automatic checking") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    Toggle("Check automatically when a trusted feed is configured", isOn: $store.automaticallyChecks)
                        .accessibilityHint("Stores this app-local preference. Scheduling stays inactive until a trusted feed is configured")
                        .accessibilityIdentifier("settings.updates.automatic")
                    Text("This app-local preference never includes project content or credentials. No automatic network schedule runs while the trusted feed is unconfigured.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Update status") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    HStack {
                        if store.state == .checking { ProgressView().controlSize(.small) }
                        Text(store.status).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(store.status)
                    .accessibilityIdentifier("settings.updates.status")
                    if let update = store.update {
                        LabeledContent("Available", value: update.version)
                        if let size = update.downloadSize {
                            LabeledContent("Download", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        }
                        LabeledContent("Source", value: update.provenanceHost)
                        Text(update.notes).font(.callout).textSelection(.enabled)
                            .frame(maxHeight: 120).accessibilityLabel("Release notes: \(update.notes)")
                    }
                    HStack {
                        Button("Check for Updates") { store.check() }
                            .disabled(store.state == .checking)
                            .accessibilityIdentifier("settings.updates.check")
                        Button("Cancel") { store.cancel() }
                            .disabled(!store.canCancel)
                            .accessibilityIdentifier("settings.updates.cancel")
                        Spacer()
                        Button("Install Trusted Update") { store.requestTrustedInstall() }
                            .disabled(store.update == nil)
                            .accessibilityIdentifier("settings.updates.install")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Label("Only a cryptographically trusted, code-signed update may cross the installation boundary.", systemImage: "checkmark.shield")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: SiteForgeVisualSystem.settingsContentMaxWidth, alignment: .topLeading)
        .onChange(of: store.status) { _, status in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
}
