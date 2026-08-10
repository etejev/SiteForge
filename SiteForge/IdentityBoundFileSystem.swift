import CryptoKit
import Darwin
import Foundation

struct PackageFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct PackageFingerprint: Equatable, Sendable {
    let digest: String
    let byteCount: Int
    let identity: PackageFileIdentity
}

struct PackageSecurityMetadata: Equatable, Sendable {
    static let approvedExtendedAttributes: Set<String> = [
        "app.siteforge.project-identity",
        "com.apple.FinderInfo",
        "com.apple.metadata:_kMDItemUserTags",
        "com.apple.quarantine",
    ]

    let owner: UInt32
    let group: UInt32
    let mode: UInt16
    let linkCount: UInt64
    let extendedACL: String?
    let approvedExtendedAttributes: [String: Data]

    static var secureNewFile: PackageSecurityMetadata {
        PackageSecurityMetadata(
            owner: geteuid(),
            group: getegid(),
            mode: 0o600,
            linkCount: 1,
            extendedACL: nil,
            approvedExtendedAttributes: [:]
        )
    }

    func validateForReplacement() throws {
        guard owner == geteuid(), linkCount == 1 else {
            throw ProjectPackageError.unsafeFileMetadata
        }
    }

    func validateForRecoveryArtifact() throws {
        try validateForReplacement()
        // Recovery bytes are app-owned confidential state: preserving a durable
        // file ACL here could silently re-grant another principal read access.
        guard mode & 0o077 == 0, extendedACL == nil else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
    }
}

struct ValidatedPackageFileSnapshot: Equatable, Sendable {
    let bytes: Data
    let fingerprint: PackageFingerprint
    let metadata: PackageSecurityMetadata
}

enum ProjectPackageIOCheckpoint: String, Equatable, Sendable {
    /// A descriptor-bound read is about to begin. Tests use this only to
    /// interleave a replacement before the first snapshot is captured; the
    /// public API never treats a path observation as a validated read.
    case beforeRead
    case sourceSnapshotCaptured
    case destinationValidated
    case beforeConditionalCommit
    case afterAtomicSwap
    case recoveryValidatedForDeletion
    case recoveryDeletionReadyToCommit
}

protocol ProjectPackageIOObserving: Sendable {
    func reached(_ checkpoint: ProjectPackageIOCheckpoint) async
}

/// Lets a lifecycle owner make the final filesystem mutation linear with its
/// own transition boundary. The filesystem still owns descriptor validation;
/// this capability only serializes the final syscall against a superseding
/// in-memory adoption attempt.
protocol ProjectPackageConditionalCommitAuthorizing: Sendable {
    func commitIfAuthorized(_ operation: @Sendable () throws -> Void) throws
}

enum ProjectPackageArtifactPolicy: Equatable, Sendable {
    case durable
    case recovery(ProjectID)
}

struct IdentityBoundPackageFileSystem: Sendable {
    private static let chunkBytes = 64 * 1_024
    private static let maximumMetadataBytes = 256 * 1_024
    private static let recoveryTombstoneMagic = Data("SFRT001:".utf8)

    let observer: (any ProjectPackageIOObserving)?

    init(observer: (any ProjectPackageIOObserving)? = nil) {
        self.observer = observer
    }

    func readSnapshot(from url: URL, maximumBytes: Int) async throws -> ValidatedPackageFileSnapshot {
        await observer?.reached(.beforeRead)
        let opened = try Self.openParent(of: url)
        defer { Darwin.close(opened.descriptor) }
        let snapshot = try Self.readFile(
            named: opened.name,
            in: opened.descriptor,
            maximumBytes: maximumBytes,
            missing: .packageUnavailable,
            unsafe: .packageIsSymbolicLink
        )
        await observer?.reached(.sourceSnapshotCaptured)
        return snapshot
    }

