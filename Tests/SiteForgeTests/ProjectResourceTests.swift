import CryptoKit
import XCTest
@testable import SiteForge

final class ProjectResourceTests: XCTestCase {
    private var fixtures: [ApplicationOwnedTestFixture] = []

    override func tearDownWithError() throws {
        for fixture in fixtures.reversed() { try fixture.cleanup() }
        fixtures.removeAll()
        try super.tearDownWithError()
    }

    func testRepresentativeFiveHundredAssetIndexIsDeterministicAndExceedsInlinePackageCapacity() async throws {
        let fixture = try makeFixture()
        let store = ProjectResourceStore(root: fixture.url.appendingPathComponent("Project.siteforge.resources-v1"))
        var descriptors: [ProjectResourceDescriptor] = []
        var totalBytes = 0

        for index in 0..<500 {
            let bytes = representativeAsset(index: index)
            totalBytes += bytes.count
            let id = try XCTUnwrap(ResourceID(uuidString: String(format: "50000000-0000-0000-0000-%012d", index + 1)))
            descriptors.append(try await store.put(
                id: id,
                filename: "asset-\(index).png",
                mediaType: "image/png",
                data: bytes
            ))
        }

        XCTAssertGreaterThan(totalBytes, ProjectPackageStore.maximumPackageBytes)
        let index = ProjectResourceIndex(resources: descriptors.reversed())
        try await store.validate(index)
        XCTAssertEqual(index.resources.count, 500)
        XCTAssertEqual(index.resources.map(\.id.description), index.resources.map(\.id.description).sorted())

        let package = try ProjectPackage(document: ProjectCreation.blank()).withResourceIndex(index)
        let packageBytes = try await ProjectPackageStore().encode(package)
        XCTAssertLessThan(packageBytes.count, ProjectPackageStore.maximumPackageBytes)
        let reopened = try await ProjectPackageStore().decode(packageBytes)
        XCTAssertEqual(try ProjectResourceIndex.decode(from: reopened), index)
        let reopenedAsset = try await store.data(for: index.resources[237])
        XCTAssertEqual(reopenedAsset, representativeAsset(index: 237))
    }

    func testResourceIndexRejectsDuplicateMalformedOversizedAndUnsupportedMetadata() throws {
        let valid = descriptor(id: "50000000-0000-0000-0000-000000000001", bytes: Data([1]))
        XCTAssertThrowsError(try ProjectResourceIndex(resources: [valid, valid]).validate()) {
            XCTAssertEqual($0 as? ProjectResourceError, .duplicateResource)
        }
        let malformed = ProjectResourceDescriptor(
            id: ResourceID(), filename: "../escape", mediaType: "image/png", byteCount: 1, sha256: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try ProjectResourceIndex(resources: [malformed]).validate())
        let oversized = ProjectResourceDescriptor(
            id: ResourceID(), filename: "large.bin", mediaType: "application/octet-stream",
            byteCount: ProjectResourceIndex.maximumResourceBytes + 1, sha256: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try ProjectResourceIndex(resources: [oversized]).validate())
        XCTAssertThrowsError(try ProjectResourceIndex(version: 2, resources: []).validate()) {
            XCTAssertEqual($0 as? ProjectResourceError, .unsupportedIndexVersion(2))
        }
        XCTAssertNil(try ProjectResourceIndex.decode(from: ProjectPackage(document: ProjectCreation.blank())))
    }

    func testResourceIndexRejectsUnknownFieldsAndIncorrectPackageRole() throws {
        let resource = descriptor(id: "50000000-0000-0000-0000-000000000001", bytes: Data([1]))
        let index = ProjectResourceIndex(resources: [resource])
        let encoded = try JSONEncoder().encode(index)

        var indexObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        indexObject["futureField"] = true
        let unknownIndex = try JSONSerialization.data(withJSONObject: indexObject)
        let unknownIndexPackage = ProjectPackage(
            document: ProjectCreation.blank(),
            optionalMembers: [.init(
                path: ProjectResourceIndex.packageMemberPath,
                role: .resource,
                data: unknownIndex
            )]
        )
        XCTAssertThrowsError(try ProjectResourceIndex.decode(from: unknownIndexPackage)) {
            XCTAssertEqual($0 as? ProjectResourceError, .corruptIndex)
        }

        var descriptorObject = try XCTUnwrap(
            (indexObject["resources"] as? [[String: Any]])?.first
        )
        descriptorObject["futureField"] = "unapproved"
        indexObject.removeValue(forKey: "futureField")
        indexObject["resources"] = [descriptorObject]
        let unknownDescriptor = try JSONSerialization.data(withJSONObject: indexObject)
        let unknownDescriptorPackage = ProjectPackage(
            document: ProjectCreation.blank(),
            optionalMembers: [.init(
                path: ProjectResourceIndex.packageMemberPath,
                role: .resource,
                data: unknownDescriptor
            )]
        )
        XCTAssertThrowsError(try ProjectResourceIndex.decode(from: unknownDescriptorPackage)) {
            XCTAssertEqual($0 as? ProjectResourceError, .corruptIndex)
        }

        let wrongRolePackage = ProjectPackage(
            document: ProjectCreation.blank(),
            optionalMembers: [.init(
                path: ProjectResourceIndex.packageMemberPath,
                role: .optional,
                data: encoded
            )]
        )
        XCTAssertThrowsError(try ProjectResourceIndex.decode(from: wrongRolePackage)) {
            XCTAssertEqual($0 as? ProjectResourceError, .corruptIndex)
        }
    }

