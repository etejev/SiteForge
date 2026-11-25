import AppKit
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A native File command can outlive the last scene. Transfer its intent once
/// to the next scene, never to a retained controller from a closed window.
@MainActor
final class WorkspaceLaunchRequestQueue {
    enum Request: Equatable { case new, open(URL) }
    static let shared = WorkspaceLaunchRequestQueue()
    private var pending: Request?
    @discardableResult func enqueue(_ request: Request) -> Bool {
        guard pending == nil else { return false }
        pending = request
        return true
    }
    func take() -> Request? {
        defer { pending = nil }
        return pending
    }
}

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

/// Central AppKit ownership for local image selection. Callers receive only
/// the chosen URLs; canonical asset state never retains a panel or user path.
@MainActor
enum NativeImageOpenPanel {
    static func chooseImages(insertFirst: Bool) -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = insertFirst
            ? "Choose local raster images. The first imported image will be inserted on the active artboard."
            : "Choose local raster images to preserve in this SiteForge project."
        panel.prompt = insertFirst ? "Import and Insert" : "Import"
        return panel.runModal() == .OK ? panel.urls : nil
    }

    static func chooseReplacement() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Replace this shared asset everywhere it is referenced. To change only one object, cancel and use Choose from Assets or Import Image beside that object."
        panel.prompt = "Replace Everywhere"
        return panel.runModal() == .OK ? panel.url : nil
    }
    static func chooseImageForUse() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Import and use a local image only for the captured selection. Other uses keep their current image."
        panel.prompt = "Import and Use"
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
        case .working(let status) where status.title.hasPrefix("Creating ") && status.canCancel: .creating
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
        case .welcome: "SiteForge is ready. Choose Blank Site, Starter Site or Aurora Editorial, or open an existing project."
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
    private var buffer: BoundedDiagnosticBuffer<LaunchDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    var records: [LaunchDiagnosticRecord] { buffer.snapshot() }
    func append(_ record: LaunchDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [LaunchDiagnosticRecord] { buffer.snapshot() }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
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
        "SF-0201-002", "SF-0201-003", "SF-0201-004", "SF-0201-006", "SF-0201-007", "SF-0201-008",
        "SF-0204-001", "SF-0204-002", "SF-0204-003", "SF-0204-004",
        "SF-0204-005", "SF-0204-006", "SF-0204-007", "SF-0204-008",
        "SF-0301-002", "SF-0301-004", "SF-0301-006", "SF-0301-007", "SF-0301-008",
        "SF-1602-004", "SF-1602-006", "SF-1602-007", "SF-1602-008",
    ]

    @Published private(set) var state: LaunchExperienceState
    @Published private(set) var transitionHistory: [LaunchExperienceStateKind]
    @Published private(set) var recentProjects: [RecentProjectReference] = []
    @Published private(set) var recentProjectsMessage: String?
    @Published private(set) var isUpdatingRecentProjects = false
    @Published private(set) var recoveryAvailableAtWelcome = false
    @Published private(set) var recoveryHistoryMessage: String?
    @Published private(set) var isResolvingRecovery = false
    private var recoveryActionID = UUID()
    private var checkedInitialRecovery = false
    let lifecycle: DocumentLifecycleController
    let diagnostics: LaunchExperienceDiagnostics

    private var operationTask: Task<Void, Never>?
    private var operationID = UUID()
    private var recentProjectsTask: Task<Void, Never>?
    private var recentProjectsRequestID = UUID()
    private var pendingRecentProjectOperations = 0
    private var returnState: LaunchExperienceState = .welcome
    private var lastOpenURL: URL?
    private(set) var isPreviewScenario = false
    let forcesReducedMotionForTesting: Bool
    private let recentProjectStore: any RecentProjectPersisting
#if DEBUG
    private var didStartIntegrationOpen = false
    private var integrationRetryBase64URL: URL?
