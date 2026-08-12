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
