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
        case blank, starter, aurora

        var title: String {
            switch self { case .blank: "blank project"; case .starter: "Starter Site"; case .aurora: "Aurora Editorial" }
        }
        var detail: String {
            switch self {
            case .blank: "Preparing the approved Home and Not Found page baseline."
            case .starter: "Preparing editable Home and About pages with semantic site structure."
            case .aurora: "Loading an editable four-page editorial website and its local coastal image."
            }
        }
        func package() async throws -> ProjectPackage {
            switch self {
            case .blank: return ProjectPackage(document: ProjectCreation.blank())
            case .starter: return ProjectPackage(document: StarterSiteTemplate.document())
            case .aurora:
                guard let url = BundledSiteTemplates.auroraURL() else { throw ProjectPackageError.packageUnavailable }
                return try await PackagedSiteTemplateLoader().load(from: url, templateID: BundledSiteTemplates.auroraID)
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
    case newProject, starterProject, auroraProject, openProject, cancel, primaryFailure, chooseAnother
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
                .frame(maxWidth: 600)
                .padding(SiteForgeVisualSystem.launchOuterPadding)
        }
        .frame(
            // A named constrained UI-test placement is the one non-product
            // composition allowed to fit vertically.  Keeping the launch
            // surface on the same policy as the workspace prevents its
            // SwiftUI content minimum from pinning an otherwise valid
            // bottom-aligned test window at 700 points after the transition.
            minWidth: WorkspaceMetrics.effectiveMinimumWindowSize().width,
            minHeight: WorkspaceMetrics.effectiveMinimumWindowSize().height
        )
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
    }

    @ViewBuilder
    private var launchCard: some View {
        VStack(spacing: SiteForgeVisualSystem.launchSectionSpacing) {
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
        .padding(SiteForgeVisualSystem.launchInnerPadding)
        .workspaceChrome(.launchCard)
        .clipShape(RoundedRectangle(cornerRadius: SiteForgeVisualSystem.launchCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SiteForgeVisualSystem.launchCardCornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.13))
        }
        .shadow(color: .black.opacity(reduceTransparency ? 0.08 : 0.16),
                radius: SiteForgeVisualSystem.launchShadowRadius,
                y: SiteForgeVisualSystem.launchShadowOffset)
    }

    private var brand: some View {
        VStack(spacing: SiteForgeVisualSystem.standardSpacing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("SiteForge")
                .font(.largeTitle.bold())
            Text("Design durable websites in a native Mac workspace.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SiteForge. Design durable websites in a native Mac workspace.")
        .accessibilityIdentifier("launch.brand")
    }

    private var welcome: some View {
        VStack(spacing: SiteForgeVisualSystem.standardSpacing) {
            Text("Start building")
                .font(.title3.weight(.semibold))
            Text("Start blank, begin with a local editable structure, or open an existing SiteForge project.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SiteForgeVisualSystem.standardSpacing) { creationChoices }
                VStack(spacing: SiteForgeVisualSystem.compactSpacing + 4) { creationChoices }
            }
            Button("Open Project…") { controller.presentOpenPanel() }
                .focused($focus, equals: .openProject)
                .accessibilityHint("Choose a SiteForge project to validate before opening")
                .accessibilityIdentifier("launch.openProject")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SiteForgeVisualSystem.sectionSpacing) { launchAssurances }
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.compactSpacing) { launchAssurances }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            recentProjectsSection
            Button("Review Recovery History…", action: controller.reviewRecoveryHistory)
                .accessibilityHint("Inspect retained snapshots, including older sessions. Nothing is restored or removed until you choose an action.")
                .accessibilityIdentifier("launch.recovery.history")
            if let message = controller.recoveryHistoryMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("launch.recovery.history.message")
            }
            if controller.recoveryAvailableAtWelcome {
                GroupBox("Recoverable work") {
                    VStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                        Text("An earlier unsaved project is safely retained.")
                            .font(.caption).multilineTextAlignment(.center)
                        Button("Review Recovery…", action: controller.reviewWelcomeRecovery)
                            .accessibilityIdentifier("launch.recovery.review")
                    }.frame(maxWidth: .infinity)
                }.accessibilityIdentifier("launch.recovery.available")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.welcome")
    }

    @ViewBuilder
    private var creationChoices: some View {
        Button {
            controller.createBlankProject()
        } label: {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                Label("Blank Site", systemImage: "doc")
                    .font(.headline)
                Text("Home and Not Found, ready to shape from scratch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 210, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .focused($focus, equals: .newProject)
        .accessibilityLabel("Blank Site")
        .accessibilityHint("Creates Home and Not Found pages as one clean baseline")
        .accessibilityIdentifier("launch.newBlankProject")

        Button {
            controller.createStarterProject()
        } label: {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                Label("Starter Site", systemImage: "rectangle.3.group")
                    .font(.headline)
                Text("Editable Home and About pages with a semantic structure")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 210, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .focused($focus, equals: .starterProject)
        .accessibilityLabel("Starter Site")
        .accessibilityHint("Creates editable Home and About pages with Header, Main, and Footer sections")
        .accessibilityIdentifier("launch.newStarterProject")

        Button { controller.createAuroraProject() } label: {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                Label("Aurora Editorial", systemImage: "sun.horizon").font(.headline)
                Text("Editable coastal website · four linked pages")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(width: 210, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Aurora Editorial sample")
        .focused($focus, equals: .auroraProject)
        .accessibilityHint("Creates an independent editable copy with a local image and responsive content; the original is unchanged")
        .accessibilityIdentifier("launch.newAuroraProject")
    }

    @ViewBuilder
    private var launchAssurances: some View {
        Label("Local projects", systemImage: "internaldrive")
            .accessibilityLabel("Local projects")
            .accessibilityIdentifier("launch.assurance.local")
        Label("Private by default", systemImage: "lock")
            .accessibilityLabel("Private by default")
            .accessibilityIdentifier("launch.assurance.private")
        Label("Recovery protected", systemImage: "clock.arrow.circlepath")
            .accessibilityLabel("Recovery protected")
            .accessibilityIdentifier("launch.assurance.recovery")
    }

    @ViewBuilder
    private var recentProjectsSection: some View {
        if !controller.recentProjects.isEmpty || controller.recentProjectsMessage != nil {
            Divider()
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                if !controller.recentProjects.isEmpty {
                    Text("Recent Projects")
                        .font(.headline)
                        .accessibilityIdentifier("launch.recentProjects.title")
                    ScrollView {
                        LazyVStack(spacing: SiteForgeVisualSystem.controlInset) {
                            ForEach(Array(controller.recentProjects.prefix(4))) { project in
                                HStack(spacing: SiteForgeVisualSystem.controlInset) {
                                    Button {
                                        controller.openRecentProject(project)
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc")
                                            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.hairlineSpacing) {
                                                Text(project.displayName)
                                                    .lineLimit(1)
                                                Text("Authorized local project")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 8)
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.tertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open \(project.displayName)")
                                    .accessibilityLabel("Open recent project \(project.displayName)")
                                    .accessibilityHint("Uses SiteForge’s retained macOS file authorization")
                                    .accessibilityIdentifier("launch.recentProject.\(project.id.rawValue)")

                                    Button {
                                        controller.forgetRecentProject(project)
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove \(project.displayName) from Recent Projects")
                                    .accessibilityLabel("Remove \(project.displayName) from Recent Projects")
                                    .accessibilityIdentifier("launch.recentProject.remove.\(project.id.rawValue)")
                                    .disabled(controller.isUpdatingRecentProjects)
                                }
                                .padding(.horizontal, SiteForgeVisualSystem.panePadding)
                                .padding(.vertical, SiteForgeVisualSystem.compactSpacing)
                                .background(SiteForgeVisualSystem.elevatedSurface, in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 168)
                    .accessibilityIdentifier("launch.recentProjects.scroll")
                }
                if controller.isUpdatingRecentProjects {
                    ProgressView("Updating recent projects…").controlSize(.small)
                        .accessibilityIdentifier("launch.recentProjects.progress")
                }
                if let message = controller.recentProjectsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("launch.recentProjects.status")
                    Button("Locate with Open Project…") { controller.presentOpenPanel() }
                        .controlSize(.small)
                        .accessibilityIdentifier("launch.recentProjects.locate")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func working(_ status: ProjectLoadingStatus) -> some View {
        VStack(spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
            if let progress = status.progress {
                ProgressView(value: progress)
                    .accessibilityValue("\(Int(progress * 100)) percent")
                    .accessibilityIdentifier("launch.progress.determinate")
            } else {
                Group {
                    if LaunchExperienceController.usesAnimatedIndeterminateProgress(reduceMotion: effectiveReduceMotion) {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: "hourglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    effectiveReduceMotion ? "Indeterminate progress, static" : "Indeterminate progress"
                )
                .accessibilityIdentifier("launch.progress.indeterminate")
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
        VStack(spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(SiteForgeVisualSystem.warning)
                .accessibilityHidden(true)
            Text(failure.title)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("launch.failure.title")
            Text(failure.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("launch.failure.message")
            HStack(spacing: SiteForgeVisualSystem.standardSpacing) {
                if failure.primaryAction == .retry {
                    Button("Retry") { controller.retry() }
                        .buttonStyle(.borderedProminent)
                        .focused($focus, equals: .primaryFailure)
                        .accessibilityIdentifier("launch.retry")
                }
                Button("Choose Another Project…") { controller.presentOpenPanel() }
                    .focused($focus, equals: .chooseAnother)
                    .accessibilityIdentifier("launch.chooseAnother")
                if controller.canReturnToCurrentProject {
                    Button("Return to Current Project") { controller.returnToCurrentProject() }
                        .accessibilityIdentifier("launch.returnToProject")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.failure")
    }

    private func recoveryView(_ recovery: LaunchRecoveryPresentation) -> some View {
        VStack(spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
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
            if let message = controller.recoveryHistoryMessage {
                Text(message).font(.callout).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(message).accessibilityIdentifier("launch.recovery.status")
            }
            if controller.isResolvingRecovery {
                ProgressView("Completing recovery action…").controlSize(.small)
                    .accessibilityIdentifier("launch.recovery.progress")
            }
            HStack(spacing: SiteForgeVisualSystem.standardSpacing) {
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
                Button("Later", action: controller.deferRecovery)
                    .keyboardShortcut(.cancelAction)
                    .help("Keep all recovery data and return without restoring or discarding it")
                    .accessibilityIdentifier("launch.recovery.later")
            }
            .disabled(controller.isResolvingRecovery)
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
