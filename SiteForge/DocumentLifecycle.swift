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

enum LifecycleOperation: String, Sendable { case new, open, save, saveAs, revert, autosave, restore, discardRecovery }
enum LifecycleResult: String, Sendable { case success, failure, cancelled, stale }
struct LifecycleDiagnostic: Equatable, Sendable {
    let requirementIDs: [String]
    let operation: LifecycleOperation
    let sanitizedProjectID: String?
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
    private var newestGeneration = 0
    private var fault: LifecycleBackendFault = .none
    private var delayNanoseconds: UInt64 = 0

    init(store: ProjectPackageStore = ProjectPackageStore(), diagnostics: DocumentLifecycleDiagnostics = DocumentLifecycleDiagnostics(), historyStore: PersistedHistoryStore = PersistedHistoryStore()) {
        self.store = store
        self.diagnostics = diagnostics
        self.historyStore = historyStore
    }

    func configureForTesting(fault: LifecycleBackendFault = .none, delayNanoseconds: UInt64 = 0) {
        self.fault = fault
        self.delayNanoseconds = delayNanoseconds
    }

    func diagnosticRecords() async -> [LifecycleDiagnostic] { await diagnostics.records }
    func historyDiagnosticRecords() async -> [HistoryDiagnosticRecord] { await historyStore.diagnosticRecords() }