    func testMissingAndCorruptResourcesAreRejectedWithoutChangingPackageBytes() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let store = ProjectResourceStore(root: root)
        let bytes = representativeAsset(index: 1)
        let resource = try await store.put(filename: "hero.png", mediaType: "image/png", data: bytes)
        let index = ProjectResourceIndex(resources: [resource])
        let package = try ProjectPackage(document: ProjectCreation.blank()).withResourceIndex(index)
        let packageStore = ProjectPackageStore()
        let packageBytes = try await packageStore.encode(package)

        try FileManager.default.removeItem(at: root.appendingPathComponent("\(resource.sha256).blob"))
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .missingBlob)
        let unchangedPackageBytes = try await packageStore.encode(package)
        XCTAssertEqual(packageBytes, unchangedPackageBytes, "resource failures must not mutate canonical package bytes")

        _ = try await store.put(id: resource.id, filename: resource.filename, mediaType: resource.mediaType, data: bytes)
        try Data(repeating: 0xff, count: bytes.count).write(to: root.appendingPathComponent("\(resource.sha256).blob"))
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .corruptBlob)
    }

    func testResourceValidationCancellationIsCooperativeAndStateNeutral() async throws {
        let fixture = try makeFixture()
        let base = ProjectResourceStore(root: fixture.url.appendingPathComponent("Resources"))
        let resource = try await base.put(filename: "asset.bin", mediaType: "application/octet-stream", data: representativeAsset(index: 4))
        let barrier = ResourceCancellationBarrier(blockAt: 2)
        let store = ProjectResourceStore(
            root: fixture.url.appendingPathComponent("Resources"),
            cancellation: CooperativeCancellationCheckpoint { try barrier.check() }
        )
        let task = Task { try await store.validate(ProjectResourceIndex(resources: [resource])) }
        await barrier.waitUntilBlocked()
        task.cancel()
        barrier.release()
        do {
            try await task.value
            XCTFail("cancelled validation must not succeed")
        } catch is CancellationError {}
        let unchanged = try await base.data(for: resource)
        XCTAssertEqual(unchanged, representativeAsset(index: 4))
    }

    func testResourceStoreRequiresRestrictiveDirectoryFileAndLinkMetadata() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let store = ProjectResourceStore(root: root)
        let resource = try await store.put(
            filename: "secure.bin", mediaType: "application/octet-stream", data: representativeAsset(index: 5)
        )
        let blob = root.appendingPathComponent("\(resource.sha256).blob")
        XCTAssertEqual(try permissions(at: root), 0o700)
        XCTAssertEqual(try permissions(at: blob), 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: blob.path)
        await XCTAssertThrowsErrorAsync(
            try await store.validate(ProjectResourceIndex(resources: [resource])), equals: .unsafeStore
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: blob.path)

        let alias = root.appendingPathComponent("linked.blob")
        try FileManager.default.linkItem(at: blob, to: alias)
        await XCTAssertThrowsErrorAsync(
            try await store.validate(ProjectResourceIndex(resources: [resource])), equals: .unsafeStore
        )
        try FileManager.default.removeItem(at: alias)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        await XCTAssertThrowsErrorAsync(
            try await store.validate(ProjectResourceIndex(resources: [resource])), equals: .unsafeStore
        )
    }

    func testResourceStoreRejectsExtendedACLsOnRootAndBlob() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let store = ProjectResourceStore(root: root)
        let resource = try await store.put(
            filename: "private.bin",
            mediaType: "application/octet-stream",
            data: representativeAsset(index: 6)
        )
        let index = ProjectResourceIndex(resources: [resource])
        let blob = root.appendingPathComponent("\(resource.sha256).blob")

        try run("/bin/chmod", arguments: ["+a", "everyone allow search", root.path])
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .unsafeStore)
        try run("/bin/chmod", arguments: ["-a", "everyone allow search", root.path])

        try run("/bin/chmod", arguments: ["+a", "everyone allow read", blob.path])
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .unsafeStore)
    }

    func testResourceStoreRemainsBoundToValidatedRootWhenPathIsExchanged() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let displaced = fixture.url.appendingPathComponent("Displaced")
        let redirected = fixture.url.appendingPathComponent("Redirected")
        let originalBytes = representativeAsset(index: 7)
        let base = ProjectResourceStore(root: root)
        let resource = try await base.put(
            filename: "original.bin",
            mediaType: "application/octet-stream",
            data: originalBytes
        )

        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: redirected.path)
        let redirectedBlob = redirected.appendingPathComponent("\(resource.sha256).blob")
        try Data(repeating: 0xff, count: originalBytes.count).write(to: redirectedBlob)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: redirectedBlob.path)

        let barrier = ResourceStoreDescriptorBarrier()
        let guarded = ProjectResourceStore(
            root: root,
            ioObserver: ProjectResourceIOObserver { phase in
                if case .storeDescriptorBound = phase { barrier.reachAndWait() }
            }
        )
        let read = Task { try await guarded.data(for: resource) }
        await barrier.waitUntilReached()
        try FileManager.default.moveItem(at: root, to: displaced)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: redirected)
        barrier.release()

        let readBytes = try await read.value
        XCTAssertEqual(readBytes, originalBytes)
        XCTAssertEqual(try Data(contentsOf: redirectedBlob), Data(repeating: 0xff, count: originalBytes.count))
    }

    func testResourceIndexSurvivesRecoveryPackageRoundTrip() async throws {
        let fixture = try makeFixture()
        let projectURL = fixture.url.appendingPathComponent("Recovered.siteforge")
        let store = ProjectResourceStore(root: ProjectResourceStore.sidecarURL(for: projectURL))
        let resource = try await store.put(filename: "recovered.jpg", mediaType: "image/jpeg", data: representativeAsset(index: 9))
        let index = ProjectResourceIndex(resources: [resource])
        let package = try ProjectPackage(document: ProjectCreation.blank()).withResourceIndex(index)
        let packageStore = ProjectPackageStore()
        try await packageStore.write(package, to: projectURL)
        let recovered = try await packageStore.read(from: projectURL)
        XCTAssertEqual(try ProjectResourceIndex.decode(from: recovered), index)
        try await store.validate(index)
    }

    func testRepositoryFixtureAllocatorIsUniqueContainedAndResidueFree() throws {
        let first = try RepositoryTestFixture.create("cleanup")
        let second = try RepositoryTestFixture.create("cleanup")
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(first.url.path.hasPrefix(RepositoryTestFixture.root.path + "/"))
        try Data("fixture".utf8).write(to: first.url.appendingPathComponent("nested.txt"))
        try first.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        try second.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.url.path))

        let outside = RepositoryTestFixture(url: FileManager.default.temporaryDirectory)
        XCTAssertThrowsError(try outside.cleanup())
    }

    private func makeFixture() throws -> ApplicationOwnedTestFixture {
        let fixture = try ApplicationOwnedTestFixture.create("resources")
        fixtures.append(fixture)
        return fixture
    }

    private func representativeAsset(index: Int) -> Data {
        var data = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        data.append(Data(repeating: UInt8(truncatingIfNeeded: index), count: 32 * 1_024 - data.count))
        return data
    }

    private func descriptor(id: String, bytes: Data) -> ProjectResourceDescriptor {
        ProjectResourceDescriptor(
            id: ResourceID(uuidString: id)!, filename: "asset.bin", mediaType: "application/octet-stream",
            byteCount: bytes.count, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private actor ResourceStoreDescriptorBarrier {
    private var hasReached = false
    private var reachedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    nonisolated func reachAndWait() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await markReached()
            await waitForRelease()
            semaphore.signal()
        }
        semaphore.wait()
    }

    func waitUntilReached() async {
        if hasReached { return }
        await withCheckedContinuation { reachedContinuation = $0 }
    }

    nonisolated func release() { Task { await releaseNow() } }

    private func markReached() {
        hasReached = true
        reachedContinuation?.resume()
        reachedContinuation = nil
    }

    private func waitForRelease() async {
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    private func releaseNow() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ResourceCancellationBarrier {
    private let blockAt: Int
    private var count = 0
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(blockAt: Int) { self.blockAt = blockAt }

    nonisolated func check() throws {
        try Task.checkCancellation()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let shouldBlock = await checkpoint()
            if shouldBlock { await waitForRelease() }
            semaphore.signal()
        }
        semaphore.wait()
        try Task.checkCancellation()
    }

    func waitUntilBlocked() async {
        if count >= blockAt { return }
        await withCheckedContinuation { blockedContinuation = $0 }
    }

    nonisolated func release() { Task { await releaseNow() } }

    private func checkpoint() -> Bool {
        count += 1
        if count == blockAt {
            blockedContinuation?.resume()
            blockedContinuation = nil
            return true
        }
        return false
    }

    private func waitForRelease() async { await withCheckedContinuation { releaseContinuation = $0 } }
    private func releaseNow() { releaseContinuation?.resume(); releaseContinuation = nil }
}

private func XCTAssertThrowsErrorAsync<T: Sendable>(
    _ expression: @autoclosure () async throws -> T,
    equals expected: ProjectResourceError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? ProjectResourceError, expected, file: file, line: line)
    }
}