#endif
    private let announcementPoster: AccessibilityAnnouncementPoster

    init(
        lifecycle: DocumentLifecycleController,
        diagnostics: LaunchExperienceDiagnostics = LaunchExperienceDiagnostics(),
        recentProjectStore: any RecentProjectPersisting = RecentProjectStore(),
        previewScenario: LaunchPreviewScenario? = LaunchPreviewScenario.from(),
        announcementPoster: AccessibilityAnnouncementPoster = .native
    ) {
        self.lifecycle = lifecycle
        self.diagnostics = diagnostics
        self.recentProjectStore = recentProjectStore
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
            await self.performCreation(.blank, operationID: id, start: start)
        }
    }

    func createBlankProjectAndWait() async {
        let id = UUID()
        operationID = id
        captureOperationReturnState()
        await performCreation(.blank, operationID: id, start: .now)
    }

    func createStarterProject() {
        startOperation(.new) { [weak self] id, start in
            guard let self else { return }
            await self.performCreation(.starter, operationID: id, start: start)
        }
    }

    func createStarterProjectAndWait() async {
        let id = UUID()
        operationID = id
        captureOperationReturnState()
        await performCreation(.starter, operationID: id, start: .now)
    }

    func createAuroraProject() {
        startOperation(.new) { [weak self] id, start in
            await self?.performCreation(.aurora, operationID: id, start: start)
        }
    }

    func createAuroraProjectAndWait() async {
        let id = UUID()
        operationID = id
        captureOperationReturnState()
        await performCreation(.aurora, operationID: id, start: .now)
    }

    func createAuroraFlowProject() {
        startOperation(.new) { [weak self] id, start in
            await self?.performCreation(.auroraFlow, operationID: id, start: start)
        }
    }

    func createAuroraFlowProjectAndWait() async {
        let id = UUID()
        operationID = id
        captureOperationReturnState()
        await performCreation(.auroraFlow, operationID: id, start: .now)
    }

    func openProject(_ url: URL, userSelected: Bool = false) {
        lastOpenURL = url
        startOperation(.open) { [weak self] id, start in
            guard let self else { return }
            await self.performOpen(
                url, userSelected: userSelected, rememberOnSuccess: userSelected,
                operationID: id, start: start
            )
        }
    }

    func openProjectAndWait(_ url: URL, userSelected: Bool = false) async {
        lastOpenURL = url
        let id = UUID()
        operationID = id
        captureOperationReturnState()
        await performOpen(url, userSelected: userSelected, rememberOnSuccess: userSelected, operationID: id, start: .now)
    }

    func loadRecentProjects() async {
        await enqueueRecentProjects { owner in
            do {
                owner.recentProjects = try await owner.recentProjectStore.load()
                owner.recentProjectsMessage = nil
            } catch {
                owner.recentProjectsMessage = "Recent projects could not be refreshed. The last valid list is retained; Open Project remains available."
            }
        }.value
    }

    func openRecentProject(_ reference: RecentProjectReference) {
        startOperation(.open) { [weak self] id, start in
            guard let self, id == self.operationID else { return }
            self.transition(to: .working(ProjectLoadingStatus(
                title: "Locating recent project…",
                detail: "Restoring authorized local access without exposing its path.",
                progress: nil,
                canCancel: true,
                accessibilityLabel: "Locating recent project"
            )))
            do {
                let url = try await self.lifecycle.resolveAuthorizedProject(bookmarkKey: reference.bookmarkKey)
                guard id == self.operationID, !Task.isCancelled else {
                    await self.finishCancelled(.open, start: start, operationID: id)
                    return
                }
                self.lastOpenURL = url
                await self.performOpen(
                    url, userSelected: false, rememberOnSuccess: true,
                    operationID: id, start: start
                )
            } catch let failure as DocumentLifecycleFailure {
                guard id == self.operationID else { return }
                if Task.isCancelled { await self.finishCancelled(.open, start: start, operationID: id); return }
                self.recentProjectsMessage = "Access to \(reference.displayName) needs to be restored with Open Project."
                self.transition(to: .welcome)
                await self.record(.open, start: start, result: .failure, failure: failure)
            } catch {
                guard id == self.operationID else { return }
                if Task.isCancelled { await self.finishCancelled(.open, start: start, operationID: id); return }
                self.recentProjectsMessage = "Access to \(reference.displayName) needs to be restored with Open Project."
                self.transition(to: .welcome)
                await self.record(.open, start: start, result: .failure, failure: .staleSecurityScope)
            }
        }
    }

    func forgetRecentProject(_ reference: RecentProjectReference) {
        enqueueRecentProjects { owner in
            let next = RecentProjectPolicy.removing(reference.id, from: owner.recentProjects)
            guard next != owner.recentProjects else { return }
            do {
                try await owner.recentProjectStore.save(next)
                owner.recentProjects = next
                owner.recentProjectsMessage = nil
            }
            catch { owner.recentProjectsMessage = "The recent-project list could not be updated. Project access was not changed." }
        }
    }

    /// One ordering boundary for the existing store. Compute each mutation
    /// after earlier persistence completes, so a late load/remove cannot
    /// resurrect a forgotten entry or overwrite a successful later open.
    @discardableResult
    private func enqueueRecentProjects(_ work: @escaping @MainActor (LaunchExperienceController) async -> Void) -> Task<Void, Never> {
        let previous = recentProjectsTask, id = UUID()
        recentProjectsRequestID = id
        pendingRecentProjectOperations += 1; isUpdatingRecentProjects = true
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                pendingRecentProjectOperations -= 1
                isUpdatingRecentProjects = pendingRecentProjectOperations > 0
                if recentProjectsRequestID == id { recentProjectsTask = nil }
            }
            await work(self)
        }
        recentProjectsTask = task
        return task
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

    var canReturnToCurrentProject: Bool { isPreviewScenario || returnState == .workspace }

    func restoreRecovery() {
        if isPreviewScenario {
            transition(to: .workspace)
            return
        }
        guard case .recovery = state, !isResolvingRecovery, let candidate = lifecycle.recoveryCandidate else { return }
        let action = UUID(), launch = operationID
        recoveryActionID = action; isResolvingRecovery = true; recoveryHistoryMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { if recoveryActionID == action { isResolvingRecovery = false } }
            guard launch == operationID, case .recovery = state else { return }
            guard lifecycle.recoveryCandidate?.fingerprint == candidate.fingerprint else {
                recoveryHistoryMessage = "The recovery candidate changed. Choose Later and review again; the old Restore action did not run."
                return
            }
            let result = await lifecycle.requestRestoreRecovery()
            guard launch == operationID, case .recovery = state else { return }
            switch result {
            case .completed: transition(to: .workspace)
            case .cancelled: recoveryHistoryMessage = "Restore cancelled. The recovery candidate is retained."
            case .failed(let failure): recoveryHistoryMessage = failure.localizedDescription
            }
        }
    }

    func discardRecovery() {
        if isPreviewScenario { transition(to: .workspace); return }
        guard case .recovery = state, !isResolvingRecovery, let candidate = lifecycle.recoveryCandidate else { return }
        let action = UUID(), launch = operationID
        recoveryActionID = action; isResolvingRecovery = true; recoveryHistoryMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { if recoveryActionID == action { isResolvingRecovery = false } }
            guard launch == operationID, case .recovery = state else { return }
            guard lifecycle.recoveryCandidate?.fingerprint == candidate.fingerprint else {
                recoveryHistoryMessage = "The recovery candidate changed. Choose Later and review again; the old Discard action did not run."
                return
            }
            await lifecycle.discardRecovery()
            guard launch == operationID, case .recovery = state else { return }
            if lifecycle.recoveryCandidate == nil, lifecycle.failure == nil { transition(to: .workspace) }
            else {
                recoveryHistoryMessage = lifecycle.failure?.localizedDescription
                    ?? "Recovery was not discarded. Inspect or try again; the retained candidate is unchanged."
            }
        }
    }

    func inspectRecovery() {
        lifecycle.isRecoveryDetailsPresented = true
    }

    func reviewWelcomeRecovery() {
        guard recoveryAvailableAtWelcome, let candidate = lifecycle.recoveryCandidate else { return }
        recoveryHistoryMessage = nil
        transition(to: .recovery(.init(title: "Unsaved project recovery available",
            message: "Your earlier work is preserved. Restore it, inspect it, or return without changing it.",
            revisionSummary: candidate.summary)))
    }

    func reviewRecoveryHistory() {
        guard state == .welcome else { return }
        startOperation(.discoverRecovery) { [weak self] id, start in
            guard let self, id == self.operationID else { return }
            // Manual history inspection is read-only and cancellation-safe.
            // Do not reuse the non-cancellable automatic launch transition.
            self.transition(to: .working(ProjectLoadingStatus(
                title: "Reviewing recovery history…",
                detail: "Inspecting retained snapshots without changing the current project.",
                progress: nil, canCancel: true,
                accessibilityLabel: "Reviewing recovery history, cancel available")))
            await self.lifecycle.discoverUntitledRecoveryCandidate()
            guard self.operationID == id else { return }
            if Task.isCancelled {
                self.recoveryAvailableAtWelcome = self.lifecycle.recoveryCandidate != nil
                self.recoveryHistoryMessage = "Recovery review cancelled. Retained snapshots are unchanged."
                await self.finishCancelled(.discoverRecovery, start: start, operationID: id)
                return
            }
            self.recoveryAvailableAtWelcome = self.lifecycle.recoveryCandidate != nil
            self.transition(to: .welcome)
            if self.recoveryAvailableAtWelcome {
                self.recoveryHistoryMessage = nil
                self.reviewWelcomeRecovery()
            } else {
                self.recoveryHistoryMessage = self.lifecycle.failure?.localizedDescription
                    ?? "No valid retained recovery snapshot is available."
            }
            await self.record(.discoverRecovery, start: start,
                result: self.lifecycle.failure == nil ? .success : .failure, failure: self.lifecycle.failure)
        }
    }

    func deferRecovery() {
        guard case .recovery = state, !isResolvingRecovery else { return }
        recoveryAvailableAtWelcome = lifecycle.recoveryCandidate != nil
        // A deliberately opened saved project is already safe to inspect.
        // Untitled discovery returns to Welcome without consuming the bytes.
        transition(to: lifecycle.fileURL == nil ? .welcome : .workspace)
    }

    @discardableResult
    func presentOpenPanel(chooseProject: @MainActor () -> URL? = { NativeProjectOpenPanel.chooseProject() }) -> Bool {
        let origin = (lifecycle.session.document.id, lifecycle.session.document.revision, operationID)
        let url = chooseProject()
        guard origin.2 == operationID else { return false }
        guard lifecycle.session.document.id == origin.0, lifecycle.session.document.revision == origin.1 else {
            lifecycle.noteNativePanelContextChanged(.open, originatingDocumentID: origin.0)
            return false
        }
        guard let url else {
            lifecycle.noteCancellation()
            return false
        }
        openProject(url, userSelected: true)
        return true
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
        guard state == .welcome, !isPreviewScenario, !checkedInitialRecovery else { return }
        checkedInitialRecovery = true
        await lifecycle.discoverUntitledRecoveryCandidate(automaticCrashOnly: true)
        guard state == .welcome else { return }
        recoveryAvailableAtWelcome = lifecycle.recoveryCandidate != nil
    }

    private func startOperation(
        _ operation: LifecycleOperation,
        work: @escaping @MainActor (UUID, ContinuousClock.Instant) async -> Void
    ) {
        operationTask?.cancel()
        let id = UUID()
        operationID = id
        captureOperationReturnState()
        let start = ContinuousClock.now
        operationTask = Task { await work(id, start) }
    }

    private func captureOperationReturnState() {
        switch state {
        case .workspace: returnState = .workspace
        case .welcome: returnState = .welcome
        case .working, .failure: break // Keep the actual origin across retries/replacement work.
        case .recovery: returnState = lifecycle.fileURL == nil ? .welcome : .workspace
        }
    }

    private enum CreationChoice: Equatable {
        case blank, starter, aurora, auroraFlow

        var title: String {
            switch self {
            case .blank: "blank project"; case .starter: "Starter Site"; case .aurora: "Aurora Editorial"
            case .auroraFlow: "Aurora Flow"
            }
        }
        var detail: String {
            switch self {
            case .blank: "Preparing the approved Home and Not Found page baseline."
            case .starter: "Preparing editable Home and About pages with semantic site structure."
            case .aurora: "Loading an editable four-page editorial website and its local coastal image."
            case .auroraFlow: "Loading an editable interactive website with a flowing gradient, glass cards and a QR footer."
            }
        }
        func package() async throws -> ProjectPackage {
            switch self {
            case .blank: return ProjectPackage(document: ProjectCreation.blank())
            case .starter: return ProjectPackage(document: StarterSiteTemplate.document())
            case .aurora:
                guard let url = BundledSiteTemplates.auroraURL() else { throw ProjectPackageError.packageUnavailable }
                return try await PackagedSiteTemplateLoader().load(from: url, templateID: BundledSiteTemplates.auroraID)
            case .auroraFlow:
                guard let url = BundledSiteTemplates.auroraFlowURL() else { throw ProjectPackageError.packageUnavailable }
                return try await PackagedSiteTemplateLoader().load(from: url, templateID: BundledSiteTemplates.auroraFlowID)
            }
        }
    }

    private func performCreation(
        _ choice: CreationChoice,
        operationID id: UUID,
        start: ContinuousClock.Instant
    ) async {
        guard id == operationID else { return }
        transition(to: .working(ProjectLoadingStatus(
            title: "Creating \(choice.title)…",
            detail: choice.detail,
            progress: 0.5,
            canCancel: true,
            accessibilityLabel: "Creating \(choice.title), step 1 of 2"
        )))
        await Task.yield()
        guard id == operationID, !Task.isCancelled else {
            await finishCancelled(.new, start: start, operationID: id)
            return
        }
        let package: ProjectPackage
        do {
            package = try await choice.package()
        } catch is CancellationError {
            await finishCancelled(.new, start: start, operationID: id)
            return
        } catch {
            guard id == operationID else { return }
            transition(to: .failure(Self.presentation(for: .malformedPackage)))
            await record(.new, start: start, result: .failure, failure: .malformedPackage)
            return
        }
        guard id == operationID, !Task.isCancelled else {
            await finishCancelled(.new, start: start, operationID: id)
            return
        }
        transition(to: .working(ProjectLoadingStatus(
            title: "Creating \(choice.title)…",
            detail: "Establishing one clean project history baseline.",
            progress: 1,
            canCancel: false,
            accessibilityLabel: "Creating \(choice.title), final non-cancelable step"
        )))
        let result = await lifecycle.requestNewDocument(package.document, resourceMembers: package.optionalMembers)
        guard id == operationID else { return }
        switch result {
        case .completed:
            transition(to: .workspace)
            await record(.new, start: start, result: .success, failure: nil)
        case .cancelled:
            await finishCancelled(.new, start: start, operationID: id)
        case .failed(let failure):
            transition(to: .failure(Self.presentation(for: failure)))
            await record(.new, start: start, result: .failure, failure: failure)
        }
    }

    private func performOpen(
        _ url: URL,
        userSelected: Bool = false,
        rememberOnSuccess: Bool,
        operationID id: UUID,
        start: ContinuousClock.Instant
    ) async {
        guard id == operationID else { return }
        let result = await lifecycle.requestOpen(url, userSelected: userSelected) { [weak self] update in
            await self?.receive(update, operationID: id)
        }
        guard id == operationID else { return }
        if Task.isCancelled {
            await finishCancelled(.open, start: start, operationID: id)
            return
        }
        switch result {
        case .completed:
            if rememberOnSuccess { await rememberRecentProject(url) }
            guard id == operationID else { return }
            if Task.isCancelled { await finishCancelled(.open, start: start, operationID: id); return }
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
            await finishCancelled(.open, start: start, operationID: id)
        case .failed(let failure):
            transition(to: .failure(Self.presentation(for: failure)))
            await record(.open, start: start, result: .failure, failure: failure)
        }
    }

    private func rememberRecentProject(_ url: URL) async {
        await enqueueRecentProjects { owner in
            let next = RecentProjectPolicy.recording(url, in: owner.recentProjects)
            guard next != owner.recentProjects else { return }
            do {
                try await owner.recentProjectStore.save(next)
                owner.recentProjects = next
                owner.recentProjectsMessage = nil
            } catch {
                owner.recentProjectsMessage = "The project opened, but the recent-project list could not be updated."
            }
        }.value
    }

    private func receive(_ update: ProjectLoadUpdate, operationID id: UUID) {
        guard id == operationID else { return }
        transition(to: .working(update.status))
    }

    private func finishCancelled(_ operation: LifecycleOperation, start: ContinuousClock.Instant, operationID id: UUID) async {
        guard id == operationID else { return }
        transition(to: returnState)
        await record(operation, start: start, result: .cancelled, failure: nil)
    }

    private func transition(to newState: LaunchExperienceState) {
        if lifecycle.recoveryCandidate == nil { recoveryAvailableAtWelcome = false }
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
        let sanitized = DiagnosticStableIdentifier.sanitize(
            identifier,
            domain: .launch,
            kind: "document"
        )
        await diagnostics.append(LaunchDiagnosticRecord(
            requirementIDs: Self.requirementIDs.sorted(),
            operation: operation,
            state: state.kind,
            sanitizedDocumentID: sanitized,
            durationNanoseconds: nanos,
            result: result,
            failureCategory: failure.map(\.diagnosticCategory)
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
    case newProject, starterProject, auroraProject, auroraFlowProject, openProject, cancel, primaryFailure, chooseAnother
    case restoreRecovery, discardRecovery, inspectRecovery
}

struct LaunchExperienceView: View {
    @ObservedObject var controller: LaunchExperienceController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focus: LaunchFocus?
    @State private var cover: NSImage?
    @State private var discardRequest: DiscardRequest?
    /// The Aurora Flow card appears only when its reviewed sample is bundled.
    private var showsAuroraFlow: Bool { BundledSiteTemplates.auroraFlowURL() != nil }

    private struct DiscardRequest {
        let fingerprint: PackageFingerprint?
    }

    private enum Template: CaseIterable {
        case blank, starter, aurora, auroraFlow

        var title: String {
            switch self {
            case .blank: "Blank Site"; case .starter: "Starter Site"; case .aurora: "Aurora Editorial"
            case .auroraFlow: "Aurora Flow"
            }
        }
        var caption: String {
            switch self {
            case .blank: "Empty canvas"; case .starter: "Home + About"; case .aurora: "Four-page template"
            case .auroraFlow: "Interactive template"
            }
        }
        var symbol: String {
            switch self {
            case .blank: "doc"; case .starter: "rectangle.split.2x1"; case .aurora: "sun.horizon"
            case .auroraFlow: "wind"
            }
        }
        var focus: LaunchFocus {
            switch self {
            case .blank: .newProject; case .starter: .starterProject; case .aurora: .auroraProject
            case .auroraFlow: .auroraFlowProject
            }
        }
        var identifier: String {
            switch self {
            case .blank: "launch.newBlankProject"
            case .starter: "launch.newStarterProject"
            case .aurora: "launch.newAuroraProject"
            case .auroraFlow: "launch.newAuroraFlowProject"
            }
        }
        var hint: String {
            switch self {
            case .blank: "Creates Home and Not Found as a clean baseline"
            case .starter: "Creates editable Home and About pages with Header, Main, and Footer"
            case .aurora: "Creates an independent editable copy with local artwork and responsive content"
            case .auroraFlow: "Creates an independent editable copy with a flowing gradient, glass cards and a QR footer"
            }
        }
    }

    private var palette: SiteForgeChromePalette { .init(scheme: scheme, contrast: contrast) }
    private var isWorking: Bool { if case .working = controller.state { true } else { false } }
    private var isRecovery: Bool { controller.state.kind == .recovery }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(palette.line).frame(width: 1)
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch controller.state {
                    case .welcome: welcome
                    case .working(let status): working(status)
                    case .failure(let failure): failureView(failure)
                    case .recovery(let recovery): recoveryView(recovery)
                    case .workspace: EmptyView()
                    }
                }.frame(maxWidth: 930, alignment: .leading)
                    .padding(.horizontal, 42)
                    .padding(.top, 73)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(palette.base.ignoresSafeArea())
        .workspaceChrome(.launchCard)
        .frame(minWidth: WorkspaceMetrics.windowContentMinimum.width,
               minHeight: WorkspaceMetrics.windowContentMinimum.height)
        .task {
            guard cover == nil, let url = BundledSiteTemplates.auroraCoverURL() else { return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url, options: .mappedIfSafe) }.value
            guard !Task.isCancelled, let data else { return }
            cover = NSImage(data: data)
        }
        .accessibilityElement(children: .contain)
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
            await controller.loadRecentProjects()
            if let request = WorkspaceLaunchRequestQueue.shared.take() {
                switch request {
                case .new: await controller.createBlankProjectAndWait()
                case .open(let url): await controller.openProjectAndWait(url, userSelected: true)
                }
            } else {
                await controller.discoverInitialRecovery()
            }
            await Task.yield()
            assignInitialFocus()
        }
        .onChange(of: controller.state.kind) { _, _ in
            assignInitialFocus()
            controller.announceCurrentState()
        }
        .animation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.18), value: controller.state.kind)
        .alert("Discard Recovery?", isPresented: Binding(
            get: { discardRequest != nil },
            set: { if !$0 { discardRequest = nil } }
        ), presenting: discardRequest) { request in
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("launch.recovery.discard.cancel")
            Button("Discard Recovery", role: .destructive) {
                if controller.lifecycle.recoveryCandidate?.fingerprint == request.fingerprint {
                    controller.discardRecovery()
                } else {
                    controller.announceCurrentState()
                }
            }.accessibilityIdentifier("launch.recovery.discard.confirm")
        } message: { _ in
            Text("This removes the selected recovery snapshot. The saved project stays as it is.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage).resizable()
                    .interpolation(.high).frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text("SiteForge").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("launch.brand")
            }.padding(.horizontal, 8).padding(.bottom, 29)
            sidebarLabel("Start", symbol: "house", selected: !isRecovery)
                .accessibilityIdentifier("launch.start")
            Button { controller.presentOpenPanel() } label: {
                sidebarLabel("Open Project…", symbol: "folder")
            }.buttonStyle(.plain)
                .disabled(isWorking)
                .focused($focus, equals: .openProject)
                .accessibilityHint("Choose a SiteForge project to validate before opening")
                .accessibilityIdentifier("launch.openProject")
            Spacer(minLength: 0)
            rule.padding(.bottom, 6)
            if isRecovery {
                sidebarLabel("Recovery History", symbol: "clock.arrow.circlepath", selected: true)
            } else {
                Button(action: controller.reviewRecoveryHistory) {
                    sidebarLabel("Recovery History", symbol: "clock.arrow.circlepath")
                }.buttonStyle(.plain)
                    .disabled(controller.state.kind != .welcome)
                    .accessibilityHint("Inspect retained snapshots before choosing an action")
                    .accessibilityIdentifier("launch.recovery.history")
            }
            SettingsLink { sidebarLabel("Settings", symbol: "gearshape") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("launch.settings")
        }.padding(16).padding(.top, 24)
            .frame(width: 224)
            .frame(maxHeight: .infinity)
            .background(palette.panel)
    }

    private func sidebarLabel(_ title: String, symbol: String, selected: Bool = false) -> some View {
        Label {
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(palette.text)
        } icon: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? palette.accent : palette.quiet).frame(width: 18)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 34)
        .background(selected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rule: some View {
        Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Create a website").font(.system(size: 38, weight: .semibold))
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 16) {
                templateButton(.blank).keyboardShortcut(.defaultAction)
                templateButton(.starter)
                templateButton(.aurora)
                if showsAuroraFlow { templateButton(.auroraFlow) }
            }.padding(.top, 26)
            recentProjectsSection
            if let message = controller.recoveryHistoryMessage {
                Text(message).font(.caption).foregroundStyle(palette.quiet)
                    .padding(.top, 14)
                    .accessibilityIdentifier("launch.recovery.history.message")
            }
            if controller.recoveryAvailableAtWelcome {
                Button("Review Recovery…", action: controller.reviewWelcomeRecovery)
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .padding(.top, 14)
                    .accessibilityIdentifier("launch.recovery.review")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("launch.welcome")
    }

    private func templateButton(_ template: Template) -> some View {
        Button {
            switch template {
            case .blank: controller.createBlankProject()
            case .starter: controller.createStarterProject()
            case .aurora: controller.createAuroraProject()
            case .auroraFlow: controller.createAuroraFlowProject()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                templateArt(template).frame(height: 145)
                HStack(spacing: 10) {
                    Image(systemName: template.symbol).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(template == .blank ? palette.accent : palette.quiet)
                        .frame(width: 30, height: 30)
                        .background(template == .blank ? palette.selected : palette.inset,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                        Text(template.caption).font(.system(size: 12)).foregroundStyle(palette.quiet)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(palette.faint)
                        .accessibilityHidden(true)
                }.padding(12)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(focus == template.focus ? palette.accent : palette.line, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($focus, equals: template.focus)
            .accessibilityLabel(template.title)
            .accessibilityHint(template.hint)
            .accessibilityIdentifier(template.identifier)
    }

    private func templateArt(_ template: Template) -> some View {
        GeometryReader { geo in
            ZStack {
                if template == .aurora, let cover {
                    Image(nsImage: cover).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.63)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AURORA").font(.system(size: 8, weight: .semibold)).tracking(2)
                        Text("Along the coast").font(.system(size: 22, weight: .medium, design: .serif))
                    }.foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(18)
                } else if template == .auroraFlow {
                    auroraFlowArt
                } else {
                    let blank = template == .blank
                    blank ? palette.shade(0x252936, 0xE1E5FB) : palette.shade(0x283633, 0xE2EFE8)
                    Canvas { context, size in
                        var path = Path()
                        for x in stride(from: 14.0, to: size.width, by: 14) {
                            path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height))
                        }
                        for y in stride(from: 14.0, to: size.height, by: 14) {
                            path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y))
                        }
                        context.stroke(path, with: .color(palette.shade(0x353A4A, 0xBAC2DE).opacity(0.5)), lineWidth: 0.5)
                    }
                    templatePage(blank: blank)
                        .frame(width: min(max(0, geo.size.width - 36), 156), height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }.accessibilityHidden(true)
    }

    /// Native static preview of the sample's resting hero gradient and glass
    /// card. It is decorative card art, not website content or an animation.
    private var auroraFlowArt: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.231, green: 0.102, blue: 0.580),
                                    Color(red: 0.122, green: 0.227, blue: 0.478),
                                    Color(red: 0.020, green: 0.380, blue: 0.361)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(0.14))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.28), lineWidth: 0.5) }
                .frame(width: 74, height: 46)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(14)
            VStack(alignment: .leading, spacing: 3) {
                Text("AURORA / FLOW").font(.system(size: 8, weight: .semibold)).tracking(2)
                Text("Make room for possibility").font(.system(size: 18, weight: .semibold))
            }.foregroundStyle(.white).padding(18)
        }
    }

    private func templatePage(blank: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in Circle().fill(.black.opacity(0.20)).frame(width: 3, height: 3) }
                Spacer()
            }.padding(.horizontal, 7).frame(height: 13)
                .background(Color(red: 0.86, green: 0.87, blue: 0.91))
            if blank {
                Rectangle().fill(Color(red: 0.96, green: 0.96, blue: 0.99))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.25, green: 0.35, blue: 0.32)).frame(width: 39, height: 4)
                    RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.72, green: 0.83, blue: 0.78)).frame(height: 23)
                    HStack(spacing: 5) {
                        ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.83, green: 0.88, blue: 0.85)) }
                    }.frame(height: 13)
                    Spacer(minLength: 0)
                }.padding(10).background(Color(red: 0.95, green: 0.97, blue: 0.96))
            }
        }
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent projects")
                .font(.system(size: 21, weight: .semibold)).foregroundStyle(palette.text)
                .accessibilityIdentifier("launch.recentProjects.title")
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 15)
            rule
            if controller.recentProjects.isEmpty {
                Label("No recent projects", systemImage: "clock")
                    .font(.system(size: 13)).foregroundStyle(palette.quiet)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(controller.recentProjects.prefix(4))) { project in
                        HStack(spacing: 8) {
                            Button { controller.openRecentProject(project) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "doc").foregroundStyle(palette.quiet)
                                    Text(project.displayName).lineLimit(1).foregroundStyle(palette.text)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(palette.faint)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .help(project.displayName)
                                .accessibilityLabel("Open recent project \(project.displayName)")
                                .accessibilityHint("Uses SiteForge’s retained macOS file authorization")
                                .accessibilityIdentifier("launch.recentProject.\(project.id.rawValue)")
                            Button { controller.forgetRecentProject(project) } label: {
                                Image(systemName: "xmark.circle")
                            }.buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(project.displayName) from Recent Projects")
                                .accessibilityIdentifier("launch.recentProject.remove.\(project.id.rawValue)")
                                .disabled(controller.isUpdatingRecentProjects)
                        }.font(.system(size: 13)).padding(.vertical, 10)
                        rule
                    }
                }.accessibilityElement(children: .contain)
                    .accessibilityIdentifier("launch.recentProjects.scroll")
            }
            if controller.isUpdatingRecentProjects {
                ProgressView("Updating recent projects…").controlSize(.small)
                    .accessibilityIdentifier("launch.recentProjects.progress")
            }
            if let message = controller.recentProjectsMessage {
                Text(message).font(.caption).foregroundStyle(palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("launch.recentProjects.status")
                Button("Locate with Open Project…") { controller.presentOpenPanel() }
                    .accessibilityIdentifier("launch.recentProjects.locate")
            }
        }.padding(.top, 48)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 36, weight: .semibold))
            .foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
    }

    private func working(_ status: ProjectLoadingStatus) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heading(status.displayedTitle).accessibilityIdentifier("launch.operation.title")
            Text(status.displayedDetail).font(.system(size: 14)).foregroundStyle(palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("launch.operation.status")
            if let progress = status.progress {
                ProgressView(value: progress).tint(palette.accent).frame(maxWidth: 380)
                    .accessibilityValue("\(Int(progress * 100)) percent")
                    .accessibilityIdentifier("launch.progress.determinate")
            } else {
                Group {
                    if LaunchExperienceController.usesAnimatedIndeterminateProgress(reduceMotion: effectiveReduceMotion) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "hourglass").foregroundStyle(palette.quiet)
                    }
                }.accessibilityElement(children: .ignore)
                    .accessibilityLabel(effectiveReduceMotion ? "Indeterminate progress, static" : "Indeterminate progress")
                    .accessibilityIdentifier("launch.progress.indeterminate")
            }
            if status.canCancel && !status.isCancellationRequested {
                Button("Cancel") { controller.cancelCurrentOperation() }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .keyboardShortcut(.cancelAction)
                    .focused($focus, equals: .cancel)
                    .accessibilityHint("Keeps the current valid project unchanged")
                    .accessibilityIdentifier("launch.cancel")
            } else if !status.isCancellationRequested {
                Label("This final step can’t be safely canceled.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(palette.quiet)
                    .accessibilityIdentifier("launch.nonCancelable")
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(status.accessibilityLabel)
            .accessibilityIdentifier("launch.loading")
    }

    private func failureView(_ failure: LaunchFailurePresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.danger)
                .frame(width: 42, height: 42)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            heading(failure.title).accessibilityIdentifier("launch.failure.title")
            Text(failure.message).font(.system(size: 14)).foregroundStyle(palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("launch.failure.message")
            HStack(spacing: 9) {
                if failure.primaryAction == .retry {
                    Button("Try Again", action: controller.retry)
                        .buttonStyle(SiteForgeChromeButtonStyle(palette: palette, primary: true))
                        .focused($focus, equals: .primaryFailure)
                        .accessibilityIdentifier("launch.retry")
                }
                Button { controller.presentOpenPanel() } label: { Label("Open Another…", systemImage: "folder") }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .focused($focus, equals: .chooseAnother)
                    .accessibilityIdentifier("launch.chooseAnother")
                if controller.canReturnToCurrentProject {
                    Button("Return to Current Project", action: controller.returnToCurrentProject)
                        .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                        .accessibilityIdentifier("launch.returnToProject")
                }
            }.padding(.top, 4)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("launch.failure")
    }

    private func recoveryView(_ recovery: LaunchRecoveryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Recover your project")
            rule.padding(.top, 29)
            HStack(spacing: 11) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 35, height: 35)
                    .background(palette.selected, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(recovery.revisionSummary).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("launch.recovery.summary")
                    Text(recovery.message).font(.system(size: 12)).foregroundStyle(palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Inspect", action: controller.inspectRecovery)
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .focused($focus, equals: .inspectRecovery)
                    .accessibilityIdentifier("launch.recovery.inspect")
                Button("Restore", action: controller.restoreRecovery)
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette, primary: true))
                    .keyboardShortcut(.defaultAction)
                    .focused($focus, equals: .restoreRecovery)
                    .accessibilityIdentifier("launch.recovery.restore")
            }.padding(.vertical, 14)
            rule
            HStack {
                Button("Discard Recovery…") {
                    discardRequest = .init(fingerprint: controller.lifecycle.recoveryCandidate?.fingerprint)
                }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(palette.danger)
                    .focused($focus, equals: .discardRecovery)
                    .accessibilityIdentifier("launch.recovery.discard")
                Spacer()
                Button("Later", action: controller.deferRecovery).buttonStyle(.plain)
                    .foregroundStyle(palette.quiet).keyboardShortcut(.cancelAction)
                    .help("Keep the recovery snapshot and return without restoring it")
                    .accessibilityIdentifier("launch.recovery.later")
            }.padding(.top, 15)
            if let message = controller.recoveryHistoryMessage {
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12).accessibilityIdentifier("launch.recovery.status")
            }
            if controller.isResolvingRecovery {
                ProgressView("Completing recovery action…").controlSize(.small)
                    .padding(.top, 12).accessibilityIdentifier("launch.recovery.progress")
            }
        }.frame(maxWidth: 630, alignment: .leading)
            .disabled(controller.isResolvingRecovery)
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
