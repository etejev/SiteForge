import CryptoKit
import Foundation

enum TransactionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "transaction"
}

typealias TransactionID = StableIdentifier<TransactionIdentifierDomain>

struct PersistedHistorySnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let documentID: DocumentID
    let documentRevision: UInt64
    let boundaryRevision: UInt64
    let undoEntries: [HistoryEntry]
    let redoEntries: [HistoryEntry]

    init(
        documentID: DocumentID,
        documentRevision: UInt64,
        boundaryRevision: UInt64,
        undoEntries: [HistoryEntry],
        redoEntries: [HistoryEntry]
    ) {
        format = "app.siteforge.persisted-history"
        schemaVersion = Self.currentSchemaVersion
        self.documentID = documentID
        self.documentRevision = documentRevision
        self.boundaryRevision = boundaryRevision
        self.undoEntries = undoEntries
        self.redoEntries = redoEntries
    }

    private init(
        format: String,
        schemaVersion: Int,
        documentID: DocumentID,
        documentRevision: UInt64,
        boundaryRevision: UInt64,
        undoEntries: [HistoryEntry],
        redoEntries: [HistoryEntry]
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.documentID = documentID
        self.documentRevision = documentRevision
        self.boundaryRevision = boundaryRevision
        self.undoEntries = undoEntries
        self.redoEntries = redoEntries
    }
}

enum PersistedHistoryError: Error, Equatable, LocalizedError, Sendable {
    case missing
    case corrupt
    case oversized
    case unsupportedSchema(Int)
    case duplicateTransaction
    case reorderedTransactions
    case documentMismatch
    case revisionMismatch
    case identityMismatch
    case inverseMismatch

    var errorDescription: String? {
        switch self {
        case .missing: "This legacy project has no persisted history; a clean history baseline was established."
        case .corrupt: "Persisted history is corrupt and was isolated; the canonical document remains available."
        case .oversized: "Persisted history exceeds the supported local limit and was isolated."
        case .unsupportedSchema(let version): "History schema version \(version) is not supported; a clean baseline was established."
        case .duplicateTransaction: "Persisted history contains a duplicate transaction identity."
        case .reorderedTransactions: "Persisted history transaction ordering is inconsistent."
        case .documentMismatch: "Persisted history belongs to a different document or revision."
        case .revisionMismatch: "A persisted transaction does not apply to its declared parent revision."
        case .identityMismatch: "A persisted transaction references inconsistent stable identities."
        case .inverseMismatch: "A persisted inverse does not restore the expected document state."
        }
    }
}

enum HistoryDiagnosticResult: String, Sendable { case restored, isolated, legacy, retained }
struct HistoryDiagnosticRecord: Equatable, Sendable {
    let requirementIDs: [String]
    let result: HistoryDiagnosticResult
    let sanitizedDocumentID: String
    let undoCount: Int
    let redoCount: Int
    let failureCategory: String?
}

actor PersistedHistoryDiagnostics {
    private(set) var records: [HistoryDiagnosticRecord] = []
    func append(_ record: HistoryDiagnosticRecord) { records.append(record) }
}

enum PersistedHistoryLoadResult: Equatable, Sendable {
    case restored(PersistedHistorySnapshot)
    case cleanBaseline(PersistedHistoryError)
}

