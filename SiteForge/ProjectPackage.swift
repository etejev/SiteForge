import CryptoKit
import Darwin
import Foundation

struct CooperativeCancellationCheckpoint: Sendable {
    private let operation: @Sendable () throws -> Void

    init(_ operation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }) {
        self.operation = operation
    }

    func check() throws { try operation() }
}

enum ProjectIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "project"
}

typealias ProjectID = StableIdentifier<ProjectIdentifierDomain>

struct ProjectTimestamp: Codable, Equatable, Comparable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(date: Date) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        rawValue = formatter.string(from: date)
    }

    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: rawValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func < (lhs: ProjectTimestamp, rhs: ProjectTimestamp) -> Bool {
        guard let left = lhs.date, let right = rhs.date else { return lhs.rawValue < rhs.rawValue }
        return left < right
    }
}

enum ProjectPackageMemberRole: String, Codable, Equatable, Sendable {
    case document
    case resource
    case optional
    /// Package v2: an ordered member holding whole pages (OD-032).
    case pages
}

struct ProjectPackageMember: Equatable, Sendable {
    let path: String
    let role: ProjectPackageMemberRole
    let data: Data

    init(path: String, role: ProjectPackageMemberRole = .optional, data: Data) {
        self.path = path
        self.role = role
        self.data = data
    }
}

struct ProjectPackageCompatibility: Codable, Equatable, Sendable {
    let minimumPackageReaderVersion: Int
    let minimumDocumentSchemaVersion: Int

    init(
        minimumPackageReaderVersion: Int = 1,
        minimumDocumentSchemaVersion: Int = 1
    ) {
        self.minimumPackageReaderVersion = minimumPackageReaderVersion
        self.minimumDocumentSchemaVersion = minimumDocumentSchemaVersion
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case minimumPackageReaderVersion, minimumDocumentSchemaVersion
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumPackageReaderVersion = try container.decode(Int.self, forKey: .minimumPackageReaderVersion)
        minimumDocumentSchemaVersion = try container.decode(Int.self, forKey: .minimumDocumentSchemaVersion)
    }
}

/// OD-032 (ADR-0030): package v2 stores a document too large for one member as
/// a small root (`document.json`, whose page list is replaced by `marker`) and
/// ordered page members (`pages/0000.json`, …; role `pages`), each a JSON array
/// of whole pages in the canonical encoding. Joining the members reproduces
/// the exact canonical bytes package v1 would store, so reading reuses the
/// strict document decoder unchanged. Every existing per-member, member-count
/// and file bound still applies.
enum ProjectPackagePageSplit {
    static let marker = Data(#""pages":"app.siteforge.package-v2.pages""#.utf8)
    static let markerValue = "app.siteforge.package-v2.pages"
    static let memberPrefix = "pages/"
    private static let open = Data(#""pages":["#.utf8)
    private static let comma = Data(",".utf8)

    static func memberPath(_ index: Int) -> String { String(format: "pages/%04d.json", index) }

    /// The member index a path names, only in canonical spelling.
    static func memberIndex(_ path: String) -> Int? {
        guard path.hasPrefix(memberPrefix), path.hasSuffix(".json"), path.utf8.count == "pages/0000.json".utf8.count,
              let index = Int(path.dropFirst(memberPrefix.count).dropLast(".json".count)), index >= 0,
              memberPath(index) == path else { return nil }
        return index
    }

    struct Split: Equatable, Sendable {
        let root: Data
        let members: [Data]
        /// The largest single page, in bytes (a page can never be split).
        let largestPageBytes: Int
    }

    /// Packs `pages` (each page's canonical encoding, in order) into members
    /// of at most `memberLimit` bytes. `envelope` must contain the page list
    /// exactly once in that encoding; otherwise nothing is written.
    static func split(envelope: Data, pages: [Data], memberLimit: Int) throws -> Split {
        guard !pages.isEmpty, envelope.range(of: marker) == nil else { throw ProjectPackageError.corruptDocument }
        var list = open
        for (index, page) in pages.enumerated() {
            if index > 0 { list.append(comma) }
            list.append(page)
        }
        list.append(Data("]".utf8))
        guard let range = envelope.range(of: list),
              envelope.range(of: list, in: range.upperBound..<envelope.endIndex) == nil else {
            throw ProjectPackageError.corruptDocument
        }
        var root = envelope
        root.replaceSubrange(range, with: marker)
        var members: [Data] = []
        var current = Data()
        for page in pages {
            guard page.count + 2 <= memberLimit else { throw ProjectPackageError.oversizedInput }
            if !current.isEmpty, current.count + 1 + page.count + 1 > memberLimit {
                current.append(Data("]".utf8))
                members.append(current)
                current = Data()
            }
            current.append(current.isEmpty ? Data("[".utf8) : comma)
            current.append(page)
        }
        current.append(Data("]".utf8))
        members.append(current)
        return .init(root: root, members: members, largestPageBytes: pages.map(\.count).max() ?? 0)
    }

    /// Reassembles the canonical document bytes. The root must hold the
    /// marker exactly once, as the document's page list; every member must be
    /// one non-empty JSON array of objects, so a member cannot close the list
    /// early and inject other document fields.
    static func join(root: Data, members: [Data], checkpoint: () throws -> Void = {}) throws -> Data {
        guard !members.isEmpty, let range = root.range(of: marker),
              root.range(of: marker, in: range.upperBound..<root.endIndex) == nil else {
            throw ProjectPackageError.corruptDocument
        }
        guard let envelope = try? JSONSerialization.jsonObject(with: root) as? [String: Any],
              let document = envelope["document"] as? [String: Any],
              document["pages"] as? String == markerValue else { throw ProjectPackageError.corruptDocument }
        var list = open
        for (index, member) in members.enumerated() {
            try checkpoint()
            guard member.first == UInt8(ascii: "["), member.last == UInt8(ascii: "]"), member.count > 2,
                  let pages = try? JSONSerialization.jsonObject(with: member) as? [Any], !pages.isEmpty,
                  pages.allSatisfy({ $0 is [String: Any] }) else { throw ProjectPackageError.corruptDocument }
            if index > 0 { list.append(comma) }
            list.append(member.dropFirst().dropLast())
        }
        list.append(Data("]".utf8))
        var joined = root
        joined.replaceSubrange(range, with: list)
        return joined
    }
}

/// What one save wrote, for project-file capacity (SF-0301-007).
struct ProjectPackageMeasurement: Equatable, Sendable {
    /// The package file's size.
    let fileBytes: Int
    /// The largest page's canonical size when it was measured (always for
    /// package v2; for v1 only when the document is close to the member
    /// limit); nil means no page is close to the per-page limit.
    let largestPageBytes: Int?
    let packageVersion: Int
}

struct ProjectPackage: Equatable, Sendable {
    /// The newest package version this build reads and writes. Version 1 is
    /// still written whenever the document fits one member (OD-032).
    static let currentPackageVersion = 2
    static let singleMemberPackageVersion = 1

    let projectID: ProjectID
    let createdAt: ProjectTimestamp
    let modifiedAt: ProjectTimestamp
    let document: CanonicalDocument
    let optionalMembers: [ProjectPackageMember]
    let compatibility: ProjectPackageCompatibility

    init(
        projectID: ProjectID = ProjectID(),
        createdAt: ProjectTimestamp = ProjectTimestamp(date: Date()),
        modifiedAt: ProjectTimestamp? = nil,
        document: CanonicalDocument,
        optionalMembers: [ProjectPackageMember] = [],
        compatibility: ProjectPackageCompatibility = ProjectPackageCompatibility()
    ) {
        self.projectID = projectID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.document = document
        self.optionalMembers = optionalMembers
        self.compatibility = compatibility
    }
}

enum ProjectPackageError: Error, Equatable, LocalizedError, Sendable {
    case packageUnavailable
    case packageIsSymbolicLink
    case unsafeDestination
    case fileIdentityChanged
    case unsafeFileMetadata
    case unsafeRecoveryArtifact
    case recoveryDeletionFailed
    case malformedContainer
    case duplicateMember
    case invalidMemberPath
    case missingManifest
    case missingDocument
    case corruptManifest
    case corruptDocument
    case unsupportedPackageVersion(Int)
    case unsupportedDocumentSchema(Int)
    case incompatibleReaderVersion(Int)
    case malformedMetadata
    case undeclaredMember
    case memberIntegrityFailure
    case oversizedInput
    case interrupted
    case ioFailure

    var errorDescription: String? {
        switch self {
        case .packageUnavailable: "The project package is unavailable. Locate it and try again."
        case .packageIsSymbolicLink: "Symbolic-link project packages are not accepted. Choose the original package."
        case .unsafeDestination: "The project destination contains an unsafe symbolic link or unsupported item."
        case .fileIdentityChanged: "The project changed on disk before the operation could commit. Reopen it or use Save As."
        case .unsafeFileMetadata: "The project file has unsupported ownership or security metadata. Choose another location."
        case .unsafeRecoveryArtifact: "The recovery artifact is not owned by this SiteForge project and was preserved."
        case .recoveryDeletionFailed: "The recovery artifact could not be removed. It remains available; correct access and retry."
        case .malformedContainer: "The project package container is malformed. Restore a valid copy."
        case .duplicateMember: "The project package contains a duplicate member."
        case .invalidMemberPath: "The project package contains an unsafe member path."
        case .missingManifest: "The project package manifest is missing."
        case .missingDocument: "The canonical document payload is missing."
        case .corruptManifest: "The project package manifest is corrupt."
        case .corruptDocument: "The canonical document payload is corrupt."
        case .unsupportedPackageVersion(let version): "Project package version \(version) is not supported by this build."
        case .unsupportedDocumentSchema(let version): "Document schema version \(version) is not supported by this build."
        case .incompatibleReaderVersion(let version): "This package requires project reader version \(version) or later."
        case .malformedMetadata: "The project package metadata is invalid."
        case .undeclaredMember: "The project package contains a member that is not declared by its manifest."
        case .memberIntegrityFailure: "A project package member failed its integrity check."
        case .oversizedInput: "The project package exceeds the supported local size limit."
        case .interrupted: "The project write was interrupted before replacement; the previous package is unchanged."
        case .ioFailure: "The project package could not be read or written. Check local access and free space."
        }
    }
}

enum ProjectPackageDiagnosticOperation: String, Equatable, Sendable {
    case read
    case write
}

enum ProjectPackageDiagnosticResult: String, Equatable, Sendable {
    case success
    case failure
}

enum ProjectPackageFailureCategory: String, Equatable, Sendable {
    case validation
    case compatibility
    case integrity
    case security
    case interruption
    case io
}

struct ProjectPackageDiagnosticRecord: Equatable, Sendable {
    let requirementID: String
    let operation: ProjectPackageDiagnosticOperation
    let sanitizedProjectID: String?
    let durationNanoseconds: UInt64
    let result: ProjectPackageDiagnosticResult
    let failureCategory: ProjectPackageFailureCategory?
}

actor ProjectPackageDiagnostics {
    private var buffer: BoundedDiagnosticBuffer<ProjectPackageDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    var records: [ProjectPackageDiagnosticRecord] { buffer.snapshot() }
    func append(_ record: ProjectPackageDiagnosticRecord) { buffer.append(record) }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

enum ProjectPackageWriteInterruption: Sendable {
    case none
    case beforeReplacement
}

struct ValidatedProjectPackageRead: Equatable, Sendable {
    let package: ProjectPackage
    let file: ValidatedPackageFileSnapshot
    let legacyDocumentData: Data?
}

actor ProjectPackageStore {
    static let requirementIDs: Set<String> = [
        "SF-0301-001", "SF-0301-003", "SF-0301-004", "SF-0301-005", "SF-0301-008",
        "SF-0306-003", "SF-0306-004",
        "SF-1504-003", "SF-1504-004",
        "SF-1603-004", "SF-1604-004",
        "SF-1702-001", "SF-1702-004", "SF-1702-008",
    ]

    static let maximumPackageBytes = 8 * 1_024 * 1_024
    static let maximumMemberBytes = 4 * 1_024 * 1_024
    static let maximumMemberCount = 256
    /// A package v1 document this close to the member limit also measures its
    /// largest page, so the capacity warning can name the per-page limit.
    /// Matches `ProjectFileCapacity.warningFraction`.
    static let pageMeasurementFraction = 0.85

    private static let magic = Data("SFPKG001".utf8)
    private static let manifestPath = "manifest.json"
    private static let documentPath = "document.json"
    private let diagnostics: ProjectPackageDiagnostics
    private let fileSystem: IdentityBoundPackageFileSystem
    private let cancellation: CooperativeCancellationCheckpoint

    init(
        diagnostics: ProjectPackageDiagnostics = ProjectPackageDiagnostics(),
        ioObserver: (any ProjectPackageIOObserving)? = nil,
        cancellation: CooperativeCancellationCheckpoint = CooperativeCancellationCheckpoint()
    ) {
        self.diagnostics = diagnostics
        fileSystem = IdentityBoundPackageFileSystem(observer: ioObserver)
        self.cancellation = cancellation
    }

    func encode(_ package: ProjectPackage) async throws -> Data {
        let started = ContinuousClock.now
        do {
            let data = try Self.makeContainer(for: package)
            await record(.write, projectID: package.projectID, started: started, error: nil)
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await record(.write, projectID: package.projectID, started: started, error: error)
            throw error
        }
    }

    func decode(_ data: Data) async throws -> ProjectPackage {
        let started = ContinuousClock.now
        do {
            let package = try Self.parseContainer(data, cancellation: cancellation).package
            await record(.read, projectID: package.projectID, started: started, error: nil)
            return package
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await record(.read, projectID: nil, started: started, error: error)
            throw error
        }
    }

    @discardableResult
    func write(
        _ package: ProjectPackage,
        to destination: URL,
        expected: PackageFingerprint? = nil,
        policy: ProjectPackageArtifactPolicy = .durable,
        interruption: ProjectPackageWriteInterruption = .none
    ) async throws -> PackageFingerprint {
        try await writeMeasured(package, to: destination, expected: expected, policy: policy,
                                interruption: interruption).fingerprint
    }

    /// `write` plus what the written file measures (project-file capacity).
    func writeMeasured(
        _ package: ProjectPackage,
        to destination: URL,
        expected: PackageFingerprint? = nil,
        policy: ProjectPackageArtifactPolicy = .durable,
        interruption: ProjectPackageWriteInterruption = .none
    ) async throws -> (fingerprint: PackageFingerprint, measurement: ProjectPackageMeasurement) {
        let started = ContinuousClock.now
        do {
            if case .recovery(let owner) = policy, owner != package.projectID {
                throw ProjectPackageError.unsafeRecoveryArtifact
            }
            let (data, measurement) = try Self.makeMeasuredContainer(for: package)
            let fingerprint = try await fileSystem.replace(
                bytes: data,
                at: destination,
                expected: expected,
                policy: policy,
                interruption: interruption
            )
            await record(.write, projectID: package.projectID, started: started, error: nil)
            return (fingerprint, measurement)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let typed = Self.mapIOError(error)
            await record(.write, projectID: package.projectID, started: started, error: typed)
            throw typed
        }
    }

    func read(from source: URL) async throws -> ProjectPackage {
        try await readSnapshot(from: source).package
    }

    func readSnapshot(from source: URL) async throws -> ValidatedProjectPackageRead {
        try await readSnapshot(from: source, recoveryOwner: nil, isRecovery: false)
    }

    func readOwnedRecoverySnapshot(
        from source: URL,
        expectedProjectID: ProjectID? = nil
    ) async throws -> ValidatedProjectPackageRead {
        try await readSnapshot(from: source, recoveryOwner: expectedProjectID, isRecovery: true)
    }

    private func readSnapshot(
        from source: URL,
        recoveryOwner: ProjectID?,
        isRecovery: Bool
    ) async throws -> ValidatedProjectPackageRead {
        let started = ContinuousClock.now
        do {
            let file: ValidatedPackageFileSnapshot
            if isRecovery {
                file = try await fileSystem.readOwnedRecoverySnapshot(
                    from: source,
                    maximumBytes: Self.maximumPackageBytes
                )
            } else {
                file = try await fileSystem.readSnapshot(from: source, maximumBytes: Self.maximumPackageBytes)
            }
            let parsed = try Self.parseContainer(file.bytes, cancellation: cancellation)
            let package = parsed.package
            if let recoveryOwner, package.projectID != recoveryOwner {
                throw ProjectPackageError.unsafeRecoveryArtifact
            }
            await record(.read, projectID: package.projectID, started: started, error: nil)
            return ValidatedProjectPackageRead(package: package, file: file,
                                               legacyDocumentData: parsed.legacyDocumentData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let typed = Self.mapIOError(error)
            await record(.read, projectID: nil, started: started, error: typed)
            throw typed
        }
    }

    func prepareRecoveryDirectory(_ directory: URL) throws {
        try fileSystem.prepareOwnedRecoveryDirectory(directory)
    }

    func validateRecoveryDirectory(_ directory: URL) throws {
        try fileSystem.validateOwnedRecoveryDirectory(directory)
    }

    func isRetiredRecoveryTombstone(
        at url: URL,
        projectID: ProjectID
    ) throws -> Bool {
        try fileSystem.isRetiredRecoveryTombstone(
            at: url,
            projectID: projectID,
            maximumBytes: Self.maximumPackageBytes
        )
    }

    func removeOwnedRecovery(
        at url: URL,
        projectID: ProjectID,
        expected: PackageFingerprint? = nil,
        commitAuthorizer: (any ProjectPackageConditionalCommitAuthorizing)? = nil
    ) async throws {
        // The descriptor layer captures a single final bounded snapshot and
        // invokes this closed parser over those exact bytes before its
        // identity-conditional exchange. The caller's project ID therefore
        // cannot relabel a same-fingerprint artifact from another project.
        // This is deliberately not a path re-open: the parser consumes the
        // descriptor-bound snapshot that the delete operation is about to
        // conditionally retire.
        guard let expected else { throw ProjectPackageError.unsafeRecoveryArtifact }
        let cancellation = cancellation
        try await fileSystem.removeOwnedRecovery(
            at: url,
            projectID: projectID,
            expected: expected,
            ownershipValidator: { snapshot in
                let package = try Self.parseContainer(snapshot.bytes, cancellation: cancellation).package
                guard package.projectID == projectID else {
                    throw ProjectPackageError.unsafeRecoveryArtifact
                }
            },
            commitAuthorizer: commitAuthorizer
        )
    }
}

/// Internal (not part of the private extension below) so the lifecycle backend
/// and tests can read the stored document of an accepted container.
extension ProjectPackageStore {
    /// SF-0309: the declared document schema and the stored document bytes
    /// (page members joined for package v2) of a container that
    /// `parseContainer` already accepted, so an upgrade can be reported and the
    /// original kept before anything replaces it.
    static func storedDocument(in data: Data) throws -> (schemaVersion: Int, data: Data) {
        let payloads = try ArchiveCodec.decode(data)
        let byPath = Dictionary(payloads.map { ($0.path, $0.data) }, uniquingKeysWith: { first, _ in first })
        guard let manifestData = byPath[manifestPath] else { throw ProjectPackageError.missingManifest }
        guard let rootData = byPath[documentPath] else { throw ProjectPackageError.missingDocument }
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: manifestData) }
        catch { throw ProjectPackageError.corruptManifest }
        let pageMembers = try pageMemberPaths(in: manifest)
        guard !pageMembers.isEmpty else { return (manifest.documentSchemaVersion, rootData) }
        let members = try pageMembers.map { path -> Data in
            guard let member = byPath[path] else { throw ProjectPackageError.corruptManifest }
            return member
        }
        return (manifest.documentSchemaVersion, try ProjectPackagePageSplit.join(root: rootData, members: members))
    }
}

extension ProjectPackageStore {
    /// Measure the largest page without retaining all encoded pages on open.
    static func largestEncodedPageSize(in document: CanonicalDocument) throws -> Int? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var largest: Int?
        for page in document.pages {
            let size = try encoder.encode(page).count
            largest = max(largest ?? 0, size)
        }
        return largest
    }
}

private extension ProjectPackageStore {
    /// Future package versions may legitimately carry fields this build cannot
    /// understand. Decode only the stable routing header before applying the
    /// closed current-schema manifest contract.
    struct ManifestHeader: Decodable {
        let format: String
        let packageVersion: Int
    }

