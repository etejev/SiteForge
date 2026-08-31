import CryptoKit
import Foundation

/// Shared retention policy for in-memory support diagnostics.
///
/// Diagnostic evidence is intentionally bounded so a long authoring session
/// cannot grow memory without limit. The default retains the newest 512
/// records, which is enough to preserve a useful operation trail without
/// turning diagnostics into durable user-data storage.
enum DiagnosticRetentionPolicy {
    static let defaultCapacity = 512
}

/// A sequence number paired with a retained diagnostic record.
struct SequencedDiagnosticRecord<Record: Sendable>: Sendable {
    let sequence: UInt64
    let record: Record
}

/// Fixed-capacity ring buffer with deterministic oldest-to-newest snapshots.
/// Sequence numbers are assigned before eviction and remain monotonic for the
/// lifetime of the buffer. `droppedRecordCount` makes eviction observable.
struct BoundedDiagnosticBuffer<Record: Sendable>: Sendable {
    let capacity: Int
    private(set) var droppedRecordCount: UInt64 = 0

    private var storage: [SequencedDiagnosticRecord<Record>?]
    private var oldestIndex = 0
    private var retainedCount = 0
    private var nextSequence: UInt64 = 0

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        precondition(capacity > 0, "Diagnostic capacity must be positive")
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    @discardableResult
    mutating func append(_ record: Record) -> UInt64 {
        precondition(nextSequence < UInt64.max, "Diagnostic sequence exhausted")
        let sequence = nextSequence
        nextSequence += 1
        let value = SequencedDiagnosticRecord(sequence: sequence, record: record)

        if retainedCount < capacity {
            storage[(oldestIndex + retainedCount) % capacity] = value
            retainedCount += 1
        } else {
            storage[oldestIndex] = value
            oldestIndex = (oldestIndex + 1) % capacity
            droppedRecordCount += 1
        }
        return sequence
    }

    func sequencedSnapshot() -> [SequencedDiagnosticRecord<Record>] {
        (0..<retainedCount).compactMap { offset in
            storage[(oldestIndex + offset) % capacity]
        }
    }

    func snapshot() -> [Record] {
        sequencedSnapshot().map(\.record)
    }
}

/// Closed domain labels prevent the same stable identifier from producing the
/// same support token in unrelated subsystems.
enum DiagnosticIdentifierDomain: String, Sendable {
    case canvasRender = "canvas-render"
    case command = "command"
    case containerLayout = "container-layout"
    case document = "document"
    case dragDrop = "drag-drop"
    case geometryInspector = "geometry-inspector"
    case history = "history"
    case launch = "launch"
    case lifecycleDestination = "lifecycle-destination"
    case lifecycleDocument = "lifecycle-document"
    case lifecycleEpoch = "lifecycle-epoch"
    case lifecycleOperation = "lifecycle-operation"
    case lifecycleProject = "lifecycle-project"
    case projectPackage = "project-package"
    case responsiveVisibility = "responsive-visibility"
    case selection = "selection"
    case snapping = "snapping"
    case textEditing = "text-editing"
    case transform = "transform"
    case viewport = "viewport"
}

enum DiagnosticStableIdentifier {
    /// Returns a deterministic, non-reversible support token. Only the first
    /// 96 bits are retained; raw UUIDs, paths, and authored values never enter
    /// the diagnostic record.
    static func sanitize(
        _ value: String,
        domain: DiagnosticIdentifierDomain,
        kind: String
    ) -> String {
        let payload = "siteforge-diagnostic-v1\u{0}\(domain.rawValue)\u{0}\(value)"
        let digest = SHA256.hash(data: Data(payload.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(kind)-\(digest)"
    }
}

/// Common closed categories for errors received at an untyped subsystem
/// boundary. Domain-specific errors should map exhaustively to their own closed
/// enums and store the raw value rather than serializing an error description.
enum DiagnosticErrorCategory: String, Codable, Sendable {
    case cancelled
    case conflict
    case corruptData = "corrupt-data"
    case integrity
    case invalidInput = "invalid-input"
    case io
    case missingTarget = "missing-target"
    case permission
    case stale
    case unavailable
    case unsupported
    case invariantViolation = "invariant-violation"
    case unknown

    static func closedCategory(for error: Error) -> Self {
        if error is CancellationError { return .cancelled }
        return .unknown
    }

    static func closedCategory(forUntrustedValue value: String) -> Self {
        let normalized = value.lowercased()
        if normalized.contains("cancel") { return .cancelled }
        if normalized.contains("stale") { return .stale }
        if normalized.contains("permission") || normalized.contains("denied") { return .permission }
        if normalized.contains("conflict") { return .conflict }
        if normalized.contains("integrity") || normalized.contains("checksum") { return .integrity }
        if normalized.contains("corrupt") || normalized.contains("malformed") { return .corruptData }
        if normalized.contains("unsupported") || normalized.contains("incompatible") { return .unsupported }
        if normalized.contains("missing") { return .missingTarget }
        if normalized.contains("unavailable") { return .unavailable }
        if normalized.contains("invalid") || normalized.contains("nonfinite") { return .invalidInput }
        if normalized.contains("invariant") { return .invariantViolation }
        if normalized.contains("io") || normalized.contains("read") || normalized.contains("write") { return .io }
        return .unknown
    }
}
