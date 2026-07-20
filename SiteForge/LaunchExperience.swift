import AppKit
import CryptoKit
import Foundation
import SwiftUI

@MainActor
enum NativeProjectOpenPanel {
    static func chooseProject() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.siteForgeProject]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a SiteForge project to validate before opening."
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum ProjectLoadUpdate: String, CaseIterable, Equatable, Sendable {
    case readingPackage
    case validatingCanonicalDocument
    case validatingHistory
    case preparingWorkspace
    case checkingRecovery

    var status: ProjectLoadingStatus {
        switch self {
        case .readingPackage:
            ProjectLoadingStatus(
                title: "Opening project…",
                detail: "Reading the project package.",
                progress: nil,
                canCancel: true,
                accessibilityLabel: "Opening project, reading package"
            )
        case .validatingCanonicalDocument:
            ProjectLoadingStatus(
                title: "Validating project…",
                detail: "Checking the canonical document and package integrity.",
                progress: 1.0 / 3.0,
                canCancel: true,
                accessibilityLabel: "Validating project, step 1 of 3"
            )
        case .validatingHistory:
            ProjectLoadingStatus(
                title: "Restoring document history…",
                detail: "Checking compatible undo and redo transactions.",
                progress: 2.0 / 3.0,
                canCancel: true,
                accessibilityLabel: "Restoring document history, step 2 of 3"
            )
        case .preparingWorkspace:
            ProjectLoadingStatus(
                title: "Preparing workspace…",
                detail: "The validated project is being installed as one atomic workspace.",
                progress: 1,
                canCancel: false,
                accessibilityLabel: "Preparing workspace, final non-cancelable step"
            )
        case .checkingRecovery:
            ProjectLoadingStatus(
                title: "Checking recovery…",
                detail: "Looking for a newer valid recovery candidate.",
                progress: nil,
                canCancel: false,
                accessibilityLabel: "Checking recovery, non-cancelable"
            )
        }
    }
}

struct ProjectLoadingStatus: Equatable, Sendable {
    let title: String
    let detail: String
    let progress: Double?
    let canCancel: Bool
    let accessibilityLabel: String
    var isCancellationRequested = false

    var displayedTitle: String { isCancellationRequested ? "Canceling safely…" : title }
    var displayedDetail: String {
        isCancellationRequested
            ? "The current project will remain unchanged."
            : detail
    }
}

enum LaunchExperienceStateKind: String, Equatable, Sendable {
    case welcome, creating, loadingIndeterminate, loadingDeterminate
    case loadingNonCancelable, failure, recovery, workspace
}

enum LaunchFailureAction: String, Equatable, Sendable {
    case retry = "Retry"
    case chooseAnother = "Choose Another Project"
}

struct LaunchFailurePresentation: Equatable, Sendable {
    let title: String
    let message: String
    let primaryAction: LaunchFailureAction
    let failure: DocumentLifecycleFailure
}

struct LaunchRecoveryPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let revisionSummary: String
}

enum LaunchExperienceState: Equatable, Sendable {
    case welcome
    case working(ProjectLoadingStatus)
    case failure(LaunchFailurePresentation)
    case recovery(LaunchRecoveryPresentation)
    case workspace

    var kind: LaunchExperienceStateKind {
        switch self {
        case .welcome: .welcome
        case .working(let status) where status.title == "Creating blank project…" && status.canCancel: .creating
        case .working(let status) where status.progress == nil && status.canCancel: .loadingIndeterminate
        case .working(let status) where status.canCancel: .loadingDeterminate
        case .working: .loadingNonCancelable
        case .failure: .failure
        case .recovery: .recovery
        case .workspace: .workspace
        }
    }

    var announcement: String {
        switch self {
        case .welcome: "SiteForge is ready. Create a blank project or open an existing project."
        case .working(let status): status.accessibilityLabel
        case .failure(let failure): "Project loading failed. \(failure.message)"
        case .recovery(let recovery): "Recovery candidate found. \(recovery.revisionSummary)"
        case .workspace: "Project ready."
        }
    }
}

