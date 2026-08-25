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
        // A lifecycle operation owns the lexical URL selected before it
        // suspends. `standardizedFileURL` may re-spell macOS's `/var` ↔
        // `/private/var` system alias after file coordination, which would
        // make an otherwise identical operation appear to target a different
        // destination. Do not resolve or normalize symlinks for an operation
        // identity; descriptor-bound package I/O supplies the actual file
        // identity proof separately.
        return LifecycleDestinationIdentity(
            kind: kind,
            sanitizedToken: DiagnosticStableIdentifier.sanitize(
                url.path,
                domain: .lifecycleDestination,
                kind: "destination"
            )
        )
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

/// A recovery-directory entry is trusted only after its canonical filename
/// supplies the project identity expected by the descriptor-bound read.  The
/// public URL alone is never an ownership capability.
struct RecoveryArtifactReference: Equatable, Sendable {
    let url: URL
    let expectedProjectID: ProjectID
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

/// A small, lock-protected handoff used only at destructive lifecycle seams.
/// The controller is main-actor isolated, while the package backend performs
/// I/O off that actor. Claiming and checking the typed attempt synchronously
/// prevents a transition that has already been superseded at a testable
/// pre-commit checkpoint from entering identity-bound recovery retirement.
/// It is not a substitute for filesystem identity checks: macOS does not
/// offer an expected-inode rename/unlink primitive for the final syscall.
final class LifecycleTransitionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeAttempt: LifecycleOperationID?

    func claim(_ attempt: LifecycleOperationID) {
        lock.lock()
        activeAttempt = attempt
        lock.unlock()
    }

    func finish(_ attempt: LifecycleOperationID) {
        lock.lock()
        if activeAttempt == attempt { activeAttempt = nil }
        lock.unlock()
    }

    func isCurrent(_ attempt: LifecycleOperationID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeAttempt == attempt
    }

    /// The final rename is a transition linearization point. Hold the gate
    /// only for that syscall, never across awaitable package preparation, so a
    /// newer transition either supersedes it before the commit or starts after
    /// the committed retirement has completed.
    func commitIfCurrent(
        _ attempt: LifecycleOperationID,
        operation: @Sendable () throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard activeAttempt == attempt, !Task.isCancelled else {
            throw CancellationError()
        }
        try operation()
    }
}

private final class LifecycleTransitionCommitAuthorizer: ProjectPackageConditionalCommitAuthorizing, @unchecked Sendable {
    private let gate: LifecycleTransitionGate
    private let attempt: LifecycleOperationID

    init(gate: LifecycleTransitionGate, attempt: LifecycleOperationID) {
        self.gate = gate
        self.attempt = attempt
    }

    func commitIfAuthorized(_ operation: @Sendable () throws -> Void) throws {
        try gate.commitIfCurrent(attempt, operation: operation)
    }
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
    private var buffer: BoundedDiagnosticBuffer<LifecycleDiagnostic>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    var records: [LifecycleDiagnostic] { buffer.snapshot() }
    func append(_ record: LifecycleDiagnostic) { buffer.append(record) }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

struct LoadedProject: Sendable {
    let package: ProjectPackage
    let fingerprint: PackageFingerprint
    let history: PersistedHistoryLoadResult
    let sourceURL: URL
}

struct CompletedPackageWrite: Sendable {
    let fingerprint: PackageFingerprint
    let destinationURL: URL
}

enum LifecycleBackendFault: Sendable { case none, permission, staleScope, io }

actor DocumentLifecycleBackend {
    private let store: ProjectPackageStore
    private let diagnostics: DocumentLifecycleDiagnostics
    private let historyStore: PersistedHistoryStore
    private let fileAccess: FileAccessService
    private let observer: (any LifecycleBackendObserving)?
    private var fault: LifecycleBackendFault = .none
    private var delayNanoseconds: UInt64 = 0

    init(
        store: ProjectPackageStore = ProjectPackageStore(),
        diagnostics: DocumentLifecycleDiagnostics = DocumentLifecycleDiagnostics(),
        historyStore: PersistedHistoryStore = PersistedHistoryStore(),
        fileAccess: FileAccessService = FileAccessService(),
        observer: (any LifecycleBackendObserving)? = nil
    ) {
        self.store = store
        self.diagnostics = diagnostics
        self.historyStore = historyStore
        self.fileAccess = fileAccess
        self.observer = observer
    }

    func configureForTesting(fault: LifecycleBackendFault = .none, delayNanoseconds: UInt64 = 0) {
        self.fault = fault
        self.delayNanoseconds = delayNanoseconds
    }

    func diagnosticRecords() async -> [LifecycleDiagnostic] { await diagnostics.records }
    func historyDiagnosticRecords() async -> [HistoryDiagnosticRecord] { await historyStore.diagnosticRecords() }
    func fileAccessDiagnosticRecords() async -> [FileAccessDiagnostic] { await fileAccess.diagnosticRecords() }

    func recordEvent(
        _ identity: LifecycleOperationIdentity,
        result: LifecycleResult,
        failure: DocumentLifecycleFailure? = nil
    ) async {
        await record(identity, nil, .now, result, failure)
    }

    func authorizeUserSelection(_ url: URL) async throws {
        do { try await fileAccess.authorizeUserSelection(url) }
        catch { throw Self.map(error) }
    }

    func recordRelocation(from oldURL: URL, to newURL: URL) async throws {
        do { try await fileAccess.recordRelocation(from: oldURL, to: newURL) }
        catch { throw Self.map(error) }
    }

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
            let accessed = try await fileAccess.withAccess(
                to: url,
                intent: identity.intent == .revert ? .revert : .open
            ) { [store] coordinatedURL in
                let read = try await store.readSnapshot(from: coordinatedURL)
                return (coordinatedURL, read)
            }
            let (sourceURL, read) = accessed
            try Task.checkCancellation()
            await progress?(.validatingCanonicalDocument)
            try Task.checkCancellation()
            await progress?(.validatingHistory)
            let history = try await historyStore.load(from: read.package)
            try Task.checkCancellation()
            await progress?(.preparingWorkspace)
            await observer?.reached(.afterRead, operation: identity)
            try Task.checkCancellation()
            await record(identity, read.package.projectID, start, .success, nil)
            return LoadedProject(
                package: read.package,
                fingerprint: read.file.fingerprint,
                history: history,
                sourceURL: sourceURL
            )
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
            let accessed = try await fileAccess.withAccess(to: url, intent: .recovery) { [store] coordinatedURL in
                let read = try await store.readOwnedRecoverySnapshot(
                    from: coordinatedURL,
                    expectedProjectID: expectedProjectID
                )
                return (coordinatedURL, read)
            }
            let (sourceURL, read) = accessed
            try Task.checkCancellation()
            let history = try await historyStore.load(from: read.package)
            try Task.checkCancellation()
            await observer?.reached(.afterRead, operation: identity)
            try Task.checkCancellation()
            await record(identity, read.package.projectID, start, .success, nil)
            return LoadedProject(
                package: read.package,
                fingerprint: read.file.fingerprint,
                history: history,
                sourceURL: sourceURL
            )
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
    ) async throws -> CompletedPackageWrite {
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
            // The controller captured this fingerprint from the exact validated
            // recovery snapshot it owns. Re-reading the path here would turn a
            // same-project collision into an implicit authorization to replace
            // someone else's artifact.
            let replacementExpectation = expected
            try Task.checkCancellation()
            await observer?.reached(.beforeFilesystemWrite, operation: identity)
            try Task.checkCancellation()
            let accessIntent: FileAccessIntent = identity.intent == .autosave ? .autosave : .save
            let completed = try await fileAccess.withAccess(to: url, intent: accessIntent) { [store] coordinatedURL in
                let fingerprint = try await store.write(
                    packageWithHistory,
                    to: coordinatedURL,
                    expected: replacementExpectation,
                    policy: policy
                )
                return CompletedPackageWrite(fingerprint: fingerprint, destinationURL: coordinatedURL)
            }
            await observer?.reached(.afterFilesystemWrite, operation: identity)
            await record(identity, package.projectID, start, .success, nil)
            return completed
        } catch is CancellationError {
            await record(identity, package.projectID, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure: DocumentLifecycleFailure
            if identity.intent == .autosave,
               (error as? ProjectPackageError) == .fileIdentityChanged {
                // A recovery write never treats an unexpected existing name as
                // permission to replace it. Classify a fresh, coordinated
                // read only after the failed conditional write so the UI can
                // distinguish a foreign artifact from malformed bytes without
                // using that read as overwrite authorization.
                failure = await classifyRecoveryWriteConflict(at: url, projectID: package.projectID)
            } else {
                failure = Self.map(error)
            }
            await record(identity, package.projectID, start, failure == .conflict ? .stale : .failure, failure)
            throw failure
        }
    }

