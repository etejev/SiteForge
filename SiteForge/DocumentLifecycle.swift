import AppKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let siteForgeProject = UTType(exportedAs: "app.siteforge.project-package", conformingTo: .data)
}

enum DocumentLifecyclePhase: String, Equatable, Sendable {
    case clean, modified, saving, autosaving, failed, conflicted, recovered
}

enum DocumentLifecycleFailure: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied, staleSecurityScope, externalModification, conflict
    case malformedPackage, incompatiblePackage, malformedRecovery, ioFailure
    case unsafeFileMetadata, recoveryArtifactConflict, recoveryDeletionFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Permission was denied. Choose another location or review access in System Settings."
        case .staleSecurityScope: "File access has expired. Locate the project again."
        case .externalModification: "The project changed on disk. Reopen it or use Save As to preserve both versions."
        case .conflict: "A newer save superseded this operation. The current document is unchanged."
        case .malformedPackage: "The project could not be validated. The current document is unchanged."
        case .incompatiblePackage: "This project was created by an incompatible SiteForge version. Choose another project or update SiteForge."
        case .malformedRecovery: "Recovery data is invalid. Discard it or continue with the last saved project."
        case .unsafeFileMetadata: "The file has unsupported ownership or security metadata. Choose another location."
        case .recoveryArtifactConflict: "The recovery location contains an artifact SiteForge does not own. It was preserved; inspect the recovery folder and try again."
        case .recoveryDeletionFailed: "The recovery artifact could not be removed. It remains available; correct access and retry Discard."
        case .ioFailure: "The project could not be read or written. Check access and free space, then try again."
        }
    }
}

enum LifecycleOperationIntent: String, Equatable, Sendable {
    case new
    case open
    case save
    case saveAs
    case revert
    case autosave
    case restore
    case discardRecovery
    case close
    case discoverRecovery
}

typealias LifecycleOperation = LifecycleOperationIntent

struct LifecycleEpoch: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct LifecycleOperationID: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum LifecycleDestinationKind: String, Equatable, Sendable {
    case none
    case source
    case durable
    case recovery
}

struct LifecycleDestinationIdentity: Equatable, Sendable {
    let kind: LifecycleDestinationKind
    let sanitizedToken: String?

    static let none = LifecycleDestinationIdentity(kind: .none, sanitizedToken: nil)

    static func file(_ url: URL, kind: LifecycleDestinationKind) -> LifecycleDestinationIdentity {
        let normalized = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(normalized.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        return LifecycleDestinationIdentity(kind: kind, sanitizedToken: "destination-\(digest)")
    }
}

struct LifecycleOperationIdentity: Equatable, Sendable {
    let id: LifecycleOperationID
    let epoch: LifecycleEpoch
    let documentID: DocumentID
    let projectID: ProjectID
    let revision: UInt64
    let destination: LifecycleDestinationIdentity
    let intent: LifecycleOperationIntent
}

enum LifecycleBackendCheckpoint: Equatable, Sendable {
    case beforeRead
    case afterRead
    case beforeWritePreparation
    case beforeFilesystemWrite
    case afterFilesystemWrite
    case beforeRecoveryDeletion
    case afterRecoveryDeletion
}

protocol LifecycleBackendObserving: Sendable {
    func reached(_ checkpoint: LifecycleBackendCheckpoint, operation: LifecycleOperationIdentity) async
}

protocol LifecycleAutosaveDebouncing: Sendable {
    func wait() async throws
}

struct ContinuousLifecycleAutosaveDebouncer: LifecycleAutosaveDebouncing {
    let duration: Duration

    init(duration: Duration = .milliseconds(250)) {
        self.duration = duration
    }

    func wait() async throws {
        try await Task.sleep(for: duration)
    }
}

struct LifecycleClock: Sendable {
    let now: @Sendable () -> Date