    struct Manifest: Codable {
        let format: String
        let packageVersion: Int
        let documentSchemaVersion: Int
        let projectID: ProjectID
        let createdAt: ProjectTimestamp
        let modifiedAt: ProjectTimestamp
        let compatibility: ProjectPackageCompatibility
        let members: [MemberDescriptor]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case format, packageVersion, documentSchemaVersion, projectID, createdAt, modifiedAt, compatibility, members
        }

        init(
            format: String,
            packageVersion: Int,
            documentSchemaVersion: Int,
            projectID: ProjectID,
            createdAt: ProjectTimestamp,
            modifiedAt: ProjectTimestamp,
            compatibility: ProjectPackageCompatibility,
            members: [MemberDescriptor]
        ) {
            self.format = format
            self.packageVersion = packageVersion
            self.documentSchemaVersion = documentSchemaVersion
            self.projectID = projectID
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.compatibility = compatibility
            self.members = members
        }

        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            format = try container.decode(String.self, forKey: .format)
            packageVersion = try container.decode(Int.self, forKey: .packageVersion)
            documentSchemaVersion = try container.decode(Int.self, forKey: .documentSchemaVersion)
            projectID = try container.decode(ProjectID.self, forKey: .projectID)
            createdAt = try container.decode(ProjectTimestamp.self, forKey: .createdAt)
            modifiedAt = try container.decode(ProjectTimestamp.self, forKey: .modifiedAt)
            compatibility = try container.decode(ProjectPackageCompatibility.self, forKey: .compatibility)
            members = try container.decode([MemberDescriptor].self, forKey: .members)
        }
    }

    struct MemberDescriptor: Codable, Equatable {
        let path: String
        let role: ProjectPackageMemberRole
        let byteCount: Int
        let sha256: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case path, role, byteCount, sha256 }

        init(path: String, role: ProjectPackageMemberRole, byteCount: Int, sha256: String) {
            self.path = path
            self.role = role
            self.byteCount = byteCount
            self.sha256 = sha256
        }

        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            role = try container.decode(ProjectPackageMemberRole.self, forKey: .role)
            byteCount = try container.decode(Int.self, forKey: .byteCount)
            sha256 = try container.decode(String.self, forKey: .sha256)
        }
    }

    static func makeContainer(for package: ProjectPackage) throws -> Data {
        try makeMeasuredContainer(for: package).data
    }

    /// The container and what it measures, so a caller can report how close
    /// a project is to the file and per-page limits without encoding twice.
    /// A document that fits one member is written as package v1, which older
    /// builds still open; a larger one as package v2 (OD-032, ADR-0030).
    static func makeMeasuredContainer(for package: ProjectPackage) throws -> (data: Data, measurement: ProjectPackageMeasurement) {
        try validateMetadata(package)
        let documentData: Data
        do {
            documentData = try DocumentSerializer.encode(package.document)
        } catch {
            throw ProjectPackageError.corruptDocument
        }

        // Original resource blobs are persisted by ProjectResourceStore in
        // the identity-bound sidecar. Only the canonical index belongs in the
        // bounded project package; transient in-memory blobs must never create
        // a second embedded resource format or exceed package member limits.
        var payloads = package.archiveOptionalMembers
        guard !payloads.contains(where: { $0.role == .pages || $0.path.hasPrefix(ProjectPackagePageSplit.memberPrefix) }) else {
            throw ProjectPackageError.corruptManifest
        }
        let packageVersion: Int
        var largestPageBytes: Int?
        if documentData.count <= maximumMemberBytes {
            packageVersion = ProjectPackage.singleMemberPackageVersion
            payloads.append(ProjectPackageMember(path: documentPath, role: .document, data: documentData))
            if Double(documentData.count) >= Double(maximumMemberBytes) * pageMeasurementFraction {
                largestPageBytes = try encodedPages(of: package.document).map(\.count).max()
            }
        } else {
            packageVersion = ProjectPackage.currentPackageVersion
            let split = try ProjectPackagePageSplit.split(envelope: documentData, pages: try encodedPages(of: package.document),
                                                          memberLimit: maximumMemberBytes)
            payloads.append(ProjectPackageMember(path: documentPath, role: .document, data: split.root))
            for (index, member) in split.members.enumerated() {
                payloads.append(ProjectPackageMember(path: ProjectPackagePageSplit.memberPath(index), role: .pages, data: member))
            }
            largestPageBytes = split.largestPageBytes
        }
        try validatePayloads(payloads)

        let descriptors = payloads
            .map { MemberDescriptor(path: $0.path, role: $0.role, byteCount: $0.data.count, sha256: checksum($0.data)) }
            .sorted { $0.path < $1.path }
        let manifest = Manifest(
            format: "app.siteforge.project-package",
            packageVersion: packageVersion,
            documentSchemaVersion: DocumentSerializer.currentSchemaVersion,
            projectID: package.projectID,
            createdAt: package.createdAt,
            modifiedAt: package.modifiedAt,
            // The written format decides which readers can open it.
            compatibility: ProjectPackageCompatibility(
                minimumPackageReaderVersion: packageVersion,
                minimumDocumentSchemaVersion: package.compatibility.minimumDocumentSchemaVersion
            ),
            members: descriptors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        payloads.append(ProjectPackageMember(path: manifestPath, data: manifestData))
        let data = try ArchiveCodec.encode(payloads)
        return (data, ProjectPackageMeasurement(fileBytes: data.count, largestPageBytes: largestPageBytes,
                                                packageVersion: packageVersion))
    }

    /// Each page in the canonical document encoding (the same encoder
    /// settings as `DocumentSerializer.encode`; `split` verifies the match).
    static func encodedPages(of document: CanonicalDocument) throws -> [Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try document.pages.map { try encoder.encode($0) }
    }

    static func parseContainer(
        _ data: Data,
        cancellation: CooperativeCancellationCheckpoint
    ) throws -> (package: ProjectPackage, legacyDocumentData: Data?) {
        try cancellation.check()
        guard data.count <= maximumPackageBytes else { throw ProjectPackageError.oversizedInput }
        let payloads = try ArchiveCodec.decode(data)
        try cancellation.check()
        let byPath = Dictionary(uniqueKeysWithValues: payloads.map { ($0.path, $0) })
        guard let manifestData = byPath[manifestPath]?.data else { throw ProjectPackageError.missingManifest }
        guard let rootData = byPath[documentPath]?.data else { throw ProjectPackageError.missingDocument }

        let header: ManifestHeader
        do {
            header = try JSONDecoder().decode(ManifestHeader.self, from: manifestData)
        } catch {
            throw ProjectPackageError.corruptManifest
        }
        try cancellation.check()
        guard header.format == "app.siteforge.project-package" else {
            throw ProjectPackageError.corruptManifest
        }
        guard (ProjectPackage.singleMemberPackageVersion...ProjectPackage.currentPackageVersion).contains(header.packageVersion) else {
            throw ProjectPackageError.unsupportedPackageVersion(header.packageVersion)
        }

        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        } catch {
            throw ProjectPackageError.corruptManifest
        }
        guard (DocumentSerializer.minimumSupportedSchemaVersion...DocumentSerializer.currentSchemaVersion)
            .contains(manifest.documentSchemaVersion) else {
            throw ProjectPackageError.unsupportedDocumentSchema(manifest.documentSchemaVersion)
        }
        guard manifest.compatibility.minimumPackageReaderVersion <= ProjectPackage.currentPackageVersion else {
            throw ProjectPackageError.incompatibleReaderVersion(
                manifest.compatibility.minimumPackageReaderVersion
            )
        }
        guard manifest.packageVersion == header.packageVersion else { throw ProjectPackageError.corruptManifest }
        try validateManifestMetadata(manifest)
        try validateDescriptors(manifest.members, payloads: payloads, cancellation: cancellation)
        try cancellation.check()

        // Package v1: `document.json` is the document. Package v2: it is the
        // root, joined with the ordered page members (OD-032).
        let pageMembers = try pageMemberPaths(in: manifest)
        let documentData: Data
        if manifest.packageVersion == ProjectPackage.singleMemberPackageVersion {
            guard pageMembers.isEmpty else { throw ProjectPackageError.corruptManifest }
            documentData = rootData
        } else {
            guard !pageMembers.isEmpty, manifest.compatibility.minimumPackageReaderVersion == manifest.packageVersion else {
                throw ProjectPackageError.corruptManifest
            }
            documentData = try ProjectPackagePageSplit.join(root: rootData,
                members: pageMembers.map { byPath[$0]!.data }, checkpoint: cancellation.check)
        }

        let document: CanonicalDocument
        do {
            let declaredDocumentSchema = try DocumentSerializer.schemaVersion(in: documentData)
            guard declaredDocumentSchema == manifest.documentSchemaVersion else {
                throw ProjectPackageError.corruptManifest
            }
            document = try DocumentSerializer.decode(documentData, checkpoint: cancellation.check)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProjectPackageError {
            throw error
        } catch let error as DocumentSerializationError {
            if case .unsupportedSchema(let version) = error {
                throw ProjectPackageError.unsupportedDocumentSchema(version)
            }
            throw ProjectPackageError.corruptDocument
        } catch {
            throw ProjectPackageError.corruptDocument
        }
        try cancellation.check()
        guard document.id.description.isEmpty == false else { throw ProjectPackageError.malformedMetadata }

        let descriptorByPath = Dictionary(uniqueKeysWithValues: manifest.members.map { ($0.path, $0) })
        let optionalMembers = payloads
            .filter { $0.path != manifestPath && $0.path != documentPath && descriptorByPath[$0.path]!.role != .pages }
            .map { ProjectPackageMember(path: $0.path, role: descriptorByPath[$0.path]!.role, data: $0.data) }
            .sorted { $0.path < $1.path }
        let package = ProjectPackage(
            projectID: manifest.projectID,
            createdAt: manifest.createdAt,
            modifiedAt: manifest.modifiedAt,
            document: document,
            optionalMembers: optionalMembers,
            compatibility: manifest.compatibility
        )
        return (package, manifest.documentSchemaVersion < DocumentSerializer.currentSchemaVersion ? documentData : nil)
    }

    static func validateMetadata(_ package: ProjectPackage) throws {
        guard package.createdAt.date != nil,
              package.modifiedAt.date != nil,
              package.modifiedAt >= package.createdAt,
              package.compatibility.minimumPackageReaderVersion > 0,
              package.compatibility.minimumDocumentSchemaVersion > 0,
              package.compatibility.minimumPackageReaderVersion <= ProjectPackage.currentPackageVersion,
              package.compatibility.minimumDocumentSchemaVersion <= DocumentSerializer.currentSchemaVersion else {
            throw ProjectPackageError.malformedMetadata
        }
    }

    static func validateManifestMetadata(_ manifest: Manifest) throws {
        guard manifest.createdAt.date != nil,
              manifest.modifiedAt.date != nil,
              manifest.modifiedAt >= manifest.createdAt,
              manifest.compatibility.minimumPackageReaderVersion > 0,
              manifest.compatibility.minimumDocumentSchemaVersion > 0,
              manifest.compatibility.minimumPackageReaderVersion <= manifest.packageVersion,
              manifest.compatibility.minimumDocumentSchemaVersion <= manifest.documentSchemaVersion else {
            throw ProjectPackageError.malformedMetadata
        }
        guard manifest.compatibility.minimumDocumentSchemaVersion <= DocumentSerializer.currentSchemaVersion else {
            throw ProjectPackageError.unsupportedDocumentSchema(
                manifest.compatibility.minimumDocumentSchemaVersion
            )
        }
    }

    static func validatePayloads(_ payloads: [ProjectPackageMember]) throws {
        guard payloads.count <= maximumMemberCount else { throw ProjectPackageError.oversizedInput }
        var paths = Set<String>()
        for payload in payloads {
            try validateMemberPath(payload.path)
            guard paths.insert(payload.path).inserted else { throw ProjectPackageError.duplicateMember }
            guard payload.path != manifestPath else { throw ProjectPackageError.duplicateMember }
            guard payload.data.count <= maximumMemberBytes else { throw ProjectPackageError.oversizedInput }
            if payload.path == documentPath {
                guard payload.role == .document else { throw ProjectPackageError.corruptManifest }
            } else {
                guard payload.role != .document else { throw ProjectPackageError.corruptManifest }
            }
        }
    }

    static func validateDescriptors(
        _ descriptors: [MemberDescriptor],
        payloads: [ProjectPackageMember],
        cancellation: CooperativeCancellationCheckpoint
    ) throws {
        guard descriptors.count <= maximumMemberCount else { throw ProjectPackageError.oversizedInput }
        var paths = Set<String>()
        for descriptor in descriptors {
            try cancellation.check()
            try validateMemberPath(descriptor.path)
            guard paths.insert(descriptor.path).inserted else { throw ProjectPackageError.duplicateMember }
            guard descriptor.path != manifestPath else { throw ProjectPackageError.corruptManifest }
            guard descriptor.byteCount >= 0, descriptor.byteCount <= maximumMemberBytes else {
                throw ProjectPackageError.oversizedInput
            }
        }
        let actualPaths = Set(payloads.map(\.path)).subtracting([manifestPath])
        guard paths == actualPaths else { throw ProjectPackageError.undeclaredMember }
        guard let document = descriptors.first(where: { $0.path == documentPath }),
              document.role == .document else { throw ProjectPackageError.missingDocument }
        guard descriptors.filter({ $0.role == .document }).count == 1 else {
            throw ProjectPackageError.corruptManifest
        }
        let payloadByPath = Dictionary(uniqueKeysWithValues: payloads.map { ($0.path, $0.data) })
        for descriptor in descriptors {
            try cancellation.check()
            guard let data = payloadByPath[descriptor.path],
                  data.count == descriptor.byteCount,
                  checksum(data) == descriptor.sha256 else {
                throw ProjectPackageError.memberIntegrityFailure
            }
        }
    }

    /// Package v2 page members in order: exactly `pages/0000.json` … with no
    /// gap, each with role `pages`; no other member may use that role or prefix.
    static func pageMemberPaths(in manifest: Manifest) throws -> [String] {
        var indexed: [Int: String] = [:]
        for descriptor in manifest.members {
            let isPageRole = descriptor.role == .pages
            let index = ProjectPackagePageSplit.memberIndex(descriptor.path)
            guard isPageRole == (index != nil),
                  isPageRole || !descriptor.path.hasPrefix(ProjectPackagePageSplit.memberPrefix) else {
                throw ProjectPackageError.corruptManifest
            }
            if let index { indexed[index] = descriptor.path }
        }
        guard Set(indexed.keys) == Set(0..<indexed.count) else { throw ProjectPackageError.corruptManifest }
        return (0..<indexed.count).compactMap { indexed[$0] }
    }

    static func validateMemberPath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 512,
              !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            throw ProjectPackageError.invalidMemberPath
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProjectPackageError.invalidMemberPath
        }
    }

    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sanitized(_ projectID: ProjectID) -> String {
        DiagnosticStableIdentifier.sanitize(
            projectID.description,
            domain: .projectPackage,
            kind: "project"
        )
    }

    func record(
        _ operation: ProjectPackageDiagnosticOperation,
        projectID: ProjectID?,
        started: ContinuousClock.Instant,
        error: Error?
    ) async {
        let elapsed = started.duration(to: .now)
        let nanoseconds = UInt64(max(0, elapsed.components.seconds)) * 1_000_000_000
            + UInt64(max(0, elapsed.components.attoseconds / 1_000_000_000))
        await diagnostics.append(
            ProjectPackageDiagnosticRecord(
                requirementID: operation == .read ? "SF-0301-004" : "SF-0301-001",
                operation: operation,
                sanitizedProjectID: projectID.map(Self.sanitized),
                durationNanoseconds: nanoseconds,
                result: error == nil ? .success : .failure,
                failureCategory: error.map(Self.failureCategory)
            )
        )
    }

    static func failureCategory(_ error: Error) -> ProjectPackageFailureCategory {
        guard let error = error as? ProjectPackageError else { return .io }
        switch error {
        case .unsupportedPackageVersion, .unsupportedDocumentSchema, .incompatibleReaderVersion:
            return .compatibility
        case .memberIntegrityFailure, .corruptDocument, .corruptManifest:
            return .integrity
        case .invalidMemberPath, .duplicateMember, .packageIsSymbolicLink, .unsafeDestination,
             .fileIdentityChanged, .unsafeFileMetadata, .unsafeRecoveryArtifact,
             .recoveryDeletionFailed:
            return .security
        case .interrupted:
            return .interruption
        case .packageUnavailable, .ioFailure:
            return .io
        default:
            return .validation
        }
    }

    static func mapIOError(_ error: Error) -> ProjectPackageError {
        if let typed = error as? ProjectPackageError { return typed }
        return .ioFailure
    }

    enum ArchiveCodec {
        static func encode(_ members: [ProjectPackageMember]) throws -> Data {
            guard members.count <= maximumMemberCount else { throw ProjectPackageError.oversizedInput }
            let sorted = members.sorted { $0.path < $1.path }
            var data = magic
            data.appendInteger(UInt32(sorted.count))
            for member in sorted {
                let path = Data(member.path.utf8)
                guard path.count <= Int(UInt16.max) else { throw ProjectPackageError.invalidMemberPath }
                data.appendInteger(UInt16(path.count))
                data.appendInteger(UInt64(member.data.count))
                data.append(path)
                data.append(member.data)
            }
            guard data.count <= maximumPackageBytes else { throw ProjectPackageError.oversizedInput }
            return data
        }

        static func decode(_ data: Data) throws -> [ProjectPackageMember] {
            var reader = DataReader(data: data)
            guard try reader.read(count: magic.count) == magic else {
                throw ProjectPackageError.malformedContainer
            }
            let count = Int(try reader.readInteger(UInt32.self))
            guard count <= maximumMemberCount else { throw ProjectPackageError.oversizedInput }
            var paths = Set<String>()
            var members: [ProjectPackageMember] = []
            for _ in 0..<count {
                let pathLength = Int(try reader.readInteger(UInt16.self))
                let memberLength = try reader.readInteger(UInt64.self)
                guard memberLength <= UInt64(maximumMemberBytes),
                      memberLength <= UInt64(Int.max) else { throw ProjectPackageError.oversizedInput }
                let pathData = try reader.read(count: pathLength)
                guard let path = String(data: pathData, encoding: .utf8) else {
                    throw ProjectPackageError.invalidMemberPath
                }
                try validateMemberPath(path)
                guard paths.insert(path).inserted else { throw ProjectPackageError.duplicateMember }
                let payload = try reader.read(count: Int(memberLength))
                members.append(ProjectPackageMember(path: path, data: payload))
            }
            guard reader.isAtEnd else { throw ProjectPackageError.malformedContainer }
            return members
        }
    }

    struct DataReader {
        let data: Data
        var offset = 0

        var isAtEnd: Bool { offset == data.count }

        mutating func read(count: Int) throws -> Data {
            guard count >= 0, offset <= data.count, count <= data.count - offset else {
                throw ProjectPackageError.malformedContainer
            }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let bytes = try read(count: MemoryLayout<T>.size)
            return bytes.reduce(T.zero) { ($0 << 8) | T($1) }
        }
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: (MemoryLayout<T>.size - 1) * 8, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> T(shift)))
        }
    }
}

