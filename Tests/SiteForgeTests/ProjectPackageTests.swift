import CryptoKit
import XCTest
@testable import SiteForge

final class ProjectPackageTests: XCTestCase {
    private let projectID = ProjectID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
    private let documentID = DocumentID(UUID(uuidString: "20000000-0000-0000-0000-000000000001")!)
    private let pageID = PageID(UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)

    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/.tmp", isDirectory: true)
    }

    private func fixtureDirectory() throws -> URL {
        let directory = fixtureRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func package(
        pageName: String = "Home",
        optionalMembers: [ProjectPackageMember] = []
    ) -> ProjectPackage {
        ProjectPackage(
            projectID: projectID,
            createdAt: ProjectTimestamp("2026-07-19T12:00:00.000Z"),
            modifiedAt: ProjectTimestamp("2026-07-19T12:30:00.000Z"),
            document: CanonicalDocument(
                id: documentID,
                revision: 7,
                pages: [DocumentPage(id: pageID, name: pageName)]
            ),
            optionalMembers: optionalMembers
        )
    }

    // SF-0301-001, SF-0301-003, SF-1702-001
    func testCanonicalPackageBytesAreDeterministicAndVersioned() async throws {
        let store = ProjectPackageStore()
        let value = package(optionalMembers: [
            ProjectPackageMember(path: "resources/hero.bin", role: .resource, data: Data([3, 2, 1])),
            ProjectPackageMember(path: "extensions/future.dat", data: Data("future".utf8)),
        ])

        let first = try await store.encode(value)
        let second = try await store.encode(value)

        XCTAssertEqual(first, second)
        let members = try decodeArchive(first)
        let manifest = try XCTUnwrap(members.first(where: { $0.path == "manifest.json" }))
        let text = String(decoding: manifest.data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"packageVersion\":1"))
        XCTAssertTrue(text.contains("\"documentSchemaVersion\":2"))
        XCTAssertTrue(text.contains(projectID.description))
        XCTAssertTrue(text.contains("\"sha256\""))
    }

    // SF-0301-001, SF-1702-001, SF-1702-008
    func testSuccessfulRoundTripPreservesIdentityMetadataResourcesAndDocument() async throws {
        let store = ProjectPackageStore()
        let original = package(optionalMembers: [
            ProjectPackageMember(path: "resources/logo.bin", role: .resource, data: Data([0, 1, 2]))
        ])

        let encoded = try await store.encode(original)
        let decoded = try await store.decode(encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.projectID, projectID)
        XCTAssertEqual(decoded.document.id, documentID)
    }

    // SF-0301-004, SF-0301-007, SF-0301-008
    func testCancellationInsideContainerAndCanonicalValidationIsDistinctAndNonAdopting() async throws {
        let encoded = try await ProjectPackageStore().encode(package())
        let barrier = DeterministicCancellationBarrier(blockAt: 4)
        let store = ProjectPackageStore(cancellation: CooperativeCancellationCheckpoint(barrier.check))
        let task = Task { try await store.decode(encoded) }

        await barrier.waitUntilBlocked()
        task.cancel()
        barrier.release()

        do {
            _ = try await task.value
            XCTFail("Cancelled package validation must not return a package")
        } catch is CancellationError {
            // Cancellation is intentionally distinct from corrupt input.
        }
    }

    // SF-0301-005, SF-0303-005, SF-0303-008, SF-1702-008
    func testImmutableSchemaOneEmptyGoldenMigratesDeterministicallyAndWithoutHistory() async throws {
        let store = ProjectPackageStore()
        let historyStore = PersistedHistoryStore()
        let legacyPackage = try legacyGolden(
            named: "schema-v1-empty",
            sha256: "b5a46c3ddc705b978324e17a5e0b9912155950b2a7c05b36e07117bae4d98576"
        )

        let first = try await store.decode(legacyPackage)
        let second = try await store.decode(legacyPackage)
        XCTAssertEqual(first.projectID.description, "11000000-0000-0000-0000-000000000001")
        XCTAssertEqual(first.document.id.description, "21000000-0000-0000-0000-000000000001")
        XCTAssertEqual(first.document.creationKind, .migratedLegacy)
        XCTAssertEqual(first.document.pages.map(\.name), ["Home", "Not Found"])
        XCTAssertEqual(first.document.pages.map(\.route.rawValue), ["/", "/404"])
        XCTAssertEqual(first.document.pages.map(\.role), [.home, .notFound])
        XCTAssertEqual(first.document.pages.map(\.provenance), [.migratedLegacy, .migratedLegacy])
        XCTAssertEqual(first.document.pages.map(\.id.description), [
            "7dbd7acf-dc5a-5f0d-90c5-77b9c590c4e7",
            "c24169c4-4ee6-57fd-b673-d828c32edbbb",
        ])
        XCTAssertEqual(first.document.pages.flatMap(\.rootNodeIDs).map(\.description), [
            "0cc53b20-9703-5c29-82c6-54745199eb91",
            "c14c57c6-b3fb-531f-be51-2188bc3e44b4",
        ])
        XCTAssertEqual(first, second)
        XCTAssertNoThrow(try first.document.validate())
        let history = try await historyStore.load(from: first)
        XCTAssertEqual(history, .cleanBaseline(.missing))

        let savedOnce = try await store.encode(first)
        let savedTwice = try await store.encode(first)
        XCTAssertEqual(savedOnce, savedTwice)
        let reopened = try await store.decode(savedOnce)
        XCTAssertEqual(reopened, first)
    }

    // SF-0301-005, SF-0303-005, SF-0303-008, SF-1702-008
    func testImmutableSchemaOneRootlessGoldenPreservesIdentityAndAddsOnlyMinimumRoot() async throws {
        let store = ProjectPackageStore()
        let legacyPackage = try legacyGolden(
            named: "schema-v1-rootless",
            sha256: "ef1455c5eb9055ec97fb5d41562686226e9db040313a4609e769cc5f7f44694d"
        )

        let first = try await store.decode(legacyPackage)
        let second = try await store.decode(legacyPackage)
        let page = try XCTUnwrap(first.document.pages.only)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.document.revision, 4)
        XCTAssertEqual(first.document.creationKind, .migratedLegacy)
        XCTAssertEqual(page.id.description, "31000000-0000-0000-0000-000000000002")
        XCTAssertEqual(page.name, "Legacy Landing")
        XCTAssertEqual(page.route.rawValue, "/legacy-landing")
        XCTAssertEqual(page.role, .standard)
        XCTAssertEqual(page.provenance, .migratedLegacy)
        XCTAssertEqual(page.rootNodeIDs.map(\.description), ["2a3ba9f8-b7dd-522b-8726-a319ed8a731b"])
        XCTAssertEqual(page.nodes.map(\.id), page.rootNodeIDs)
        XCTAssertNoThrow(try first.document.validate())

        let resaved = try await store.encode(first)
        let reopened = try await store.decode(resaved)
        XCTAssertEqual(reopened, first)
    }

    // SF-0301-004, SF-0301-005, SF-1702-004, SF-1702-008
    func testInvalidSchemaOneGoldenVariantsAreRejectedWithoutCompatibilityDefaults() async throws {
        let store = ProjectPackageStore()
        let golden = try legacyGolden(
            named: "schema-v1-rootless",
            sha256: "ef1455c5eb9055ec97fb5d41562686226e9db040313a4609e769cc5f7f44694d"
        )
        let members = try decodeArchive(golden)
        let documentMember = try XCTUnwrap(members.first { $0.path == "document.json" })
        let original = try XCTUnwrap(
            JSONSerialization.jsonObject(with: documentMember.data) as? [String: Any]
        )

        for field in ["id", "pages"] {
            var envelope = original
            var document = try XCTUnwrap(envelope["document"] as? [String: Any])
            document.removeValue(forKey: field)
            envelope["document"] = document
            let invalid = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            let archive = try replacingDocumentAndIntegrity(in: members, with: invalid)
            await XCTAssertThrowsProjectPackageError(.corruptDocument) {
                try await store.decode(encodeArchive(archive))
            }
        }
    }

    // SF-0301-004, SF-1702-004
    func testAtomicReplacementCommitsOnlyCompletePackage() async throws {
        let directory = try fixtureDirectory()
        let destination = directory.appendingPathComponent("Project.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(pageName: "Before"), to: destination)
        let expected = try await store.readSnapshot(from: destination).file.fingerprint

        try await store.write(package(pageName: "After"), to: destination, expected: expected)

        let loaded = try await store.read(from: destination)
        XCTAssertEqual(loaded.document.pages[0].name, "After")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
            $0.hasPrefix(".siteforge-stage-")
        })
    }

    // SF-0301-004, SF-1702-004
    func testSimulatedInterruptionLeavesLastValidPackageByteForByteUnchanged() async throws {
        let destination = try fixtureDirectory().appendingPathComponent("Project.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(pageName: "Committed"), to: destination)
        let expected = try await store.readSnapshot(from: destination).file.fingerprint
        let before = try Data(contentsOf: destination)

        await XCTAssertThrowsProjectPackageError(.interrupted) {
            try await store.write(
                package(pageName: "Interrupted"),
                to: destination,
                expected: expected,
                interruption: .beforeReplacement
            )
        }

        XCTAssertEqual(try Data(contentsOf: destination), before)
        let preserved = try await store.read(from: destination)
        XCTAssertEqual(preserved.document.pages[0].name, "Committed")
    }

    // SF-0301-003, SF-1702-001
    func testUnknownOptionalMemberIsPreservedByteForByteAcrossRoundTrip() async throws {
        let store = ProjectPackageStore()
        let unknown = ProjectPackageMember(
            path: "vendor/future-extension.payload",
            role: .optional,
            data: Data([0, 255, 4, 9, 42])
        )
        let encoded = try await store.encode(package(optionalMembers: [unknown]))

        let decoded = try await store.decode(encoded)
        let reencoded = try await store.encode(decoded)

        XCTAssertEqual(decoded.optionalMembers, [unknown])
        XCTAssertEqual(reencoded, encoded)
    }

    // SF-0301-004, SF-1702-004
    func testMissingAndCorruptRequiredMembersAreRejected() async throws {
        let store = ProjectPackageStore()
        let valid = try await store.encode(package())
        let members = try decodeArchive(valid)

        await XCTAssertThrowsProjectPackageError(.missingManifest) {
            try await store.decode(encodeArchive(members.filter { $0.path != "manifest.json" }))
        }
        await XCTAssertThrowsProjectPackageError(.missingDocument) {
            try await store.decode(encodeArchive(members.filter { $0.path != "document.json" }))
        }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(replacing("manifest.json", with: Data("{".utf8), in: members)))
        }

        let corruptDocument = try replacingDocumentAndIntegrity(in: members, with: Data("not-json".utf8))
        await XCTAssertThrowsProjectPackageError(.corruptDocument) {
            try await store.decode(encodeArchive(corruptDocument))
        }
    }

    // SF-0301-004, SF-1702-004, SF-1702-008
    func testUnsupportedPackageDocumentAndReaderVersionsAreActionable() async throws {
        let store = ProjectPackageStore()
        let encoded = try await store.encode(package())
        let members = try decodeArchive(encoded)

        let packageVersion = try editingManifest(in: members) { $0["packageVersion"] = 99 }
        await XCTAssertThrowsProjectPackageError(.unsupportedPackageVersion(99)) {
            try await store.decode(encodeArchive(packageVersion))
        }

        let schemaVersion = try editingManifest(in: members) { $0["documentSchemaVersion"] = 99 }
        await XCTAssertThrowsProjectPackageError(.unsupportedDocumentSchema(99)) {
            try await store.decode(encodeArchive(schemaVersion))
        }

        let readerVersion = try editingManifest(in: members) { manifest in
            var compatibility = manifest["compatibility"] as! [String: Any]
            compatibility["minimumPackageReaderVersion"] = 99
            manifest["compatibility"] = compatibility
        }
        await XCTAssertThrowsProjectPackageError(.incompatibleReaderVersion(99)) {
            try await store.decode(encodeArchive(readerVersion))
        }
    }

    // SF-0301-004, SF-1702-004
    func testPathTraversalDuplicateAndOversizedInputsAreRejected() async throws {
        let store = ProjectPackageStore()
        let encoded = try await store.encode(package())
        let members = try decodeArchive(encoded)

        await XCTAssertThrowsProjectPackageError(.invalidMemberPath) {
            try await store.decode(encodeArchive(members + [ArchiveMember(path: "../escape", data: Data())]))
        }
        await XCTAssertThrowsProjectPackageError(.duplicateMember) {
            try await store.decode(encodeArchive(members + [members[0]]))
        }
        await XCTAssertThrowsProjectPackageError(.oversizedInput) {
            try await store.decode(Data(repeating: 0, count: ProjectPackageStore.maximumPackageBytes + 1))
        }
    }

    // SF-0301-004, SF-1702-004
    func testSymbolicLinkSourceAndDestinationEscapeAreRejected() async throws {
        let directory = try fixtureDirectory()
        let real = directory.appendingPathComponent("Real.siteforge")
        let link = directory.appendingPathComponent("Linked.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(), to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        await XCTAssertThrowsProjectPackageError(.packageIsSymbolicLink) {
            try await store.read(from: link)
        }
        await XCTAssertThrowsProjectPackageError(.unsafeDestination) {
            try await store.write(package(pageName: "Replacement"), to: link)
        }
        let preserved = try await store.read(from: real)
        XCTAssertEqual(preserved.document.pages[0].name, "Home")
    }

    // SF-0301-004, SF-1702-004
    func testMalformedMetadataAndIntegrityMismatchAreRejected() async throws {
        let store = ProjectPackageStore()
        let encoded = try await store.encode(package())
        let members = try decodeArchive(encoded)
        let malformed = try editingManifest(in: members) { $0["createdAt"] = "not-a-date" }
        await XCTAssertThrowsProjectPackageError(.malformedMetadata) {
            try await store.decode(encodeArchive(malformed))
        }

        let corrupt = replacing("document.json", with: Data("tampered".utf8), in: members)
        await XCTAssertThrowsProjectPackageError(.memberIntegrityFailure) {
            try await store.decode(encodeArchive(corrupt))
        }
    }

    // SF-0301-004
    func testRejectedReadDoesNotMutateCurrentInMemoryDocument() async throws {
        let store = ProjectPackageStore()
        let committed = package(pageName: "Still Committed").document
        var currentDocument = committed

        do {
            let candidate = try await store.decode(Data("invalid".utf8))
            currentDocument = candidate.document
        } catch {
            XCTAssertEqual(error as? ProjectPackageError, .malformedContainer)
        }

        XCTAssertEqual(currentDocument, committed)
    }

    // SF-0301-008, SF-1702-008
    func testDiagnosticsRedactContentRawIdentityAndAbsolutePaths() async throws {
        let diagnostics = ProjectPackageDiagnostics()
        let store = ProjectPackageStore(diagnostics: diagnostics)
        let directory = try fixtureDirectory()
        let secretPath = directory.appendingPathComponent("Secret Customer Name.siteforge")
        try await store.write(package(pageName: "Confidential Campaign"), to: secretPath)
        _ = try await store.read(from: secretPath)

        let records = await diagnostics.records
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.result == .success })
        XCTAssertTrue(records.allSatisfy { $0.requirementID.hasPrefix("SF-0301-") })
        let description = String(describing: records)
        XCTAssertFalse(description.contains("Confidential Campaign"))
        XCTAssertFalse(description.contains("Secret Customer Name"))
        XCTAssertFalse(description.contains(directory.path))
        XCTAssertFalse(description.lowercased().contains(projectID.description))
        XCTAssertTrue(records.allSatisfy { $0.sanitizedProjectID?.hasPrefix("project-") == true })
    }

    // SF-0301-008, SF-1702-008
    func testFoundationPersistenceRequirementTraceabilityIsExact() {
        XCTAssertEqual(
            ProjectPackageStore.requirementIDs,
            [
                "SF-0301-001", "SF-0301-003", "SF-0301-004", "SF-0301-005", "SF-0301-008",
                "SF-0306-003", "SF-0306-004",
                "SF-1504-003", "SF-1504-004",
                "SF-1603-004", "SF-1604-004",
                "SF-1702-001", "SF-1702-004", "SF-1702-008",
            ]
        )
    }

    private func legacyGolden(named name: String, sha256 expectedHash: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Legacy/\(name).siteforge.b64")
        let encoded = try Data(contentsOf: url)
        let package = try XCTUnwrap(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
        let actualHash = SHA256.hash(data: package).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, expectedHash, "The immutable compatibility fixture changed")
        return package
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

final class DeterministicCancellationBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let blocked = DispatchSemaphore(value: 0)
    private let continuation = DispatchSemaphore(value: 0)
    private let blockAt: Int
    private var count = 0

    init(blockAt: Int) { self.blockAt = blockAt }

    func check() throws {
        let shouldBlock = lock.withLock { () -> Bool in
            count += 1
            return count == blockAt
        }
        if shouldBlock {
            blocked.signal()
            continuation.wait()
        }
        try Task.checkCancellation()
    }

    func waitUntilBlocked() async {
        await Task.detached { self.waitUntilBlockedSynchronously() }.value
    }

    func release() { continuation.signal() }

    private func waitUntilBlockedSynchronously() { blocked.wait() }
}