    func readOwnedRecoverySnapshot(
        from url: URL,
        maximumBytes: Int
    ) async throws -> ValidatedPackageFileSnapshot {
        await observer?.reached(.beforeRead)
        let opened = try Self.openParent(of: url)
        defer { Darwin.close(opened.descriptor) }
        try Self.validateOwnedRecoveryDirectoryDescriptor(opened.descriptor)
        let snapshot = try Self.readFile(
            named: opened.name,
            in: opened.descriptor,
            maximumBytes: maximumBytes,
            missing: .packageUnavailable,
            unsafe: .unsafeRecoveryArtifact
        )
        do {
            try snapshot.metadata.validateForRecoveryArtifact()
        } catch {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        await observer?.reached(.sourceSnapshotCaptured)
        return snapshot
    }

    /// A retired recovery is represented by a versioned, project-bound marker
    /// in an app-owned directory. The marker avoids an unsafe pathname unlink
    /// while keeping the public recovery name non-restorable.
    /// Tests a recovery name only against the project identity that owns that
    /// name. A structurally valid marker for another project is never a
    /// discovery authority for this path.
    func isRetiredRecoveryTombstone(
        at url: URL,
        projectID: ProjectID,
        maximumBytes: Int
    ) throws -> Bool {
        let opened = try Self.openParent(of: url)
        defer { Darwin.close(opened.descriptor) }
        try Self.validateOwnedRecoveryDirectoryDescriptor(opened.descriptor)
        do {
            let snapshot = try Self.readFile(
                named: opened.name,
                in: opened.descriptor,
                maximumBytes: maximumBytes,
                missing: .packageUnavailable,
                unsafe: .unsafeRecoveryArtifact
            )
            return Self.isRetiredRecoveryTombstone(snapshot, for: projectID)
        } catch let error as ProjectPackageError where error == .packageUnavailable {
            return false
        }
    }

    func replace(
        bytes: Data,
        at destination: URL,
        expected: PackageFingerprint?,
        policy: ProjectPackageArtifactPolicy,
        interruption: ProjectPackageWriteInterruption
    ) async throws -> PackageFingerprint {
        guard bytes.count <= ProjectPackageStore.maximumPackageBytes else {
            throw ProjectPackageError.oversizedInput
        }
        let opened = try Self.openParent(of: destination)
        defer { Darwin.close(opened.descriptor) }

        if case .recovery = policy {
            try Self.validateOwnedRecoveryDirectoryDescriptor(opened.descriptor)
        }

        let initial: ValidatedPackageFileSnapshot?
        let conditionalExpectation: PackageFingerprint?
        if let expected {
            let snapshot = try Self.readFile(
                named: opened.name,
                in: opened.descriptor,
                maximumBytes: ProjectPackageStore.maximumPackageBytes,
                missing: .fileIdentityChanged,
                unsafe: .unsafeDestination
            )
            guard snapshot.fingerprint == expected else { throw ProjectPackageError.fileIdentityChanged }
            try snapshot.metadata.validateForReplacement()
            if case .recovery = policy { try snapshot.metadata.validateForRecoveryArtifact() }
            initial = snapshot
            conditionalExpectation = expected
        } else if case .recovery(let projectID) = policy,
                  let retired = try? Self.readFile(
                    named: opened.name,
                    in: opened.descriptor,
                    maximumBytes: ProjectPackageStore.maximumPackageBytes,
                    missing: .fileIdentityChanged,
                    unsafe: .unsafeRecoveryArtifact
                  ),
                  Self.isRetiredRecoveryTombstone(retired, for: projectID) {
            // A successful retirement intentionally leaves a versioned,
            // project-bound marker at the public recovery name: Darwin offers
            // no identity-conditional unlink. Treat only that exact marker as
            // a conditional replacement source for a later autosave; an
            // unrelated empty owner-restricted file is never such proof.
            initial = retired
            conditionalExpectation = retired.fingerprint
        } else {
            try Self.requireMissing(opened.name, in: opened.descriptor)
            initial = nil
            conditionalExpectation = nil
        }
        await observer?.reached(.destinationValidated)

        let stagingName = ".siteforge-stage-\(UUID().uuidString)"
        let stagingDescriptor = Darwin.openat(
            opened.descriptor,
            stagingName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard stagingDescriptor >= 0 else { throw Self.writeError(errno) }
        defer { Darwin.close(stagingDescriptor) }

        // There is no macOS pathname API that atomically says “unlink this
        // exact inode.” Once a staging name is visible, a same-UID concurrent
        // writer can replace that name between a final identity check and an
        // unlink. Retain abandoned/displaced staging entries rather than risk
        // deleting bytes we no longer own. They are hidden, ignored by the
        // package parser, and intentionally require an explicit trusted-root
        // maintenance policy rather than opportunistic path cleanup.

        try Self.writeAll(bytes, to: stagingDescriptor)
        try Self.apply(initial?.metadata ?? .secureNewFile, to: stagingDescriptor)
        guard Darwin.fsync(stagingDescriptor) == 0 else { throw Self.writeError(errno) }
        guard interruption == .none else { throw ProjectPackageError.interrupted }

        let digest = Self.digest(bytes)
        let stagedFingerprint = PackageFingerprint(
            digest: digest,
            byteCount: bytes.count,
            identity: try Self.identity(of: stagingDescriptor)
        )

        await observer?.reached(.beforeConditionalCommit)
        try Self.revalidate(opened, for: destination)
        if let expected = conditionalExpectation, let initial {
            let final = try Self.readFile(
                named: opened.name,
                in: opened.descriptor,
                maximumBytes: ProjectPackageStore.maximumPackageBytes,
                missing: .fileIdentityChanged,
                unsafe: .unsafeDestination
            )
            guard final.fingerprint == expected, final.metadata == initial.metadata else {
                throw ProjectPackageError.fileIdentityChanged
            }
            try Self.apply(final.metadata, to: stagingDescriptor)
            guard Darwin.fsync(stagingDescriptor) == 0 else { throw Self.writeError(errno) }
            try Self.validateStaging(
                named: stagingName,
                in: opened.descriptor,
                fingerprint: stagedFingerprint,
                metadata: final.metadata
            )

            guard Darwin.renameatx_np(
                opened.descriptor,
                stagingName,
                opened.descriptor,
                opened.name,
                UInt32(RENAME_SWAP)
            ) == 0 else {
                throw Self.writeError(errno)
            }

            let replacementIdentity = try Self.identity(of: stagingDescriptor)
            let replacementFingerprint = PackageFingerprint(
                digest: digest,
                byteCount: bytes.count,
                identity: replacementIdentity
            )
            await observer?.reached(.afterAtomicSwap)
            let committed = try Self.readFile(
                named: opened.name,
                in: opened.descriptor,
                maximumBytes: ProjectPackageStore.maximumPackageBytes,
                missing: .fileIdentityChanged,
                unsafe: .unsafeDestination
            )
            guard committed.fingerprint == replacementFingerprint,
                  committed.metadata == final.metadata else {
                // Never reverse the exchange through a pathname that may have
                // been replaced after it became public. The public name now
                // belongs to the external writer; keep it untouched and leave
                // operation artifacts for trusted-root maintenance.
                throw ProjectPackageError.fileIdentityChanged
            }
            // The exchange moved the former public entry to the unpredictable
            // staging name. Do not reopen, inspect, move, or unlink that
            // pathname: a same-UID writer can replace it at any point after
            // the exchange. The public replacement above is the only durable
            // success boundary; the displaced entry is retained for an
            // explicit trusted-root maintenance policy.
        } else {
            try Self.validateStaging(
                named: stagingName,
                in: opened.descriptor,
                fingerprint: stagedFingerprint,
                metadata: .secureNewFile
            )
            guard Darwin.renameatx_np(
                opened.descriptor,
                stagingName,
                opened.descriptor,
                opened.name,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                if errno == EEXIST { throw ProjectPackageError.fileIdentityChanged }
                throw Self.writeError(errno)
            }
        }

        guard Darwin.fsync(opened.descriptor) == 0 else { throw Self.writeError(errno) }
        let identity = try Self.identity(of: stagingDescriptor)
        return PackageFingerprint(digest: digest, byteCount: bytes.count, identity: identity)
    }

    func prepareOwnedRecoveryDirectory(_ directory: URL) throws {
        let opened = try Self.openDirectory(directory, createMissing: true)
        defer { Darwin.close(opened.descriptor) }
        var information = stat()
        guard Darwin.fstat(opened.descriptor, &information) == 0,
              UInt32(information.st_uid) == geteuid() else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        guard Darwin.fchmod(opened.descriptor, mode_t(0o700)) == 0 else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        try Self.clearExtendedACL(on: opened.descriptor, error: .unsafeRecoveryArtifact)
        try Self.validateOwnedRecoveryDirectoryDescriptor(opened.descriptor)
    }

    func validateOwnedRecoveryDirectory(_ directory: URL) throws {
        let opened = try Self.openDirectory(directory, createMissing: false)
        defer { Darwin.close(opened.descriptor) }
        var information = stat()
        guard Darwin.fstat(opened.descriptor, &information) == 0,
              UInt32(information.st_uid) == geteuid(),
              UInt16(information.st_mode & 0o777) & 0o077 == 0 else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        try Self.validateOwnedRecoveryDirectoryDescriptor(opened.descriptor)
    }

    func removeOwnedRecovery(
        at url: URL,
        projectID: ProjectID,
        expected: PackageFingerprint,
        ownershipValidator: @Sendable (ValidatedPackageFileSnapshot) throws -> Void,
        commitAuthorizer: (any ProjectPackageConditionalCommitAuthorizing)? = nil
    ) async throws {
        let opened = try Self.openParent(of: url)
        defer { Darwin.close(opened.descriptor) }
        try Self.validateOwnedRecoveryDirectoryDescriptor(opened.descriptor)

        let initial = try Self.readFile(
            named: opened.name,
            in: opened.descriptor,
            maximumBytes: ProjectPackageStore.maximumPackageBytes,
            missing: .recoveryDeletionFailed,
            unsafe: .unsafeRecoveryArtifact
        )
        // A prior identity-bound retirement leaves this exact, project-bound
        // marker at the public name. Its presence means there are no recovery
        // bytes left to delete, so another controller that still holds the
        // old snapshot can complete idempotently without reopening or
        // removing a pathname. A marker for another project never qualifies.
        if Self.isRetiredRecoveryTombstone(initial, for: projectID) {
            return
        }
        guard initial.fingerprint == expected else { throw ProjectPackageError.unsafeRecoveryArtifact }
        try initial.metadata.validateForRecoveryArtifact()
        // Ownership is a property of the exact bytes and file identity held by
        // this descriptor-bound snapshot. The package layer validates its
        // project ID here, rather than trusting a caller-supplied identifier
        // that could describe a different recovery artifact with the same
        // filesystem policy.
        do {
            try ownershipValidator(initial)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        await observer?.reached(.recoveryValidatedForDeletion)
        try Self.revalidate(opened, for: url)
        let final = try Self.readFile(
            named: opened.name,
            in: opened.descriptor,
            maximumBytes: ProjectPackageStore.maximumPackageBytes,
            missing: .recoveryDeletionFailed,
            unsafe: .unsafeRecoveryArtifact
        )
        guard final == initial else { throw ProjectPackageError.unsafeRecoveryArtifact }

        // `unlinkat` has no expected-inode argument. Exchange the validated
        // artifact with an operation-owned tombstone first, so a replacement at
        // the public recovery name after validation is never deleted by us.
        let tombstoneName = ".siteforge-delete-\(UUID().uuidString)"
        let tombstoneDescriptor = Darwin.openat(
            opened.descriptor,
            tombstoneName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard tombstoneDescriptor >= 0 else { throw ProjectPackageError.recoveryDeletionFailed }
        let tombstoneIdentity: PackageFileIdentity
        do {
            try Self.writeAll(Self.recoveryTombstonePayload(for: projectID), to: tombstoneDescriptor)
            try Self.apply(.secureNewFile, to: tombstoneDescriptor)
            guard Darwin.fsync(tombstoneDescriptor) == 0 else {
                throw ProjectPackageError.recoveryDeletionFailed
            }
            tombstoneIdentity = try Self.identity(of: tombstoneDescriptor)
        } catch {
            Darwin.close(tombstoneDescriptor)
            // Preserve a failed-operation artifact rather than reopen a name
            // that could already belong to another writer.
            throw ProjectPackageError.recoveryDeletionFailed
        }
        Darwin.close(tombstoneDescriptor)

        await observer?.reached(.recoveryDeletionReadyToCommit)
        try Self.revalidate(opened, for: url)
        // Bind both public names again immediately before the exchange. The
        // directory descriptor alone is not evidence that either entry still
        // names the artifact that this operation owns.
        let finalPublic = try Self.readFile(
            named: opened.name,
            in: opened.descriptor,
            maximumBytes: ProjectPackageStore.maximumPackageBytes,
            missing: .recoveryDeletionFailed,
            unsafe: .unsafeRecoveryArtifact
        )
        guard finalPublic == initial else { throw ProjectPackageError.unsafeRecoveryArtifact }
        try finalPublic.metadata.validateForRecoveryArtifact()
        let finalTombstone = try Self.readFile(
            named: tombstoneName,
            in: opened.descriptor,
            maximumBytes: ProjectPackageStore.maximumPackageBytes,
            missing: .recoveryDeletionFailed,
            unsafe: .unsafeRecoveryArtifact
        )
        guard finalTombstone.fingerprint.identity == tombstoneIdentity,
              Self.isRetiredRecoveryTombstone(finalTombstone, for: projectID) else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        let exchange: @Sendable () throws -> Void = {
            try Task.checkCancellation()
            guard Darwin.renameatx_np(
                opened.descriptor,
                opened.name,
                opened.descriptor,
                tombstoneName,
                UInt32(RENAME_SWAP)
            ) == 0 else {
                throw ProjectPackageError.recoveryDeletionFailed
            }
        }
        if let commitAuthorizer {
            try commitAuthorizer.commitIfAuthorized(exchange)
        } else {
            try exchange()
        }

        do {
            let quarantined = try Self.readFile(
                named: tombstoneName,
                in: opened.descriptor,
                maximumBytes: ProjectPackageStore.maximumPackageBytes,
                missing: .recoveryDeletionFailed,
                unsafe: .unsafeRecoveryArtifact
            )
            guard quarantined == initial else { throw ProjectPackageError.unsafeRecoveryArtifact }
        } catch {
            // Do not roll back through either pathname. A same-UID process
            // can replace either name after exchange, and Darwin has no
            // identity-conditional rename or unlink primitive. Preserve both
            // entries for explicit trusted-root maintenance/retry.
            _ = Darwin.fsync(opened.descriptor)
            throw ProjectPackageError.unsafeRecoveryArtifact
        }

        let publicTombstone = try Self.readFile(
            named: opened.name,
            in: opened.descriptor,
            maximumBytes: ProjectPackageStore.maximumPackageBytes,
            missing: .recoveryDeletionFailed,
            unsafe: .unsafeRecoveryArtifact
        )
        guard publicTombstone.fingerprint.identity == tombstoneIdentity,
              Self.isRetiredRecoveryTombstone(publicTombstone, for: projectID) else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        // Keep the quarantined owned bytes and public project-bound marker
        // rather than perform either pathname-based unlink. This is a logical
        // retirement: discovery ignores the exact marker and no recovery can be restored,
        // while an external same-UID replacement after this point is never
        // deleted by SiteForge. A future explicit trusted-root maintenance
        // policy may reclaim these entries with an owner-approved threat model.
        guard Darwin.fsync(opened.descriptor) == 0 else {
            throw ProjectPackageError.recoveryDeletionFailed
        }
    }
}

private extension IdentityBoundPackageFileSystem {
    struct OpenedParent: Sendable {
        let descriptor: Int32
        let identity: PackageFileIdentity
        let name: String
    }

    struct OpenedDirectory {
        let descriptor: Int32
        let identity: PackageFileIdentity
    }

    struct FileVersion: Equatable {
        let identity: PackageFileIdentity
        let size: Int64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let changeSeconds: Int64
        let changeNanoseconds: Int64
    }

    static func openParent(of url: URL) throws -> OpenedParent {
        let resolved = try validatedAbsoluteURL(url)
        guard !resolved.lastPathComponent.isEmpty else {
            throw ProjectPackageError.unsafeDestination
        }
        let parent = try openDirectory(resolved.deletingLastPathComponent(), createMissing: false)
        return OpenedParent(
            descriptor: parent.descriptor,
            identity: parent.identity,
            name: resolved.lastPathComponent
        )
    }

    static func openDirectory(_ url: URL, createMissing: Bool) throws -> OpenedDirectory {
        let resolved = try validatedAbsoluteURL(url)
        // Each path component is opened relative to an already-open directory
        // descriptor. O_NOFOLLOW therefore rejects a symlink at every hop
        // without O_NOFOLLOW_ANY's platform-specific traversal behavior on
        // File Provider-backed user directories.
        let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard root >= 0 else { throw ProjectPackageError.unsafeDestination }
        var descriptor = root
        for component in resolved.pathComponents.dropFirst() where component != "/" {
            var child = Darwin.openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
            )
            if child < 0, createMissing, errno == ENOENT {
                guard Darwin.mkdirat(descriptor, component, mode_t(0o700)) == 0 || errno == EEXIST else {
                    Darwin.close(descriptor)
                    throw ProjectPackageError.unsafeRecoveryArtifact
                }
                child = Darwin.openat(
                    descriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
                )
            }
            guard child >= 0 else {
                Darwin.close(descriptor)
                throw createMissing
                    ? ProjectPackageError.unsafeRecoveryArtifact
                    : ProjectPackageError.unsafeDestination
            }
            Darwin.close(descriptor)
            descriptor = child
        }
        let identity = try identity(of: descriptor)
        return OpenedDirectory(descriptor: descriptor, identity: identity)
    }

    static func revalidate(_ opened: OpenedParent, for url: URL) throws {
        let current = try openDirectory(try validatedAbsoluteURL(url).deletingLastPathComponent(), createMissing: false)
        defer { Darwin.close(current.descriptor) }
        guard current.identity == opened.identity else { throw ProjectPackageError.fileIdentityChanged }
    }

    static func validatedAbsoluteURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw ProjectPackageError.unsafeDestination
        }
        let components = url.pathComponents
        guard !components.contains("."), !components.contains("..") else {
            throw ProjectPackageError.unsafeDestination
        }
        return url
    }

    static func requireMissing(_ name: String, in parent: Int32) throws {
        var information = stat()
        if Darwin.fstatat(parent, name, &information, AT_SYMLINK_NOFOLLOW) == 0 {
            guard information.st_mode & S_IFMT == S_IFREG else {
                throw ProjectPackageError.unsafeDestination
            }
            throw ProjectPackageError.fileIdentityChanged
        }
        guard errno == ENOENT else { throw ProjectPackageError.unsafeDestination }
    }

    static func readFile(
        named name: String,
        in parent: Int32,
        maximumBytes: Int,
        missing: ProjectPackageError,
        unsafe: ProjectPackageError
    ) throws -> ValidatedPackageFileSnapshot {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw missing }
            if errno == ELOOP { throw unsafe }
            throw ProjectPackageError.ioFailure
        }
        defer { Darwin.close(descriptor) }
        return try readFile(descriptor: descriptor, maximumBytes: maximumBytes, unsafe: unsafe)
    }

    static func readFile(
        descriptor: Int32,
        maximumBytes: Int,
        unsafe: ProjectPackageError
    ) throws -> ValidatedPackageFileSnapshot {
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0 else { throw ProjectPackageError.ioFailure }
        guard before.st_mode & S_IFMT == S_IFREG else { throw unsafe }
        guard before.st_size >= 0, before.st_size <= Int64(maximumBytes) else {
            throw ProjectPackageError.oversizedInput
        }
        let beforeVersion = version(before)
        var bytes = Data()
        bytes.reserveCapacity(Int(before.st_size))
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: chunkBytes)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw ProjectPackageError.ioFailure
            }
            guard bytes.count <= maximumBytes - count else {
                throw ProjectPackageError.oversizedInput
            }
            let chunk = Data(buffer[0..<count])
            hasher.update(data: chunk)
            bytes.append(chunk)
        }
        // ACL and xattr reads are part of the identity-bound snapshot. Take
        // them before the final version check so any concurrent metadata
        // mutation invalidates the complete bytes-and-metadata result.
        let metadata = try securityMetadata(before, descriptor: descriptor)
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              beforeVersion == version(after),
              bytes.count == Int(after.st_size) else {
            throw ProjectPackageError.fileIdentityChanged
        }
        let identity = beforeVersion.identity
        return ValidatedPackageFileSnapshot(
            bytes: bytes,
            fingerprint: PackageFingerprint(
                digest: digest(hasher.finalize()),
                byteCount: bytes.count,
                identity: identity
            ),
            metadata: metadata
        )
    }

    static func identity(of descriptor: Int32) throws -> PackageFileIdentity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw ProjectPackageError.ioFailure }
        return version(information).identity
    }

    static func isRetiredRecoveryTombstone(
        _ snapshot: ValidatedPackageFileSnapshot,
        for projectID: ProjectID? = nil
    ) -> Bool {
        guard snapshot.metadata == .secureNewFile,
              snapshot.bytes.count == recoveryTombstoneMagic.count + 32,
              snapshot.bytes.prefix(recoveryTombstoneMagic.count) == recoveryTombstoneMagic else {
            return false
        }
        guard let projectID else { return true }
        return snapshot.bytes == recoveryTombstonePayload(for: projectID)
    }

    static func recoveryTombstonePayload(for projectID: ProjectID) -> Data {
        var payload = recoveryTombstoneMagic
        let input = Data("siteforge-recovery-tombstone-v1:\(projectID.description)".utf8)
        payload.append(contentsOf: SHA256.hash(data: input))
        return payload
    }

    static func validateStaging(
        named name: String,
        in parent: Int32,
        fingerprint: PackageFingerprint,
        metadata: PackageSecurityMetadata
    ) throws {
        let snapshot = try readFile(
            named: name,
            in: parent,
            maximumBytes: ProjectPackageStore.maximumPackageBytes,
            missing: .fileIdentityChanged,
            unsafe: .unsafeDestination
        )
        guard snapshot.fingerprint == fingerprint, snapshot.metadata == metadata else {
            throw ProjectPackageError.fileIdentityChanged
        }
    }

    static func version(_ information: stat) -> FileVersion {
        FileVersion(
            identity: PackageFileIdentity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            ),
            size: information.st_size,
            modificationSeconds: Int64(information.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(information.st_mtimespec.tv_nsec),
            changeSeconds: Int64(information.st_ctimespec.tv_sec),
            changeNanoseconds: Int64(information.st_ctimespec.tv_nsec)
        )
    }

    static func securityMetadata(_ information: stat, descriptor: Int32) throws -> PackageSecurityMetadata {
        PackageSecurityMetadata(
            owner: UInt32(information.st_uid),
            group: UInt32(information.st_gid),
            mode: UInt16(information.st_mode & 0o7777),
            linkCount: UInt64(information.st_nlink),
            extendedACL: try extendedACL(descriptor),
            approvedExtendedAttributes: try approvedExtendedAttributes(descriptor)
        )
    }

    static func extendedACL(_ descriptor: Int32) throws -> String? {
        errno = 0
        guard let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT || errno == ENOTSUP || errno == EOPNOTSUPP { return nil }
            throw ProjectPackageError.unsafeFileMetadata
        }
        defer { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        var length: ssize_t = 0
        guard let text = Darwin.acl_to_text(acl, &length) else {
            throw ProjectPackageError.unsafeFileMetadata
        }
        defer { Darwin.acl_free(text) }
        guard length >= 0, length <= maximumMetadataBytes else {
            throw ProjectPackageError.unsafeFileMetadata
        }
        let bytes = UnsafeBufferPointer(start: text, count: Int(length)).map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func approvedExtendedAttributes(_ descriptor: Int32) throws -> [String: Data] {
        let length = Darwin.flistxattr(descriptor, nil, 0, 0)
        guard length >= 0, length <= maximumMetadataBytes else {
            throw ProjectPackageError.unsafeFileMetadata
        }
        guard length > 0 else { return [:] }
        var names = [CChar](repeating: 0, count: length)
        let read = names.withUnsafeMutableBufferPointer { buffer in
            Darwin.flistxattr(descriptor, buffer.baseAddress, buffer.count, 0)
        }
        guard read == length else { throw ProjectPackageError.unsafeFileMetadata }
        var result: [String: Data] = [:]
        var start = 0
        for index in 0..<names.count where names[index] == 0 {
            guard index > start else { start = index + 1; continue }
            let name = names[start..<index].withContiguousStorageIfAvailable { buffer in
                String(decoding: buffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            } ?? ""
            start = index + 1
            guard PackageSecurityMetadata.approvedExtendedAttributes.contains(name) else { continue }
            let valueLength = name.withCString { Darwin.fgetxattr(descriptor, $0, nil, 0, 0, 0) }
            guard valueLength >= 0, valueLength <= maximumMetadataBytes else {
                throw ProjectPackageError.unsafeFileMetadata
            }
            var value = Data(count: valueLength)
            let valueRead = value.withUnsafeMutableBytes { buffer in
                name.withCString {
                    Darwin.fgetxattr(descriptor, $0, buffer.baseAddress, buffer.count, 0, 0)
                }
            }
            guard valueRead == valueLength else { throw ProjectPackageError.unsafeFileMetadata }
            result[name] = value
        }
        return result
    }

    static func apply(_ metadata: PackageSecurityMetadata, to descriptor: Int32) throws {
        try metadata.validateForReplacement()
        guard Darwin.fchown(descriptor, uid_t(metadata.owner), gid_t(metadata.group)) == 0,
              Darwin.fchmod(descriptor, mode_t(metadata.mode)) == 0 else {
            throw ProjectPackageError.unsafeFileMetadata
        }

        let acl: acl_t?
        if let text = metadata.extendedACL {
            acl = text.withCString { Darwin.acl_from_text($0) }
        } else {
            acl = Darwin.acl_init(0)
        }
        guard let acl else { throw ProjectPackageError.unsafeFileMetadata }
        defer { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        guard Darwin.acl_set_fd_np(descriptor, acl, ACL_TYPE_EXTENDED) == 0 else {
            throw ProjectPackageError.unsafeFileMetadata
        }

        for (name, value) in metadata.approvedExtendedAttributes {
            let result = value.withUnsafeBytes { buffer in
                name.withCString {
                    Darwin.fsetxattr(descriptor, $0, buffer.baseAddress, buffer.count, 0, 0)
                }
            }
            guard result == 0 else { throw ProjectPackageError.unsafeFileMetadata }
        }
    }

    static func clearExtendedACL(on descriptor: Int32, error: ProjectPackageError) throws {
        guard let acl = Darwin.acl_init(0) else { throw error }
        defer { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        guard Darwin.acl_set_fd_np(descriptor, acl, ACL_TYPE_EXTENDED) == 0 else {
            throw error
        }
    }

    static func writeAll(_ bytes: Data, to descriptor: Int32) throws {
        try bytes.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard count > 0 else {
                    if errno == EINTR { continue }
                    throw writeError(errno)
                }
                offset += count
            }
        }
    }

    static func validateOwnedRecoveryDirectoryDescriptor(_ descriptor: Int32) throws {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR,
              UInt32(information.st_uid) == geteuid(),
              UInt16(information.st_mode & 0o777) & 0o077 == 0 else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        guard try extendedACL(descriptor) == nil else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ hash: SHA256.Digest) -> String {
        hash.map { String(format: "%02x", $0) }.joined()
    }

    static func writeError(_ code: Int32) -> ProjectPackageError {
        switch code {
        case EACCES, EPERM: .unsafeFileMetadata
        case EEXIST, ENOENT: .fileIdentityChanged
        case ELOOP: .unsafeDestination
        default: .ioFailure
        }
    }
}