// MARK: - Local named snapshots (OD-043, SF-1301, ADR-0038)

enum ProjectSnapshotIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "snapshot"
}

typealias ProjectSnapshotID = StableIdentifier<ProjectSnapshotIdentifierDomain>

/// One named snapshot. Its complete canonical document is stored in its own
/// optional package member (`snapshots/<id>.json`), so it is saved, copied by
/// Save As and integrity-checked with the project file like every member.
struct ProjectSnapshotEntry: Codable, Equatable, Identifiable, Sendable {
    let id: ProjectSnapshotID
    let name: String
    let createdAt: ProjectTimestamp
    let documentRevision: UInt64
    let documentSchemaVersion: Int
    let byteCount: Int
    let sha256: String

    init(
        id: ProjectSnapshotID,
        name: String,
        createdAt: ProjectTimestamp,
        documentRevision: UInt64,
        documentSchemaVersion: Int,
        byteCount: Int,
        sha256: String
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.documentRevision = documentRevision
        self.documentSchemaVersion = documentSchemaVersion
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    var memberPath: String { ProjectSnapshotIndex.memberPath(for: id) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, createdAt, documentRevision, documentSchemaVersion, byteCount, sha256
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ProjectSnapshotID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(ProjectTimestamp.self, forKey: .createdAt)
        documentRevision = try container.decode(UInt64.self, forKey: .documentRevision)
        documentSchemaVersion = try container.decode(Int.self, forKey: .documentSchemaVersion)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
    }
}

/// The closed, versioned list of a project's named snapshots, oldest first,
/// stored as the optional member `snapshots/index-v1.json`.
struct ProjectSnapshotIndex: Codable, Equatable, Sendable {
    static let formatIdentifier = "app.siteforge.project-snapshots"
    static let currentVersion = 1
    static let indexMemberPath = "snapshots/index-v1.json"
    static let memberPrefix = "snapshots/"
    /// Named snapshots are never pruned automatically; creation stops here.
    static let maximumCount = 10
    /// All snapshot documents together, so the document keeps most of the file.
    static let maximumTotalBytes = 2 * 1_024 * 1_024
    static let maximumIndexBytes = 64 * 1_024
    static let maximumNameBytes = 256

    static func memberPath(for id: ProjectSnapshotID) -> String { "snapshots/\(id.description).json" }

    let format: String
    let version: Int
    let documentID: DocumentID
    let snapshots: [ProjectSnapshotEntry]

    init(documentID: DocumentID, snapshots: [ProjectSnapshotEntry]) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.documentID = documentID
        self.snapshots = snapshots
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, version, documentID, snapshots
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        documentID = try container.decode(DocumentID.self, forKey: .documentID)
        snapshots = try container.decode([ProjectSnapshotEntry].self, forKey: .snapshots)
    }

    func validate() throws {
        guard format == Self.formatIdentifier else { throw ProjectSnapshotError.corrupt }
        guard version == Self.currentVersion else { throw ProjectSnapshotError.unsupportedVersion(version) }
        guard snapshots.count <= Self.maximumCount else { throw ProjectSnapshotError.corrupt }
        var identities = Set<ProjectSnapshotID>()
        var names = Set<String>()
        var total = 0
        let schemas = DocumentSerializer.minimumSupportedSchemaVersion...DocumentSerializer.currentSchemaVersion
        for entry in snapshots {
            guard identities.insert(entry.id).inserted,
                  names.insert(ProjectSnapshots.nameKey(entry.name)).inserted,
                  (try? ProjectSnapshots.validatedName(entry.name)) == entry.name,
                  entry.createdAt.date != nil,
                  schemas.contains(entry.documentSchemaVersion),
                  entry.byteCount > 0, entry.byteCount <= ProjectPackageStore.maximumMemberBytes,
                  entry.sha256.count == 64, entry.sha256 == entry.sha256.lowercased(),
                  entry.sha256.allSatisfy(\.isHexDigit) else {
                throw ProjectSnapshotError.corrupt
            }
            total += entry.byteCount
        }
        guard total <= Self.maximumTotalBytes else { throw ProjectSnapshotError.corrupt }
    }
}

enum ProjectSnapshotError: Error, Equatable, LocalizedError, Sendable {
    case invalidName
    case duplicateName
    case sameName
    case limitReached
    case storageFull
    case invalidDocument
    case notFound
    case corrupt
    case unsupportedVersion(Int)
    case documentMismatch
    case missingResource
    case unchanged
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a snapshot name of 1–256 UTF-8 bytes without control characters."
        case .duplicateName: "Another snapshot already uses this name. Choose a different name."
        case .sameName: "The snapshot already has this name."
        case .limitReached: "This project already keeps \(ProjectSnapshotIndex.maximumCount) snapshots. Delete one before creating another."
        case .storageFull: "There is not enough room for this snapshot in the project file. Delete an older snapshot first."
        case .invalidDocument: "The current document could not be stored as a snapshot. Nothing changed."
        case .notFound: "This snapshot no longer exists. Refresh the snapshot list."
        case .corrupt: "The project's snapshot storage is damaged. The document is unchanged; delete all snapshots to start a new list."
        case .unsupportedVersion(let version): "Snapshot storage version \(version) is not supported by this build. Snapshots were left unchanged."
        case .documentMismatch: "These snapshots belong to a different document and cannot be used here."
        case .missingResource: "This snapshot uses an image whose original file is no longer in the project. Nothing was restored."
        case .unchanged: "The document already matches this snapshot."
        case .unavailable: "Snapshots are unavailable while the project is being saved, opened or replaced. Try again when it finishes."
        }
    }

    var diagnosticCategory: String {
        switch self {
        case .invalidName: "invalid-name"
        case .duplicateName: "duplicate-name"
        case .sameName: "same-name"
        case .limitReached: "limit-reached"
        case .storageFull: "storage-full"
        case .invalidDocument: "invalid-document"
        case .notFound: "not-found"
        case .corrupt: "corrupt"
        case .unsupportedVersion: "unsupported-version"
        case .documentMismatch: "document-mismatch"
        case .missingResource: "missing-resource"
        case .unchanged: "unchanged"
        case .unavailable: "unavailable"
        }
    }
}

