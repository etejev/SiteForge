import Darwin
import Foundation

/// SF-0306-003/004/005: qualifies an automatic offer, never authority to restore,
/// replace or retire recovery. Package ownership validation remains unchanged.
final class RecoverySessionEvidence: @unchecked Sendable {
    static let shared = RecoverySessionEvidence()
    static let memberPath = "recovery/session-v1"
    private static let running = Data("SFRS1:R\n".utf8)
    private let lock = NSLock()
    private let sessionID = UUID()
    private var descriptors: [String: Int32] = [:]
    private var ended = false

    deinit { for descriptor in descriptors.values { Darwin.close(descriptor) } }

    /// Runs on the backend actor. A held advisory lock distinguishes a live app
    /// from an abandoned session without PID reuse or process enumeration.
    func tagging(_ package: ProjectPackage, in directory: URL) throws -> ProjectPackage {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { throw CancellationError() }
        let root = try Self.openDirectory(directory)
        defer { Darwin.close(root) }
        let key = directory.standardizedFileURL.path
        if descriptors[key] == nil {
            guard descriptors.count < 256 else { throw ProjectPackageError.oversizedInput }
            let fd = Darwin.openat(root, Self.filename(sessionID),
                O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else { throw ProjectPackageError.unsafeRecoveryArtifact }
            do {
                try Self.validate(fd, directory: false)
                guard flock(fd, LOCK_EX | LOCK_NB) == 0,
                      Self.running.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == Self.running.count,
                      fsync(fd) == 0, fsync(root) == 0 else { throw ProjectPackageError.unsafeRecoveryArtifact }
                descriptors[key] = fd
            } catch { Darwin.close(fd); throw error }
        }
        return Self.replacingEvidence(in: package, with: .init(path: Self.memberPath,
            data: Data(Self.receipt(sessionID, package: package).utf8)))
    }

    /// AppKit termination is synchronous. Touch only fixed-size already-open
    /// descriptors: no scan, package save, async task or model publication.
    func markCleanShutdown() {
        lock.lock(); defer { lock.unlock() }
        ended = true
        for descriptor in descriptors.values {
            var byte: UInt8 = 67
            if Darwin.pwrite(descriptor, &byte, 1, 6) == 1 { _ = fsync(descriptor) }
        }
    }

    static func removingEvidence(from package: ProjectPackage) -> ProjectPackage {
        replacingEvidence(in: package, with: nil)
    }

    private static func replacingEvidence(in package: ProjectPackage, with member: ProjectPackageMember?) -> ProjectPackage {
        var members = package.optionalMembers.filter { $0.path != memberPath }
        if let member { members.append(member) }
        return ProjectPackage(projectID: package.projectID, createdAt: package.createdAt,
            modifiedAt: package.modifiedAt, document: package.document,
            optionalMembers: members, compatibility: package.compatibility)
    }

    func qualifiesForAutomaticRecovery(_ package: ProjectPackage, in directory: URL) -> Bool {
        let members = package.optionalMembers.filter { $0.path == Self.memberPath }
        guard members.count == 1, members[0].role == .optional,
              members[0].data.count <= 160,
              let text = String(data: members[0].data, encoding: .utf8) else { return false }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "SFR1", let id = UUID(uuidString: String(parts[1])),
              text == Self.receipt(id, package: package) else { return false }
        do {
            let root = try Self.openDirectory(directory)
            defer { Darwin.close(root) }
            let fd = Darwin.openat(root, Self.filename(id), O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { return false }
            defer { Darwin.close(fd) }
            try Self.validate(fd, directory: false)
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
            defer { _ = flock(fd, LOCK_UN) }
            var bytes = [UInt8](repeating: 0, count: Self.running.count + 1)
            let count = Darwin.pread(fd, &bytes, bytes.count, 0)
            return count == Self.running.count && Data(bytes.prefix(count)) == Self.running
        } catch { return false }
    }

    private static func filename(_ id: UUID) -> String { ".session-\(id.uuidString.lowercased()).v1" }

    private static func receipt(_ id: UUID, package: ProjectPackage) -> String {
        "SFR1:\(id.uuidString.lowercased()):\(package.projectID.description):\(package.document.id.description):\(package.document.revision)"
    }

    private static func openDirectory(_ url: URL) throws -> Int32 {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ProjectPackageError.unsafeRecoveryArtifact }
        do { try validate(fd, directory: true); return fd }
        catch { Darwin.close(fd); throw error }
    }

    private static func validate(_ fd: Int32, directory: Bool) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1 else { throw ProjectPackageError.unsafeRecoveryArtifact }
        errno = 0
        if let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) {
            acl_free(UnsafeMutableRawPointer(acl))
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
        guard errno == ENOENT || errno == ENOTSUP || errno == EOPNOTSUPP else {
            throw ProjectPackageError.unsafeRecoveryArtifact
        }
    }
}
