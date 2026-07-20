import CryptoKit
import Darwin
import Foundation

enum ResourceIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "resource"
}

typealias ResourceID = StableIdentifier<ResourceIdentifierDomain>

struct ProjectResourceDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: ResourceID
    let filename: String
    let mediaType: String
    let byteCount: Int
    let sha256: String
}

struct ProjectResourceIndex: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let packageMemberPath = "resources/index-v1.json"
    static let maximumResourceCount = 2_000
    static let maximumResourceBytes = 16 * 1_024 * 1_024
    static let maximumTotalBytes = 2 * 1_024 * 1_024 * 1_024

    let version: Int
    let resources: [ProjectResourceDescriptor]

    init(version: Int = currentVersion, resources: [ProjectResourceDescriptor]) {
        self.version = version
        self.resources = resources.sorted { $0.id.description < $1.id.description }
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw ProjectResourceError.unsupportedIndexVersion(version) }
        guard resources.count <= Self.maximumResourceCount else { throw ProjectResourceError.capacityExceeded }
        var identities = Set<ResourceID>()
        var total = 0
        for resource in resources {
            guard identities.insert(resource.id).inserted else { throw ProjectResourceError.duplicateResource }
            guard !resource.filename.isEmpty,
                  !resource.filename.contains("/"),
                  !resource.filename.contains("\\"),
                  resource.filename != ".",
                  resource.filename != "..",
                  !resource.mediaType.isEmpty,
                  resource.byteCount > 0,
                  resource.byteCount <= Self.maximumResourceBytes,
                  resource.sha256.count == 64,
                  resource.sha256.allSatisfy({ $0.isHexDigit }) else {
                throw ProjectResourceError.malformedMetadata
            }
            let (next, overflow) = total.addingReportingOverflow(resource.byteCount)
            guard !overflow, next <= Self.maximumTotalBytes else { throw ProjectResourceError.capacityExceeded }
            total = next
        }
    }

    func encodedMember() throws -> ProjectPackageMember {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ProjectPackageMember(
            path: Self.packageMemberPath,
            role: .resource,
            data: try encoder.encode(self)
        )
    }

    static func decode(from package: ProjectPackage) throws -> ProjectResourceIndex? {
        guard let member = package.optionalMembers.first(where: { $0.path == packageMemberPath }) else {
            return nil
        }
        do {
            let value = try JSONDecoder().decode(Self.self, from: member.data)
            try value.validate()
            return value
        } catch let error as ProjectResourceError {
            throw error
        } catch {
            throw ProjectResourceError.corruptIndex
        }
    }
}

enum ProjectResourceError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedIndexVersion(Int)
    case duplicateResource
    case malformedMetadata
    case capacityExceeded
    case corruptIndex
    case missingBlob
    case corruptBlob
    case unsafeStore
    case ioFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedIndexVersion: "This project uses an unsupported resource-index version."
        case .duplicateResource: "The project resource index contains a duplicate stable identity."
        case .malformedMetadata: "The project resource metadata is malformed."
        case .capacityExceeded: "The project resources exceed the versioned capacity policy."
        case .corruptIndex: "The project resource index is corrupt."
        case .missingBlob: "A declared project resource is missing. Locate a complete project copy."
        case .corruptBlob: "A project resource failed its integrity check. Restore a valid copy."
        case .unsafeStore: "The resource store has unsafe ownership or link metadata."
        case .ioFailure: "A project resource could not be read or written."
        }
    }
}

