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
        guard mode & 0o077 == 0 else {
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
    case sourceSnapshotCaptured
    case destinationValidated
    case beforeConditionalCommit
    case afterAtomicSwap
    case recoveryValidatedForDeletion
}

protocol ProjectPackageIOObserving: Sendable {
    func reached(_ checkpoint: ProjectPackageIOCheckpoint) async
}

enum ProjectPackageArtifactPolicy: Equatable, Sendable {
    case durable
    case recovery(ProjectID)
}

struct IdentityBoundPackageFileSystem: Sendable {
    private static let chunkBytes = 64 * 1_024
    private static let maximumMetadataBytes = 256 * 1_024

    let observer: (any ProjectPackageIOObserving)?

    init(observer: (any ProjectPackageIOObserving)? = nil) {
        self.observer = observer
    }

    func readSnapshot(from url: URL, maximumBytes: Int) async throws -> ValidatedPackageFileSnapshot {
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

        let initial: ValidatedPackageFileSnapshot?
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
        } else {
            try Self.requireMissing(opened.name, in: opened.descriptor)
            initial = nil
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
        var stagingExists = true
        defer {
            Darwin.close(stagingDescriptor)
            if stagingExists { _ = Darwin.unlinkat(opened.descriptor, stagingName, 0) }
        }

        try Self.writeAll(bytes, to: stagingDescriptor)
        try Self.apply(initial?.metadata ?? .secureNewFile, to: stagingDescriptor)
        guard Darwin.fsync(stagingDescriptor) == 0 else { throw Self.writeError(errno) }
        guard interruption == .none else { throw ProjectPackageError.interrupted }

        await observer?.reached(.beforeConditionalCommit)
        try Self.revalidate(opened, for: destination)

        let digest = Self.digest(bytes)
        if let expected, let initial {
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
            await observer?.reached(.afterAtomicSwap)
            do {
                let displaced = try Self.readFile(
                    named: stagingName,
                    in: opened.descriptor,
                    maximumBytes: ProjectPackageStore.maximumPackageBytes,
                    missing: .ioFailure,
                    unsafe: .unsafeDestination
                )
                guard displaced.fingerprint == expected, displaced.metadata == initial.metadata else {
                    throw ProjectPackageError.fileIdentityChanged
                }
            } catch {
                let rolledBack = Self.rollbackSwap(
                    stagingName: stagingName,
                    destinationName: opened.name,
                    in: opened.descriptor,
                    replacementIdentity: replacementIdentity
                )
                if !rolledBack {
                    // The displaced object is no longer safe to remove. Preserve it under
                    // the unpredictable staging name for explicit recovery rather than
                    // risk deleting unrelated bytes introduced during the race.
                    stagingExists = false
                } else if Darwin.unlinkat(opened.descriptor, stagingName, 0) == 0 {
                    // Rollback restored the changed external object. Remove only our own
                    // replacement inode and make the restored directory entry durable.
                    stagingExists = false
                }
                _ = Darwin.fsync(opened.descriptor)
                throw ProjectPackageError.fileIdentityChanged
            }
            guard Darwin.unlinkat(opened.descriptor, stagingName, 0) == 0 else {
                throw Self.writeError(errno)
            }
            stagingExists = false
        } else {
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
            stagingExists = false
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
    }

    func removeOwnedRecovery(
        at url: URL,
        expected: PackageFingerprint
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
        guard initial.fingerprint == expected else { throw ProjectPackageError.unsafeRecoveryArtifact }
        try initial.metadata.validateForRecoveryArtifact()
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
        guard Darwin.unlinkat(opened.descriptor, opened.name, 0) == 0 else {
            throw ProjectPackageError.recoveryDeletionFailed
        }
        guard Darwin.fsync(opened.descriptor) == 0 else {
            throw ProjectPackageError.recoveryDeletionFailed
        }
    }
}

private extension IdentityBoundPackageFileSystem {
    struct OpenedParent {
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
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL, standardized.path.hasPrefix("/"),
              !standardized.lastPathComponent.isEmpty else {
            throw ProjectPackageError.unsafeDestination
        }
        let parent = try openDirectory(standardized.deletingLastPathComponent(), createMissing: false)
        return OpenedParent(
            descriptor: parent.descriptor,
            identity: parent.identity,
            name: standardized.lastPathComponent
        )
    }

    static func openDirectory(_ url: URL, createMissing: Bool) throws -> OpenedDirectory {
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL, standardized.path.hasPrefix("/") else {
            throw ProjectPackageError.unsafeDestination
        }
        if createMissing, !FileManager.default.fileExists(atPath: standardized.path) {
            do {
                try FileManager.default.createDirectory(
                    at: standardized,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw ProjectPackageError.unsafeRecoveryArtifact
            }
        }
        let descriptor = Darwin.open(
            standardized.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw ProjectPackageError.unsafeDestination }
        let identity = try identity(of: descriptor)
        return OpenedDirectory(descriptor: descriptor, identity: identity)
    }

    static func revalidate(_ opened: OpenedParent, for url: URL) throws {
        let current = try openDirectory(url.standardizedFileURL.deletingLastPathComponent(), createMissing: false)
        defer { Darwin.close(current.descriptor) }
        guard current.identity == opened.identity else { throw ProjectPackageError.fileIdentityChanged }
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
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
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
            bytes.append(contentsOf: buffer[0..<count])
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              beforeVersion == version(after),
              bytes.count == Int(after.st_size) else {
            throw ProjectPackageError.fileIdentityChanged
        }
        let metadata = try securityMetadata(after, descriptor: descriptor)
        let identity = beforeVersion.identity
        return ValidatedPackageFileSnapshot(
            bytes: bytes,
            fingerprint: PackageFingerprint(
                digest: digest(bytes),
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

    static func rollbackSwap(
        stagingName: String,
        destinationName: String,
        in parent: Int32,
        replacementIdentity: PackageFileIdentity
    ) -> Bool {
        let currentDescriptor = Darwin.openat(parent, destinationName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard currentDescriptor >= 0 else { return false }
        defer { Darwin.close(currentDescriptor) }
        guard (try? identity(of: currentDescriptor)) == replacementIdentity else { return false }
        return Darwin.renameatx_np(
            parent,
            stagingName,
            parent,
            destinationName,
            UInt32(RENAME_SWAP)
        ) == 0
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
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