enum ProjectSnapshotOperation: String, Equatable, Sendable {
    case create, rename, delete, restore
    case deleteAll = "delete-all"
}

/// SF-1301-008: no names, document content or raw identifiers.
struct ProjectSnapshotDiagnosticRecord: Equatable, Sendable {
    let requirementID: String
    let operation: ProjectSnapshotOperation
    let sanitizedSnapshotID: String?
    let durationNanoseconds: UInt64
    let result: ProjectPackageDiagnosticResult
    let failureCategory: String?
}

/// Pure snapshot operations over a project package. Each returns a new
/// package and never edits the canonical document; restore is expressed as one
/// ordinary document command, so it is a new undoable head (SF-1301-005).
enum ProjectSnapshots {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-1301-%03d", $0) })
    /// The document, the other members and every snapshot together stay below
    /// this share of the project file limit when a snapshot is created.
    static let packageBudgetFraction = 0.75

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    static func validatedName(_ draft: String) throws -> String {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= ProjectSnapshotIndex.maximumNameBytes,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ProjectSnapshotError.invalidName
        }
        return name
    }

    /// Names are unique without regard to case.
    static func nameKey(_ name: String) -> String { name.lowercased() }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The validated index, or nil when the project has no snapshots. Every
    /// `snapshots/` member must be listed and match its recorded size and hash.
    static func index(in package: ProjectPackage, documentID: DocumentID) throws -> ProjectSnapshotIndex? {
        let members = package.optionalMembers.filter { $0.path.hasPrefix(ProjectSnapshotIndex.memberPrefix) }
        guard let indexMember = members.first(where: { $0.path == ProjectSnapshotIndex.indexMemberPath }) else {
            guard members.isEmpty else { throw ProjectSnapshotError.corrupt }
            return nil
        }
        guard indexMember.role == .optional, indexMember.data.count <= ProjectSnapshotIndex.maximumIndexBytes else {
            throw ProjectSnapshotError.corrupt
        }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: indexMember.data) }
        catch { throw ProjectSnapshotError.corrupt }
        guard header.format == ProjectSnapshotIndex.formatIdentifier else { throw ProjectSnapshotError.corrupt }
        guard header.version == ProjectSnapshotIndex.currentVersion else {
            throw ProjectSnapshotError.unsupportedVersion(header.version)
        }
        let index: ProjectSnapshotIndex
        do { index = try JSONDecoder().decode(ProjectSnapshotIndex.self, from: indexMember.data) }
        catch { throw ProjectSnapshotError.corrupt }
        try index.validate()
        guard index.documentID == documentID else { throw ProjectSnapshotError.documentMismatch }
        let expected = Set(index.snapshots.map(\.memberPath)).union([ProjectSnapshotIndex.indexMemberPath])
        guard Set(members.map(\.path)) == expected, members.count == expected.count else {
            throw ProjectSnapshotError.corrupt
        }
        for entry in index.snapshots {
            guard let member = members.first(where: { $0.path == entry.memberPath }), member.role == .optional,
                  member.data.count == entry.byteCount, digest(member.data) == entry.sha256 else {
                throw ProjectSnapshotError.corrupt
            }
        }
        return index
    }

    static func list(in package: ProjectPackage, documentID: DocumentID) throws -> [ProjectSnapshotEntry] {
        try index(in: package, documentID: documentID)?.snapshots ?? []
    }

    static func creating(
        named draft: String,
        from document: CanonicalDocument,
        in package: ProjectPackage,
        id: ProjectSnapshotID = ProjectSnapshotID(),
        at timestamp: ProjectTimestamp
    ) throws -> (package: ProjectPackage, entry: ProjectSnapshotEntry) {
        let name = try validatedName(draft)
        let existing = try list(in: package, documentID: document.id)
        guard existing.count < ProjectSnapshotIndex.maximumCount else { throw ProjectSnapshotError.limitReached }
        guard !existing.contains(where: { nameKey($0.name) == nameKey(name) }) else {
            throw ProjectSnapshotError.duplicateName
        }
        guard !existing.contains(where: { $0.id == id }) else { throw ProjectSnapshotError.corrupt }
        let data: Data
        do { data = try DocumentSerializer.encode(document) }
        catch { throw ProjectSnapshotError.invalidDocument }
        let snapshotBytes = existing.reduce(0) { $0 + $1.byteCount } + data.count
        let otherBytes = package.archiveOptionalMembers
            .filter { !$0.path.hasPrefix(ProjectSnapshotIndex.memberPrefix) }
            .reduce(0) { $0 + $1.data.count }
        guard data.count <= ProjectPackageStore.maximumMemberBytes,
              snapshotBytes <= ProjectSnapshotIndex.maximumTotalBytes,
              Double(data.count + otherBytes + snapshotBytes)
                <= Double(ProjectPackageStore.maximumPackageBytes) * packageBudgetFraction else {
            throw ProjectSnapshotError.storageFull
        }
        let entry = ProjectSnapshotEntry(
            id: id, name: name, createdAt: timestamp, documentRevision: document.revision,
            documentSchemaVersion: DocumentSerializer.currentSchemaVersion,
            byteCount: data.count, sha256: digest(data)
        )
        let updated = try replacing(existing + [entry], documentID: document.id,
                                    adding: [ProjectPackageMember(path: entry.memberPath, role: .optional, data: data)],
                                    in: package)
        return (updated, entry)
    }

    /// SF-0309: the name of the snapshot that keeps a project's original
    /// document when it is upgraded from an older schema.
    static func migrationBackupName(for schemaVersion: Int) -> String {
        "Before upgrade from schema \(schemaVersion)"
    }

    /// Keeps `storedDocument` (the unchanged bytes of an older-schema
    /// document) as a named snapshot (SF-0309-004). Restoring it decodes it with
    /// the same migrating decoder, so the original stays available to a later,
    /// corrected migration. Same count and size limits as `creating`.
    static func creatingMigrationBackup(
        of storedDocument: Data,
        schemaVersion: Int,
        documentID: DocumentID,
        in package: ProjectPackage,
        id: ProjectSnapshotID = ProjectSnapshotID(),
        at timestamp: ProjectTimestamp
    ) throws -> (package: ProjectPackage, entry: ProjectSnapshotEntry) {
        let name = migrationBackupName(for: schemaVersion)
        let existing = try list(in: package, documentID: documentID)
        guard existing.count < ProjectSnapshotIndex.maximumCount else { throw ProjectSnapshotError.limitReached }
        guard !existing.contains(where: { nameKey($0.name) == nameKey(name) }) else {
            throw ProjectSnapshotError.duplicateName
        }
        guard !existing.contains(where: { $0.id == id }) else { throw ProjectSnapshotError.corrupt }
        guard schemaVersion < DocumentSerializer.currentSchemaVersion,
              (try? DocumentSerializer.schemaVersion(in: storedDocument)) == schemaVersion,
              let original = try? DocumentSerializer.decode(storedDocument), original.id == documentID else {
            throw ProjectSnapshotError.invalidDocument
        }
        let currentBytes = (try? DocumentSerializer.encode(package.document).count) ?? storedDocument.count
        let snapshotBytes = existing.reduce(0) { $0 + $1.byteCount } + storedDocument.count
        let otherBytes = package.archiveOptionalMembers
            .filter { !$0.path.hasPrefix(ProjectSnapshotIndex.memberPrefix) }
            .reduce(0) { $0 + $1.data.count }
        guard storedDocument.count <= ProjectPackageStore.maximumMemberBytes,
              snapshotBytes <= ProjectSnapshotIndex.maximumTotalBytes,
              Double(currentBytes + otherBytes + snapshotBytes)
                <= Double(ProjectPackageStore.maximumPackageBytes) * packageBudgetFraction else {
            throw ProjectSnapshotError.storageFull
        }
        let entry = ProjectSnapshotEntry(
            id: id, name: name, createdAt: timestamp, documentRevision: original.revision,
            documentSchemaVersion: schemaVersion, byteCount: storedDocument.count, sha256: digest(storedDocument)
        )
        let updated = try replacing(existing + [entry], documentID: documentID,
                                    adding: [ProjectPackageMember(path: entry.memberPath, role: .optional, data: storedDocument)],
                                    in: package)
        return (updated, entry)
    }

    static func renaming(
        _ id: ProjectSnapshotID,
        to draft: String,
        documentID: DocumentID,
        in package: ProjectPackage
    ) throws -> ProjectPackage {
        let name = try validatedName(draft)
        var entries = try list(in: package, documentID: documentID)
        guard let position = entries.firstIndex(where: { $0.id == id }) else { throw ProjectSnapshotError.notFound }
        let old = entries[position]
        guard old.name != name else { throw ProjectSnapshotError.sameName }
        guard !entries.contains(where: { $0.id != id && nameKey($0.name) == nameKey(name) }) else {
            throw ProjectSnapshotError.duplicateName
        }
        entries[position] = ProjectSnapshotEntry(
            id: old.id, name: name, createdAt: old.createdAt, documentRevision: old.documentRevision,
            documentSchemaVersion: old.documentSchemaVersion, byteCount: old.byteCount, sha256: old.sha256
        )
        return try replacing(entries, documentID: documentID, adding: [], in: package)
    }

    static func deleting(_ id: ProjectSnapshotID, documentID: DocumentID, in package: ProjectPackage) throws -> ProjectPackage {
        let entries = try list(in: package, documentID: documentID)
        guard entries.contains(where: { $0.id == id }) else { throw ProjectSnapshotError.notFound }
        return try replacing(entries.filter { $0.id != id }, documentID: documentID, adding: [], in: package)
    }

    /// The recovery action for damaged or foreign snapshot storage: removes
    /// every `snapshots/` member and nothing else.
    static func removingAll(in package: ProjectPackage) -> ProjectPackage {
        ProjectPackage(
            projectID: package.projectID, createdAt: package.createdAt, modifiedAt: package.modifiedAt,
            document: package.document,
            optionalMembers: package.optionalMembers.filter { !$0.path.hasPrefix(ProjectSnapshotIndex.memberPrefix) },
            compatibility: package.compatibility
        )
    }

    /// The snapshot's document, decoded by the canonical (migrating) document
    /// decoder, so snapshots written by an older schema stay readable.
    static func document(
        for id: ProjectSnapshotID,
        documentID: DocumentID,
        in package: ProjectPackage,
        checkpoint: () throws -> Void = {}
    ) throws -> CanonicalDocument {
        guard let entry = try list(in: package, documentID: documentID).first(where: { $0.id == id }) else {
            throw ProjectSnapshotError.notFound
        }
        guard let member = package.optionalMembers.first(where: { $0.path == entry.memberPath }) else {
            throw ProjectSnapshotError.corrupt
        }
        let document: CanonicalDocument
        do {
            guard try DocumentSerializer.schemaVersion(in: member.data) == entry.documentSchemaVersion else {
                throw ProjectSnapshotError.corrupt
            }
            document = try DocumentSerializer.decode(member.data, checkpoint: checkpoint)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectSnapshotError.corrupt
        }
        guard document.id == documentID else { throw ProjectSnapshotError.corrupt }
        return document
    }

    /// One grouped command that turns `current` into the snapshot's content.
    /// Only changed parts are replaced. Creation kind, template and revision
    /// stay with the current head; the result is a new revision, never a rewind.
    static func restoreCommand(
        to snapshot: CanonicalDocument,
        from current: CanonicalDocument,
        resources: ProjectResourceIndex?
    ) throws -> DocumentCommand {
        guard snapshot.id == current.id else { throw ProjectSnapshotError.documentMismatch }
        let available = Set(resources?.resources.map(\.id) ?? []).union(current.imageAssets.map(\.resourceID))
        guard snapshot.imageAssets.allSatisfy({ available.contains($0.resourceID) }),
              snapshot.fontAssets.allSatisfy({ available.contains($0.resourceID) || current.fontAssets.contains($0) }),
              snapshot.mediaAssets.allSatisfy({ available.contains($0.resourceID) || current.mediaAssets.contains($0) }) else {
            throw ProjectSnapshotError.missingResource
        }
        let pagesChanged = snapshot.pages != current.pages
        let guidesChanged = snapshot.guides != current.guides
        let assetsChanged = snapshot.imageAssets != current.imageAssets
        var commands: [DocumentCommand] = []
        if pagesChanged {
            commands += current.pages.reversed().map { DocumentCommand.removePage(RemovePageCommand(pageID: $0.id)) }
        }
        if guidesChanged {
            commands += current.guides.reversed().map { DocumentCommand.removeGuide(RemoveGuideCommand(guideID: $0.id)) }
        }
        if assetsChanged {
            commands += current.imageAssets.reversed().map {
                DocumentCommand.removeImageAsset(RemoveImageAssetCommand(assetID: $0.id))
            }
            commands += snapshot.imageAssets.enumerated().map {
                DocumentCommand.insertImageAsset(InsertImageAssetCommand(asset: $0.element, index: $0.offset))
            }
        }
        if guidesChanged {
            commands += snapshot.guides.enumerated().map {
                DocumentCommand.insertGuide(InsertGuideCommand(guide: $0.element, index: $0.offset))
            }
        }
        if pagesChanged {
            commands += snapshot.pages.enumerated().map {
                DocumentCommand.insertPage(InsertPageCommand(page: $0.element, index: $0.offset))
            }
        }
        if snapshot.colorTokens != current.colorTokens {
            commands.append(.setColorTokens(SetColorTokensCommand(tokens: snapshot.colorTokens)))
        }
        // Removing a page also removes its website metadata entry, so the
        // snapshot's metadata is written back whenever pages were replaced.
        if pagesChanged || snapshot.websiteMetadata != current.websiteMetadata {
            commands.append(.setWebsiteMetadata(SetWebsiteMetadataCommand(
                documentID: current.id, metadata: snapshot.websiteMetadata)))
        }
        if snapshot.projectPreferences != current.projectPreferences {
            commands.append(.setProjectPreferences(SetProjectPreferencesCommand(
                documentID: current.id, preferences: snapshot.projectPreferences)))
        }
        // OD-035: collections are restored with the rest of the snapshot.
        if snapshot.collections != current.collections {
            commands.append(.setCollections(SetCollectionsCommand(documentID: current.id, collections: snapshot.collections)))
        }
        // OD-045 / SF-0805: project fonts too.
        if snapshot.fontAssets != current.fontAssets {
            commands.append(.setFontAssets(SetFontAssetsCommand(documentID: current.id, fontAssets: snapshot.fontAssets)))
        }
        // OD-045 / SF-0803: project video and audio files too; the grouped
        // edit is validated as a whole, so restored Images find their files.
        if snapshot.mediaAssets != current.mediaAssets {
            commands.append(.setMediaAssets(SetMediaAssetsCommand(documentID: current.id, mediaAssets: snapshot.mediaAssets)))
        }
        // OD-038 / SF-1007-005: site languages too.
        if snapshot.localization != current.localization {
            commands.append(.setLocalization(SetLocalizationCommand(documentID: current.id, localization: snapshot.localization)))
        }
        guard !commands.isEmpty else { throw ProjectSnapshotError.unchanged }
        return .batch(commands)
    }

    private static func replacing(
        _ entries: [ProjectSnapshotEntry],
        documentID: DocumentID,
        adding added: [ProjectPackageMember],
        in package: ProjectPackage
    ) throws -> ProjectPackage {
        let kept = Set(entries.map(\.memberPath))
        let addedPaths = Set(added.map(\.path))
        var members = package.optionalMembers.filter {
            (!$0.path.hasPrefix(ProjectSnapshotIndex.memberPrefix) || kept.contains($0.path))
                && !addedPaths.contains($0.path)
        }
        members += added
        if !entries.isEmpty {
            let index = ProjectSnapshotIndex(documentID: documentID, snapshots: entries)
            try index.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data: Data
            do { data = try encoder.encode(index) }
            catch { throw ProjectSnapshotError.corrupt }
            guard data.count <= ProjectSnapshotIndex.maximumIndexBytes else { throw ProjectSnapshotError.storageFull }
            members.append(ProjectPackageMember(path: ProjectSnapshotIndex.indexMemberPath, role: .optional, data: data))
        }
        return ProjectPackage(
            projectID: package.projectID, createdAt: package.createdAt, modifiedAt: package.modifiedAt,
            document: package.document, optionalMembers: members.sorted { $0.path < $1.path },
            compatibility: package.compatibility
        )
    }
}