    private func classifyRecoveryWriteConflict(
        at url: URL,
        projectID: ProjectID
    ) async -> DocumentLifecycleFailure {
        do {
            _ = try await fileAccess.withAccess(to: url, intent: .autosave) { [store] coordinatedURL in
                try await store.readOwnedRecoverySnapshot(
                    from: coordinatedURL,
                    expectedProjectID: projectID
                )
            }
            return .recoveryArtifactConflict
        } catch let error as ProjectPackageError {
            switch error {
            case .unsafeRecoveryArtifact, .fileIdentityChanged:
                return .recoveryArtifactConflict
            default:
                return Self.map(error)
            }
        } catch {
            return Self.map(error)
        }
    }

    func removeRecovery(
        _ url: URL,
        projectID: ProjectID,
        expected: PackageFingerprint? = nil,
        transitionGate: LifecycleTransitionGate? = nil,
        transitionAttempt: LifecycleOperationID? = nil,
        identity: LifecycleOperationIdentity
    ) async throws {
        let start = ContinuousClock.now
        do {
            try Task.checkCancellation()
            await observer?.reached(.beforeRecoveryDeletion, operation: identity)
            try Task.checkCancellation()
            if let transitionGate, let transitionAttempt,
               !transitionGate.isCurrent(transitionAttempt) {
                throw CancellationError()
            }
            let commitAuthorizer: (any ProjectPackageConditionalCommitAuthorizing)? = if let transitionGate, let transitionAttempt {
                LifecycleTransitionCommitAuthorizer(gate: transitionGate, attempt: transitionAttempt)
            } else {
                nil
            }
            try await fileAccess.withAccess(to: url, intent: .autosave) { [store] coordinatedURL in
                try await store.removeOwnedRecovery(
                    at: coordinatedURL,
                    projectID: projectID,
                    expected: expected,
                    commitAuthorizer: commitAuthorizer
                )
            }
            await observer?.reached(.afterRecoveryDeletion, operation: identity)
            await record(identity, projectID, start, .success, nil)
        } catch let error as ProjectPackageError where error == .packageUnavailable {
            guard expected == nil else {
                let failure = Self.map(error)
                await record(identity, projectID, start, .failure, failure)
                throw failure
            }
            await record(identity, projectID, start, .success, nil)
            return
        } catch is CancellationError {
            await record(identity, projectID, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure = Self.map(error)
            await record(identity, projectID, start, .failure, failure)
            throw failure
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

    func isRetiredRecoveryTombstone(
        at url: URL,
        projectID: ProjectID
    ) async throws -> Bool {
        do {
            return try await store.isRetiredRecoveryTombstone(at: url, projectID: projectID)
        } catch {
            throw Self.map(error)
        }
    }

    func recoveryURLs(
        in directory: URL,
        identity: LifecycleOperationIdentity
    ) async throws -> [RecoveryArtifactReference] {
        do {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            try await store.validateRecoveryDirectory(directory)
            try Task.checkCancellation()
            let discovered = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "siteforge-recovery" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            var artifacts: [RecoveryArtifactReference] = []
            for url in discovered {
                try Task.checkCancellation()
                // A canonical filename is the only safe source of the
                // expected project identity during untitled discovery.  A
                // malformed or noncanonical name is deliberately preserved
                // but cannot become a recovery candidate without an exact
                // filename-to-package identity binding.
                guard let expectedProjectID = Self.recoveryProjectID(from: url) else {
                    continue
                }
                if try await store.isRetiredRecoveryTombstone(
                    at: url,
                    projectID: expectedProjectID
                ) {
                    continue
                }
                artifacts.append(.init(url: url, expectedProjectID: expectedProjectID))
            }
            try Task.checkCancellation()
            return artifacts
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func recoveryURL(for projectID: ProjectID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(projectID.description).siteforge-recovery", isDirectory: false)
    }

    nonisolated private static func recoveryProjectID(from url: URL) -> ProjectID? {
        guard url.pathExtension == "siteforge-recovery" else { return nil }
        guard let projectID = ProjectID(uuidString: url.deletingPathExtension().lastPathComponent),
              url.lastPathComponent == "\(projectID.description).siteforge-recovery" else {
            return nil
        }
        return projectID
    }

    private func throwFault() throws {
        switch fault {
        case .none: break
        case .permission: throw DocumentLifecycleFailure.permissionDenied
        case .staleScope: throw DocumentLifecycleFailure.staleSecurityScope
        case .io: throw DocumentLifecycleFailure.ioFailure
        }
    }

    private nonisolated static func map(_ error: Error) -> DocumentLifecycleFailure {
        if let error = error as? DocumentLifecycleFailure { return error }
        if let error = error as? FileAccessFailure {
            switch error {
            case .permissionDenied: return .permissionDenied
            case .missingBookmark, .corruptBookmarkStore, .staleBookmarkRepairFailed:
                return .staleSecurityScope
            case .coordinationFailed: return .ioFailure
            }
        }
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
            sanitizedOperationID: DiagnosticStableIdentifier.sanitize(
                identity.id.rawValue.uuidString,
                domain: .lifecycleOperation,
                kind: "operation"
            ),
            sanitizedEpoch: DiagnosticStableIdentifier.sanitize(
                identity.epoch.rawValue.uuidString,
                domain: .lifecycleEpoch,
                kind: "epoch"
            ),
            sanitizedDocumentID: DiagnosticStableIdentifier.sanitize(
                identity.documentID.description,
                domain: .lifecycleDocument,
                kind: "document"
            ),
            sanitizedProjectID: DiagnosticStableIdentifier.sanitize(
                projectID.description,
                domain: .lifecycleProject,
                kind: "project"
            ),
            revision: identity.revision,
            destinationKind: identity.destination.kind,
            sanitizedDestination: identity.destination.sanitizedToken,
            durationNanoseconds: nanos,
            result: result,
            failure: failure.map(\.diagnosticCategory)
        ))
    }
}

extension DocumentLifecycleFailure {
    var diagnosticCategory: String {
        switch self {
        case .permissionDenied: "permission-denied"
        case .staleSecurityScope: "stale-security-scope"
        case .externalModification: "external-modification"
        case .conflict: "conflict"
        case .malformedPackage: "malformed-package"
        case .incompatiblePackage: "incompatible-package"
        case .malformedRecovery: "malformed-recovery"
        case .ioFailure: "io-failure"
        case .unsafeFileMetadata: "unsafe-file-metadata"
        case .recoveryArtifactConflict: "recovery-artifact-conflict"
        case .recoveryDeletionFailed: "recovery-deletion-failed"
        }
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

private struct OwnedRecoveryArtifact: Equatable, Sendable {
    let projectID: ProjectID
    let fingerprint: PackageFingerprint
    /// The revision that produced these bytes orders recovery ownership even
    /// when an older autosave completes after a newer task was scheduled.
    let revision: UInt64
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
    private let transitionGate = LifecycleTransitionGate()
    /// A standalone recovery retirement holds the same final-commit gate used
    /// by destructive transitions.  It is deliberately separate from the
    /// UI-operation identity: a new document transition must be able to
    /// invalidate the filesystem exchange before it adopts another document.
    private var activeRecoveryRetirementAttempt: LifecycleOperationID?
    /// A lifecycle epoch scopes background work once an adoption boundary is
    /// active. This separate attempt token also scopes the asynchronous
    /// authorization/cleanup period *before* that boundary. Without it, an
    /// older Open/Restore could resume after an awaited cleanup and adopt over
    /// a newer user-requested transition.
    private var activeTransitionAttempt: LifecycleOperationID?
    private var autosaveTask: Task<Void, Never>?
    private var activeSaveTask: Task<Bool, Never>?
    private var activeReadTask: Task<LifecycleReadOutcome, Never>?
    private var activeReadOperation: LifecycleOperationIdentity?
    private var activeSaveOperation: LifecycleOperationIdentity?
    private var autosaveOperation: LifecycleOperationIdentity?
    private var activeRecoveryOperation: LifecycleOperationIdentity?
    /// The exact recovery artifact written for the document currently hosted
    /// by this scene. It is the only artifact an autosave may conditionally
    /// replace or a durable save may retire.
    private var currentRecoveryArtifact: OwnedRecoveryArtifact?
    /// The separately presented recovery candidate. At launch this can belong
    /// to a different untitled project than the blank document in this scene,
    /// so it must never share the current document's ownership proof.
    private var candidateRecoveryArtifact: OwnedRecoveryArtifact?
    private var observing = false
    private var hasUnsavedChanges = false
    private var observation: AnyCancellable?
    private var allowNextClose = false
    private var pendingDecisionContinuation: CheckedContinuation<UnsavedChangesDecision, Never>?
    private var filePresenter: ProjectFilePresenter?

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
    var canRestoreRecovery: Bool {
        guard let recoveryCandidate else { return false }
        return fileURL == nil || recoveryCandidate.package.document.revision > project.document.revision
    }
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

    static var productionRecoveryDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SiteForge/Recovery", isDirectory: true)
    }

    static var defaultRecoveryDirectory: URL {
        DebugTestComposition.current().value(after: "-SiteForgeRecoveryDirectory")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? productionRecoveryDirectory
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
        let attempt = beginTransitionAttempt()
        defer { finishTransitionAttempt(attempt) }
        let previousProjectID = project.projectID
        switch await authorize(.newDocument) {
        case .cancelled:
            finishTransitionAttempt(attempt)
            return .cancelled
        case .failed(let error):
            guard transitionStillMatches(attempt) else { return .cancelled }
            finishTransitionAttempt(attempt)
            return .failed(error)
        case .proceed(let discarding):
            guard transitionStillMatches(attempt) else { return .cancelled }
            let previousRecovery = currentRecoveryArtifact
            if discarding, let previousRecovery, previousRecovery.projectID == previousProjectID,
               !(await removeRecovery(previousRecovery, transitionAttempt: attempt)) {
                guard transitionStillMatches(attempt) else { return .cancelled }
                finishTransitionAttempt(attempt)
                return .failed(failure ?? .recoveryDeletionFailed)
            }
            guard transitionStillMatches(attempt) else { return .cancelled }
            let boundary = await beginDocumentBoundary()
            guard transitionStillMatches(attempt), lifecycleEpoch == boundary else { return .cancelled }
            establishNewDocument()
            finishTransitionAttempt(attempt)
            return .completed
        }
    }

    private func establishNewDocument() {
        stopPresentingDurableFile()
        let document = ProjectCreation.blank()
        observing = true
        try? session.establishBaseline(document)
        observing = false
        let now = ProjectTimestamp(date: clock.now())
        project = ProjectPackage(createdAt: now, document: document)
        currentRecoveryArtifact = nil
        candidateRecoveryArtifact = nil
        fileURL = nil; durableFingerprint = nil; displayName = "Untitled"
        failure = nil; recoveryCandidate = nil; phase = .clean; hasUnsavedChanges = false
        historyNotice = nil; transitionFailure = nil
    }

    @discardableResult
    func requestOpen(
        _ url: URL,
        userSelected: Bool = false,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async -> DocumentTransitionResult {
        let attempt = beginTransitionAttempt()
        defer { finishTransitionAttempt(attempt) }
        switch await authorize(.openProject) {
        case .cancelled:
            finishTransitionAttempt(attempt)
            return .cancelled
        case .failed(let error):
            guard transitionStillMatches(attempt) else { return .cancelled }
            finishTransitionAttempt(attempt)
            return .failed(error)
        case .proceed(let discarding):
            guard transitionStillMatches(attempt) else { return .cancelled }
            if userSelected {
                do { try await backend.authorizeUserSelection(url) }
                catch let error as DocumentLifecycleFailure {
                    guard transitionStillMatches(attempt) else { return .cancelled }
                    setFailure(error)
                    finishTransitionAttempt(attempt)
                    return .failed(error)
                } catch {
                    guard transitionStillMatches(attempt) else { return .cancelled }
                    setFailure(.permissionDenied)
                    finishTransitionAttempt(attempt)
                    return .failed(.permissionDenied)
                }
            }
            guard transitionStillMatches(attempt) else { return .cancelled }
            // Do not delete a valid recovery until the incoming project has
            // been completely read and validated. A malformed Open must leave
            // the prior canonical document *and* its recovery artifact intact.
            let recoveryToDiscard = discarding ? currentRecoveryArtifact : nil
            let boundary = await beginDocumentBoundary()
            guard transitionStillMatches(attempt), lifecycleEpoch == boundary else { return .cancelled }
            let result = await loadAndAdopt(
                url,
                intent: .open,
                recoveryToDiscardAfterValidation: recoveryToDiscard,
                transitionAttempt: attempt,
                progress: progress
            )
            finishTransitionAttempt(attempt)
            return result
        }
    }

    private func loadAndAdopt(
        _ url: URL,
        intent: LifecycleOperationIntent,
        recoveryToDiscardAfterValidation: OwnedRecoveryArtifact? = nil,
        transitionAttempt: LifecycleOperationID,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async -> DocumentTransitionResult {
        guard transitionStillMatches(transitionAttempt) else { return .cancelled }
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
        guard activeReadOperation == identity, transitionStillMatches(transitionAttempt) else {
            // A newer boundary may already own the active read slot. Clear
            // only this operation's completed bookkeeping; never disturb the
            // newer operation's task or identity.
            if activeReadOperation == identity {
                activeReadTask = nil
                activeReadOperation = nil
            }
            return .cancelled
        }
        activeReadTask = nil
        activeReadOperation = nil

        guard operationStillMatches(identity, requireRevision: true),
              transitionStillMatches(transitionAttempt),
              !Task.isCancelled else {
            return .cancelled
        }

        switch outcome {
        case .success(let loaded):
            // This is the last point at which a rejected cleanup can preserve
            // the complete old document/recovery state. Only a validated
            // incoming package is allowed to reach this conditional cleanup.
            if let recoveryToDiscardAfterValidation,
               !(await removeRecovery(recoveryToDiscardAfterValidation, transitionAttempt: transitionAttempt)) {
                guard transitionStillMatches(transitionAttempt) else { return .cancelled }
                return .failed(failure ?? .recoveryDeletionFailed)
            }
            guard transitionStillMatches(transitionAttempt) else { return .cancelled }
            let adoptionBoundary = await beginDocumentBoundary()
            guard transitionStillMatches(transitionAttempt), lifecycleEpoch == adoptionBoundary else {
                return .cancelled
            }
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
            project = loaded.package; fileURL = loaded.sourceURL; durableFingerprint = loaded.fingerprint
            displayName = loaded.sourceURL.deletingPathExtension().lastPathComponent
            startPresentingDurableFile(loaded.sourceURL)
            failure = nil; phase = .clean; hasUnsavedChanges = false
            await progress?(.checkingRecovery)
            guard transitionStillMatches(transitionAttempt) else { return .cancelled }
            await findRecoveryCandidate(transitionAttempt: transitionAttempt)
            guard transitionStillMatches(transitionAttempt) else { return .cancelled }
            transitionFailure = nil
            return .completed
        case .cancelled:
            return .cancelled
        case .failure(let error):
            guard transitionStillMatches(transitionAttempt) else { return .cancelled }
            setFailure(error)
            return .failed(error)
        }
    }

    @discardableResult func save(to destination: URL? = nil, userSelected: Bool = false) async -> Bool {
        let invocationEpoch = lifecycleEpoch
        await cancelAndDrainAutosave()
        if let priorSave = activeSaveTask {
            _ = await priorSave.value
        }
        await cancelAndDrainAutosave()
        guard lifecycleEpoch == invocationEpoch, !Task.isCancelled else { return false }
        guard let target = destination ?? fileURL else { return false }
        if userSelected {
            do { try await backend.authorizeUserSelection(target) }
            catch let error as DocumentLifecycleFailure { setFailure(error); return false }
            catch { setFailure(.permissionDenied); return false }
        }
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
        // Claim the operation before creating the unstructured task. A task
        // inherited by the main actor is allowed to begin as soon as this
        // method next suspends; publishing after creation left a tiny
        // scheduler-dependent interval where `performSave` could correctly
        // reject its own operation as inactive without producing a failure.
        activeSaveOperation = identity
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
            let completed = try await backend.write(
                package,
                history: history,
                to: target,
                expected: expected,
                identity: identity
            )
            // `identity.destination` was frozen before this task was created.
            // Rebuilding a token from a Foundation URL after coordination is
            // unsound because the framework may re-spell system aliases. The
            // backend has already committed via the exact requested access
            // boundary, and the returned fingerprint binds the committed file.
            guard operationStillMatches(identity, requireRevision: false),
                  activeSaveOperation == identity,
                  !Task.isCancelled else {
                return false
            }
            project = package
            fileURL = completed.destinationURL
            durableFingerprint = completed.fingerprint
            displayName = completed.destinationURL.deletingPathExtension().lastPathComponent
            startPresentingDurableFile(completed.destinationURL)
            if session.document.revision == identity.revision {
                hasUnsavedChanges = false
                // A durable package can be committed while retirement of an
                // older recovery artifact is rejected by its identity proof.
                // That is not a fully successful Save operation: retain the
                // artifact and surface its typed, retryable failure instead
                // of claiming the entire save completed.
                guard await removeRecovery(for: package.projectID) else {
                    return false
                }
                phase = .clean
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
        let attempt = beginTransitionAttempt()
        defer { finishTransitionAttempt(attempt) }
        switch await authorize(.revertToSaved) {
        case .cancelled:
            finishTransitionAttempt(attempt)
            return .cancelled
        case .failed(let error):
            guard transitionStillMatches(attempt) else { return .cancelled }
            finishTransitionAttempt(attempt)
            return .failed(error)
        case .proceed(let discarding):
            guard transitionStillMatches(attempt) else { return .cancelled }
            // Revert reads through the same pre-adoption boundary as Open.
            // Never discard a valid recovery just because the durable package
            // later proves malformed or unavailable.
            let recoveryToDiscard = discarding ? currentRecoveryArtifact : nil
            let boundary = await beginDocumentBoundary()
            guard transitionStillMatches(attempt), lifecycleEpoch == boundary else { return .cancelled }
            let result = await loadAndAdopt(
                fileURL,
                intent: .revert,
                recoveryToDiscardAfterValidation: recoveryToDiscard,
                transitionAttempt: attempt
            )
            finishTransitionAttempt(attempt)
            return result
        }
    }

    func noteCancellation() { /* Native panel cancellation is intentionally state-neutral. */ }

    @discardableResult
    func requestRestoreRecovery() async -> DocumentTransitionResult {
        guard let candidate = recoveryCandidate else { return .cancelled }
        guard canRestoreRecovery else {
            setFailure(.recoveryDeletionFailed)
            return .failed(.recoveryDeletionFailed)
        }
        let attempt = beginTransitionAttempt()
        defer { finishTransitionAttempt(attempt) }
        // Authorization may save or otherwise cross a lifecycle boundary. Keep
        // this presentation identity only for an authorization outcome; create
        // the actual read/adoption identity after the new boundary is active.
        let authorizationIdentity = makeOperation(
            intent: .restore,
            destination: .file(candidate.url, kind: .recovery),
            documentID: candidate.package.document.id,
            projectID: candidate.package.projectID,
            revision: candidate.package.document.revision
        )
        let previousProjectID = project.projectID
        switch await authorize(.restoreRecovery) {
        case .cancelled:
            finishTransitionAttempt(attempt)
            await backend.recordEvent(authorizationIdentity, result: .cancelled)
            return .cancelled
        case .failed(let error):
            guard transitionStillMatches(attempt) else { return .cancelled }
            finishTransitionAttempt(attempt)
            await backend.recordEvent(authorizationIdentity, result: .failure, failure: error)
            return .failed(error)
        case .proceed(let discarding):
            guard transitionStillMatches(attempt) else { return .cancelled }
            let recoveryToDiscard = discarding && previousProjectID != candidate.package.projectID
                ? currentRecoveryArtifact
                : nil
            let boundary = await beginDocumentBoundary()
            guard transitionStillMatches(attempt), lifecycleEpoch == boundary,
                  recoveryCandidate == candidate else {
                await backend.recordEvent(authorizationIdentity, result: .cancelled)
                return .cancelled
            }
            let identity = makeOperation(
                intent: .restore,
                destination: .file(candidate.url, kind: .recovery),
                documentID: candidate.package.document.id,
                projectID: candidate.package.projectID,
                revision: candidate.package.document.revision
            )
            activeRecoveryOperation = identity
            do {
                // A candidate is a presentation snapshot, not an adoption right.
                // Re-read the exact app-owned bytes immediately before adoption.
                let loaded = try await backend.readRecovery(
                    from: candidate.url,
                    expectedProjectID: candidate.package.projectID,
                    identity: identity
                )
                guard recoveryOperationStillMatches(identity, candidate: candidate),
                      transitionStillMatches(attempt) else {
                    finishRecoveryOperation(identity)
                    await backend.recordEvent(identity, result: .cancelled)
                    return .cancelled
                }
                let refreshed = RecoveryCandidate(
                    package: loaded.package,
                    url: loaded.sourceURL,
                    durableURL: candidate.durableURL,
                    history: loaded.history,
                    fingerprint: loaded.fingerprint
                )
                guard refreshed.fingerprint == candidate.fingerprint else {
                    let priorCandidateOwnership = candidateRecoveryArtifact
                    // If this was the current document's candidate, the
                    // public recovery name has changed beneath its old
                    // fingerprint. Do not carry that stale expectation into a
                    // later autosave after the refreshed candidate is
                    // discarded. A foreign untitled candidate must not affect
                    // the current document's independent proof.
                    if currentRecoveryArtifact == priorCandidateOwnership {
                        currentRecoveryArtifact = nil
                    }
                    setRecoveryCandidate(refreshed)
                    activeRecoveryOperation = nil
                    setFailure(.recoveryArtifactConflict)
                    finishTransitionAttempt(attempt)
                    await backend.recordEvent(identity, result: .stale, failure: .recoveryArtifactConflict)
                    return .failed(.recoveryArtifactConflict)
                }
                // Restore has now re-read and identity-validated the incoming
                // candidate. If it replaces a different project, only now may
                // the old project's exact owned recovery be discarded.
                if let recoveryToDiscard, !(await removeRecovery(recoveryToDiscard, transitionAttempt: attempt)) {
                    guard transitionStillMatches(attempt) else {
                        finishRecoveryOperation(identity)
                        return .cancelled
                    }
                    finishRecoveryOperation(identity)
                    await backend.recordEvent(identity, result: .failure, failure: failure ?? .recoveryDeletionFailed)
                    return .failed(failure ?? .recoveryDeletionFailed)
                }
                guard transitionStillMatches(attempt) else {
                    finishRecoveryOperation(identity)
                    return .cancelled
                }
                installRecovery(refreshed)
                activeRecoveryOperation = nil
                finishTransitionAttempt(attempt)
                await backend.recordEvent(identity, result: .success)
                return .completed
            } catch is CancellationError {
                finishRecoveryOperation(identity)
                finishTransitionAttempt(attempt)
                await backend.recordEvent(identity, result: .cancelled)
                return .cancelled
            } catch let error as DocumentLifecycleFailure {
                guard recoveryOperationStillMatches(identity, candidate: candidate),
                      transitionStillMatches(attempt) else {
                    finishRecoveryOperation(identity)
                    return .cancelled
                }
                activeRecoveryOperation = nil
                setFailure(error)
                finishTransitionAttempt(attempt)
                await backend.recordEvent(identity, result: .failure, failure: error)
                return .failed(error)
            } catch {
                guard recoveryOperationStillMatches(identity, candidate: candidate),
                      transitionStillMatches(attempt) else {
                    finishRecoveryOperation(identity)
                    return .cancelled
                }
                activeRecoveryOperation = nil
                setFailure(.malformedRecovery)
                finishTransitionAttempt(attempt)
                await backend.recordEvent(identity, result: .failure, failure: .malformedRecovery)
                return .failed(.malformedRecovery)
            }
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
        // The re-read candidate is now the document actually hosted by this
        // scene. Promote its exact ownership proof to the current-project
        // slot; an unrelated candidate must never become the current
        // document's autosave or retirement capability.
        currentRecoveryArtifact = OwnedRecoveryArtifact(
            projectID: candidate.package.projectID,
            fingerprint: candidate.fingerprint,
            revision: candidate.package.document.revision
        )
        clearRecoveryCandidate()
        failure = nil; phase = .recovered; hasUnsavedChanges = true
        transitionFailure = nil
        if let durableURL = candidate.durableURL { startPresentingDurableFile(durableURL) }
        else { stopPresentingDurableFile() }
    }

    func discardRecovery() async {
        guard let candidate = recoveryCandidate else { return }
        // A recovery action is unavailable while a document transition owns
        // the lifecycle.  Do not let a second UI action replace its commit
        // capability or race its adoption boundary.
        guard activeTransitionAttempt == nil else { return }
        let candidateOwnership = OwnedRecoveryArtifact(
            projectID: candidate.package.projectID,
            fingerprint: candidate.fingerprint,
            revision: candidate.package.document.revision
        )
        guard candidateRecoveryArtifact == candidateOwnership else {
            setFailure(.recoveryArtifactConflict)
            return
        }
        let identity = makeOperation(
            intent: .discardRecovery,
            destination: .file(candidate.url, kind: .recovery),
            documentID: candidate.package.document.id,
            projectID: candidate.package.projectID,
            revision: candidate.package.document.revision
        )
        activeRecoveryOperation = identity
        guard let retirementLease = acquireRecoveryRetirementLease(transitionAttempt: nil) else {
            return
        }
        defer { releaseRecoveryRetirementLease(retirementLease, transitionAttempt: nil) }
        do {
            try await backend.removeRecovery(
                candidate.url,
                projectID: candidate.package.projectID,
                expected: candidate.fingerprint,
                transitionGate: transitionGate,
                transitionAttempt: retirementLease,
                identity: identity
            )
            guard recoveryRetirementLeaseStillMatches(retirementLease, transitionAttempt: nil),
                  recoveryOperationStillMatches(identity, candidate: candidate) else {
                finishRecoveryOperation(identity)
                return
            }
            if currentRecoveryArtifact == candidateOwnership {
                currentRecoveryArtifact = nil
            }
            clearRecoveryCandidate()
            // Discarding an *external* untitled candidate must not rewrite the
            // modified state of the document currently hosted by this scene.
            // In particular, a blank document with pending edits must remain
            // modified and retain its own autosave ownership proof.
            failure = nil
            if !hasUnsavedChanges, phase != .recovered { phase = .clean }
            activeRecoveryOperation = nil
        } catch is CancellationError {
            finishRecoveryOperation(identity)
            return
        } catch let error as DocumentLifecycleFailure {
            guard recoveryRetirementLeaseStillMatches(retirementLease, transitionAttempt: nil),
                  recoveryOperationStillMatches(identity, candidate: candidate) else {
                finishRecoveryOperation(identity)
                return
            }
            activeRecoveryOperation = nil
            setFailure(error)
        } catch {
            guard recoveryRetirementLeaseStillMatches(retirementLease, transitionAttempt: nil),
                  recoveryOperationStillMatches(identity, candidate: candidate) else {
                finishRecoveryOperation(identity)
                return
            }
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
        let attempt = beginTransitionAttempt()
        defer { finishTransitionAttempt(attempt) }
        switch await authorize(.closeWindow) {
        case .cancelled:
            finishTransitionAttempt(attempt)
            return .cancelled
        case .failed(let error):
            guard transitionStillMatches(attempt) else { return .cancelled }
            finishTransitionAttempt(attempt)
            return .failed(error)
        case .proceed(let discarding):
            guard transitionStillMatches(attempt) else { return .cancelled }
            let priorRecovery = currentRecoveryArtifact
            if discarding, let priorRecovery, priorRecovery.projectID == project.projectID,
               !(await removeRecovery(priorRecovery, transitionAttempt: attempt)) {
                guard transitionStillMatches(attempt) else { return .cancelled }
                finishTransitionAttempt(attempt)
                return .failed(failure ?? .recoveryDeletionFailed)
            }
            guard transitionStillMatches(attempt) else { return .cancelled }
            let boundary = await beginDocumentBoundary()
            guard transitionStillMatches(attempt), lifecycleEpoch == boundary else { return .cancelled }
            stopPresentingDurableFile()
            finishTransitionAttempt(attempt)
            return .completed
        }
    }

    func closeAfterAuthorization(_ window: NSWindow) {
        allowNextClose = true
        window.performClose(nil)
    }

    private func documentDidChange(_ document: CanonicalDocument) {
        guard !observing else { return }
        // Keep a previously validated candidate actionable while the newer
        // revision is still only in memory or is crossing the recovery-write
        // boundary. Restore must be allowed to authorize against that exact
        // candidate; it is retired only after a replacement artifact has
        // committed and proved that the old fingerprint is no longer current.
        phase = .modified; failure = nil; hasUnsavedChanges = true
        scheduleAutosave(for: document)
    }

    private func scheduleAutosave(for document: CanonicalDocument) {
        let priorAutosave = autosaveTask
        priorAutosave?.cancel()
        let identity = makeOperation(
            intent: .autosave,
            destination: .file(recoveryURL(for: project.projectID), kind: .recovery),
            documentID: document.id,
            revision: document.revision
        )
        autosaveOperation = identity
        autosaveTask = Task { @MainActor [weak self, autosaveDebouncer] in
            do {
                // An older write may already have crossed the filesystem
                // commit boundary when it is cancelled. Drain it before a new
                // autosave captures its expected recovery fingerprint.
                if let priorAutosave { await priorAutosave.value }
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
            let completed = try await backend.write(
                package,
                history: historySnapshot,
                recoveryBoundary: project.document.revision,
                to: recoveryURL(for: project.projectID),
                expected: expectedRecoveryFingerprint(for: package.projectID),
                identity: identity
            )
            // A completed write is durable even when cancellation/newer work
            // makes its UI result stale. Retain its exact ownership proof for
            // the next conditional recovery write, but never adopt stale UI
            // phase or document state.
            recordCompletedRecoveryArtifact(completed.fingerprint, identity: identity)
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

    private func findRecoveryCandidate(transitionAttempt: LifecycleOperationID) async {
        guard self.transitionStillMatches(transitionAttempt) else { return }
        guard let fileURL else { return }
        let recoveryURL = recoveryURL(for: project.projectID)
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else {
            clearRecoveryCandidate()
            currentRecoveryArtifact = nil
            return
        }
        let identity = makeOperation(
            intent: .discoverRecovery,
            destination: .file(recoveryURL, kind: .recovery)
        )
        activeRecoveryOperation = identity
        do {
            if try await backend.isRetiredRecoveryTombstone(
                at: recoveryURL,
                projectID: project.projectID
            ) {
                guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                    finishRecoveryOperation(identity)
                    return
                }
                clearRecoveryCandidate()
                currentRecoveryArtifact = nil
                activeRecoveryOperation = nil
                return
            }
            let loaded = try await backend.readRecovery(
                from: recoveryURL,
                expectedProjectID: project.projectID,
                identity: identity
            )
            guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                finishRecoveryOperation(identity)
                return
            }
            guard loaded.package.projectID == project.projectID,
                  loaded.package.document.revision > project.document.revision else {
                if loaded.package.projectID == project.projectID {
                    let staleCandidate = RecoveryCandidate(
                        package: loaded.package,
                        url: recoveryURL,
                        durableURL: fileURL,
                        history: loaded.history,
                        fingerprint: loaded.fingerprint
                    )
                    let staleOwnership = OwnedRecoveryArtifact(
                        projectID: loaded.package.projectID,
                        fingerprint: loaded.fingerprint,
                        revision: loaded.package.document.revision
                    )
                    currentRecoveryArtifact = staleOwnership
                    guard await removeRecovery(
                        staleOwnership,
                        transitionAttempt: transitionAttempt
                    ) else {
                        guard recoveryOperationStillMatches(identity, requireRevision: true),
                              transitionStillMatches(transitionAttempt) else {
                            finishRecoveryOperation(identity)
                            return
                        }
                        setRecoveryCandidate(staleCandidate)
                        activeRecoveryOperation = nil
                        if failure == nil { setFailure(.recoveryDeletionFailed) }
                        return
                    }
                    guard recoveryOperationStillMatches(identity, requireRevision: true),
                          transitionStillMatches(transitionAttempt) else {
                        finishRecoveryOperation(identity)
                        return
                    }
                    if currentRecoveryArtifact == staleOwnership { currentRecoveryArtifact = nil }
                } else {
                    setFailure(.recoveryArtifactConflict)
                }
                clearRecoveryCandidate()
                activeRecoveryOperation = nil
                return
            }
            let candidate = RecoveryCandidate(
                package: loaded.package,
                url: recoveryURL,
                durableURL: fileURL,
                history: loaded.history,
                fingerprint: loaded.fingerprint
            )
            let ownership = OwnedRecoveryArtifact(
                projectID: loaded.package.projectID,
                fingerprint: loaded.fingerprint,
                revision: loaded.package.document.revision
            )
            currentRecoveryArtifact = ownership
            setRecoveryCandidate(candidate, ownership: ownership)
            activeRecoveryOperation = nil
        } catch is CancellationError {
            finishRecoveryOperation(identity)
            return
        } catch let error as DocumentLifecycleFailure {
            guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                finishRecoveryOperation(identity)
                return
            }
            activeRecoveryOperation = nil
            clearRecoveryCandidate()
            currentRecoveryArtifact = nil
            setFailure(error == .recoveryArtifactConflict ? error : .malformedRecovery)
        } catch {
            guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                finishRecoveryOperation(identity)
                return
            }
            activeRecoveryOperation = nil
            clearRecoveryCandidate(); currentRecoveryArtifact = nil; setFailure(.malformedRecovery)
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
            let artifacts = try await backend.recoveryURLs(in: recoveryDirectory, identity: identity)
            guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                finishRecoveryOperation(identity)
                return
            }
            var candidates: [RecoveryCandidate] = []
            for artifact in artifacts {
                let url = artifact.url
                do {
                    let candidateIdentity = makeOperation(
                        intent: .discoverRecovery,
                        destination: .file(url, kind: .recovery),
                        projectID: artifact.expectedProjectID
                    )
                    let loaded = try await backend.readRecovery(
                        from: url,
                        expectedProjectID: artifact.expectedProjectID,
                        identity: candidateIdentity
                    )
                    // `candidateIdentity` intentionally names the recovered
                    // project, while the scene is still hosting an untitled
                    // blank project. The outer discovery identity is the
                    // lifecycle authority here; comparing the candidate's
                    // project ID to the current blank project's ID would
                    // reject every valid untitled recovery after a relaunch.
                    guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                        finishRecoveryOperation(identity)
                        return
                    }
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
            guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                finishRecoveryOperation(identity)
                return
            }
            let candidate = candidates.max {
                if $0.package.modifiedAt == $1.package.modifiedAt {
                    return $0.package.projectID.description < $1.package.projectID.description
                }
                return $0.package.modifiedAt < $1.package.modifiedAt
            }
            if let candidate {
                setRecoveryCandidate(candidate)
            } else {
                clearRecoveryCandidate()
            }
            activeRecoveryOperation = nil
        } catch is CancellationError {
            finishRecoveryOperation(identity)
            return
        } catch {
            guard recoveryOperationStillMatches(identity, requireRevision: true) else {
                finishRecoveryOperation(identity)
                return
            }
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

    @discardableResult
    private func beginDocumentBoundary() async -> LifecycleEpoch {
        let boundary = LifecycleEpoch()
        lifecycleEpoch = boundary

        invalidateRecoveryRetirementLease()

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
        return boundary
    }

    private func beginTransitionAttempt() -> LifecycleOperationID {
        // A standalone Discard or stale-recovery cleanup may be suspended at
        // the descriptor-bound final exchange.  Claiming a newer transition
        // first makes that old exchange and all of its later UI publication
        // neutral; it never deletes a recovery artifact for a new document.
        invalidateRecoveryRetirementLease()
        activeRecoveryOperation = nil
        let attempt = LifecycleOperationID()
        activeTransitionAttempt = attempt
        transitionGate.claim(attempt)
        return attempt
    }

    private func transitionStillMatches(_ attempt: LifecycleOperationID) -> Bool {
        activeTransitionAttempt == attempt && !Task.isCancelled
    }

    private func finishTransitionAttempt(_ attempt: LifecycleOperationID) {
        guard activeTransitionAttempt == attempt else { return }
        activeTransitionAttempt = nil
        transitionGate.finish(attempt)
    }

    /// Acquires the final-commit authorization for a recovery retirement.
    /// Transition-owned cleanup borrows its already-current transition token;
    /// standalone cleanup gets a distinct short-lived lease that a later
    /// transition can atomically supersede.
    private func acquireRecoveryRetirementLease(
        transitionAttempt: LifecycleOperationID?
    ) -> LifecycleOperationID? {
        if let transitionAttempt {
            guard transitionStillMatches(transitionAttempt),
                  transitionGate.isCurrent(transitionAttempt) else {
                return nil
            }
            return transitionAttempt
        }
        guard activeTransitionAttempt == nil else { return nil }
        invalidateRecoveryRetirementLease()
        let lease = LifecycleOperationID()
        activeRecoveryRetirementAttempt = lease
        transitionGate.claim(lease)
        return lease
    }

    private func recoveryRetirementLeaseStillMatches(
        _ lease: LifecycleOperationID,
        transitionAttempt: LifecycleOperationID?
    ) -> Bool {
        if let transitionAttempt {
            return lease == transitionAttempt
                && transitionStillMatches(transitionAttempt)
                && transitionGate.isCurrent(lease)
        }
        return activeRecoveryRetirementAttempt == lease
            && transitionGate.isCurrent(lease)
            && !Task.isCancelled
    }

    private func releaseRecoveryRetirementLease(
        _ lease: LifecycleOperationID,
        transitionAttempt: LifecycleOperationID?
    ) {
        guard transitionAttempt == nil,
              activeRecoveryRetirementAttempt == lease else { return }
        activeRecoveryRetirementAttempt = nil
        transitionGate.finish(lease)
    }

    private func invalidateRecoveryRetirementLease() {
        guard let lease = activeRecoveryRetirementAttempt else { return }
        activeRecoveryRetirementAttempt = nil
        transitionGate.finish(lease)
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

    @discardableResult
    private func removeRecovery(for projectID: ProjectID) async -> Bool {
        guard let owned = currentRecoveryArtifact, owned.projectID == projectID else { return true }
        return await removeRecovery(owned, transitionAttempt: activeTransitionAttempt)
    }

    /// An adoption boundary can replace the current-document recovery proof
    /// before prior-project cleanup runs. Carry the exact proof captured
    /// before that boundary instead of consulting mutable current-project
    /// state. A separately presented candidate may also be retired, but only
    /// its exact candidate proof may clear that presentation.
    @discardableResult
    private func removeRecovery(
        _ owned: OwnedRecoveryArtifact,
        transitionAttempt: LifecycleOperationID? = nil
    ) async -> Bool {
        // A transition may lose ownership while this identity-bound cleanup is
        // suspended. Its package operation remains conditional on `owned`, but
        // it must not then clear recovery presentation or publish a failure
        // into the newer transition's lifecycle state.
        if let transitionAttempt, !transitionStillMatches(transitionAttempt) {
            return false
        }
        guard let retirementLease = acquireRecoveryRetirementLease(
            transitionAttempt: transitionAttempt
        ) else {
            return false
        }
        defer {
            releaseRecoveryRetirementLease(
                retirementLease,
                transitionAttempt: transitionAttempt
            )
        }
        let url = recoveryURL(for: owned.projectID)
        let identity = makeOperation(
            intent: .discardRecovery,
            destination: .file(url, kind: .recovery),
            projectID: owned.projectID
        )
        do {
            try await backend.removeRecovery(
                url,
                projectID: owned.projectID,
                expected: owned.fingerprint,
                transitionGate: transitionGate,
                transitionAttempt: retirementLease,
                identity: identity
            )
            guard recoveryRetirementLeaseStillMatches(
                retirementLease,
                transitionAttempt: transitionAttempt
            ) else {
                return false
            }
            guard ownsRecoveryArtifact(owned) else { return false }
            if currentRecoveryArtifact == owned { currentRecoveryArtifact = nil }
            if candidateRecoveryArtifact == owned { clearRecoveryCandidate() }
            return true
        } catch let error as DocumentLifecycleFailure {
            // The artifact remains discoverable and retryable. Do not clear the
            // ownership proof until the identity-bound deletion has succeeded.
            guard recoveryRetirementLeaseStillMatches(
                retirementLease,
                transitionAttempt: transitionAttempt
            ) else {
                return false
            }
            guard ownsRecoveryArtifact(owned) else { return false }
            setFailure(error)
            return false
        } catch {
            guard recoveryRetirementLeaseStillMatches(
                retirementLease,
                transitionAttempt: transitionAttempt
            ) else {
                return false
            }
            guard ownsRecoveryArtifact(owned) else { return false }
            setFailure(.recoveryDeletionFailed)
            return false
        }
    }

    private func expectedRecoveryFingerprint(for projectID: ProjectID) -> PackageFingerprint? {
        guard let owned = currentRecoveryArtifact, owned.projectID == projectID else { return nil }
        return owned.fingerprint
    }

    private func recordCompletedRecoveryArtifact(
        _ fingerprint: PackageFingerprint,
        identity: LifecycleOperationIdentity
    ) {
        guard identity.epoch == lifecycleEpoch,
              identity.documentID == session.document.id,
              identity.projectID == project.projectID else { return }
        if let owned = currentRecoveryArtifact,
           owned.projectID == identity.projectID,
           owned.revision > identity.revision {
            return
        }
        currentRecoveryArtifact = OwnedRecoveryArtifact(
            projectID: identity.projectID,
            fingerprint: fingerprint,
            revision: identity.revision
        )
        // The completed bytes replace the candidate's exact recovered
        // snapshot. Do this at the post-commit ownership boundary rather than
        // at edit time, including when a later cancellation makes the UI
        // completion stale, so we never expose a fingerprint that no longer
        // names the recovery artifact on disk.
        if let candidate = recoveryCandidate,
           candidateRecoveryArtifact?.projectID == identity.projectID,
           identity.destination == .file(candidate.url, kind: .recovery),
           candidate.fingerprint != fingerprint {
            clearRecoveryCandidate()
        }
    }

    private func setRecoveryCandidate(
        _ candidate: RecoveryCandidate,
        ownership: OwnedRecoveryArtifact? = nil
    ) {
        recoveryCandidate = candidate
        candidateRecoveryArtifact = ownership ?? OwnedRecoveryArtifact(
            projectID: candidate.package.projectID,
            fingerprint: candidate.fingerprint,
            revision: candidate.package.document.revision
        )
    }

    private func clearRecoveryCandidate() {
        recoveryCandidate = nil
        candidateRecoveryArtifact = nil
    }

    private func ownsRecoveryArtifact(_ owned: OwnedRecoveryArtifact) -> Bool {
        currentRecoveryArtifact == owned || candidateRecoveryArtifact == owned
    }

    private func setFailure(_ error: DocumentLifecycleFailure) {
        failure = error
        phase = error == .externalModification || error == .conflict ? .conflicted : .failed
    }

    func presentSavePanel() {
        guard let url = saveDestinationProvider(suggestedSaveFilename) else { noteCancellation(); return }
        Task { _ = await save(to: url, userSelected: true) }
    }

    private func startPresentingDurableFile(_ url: URL) {
        stopPresentingDurableFile()
        let presenter = ProjectFilePresenter(url: url) { [weak self] event in
            Task { @MainActor [weak self] in self?.receiveFilePresentation(event) }
        }
        filePresenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)
    }

    private func stopPresentingDurableFile() {
        guard let filePresenter else { return }
        NSFileCoordinator.removeFilePresenter(filePresenter)
        self.filePresenter = nil
    }

    func receiveFilePresentation(_ event: ProjectFilePresentationEvent) {
        switch event {
        case .changed:
            guard phase != .saving, phase != .autosaving else { return }
            setFailure(.externalModification)
        case .moved(let newURL):
            guard let oldURL = fileURL else { return }
            fileURL = newURL
            displayName = newURL.deletingPathExtension().lastPathComponent
            Task { [backend] in try? await backend.recordRelocation(from: oldURL, to: newURL) }
        case .deleted:
            setFailure(.externalModification)
        }
    }
}
