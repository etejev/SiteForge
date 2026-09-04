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

struct ProjectPackage: Equatable, Sendable {
    static let currentPackageVersion = 1

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
            let package = try Self.parseContainer(data, cancellation: cancellation)
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
        let started = ContinuousClock.now
        do {
            if case .recovery(let owner) = policy, owner != package.projectID {
                throw ProjectPackageError.unsafeRecoveryArtifact
            }
            let data = try Self.makeContainer(for: package)
            let fingerprint = try await fileSystem.replace(
                bytes: data,
                at: destination,
                expected: expected,
                policy: policy,
                interruption: interruption
            )
            await record(.write, projectID: package.projectID, started: started, error: nil)
            return fingerprint
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
            let package = try Self.parseContainer(file.bytes, cancellation: cancellation)
            if let recoveryOwner, package.projectID != recoveryOwner {
                throw ProjectPackageError.unsafeRecoveryArtifact
            }
            await record(.read, projectID: package.projectID, started: started, error: nil)
            return ValidatedProjectPackageRead(package: package, file: file)
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
                let package = try Self.parseContainer(snapshot.bytes, cancellation: cancellation)
                guard package.projectID == projectID else {
                    throw ProjectPackageError.unsafeRecoveryArtifact
                }
            },
            commitAuthorizer: commitAuthorizer
        )
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
        payloads.append(ProjectPackageMember(path: documentPath, role: .document, data: documentData))
        try validatePayloads(payloads)

        let descriptors = payloads
            .map { MemberDescriptor(path: $0.path, role: $0.role, byteCount: $0.data.count, sha256: checksum($0.data)) }
            .sorted { $0.path < $1.path }
        let manifest = Manifest(
            format: "app.siteforge.project-package",
            packageVersion: ProjectPackage.currentPackageVersion,
            documentSchemaVersion: DocumentSerializer.currentSchemaVersion,
            projectID: package.projectID,
            createdAt: package.createdAt,
            modifiedAt: package.modifiedAt,
            compatibility: package.compatibility,
            members: descriptors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        payloads.append(ProjectPackageMember(path: manifestPath, data: manifestData))
        return try ArchiveCodec.encode(payloads)
    }

    static func parseContainer(
        _ data: Data,
        cancellation: CooperativeCancellationCheckpoint
    ) throws -> ProjectPackage {
        try cancellation.check()
        guard data.count <= maximumPackageBytes else { throw ProjectPackageError.oversizedInput }
        let payloads = try ArchiveCodec.decode(data)
        try cancellation.check()
        let byPath = Dictionary(uniqueKeysWithValues: payloads.map { ($0.path, $0) })
        guard let manifestData = byPath[manifestPath]?.data else { throw ProjectPackageError.missingManifest }
        guard let documentData = byPath[documentPath]?.data else { throw ProjectPackageError.missingDocument }

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
        guard header.packageVersion == ProjectPackage.currentPackageVersion else {
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
        try validateManifestMetadata(manifest)
        try validateDescriptors(manifest.members, payloads: payloads, cancellation: cancellation)
        try cancellation.check()

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
            .filter { $0.path != manifestPath && $0.path != documentPath }
            .map { ProjectPackageMember(path: $0.path, role: descriptorByPath[$0.path]!.role, data: $0.data) }
            .sorted { $0.path < $1.path }
        return ProjectPackage(
            projectID: manifest.projectID,
            createdAt: manifest.createdAt,
            modifiedAt: manifest.modifiedAt,
            document: document,
            optionalMembers: optionalMembers,
            compatibility: manifest.compatibility
        )
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