// MARK: - Version comparison (OD-043, SF-1306, ADR-0040)

/// One side of a comparison: a named snapshot, or (without a snapshot) the
/// current document, the head.
struct ProjectComparisonSource: Equatable, Sendable {
    static let currentDocumentName = "Current Document"

    let snapshotID: ProjectSnapshotID?
    let name: String
    let document: CanonicalDocument

    init(snapshotID: ProjectSnapshotID?, name: String, document: CanonicalDocument) {
        self.snapshotID = snapshotID
        self.name = name
        self.document = document
    }

    /// Reads one side from an immutable copy of the project package, so it can
    /// run off the main actor. `nil` is the head.
    static func resolve(
        _ id: ProjectSnapshotID?,
        head: CanonicalDocument,
        package: ProjectPackage,
        checkpoint: () throws -> Void = {}
    ) throws -> ProjectComparisonSource {
        guard let id else {
            return ProjectComparisonSource(snapshotID: nil, name: currentDocumentName, document: head)
        }
        guard let entry = try ProjectSnapshots.list(in: package, documentID: head.id).first(where: { $0.id == id }) else {
            throw ProjectSnapshotError.notFound
        }
        let document = try ProjectSnapshots.document(for: id, documentID: head.id, in: package, checkpoint: checkpoint)
        return ProjectComparisonSource(snapshotID: id, name: entry.name, document: document)
    }
}

enum ProjectComparisonArea: String, CaseIterable, Identifiable, Sendable {
    case pages
    case layers
    case properties
    case images
    case guides
    case colorTokens = "color-tokens"
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pages: "Pages"
        case .layers: "Layers"
        case .properties: "Properties"
        case .images: "Images"
        case .guides: "Guides"
        case .colorTokens: "Color Tokens"
        case .settings: "Settings"
        }
    }
}

enum ProjectComparisonChangeKind: String, CaseIterable, Identifiable, Sendable {
    case added
    case removed
    case changed
    case moved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .added: "Added"
        case .removed: "Removed"
        case .changed: "Changed"
        case .moved: "Moved"
        }
    }

    var symbol: String {
        switch self {
        case .added: "plus.circle"
        case .removed: "minus.circle"
        case .changed: "pencil.circle"
        case .moved: "arrow.up.arrow.down.circle"
        }
    }
}

/// One difference. `id` is its position in the comparison, so it is unique
/// and deterministic for the same two versions.
struct ProjectComparisonChange: Identifiable, Equatable, Sendable {
    let id: Int
    let area: ProjectComparisonArea
    let kind: ProjectComparisonChangeKind
    let pageID: PageID?
    let nodeID: NodeID?
    /// Where the change is: the page and layer, the image or the token; empty
    /// for project-wide settings.
    let location: String
    /// What changed: "Page", "Layer name", a property key, …
    let subject: String
    let before: String?
    let after: String?

    var summary: String {
        var text = "\(kind.title) \(subject)"
        if !location.isEmpty { text += " — \(location)" }
        switch (before, after) {
        case let (old?, new?): text += ": \(old) → \(new)"
        case let (old?, nil): text += ": \(old)"
        case let (nil, new?): text += ": \(new)"
        case (nil, nil): break
        }
        return text
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || summary.localizedCaseInsensitiveContains(needle)
    }
}

/// SF-1306-008: timing and counts only; no names, values or identifiers.
struct ProjectComparisonDiagnosticRecord: Equatable, Sendable {
    let requirementID: String
    let durationNanoseconds: UInt64
    let changeCount: Int
    let isTruncated: Bool
    let result: ProjectPackageDiagnosticResult
    let failureCategory: String?
}

struct ProjectComparison: Equatable, Sendable {
    let baselineName: String
    let targetName: String
    let baselineSnapshotID: ProjectSnapshotID?
    let targetSnapshotID: ProjectSnapshotID?
    let baselineRevision: UInt64
    let targetRevision: UInt64
    let changes: [ProjectComparisonChange]
    /// The list stopped at `ProjectComparer.maximumChanges`.
    let isTruncated: Bool

    var isIdentical: Bool { changes.isEmpty && !isTruncated }

    func count(of kind: ProjectComparisonChangeKind) -> Int {
        changes.reduce(0) { $0 + ($1.kind == kind ? 1 : 0) }
    }

    func filtered(
        area: ProjectComparisonArea? = nil,
        kind: ProjectComparisonChangeKind? = nil,
        query: String = ""
    ) -> [ProjectComparisonChange] {
        changes.filter { change in
            (area == nil || change.area == area) && (kind == nil || change.kind == kind) && change.matches(query)
        }
    }

    var countSummary: String {
        guard !changes.isEmpty else { return "No differences" }
        let parts = ProjectComparisonChangeKind.allCases.compactMap { kind -> String? in
            let value = count(of: kind)
            return value == 0 ? nil : "\(value) \(kind.title.lowercased())"
        }
        let total = "\(changes.count) \(changes.count == 1 ? "change" : "changes") (\(parts.joined(separator: ", ")))"
        return isTruncated ? total + "; only the first \(ProjectComparer.maximumChanges) are listed" : total
    }