private struct ArchiveMember {
    let path: String
    let data: Data
}

private func encodeArchive(_ members: [ArchiveMember]) -> Data {
    var data = Data("SFPKG001".utf8)
    append(UInt32(members.count), to: &data)
    for member in members {
        let path = Data(member.path.utf8)
        append(UInt16(path.count), to: &data)
        append(UInt64(member.data.count), to: &data)
        data.append(path)
        data.append(member.data)
    }
    return data
}

private func decodeArchive(_ data: Data) throws -> [ArchiveMember] {
    var offset = 8
    func read(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw ProjectPackageError.malformedContainer }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
    func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        try read(MemoryLayout<T>.size).reduce(T.zero) { ($0 << 8) | T($1) }
    }
    let count = Int(try integer(UInt32.self))
    return try (0..<count).map { _ in
        let pathLength = Int(try integer(UInt16.self))
        let dataLength = Int(try integer(UInt64.self))
        let path = try XCTUnwrap(String(data: read(pathLength), encoding: .utf8))
        return ArchiveMember(path: path, data: try read(dataLength))
    }
}

private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    for shift in stride(from: (MemoryLayout<T>.size - 1) * 8, through: 0, by: -8) {
        data.append(UInt8(truncatingIfNeeded: value >> T(shift)))
    }
}