actor ProjectResourceStore {
    static let requirementIDs: Set<String> = [
        "SF-0303-001", "SF-0303-008", "SF-1702-008", "SF-2002-008",
    ]

    let root: URL
    private let cancellation: CooperativeCancellationCheckpoint

    init(root: URL, cancellation: CooperativeCancellationCheckpoint = CooperativeCancellationCheckpoint()) {
        self.root = root
        self.cancellation = cancellation
    }

    static func sidecarURL(for packageURL: URL) -> URL {
        packageURL.appendingPathExtension("resources-v1")
    }

    func put(
        id: ResourceID = ResourceID(),
        filename: String,
        mediaType: String,
        data: Data
    ) throws -> ProjectResourceDescriptor {
        let digest = Self.digest(data)
        let descriptor = ProjectResourceDescriptor(
            id: id,
            filename: filename,
            mediaType: mediaType,
            byteCount: data.count,
            sha256: digest
        )
        try ProjectResourceIndex(resources: [descriptor]).validate()
        try prepareStore()
        try cancellation.check()
        let destination = blobURL(for: digest)
        if FileManager.default.fileExists(atPath: destination.path) {
            try validateBlob(descriptor)
            return descriptor
        }
        let temporary = root.appendingPathComponent(".stage-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            try synchronize(at: temporary, directory: false)
            try cancellation.check()
            if Darwin.link(temporary.path, destination.path) != 0 {
                if errno == EEXIST {
                    try? FileManager.default.removeItem(at: temporary)
                    try validateBlob(descriptor)
                } else {
                    throw ProjectResourceError.ioFailure
                }
            } else {
                try FileManager.default.removeItem(at: temporary)
                try synchronize(at: root, directory: true)
            }
            return descriptor
        } catch let error as ProjectResourceError {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: temporary)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw ProjectResourceError.ioFailure
        }
    }

    func validate(_ index: ProjectResourceIndex) throws {
        try index.validate()
        try prepareStore()
        for resource in index.resources {
            try cancellation.check()
            try validateBlob(resource)
        }
    }

    func data(for resource: ProjectResourceDescriptor) throws -> Data {
        try prepareStore()
        let descriptor = try openBlob(resource)
        defer { Darwin.close(descriptor) }
        var result = Data()
        result.reserveCapacity(resource.byteCount)
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            try cancellation.check()
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw ProjectResourceError.ioFailure }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        guard result.count == resource.byteCount, Self.digest(result) == resource.sha256 else {
            throw ProjectResourceError.corruptBlob
        }
        return result
    }

    private func prepareStore() throws {
        var info = stat()
        if lstat(root.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR,
                  info.st_uid == getuid(),
                  (info.st_mode & 0o077) == 0 else {
                throw ProjectResourceError.unsafeStore
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            } catch {
                throw ProjectResourceError.ioFailure
            }
        }
    }

    private func blobURL(for digest: String) -> URL {
        root.appendingPathComponent("\(digest).blob", isDirectory: false)
    }

    private func validateBlob(_ resource: ProjectResourceDescriptor) throws {
        let descriptor = try openBlob(resource)
        defer { Darwin.close(descriptor) }
        var hasher = SHA256()
        var remaining = resource.byteCount
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while remaining > 0 {
            try cancellation.check()
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, remaining))
            guard count > 0 else { throw ProjectResourceError.corruptBlob }
            hasher.update(data: Data(buffer[0..<count]))
            remaining -= count
        }
        var extra: UInt8 = 0
        guard Darwin.read(descriptor, &extra, 1) == 0,
              hasher.finalize().map({ String(format: "%02x", $0) }).joined() == resource.sha256 else {
            throw ProjectResourceError.corruptBlob
        }
    }

    private func openBlob(_ resource: ProjectResourceDescriptor) throws -> Int32 {
        let path = blobURL(for: resource.sha256).path
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw errno == ENOENT ? ProjectResourceError.missingBlob : ProjectResourceError.unsafeStore
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              (info.st_mode & 0o077) == 0,
              info.st_size == resource.byteCount,
              info.st_size <= ProjectResourceIndex.maximumResourceBytes else {
            Darwin.close(descriptor)
            throw ProjectResourceError.unsafeStore
        }
        return descriptor
    }

    private func synchronize(at url: URL, directory: Bool) throws {
        let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (directory ? O_DIRECTORY : 0)
        let descriptor = Darwin.open(url.path, flags)
        guard descriptor >= 0 else { throw ProjectResourceError.ioFailure }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw ProjectResourceError.ioFailure }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension ProjectPackage {
    func withResourceIndex(_ index: ProjectResourceIndex) throws -> ProjectPackage {
        let member = try index.encodedMember()
        return ProjectPackage(
            projectID: projectID,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            document: document,
            optionalMembers: optionalMembers.filter { $0.path != ProjectResourceIndex.packageMemberPath } + [member],
            compatibility: compatibility
        )
    }
}