    /// The exported review report (Markdown), grouped by area.
    func report() -> String {
        var lines = [
            "# SiteForge version comparison",
            "",
            "- Baseline: \(baselineName) (revision \(baselineRevision))",
            "- Compared with: \(targetName) (revision \(targetRevision))",
            "- Mode: structural (pages, layers, properties, images, guides, color tokens, settings), matched by identity; no rendering, so no viewport, data or font context applies.",
            "- Result: \(countSummary)",
        ]
        for area in ProjectComparisonArea.allCases {
            let items = changes.filter { $0.area == area }
            guard !items.isEmpty else { continue }
            lines += ["", "## \(area.title)", ""]
            lines += items.map { "- " + $0.summary }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum ProjectComparisonError: Error, Equatable, LocalizedError, Sendable {
    case documentMismatch
    case sameSource

    var errorDescription: String? {
        switch self {
        case .documentMismatch: "These versions belong to different documents and cannot be compared."
        case .sameSource: "Choose two different versions to compare."
        }
    }

    var diagnosticCategory: String {
        switch self {
        case .documentMismatch: "document-mismatch"
        case .sameSource: "same-source"
        }
    }
}

/// SF-1306 structural comparison. Pure and deterministic. Objects are matched
/// by stable identity only: an object that changed place is reported as moved,
/// one that was re-created (new identity) as removed plus added. Names and
/// property keys never match objects.
enum ProjectComparer {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-1306-%03d", $0) })
    static let maximumChanges = 5_000
    static let maximumValueCharacters = 160

    private struct Collector {
        var changes: [ProjectComparisonChange] = []
        var isTruncated = false

        mutating func add(
            _ area: ProjectComparisonArea,
            _ kind: ProjectComparisonChangeKind,
            pageID: PageID? = nil,
            nodeID: NodeID? = nil,
            location: String = "",
            subject: String,
            before: String? = nil,
            after: String? = nil
        ) {
            guard changes.count < ProjectComparer.maximumChanges else {
                isTruncated = true
                return
            }
            changes.append(ProjectComparisonChange(
                id: changes.count, area: area, kind: kind, pageID: pageID, nodeID: nodeID,
                location: location, subject: subject, before: before, after: after
            ))
        }
    }

    static func compare(
        _ baseline: ProjectComparisonSource,
        with target: ProjectComparisonSource,
        checkpoint: () throws -> Void = {}
    ) throws -> ProjectComparison {
        let old = baseline.document
        let new = target.document
        guard old.id == new.id else { throw ProjectComparisonError.documentMismatch }
        try checkpoint()
        var collector = Collector()
        try comparePages(old, new, into: &collector, checkpoint: checkpoint)
        try checkpoint()
        compareImages(old, new, into: &collector)
        compareGuides(old, new, into: &collector)
        compareColorTokens(old, new, into: &collector)
        if old.websiteMetadata != new.websiteMetadata {
            collector.add(.settings, .changed, subject: "Website and page settings")
        }
        let oldPreferences = old.projectPreferences
        let newPreferences = new.projectPreferences
        if oldPreferences?.gridVisibleOnOpen != newPreferences?.gridVisibleOnOpen
            || oldPreferences?.gridSpacing != newPreferences?.gridSpacing {
            collector.add(.settings, .changed, subject: "Project preferences")
        }
        // ADR-0122: build settings are stored with the preferences but are
        // named on their own.
        if oldPreferences?.build != newPreferences?.build {
            collector.add(.settings, .changed, subject: "Build settings")
        }
        if old.collections != new.collections {
            collector.add(.settings, .changed, subject: "Collections")
        }
        if old.localization != new.localization {
            collector.add(.settings, .changed, subject: "Languages")
        }
        if old.fontAssets != new.fontAssets {
            collector.add(.settings, .changed, subject: "Project fonts")
        }
        if old.mediaAssets != new.mediaAssets {
            collector.add(.settings, .changed, subject: "Video and audio files")
        }
        // Never hide a difference: project data without its own comparison
        // is still named once.
        if !sameUncomparedContent(old, new) {
            collector.add(.settings, .changed, subject: "Other project data")
        } else if collector.changes.isEmpty {
            // Safety net: a difference no entry describes (for example only
            // the stored order of a page's layer list) is still never
            // "identical".
            var aligned = new
            aligned.revision = old.revision
            if aligned != old { collector.add(.settings, .changed, subject: "Other project data") }
        }
        return ProjectComparison(
            baselineName: baseline.name, targetName: target.name,
            baselineSnapshotID: baseline.snapshotID, targetSnapshotID: target.snapshotID,
            baselineRevision: old.revision, targetRevision: new.revision,
            changes: collector.changes, isTruncated: collector.isTruncated
        )
    }

    /// Equal in everything the comparison does not list on its own. The
    /// revision counter, which every save advances, is ignored.
    static func sameUncomparedContent(_ old: CanonicalDocument, _ new: CanonicalDocument) -> Bool {
        var aligned = new
        aligned.revision = old.revision
        aligned.pages = old.pages
        aligned.imageAssets = old.imageAssets
        aligned.guides = old.guides
        aligned.colorTokens = old.colorTokens
        aligned.websiteMetadata = old.websiteMetadata
        aligned.projectPreferences = old.projectPreferences
        aligned.collections = old.collections
        aligned.fontAssets = old.fontAssets
        aligned.localization = old.localization
        aligned.mediaAssets = old.mediaAssets
        return aligned == old
    }

    /// Identifiers present in both orders that are outside one longest run kept
    /// in the same relative order. Inserting or removing an object never marks
    /// its neighbours as moved, and the result is deterministic.
    static func movedIdentifiers<ID: Hashable>(from old: [ID], to new: [ID]) -> Set<ID> {
        let newSet = Set(new)
        var position: [ID: Int] = [:]
        for id in old where newSet.contains(id) && position[id] == nil {
            position[id] = position.count
        }
        let common = new.filter { position[$0] != nil }
        let sequence = common.compactMap { position[$0] }
        var tails: [Int] = []
        var previous = [Int](repeating: -1, count: sequence.count)
        for (index, value) in sequence.enumerated() {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if sequence[tails[middle]] < value { low = middle + 1 } else { high = middle }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var kept = Set<Int>()
        var cursor = tails.last ?? -1
        while cursor >= 0 {
            kept.insert(cursor)
            cursor = previous[cursor]
        }
        var moved = Set<ID>()
        for (index, id) in common.enumerated() where !kept.contains(index) { moved.insert(id) }
        return moved
    }

    static func valueText(_ value: PropertyValue) -> String {
        switch value {
        case .string(let text):
            return "\"\(clipped(text))\""
        case .number(let number):
            if number.isFinite, number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
            return String(number)
        case .boolean(let flag):
            return flag ? "true" : "false"
        }
    }

    /// Control characters become spaces; long text ends with an ellipsis.
    static func clipped(_ text: String) -> String {
        var flat = ""
        flat.unicodeScalars.append(contentsOf: text.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : $0
        })
        guard flat.count > maximumValueCharacters else { return flat }
        return String(flat.prefix(maximumValueCharacters)) + "…"
    }

    private static func propertyText(_ property: NodeProperty) -> String {
        valueText(property.value) + (property.origin == .defaulted ? " (default)" : "")
    }

    private static func pageNoun(_ page: DocumentPage) -> String {
        page.role == .componentDefinition ? "Component" : "Page"
    }

    private static func pageLabel(_ page: DocumentPage) -> String {
        page.role == .componentDefinition ? clipped(page.name) : "\(clipped(page.name)) (\(clipped(page.route.rawValue)))"
    }

    private static func layerNoun(_ node: DocumentNode) -> String {
        node.kind.rawValue.capitalized + " layer"
    }

    private static func layerName(_ node: DocumentNode) -> String {
        node.name.isEmpty ? node.kind.rawValue.capitalized : clipped(node.name)
    }

    private static func containerName(_ parent: NodeParent, nodes: [NodeID: DocumentNode]) -> String {
        switch parent {
        case .page: return "Page"
        case .node(let id): return nodes[id].map { layerName($0) } ?? "Missing layer"
        }
    }

    private static func comparePages(
        _ old: CanonicalDocument,
        _ new: CanonicalDocument,
        into collector: inout Collector,
        checkpoint: () throws -> Void
    ) throws {
        let oldPages = Dictionary(old.pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newPages = Dictionary(new.pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for page in old.pages where newPages[page.id] == nil {
            collector.add(.pages, .removed, pageID: page.id, subject: pageNoun(page), before: pageLabel(page))
        }
        let moved = movedIdentifiers(from: old.pages.map(\.id), to: new.pages.map(\.id))
        for page in new.pages {
            try checkpoint()
            guard let previous = oldPages[page.id] else {
                collector.add(.pages, .added, pageID: page.id, subject: pageNoun(page), after: pageLabel(page))
                continue
            }
            let location = clipped(page.name)
            if moved.contains(page.id) {
                collector.add(.pages, .moved, pageID: page.id, location: location, subject: "\(pageNoun(page)) order")
            }
            if previous.name != page.name {
                collector.add(.pages, .changed, pageID: page.id, location: location, subject: "\(pageNoun(page)) name",
                              before: clipped(previous.name), after: clipped(page.name))
            }
            if previous.route != page.route {
                collector.add(.pages, .changed, pageID: page.id, location: location, subject: "Route",
                              before: clipped(previous.route.rawValue), after: clipped(page.route.rawValue))
            }
            if previous.role != page.role {
                collector.add(.pages, .changed, pageID: page.id, location: location, subject: "Page role",
                              before: previous.role.rawValue, after: page.role.rawValue)
            }
            // Named on its own so it is never hidden behind other changes.
            if previous.provenance != page.provenance {
                collector.add(.pages, .changed, pageID: page.id, location: location, subject: "Page origin",
                              before: previous.provenance.rawValue, after: page.provenance.rawValue)
            }
            try compareNodes(previous, page, into: &collector, checkpoint: checkpoint)
        }
    }

    private static func compareNodes(
        _ old: DocumentPage,
        _ new: DocumentPage,
        into collector: inout Collector,
        checkpoint: () throws -> Void
    ) throws {
        guard old.nodes != new.nodes || old.rootNodeIDs != new.rootNodeIDs else { return }
        let oldNodes = Dictionary(old.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newNodes = Dictionary(new.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pageName = clipped(new.name)
        for (offset, node) in old.nodes.enumerated() where newNodes[node.id] == nil {
            if offset % 256 == 0 { try checkpoint() }
            collector.add(.layers, .removed, pageID: new.id, nodeID: node.id, location: pageName,
                          subject: layerNoun(node), before: layerName(node))
        }
        // Reordered siblings are judged per container; a node that changed
        // container is reported once, as moved to another container.
        var reordered = movedIdentifiers(from: old.rootNodeIDs, to: new.rootNodeIDs)
        for node in new.nodes {
            guard let previous = oldNodes[node.id], previous.childIDs != node.childIDs else { continue }
            reordered.formUnion(movedIdentifiers(from: previous.childIDs, to: node.childIDs))
        }
        for (offset, node) in new.nodes.enumerated() {
            if offset % 256 == 0 { try checkpoint() }
            guard let previous = oldNodes[node.id] else {
                collector.add(.layers, .added, pageID: new.id, nodeID: node.id, location: pageName,
                              subject: layerNoun(node), after: layerName(node))
                continue
            }
            guard previous != node || reordered.contains(node.id) else { continue }
            let location = "\(pageName) › \(layerName(node))"
            if previous.parent != node.parent {
                collector.add(.layers, .moved, pageID: new.id, nodeID: node.id, location: location, subject: "Container",
                              before: containerName(previous.parent, nodes: oldNodes),
                              after: containerName(node.parent, nodes: newNodes))
            } else if reordered.contains(node.id) {
                collector.add(.layers, .moved, pageID: new.id, nodeID: node.id, location: location, subject: "Layer order")
            }
            if previous.name != node.name {
                collector.add(.layers, .changed, pageID: new.id, nodeID: node.id, location: location, subject: "Layer name",
                              before: layerName(previous), after: layerName(node))
            }
            if previous.kind != node.kind {
                collector.add(.layers, .changed, pageID: new.id, nodeID: node.id, location: location, subject: "Layer type",
                              before: previous.kind.rawValue, after: node.kind.rawValue)
            }
            if previous.properties != node.properties {
                compareProperties(previous, node, pageID: new.id, location: location, into: &collector)
            }
        }
    }

    /// Property order is not compared; it carries no authored meaning.
    private static func compareProperties(
        _ old: DocumentNode,
        _ new: DocumentNode,
        pageID: PageID,
        location: String,
        into collector: inout Collector
    ) {
        let previous = Dictionary(old.properties.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Set(new.properties.map(\.id))
        for property in old.properties where !current.contains(property.id) {
            collector.add(.properties, .removed, pageID: pageID, nodeID: new.id, location: location,
                          subject: property.key.rawValue, before: propertyText(property))
        }
        for property in new.properties {
            guard let earlier = previous[property.id] else {
                collector.add(.properties, .added, pageID: pageID, nodeID: new.id, location: location,
                              subject: property.key.rawValue, after: propertyText(property))
                continue
            }
            guard earlier != property else { continue }
            let subject = earlier.key == property.key
                ? property.key.rawValue
                : "\(earlier.key.rawValue) → \(property.key.rawValue)"
            collector.add(.properties, .changed, pageID: pageID, nodeID: new.id, location: location,
                          subject: subject, before: propertyText(earlier), after: propertyText(property))
        }
    }

    private static func compareImages(_ old: CanonicalDocument, _ new: CanonicalDocument, into collector: inout Collector) {
        let previous = Dictionary(old.imageAssets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Set(new.imageAssets.map(\.id))
        func size(_ asset: ImageAsset) -> String {
            "\(asset.pixelWidth)×\(asset.pixelHeight) \(String(describing: asset.format))"
        }
        for asset in old.imageAssets where !current.contains(asset.id) {
            collector.add(.images, .removed, subject: "Image", before: clipped(asset.displayName))
        }
        // The image list order is project data too (Images panel order).
        let moved = movedIdentifiers(from: old.imageAssets.map(\.id), to: new.imageAssets.map(\.id))
        for asset in new.imageAssets {
            guard let earlier = previous[asset.id] else {
                collector.add(.images, .added, subject: "Image", after: clipped(asset.displayName))
                continue
            }
            if moved.contains(asset.id) {
                collector.add(.images, .moved, location: clipped(asset.displayName), subject: "Image order")
            }
            guard earlier != asset else { continue }
            let location = clipped(asset.displayName)
            var described = false
            if earlier.displayName != asset.displayName {
                collector.add(.images, .changed, location: location, subject: "Image name",
                              before: clipped(earlier.displayName), after: location)
                described = true
            }
            if earlier.contentHash != asset.contentHash {
                collector.add(.images, .changed, location: location, subject: "Image file",
                              before: size(earlier), after: size(asset))
                described = true
            }
            if !described {
                collector.add(.images, .changed, location: location, subject: "Image details")
            }
        }
    }

    private static func compareGuides(_ old: CanonicalDocument, _ new: CanonicalDocument, into collector: inout Collector) {
        let pageNames = Dictionary((old.pages + new.pages).map { ($0.id, $0.name) }, uniquingKeysWith: { _, latest in latest })
        let previous = Dictionary(old.guides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Set(new.guides.map(\.id))
        func label(_ guide: AuthoredGuide) -> String {
            "\(guide.axis.rawValue) at \(valueText(.number(guide.position)))"
        }
        func location(_ guide: AuthoredGuide) -> String { clipped(pageNames[guide.pageID] ?? "") }
        for guide in old.guides where !current.contains(guide.id) {
            collector.add(.guides, .removed, pageID: guide.pageID, location: location(guide), subject: "Guide",
                          before: label(guide))
        }
        let moved = movedIdentifiers(from: old.guides.map(\.id), to: new.guides.map(\.id))
        for guide in new.guides {
            guard let earlier = previous[guide.id] else {
                collector.add(.guides, .added, pageID: guide.pageID, location: location(guide), subject: "Guide",
                              after: label(guide))
                continue
            }
            if moved.contains(guide.id) {
                collector.add(.guides, .moved, pageID: guide.pageID, location: location(guide), subject: "Guide order")
            }
            guard earlier != guide else { continue }
            collector.add(.guides, .changed, pageID: guide.pageID, location: location(guide), subject: "Guide",
                          before: label(earlier), after: label(guide))
        }
    }

    private static func compareColorTokens(_ old: CanonicalDocument, _ new: CanonicalDocument, into collector: inout Collector) {
        let previous = Dictionary(old.colorTokens.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Set(new.colorTokens.map(\.id))
        func color(_ token: LocalColorToken) -> String {
            hex(token.color) + (token.darkColor.map { " / dark " + hex($0) } ?? "")
        }
        for token in old.colorTokens where !current.contains(token.id) {
            collector.add(.colorTokens, .removed, subject: "Color token", before: "\(clipped(token.name)) \(color(token))")
        }
        // Token order is the swatch order authors arranged.
        let moved = movedIdentifiers(from: old.colorTokens.map(\.id), to: new.colorTokens.map(\.id))
        for token in new.colorTokens {
            guard let earlier = previous[token.id] else {
                collector.add(.colorTokens, .added, subject: "Color token", after: "\(clipped(token.name)) \(color(token))")
                continue
            }
            let location = clipped(token.name)
            if moved.contains(token.id) {
                collector.add(.colorTokens, .moved, location: location, subject: "Token order")
            }
            if earlier.name != token.name {
                collector.add(.colorTokens, .changed, location: location, subject: "Token name",
                              before: clipped(earlier.name), after: location)
            }
            if earlier.color != token.color || earlier.darkColor != token.darkColor {
                collector.add(.colorTokens, .changed, location: location, subject: "Token color",
                              before: color(earlier), after: color(token))
            }
        }
    }

    private static func hex(_ color: CanonicalSolidColor) -> String {
        func pair(_ value: Double) -> String {
            let byte = Int((min(1, max(0, value.isFinite ? value : 0)) * 255).rounded())
            return (byte < 16 ? "0" : "") + String(byte, radix: 16, uppercase: true)
        }
        let base = "#" + pair(color.red) + pair(color.green) + pair(color.blue)
        guard color.alpha < 1 else { return base }
        return base + " \(Int((min(1, max(0, color.alpha.isFinite ? color.alpha : 0)) * 100).rounded()))%"
    }
}

// MARK: - Shared component libraries (OD-046, SF-0906, ADR-0041)

enum ComponentLibraryIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-library"
}

typealias ComponentLibraryID = StableIdentifier<ComponentLibraryIdentifierDomain>

/// A semantic version `major.minor.patch`: ASCII digits, no leading zeros,
/// no pre-release or build suffix.
struct ComponentLibraryVersion: Codable, Hashable, Comparable, CustomStringConvertible, Sendable {
    static let initial = ComponentLibraryVersion(major: 1, minor: 0, patch: 0)
    static let maximumComponent = 999_999

    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 6, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part == "0" || part.first != "0", let value = Int(part) else { return nil }
            values.append(value)
        }
        self.init(major: values[0], minor: values[1], patch: values[2])
    }

    var description: String { "\(major).\(minor).\(patch)" }

    /// The suggested next export: the next minor version.
    var nextMinor: ComponentLibraryVersion {
        minor < Self.maximumComponent ? .init(major: major, minor: minor + 1, patch: 0) : .init(major: major + 1, minor: 0, patch: 0)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Self(raw), value.description == raw else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a major.minor.patch version")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// An exported library file (JSON). Its content is a complete canonical
/// carrier document (`DocumentSerializer` encoding, base64 in JSON) whose
/// component definitions and color tokens are the library, so it is validated
/// and migrated by the same code as a project document.
struct ComponentLibraryFile: Codable, Equatable, Sendable {
    static let formatIdentifier = "app.siteforge.component-library"
    static let currentVersion = 1
    static let maximumBytes = ProjectPackageStore.maximumMemberBytes

    let format: String
    let version: Int
    let libraryID: ComponentLibraryID
    let name: String
    let libraryVersion: ComponentLibraryVersion
    let exportedAt: ProjectTimestamp
    let document: Data

    init(libraryID: ComponentLibraryID, name: String, libraryVersion: ComponentLibraryVersion,
         exportedAt: ProjectTimestamp, document: Data) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.libraryID = libraryID
        self.name = name
        self.libraryVersion = libraryVersion
        self.exportedAt = exportedAt
        self.document = document
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, version, libraryID, name, libraryVersion, exportedAt, document
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        libraryID = try container.decode(ComponentLibraryID.self, forKey: .libraryID)
        name = try container.decode(String.self, forKey: .name)
        libraryVersion = try container.decode(ComponentLibraryVersion.self, forKey: .libraryVersion)
        exportedAt = try container.decode(ProjectTimestamp.self, forKey: .exportedAt)
        document = try container.decode(Data.self, forKey: .document)
    }
}

/// The definitions and color tokens of one library, in document order.
struct ComponentLibraryContent: Equatable, Sendable {
    let definitions: [DocumentPage]
    let colorTokens: [LocalColorToken]

    var isEmpty: Bool { definitions.isEmpty && colorTokens.isEmpty }

    private struct DigestBody: Encodable {
        let definitions: [DocumentPage]
        let colorTokens: [LocalColorToken]
    }

    /// Order-independent content digest (moving a component in the list does
    /// not change it).
    func digest() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = DigestBody(
            definitions: definitions.sorted { $0.id.description < $1.id.description },
            colorTokens: colorTokens.sorted { $0.id.description < $1.id.description }
        )
        return ProjectSnapshots.digest((try? encoder.encode(body)) ?? Data())
    }

    /// The same content as a document, for `ProjectComparer`.
    func comparisonDocument(id: DocumentID) -> CanonicalDocument {
        CanonicalDocument(id: id, pages: definitions, colorTokens: colorTokens)
    }
}

/// What this project last exported, so the next export keeps the library's
/// identity and must have a higher version.
struct ComponentLibraryPublication: Codable, Equatable, Sendable {
    let libraryID: ComponentLibraryID
    let name: String
    let version: ComponentLibraryVersion

    init(libraryID: ComponentLibraryID, name: String, version: ComponentLibraryVersion) {
        self.libraryID = libraryID
        self.name = name
        self.version = version
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case libraryID, name, version }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        libraryID = try container.decode(ComponentLibraryID.self, forKey: .libraryID)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(ComponentLibraryVersion.self, forKey: .version)
    }
}

struct ComponentLibraryKnownVersion: Codable, Equatable, Sendable {
    let version: ComponentLibraryVersion
    let contentDigest: String

    init(version: ComponentLibraryVersion, contentDigest: String) {
        self.version = version
        self.contentDigest = contentDigest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case version, contentDigest }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(ComponentLibraryVersion.self, forKey: .version)
        contentDigest = try container.decode(String.self, forKey: .contentDigest)
    }
}

/// One imported library: a read-only copy of its definitions and tokens.
/// `knownVersions` (oldest first, at most 16) lets the status tell which
/// version the document holds after Undo of an update.
struct ComponentLibraryImport: Codable, Equatable, Identifiable, Sendable {
    let libraryID: ComponentLibraryID
    let name: String
    let version: ComponentLibraryVersion
    let importedAt: ProjectTimestamp
    let definitionIDs: [PageID]
    let tokenIDs: [ColorTokenID]
    let knownVersions: [ComponentLibraryKnownVersion]

    var id: ComponentLibraryID { libraryID }

    init(libraryID: ComponentLibraryID, name: String, version: ComponentLibraryVersion, importedAt: ProjectTimestamp,
         definitionIDs: [PageID], tokenIDs: [ColorTokenID], knownVersions: [ComponentLibraryKnownVersion]) {
        self.libraryID = libraryID
        self.name = name
        self.version = version
        self.importedAt = importedAt
        self.definitionIDs = definitionIDs
        self.tokenIDs = tokenIDs
        self.knownVersions = knownVersions
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case libraryID, name, version, importedAt, definitionIDs, tokenIDs, knownVersions
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        libraryID = try container.decode(ComponentLibraryID.self, forKey: .libraryID)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(ComponentLibraryVersion.self, forKey: .version)
        importedAt = try container.decode(ProjectTimestamp.self, forKey: .importedAt)
        definitionIDs = try container.decode([PageID].self, forKey: .definitionIDs)
        tokenIDs = try container.decode([ColorTokenID].self, forKey: .tokenIDs)
        knownVersions = try container.decode([ComponentLibraryKnownVersion].self, forKey: .knownVersions)
    }
}

/// The closed, versioned record of a project's libraries, stored as the
/// optional package member `libraries/index-v1.json`. The document schema does
/// not change: the copied definitions and tokens are ordinary document content.
struct ComponentLibraryIndex: Codable, Equatable, Sendable {
    static let formatIdentifier = "app.siteforge.component-libraries"
    static let currentVersion = 1
    static let memberPath = "libraries/index-v1.json"
    static let memberPrefix = "libraries/"
    static let maximumImports = 32
    static let maximumKnownVersions = 16
    static let maximumIndexBytes = 256 * 1_024

    let format: String
    let version: Int
    let documentID: DocumentID
    let published: ComponentLibraryPublication?
    let imported: [ComponentLibraryImport]

    init(documentID: DocumentID, published: ComponentLibraryPublication?, imported: [ComponentLibraryImport]) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.documentID = documentID
        self.published = published
        self.imported = imported
    }

    var isEmpty: Bool { published == nil && imported.isEmpty }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, version, documentID, published, imported
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        documentID = try container.decode(DocumentID.self, forKey: .documentID)
        published = try container.decodeIfPresent(ComponentLibraryPublication.self, forKey: .published)
        imported = try container.decode([ComponentLibraryImport].self, forKey: .imported)
    }

    /// `published` is always written (as null when absent), so the key set is exact.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(version, forKey: .version)
        try container.encode(documentID, forKey: .documentID)
        try container.encode(published, forKey: .published)
        try container.encode(imported, forKey: .imported)
    }

    func validate() throws {
        guard format == Self.formatIdentifier else { throw ComponentLibraryError.corrupt }
        guard version == Self.currentVersion else { throw ComponentLibraryError.unsupportedVersion(version) }
        guard imported.count <= Self.maximumImports else { throw ComponentLibraryError.corrupt }
        var libraries = Set<ComponentLibraryID>()
        var pages = Set<PageID>()
        var tokens = Set<ColorTokenID>()
        if let published {
            guard (try? ComponentLibraries.validatedName(published.name)) == published.name else {
                throw ComponentLibraryError.corrupt
            }
            libraries.insert(published.libraryID)
        }
        for record in imported {
            guard libraries.insert(record.libraryID).inserted,
                  (try? ComponentLibraries.validatedName(record.name)) == record.name,
                  record.importedAt.date != nil,
                  !record.definitionIDs.isEmpty || !record.tokenIDs.isEmpty,
                  record.definitionIDs.allSatisfy({ pages.insert($0).inserted }),
                  record.tokenIDs.allSatisfy({ tokens.insert($0).inserted }),
                  !record.knownVersions.isEmpty, record.knownVersions.count <= Self.maximumKnownVersions,
                  Set(record.knownVersions.map(\.version)).count == record.knownVersions.count,
                  record.knownVersions.contains(where: { $0.version == record.version }),
                  record.knownVersions.allSatisfy({ known in
                      known.contentDigest.count == 64 && known.contentDigest == known.contentDigest.lowercased()
                          && known.contentDigest.allSatisfy(\.isHexDigit)
                  }) else {
                throw ComponentLibraryError.corrupt
            }
        }
    }
}

enum ComponentLibraryError: Error, Equatable, LocalizedError, Sendable {
    case invalidName
    case invalidVersion
    case versionNotNewer(ComponentLibraryVersion)
    case nothingToExport
    case usesImages(String)
    case usesVideoOrAudio(String)
    case usesTranslations(String)
    case usesProjectFonts(String)
    case linksOutside(String)
    /// The component, then the reusable style stored outside the exported components.
    case usesReusableStyle(String, String)
    case dependsOnLibrary(String)
    case invalidContent
    case writeFailed
    case invalidFile
    case unsupportedVersion(Int)
    case fileTooLarge
    case ownLibrary
    case alreadyImported(String)
    case tooManyLibraries
    case recordTooLarge
    case identityConflict
    case notImported
    case unchanged
    case corrupt
    case documentMismatch
    case readOnly(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a library name of 1–256 UTF-8 bytes without control characters."
        case .invalidVersion: "Enter a version as three numbers, such as 1.0.0."
        case .versionNotNewer(let version): "This library was last exported as version \(version). Enter a higher version."
        case .nothingToExport: "This project has no components of its own to export. Create a component first."
        case .usesImages(let name): "The component \u{201C}\(name)\u{201D} uses an image. Libraries cannot include images yet; remove the image from the component to export it."
        case .usesVideoOrAudio(let name): "The component \u{201C}\(name)\u{201D} plays a video or audio file. Libraries cannot include video or audio yet; turn off its video or audio to export it."
        case .usesTranslations(let name): "The component \u{201C}\(name)\u{201D} has translations. Libraries cannot include translations yet; clear its translations to export it."
        case .usesProjectFonts(let name): "The component \u{201C}\(name)\u{201D} uses a font stored in this project. Libraries cannot include fonts yet; choose a system font for it to export it."
        case .linksOutside(let name): "The component \u{201C}\(name)\u{201D} links to a page of this project, which other projects do not have. Link to a web address or remove the link to export it."
        case .usesReusableStyle(let name, let style): "The component \u{201C}\(name)\u{201D} uses the reusable style \u{201C}\(style)\u{201D}, which is stored outside the exported components. Libraries cannot include it yet; choose Unlink for that style on the component's layers in the Inspector to export it."
        case .dependsOnLibrary(let name): "These components use items from the imported library \u{201C}\(name)\u{201D}. Detach that library first to export them as your own."
        case .invalidContent: "The components could not be stored in a library. Nothing was exported."
        case .writeFailed: "The library file could not be written there. Choose another location and try again."
        case .invalidFile: "This file is not a valid SiteForge component library. Nothing was imported."
        case .unsupportedVersion(let version): "Component library format version \(version) is not supported by this build. Nothing changed."
        case .fileTooLarge: "This library file is larger than \(ComponentLibraryFile.maximumBytes / 1_048_576) MB. Nothing was imported."
        case .ownLibrary: "This library was exported from this project. Its components are already here and editable."
        case .alreadyImported(let name): "The library \u{201C}\(name)\u{201D} is already imported. Use Update to change its version."
        case .tooManyLibraries: "This project already uses \(ComponentLibraryIndex.maximumImports) libraries. Detach one before importing another."
        case .recordTooLarge: "The project's library records would be larger than \(ComponentLibraryIndex.maximumIndexBytes / 1_024) KB. Detach a library you no longer update, then try again. Nothing changed."
        case .identityConflict: "This project already contains some of these components or color tokens (for example a copy made before). Nothing was imported."
        case .notImported: "This file is a different library. Choose a version of the library you are updating."
        case .unchanged: "The project already has this version of the library."
        case .corrupt: "The project's library records are damaged. The document is unchanged; remove all library records to repair them."
        case .documentMismatch: "These library records belong to a different document."
        case .readOnly(let name): "This item is a read-only copy from the library \u{201C}\(name)\u{201D}. Update the library to change it, or detach the library to edit it here."
        case .unavailable: "Libraries are unavailable while the project is being saved, opened or replaced. Try again when it finishes."
        }
    }

    var diagnosticCategory: String {
        switch self {
        case .invalidName: "invalid-name"
        case .invalidVersion: "invalid-version"
        case .versionNotNewer: "version-not-newer"
        case .nothingToExport: "nothing-to-export"
        case .usesImages: "uses-images"
        case .usesVideoOrAudio: "uses-media"
        case .usesTranslations: "uses-translations"
        case .usesProjectFonts: "uses-project-fonts"
        case .linksOutside: "links-outside"
        case .usesReusableStyle: "uses-reusable-style"
        case .dependsOnLibrary: "depends-on-library"
        case .invalidContent: "invalid-content"
        case .writeFailed: "write-failed"
        case .invalidFile: "invalid-file"
        case .unsupportedVersion: "unsupported-version"
        case .fileTooLarge: "file-too-large"
        case .ownLibrary: "own-library"
        case .alreadyImported: "already-imported"
        case .tooManyLibraries: "too-many-libraries"
        case .recordTooLarge: "record-too-large"
        case .identityConflict: "identity-conflict"
        case .notImported: "not-imported"
        case .unchanged: "unchanged"
        case .corrupt: "corrupt"
        case .documentMismatch: "document-mismatch"
        case .readOnly: "read-only"
        case .unavailable: "unavailable"
        }
    }
}

enum ComponentLibraryStatus: Equatable, Sendable {
    /// The document holds the recorded version.
    case current(ComponentLibraryVersion)
    /// The document holds an earlier known version (an update was undone).
    case earlier(ComponentLibraryVersion)
    /// The content matches no known version.
    case changed
    /// None of the library's items are in the document (the import was undone).
    case missing

    var title: String {
        switch self {
        case .current(let version): "Version \(version) \u{2014} read-only copy"
        case .earlier(let version): "Holds earlier version \(version) (an update was undone)"
        case .changed: "Content differs from every imported version"
        case .missing: "Not in the document (the import was undone)"
        }
    }
}

struct ComponentLibraryRow: Identifiable, Equatable, Sendable {
    let record: ComponentLibraryImport
    let status: ComponentLibraryStatus
    let componentCount: Int
    let tokenCount: Int

    var id: ComponentLibraryID { record.libraryID }
}

struct ComponentLibraryUpdatePreview: Equatable, Sendable {
    let libraryID: ComponentLibraryID
    let name: String
    let fromVersion: ComponentLibraryVersion
    let toVersion: ComponentLibraryVersion
    let comparison: ProjectComparison
    /// Components this version no longer has; copies of them on pages will
    /// show as missing components.
    let removedComponentNames: [String]
    let affectedCopyCount: Int

    var isDowngrade: Bool { toVersion < fromVersion }
}

enum ComponentLibraryOperation: String, Equatable, Sendable {
    case export
    case `import`
    case previewUpdate = "preview-update"
    case update
    case detach
    case removeAll = "remove-all"
}

/// SF-0906-008: no names, content or raw identifiers.
struct ComponentLibraryDiagnosticRecord: Equatable, Sendable {
    let requirementID: String
    let operation: ComponentLibraryOperation
    let sanitizedLibraryID: String?
    let durationNanoseconds: UInt64
    let result: ProjectPackageDiagnosticResult
    let failureCategory: String?
}

/// Pure library operations. Imported definitions and tokens keep their stable
/// identities, so instances keep linking across updates and the comparison
/// matches by identity. Document changes are returned as one command; the
/// library record is returned as a new package.
enum ComponentLibraries {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0906-%03d", $0) })

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    static func validatedName(_ draft: String) throws -> String {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 256,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ComponentLibraryError.invalidName
        }
        return name
    }

    static func index(in package: ProjectPackage, documentID: DocumentID) throws -> ComponentLibraryIndex? {
        let members = package.optionalMembers.filter { $0.path.hasPrefix(ComponentLibraryIndex.memberPrefix) }
        guard let member = members.first(where: { $0.path == ComponentLibraryIndex.memberPath }) else {
            guard members.isEmpty else { throw ComponentLibraryError.corrupt }
            return nil
        }
        guard members.count == 1, member.role == .optional,
              member.data.count <= ComponentLibraryIndex.maximumIndexBytes else {
            throw ComponentLibraryError.corrupt
        }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: member.data) }
        catch { throw ComponentLibraryError.corrupt }
        guard header.format == ComponentLibraryIndex.formatIdentifier else { throw ComponentLibraryError.corrupt }
        guard header.version == ComponentLibraryIndex.currentVersion else {
            throw ComponentLibraryError.unsupportedVersion(header.version)
        }
        let index: ComponentLibraryIndex
        do { index = try JSONDecoder().decode(ComponentLibraryIndex.self, from: member.data) }
        catch { throw ComponentLibraryError.corrupt }
        try index.validate()
        guard index.documentID == documentID else { throw ComponentLibraryError.documentMismatch }
        return index
    }

    /// Identifiers new commands may not change, with their library's name.
    static func protectedIdentifiers(
        in index: ComponentLibraryIndex?
    ) -> (pages: [PageID: String], tokens: [ColorTokenID: String]) {
        var pages: [PageID: String] = [:]
        var tokens: [ColorTokenID: String] = [:]
        for record in index?.imported ?? [] {
            for id in record.definitionIDs { pages[id] = record.name }
            for id in record.tokenIDs { tokens[id] = record.name }
        }
        return (pages, tokens)
    }

    /// The read-only rule for new commands: a library item present before the
    /// command must be present and unchanged after it. Moving a component in
    /// the list is allowed. Undo and redo are not checked.
    static func readOnlyViolation(
        from old: CanonicalDocument,
        to new: CanonicalDocument,
        pages: [PageID: String],
        tokens: [ColorTokenID: String]
    ) -> ComponentLibraryError? {
        if !pages.isEmpty {
            let after = Dictionary(new.pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for page in old.pages {
                if let name = pages[page.id], after[page.id] != page { return .readOnly(name) }
            }
        }
        if !tokens.isEmpty {
            let after = Dictionary(new.colorTokens.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for token in old.colorTokens {
                if let name = tokens[token.id], after[token.id] != token { return .readOnly(name) }
            }
        }
        return nil
    }

    static func content(of record: ComponentLibraryImport, in document: CanonicalDocument) -> ComponentLibraryContent {
        let pages = Set(record.definitionIDs)
        let tokens = Set(record.tokenIDs)
        return ComponentLibraryContent(
            definitions: document.pages.filter { pages.contains($0.id) },
            colorTokens: document.colorTokens.filter { tokens.contains($0.id) }
        )
    }

    static func status(of record: ComponentLibraryImport, in document: CanonicalDocument) -> ComponentLibraryStatus {
        let content = content(of: record, in: document)
        guard !content.isEmpty else { return .missing }
        let digest = content.digest()
        if record.knownVersions.contains(where: { $0.version == record.version && $0.contentDigest == digest }) {
            return .current(record.version)
        }
        if let known = record.knownVersions.last(where: { $0.contentDigest == digest }) { return .earlier(known.version) }
        return .changed
    }

    static func rows(_ index: ComponentLibraryIndex?, in document: CanonicalDocument) -> [ComponentLibraryRow] {
        (index?.imported ?? []).map { record in
            let content = content(of: record, in: document)
            return ComponentLibraryRow(record: record, status: status(of: record, in: document),
                                       componentCount: content.definitions.count, tokenCount: content.colorTokens.count)
        }
    }

    /// Exports every component definition of the project's own (not imported)
    /// with the color tokens they use. The project keeps the library's identity
    /// and version so the next export is an update of the same library.
    static func exporting(
        named draft: String,
        version: ComponentLibraryVersion,
        from document: CanonicalDocument,
        in package: ProjectPackage,
        newLibraryID: ComponentLibraryID = ComponentLibraryID(),
        at timestamp: ProjectTimestamp
    ) throws -> (package: ProjectPackage, data: Data, file: ComponentLibraryFile) {
        let name = try validatedName(draft)
        let index = try self.index(in: package, documentID: document.id)
        if let published = index?.published, version <= published.version {
            throw ComponentLibraryError.versionNotNewer(published.version)
        }
        let imported = protectedIdentifiers(in: index)
        let definitions = document.componentDefinitions.filter { imported.pages[$0.id] == nil }
        guard !definitions.isEmpty else { throw ComponentLibraryError.nothingToExport }
        var used = Set<ColorTokenID>()
        // A reusable style is stored as properties of whichever node defines
        // it, so only styles defined inside the exported components travel
        // with them; any other applied style is refused by name (lane V07).
        let styleDefinitionPrefix = CanonicalReusableStyleIndex.namespace + "definition."
        let carriedStyles = Set(definitions.flatMap(\.nodes).flatMap(\.properties).compactMap { property -> ReusableStyleID? in
            let parts = property.key.rawValue.split(separator: ".")
            guard property.key.rawValue.hasPrefix(styleDefinitionPrefix), parts.count == 6 else { return nil }
            return ReusableStyleID(uuidString: String(parts[4]))
        })
        let styleNames = (try? CanonicalReusableStyleIndex(document: document))?.byID ?? [:]
        for definition in definitions {
            for node in definition.nodes {
                if let style = CanonicalReusableStyleIndex.appliedIDs(node).first(where: { !carriedStyles.contains($0) }) {
                    throw ComponentLibraryError.usesReusableStyle(definition.name, styleNames[style]?.name ?? "Unknown style")
                }
                if let target = CanonicalComponentReference.definitionID(for: node), let library = imported.pages[target] {
                    throw ComponentLibraryError.dependsOnLibrary(library)
                }
                guard CanonicalGraphReferences.assets(node).isEmpty else {
                    throw ComponentLibraryError.usesImages(definition.name)
                }
                // The carrier holds only definitions and tokens, so anything
                // else a component needs is refused by name (SF-0906-004)
                // rather than dropped or reported as invalid content.
                guard CanonicalMediaPlayback.resolve(node) == nil else {
                    throw ComponentLibraryError.usesVideoOrAudio(definition.name)
                }
                guard !node.properties.contains(where: { $0.key.rawValue.hasPrefix(SiteTranslationKey.namespace) }) else {
                    throw ComponentLibraryError.usesTranslations(definition.name)
                }
                if let family = CanonicalTypography.resolved(for: node)?.family,
                   document.fontAssets.contains(where: { $0.family.caseInsensitiveCompare(family) == .orderedSame }) {
                    throw ComponentLibraryError.usesProjectFonts(definition.name)
                }
                switch try? CanonicalLinkTarget.resolve(node) {
                case .page(let pageID)? where pageID != definition.id,
                     .section(let pageID, _)? where pageID != definition.id:
                    throw ComponentLibraryError.linksOutside(definition.name)
                default:
                    break
                }
                for token in CanonicalGraphReferences.tokens(node) {
                    if let library = imported.tokens[token] { throw ComponentLibraryError.dependsOnLibrary(library) }
                    used.insert(token)
                }
            }
        }
        let tokens = document.colorTokens.filter { used.contains($0.id) }
        let libraryID = index?.published?.libraryID ?? newLibraryID
        let carrier = CanonicalDocument(
            id: DocumentID(libraryID.rawValue),
            pages: BlankProjectDefaults.pages() + definitions,
            colorTokens: tokens
        )
        let carrierData: Data
        do { carrierData = try DocumentSerializer.encode(carrier) }
        catch { throw ComponentLibraryError.invalidContent }
        let file = ComponentLibraryFile(libraryID: libraryID, name: name, libraryVersion: version,
                                        exportedAt: timestamp, document: carrierData)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do { data = try encoder.encode(file) }
        catch { throw ComponentLibraryError.invalidContent }
        guard data.count <= ComponentLibraryFile.maximumBytes else { throw ComponentLibraryError.fileTooLarge }
        let updated = ComponentLibraryIndex(
            documentID: document.id,
            published: ComponentLibraryPublication(libraryID: libraryID, name: name, version: version),
            imported: index?.imported ?? []
        )
        return (try replacing(updated, in: package), data, file)
    }

    /// Reads and fully validates a library file.
    static func reading(
        _ data: Data,
        checkpoint: () throws -> Void = {}
    ) throws -> (file: ComponentLibraryFile, content: ComponentLibraryContent) {
        guard data.count <= ComponentLibraryFile.maximumBytes else { throw ComponentLibraryError.fileTooLarge }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw ComponentLibraryError.invalidFile }
        guard header.format == ComponentLibraryFile.formatIdentifier else { throw ComponentLibraryError.invalidFile }
        guard header.version == ComponentLibraryFile.currentVersion else {
            throw ComponentLibraryError.unsupportedVersion(header.version)
        }
        let file: ComponentLibraryFile
        let carrier: CanonicalDocument
        do {
            file = try JSONDecoder().decode(ComponentLibraryFile.self, from: data)
            carrier = try DocumentSerializer.decode(file.document, checkpoint: checkpoint)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ComponentLibraryError.invalidFile
        }
        guard (try? validatedName(file.name)) == file.name,
              file.exportedAt.date != nil,
              carrier.id.rawValue == file.libraryID.rawValue,
              carrier.imageAssets.isEmpty,
              !carrier.componentDefinitions.isEmpty else {
            throw ComponentLibraryError.invalidFile
        }
        return (file, ComponentLibraryContent(definitions: carrier.componentDefinitions, colorTokens: carrier.colorTokens))
    }

    /// One command that adds the library's definitions (after every page) and
    /// tokens (after every token), and the package with the new record.
    static func importing(
        _ file: ComponentLibraryFile,
        _ content: ComponentLibraryContent,
        into document: CanonicalDocument,
        package: ProjectPackage,
        at timestamp: ProjectTimestamp
    ) throws -> (command: DocumentCommand, package: ProjectPackage, record: ComponentLibraryImport) {
        let index = try self.index(in: package, documentID: document.id)
        if index?.published?.libraryID == file.libraryID { throw ComponentLibraryError.ownLibrary }
        let imported = index?.imported ?? []
        if let existing = imported.first(where: { $0.libraryID == file.libraryID }) {
            throw ComponentLibraryError.alreadyImported(existing.name)
        }
        guard imported.count < ComponentLibraryIndex.maximumImports else { throw ComponentLibraryError.tooManyLibraries }
        let pageIDs = Set(document.pages.map(\.id))
        let tokenIDs = Set(document.colorTokens.map(\.id))
        guard content.definitions.allSatisfy({ !pageIDs.contains($0.id) }),
              content.colorTokens.allSatisfy({ !tokenIDs.contains($0.id) }) else {
            throw ComponentLibraryError.identityConflict
        }
        var commands = content.definitions.enumerated().map {
            DocumentCommand.insertPage(InsertPageCommand(page: $0.element, index: document.pages.count + $0.offset))
        }
        if !content.colorTokens.isEmpty {
            commands.append(.setColorTokens(SetColorTokensCommand(tokens: document.colorTokens + content.colorTokens)))
        }
        let record = ComponentLibraryImport(
            libraryID: file.libraryID, name: file.name, version: file.libraryVersion, importedAt: timestamp,
            definitionIDs: content.definitions.map(\.id), tokenIDs: content.colorTokens.map(\.id),
            knownVersions: [ComponentLibraryKnownVersion(version: file.libraryVersion, contentDigest: content.digest())]
        )
        let updated = ComponentLibraryIndex(documentID: document.id, published: index?.published, imported: imported + [record])
        return (.batch(commands), try replacing(updated, in: package), record)
    }

    /// The comparison between the version the document holds and the file's
    /// version, plus what the update would leave missing. Changes nothing.
    static func previewingUpdate(
        _ file: ComponentLibraryFile,
        _ content: ComponentLibraryContent,
        in document: CanonicalDocument,
        package: ProjectPackage,
        checkpoint: () throws -> Void = {}
    ) throws -> ComponentLibraryUpdatePreview {
        let index = try self.index(in: package, documentID: document.id)
        guard let record = index?.imported.first(where: { $0.libraryID == file.libraryID }) else {
            throw ComponentLibraryError.notImported
        }
        let current = self.content(of: record, in: document)
        if file.libraryVersion == record.version, content.digest() == current.digest() {
            throw ComponentLibraryError.unchanged
        }
        let ownedPages = Set(record.definitionIDs)
        let ownedTokens = Set(record.tokenIDs)
        let otherPages = Set(document.pages.map(\.id)).subtracting(ownedPages)
        let otherTokens = Set(document.colorTokens.map(\.id)).subtracting(ownedTokens)
        guard content.definitions.allSatisfy({ !otherPages.contains($0.id) }),
              content.colorTokens.allSatisfy({ !otherTokens.contains($0.id) }) else {
            throw ComponentLibraryError.identityConflict
        }
        let fromName = "\(record.name) \(record.version)"
        let toName = "\(file.name) \(file.libraryVersion)"
        let comparison = try ProjectComparer.compare(
            ProjectComparisonSource(snapshotID: nil, name: fromName, document: current.comparisonDocument(id: document.id)),
            with: ProjectComparisonSource(snapshotID: nil, name: toName, document: content.comparisonDocument(id: document.id)),
            checkpoint: checkpoint
        )
        let kept = Set(content.definitions.map(\.id))
        let removed = current.definitions.filter { !kept.contains($0.id) }
        let removedIDs = Set(removed.map(\.id))
        let affected = document.pages.filter { !ownedPages.contains($0.id) }.reduce(0) { total, page in
            total + page.nodes.filter { node in
                guard let target = CanonicalComponentReference.definitionID(for: node) else { return false }
                return removedIDs.contains(target)
            }.count
        }
        return ComponentLibraryUpdatePreview(
            libraryID: record.libraryID, name: record.name, fromVersion: record.version, toVersion: file.libraryVersion,
            comparison: comparison, removedComponentNames: removed.map(\.name), affectedCopyCount: affected
        )
    }

    /// One command that replaces the library's definitions and tokens with the
    /// file's version (nil when only the record changes), and the new package.
    /// The command is one Undo step; the record keeps every known version.
    static func updating(
        _ file: ComponentLibraryFile,
        _ content: ComponentLibraryContent,
        in document: CanonicalDocument,
        package: ProjectPackage
    ) throws -> (command: DocumentCommand?, package: ProjectPackage) {
        _ = try previewingUpdate(file, content, in: document, package: package)
        guard let index = try self.index(in: package, documentID: document.id),
              let position = index.imported.firstIndex(where: { $0.libraryID == file.libraryID }) else {
            throw ComponentLibraryError.notImported
        }
        let record = index.imported[position]
        let current = self.content(of: record, in: document)
        var commands: [DocumentCommand] = []
        if current.definitions != content.definitions {
            commands += current.definitions.reversed().map { DocumentCommand.removePage(RemovePageCommand(pageID: $0.id)) }
            // Keep the library's place in the page list (its first component).
            let owned = Set(record.definitionIDs)
            let start = document.pages.firstIndex { owned.contains($0.id) } ?? (document.pages.count - current.definitions.count)
            commands += content.definitions.enumerated().map {
                DocumentCommand.insertPage(InsertPageCommand(page: $0.element, index: start + $0.offset))
            }
        }
        let ownedTokens = Set(record.tokenIDs)
        let tokens = document.colorTokens.filter { !ownedTokens.contains($0.id) } + content.colorTokens
        if tokens != document.colorTokens {
            commands.append(.setColorTokens(SetColorTokensCommand(tokens: tokens)))
        }
        let known = Array((record.knownVersions.filter { $0.version != file.libraryVersion }
            + [ComponentLibraryKnownVersion(version: file.libraryVersion, contentDigest: content.digest())])
            .suffix(ComponentLibraryIndex.maximumKnownVersions))
        // The record keeps every identity any imported version delivered, so
        // after Undo of this update the earlier version's items are still
        // recognised (status "earlier") and stay read-only.
        let ownedPages = Set(record.definitionIDs)
        var imported = index.imported
        imported[position] = ComponentLibraryImport(
            libraryID: record.libraryID, name: file.name, version: file.libraryVersion, importedAt: record.importedAt,
            definitionIDs: record.definitionIDs + content.definitions.map(\.id).filter { !ownedPages.contains($0) },
            tokenIDs: record.tokenIDs + content.colorTokens.map(\.id).filter { !ownedTokens.contains($0) },
            knownVersions: known
        )
        let updated = ComponentLibraryIndex(documentID: document.id, published: index.published, imported: imported)
        return (commands.isEmpty ? nil : .batch(commands), try replacing(updated, in: package))
    }

    /// Ends the read-only link: the items stay as ordinary editable content and
    /// no longer receive updates.
    static func detaching(_ id: ComponentLibraryID, documentID: DocumentID, in package: ProjectPackage) throws -> ProjectPackage {
        guard let index = try self.index(in: package, documentID: documentID),
              index.imported.contains(where: { $0.libraryID == id }) else {
            throw ComponentLibraryError.notImported
        }
        let updated = ComponentLibraryIndex(documentID: documentID, published: index.published,
                                            imported: index.imported.filter { $0.libraryID != id })
        return try replacing(updated, in: package)
    }

    /// Repair for damaged or foreign library records: removes every
    /// `libraries/` member and nothing else; the document is unchanged.
    static func removingAll(in package: ProjectPackage) -> ProjectPackage {
        ProjectPackage(
            projectID: package.projectID, createdAt: package.createdAt, modifiedAt: package.modifiedAt,
            document: package.document,
            optionalMembers: package.optionalMembers.filter { !$0.path.hasPrefix(ComponentLibraryIndex.memberPrefix) },
            compatibility: package.compatibility
        )
    }

    private static func replacing(_ index: ComponentLibraryIndex, in package: ProjectPackage) throws -> ProjectPackage {
        var members = package.optionalMembers.filter { !$0.path.hasPrefix(ComponentLibraryIndex.memberPrefix) }
        if !index.isEmpty {
            try index.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data: Data
            do { data = try encoder.encode(index) }
            catch { throw ComponentLibraryError.corrupt }
            guard data.count <= ComponentLibraryIndex.maximumIndexBytes else { throw ComponentLibraryError.recordTooLarge }
            members.append(ProjectPackageMember(path: ComponentLibraryIndex.memberPath, role: .optional, data: data))
        }
        return ProjectPackage(
            projectID: package.projectID, createdAt: package.createdAt, modifiedAt: package.modifiedAt,
            document: package.document, optionalMembers: members.sorted { $0.path < $1.path },
            compatibility: package.compatibility
        )
    }
}