private func replacing(_ path: String, with data: Data, in members: [ArchiveMember]) -> [ArchiveMember] {
    members.map { $0.path == path ? ArchiveMember(path: path, data: data) : $0 }
}

private func editingManifest(
    in members: [ArchiveMember],
    edit: (inout [String: Any]) -> Void
) throws -> [ArchiveMember] {
    let member = try XCTUnwrap(members.first(where: { $0.path == "manifest.json" }))
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: member.data) as? [String: Any])
    edit(&json)
    let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    return replacing("manifest.json", with: data, in: members)
}

private func replacingDocumentAndIntegrity(
    in members: [ArchiveMember],
    with document: Data
) throws -> [ArchiveMember] {
    var updated = replacing("document.json", with: document, in: members)
    updated = try editingManifest(in: updated) { manifest in
        var descriptors = manifest["members"] as! [[String: Any]]
        let index = descriptors.firstIndex { $0["path"] as? String == "document.json" }!
        descriptors[index]["byteCount"] = document.count
        descriptors[index]["sha256"] = SHA256.hash(data: document)
            .map { String(format: "%02x", $0) }
            .joined()
        manifest["members"] = descriptors
    }
    return updated
}

private func XCTAssertThrowsProjectPackageError<T>(
    _ expected: ProjectPackageError,
    operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? ProjectPackageError, expected, file: file, line: line)
    }
}
