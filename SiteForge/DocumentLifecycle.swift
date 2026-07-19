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

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Permission was denied. Choose another location or review access in System Settings."
        case .staleSecurityScope: "File access has expired. Locate the project again."
        case .externalModification: "The project changed on disk. Reopen it or use Save As to preserve both versions."
        case .conflict: "A newer save superseded this operation. The current document is unchanged."
        case .malformedPackage: "The project could not be validated. The current document is unchanged."
        case .incompatiblePackage: "This project was created by an incompatible SiteForge version. Choose another project or update SiteForge."
        case .malformedRecovery: "Recovery data is invalid. Discard it or continue with the last saved project."
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

struct PackageFingerprint: Equatable, Sendable {
    let digest: String
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
            let package = try await store.read(from: url)
            try Task.checkCancellation()
            await progress?(.validatingCanonicalDocument)
            let fingerprint = try Self.fingerprint(url)
            try Task.checkCancellation()
            await progress?(.validatingHistory)
            let history = await historyStore.load(from: package)
            try Task.checkCancellation()
            await progress?(.preparingWorkspace)
            await record(operation, package.projectID, start, .success, nil)
            return LoadedProject(package: package, fingerprint: fingerprint, history: history)
        } catch is CancellationError {
            await record(operation, nil, start, .cancelled, nil)
            throw CancellationError()
        } catch {
            let failure = Self.map(error)
            await record(operation, nil, start, .failure, failure)
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
            if let expected {
                guard FileManager.default.fileExists(atPath: url.path), try Self.fingerprint(url) == expected else {
                    throw DocumentLifecycleFailure.externalModification
                }
            }
            let historySnapshot: PersistedHistorySnapshot
            if let recoveryBoundary {
                historySnapshot = await historyStore.recoverySnapshot(history, durableRevision: recoveryBoundary)
            } else {
                historySnapshot = history
            }
            let packageWithHistory = try await historyStore.package(package, with: historySnapshot)
            try await store.write(packageWithHistory, to: url)
            let fingerprint = try Self.fingerprint(url)
            await record(operation, package.projectID, start, .success, nil)
            return fingerprint
        } catch {
            let failure = Self.map(error)
            await record(operation, package.projectID, start, failure == .conflict ? .stale : .failure, failure)
            throw failure
        }
    }

    func remove(_ url: URL) async throws {
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { throw Self.map(error) }
    }

    nonisolated static func recoveryURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).recovery")
    }

    private func throwFault() throws {
        switch fault {
        case .none: break
        case .permission: throw DocumentLifecycleFailure.permissionDenied
        case .staleScope: throw DocumentLifecycleFailure.staleSecurityScope
        case .io: throw DocumentLifecycleFailure.ioFailure
        }
    }

    private nonisolated static func fingerprint(_ url: URL) throws -> PackageFingerprint {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return PackageFingerprint(digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        } catch let error as CocoaError where error.code == .fileReadNoPermission || error.code == .fileWriteNoPermission {
            throw DocumentLifecycleFailure.permissionDenied
        } catch { throw DocumentLifecycleFailure.ioFailure }
    }

    private nonisolated static func map(_ error: Error) -> DocumentLifecycleFailure {
        if let error = error as? DocumentLifecycleFailure { return error }
        if let error = error as? ProjectPackageError {
            switch error {
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
    let history: PersistedHistoryLoadResult
    var summary: String { "Revision \(package.document.revision), newer than the durable revision." }
}

@MainActor
final class DocumentLifecycleController: ObservableObject {
    static let requirementIDs: Set<String> = [
        "SF-0301-002", "SF-0301-004", "SF-0301-005", "SF-0301-006", "SF-0301-008",
        "SF-0306-001", "SF-0306-002", "SF-0306-003", "SF-0306-004", "SF-0306-005", "SF-0306-006", "SF-0306-008",
        "SF-1504-001", "SF-1504-004", "SF-1504-006", "SF-1504-008",
    ]

    @Published private(set) var phase: DocumentLifecyclePhase = .clean
    @Published private(set) var displayName = "Untitled"
    @Published private(set) var failure: DocumentLifecycleFailure?
    @Published private(set) var recoveryCandidate: RecoveryCandidate?
    @Published private(set) var historyNotice: String?
    @Published var isRecoveryDetailsPresented = false
    @Published var isCloseConfirmationPresented = false

    let session: DocumentSession
    let backend: DocumentLifecycleBackend
    private var project: ProjectPackage
    private var durableFingerprint: PackageFingerprint?
    private(set) var fileURL: URL?
    private var generation = 0
    private var autosaveTask: Task<Void, Never>?
    private var observing = false
    private var observation: AnyCancellable?
    private var allowNextClose = false

    init(session: DocumentSession, backend: DocumentLifecycleBackend = DocumentLifecycleBackend()) {
        self.session = session
        self.backend = backend
        let now = ProjectTimestamp(date: Date())
        project = ProjectPackage(createdAt: now, document: session.document)
        observation = session.$document.dropFirst().sink { [weak self] _ in self?.documentDidChange() }
    }

    var isModified: Bool { phase == .modified || phase == .autosaving || phase == .failed || phase == .conflicted || phase == .recovered }
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

    func newDocument() {
        autosaveTask?.cancel()
        let document = ProjectCreation.blank()
        observing = true
        try? session.establishBaseline(document)
        observing = false
        let now = ProjectTimestamp(date: Date())
        project = ProjectPackage(createdAt: now, document: document)
        fileURL = nil; durableFingerprint = nil; displayName = "Untitled"
        failure = nil; recoveryCandidate = nil; phase = .clean
        historyNotice = nil
    }

    @discardableResult
    func open(
        _ url: URL,
        progress: (@Sendable (ProjectLoadUpdate) async -> Void)? = nil
    ) async -> Bool {
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
            failure = nil; phase = .clean
            await progress?(.checkingRecovery)
            await findRecoveryCandidate()
            return true
        } catch is CancellationError {
            observing = false
            return false
        } catch let error as DocumentLifecycleFailure {
            observing = false
            setFailure(error)
            return false
        } catch {
            observing = false
            setFailure(.ioFailure)
            return false
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
            if phase == .clean { try? await backend.remove(DocumentLifecycleBackend.recoveryURL(for: target)) }
            return true
        } catch let error as DocumentLifecycleFailure { setFailure(error); return false }
        catch { setFailure(.ioFailure); return false }
    }

    func revert() async {
        guard let fileURL else { return }
        await open(fileURL)
    }

    func noteCancellation() { /* Native panel cancellation is intentionally state-neutral. */ }

    func restoreRecovery() {
        guard let candidate = recoveryCandidate else { return }
        observing = true
        try? session.establishBaseline(candidate.package.document)
        switch candidate.history {
        case .restored(let snapshot):
            do { try session.installValidatedHistory(snapshot); historyNotice = nil }
            catch { try? session.establishBaseline(candidate.package.document); historyNotice = PersistedHistoryError.inverseMismatch.localizedDescription }
        case .cleanBaseline(let reason): historyNotice = reason.localizedDescription
        }
        observing = false
        project = candidate.package; recoveryCandidate = nil; failure = nil; phase = .recovered
    }

    func discardRecovery() async {
        guard let candidate = recoveryCandidate else { return }
        try? await backend.remove(candidate.url)
        recoveryCandidate = nil; failure = nil; phase = .clean
    }

    func requestClose() -> Bool {
        if allowNextClose { allowNextClose = false; return true }
        guard isModified else { return true }
        isCloseConfirmationPresented = true
        return false
    }

    func saveAndClose() async {
        let saved: Bool
        if fileURL == nil { presentSavePanel(closeAfterSave: true); return }
        saved = await save()
        if saved { closeAfterConfirmation() }
    }

    func discardAndClose() {
        allowNextClose = true
        NSApp.keyWindow?.performClose(nil)
    }

    private func closeAfterConfirmation() {
        allowNextClose = true
        NSApp.keyWindow?.performClose(nil)
    }

    private func documentDidChange() {
        guard !observing else { return }
        phase = .modified; failure = nil
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard fileURL != nil else { return }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.writeRecovery()
        }
    }

    private func writeRecovery() async {
        guard let fileURL else { return }
        generation += 1
        let currentGeneration = generation
        let snapshot = session.document
        let historySnapshot = session.historySnapshot()
        let package = ProjectPackage(projectID: project.projectID, createdAt: project.createdAt,
                                     modifiedAt: ProjectTimestamp(date: Date()), document: snapshot,
                                     optionalMembers: project.optionalMembers, compatibility: project.compatibility)
        phase = .autosaving
        do {
            _ = try await backend.write(package, history: historySnapshot, recoveryBoundary: project.document.revision,
                                        to: DocumentLifecycleBackend.recoveryURL(for: fileURL), expected: nil,
                                        generation: currentGeneration, operation: .autosave)
            if currentGeneration == generation { phase = .modified }
        } catch let error as DocumentLifecycleFailure { setFailure(error) }
        catch { setFailure(.ioFailure) }
    }

    private func findRecoveryCandidate() async {
        guard let fileURL else { return }
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: fileURL)
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { recoveryCandidate = nil; return }
        do {
            let loaded = try await backend.read(from: recoveryURL, operation: .open)
            guard loaded.package.projectID == project.projectID,
                  loaded.package.document.revision > project.document.revision else {
                try? await backend.remove(recoveryURL); recoveryCandidate = nil; return
            }
            recoveryCandidate = RecoveryCandidate(package: loaded.package, url: recoveryURL, history: loaded.history)
        } catch {
            recoveryCandidate = nil; setFailure(.malformedRecovery)
        }
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
        Task { await open(url) }
    }

    func presentSavePanel(closeAfterSave: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.siteForgeProject]
        panel.nameFieldStringValue = displayName == "Untitled" ? "Untitled.siteforge" : "\(displayName).siteforge"
        panel.message = "Save an atomic SiteForge project package."
        guard panel.runModal() == .OK, let url = panel.url else { noteCancellation(); return }
        Task {
            let saved = await save(to: url)
            if saved && closeAfterSave { closeAfterConfirmation() }
        }
    }
}
