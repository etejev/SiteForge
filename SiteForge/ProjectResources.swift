import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageImportError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, permissionDenied, unsupported, corrupt, tooLarge, invalidDimensions, ioFailure
    var errorDescription: String? {
        switch self {
        case .cancelled: "Image import was cancelled."
        case .permissionDenied: "SiteForge cannot read the selected image. Choose an accessible local file."
        case .unsupported: "This image type is not supported. Choose PNG, JPEG, GIF, TIFF, or HEIC."
        case .corrupt: "The selected image is corrupt or cannot be decoded."
        case .tooLarge: "The selected image exceeds the 16 MB project-resource limit."
        case .invalidDimensions: "The selected image dimensions exceed the supported range."
        case .ioFailure: "The selected image could not be imported."
        }
    }
    var diagnosticCategory: String {
        switch self {
        case .cancelled: "cancelled"
        case .permissionDenied: "permission-denied"
        case .unsupported: "unsupported-format"
        case .corrupt: "decode-failed"
        case .tooLarge: "resource-limit"
        case .invalidDimensions: "dimension-limit"
        case .ioFailure: "io-failure"
        }
    }
}

struct PreparedImageImport: Sendable {
    let asset: ImageAsset
    let descriptor: ProjectResourceDescriptor
    let data: Data
}

/// Image byte loading and metadata decoding stay actor-isolated. Results are
/// immutable and identity-tagged before the main actor performs the canonical
/// transaction, so stale imports can be ignored without publishing drafts.
actor ImageImportWorker {
    func prepare(url: URL) throws -> PreparedImageImport {
        try Task.checkCancellation()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch CocoaError.fileReadNoPermission { throw ImageImportError.permissionDenied }
        catch { throw ImageImportError.ioFailure }
        guard !data.isEmpty else { throw ImageImportError.corrupt }
        guard data.count <= ProjectResourceIndex.maximumResourceBytes else { throw ImageImportError.tooLarge }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageImportError.corrupt
        }
        guard (1...ImageAsset.maximumPixelDimension).contains(width),
              (1...ImageAsset.maximumPixelDimension).contains(height) else {
            throw ImageImportError.invalidDimensions
        }
        let sourceType = CGImageSourceGetType(source) as String?
        let format: ImageAssetFormat = switch sourceType {
        case UTType.png.identifier: .png
        case UTType.jpeg.identifier: .jpeg
        case UTType.gif.identifier: .gif
        case UTType.tiff.identifier: .tiff
        case UTType.heic.identifier, UTType.heif.identifier: .heic
        default: throw ImageImportError.unsupported
        }
        guard CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) != nil else { throw ImageImportError.corrupt }
        let hash = ProjectResourceStore.digest(data)
        let resourceID = ResourceID()
        let filename = String(url.lastPathComponent.prefix(255))
        let stem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = stem.isEmpty ? "Imported Image" : String(stem.prefix(255))
        let descriptor = ProjectResourceDescriptor(
            id: resourceID, filename: filename, mediaType: format.mediaType,
            byteCount: data.count, sha256: hash
        )
        return PreparedImageImport(
            asset: ImageAsset(
                resourceID: resourceID, displayName: displayName,
                originalFilename: filename, format: format,
                pixelWidth: width, pixelHeight: height,
                byteCount: data.count, contentHash: hash
            ),
            descriptor: descriptor, data: data
        )
    }
}

/// Produces bounded preview data away from the main actor. The canonical
/// resource remains byte-for-byte unchanged; this derivative is scene-local
/// editor state and is never serialized or entered into document history.
actor ImageThumbnailWorker {
    func thumbnailPNG(from data: Data, maximumPixelSize: Int = 160) throws -> Data {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            throw ImageImportError.corrupt
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw ImageImportError.ioFailure }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageImportError.ioFailure }
        return output as Data
    }
}

struct ProjectResourceDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: ResourceID
    let filename: String
    let mediaType: String
    let byteCount: Int
    let sha256: String
}

extension ProjectResourceDescriptor {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, filename, mediaType, byteCount, sha256
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ResourceID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
    }
}