    static let continuous = LifecycleClock(now: Date.init)
}

enum LifecycleResult: String, Sendable { case success, failure, cancelled, stale }
struct LifecycleDiagnostic: Equatable, Sendable {
    let requirementIDs: [String]
    let operation: LifecycleOperation
    let sanitizedOperationID: String
    let sanitizedEpoch: String
    let sanitizedDocumentID: String
    let sanitizedProjectID: String?
    let revision: UInt64
    let destinationKind: LifecycleDestinationKind
    let sanitizedDestination: String?
    let durationNanoseconds: UInt64
    let result: LifecycleResult
    let failure: String?
}

actor DocumentLifecycleDiagnostics {
    private(set) var records: [LifecycleDiagnostic] = []
    func append(_ record: LifecycleDiagnostic) { records.append(record) }
}

struct LoadedProject: Sendable {
    let package: ProjectPackage
    let fingerprint: PackageFingerprint
    let history: PersistedHistoryLoadResult
}

enum LifecycleBackendFault: Sendable { case none, permission, staleScope, io }

actor DocumentLifecycleBackend {
    private let store: ProjectPackageStore
    private let diagnostics: DocumentLifecycleDiagnostics
    private let historyStore: PersistedHistoryStore
    private let observer: (any LifecycleBackendObserving)?
    private var fault: LifecycleBackendFault = .none
    private var delayNanoseconds: UInt64 = 0

    init(
        store: ProjectPackageStore = ProjectPackageStore(),
        diagnostics: DocumentLifecycleDiagnostics = DocumentLifecycleDiagnostics(),
        historyStore: PersistedHistoryStore = PersistedHistoryStore(),
        observer: (any LifecycleBackendObserving)? = nil
    ) {
        self.store = store
        self.diagnostics = diagnostics
        self.historyStore = historyStore
        self.observer = observer
    }

    func configureForTesting(fault: LifecycleBackendFault = .none, delayNanoseconds: UInt64 = 0) {
        self.fault = fault
        self.delayNanoseconds = delayNanoseconds
    }

    func diagnosticRecords() async -> [LifecycleDiagnostic] { await diagnostics.records }
    func historyDiagnosticRecords() async -> [HistoryDiagnosticRecord] { await historyStore.diagnosticRecords() }

    func read(
        from url: URL,
        identity: LifecycleOperationIdentity,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async throws -> LoadedProject {
        let start = ContinuousClock.now
        do {
            try throwFault()
            try Task.checkCancellation()
            await observer?.reached(.beforeRead, operation: identity)
            try Task.checkCancellation()
            await progress?(.readingPackage)
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            let read = try await store.readSnapshot(from: url)
            try Task.checkCancellation()
            await progress?(.validatingCanonicalDocument)
            try Task.checkCancellation()
            await progress?(.validatingHistory)
            let history = await historyStore.load(from: read.package)
            try Task.checkCancellation()
            await progress?(.preparingWorkspace)
            await observer?.reached(.afterRead, operation: identity)
            try Task.checkCancellation()
            await record(identity, read.package.projectID, start, .success, nil)
            return LoadedProject(package: read.package, fingerprint: read.file.fingerprint, history: history)
        } catch is CancellationError {
            await record(identity, nil, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure = Self.map(error)
            await record(identity, nil, start, .failure, failure)
            throw failure
        }
    }

    func readRecovery(
        from url: URL,
        expectedProjectID: ProjectID? = nil,
        identity: LifecycleOperationIdentity
    ) async throws -> LoadedProject {
        let start = ContinuousClock.now
        do {
            try throwFault()
            try Task.checkCancellation()
            await observer?.reached(.beforeRead, operation: identity)
            try Task.checkCancellation()
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            let read = try await store.readOwnedRecoverySnapshot(
                from: url,
                expectedProjectID: expectedProjectID
            )
            try Task.checkCancellation()
            let history = await historyStore.load(from: read.package)
            try Task.checkCancellation()
            await observer?.reached(.afterRead, operation: identity)
            try Task.checkCancellation()
            await record(identity, read.package.projectID, start, .success, nil)
            return LoadedProject(package: read.package, fingerprint: read.file.fingerprint, history: history)
        } catch is CancellationError {
            await record(identity, nil, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure = Self.map(error)
            await record(identity, nil, start, .failure, failure)
            throw failure
        }
    }

    func write(
        _ package: ProjectPackage,
        history: PersistedHistorySnapshot,
        recoveryBoundary: UInt64? = nil,
        to url: URL,
        expected: PackageFingerprint?,
        identity: LifecycleOperationIdentity
    ) async throws -> PackageFingerprint {
        let start = ContinuousClock.now
        do {
            try throwFault()
            try Task.checkCancellation()
            await observer?.reached(.beforeWritePreparation, operation: identity)
            try Task.checkCancellation()
            try throwFault()
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            try Task.checkCancellation()
            let historySnapshot: PersistedHistorySnapshot
            if let recoveryBoundary {
                historySnapshot = await historyStore.recoverySnapshot(history, durableRevision: recoveryBoundary)
            } else {
                historySnapshot = history
            }
            try Task.checkCancellation()
            let packageWithHistory = try await historyStore.package(package, with: historySnapshot)
            try Task.checkCancellation()
            let policy: ProjectPackageArtifactPolicy = identity.intent == .autosave ? .recovery(package.projectID) : .durable
            let replacementExpectation: PackageFingerprint?
            if identity.intent == .autosave {
                replacementExpectation = try await ownedRecoveryExpectation(at: url, projectID: package.projectID)
            } else {
                replacementExpectation = expected
            }
            try Task.checkCancellation()
            await observer?.reached(.beforeFilesystemWrite, operation: identity)
            try Task.checkCancellation()
            let fingerprint = try await store.write(
                packageWithHistory,
                to: url,
                expected: replacementExpectation,
                policy: policy
            )
            await observer?.reached(.afterFilesystemWrite, operation: identity)
            await record(identity, package.projectID, start, .success, nil)
            return fingerprint
        } catch is CancellationError {
            await record(identity, package.projectID, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure = Self.map(error)
            await record(identity, package.projectID, start, failure == .conflict ? .stale : .failure, failure)
            throw failure
        }
    }

    func removeRecovery(
        _ url: URL,
        projectID: ProjectID,
        expected: PackageFingerprint? = nil,
        identity: LifecycleOperationIdentity
    ) async throws {
        do {
            try Task.checkCancellation()
            await observer?.reached(.beforeRecoveryDeletion, operation: identity)
            try Task.checkCancellation()
            try await store.removeOwnedRecovery(at: url, projectID: projectID, expected: expected)
            await observer?.reached(.afterRecoveryDeletion, operation: identity)
        } catch let error as ProjectPackageError where error == .packageUnavailable {
            return
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
    }

    func prepareRecoveryDirectory(
        _ directory: URL,
        identity: LifecycleOperationIdentity
    ) async throws {
        do {
            try Task.checkCancellation()
            try await store.prepareRecoveryDirectory(directory)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
    }

    func recoveryURLs(
        in directory: URL,
        identity: LifecycleOperationIdentity
    ) async throws -> [URL] {
        do {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            try await store.validateRecoveryDirectory(directory)
            try Task.checkCancellation()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "siteforge-recovery" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            try Task.checkCancellation()
            return urls
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func recoveryURL(for projectID: ProjectID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(projectID.description).siteforge-recovery", isDirectory: false)
    }

    private func throwFault() throws {
        switch fault {
        case .none: break
        case .permission: throw DocumentLifecycleFailure.permissionDenied
        case .staleScope: throw DocumentLifecycleFailure.staleSecurityScope
        case .io: throw DocumentLifecycleFailure.ioFailure
        }
    }

    private func ownedRecoveryExpectation(
        at url: URL,
        projectID: ProjectID
    ) async throws -> PackageFingerprint? {
        do {
            let read = try await store.readOwnedRecoverySnapshot(
                from: url,
                expectedProjectID: projectID
            )
            return read.file.fingerprint
        } catch let error as ProjectPackageError where error == .packageUnavailable {
            return nil
        }
    }

    private nonisolated static func map(_ error: Error) -> DocumentLifecycleFailure {
        if let error = error as? DocumentLifecycleFailure { return error }
        if let error = error as? ProjectPackageError {
            switch error {
            case .fileIdentityChanged: return .externalModification
            case .unsafeFileMetadata: return .unsafeFileMetadata
            case .unsafeRecoveryArtifact: return .recoveryArtifactConflict
            case .recoveryDeletionFailed: return .recoveryDeletionFailed
            case .ioFailure, .packageUnavailable: return .ioFailure
            case .unsupportedPackageVersion, .unsupportedDocumentSchema, .incompatibleReaderVersion:
                return .incompatiblePackage
            default: return .malformedPackage
            }
        }
        return .ioFailure
    }

    private func record(
        _ identity: LifecycleOperationIdentity,
        _ completedProjectID: ProjectID?,
        _ start: ContinuousClock.Instant,
        _ result: LifecycleResult,
        _ failure: DocumentLifecycleFailure?
    ) async {
        let duration = start.duration(to: .now).components
        let nanos = UInt64(max(0, duration.seconds)) * 1_000_000_000 + UInt64(max(0, duration.attoseconds / 1_000_000_000))
        let projectID = completedProjectID ?? identity.projectID
        await diagnostics.append(LifecycleDiagnostic(
            requirementIDs: ["SF-0301-008", "SF-0306-008", "SF-1504-008"],
            operation: identity.intent,
            sanitizedOperationID: Self.sanitized(identity.id.rawValue.uuidString, namespace: "operation"),
            sanitizedEpoch: Self.sanitized(identity.epoch.rawValue.uuidString, namespace: "epoch"),
            sanitizedDocumentID: Self.sanitized(identity.documentID.description, namespace: "document"),
            sanitizedProjectID: Self.sanitized(projectID.description, namespace: "project"),
            revision: identity.revision,
            destinationKind: identity.destination.kind,
            sanitizedDestination: identity.destination.sanitizedToken,
            durationNanoseconds: nanos,
            result: result,
            failure: failure.map { String(describing: $0) }
        ))
    }

    private nonisolated static func sanitized(_ value: String, namespace: String) -> String {
        namespace + "-" + SHA256.hash(data: Data(value.utf8)).prefix(5)
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct RecoveryCandidate: Equatable, Sendable {
    let package: ProjectPackage
    let url: URL
    let durableURL: URL?
    let history: PersistedHistoryLoadResult
    let fingerprint: PackageFingerprint
    var summary: String { "Revision \(package.document.revision), newer than the durable revision." }
}

enum DestructiveDocumentTransition: String, Equatable, Sendable {
    case newDocument, openProject, revertToSaved, restoreRecovery, closeWindow

    var title: String {
        switch self {
        case .newDocument: "Save changes before creating a new project?"
        case .openProject: "Save changes before opening another project?"
        case .revertToSaved: "Save changes before reverting?"
        case .restoreRecovery: "Save changes before restoring recovery?"
        case .closeWindow: "Save changes before closing?"
        }
    }

    var consequence: String {
        switch self {
        case .newDocument: "Creating a new project"
        case .openProject: "Opening another project"
        case .revertToSaved: "Reverting to the durable project"
        case .restoreRecovery: "Restoring the recovery candidate"
        case .closeWindow: "Closing this window"
        }
    }
}

enum UnsavedChangesDecision: Equatable, Sendable { case save, discard, cancel }

struct UnsavedChangesPrompt: Identifiable, Equatable, Sendable {
    let id: UUID
    let transition: DestructiveDocumentTransition
    let documentName: String

    var message: String {
        "\(transition.consequence) will discard unsaved changes in \(documentName) unless you save them first."
    }
}

enum DocumentTransitionResult: Equatable, Sendable {
    case completed
    case cancelled
    case failed(DocumentLifecycleFailure)
}

struct DocumentLifecycleStateSnapshot: Equatable, Sendable {
    let document: CanonicalDocument
    let history: PersistedHistorySnapshot
    let projectID: ProjectID
    let fileURL: URL?
    let durableFingerprint: PackageFingerprint?
    let phase: DocumentLifecyclePhase
    let displayName: String
    let failure: DocumentLifecycleFailure?
    let recoveryCandidate: RecoveryCandidate?
    let lifecycleEpoch: LifecycleEpoch
}

private enum ReplacementAuthorization: Equatable {
    case proceed(discardingChanges: Bool)
    case cancelled
    case failed(DocumentLifecycleFailure)
}

private enum LifecycleReadOutcome: Sendable {
    case success(LoadedProject)
    case cancelled
    case failure(DocumentLifecycleFailure)
}

private struct StableSavePresentation: Sendable {
    let phase: DocumentLifecyclePhase
    let failure: DocumentLifecycleFailure?
}

typealias SaveDestinationProvider = @MainActor (_ suggestedFilename: String) -> URL?

@MainActor
final class DocumentLifecycleController: ObservableObject {
    static let requirementIDs: Set<String> = [
        "SF-0203-004", "SF-0203-005", "SF-0203-006",
        "SF-0301-002", "SF-0301-004", "SF-0301-005", "SF-0301-006", "SF-0301-008",
        "SF-0306-001", "SF-0306-002", "SF-0306-003", "SF-0306-004", "SF-0306-005", "SF-0306-006", "SF-0306-008",
        "SF-1504-001", "SF-1504-003", "SF-1504-004", "SF-1504-006", "SF-1504-008",
        "SF-1603-004", "SF-1604-004", "SF-1702-004",
        "SF-1902-004", "SF-1902-005", "SF-1902-006",
    ]

    @Published private(set) var phase: DocumentLifecyclePhase = .clean
    @Published private(set) var displayName = "Untitled"
    @Published private(set) var failure: DocumentLifecycleFailure?
    @Published private(set) var recoveryCandidate: RecoveryCandidate?
    @Published private(set) var historyNotice: String?
    @Published private(set) var pendingUnsavedChangesPrompt: UnsavedChangesPrompt?
    @Published private(set) var transitionFailure: DocumentLifecycleFailure?
    @Published var isRecoveryDetailsPresented = false

    let session: DocumentSession
    let backend: DocumentLifecycleBackend
    private var project: ProjectPackage
    private var durableFingerprint: PackageFingerprint?
    private(set) var fileURL: URL?
    private let recoveryDirectory: URL
    private let saveDestinationProvider: SaveDestinationProvider
    private let autosaveDebouncer: any LifecycleAutosaveDebouncing
    private let clock: LifecycleClock
    private var lifecycleEpoch = LifecycleEpoch()
    private var autosaveTask: Task<Void, Never>?
    private var activeSaveTask: Task<Bool, Never>?
    private var activeReadTask: Task<LifecycleReadOutcome, Never>?
    private var activeReadOperation: LifecycleOperationIdentity?
    private var activeSaveOperation: LifecycleOperationIdentity?
    private var autosaveOperation: LifecycleOperationIdentity?
    private var activeRecoveryOperation: LifecycleOperationIdentity?
    private var observing = false
    private var hasUnsavedChanges = false
    private var observation: AnyCancellable?
    private var allowNextClose = false
    private var pendingDecisionContinuation: CheckedContinuation<UnsavedChangesDecision, Never>?

    init(
        session: DocumentSession,
        backend: DocumentLifecycleBackend = DocumentLifecycleBackend(),
        recoveryDirectory: URL = DocumentLifecycleController.defaultRecoveryDirectory,
        saveDestinationProvider: @escaping SaveDestinationProvider = DocumentLifecycleController.nativeSaveDestination,
        autosaveDebouncer: any LifecycleAutosaveDebouncing = ContinuousLifecycleAutosaveDebouncer(),
        clock: LifecycleClock = .continuous
    ) {
        self.session = session
        self.backend = backend
        self.recoveryDirectory = recoveryDirectory
        self.saveDestinationProvider = saveDestinationProvider
        self.autosaveDebouncer = autosaveDebouncer
        self.clock = clock
        let now = ProjectTimestamp(date: clock.now())
        project = ProjectPackage(createdAt: now, document: session.document)
        observation = session.$document.dropFirst().sink { [weak self] document in
            self?.documentDidChange(document)
        }
    }

    var isModified: Bool { hasUnsavedChanges }
    var title: String { displayName + (isModified ? " — Edited" : "") }
    var statusText: String {
        switch phase {
        case .clean: "Saved"
        case .modified: "Modified"
        case .saving: "Saving…"
        case .autosaving: "Autosaving recovery…"
        case .failed: failure?.localizedDescription ?? "Save failed"
        case .conflicted: failure?.localizedDescription ?? "File conflict"
        case .recovered: "Recovered — save to make durable"
        }
    }
    var canSave: Bool { (fileURL == nil || isModified) && phase != .saving && phase != .autosaving }
    var canRevert: Bool { fileURL != nil && isModified && phase != .saving && phase != .autosaving }
    var currentProjectID: ProjectID { project.projectID }
    var stateSnapshot: DocumentLifecycleStateSnapshot {
        DocumentLifecycleStateSnapshot(
            document: session.document,
            history: session.historySnapshot(),
            projectID: project.projectID,
            fileURL: fileURL,
            durableFingerprint: durableFingerprint,
            phase: phase,
            displayName: displayName,
            failure: failure,
            recoveryCandidate: recoveryCandidate,
            lifecycleEpoch: lifecycleEpoch
        )
    }

    var currentLifecycleEpoch: LifecycleEpoch { lifecycleEpoch }
    var hasPendingAutosaveWork: Bool { autosaveTask != nil || autosaveOperation != nil }

    static var defaultRecoveryDirectory: URL {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-SiteForgeRecoveryDirectory"),
           arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
#endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SiteForge/Recovery", isDirectory: true)
    }

    static func nativeSaveDestination(suggestedFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.siteForgeProject]
        panel.nameFieldStringValue = suggestedFilename
        panel.message = "Save an atomic SiteForge project package."
        return panel.runModal() == .OK ? panel.url : nil
    }

    @discardableResult
    func requestNewDocument() async -> DocumentTransitionResult {
        let previousProjectID = project.projectID
        switch await authorize(.newDocument) {
        case .cancelled: return .cancelled
        case .failed(let error): return .failed(error)
        case .proceed(let discarding):
            await beginDocumentBoundary()
            establishNewDocument()
            if discarding { await removeRecovery(for: previousProjectID) }
            return .completed
        }
    }

    private func establishNewDocument() {
        let document = ProjectCreation.blank()
        observing = true
        try? session.establishBaseline(document)
        observing = false
        let now = ProjectTimestamp(date: clock.now())
        project = ProjectPackage(createdAt: now, document: document)
        fileURL = nil; durableFingerprint = nil; displayName = "Untitled"
        failure = nil; recoveryCandidate = nil; phase = .clean; hasUnsavedChanges = false
        historyNotice = nil; transitionFailure = nil
    }

    @discardableResult
    func requestOpen(
        _ url: URL,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async -> DocumentTransitionResult {
        let previousProjectID = project.projectID
        switch await authorize(.openProject) {
        case .cancelled: return .cancelled
        case .failed(let error): return .failed(error)
        case .proceed(let discarding):
            await beginDocumentBoundary()
            let result = await loadAndAdopt(url, intent: .open, progress: progress)
            if result == .completed, discarding { await removeRecovery(for: previousProjectID) }
            return result
        }
    }

    private func loadAndAdopt(
        _ url: URL,
        intent: LifecycleOperationIntent,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async -> DocumentTransitionResult {
        let identity = makeOperation(
            intent: intent,
            destination: .file(url, kind: .source)
        )
        let readTask = Task<LifecycleReadOutcome, Never> { [backend] in
            do {
                return .success(try await backend.read(from: url, identity: identity, progress: progress))
            } catch is CancellationError {
                return .cancelled
            } catch let error as DocumentLifecycleFailure {
                return .failure(error)
            } catch {
                return .failure(.ioFailure)
            }
        }
        activeReadTask = readTask
        activeReadOperation = identity
        let outcome = await withTaskCancellationHandler {
            await readTask.value
        } onCancel: {
            readTask.cancel()
        }
        guard activeReadOperation == identity else { return .cancelled }
        activeReadTask = nil
        activeReadOperation = nil

        guard operationStillMatches(identity, requireRevision: true), !Task.isCancelled else {
            return .cancelled
        }

        switch outcome {
        case .success(let loaded):
            await beginDocumentBoundary()
            observing = true
            do {
                try session.establishBaseline(loaded.package.document)
                switch loaded.history {
                case .restored(let snapshot):
                    try session.installValidatedHistory(snapshot)
                    historyNotice = nil
                case .cleanBaseline(let reason):
                    historyNotice = reason.localizedDescription
                }
            } catch {
                observing = false
                setFailure(.malformedPackage)
                return .failed(.malformedPackage)
            }
            observing = false
            project = loaded.package; fileURL = url; durableFingerprint = loaded.fingerprint
            displayName = url.deletingPathExtension().lastPathComponent
            failure = nil; phase = .clean; hasUnsavedChanges = false
            await progress?(.checkingRecovery)
            await findRecoveryCandidate()
            transitionFailure = nil
            return .completed
        case .cancelled:
            return .cancelled
        case .failure(let error):
            setFailure(error)
            return .failed(error)
        }
    }

    @discardableResult func save(to destination: URL? = nil) async -> Bool {
        let invocationEpoch = lifecycleEpoch
        await cancelAndDrainAutosave()
        if let priorSave = activeSaveTask {
            _ = await priorSave.value
        }
        await cancelAndDrainAutosave()
        guard lifecycleEpoch == invocationEpoch, !Task.isCancelled else { return false }
        guard let target = destination ?? fileURL else { return false }
        let snapshot = session.document
        let historySnapshot = session.historySnapshot()
        let now = ProjectTimestamp(date: clock.now())
        let package = ProjectPackage(projectID: project.projectID, createdAt: project.createdAt, modifiedAt: now,
                                     document: snapshot, optionalMembers: project.optionalMembers, compatibility: project.compatibility)
        let intent: LifecycleOperationIntent = destination == nil ? .save : .saveAs
        let identity = makeOperation(
            intent: intent,
            destination: .file(target, kind: .durable),
            revision: snapshot.revision
        )
        let expected = (destination == nil || target == fileURL) ? durableFingerprint : nil
        let stablePresentation = StableSavePresentation(phase: phase, failure: failure)
        let saveTask = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performSave(
                package,
                history: historySnapshot,
                to: target,
                expected: expected,
                identity: identity,
                stablePresentation: stablePresentation
            )
        }
        activeSaveTask = saveTask
        activeSaveOperation = identity
        let saved = await withTaskCancellationHandler {
            await saveTask.value
        } onCancel: {
            saveTask.cancel()
        }
        if activeSaveOperation == identity {
            activeSaveTask = nil
            activeSaveOperation = nil
        }
        return saved
    }

    private func performSave(
        _ package: ProjectPackage,
        history: PersistedHistorySnapshot,
        to target: URL,
        expected: PackageFingerprint?,
        identity: LifecycleOperationIdentity,
        stablePresentation: StableSavePresentation
    ) async -> Bool {
        guard operationStillMatches(identity, requireRevision: true),
              activeSaveOperation == identity else { return false }
        phase = .saving
        failure = nil
        do {
            let fingerprint = try await backend.write(
                package,
                history: history,
                to: target,
                expected: expected,
                identity: identity
            )
            guard operationStillMatches(identity, requireRevision: false),
                  activeSaveOperation == identity,
                  identity.destination == .file(target, kind: .durable),
                  !Task.isCancelled else {
                return false
            }
            project = package
            fileURL = target
            durableFingerprint = fingerprint
            displayName = target.deletingPathExtension().lastPathComponent
            if session.document.revision == identity.revision {
                phase = .clean
                hasUnsavedChanges = false
                await removeRecovery(for: package.projectID)
            } else {
                phase = .modified
                hasUnsavedChanges = true
            }
            transitionFailure = nil
            return true
        } catch is CancellationError {
            restorePresentationIfCurrent(identity, stablePresentation)
            return false
        } catch let error as DocumentLifecycleFailure {
            guard operationStillMatches(identity, requireRevision: true),
                  activeSaveOperation == identity else { return false }
            setFailure(error)
            return false
        } catch {
            guard operationStillMatches(identity, requireRevision: true),
                  activeSaveOperation == identity else { return false }
            setFailure(.ioFailure)
            return false
        }
    }

    @discardableResult
    func requestRevert() async -> DocumentTransitionResult {
        guard let fileURL else { return .cancelled }
        let previousProjectID = project.projectID
        switch await authorize(.revertToSaved) {
        case .cancelled: return .cancelled
        case .failed(let error): return .failed(error)
        case .proceed(let discarding):
            await beginDocumentBoundary()
            let result = await loadAndAdopt(fileURL, intent: .revert)
            if result == .completed, discarding { await removeRecovery(for: previousProjectID) }
            return result
        }
    }

    func noteCancellation() { /* Native panel cancellation is intentionally state-neutral. */ }

    @discardableResult
    func requestRestoreRecovery() async -> DocumentTransitionResult {
        guard let candidate = recoveryCandidate else { return .cancelled }
        let previousProjectID = project.projectID
        switch await authorize(.restoreRecovery) {
        case .cancelled: return .cancelled
        case .failed(let error): return .failed(error)
        case .proceed(let discarding):
            await beginDocumentBoundary()
            guard recoveryCandidate == candidate else { return .cancelled }
            installRecovery(candidate)
            if discarding, previousProjectID != candidate.package.projectID {
                await removeRecovery(for: previousProjectID)
            }
            return .completed
        }
    }

    private func installRecovery(_ candidate: RecoveryCandidate) {
        observing = true
        try? session.establishBaseline(candidate.package.document)
        switch candidate.history {
        case .restored(let snapshot):
            do { try session.installValidatedHistory(snapshot); historyNotice = nil }
            catch { try? session.establishBaseline(candidate.package.document); historyNotice = PersistedHistoryError.inverseMismatch.localizedDescription }
        case .cleanBaseline(let reason): historyNotice = reason.localizedDescription
        }
        observing = false
        project = candidate.package
        fileURL = candidate.durableURL
        if candidate.durableURL == nil { durableFingerprint = nil; displayName = "Untitled" }
        recoveryCandidate = nil; failure = nil; phase = .recovered; hasUnsavedChanges = true
        transitionFailure = nil
    }

    func discardRecovery() async {
        guard let candidate = recoveryCandidate else { return }
        let identity = makeOperation(
            intent: .discardRecovery,
            destination: .file(candidate.url, kind: .recovery),
            documentID: candidate.package.document.id,
            projectID: candidate.package.projectID,
            revision: candidate.package.document.revision
        )
        activeRecoveryOperation = identity
        do {
            try await backend.removeRecovery(
                candidate.url,
                projectID: candidate.package.projectID,
                expected: candidate.fingerprint,
                identity: identity
            )
            guard recoveryOperationStillMatches(identity, candidate: candidate) else { return }
            recoveryCandidate = nil; failure = nil; phase = .clean; hasUnsavedChanges = false
            activeRecoveryOperation = nil
        } catch is CancellationError {
            finishRecoveryOperation(identity)
            return
        } catch let error as DocumentLifecycleFailure {
            guard recoveryOperationStillMatches(identity, candidate: candidate) else { return }
            activeRecoveryOperation = nil
            setFailure(error)
        } catch {
            guard recoveryOperationStillMatches(identity, candidate: candidate) else { return }
            activeRecoveryOperation = nil
            setFailure(.recoveryDeletionFailed)
        }
    }

    func consumeCloseAuthorization() -> Bool {
        guard allowNextClose else { return false }
        allowNextClose = false
        return true
    }

    @discardableResult
    func requestCloseTransition() async -> DocumentTransitionResult {
        switch await authorize(.closeWindow) {
        case .cancelled: return .cancelled
        case .failed(let error): return .failed(error)
        case .proceed(let discarding):
            await beginDocumentBoundary()
            if discarding { await removeRecovery(for: project.projectID) }
            return .completed
        }
    }

    func closeAfterAuthorization(_ window: NSWindow) {
        allowNextClose = true
        window.performClose(nil)
    }

    private func documentDidChange(_ document: CanonicalDocument) {
        guard !observing else { return }
        phase = .modified; failure = nil; hasUnsavedChanges = true
        scheduleAutosave(for: document)
    }

    private func scheduleAutosave(for document: CanonicalDocument) {
        autosaveTask?.cancel()
        let identity = makeOperation(
            intent: .autosave,
            destination: .file(recoveryURL(for: project.projectID), kind: .recovery),
            documentID: document.id,
            revision: document.revision
        )
        autosaveOperation = identity
        autosaveTask = Task { @MainActor [weak self, autosaveDebouncer] in
            do {
                try await autosaveDebouncer.wait()
                try Task.checkCancellation()
                await self?.writeRecovery(identity)
            } catch {
                // Cancellation is the expected coalescing and transition path.
            }
            self?.finishAutosave(identity)
        }
    }

    private func writeRecovery(_ identity: LifecycleOperationIdentity) async {
        if let saveTask = activeSaveTask {
            _ = await saveTask.value
        }
        guard operationStillMatches(identity, requireRevision: true),
              autosaveOperation == identity,
              !Task.isCancelled else { return }
        let snapshot = session.document
        let historySnapshot = session.historySnapshot()
        let package = ProjectPackage(projectID: project.projectID, createdAt: project.createdAt,
                                     modifiedAt: ProjectTimestamp(date: clock.now()), document: snapshot,
                                     optionalMembers: project.optionalMembers, compatibility: project.compatibility)
        phase = .autosaving
        do {
            try await backend.prepareRecoveryDirectory(recoveryDirectory, identity: identity)
            try Task.checkCancellation()
            _ = try await backend.write(
                package,
                history: historySnapshot,
                recoveryBoundary: project.document.revision,
                to: recoveryURL(for: project.projectID),
                expected: nil,
                identity: identity
            )
            guard operationStillMatches(identity, requireRevision: true),
                  autosaveOperation == identity,
                  !Task.isCancelled else { return }
            phase = .modified
        } catch is CancellationError {
            return
        } catch let error as DocumentLifecycleFailure {
            guard operationStillMatches(identity, requireRevision: true),
                  autosaveOperation == identity else { return }
            setFailure(error)
        } catch {
            guard operationStillMatches(identity, requireRevision: true),
                  autosaveOperation == identity else { return }
            setFailure(.ioFailure)
        }
    }

    private func findRecoveryCandidate() async {
        guard let fileURL else { return }
        let recoveryURL = recoveryURL(for: project.projectID)
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { recoveryCandidate = nil; return }
        let identity = makeOperation(
            intent: .discoverRecovery,
            destination: .file(recoveryURL, kind: .recovery)
        )
        activeRecoveryOperation = identity
        do {
            let loaded = try await backend.readRecovery(
                from: recoveryURL,
                expectedProjectID: project.projectID,
                identity: identity
            )
            guard recoveryOperationStillMatches(identity, requireRevision: true) else { return }
            guard loaded.package.projectID == project.projectID,
                  loaded.package.document.revision > project.document.revision else {
                if loaded.package.projectID == project.projectID {
                    try? await backend.removeRecovery(
                        recoveryURL,
                        projectID: project.projectID,
                        expected: loaded.fingerprint,
                        identity: identity
                    )
                } else {
                    setFailure(.recoveryArtifactConflict)
                }
                recoveryCandidate = nil
                activeRecoveryOperation = nil
                return
            }
            recoveryCandidate = RecoveryCandidate(
                package: loaded.package,
                url: recoveryURL,
                durableURL: fileURL,
                history: loaded.history,
                fingerprint: loaded.fingerprint
            )
            activeRecoveryOperation = nil
        } catch is CancellationError {
            finishRecoveryOperation(identity)
            return
        } catch let error as DocumentLifecycleFailure {
            guard recoveryOperationStillMatches(identity, requireRevision: true) else { return }
            activeRecoveryOperation = nil
            recoveryCandidate = nil
            setFailure(error == .recoveryArtifactConflict ? error : .malformedRecovery)
        } catch {
            guard recoveryOperationStillMatches(identity, requireRevision: true) else { return }
            activeRecoveryOperation = nil
            recoveryCandidate = nil; setFailure(.malformedRecovery)
        }
    }

    func discoverUntitledRecoveryCandidate() async {
        guard fileURL == nil, !isModified else { return }
        let identity = makeOperation(
            intent: .discoverRecovery,
            destination: LifecycleDestinationIdentity(kind: .recovery, sanitizedToken: "recovery-directory")
        )
        activeRecoveryOperation = identity
        do {
            let urls = try await backend.recoveryURLs(in: recoveryDirectory, identity: identity)
            guard recoveryOperationStillMatches(identity, requireRevision: true) else { return }
            var candidates: [RecoveryCandidate] = []
            for url in urls {
                do {
                    let candidateIdentity = makeOperation(
                        intent: .discoverRecovery,
                        destination: .file(url, kind: .recovery)
                    )
                    let loaded = try await backend.readRecovery(from: url, identity: candidateIdentity)
                    guard recoveryOperationStillMatches(identity, requireRevision: true),
                          operationStillMatches(candidateIdentity, requireRevision: true) else { return }
                    guard loaded.package.document.revision > 0 else { continue }
                    candidates.append(RecoveryCandidate(
                        package: loaded.package,
                        url: url,
                        durableURL: nil,
                        history: loaded.history,
                        fingerprint: loaded.fingerprint
                    ))
                } catch {
                    continue
                }
            }
            guard recoveryOperationStillMatches(identity, requireRevision: true) else { return }
            recoveryCandidate = candidates.max {
                if $0.package.modifiedAt == $1.package.modifiedAt {
                    return $0.package.projectID.description < $1.package.projectID.description
                }
                return $0.package.modifiedAt < $1.package.modifiedAt
            }
            activeRecoveryOperation = nil
        } catch is CancellationError {
            finishRecoveryOperation(identity)
            return
        } catch {
            guard recoveryOperationStillMatches(identity, requireRevision: true) else { return }
            activeRecoveryOperation = nil
            setFailure(.malformedRecovery)
        }
    }

    func resolveUnsavedChanges(_ decision: UnsavedChangesDecision, promptID: UUID) {
        guard pendingUnsavedChangesPrompt?.id == promptID else { return }
        let continuation = pendingDecisionContinuation
        pendingDecisionContinuation = nil
        pendingUnsavedChangesPrompt = nil
        continuation?.resume(returning: decision)
    }

    private func authorize(_ transition: DestructiveDocumentTransition) async -> ReplacementAuthorization {
        guard isModified else { return .proceed(discardingChanges: false) }
        let originalPhase = phase
        let originalFailure = failure
        let decision = await requestUnsavedChangesDecision(for: transition)
        switch decision {
        case .cancel:
            return .cancelled
        case .discard:
            return .proceed(discardingChanges: true)
        case .save:
            let target: URL?
            if let fileURL { target = fileURL }
            else { target = saveDestinationProvider(suggestedSaveFilename) }
            guard let target else { return .cancelled }
            let saved = await save(to: fileURL == nil ? target : nil)
            guard saved, !isModified else {
                let saveFailure = saved ? DocumentLifecycleFailure.conflict : (failure ?? .ioFailure)
                phase = originalPhase
                failure = originalFailure
                transitionFailure = saveFailure
                return .failed(saveFailure)
            }
            return .proceed(discardingChanges: false)
        }
    }

    private func beginDocumentBoundary() async {
        lifecycleEpoch = LifecycleEpoch()

        let pendingAutosave = autosaveTask
        let pendingSave = activeSaveTask
        let pendingRead = activeReadTask
        autosaveTask = nil
        autosaveOperation = nil
        activeSaveTask = nil
        activeSaveOperation = nil
        activeReadTask = nil
        activeReadOperation = nil
        activeRecoveryOperation = nil

        pendingAutosave?.cancel()
        pendingSave?.cancel()
        pendingRead?.cancel()
        if let pendingAutosave { await pendingAutosave.value }
        if let pendingSave { _ = await pendingSave.value }
        if let pendingRead { _ = await pendingRead.value }

        if phase == .saving || phase == .autosaving {
            phase = hasUnsavedChanges ? .modified : .clean
        }
    }

    private func cancelAndDrainAutosave() async {
        guard let pendingAutosave = autosaveTask else { return }
        autosaveTask = nil
        autosaveOperation = nil
        pendingAutosave.cancel()
        await pendingAutosave.value
    }

    private func finishAutosave(_ identity: LifecycleOperationIdentity) {
        guard autosaveOperation == identity else { return }
        autosaveTask = nil
        autosaveOperation = nil
    }

    private func finishRecoveryOperation(_ identity: LifecycleOperationIdentity) {
        guard activeRecoveryOperation == identity else { return }
        activeRecoveryOperation = nil
    }

    private func makeOperation(
        intent: LifecycleOperationIntent,
        destination: LifecycleDestinationIdentity,
        documentID: DocumentID? = nil,
        projectID: ProjectID? = nil,
        revision: UInt64? = nil
    ) -> LifecycleOperationIdentity {
        LifecycleOperationIdentity(
            id: LifecycleOperationID(),
            epoch: lifecycleEpoch,
            documentID: documentID ?? session.document.id,
            projectID: projectID ?? project.projectID,
            revision: revision ?? session.document.revision,
            destination: destination,
            intent: intent
        )
    }

    private func operationStillMatches(
        _ identity: LifecycleOperationIdentity,
        requireRevision: Bool
    ) -> Bool {
        identity.epoch == lifecycleEpoch
            && identity.documentID == session.document.id
            && identity.projectID == project.projectID
            && (!requireRevision || identity.revision == session.document.revision)
    }

    private func recoveryOperationStillMatches(
        _ identity: LifecycleOperationIdentity,
        requireRevision: Bool
    ) -> Bool {
        activeRecoveryOperation == identity
            && operationStillMatches(identity, requireRevision: requireRevision)
    }

    private func recoveryOperationStillMatches(
        _ identity: LifecycleOperationIdentity,
        candidate: RecoveryCandidate
    ) -> Bool {
        activeRecoveryOperation == identity
            && identity.epoch == lifecycleEpoch
            && identity.documentID == candidate.package.document.id
            && identity.projectID == candidate.package.projectID
            && identity.revision == candidate.package.document.revision
            && identity.destination == .file(candidate.url, kind: .recovery)
            && recoveryCandidate == candidate
    }

    private func restorePresentationIfCurrent(
        _ identity: LifecycleOperationIdentity,
        _ presentation: StableSavePresentation
    ) {
        guard operationStillMatches(identity, requireRevision: true),
              activeSaveOperation == identity else { return }
        phase = presentation.phase
        failure = presentation.failure
    }

    private func requestUnsavedChangesDecision(
        for transition: DestructiveDocumentTransition
    ) async -> UnsavedChangesDecision {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let prior = pendingDecisionContinuation { prior.resume(returning: .cancel) }
                pendingDecisionContinuation = continuation
                pendingUnsavedChangesPrompt = UnsavedChangesPrompt(
                    id: id,
                    transition: transition,
                    documentName: displayName
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolveUnsavedChanges(.cancel, promptID: id)
            }
        }
    }

    private var suggestedSaveFilename: String {
        displayName == "Untitled" ? "Untitled.siteforge" : "\(displayName).siteforge"
    }

    private func recoveryURL(for projectID: ProjectID) -> URL {
        DocumentLifecycleBackend.recoveryURL(for: projectID, in: recoveryDirectory)
    }

    private func removeRecovery(for projectID: ProjectID) async {
        let url = recoveryURL(for: projectID)
        let identity = makeOperation(
            intent: .discardRecovery,
            destination: .file(url, kind: .recovery),
            projectID: projectID
        )
        try? await backend.removeRecovery(
            url,
            projectID: projectID,
            identity: identity
        )
    }

    private func setFailure(_ error: DocumentLifecycleFailure) {
        failure = error
        phase = error == .externalModification || error == .conflict ? .conflicted : .failed
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.siteForgeProject]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Open a validated SiteForge project."
        panel.accessoryView = nil
        guard panel.runModal() == .OK, let url = panel.url else { noteCancellation(); return }
        Task { _ = await requestOpen(url) }
    }

    func presentSavePanel() {
        guard let url = saveDestinationProvider(suggestedSaveFilename) else { noteCancellation(); return }
        Task { _ = await save(to: url) }
    }
}