    func read(
        from url: URL,
        operation: LifecycleOperation = .open,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async throws -> LoadedProject {
        let start = ContinuousClock.now
        do {
            try throwFault()
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
            await record(operation, read.package.projectID, start, .success, nil)
            return LoadedProject(package: read.package, fingerprint: read.file.fingerprint, history: history)
        } catch is CancellationError {
            await record(operation, nil, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure = Self.map(error)
            await record(operation, nil, start, .failure, failure)
            throw failure
        }
    }

    func readRecovery(
        from url: URL,
        expectedProjectID: ProjectID? = nil
    ) async throws -> LoadedProject {
        let start = ContinuousClock.now
        do {
            try throwFault()
            try Task.checkCancellation()
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            let read = try await store.readOwnedRecoverySnapshot(
                from: url,
                expectedProjectID: expectedProjectID
            )
            try Task.checkCancellation()
            let history = await historyStore.load(from: read.package)
            try Task.checkCancellation()
            await record(.open, read.package.projectID, start, .success, nil)
            return LoadedProject(package: read.package, fingerprint: read.file.fingerprint, history: history)
        } catch is CancellationError {
            await record(.open, nil, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure = Self.map(error)
            await record(.open, nil, start, .failure, failure)
            throw failure
        }
    }

    func write(_ package: ProjectPackage, history: PersistedHistorySnapshot, recoveryBoundary: UInt64? = nil, to url: URL, expected: PackageFingerprint?, generation: Int, operation: LifecycleOperation) async throws -> PackageFingerprint {
        let start = ContinuousClock.now
        newestGeneration = max(newestGeneration, generation)
        do {
            try throwFault()
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            guard generation >= newestGeneration else { throw DocumentLifecycleFailure.conflict }
            let historySnapshot: PersistedHistorySnapshot
            if let recoveryBoundary {
                historySnapshot = await historyStore.recoverySnapshot(history, durableRevision: recoveryBoundary)
            } else {
                historySnapshot = history
            }
            let packageWithHistory = try await historyStore.package(package, with: historySnapshot)
            let policy: ProjectPackageArtifactPolicy = operation == .autosave ? .recovery(package.projectID) : .durable
            let replacementExpectation: PackageFingerprint?
            if operation == .autosave {
                replacementExpectation = try await ownedRecoveryExpectation(at: url, projectID: package.projectID)
            } else {
                replacementExpectation = expected
            }
            let fingerprint = try await store.write(
                packageWithHistory,
                to: url,
                expected: replacementExpectation,
                policy: policy
            )
            await record(operation, package.projectID, start, .success, nil)
            return fingerprint
        } catch {
            let failure = Self.map(error)
            await record(operation, package.projectID, start, failure == .conflict ? .stale : .failure, failure)
            throw failure
        }
    }

    func removeRecovery(
        _ url: URL,
        projectID: ProjectID,
        expected: PackageFingerprint? = nil
    ) async throws {
        do {
            try await store.removeOwnedRecovery(at: url, projectID: projectID, expected: expected)
        } catch let error as ProjectPackageError where error == .packageUnavailable {
            return
        } catch {
            throw Self.map(error)
        }
    }

    func prepareRecoveryDirectory(_ directory: URL) async throws {
        do {
            try await store.prepareRecoveryDirectory(directory)
        } catch {
            throw Self.map(error)
        }
    }

    func recoveryURLs(in directory: URL) async throws -> [URL] {
        do {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            try await store.validateRecoveryDirectory(directory)
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "siteforge-recovery" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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

    private func record(_ operation: LifecycleOperation, _ projectID: ProjectID?, _ start: ContinuousClock.Instant, _ result: LifecycleResult, _ failure: DocumentLifecycleFailure?) async {
        let duration = start.duration(to: .now).components
        let nanos = UInt64(max(0, duration.seconds)) * 1_000_000_000 + UInt64(max(0, duration.attoseconds / 1_000_000_000))
        let sanitized = projectID.map { id in
            "project-" + SHA256.hash(data: Data(id.description.utf8)).prefix(5).map { String(format: "%02x", $0) }.joined()
        }
        await diagnostics.append(LifecycleDiagnostic(
            requirementIDs: ["SF-0301-008", "SF-0306-008", "SF-1504-008"], operation: operation,
            sanitizedProjectID: sanitized, durationNanoseconds: nanos, result: result,
            failure: failure.map { String(describing: $0) }
        ))
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
}

private enum ReplacementAuthorization: Equatable {
    case proceed(discardingChanges: Bool)
    case cancelled
    case failed(DocumentLifecycleFailure)
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
    private var generation = 0
    private var autosaveTask: Task<Void, Never>?
    private var observing = false
    private var hasUnsavedChanges = false
    private var observation: AnyCancellable?
    private var allowNextClose = false
    private var pendingDecisionContinuation: CheckedContinuation<UnsavedChangesDecision, Never>?

    init(
        session: DocumentSession,
        backend: DocumentLifecycleBackend = DocumentLifecycleBackend(),
        recoveryDirectory: URL = DocumentLifecycleController.defaultRecoveryDirectory,
        saveDestinationProvider: @escaping SaveDestinationProvider = DocumentLifecycleController.nativeSaveDestination
    ) {
        self.session = session
        self.backend = backend
        self.recoveryDirectory = recoveryDirectory
        self.saveDestinationProvider = saveDestinationProvider
        let now = ProjectTimestamp(date: Date())
        project = ProjectPackage(createdAt: now, document: session.document)
        observation = session.$document.dropFirst().sink { [weak self] _ in self?.documentDidChange() }
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
            recoveryCandidate: recoveryCandidate
        )
    }

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
            establishNewDocument()
            if discarding { await removeRecovery(for: previousProjectID) }
            return .completed
        }
    }

    private func establishNewDocument() {
        autosaveTask?.cancel()
        let document = ProjectCreation.blank()
        observing = true
        try? session.establishBaseline(document)
        observing = false
        let now = ProjectTimestamp(date: Date())
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
            let result = await loadAndAdopt(url, progress: progress)
            if result == .completed, discarding { await removeRecovery(for: previousProjectID) }
            return result
        }
    }

    private func loadAndAdopt(
        _ url: URL,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async -> DocumentTransitionResult {
        do {
            let loaded = try await backend.read(from: url, progress: progress)
            try Task.checkCancellation()
            observing = true
            try session.establishBaseline(loaded.package.document)
            switch loaded.history {
            case .restored(let snapshot): try session.installValidatedHistory(snapshot); historyNotice = nil
            case .cleanBaseline(let reason): historyNotice = reason.localizedDescription
            }
            observing = false
            project = loaded.package; fileURL = url; durableFingerprint = loaded.fingerprint
            displayName = url.deletingPathExtension().lastPathComponent
            failure = nil; phase = .clean; hasUnsavedChanges = false
            await progress?(.checkingRecovery)
            await findRecoveryCandidate()
            transitionFailure = nil
            return .completed
        } catch is CancellationError {
            observing = false
            return .cancelled
        } catch let error as DocumentLifecycleFailure {
            observing = false
            setFailure(error)
            return .failed(error)
        } catch {
            observing = false
            setFailure(.ioFailure)
            return .failed(.ioFailure)
        }
    }

    @discardableResult func save(to destination: URL? = nil) async -> Bool {
        guard let target = destination ?? fileURL else { return false }
        generation += 1
        let currentGeneration = generation
        let snapshot = session.document
        let historySnapshot = session.historySnapshot()
        let now = ProjectTimestamp(date: Date())
        let package = ProjectPackage(projectID: project.projectID, createdAt: project.createdAt, modifiedAt: now,
                                     document: snapshot, optionalMembers: project.optionalMembers, compatibility: project.compatibility)
        phase = .saving; failure = nil
        do {
            let expected = (destination == nil || target == fileURL) ? durableFingerprint : nil
            let fingerprint = try await backend.write(package, history: historySnapshot, to: target, expected: expected, generation: currentGeneration,
                                                      operation: destination == nil ? .save : .saveAs)
            guard currentGeneration == generation else { return false }
            project = package; fileURL = target; durableFingerprint = fingerprint
            displayName = target.deletingPathExtension().lastPathComponent
            phase = session.document.revision == snapshot.revision ? .clean : .modified
            hasUnsavedChanges = phase == .modified
            if phase == .clean { await removeRecovery(for: package.projectID) }
            transitionFailure = nil
            return true
        } catch let error as DocumentLifecycleFailure { setFailure(error); return false }
        catch { setFailure(.ioFailure); return false }
    }

    @discardableResult
    func requestRevert() async -> DocumentTransitionResult {
        guard let fileURL else { return .cancelled }
        let previousProjectID = project.projectID
        switch await authorize(.revertToSaved) {
        case .cancelled: return .cancelled
        case .failed(let error): return .failed(error)
        case .proceed(let discarding):
            let result = await loadAndAdopt(fileURL)
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
        do {
            try await backend.removeRecovery(
                candidate.url,
                projectID: candidate.package.projectID,
                expected: candidate.fingerprint
            )
            recoveryCandidate = nil; failure = nil; phase = .clean; hasUnsavedChanges = false
        } catch let error as DocumentLifecycleFailure {
            setFailure(error)
        } catch {
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
            if discarding { await removeRecovery(for: project.projectID) }
            return .completed
        }
    }

    func closeAfterAuthorization(_ window: NSWindow) {
        allowNextClose = true
        window.performClose(nil)
    }

    private func documentDidChange() {
        guard !observing else { return }
        phase = .modified; failure = nil; hasUnsavedChanges = true
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.writeRecovery()
        }
    }

    private func writeRecovery() async {
        generation += 1
        let currentGeneration = generation
        let snapshot = session.document
        let historySnapshot = session.historySnapshot()
        let package = ProjectPackage(projectID: project.projectID, createdAt: project.createdAt,
                                     modifiedAt: ProjectTimestamp(date: Date()), document: snapshot,
                                     optionalMembers: project.optionalMembers, compatibility: project.compatibility)
        phase = .autosaving
        do {
            try await backend.prepareRecoveryDirectory(recoveryDirectory)
            _ = try await backend.write(package, history: historySnapshot, recoveryBoundary: project.document.revision,
                                        to: recoveryURL(for: project.projectID), expected: nil,
                                        generation: currentGeneration, operation: .autosave)
            if currentGeneration == generation { phase = .modified }
        } catch let error as DocumentLifecycleFailure { setFailure(error) }
        catch { setFailure(.ioFailure) }
    }

    private func findRecoveryCandidate() async {
        guard let fileURL else { return }
        let recoveryURL = recoveryURL(for: project.projectID)
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { recoveryCandidate = nil; return }
        do {
            let loaded = try await backend.readRecovery(
                from: recoveryURL,
                expectedProjectID: project.projectID
            )
            guard loaded.package.projectID == project.projectID,
                  loaded.package.document.revision > project.document.revision else {
                if loaded.package.projectID == project.projectID {
                    try? await backend.removeRecovery(
                        recoveryURL,
                        projectID: project.projectID,
                        expected: loaded.fingerprint
                    )
                } else {
                    setFailure(.recoveryArtifactConflict)
                }
                recoveryCandidate = nil; return
            }
            recoveryCandidate = RecoveryCandidate(
                package: loaded.package,
                url: recoveryURL,
                durableURL: fileURL,
                history: loaded.history,
                fingerprint: loaded.fingerprint
            )
        } catch let error as DocumentLifecycleFailure {
            recoveryCandidate = nil
            setFailure(error == .recoveryArtifactConflict ? error : .malformedRecovery)
        } catch {
            recoveryCandidate = nil; setFailure(.malformedRecovery)
        }
    }

    func discoverUntitledRecoveryCandidate() async {
        guard fileURL == nil, !isModified else { return }
        do {
            let urls = try await backend.recoveryURLs(in: recoveryDirectory)
            var candidates: [RecoveryCandidate] = []
            for url in urls {
                do {
                    let loaded = try await backend.readRecovery(from: url)
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
            recoveryCandidate = candidates.max {
                if $0.package.modifiedAt == $1.package.modifiedAt {
                    return $0.package.projectID.description < $1.package.projectID.description
                }
                return $0.package.modifiedAt < $1.package.modifiedAt
            }
        } catch {
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
            guard saved else {
                let saveFailure = failure ?? .ioFailure
                phase = originalPhase
                failure = originalFailure
                transitionFailure = saveFailure
                return .failed(saveFailure)
            }
            return .proceed(discardingChanges: false)
        }
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
        try? await backend.removeRecovery(recoveryURL(for: projectID), projectID: projectID)
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