struct ProjectResourceIndex: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let packageMemberPath = "resources/index-v1.json"
    static let maximumResourceCount = ImageAsset.maximumAssetCount
    static let maximumResourceBytes = ImageAsset.maximumResourceBytes
    static let maximumTotalBytes = 2 * 1_024 * 1_024 * 1_024

    static func blobMemberPath(for sha256: String) -> String {
        "resources/blobs/\(sha256).blob"
    }

    let version: Int
    let resources: [ProjectResourceDescriptor]

    init(version: Int = currentVersion, resources: [ProjectResourceDescriptor]) {
        self.version = version
        self.resources = resources.sorted { $0.id.description < $1.id.description }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, resources
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let decoded = try container.decode([ProjectResourceDescriptor].self, forKey: .resources)
        let canonical = decoded.sorted { $0.id.description < $1.id.description }
        guard decoded == canonical else {
            throw DecodingError.dataCorruptedError(
                forKey: .resources,
                in: container,
                debugDescription: "Resource descriptors must use stable-identity order."
            )
        }
        resources = decoded
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
                  resource.sha256 == resource.sha256.lowercased(),
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
        guard member.role == .resource else { throw ProjectResourceError.corruptIndex }
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

enum ProjectResourceIOPhase: Sendable {
    case storeDescriptorBound
}

struct ProjectResourceIOObserver: Sendable {
    let didReach: @Sendable (ProjectResourceIOPhase) -> Void

    init(didReach: @escaping @Sendable (ProjectResourceIOPhase) -> Void = { _ in }) {
        self.didReach = didReach
    }
}

actor ProjectResourceStore {
    static let requirementIDs: Set<String> = [
        "SF-0303-001", "SF-0303-008", "SF-1702-008", "SF-2002-008",
    ]

    let root: URL
    private let cancellation: CooperativeCancellationCheckpoint
    private let ioObserver: ProjectResourceIOObserver

    init(
        root: URL,
        cancellation: CooperativeCancellationCheckpoint = CooperativeCancellationCheckpoint(),
        ioObserver: ProjectResourceIOObserver = ProjectResourceIOObserver()
    ) {
        self.root = root
        self.cancellation = cancellation
        self.ioObserver = ioObserver
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
        let storeDescriptor = try openStore()
        defer { Darwin.close(storeDescriptor) }
        try cancellation.check()
        let destinationName = blobName(for: digest)
        var destinationInformation = stat()
        if Darwin.fstatat(
            storeDescriptor,
            destinationName,
            &destinationInformation,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            try validateBlob(descriptor, storeDescriptor: storeDescriptor)
            return descriptor
        }
        guard errno == ENOENT else { throw ProjectResourceError.unsafeStore }

        let temporaryName = ".stage-\(UUID().uuidString.lowercased())"
        let temporaryDescriptor = Darwin.openat(
            storeDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard temporaryDescriptor >= 0 else { throw ProjectResourceError.ioFailure }
        var temporaryIsOpen = true
        defer {
            if temporaryIsOpen { Darwin.close(temporaryDescriptor) }
            _ = Darwin.unlinkat(storeDescriptor, temporaryName, 0)
        }
        do {
            guard Darwin.fchmod(temporaryDescriptor, mode_t(0o600)) == 0,
                  try !Self.hasExtendedACL(temporaryDescriptor) else {
                throw ProjectResourceError.unsafeStore
            }
            try Self.writeAll(data, to: temporaryDescriptor)
            guard Darwin.fsync(temporaryDescriptor) == 0 else { throw ProjectResourceError.ioFailure }
            try cancellation.check()
            if Darwin.linkat(storeDescriptor, temporaryName, storeDescriptor, destinationName, 0) != 0 {
                if errno == EEXIST {
                    try validateBlob(descriptor, storeDescriptor: storeDescriptor)
                } else {
                    throw ProjectResourceError.ioFailure
                }
            } else {
                guard Darwin.fsync(storeDescriptor) == 0 else { throw ProjectResourceError.ioFailure }
            }
            Darwin.close(temporaryDescriptor)
            temporaryIsOpen = false
            return descriptor
        } catch let error as ProjectResourceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectResourceError.ioFailure
        }
    }

    func validate(_ index: ProjectResourceIndex) throws {
        try index.validate()
        let storeDescriptor = try openStore()
        defer { Darwin.close(storeDescriptor) }
        for resource in index.resources {
            try cancellation.check()
            try validateBlob(resource, storeDescriptor: storeDescriptor)
        }
    }

    func data(for resource: ProjectResourceDescriptor) throws -> Data {
        let storeDescriptor = try openStore()
        defer { Darwin.close(storeDescriptor) }
        let descriptor = try openBlob(resource, storeDescriptor: storeDescriptor)
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

    private func openStore() throws -> Int32 {
        var info = stat()
        if lstat(root.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR,
                  info.st_uid == geteuid(),
                  (info.st_mode & 0o077) == 0 else {
                throw ProjectResourceError.unsafeStore
            }
        } else {
            guard errno == ENOENT else { throw ProjectResourceError.ioFailure }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            } catch {
                throw ProjectResourceError.ioFailure
            }
        }
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProjectResourceError.unsafeStore }
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & 0o077) == 0,
              try !Self.hasExtendedACL(descriptor) else {
            Darwin.close(descriptor)
            throw ProjectResourceError.unsafeStore
        }
        ioObserver.didReach(.storeDescriptorBound)
        return descriptor
    }

    private func blobName(for digest: String) -> String {
        "\(digest).blob"
    }

    private func validateBlob(
        _ resource: ProjectResourceDescriptor,
        storeDescriptor: Int32
    ) throws {
        let descriptor = try openBlob(resource, storeDescriptor: storeDescriptor)
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

    private func openBlob(
        _ resource: ProjectResourceDescriptor,
        storeDescriptor: Int32
    ) throws -> Int32 {
        let descriptor = Darwin.openat(
            storeDescriptor,
            blobName(for: resource.sha256),
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
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
              info.st_size <= ProjectResourceIndex.maximumResourceBytes,
              try !Self.hasExtendedACL(descriptor) else {
            Darwin.close(descriptor)
            throw ProjectResourceError.unsafeStore
        }
        return descriptor
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ProjectResourceError.ioFailure }
                offset += count
            }
        }
    }

    private static func hasExtendedACL(_ descriptor: Int32) throws -> Bool {
        errno = 0
        guard let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT || errno == ENOTSUP || errno == EOPNOTSUPP { return false }
            throw ProjectResourceError.unsafeStore
        }
        Darwin.acl_free(UnsafeMutableRawPointer(acl))
        return true
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension ProjectPackage {
    static func isTransientResourceBlobPath(_ path: String) -> Bool {
        path.hasPrefix("resources/blobs/") && path.hasSuffix(".blob")
    }

    var archiveOptionalMembers: [ProjectPackageMember] {
        optionalMembers.filter { !Self.isTransientResourceBlobPath($0.path) }
    }

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

    func withResource(_ descriptor: ProjectResourceDescriptor, data: Data) throws -> ProjectPackage {
        guard descriptor.byteCount == data.count,
              descriptor.sha256 == ProjectResourceStore.digest(data) else {
            throw ProjectResourceError.corruptBlob
        }
        var resources = try ProjectResourceIndex.decode(from: self)?.resources ?? []
        resources.removeAll { $0.id == descriptor.id }
        resources.append(descriptor)
        let index = ProjectResourceIndex(resources: resources)
        let indexed = try withResourceIndex(index)
        let path = ProjectResourceIndex.blobMemberPath(for: descriptor.sha256)
        let blob = ProjectPackageMember(path: path, role: .resource, data: data)
        return ProjectPackage(
            projectID: indexed.projectID,
            createdAt: indexed.createdAt,
            modifiedAt: indexed.modifiedAt,
            document: indexed.document,
            optionalMembers: indexed.optionalMembers.filter { $0.path != path } + [blob],
            compatibility: indexed.compatibility
        )
    }

    func resourceData(for descriptor: ProjectResourceDescriptor) throws -> Data {
        let path = ProjectResourceIndex.blobMemberPath(for: descriptor.sha256)
        guard let member = optionalMembers.first(where: { $0.path == path }) else {
            throw ProjectResourceError.missingBlob
        }
        guard member.role == .resource,
              member.data.count == descriptor.byteCount,
              ProjectResourceStore.digest(member.data) == descriptor.sha256 else {
            throw ProjectResourceError.corruptBlob
        }
        return member.data
    }

    func attachingResourceData(_ resources: [ResourceID: Data]) throws -> ProjectPackage {
        guard let index = try ProjectResourceIndex.decode(from: self) else { return self }
        var members = archiveOptionalMembers
        for descriptor in index.resources {
            guard let data = resources[descriptor.id] else { continue }
            guard data.count == descriptor.byteCount,
                  ProjectResourceStore.digest(data) == descriptor.sha256 else {
                throw ProjectResourceError.corruptBlob
            }
            members.append(.init(
                path: ProjectResourceIndex.blobMemberPath(for: descriptor.sha256),
                role: .resource,
                data: data
            ))
        }
        return ProjectPackage(
            projectID: projectID, createdAt: createdAt, modifiedAt: modifiedAt,
            document: document, optionalMembers: members, compatibility: compatibility
        )
    }
}