actor PersistedHistoryStore {
    static let memberPath = "history.json"
    static let maximumEntryCount = 128
    static let maximumHistoryBytes = 512 * 1_024
    static let requirementIDs: Set<String> = [
        "SF-0306-002", "SF-0306-004", "SF-0306-005", "SF-0306-008",
        "SF-0307-001", "SF-0307-002", "SF-0307-003", "SF-0307-004",
        "SF-0307-005", "SF-0307-006", "SF-0307-008",
    ]

    private let diagnostics: PersistedHistoryDiagnostics
    private let cancellation: CooperativeCancellationCheckpoint

    init(
        diagnostics: PersistedHistoryDiagnostics = PersistedHistoryDiagnostics(),
        cancellation: CooperativeCancellationCheckpoint = CooperativeCancellationCheckpoint()
    ) {
        self.diagnostics = diagnostics
        self.cancellation = cancellation
    }

    func encodeRetained(_ snapshot: PersistedHistorySnapshot) async throws -> Data {
        var retained = snapshot
        while retained.undoEntries.count + retained.redoEntries.count > Self.maximumEntryCount {
            retained = Self.removingOldest(from: retained)
        }
        var data = try Self.encode(retained)
        while data.count > Self.maximumHistoryBytes,
              !retained.undoEntries.isEmpty || !retained.redoEntries.isEmpty {
            retained = Self.removingOldest(from: retained)
            data = try Self.encode(retained)
        }
        guard data.count <= Self.maximumHistoryBytes else { throw PersistedHistoryError.oversized }
        await record(.retained, snapshot: retained, error: nil)
        return data
    }

    func load(from package: ProjectPackage) async throws -> PersistedHistoryLoadResult {
        try cancellation.check()
        guard let member = package.optionalMembers.first(where: { $0.path == Self.memberPath }) else {
            let error = PersistedHistoryError.missing
            await record(.legacy, document: package.document, error: error)
            return .cleanBaseline(error)
        }
        do {
            let snapshot = try Self.decodeAndValidate(
                member.data,
                document: package.document,
                cancellation: cancellation
            )
            await record(.restored, snapshot: snapshot, error: nil)
            return .restored(snapshot)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PersistedHistoryError {
            await record(.isolated, document: package.document, error: error)
            return .cleanBaseline(error)
        } catch {
            await record(.isolated, document: package.document, error: .corrupt)
            return .cleanBaseline(.corrupt)
        }
    }

    func package(_ package: ProjectPackage, with snapshot: PersistedHistorySnapshot) async throws -> ProjectPackage {
        let data = try await encodeRetained(snapshot)
        var members = package.optionalMembers.filter { $0.path != Self.memberPath }
        members.append(ProjectPackageMember(path: Self.memberPath, role: .optional, data: data))
        return ProjectPackage(
            projectID: package.projectID, createdAt: package.createdAt, modifiedAt: package.modifiedAt,
            document: package.document, optionalMembers: members.sorted { $0.path < $1.path },
            compatibility: package.compatibility
        )
    }

    func recoverySnapshot(_ snapshot: PersistedHistorySnapshot, durableRevision: UInt64) -> PersistedHistorySnapshot {
        PersistedHistorySnapshot(
            documentID: snapshot.documentID,
            documentRevision: snapshot.documentRevision,
            boundaryRevision: durableRevision,
            undoEntries: snapshot.undoEntries.filter { $0.parentRevision >= durableRevision },
            redoEntries: snapshot.redoEntries.filter { $0.parentRevision >= durableRevision }
        )
    }

    func diagnosticRecords() async -> [HistoryDiagnosticRecord] { await diagnostics.records }
}

private extension PersistedHistoryStore {
    static func encode(_ snapshot: PersistedHistorySnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func decodeAndValidate(
        _ data: Data,
        document: CanonicalDocument,
        cancellation: CooperativeCancellationCheckpoint
    ) throws -> PersistedHistorySnapshot {
        try cancellation.check()
        guard data.count <= maximumHistoryBytes else { throw PersistedHistoryError.oversized }
        let snapshot: PersistedHistorySnapshot
        do { snapshot = try JSONDecoder().decode(PersistedHistorySnapshot.self, from: data) }
        catch { throw PersistedHistoryError.corrupt }
        try cancellation.check()
        guard snapshot.format == "app.siteforge.persisted-history" else { throw PersistedHistoryError.corrupt }
        guard snapshot.schemaVersion == PersistedHistorySnapshot.currentSchemaVersion else {
            throw PersistedHistoryError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard snapshot.undoEntries.count + snapshot.redoEntries.count <= maximumEntryCount else {
            throw PersistedHistoryError.oversized
        }
        guard snapshot.documentID == document.id, snapshot.documentRevision == document.revision,
              snapshot.boundaryRevision <= document.revision else {
            throw PersistedHistoryError.documentMismatch
        }
        try validateEntries(snapshot, document: document, cancellation: cancellation)
        return snapshot
    }

    static func validateEntries(
        _ snapshot: PersistedHistorySnapshot,
        document: CanonicalDocument,
        cancellation: CooperativeCancellationCheckpoint
    ) throws {
        let all = snapshot.undoEntries + snapshot.redoEntries
        guard Set(all.map(\.id)).count == all.count else { throw PersistedHistoryError.duplicateTransaction }
        let registry = CommandRegistry()
        for entry in all {
            try cancellation.check()
            guard entry.resultRevision == entry.parentRevision + 1 else { throw PersistedHistoryError.revisionMismatch }
            guard entry.commandName == entry.forward.name,
                  entry.label == registry.descriptor(for: entry.commandName).title,
                  entry.affectedIdentifiers == entry.forward.targets,
                  entry.timestamp.date != nil else { throw PersistedHistoryError.identityMismatch }
        }

        let logicalOrder = snapshot.undoEntries + snapshot.redoEntries.reversed()
        for pair in zip(logicalOrder, logicalOrder.dropFirst()) where pair.0.resultRevision != pair.1.parentRevision {
            try cancellation.check()
            throw PersistedHistoryError.reorderedTransactions
        }
        if let first = logicalOrder.first, first.parentRevision < snapshot.boundaryRevision {
            throw PersistedHistoryError.revisionMismatch
        }

        var undoDocument = document
        for entry in snapshot.undoEntries.reversed() {
            try cancellation.check()
            let current = undoDocument
            let availability = registry.availability(for: entry.inverse, in: undoDocument)
            guard availability.isEnabled else { throw PersistedHistoryError.inverseMismatch }
            _ = try registry.apply(entry.inverse, to: &undoDocument)
            var roundTrip = undoDocument
            _ = try registry.apply(entry.forward, to: &roundTrip)
            guard sameContent(roundTrip, current) else { throw PersistedHistoryError.inverseMismatch }
        }

        var redoDocument = document
        for entry in snapshot.redoEntries.reversed() {
            try cancellation.check()
            let before = redoDocument
            let availability = registry.availability(for: entry.forward, in: redoDocument)
            guard availability.isEnabled else { throw PersistedHistoryError.inverseMismatch }
            _ = try registry.apply(entry.forward, to: &redoDocument)
            var roundTrip = redoDocument
            _ = try registry.apply(entry.inverse, to: &roundTrip)
            guard sameContent(roundTrip, before) else { throw PersistedHistoryError.inverseMismatch }
        }
    }

    static func sameContent(_ lhs: CanonicalDocument, _ rhs: CanonicalDocument) -> Bool {
        lhs.id == rhs.id && lhs.pages == rhs.pages
    }

    static func removingOldest(from snapshot: PersistedHistorySnapshot) -> PersistedHistorySnapshot {
        var undo = snapshot.undoEntries
        var redo = snapshot.redoEntries
        if !undo.isEmpty { undo.removeFirst() }
        else if !redo.isEmpty { redo.removeFirst() }
        let boundary = undo.first?.parentRevision ?? redo.last?.parentRevision ?? snapshot.documentRevision
        return PersistedHistorySnapshot(
            documentID: snapshot.documentID, documentRevision: snapshot.documentRevision,
            boundaryRevision: max(snapshot.boundaryRevision, boundary), undoEntries: undo, redoEntries: redo
        )
    }

    func record(_ result: HistoryDiagnosticResult, snapshot: PersistedHistorySnapshot, error: PersistedHistoryError?) async {
        await record(result, document: CanonicalDocument(id: snapshot.documentID, revision: snapshot.documentRevision),
                     undoCount: snapshot.undoEntries.count, redoCount: snapshot.redoEntries.count, error: error)
    }

    func record(_ result: HistoryDiagnosticResult, document: CanonicalDocument, undoCount: Int = 0,
                redoCount: Int = 0, error: PersistedHistoryError?) async {
        let digest = SHA256.hash(data: Data(document.id.description.utf8)).prefix(5)
            .map { String(format: "%02x", $0) }.joined()
        await diagnostics.append(HistoryDiagnosticRecord(
            requirementIDs: ["SF-0306-008", "SF-0307-008"], result: result,
            sanitizedDocumentID: "document-\(digest)", undoCount: undoCount, redoCount: redoCount,
            failureCategory: error.map { String(describing: $0) }
        ))
    }
}