struct LaunchDiagnosticRecord: Equatable, Sendable {
    let requirementIDs: [String]
    let operation: LifecycleOperation
    let state: LaunchExperienceStateKind
    let sanitizedDocumentID: String
    let durationNanoseconds: UInt64
    let result: LifecycleResult
    let failureCategory: String?
}

actor LaunchExperienceDiagnostics {
    private(set) var records: [LaunchDiagnosticRecord] = []
    func append(_ record: LaunchDiagnosticRecord) { records.append(record) }
    func snapshot() -> [LaunchDiagnosticRecord] { records }
}

@MainActor
struct AccessibilityAnnouncementPoster {
    var post: (String) -> Void

    static let native = AccessibilityAnnouncementPoster { message in
        AccessibilityNotification.Announcement(message).post()
    }
}

enum LaunchPreviewScenario: String {
    case welcome
    case loadingIndeterminate
    case loadingDeterminate
    case loadingNonCancelable
    case failure
    case recovery
    case workspace

    static func from(composition: DebugTestComposition = .current()) -> LaunchPreviewScenario? {
        composition.value(after: "-SiteForgeLaunchScenario").flatMap(Self.init)
    }
}

@MainActor
final class LaunchExperienceController: ObservableObject {
    static let requirementIDs: Set<String> = [
        "SF-0201-004", "SF-0201-006", "SF-0201-007", "SF-0201-008",
        "SF-0301-002", "SF-0301-004", "SF-0301-006", "SF-0301-007", "SF-0301-008",
        "SF-1602-004", "SF-1602-006", "SF-1602-007", "SF-1602-008",
    ]

    @Published private(set) var state: LaunchExperienceState
    @Published private(set) var transitionHistory: [LaunchExperienceStateKind]
    let lifecycle: DocumentLifecycleController
    let diagnostics: LaunchExperienceDiagnostics

    private var operationTask: Task<Void, Never>?
    private var operationID = UUID()
    private var returnState: LaunchExperienceState = .welcome
    private var lastOpenURL: URL?
    private(set) var isPreviewScenario = false
    let forcesReducedMotionForTesting: Bool
#if DEBUG
    private var didStartIntegrationOpen = false
    private var integrationRetryBase64URL: URL?
#endif
    private let announcementPoster: AccessibilityAnnouncementPoster

    init(
        lifecycle: DocumentLifecycleController,
        diagnostics: LaunchExperienceDiagnostics = LaunchExperienceDiagnostics(),
        previewScenario: LaunchPreviewScenario? = LaunchPreviewScenario.from(),
        announcementPoster: AccessibilityAnnouncementPoster = .native
    ) {
        self.lifecycle = lifecycle
        self.diagnostics = diagnostics
        self.announcementPoster = announcementPoster
        let initial = Self.previewState(previewScenario) ?? .welcome
        state = initial
        transitionHistory = [initial.kind]
        isPreviewScenario = previewScenario != nil
        forcesReducedMotionForTesting = DebugTestComposition.current().contains("-SiteForgeReduceMotion")
    }

    var isWorkspaceVisible: Bool { state == .workspace }

    func announceCurrentState() {
        announcementPoster.post(state.announcement)
    }

#if DEBUG
    /// Exercises the production package loader from UI automation without teaching Release builds a test path.
    func startIntegrationOpenIfConfigured(composition: DebugTestComposition = .current()) -> Bool {
        let arguments = composition.arguments
        guard composition.enabled else { return false }
        guard !didStartIntegrationOpen,
              let index = arguments.firstIndex(of: "-SiteForgeIntegrationOpenProject"),
              arguments.indices.contains(index + 1) else { return false }
        didStartIntegrationOpen = true
        let destination = URL(fileURLWithPath: arguments[index + 1])
        if let source = Self.argumentURL("-SiteForgeIntegrationPackageBase64", in: arguments) {
            let malformed = arguments.contains("-SiteForgeIntegrationStartMalformed")
            try? Self.writeIntegrationPackage(from: source, to: destination, malformed: malformed)
        }
        integrationRetryBase64URL = Self.argumentURL("-SiteForgeIntegrationRetryBase64", in: arguments)
        openProject(destination, userSelected: true)
        return true
    }

    func prepareIntegrationRecoveryIfConfigured(composition: DebugTestComposition = .current()) {
        let arguments = composition.arguments
        guard composition.enabled else { return }
        guard let source = Self.argumentURL("-SiteForgeIntegrationRecoveryBase64", in: arguments),
              let destination = Self.argumentURL("-SiteForgeIntegrationRecoveryDestination", in: arguments) else { return }
        try? Self.writeIntegrationPackage(from: source, to: destination, malformed: false)
    }

    private static func argumentURL(_ name: String, in arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static func writeIntegrationPackage(from source: URL, to destination: URL, malformed: Bool) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data: Data
        if malformed {
            data = Data("malformed project package".utf8)
        } else {
            let encoded = try String(contentsOf: source).filter { !$0.isWhitespace }
            guard let decoded = Data(base64Encoded: encoded) else { throw CocoaError(.fileReadCorruptFile) }
            data = decoded
        }
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
#endif

    func createBlankProject() {
        startOperation(.new) { [weak self] id, start in
            guard let self else { return }
            await self.performBlankCreation(operationID: id, start: start)
        }
    }

    func createBlankProjectAndWait() async {
        let id = UUID()
        operationID = id
        returnState = state == .workspace ? .workspace : .welcome
        await performBlankCreation(operationID: id, start: .now)
    }

    func openProject(_ url: URL, userSelected: Bool = false) {
        lastOpenURL = url
        startOperation(.open) { [weak self] id, start in
            guard let self else { return }
            await self.performOpen(url, userSelected: userSelected, operationID: id, start: start)
        }
    }

    func openProjectAndWait(_ url: URL) async {
        lastOpenURL = url
        let id = UUID()
        operationID = id
        returnState = state == .workspace ? .workspace : .welcome
        await performOpen(url, userSelected: false, operationID: id, start: .now)
    }

    func cancelCurrentOperation() {
        guard case .working(var status) = state, status.canCancel else { return }
        status.isCancellationRequested = true
        transition(to: .working(status))
        operationTask?.cancel()
    }

    func retry() {
        guard let lastOpenURL else { return }
#if DEBUG
        if let integrationRetryBase64URL {
            try? Self.writeIntegrationPackage(from: integrationRetryBase64URL, to: lastOpenURL, malformed: false)
            self.integrationRetryBase64URL = nil
        }
#endif
        openProject(lastOpenURL)
    }

    func returnToCurrentProject() {
        transition(to: returnState)
    }

    func restoreRecovery() {
        if isPreviewScenario {
            transition(to: .workspace)
            return
        }
        Task {
            if await lifecycle.requestRestoreRecovery() == .completed {
                transition(to: .workspace)
            }
        }
    }

    func discardRecovery() {
        Task {
            await lifecycle.discardRecovery()
            transition(to: .workspace)
        }
    }

    func inspectRecovery() {
        lifecycle.isRecoveryDetailsPresented = true
    }

    func presentOpenPanel() {
        guard let url = NativeProjectOpenPanel.chooseProject() else {
            lifecycle.noteCancellation()
            return
        }
        openProject(url, userSelected: true)
    }

    static func usesAnimatedIndeterminateProgress(reduceMotion: Bool) -> Bool { !reduceMotion }

    var preferredFocusIdentifier: String? {
        switch state {
        case .welcome: "launch.newBlankProject"
        case .working(let status): status.canCancel ? "launch.cancel" : nil
        case .failure(let failure): failure.primaryAction == .retry ? "launch.retry" : "launch.chooseAnother"
        case .recovery: "launch.recovery.restore"
        case .workspace: nil
        }
    }

    func discoverInitialRecovery() async {
        guard state == .welcome, !isPreviewScenario else { return }
        await lifecycle.discoverUntitledRecoveryCandidate()
        if let candidate = lifecycle.recoveryCandidate {
            transition(to: .recovery(LaunchRecoveryPresentation(
                title: "Unsaved project recovery available",
                message: "A validated recovery candidate contains unsaved work from an earlier session.",
                revisionSummary: candidate.summary
            )))
        }
    }

    private func startOperation(
        _ operation: LifecycleOperation,
        work: @escaping @MainActor (UUID, ContinuousClock.Instant) async -> Void
    ) {
        operationTask?.cancel()
        let id = UUID()
        operationID = id
        returnState = state == .workspace ? .workspace : .welcome
        let start = ContinuousClock.now
        operationTask = Task { await work(id, start) }
    }

    private func performBlankCreation(operationID id: UUID, start: ContinuousClock.Instant) async {
        transition(to: .working(ProjectLoadingStatus(
            title: "Creating blank project…",
            detail: "Preparing the approved Home and Not Found page baseline.",
            progress: 0.5,
            canCancel: true,
            accessibilityLabel: "Creating blank project, step 1 of 2"
        )))
        await Task.yield()
        guard id == operationID, !Task.isCancelled else {
            await finishCancelled(.new, start: start)
            return
        }
        transition(to: .working(ProjectLoadingStatus(
            title: "Creating blank project…",
            detail: "Establishing one clean project history baseline.",
            progress: 1,
            canCancel: false,
            accessibilityLabel: "Creating blank project, final non-cancelable step"
        )))
        switch await lifecycle.requestNewDocument() {
        case .completed:
            transition(to: .workspace)
            await record(.new, start: start, result: .success, failure: nil)
        case .cancelled:
            await finishCancelled(.new, start: start)
        case .failed(let failure):
            transition(to: .failure(Self.presentation(for: failure)))
            await record(.new, start: start, result: .failure, failure: failure)
        }
    }

    private func performOpen(
        _ url: URL,
        userSelected: Bool = false,
        operationID id: UUID,
        start: ContinuousClock.Instant
    ) async {
        let result = await lifecycle.requestOpen(url, userSelected: userSelected) { [weak self] update in
            await self?.receive(update, operationID: id)
        }
        guard id == operationID else { return }
        if Task.isCancelled {
            await finishCancelled(.open, start: start)
            return
        }
        switch result {
        case .completed:
            if let candidate = lifecycle.recoveryCandidate {
                transition(to: .recovery(LaunchRecoveryPresentation(
                    title: "Newer recovery available",
                    message: "A validated recovery candidate is newer than the last durable save.",
                    revisionSummary: candidate.summary
                )))
            } else {
                transition(to: .workspace)
            }
            await record(.open, start: start, result: .success, failure: nil)
        case .cancelled:
            await finishCancelled(.open, start: start)
        case .failed(let failure):
            transition(to: .failure(Self.presentation(for: failure)))
            await record(.open, start: start, result: .failure, failure: failure)
        }
    }

    private func receive(_ update: ProjectLoadUpdate, operationID id: UUID) {
        guard id == operationID else { return }
        transition(to: .working(update.status))
    }

    private func finishCancelled(_ operation: LifecycleOperation, start: ContinuousClock.Instant) async {
        transition(to: returnState)
        await record(operation, start: start, result: .cancelled, failure: nil)
    }

    private func transition(to newState: LaunchExperienceState) {
        state = newState
        if transitionHistory.last != newState.kind { transitionHistory.append(newState.kind) }
    }

    private func record(
        _ operation: LifecycleOperation,
        start: ContinuousClock.Instant,
        result: LifecycleResult,
        failure: DocumentLifecycleFailure?
    ) async {
        let components = start.duration(to: .now).components
        let nanos = UInt64(max(0, components.seconds)) * 1_000_000_000
            + UInt64(max(0, components.attoseconds / 1_000_000_000))
        let identifier = lifecycle.session.document.id.description
        let sanitized = "document-" + SHA256.hash(data: Data(identifier.utf8)).prefix(5)
            .map { String(format: "%02x", $0) }.joined()
        await diagnostics.append(LaunchDiagnosticRecord(
            requirementIDs: Self.requirementIDs.sorted(),
            operation: operation,
            state: state.kind,
            sanitizedDocumentID: sanitized,
            durationNanoseconds: nanos,
            result: result,
            failureCategory: failure.map { String(describing: $0) }
        ))
    }

    private static func presentation(for failure: DocumentLifecycleFailure) -> LaunchFailurePresentation {
        switch failure {
        case .incompatiblePackage:
            LaunchFailurePresentation(
                title: "Project version isn’t supported",
                message: failure.localizedDescription,
                primaryAction: .chooseAnother,
                failure: failure
            )
        case .permissionDenied, .staleSecurityScope:
            LaunchFailurePresentation(
                title: "SiteForge can’t access this project",
                message: failure.localizedDescription,
                primaryAction: .chooseAnother,
                failure: failure
            )
        default:
            LaunchFailurePresentation(
                title: "Project couldn’t be opened",
                message: failure.localizedDescription,
                primaryAction: .retry,
                failure: failure
            )
        }
    }

    private static func previewState(_ scenario: LaunchPreviewScenario?) -> LaunchExperienceState? {
        switch scenario {
        case nil: nil
        case .welcome: .welcome
        case .loadingIndeterminate: .working(ProjectLoadUpdate.readingPackage.status)
        case .loadingDeterminate: .working(ProjectLoadUpdate.validatingHistory.status)
        case .loadingNonCancelable: .working(ProjectLoadUpdate.preparingWorkspace.status)
        case .failure: .failure(presentation(for: .malformedPackage))
        case .recovery: .recovery(LaunchRecoveryPresentation(
            title: "Newer recovery available",
            message: "A validated recovery candidate is newer than the last durable save.",
            revisionSummary: "Revision 4, newer than the durable revision."
        ))
        case .workspace: .workspace
        }
    }
}

private enum LaunchFocus: Hashable {
    case newProject, openProject, cancel, primaryFailure, chooseAnother
    case restoreRecovery, discardRecovery, inspectRecovery
}

struct LaunchExperienceView: View {
    @ObservedObject var controller: LaunchExperienceController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focus: LaunchFocus?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            launchCard
                .frame(maxWidth: 560)
                .padding(48)
        }
        .frame(
            minWidth: WorkspaceMetrics.minimumWindowSize.width,
            minHeight: WorkspaceMetrics.minimumWindowSize.height
        )
        .accessibilityIdentifier("launch.experience")
        .task {
#if DEBUG
            controller.prepareIntegrationRecoveryIfConfigured()
            if controller.startIntegrationOpenIfConfigured() {
                await Task.yield()
                assignInitialFocus()
                return
            }
#endif
            await controller.discoverInitialRecovery()
            await Task.yield()
            assignInitialFocus()
        }
        .onChange(of: controller.state.kind) { _, _ in
            assignInitialFocus()
            controller.announceCurrentState()
        }
        .animation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.18), value: controller.state.kind)
    }

    @ViewBuilder
    private var launchCard: some View {
        VStack(spacing: 26) {
            brand
            switch controller.state {
            case .welcome:
                welcome
            case .working(let status):
                working(status)
            case .failure(let failure):
                failureView(failure)
            case .recovery(let recovery):
                recoveryView(recovery)
            case .workspace:
                EmptyView()
            }
        }
        .padding(36)
        .workspaceChrome(.launchCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.13))
        }
        .shadow(color: .black.opacity(reduceTransparency ? 0.08 : 0.14), radius: 24, y: 10)
    }

    private var brand: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("SiteForge")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Design native, durable web projects.")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("launch.brand")
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Text("Start a project")
                .font(.title2.weight(.semibold))
            Text("Create the approved blank SiteForge structure or validate an existing project before it enters the workspace.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("New Blank Project") { controller.createBlankProject() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .focused($focus, equals: .newProject)
                    .accessibilityHint("Creates Home and Not Found pages as one clean baseline")
                    .accessibilityIdentifier("launch.newBlankProject")
                Button("Open Project…") { controller.presentOpenPanel() }
                    .focused($focus, equals: .openProject)
                    .accessibilityHint("Choose a SiteForge project to validate before opening")
                    .accessibilityIdentifier("launch.openProject")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.welcome")
    }

    private func working(_ status: ProjectLoadingStatus) -> some View {
        VStack(spacing: 16) {
            if let progress = status.progress {
                ProgressView(value: progress)
                    .accessibilityValue("\(Int(progress * 100)) percent")
                    .accessibilityIdentifier("launch.progress.determinate")
            } else if LaunchExperienceController.usesAnimatedIndeterminateProgress(reduceMotion: effectiveReduceMotion) {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityIdentifier("launch.progress.indeterminate")
            } else {
                Image(systemName: "hourglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(status.displayedTitle)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("launch.operation.title")
            Text(status.displayedDetail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("launch.operation.status")
            if status.canCancel && !status.isCancellationRequested {
                Button("Cancel") { controller.cancelCurrentOperation() }
                    .keyboardShortcut(.cancelAction)
                    .focused($focus, equals: .cancel)
                    .accessibilityHint("Keeps the current valid project unchanged")
                    .accessibilityIdentifier("launch.cancel")
            } else if !status.isCancellationRequested {
                Label("This final step can’t be safely canceled.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("launch.nonCancelable")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityIdentifier("launch.loading")
    }

    private func failureView(_ failure: LaunchFailurePresentation) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(failure.title)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("launch.failure.title")
            Text(failure.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("launch.failure.message")
            HStack(spacing: 12) {
                if failure.primaryAction == .retry {
                    Button("Retry") { controller.retry() }
                        .buttonStyle(.borderedProminent)
                        .focused($focus, equals: .primaryFailure)
                        .accessibilityIdentifier("launch.retry")
                }
                Button("Choose Another Project…") { controller.presentOpenPanel() }
                    .focused($focus, equals: .chooseAnother)
                    .accessibilityIdentifier("launch.chooseAnother")
                if controller.isPreviewScenario || controller.lifecycle.fileURL != nil {
                    Button("Return to Current Project") { controller.returnToCurrentProject() }
                        .accessibilityIdentifier("launch.returnToProject")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.failure")
    }

    private func recoveryView(_ recovery: LaunchRecoveryPresentation) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(recovery.title)
                .font(.title3.weight(.semibold))
            Text(recovery.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(recovery.revisionSummary)
                .font(.callout.monospacedDigit())
                .accessibilityIdentifier("launch.recovery.summary")
            HStack(spacing: 12) {
                Button("Inspect Recovery") { controller.inspectRecovery() }
                    .focused($focus, equals: .inspectRecovery)
                    .accessibilityIdentifier("launch.recovery.inspect")
                Button("Discard") { controller.discardRecovery() }
                    .focused($focus, equals: .discardRecovery)
                    .accessibilityIdentifier("launch.recovery.discard")
                Button("Restore") { controller.restoreRecovery() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .focused($focus, equals: .restoreRecovery)
                    .accessibilityIdentifier("launch.recovery.restore")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.recovery")
    }

    private func assignInitialFocus() {
        switch controller.state {
        case .welcome: focus = .newProject
        case .working(let status): focus = status.canCancel ? .cancel : nil
        case .failure(let failure): focus = failure.primaryAction == .retry ? .primaryFailure : .chooseAnother
        case .recovery: focus = .restoreRecovery
        case .workspace: focus = nil
        }
    }

    private var effectiveReduceMotion: Bool {
        reduceMotion || controller.forcesReducedMotionForTesting
    }
}
