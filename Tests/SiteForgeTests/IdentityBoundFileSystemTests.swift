import CryptoKit
import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class IdentityBoundFileSystemTests: XCTestCase {
    nonisolated(unsafe) private var fixtureDirectory: URL!
    nonisolated(unsafe) private var fixtureLease: RepositoryTestFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureLease = try RepositoryTestFixture.create("identity")
        fixtureDirectory = fixtureLease.url
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixtureDirectory.path)
        try fixtureLease.cleanup()
        try super.tearDownWithError()
    }

    // SF-0301-005, SF-1504-003, SF-1702-004
    func testValidatedReadSnapshotRemainsBoundToOriginalSourceAcrossReplacementAndSymlinkSwap() async throws {
        let source = fixture("Source.siteforge")
        let detached = fixture("Detached.siteforge")
        let external = fixture("External.siteforge")
        let original = package(named: "Original", project: 1)
        let replacement = package(named: "Replacement", project: 2)
        let encoder = ProjectPackageStore()
        let originalBytes = try await encoder.encode(original)
        let replacementBytes = try await encoder.encode(replacement)
        try originalBytes.write(to: source)
        try replacementBytes.write(to: external)

        let barrier = PackageIOBarrier(.sourceSnapshotCaptured)
        let store = ProjectPackageStore(ioObserver: barrier)
        let readTask = Task { try await store.readSnapshot(from: source) }
        await barrier.waitUntilReached()
        try rename(source, detached)
        XCTAssertEqual(Darwin.symlink(external.path, source.path), 0)
        await barrier.release()

        let snapshot = try await readTask.value
        XCTAssertEqual(snapshot.package, original)
        XCTAssertEqual(snapshot.file.bytes, originalBytes)
        XCTAssertEqual(snapshot.file.fingerprint.digest, sha256(originalBytes))
        XCTAssertEqual(snapshot.file.fingerprint.byteCount, originalBytes.count)
        XCTAssertEqual(snapshot.file.fingerprint.identity, try identity(of: detached))
        XCTAssertEqual(try Data(contentsOf: external), replacementBytes)
    }

    // SF-0301-004, SF-0301-005, SF-1504-003, SF-1702-004
    func testConditionalCommitRejectsDestinationReplacementAndPreservesExternalBytes() async throws {
        let destination = fixture("Destination.siteforge")
        let external = fixture("ExternalReplacement.siteforge")
        let initial = package(named: "Initial", project: 3)
        let externalPackage = package(named: "External", project: 4)
        let replacement = package(named: "SiteForge Edit", project: 3)
        let plainStore = ProjectPackageStore()
        try await plainStore.write(initial, to: destination)
        try await plainStore.write(externalPackage, to: external)
        let expected = try await plainStore.readSnapshot(from: destination).file.fingerprint
        let externalBytes = try Data(contentsOf: external)

        let barrier = PackageIOBarrier(.destinationValidated)
        let store = ProjectPackageStore(ioObserver: barrier)
        let writeTask = Task { try await store.write(replacement, to: destination, expected: expected) }
        await barrier.waitUntilReached()
        try rename(external, destination)
        await barrier.release()

        await XCTAssertThrowsIdentityError(.fileIdentityChanged) { try await writeTask.value }
        XCTAssertEqual(try Data(contentsOf: destination), externalBytes)
    }

    // SF-0301-005, SF-1504-003, SF-1702-004
    func testDeleteAndRecreateWithIdenticalBytesIsRejectedByFileIdentity() async throws {
        let destination = fixture("Recreated.siteforge")
        let displaced = fixture("Displaced.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Stable Bytes", project: 5), to: destination)
        let snapshot = try await store.readSnapshot(from: destination)

        let barrier = PackageIOBarrier(.destinationValidated)
        let guardedStore = ProjectPackageStore(ioObserver: barrier)
        let writeTask = Task {
            try await guardedStore.write(
                self.package(named: "Rejected Edit", project: 5),
                to: destination,
                expected: snapshot.file.fingerprint
            )
        }
        await barrier.waitUntilReached()
        try rename(destination, displaced)
        try snapshot.file.bytes.write(to: destination)
        XCTAssertNotEqual(try identity(of: destination), snapshot.file.fingerprint.identity)
        await barrier.release()

        await XCTAssertThrowsIdentityError(.fileIdentityChanged) { try await writeTask.value }
        XCTAssertEqual(try Data(contentsOf: destination), snapshot.file.bytes)
    }

    // SF-0301-005, SF-1504-003, SF-1702-004
    func testDestinationAndAncestorSymlinkSwapsNeverTouchExternalTargets() async throws {
        let destination = fixture("SymlinkDestination.siteforge")
        let externalTarget = fixture("ExternalTarget.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Initial", project: 6), to: destination)
        try await store.write(package(named: "External", project: 7), to: externalTarget)
        let expected = try await store.readSnapshot(from: destination).file.fingerprint
        let externalBytes = try Data(contentsOf: externalTarget)

        let destinationBarrier = PackageIOBarrier(.destinationValidated)
        let guardedDestination = ProjectPackageStore(ioObserver: destinationBarrier)
        let destinationTask = Task {
            try await guardedDestination.write(
                self.package(named: "Edit", project: 6), to: destination, expected: expected
            )
        }
        await destinationBarrier.waitUntilReached()
        try FileManager.default.removeItem(at: destination)
        XCTAssertEqual(Darwin.symlink(externalTarget.path, destination.path), 0)
        await destinationBarrier.release()
        await XCTAssertThrowsIdentityError(.unsafeDestination) { try await destinationTask.value }
        XCTAssertEqual(try Data(contentsOf: externalTarget), externalBytes)

        let activeParent = fixture("active", isDirectory: true)
        let heldParent = fixture("held", isDirectory: true)
        let externalParent = fixture("external-parent", isDirectory: true)
        try FileManager.default.createDirectory(at: activeParent, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: false)
        let nestedDestination = activeParent.appendingPathComponent("Project.siteforge")
        let nestedExternal = externalParent.appendingPathComponent("Project.siteforge")
        try await store.write(package(named: "Nested Initial", project: 8), to: nestedDestination)
        try await store.write(package(named: "Nested External", project: 9), to: nestedExternal)
        let nestedSnapshot = try await store.readSnapshot(from: nestedDestination)
        let nestedExternalBytes = try Data(contentsOf: nestedExternal)

        let ancestorBarrier = PackageIOBarrier(.destinationValidated)
        let guardedAncestor = ProjectPackageStore(ioObserver: ancestorBarrier)
        let ancestorTask = Task {
            try await guardedAncestor.write(
                self.package(named: "Nested Edit", project: 8),
                to: nestedDestination,
                expected: nestedSnapshot.file.fingerprint
            )
        }
        await ancestorBarrier.waitUntilReached()
        try rename(activeParent, heldParent)
        XCTAssertEqual(Darwin.symlink(externalParent.path, activeParent.path), 0)
        await ancestorBarrier.release()
        await XCTAssertThrowsIdentityError(.unsafeDestination) { try await ancestorTask.value }
        XCTAssertEqual(try Data(contentsOf: nestedExternal), nestedExternalBytes)
        XCTAssertEqual(
            try Data(contentsOf: heldParent.appendingPathComponent("Project.siteforge")),
            nestedSnapshot.file.bytes
        )
    }

    // SF-0301-005, SF-1504-003, SF-1702-004
    func testConcurrentSameInodeModificationIsPreservedAndRejected() async throws {
        let destination = fixture("SameInode.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Initial", project: 10), to: destination)
        let snapshot = try await store.readSnapshot(from: destination)

        let barrier = PackageIOBarrier(.destinationValidated)
        let guardedStore = ProjectPackageStore(ioObserver: barrier)
        let task = Task {
            try await guardedStore.write(
                self.package(named: "SiteForge Edit", project: 10),
                to: destination,
                expected: snapshot.file.fingerprint
            )
        }
        await barrier.waitUntilReached()
        let descriptor = Darwin.open(destination.path, O_WRONLY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        var marker = UInt8(ascii: "X")
        XCTAssertEqual(Darwin.pwrite(descriptor, &marker, 1, 0), 1)
        XCTAssertEqual(Darwin.fsync(descriptor), 0)
        Darwin.close(descriptor)
        let externalBytes = try Data(contentsOf: destination)
        XCTAssertEqual(try identity(of: destination), snapshot.file.fingerprint.identity)
        await barrier.release()

        await XCTAssertThrowsIdentityError(.fileIdentityChanged) { try await task.value }
        XCTAssertEqual(try Data(contentsOf: destination), externalBytes)
    }

    // SF-0301-004, SF-0301-005, SF-1504-003, SF-1702-004
    func testPostSwapModificationRollsBackWithoutDeletingChangedExternalBytes() async throws {
        let destination = fixture("PostSwap.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Initial", project: 18), to: destination)
        let snapshot = try await store.readSnapshot(from: destination)
        let externalDescriptor = Darwin.open(destination.path, O_WRONLY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(externalDescriptor, 0)
        defer { Darwin.close(externalDescriptor) }

        let barrier = PackageIOBarrier(.afterAtomicSwap)
        let guardedStore = ProjectPackageStore(ioObserver: barrier)
        let task = Task {
            try await guardedStore.write(
                self.package(named: "SiteForge Replacement", project: 18),
                to: destination,
                expected: snapshot.file.fingerprint
            )
        }
        await barrier.waitUntilReached()
        var marker = UInt8(ascii: "R")
        XCTAssertEqual(Darwin.pwrite(externalDescriptor, &marker, 1, 0), 1)
        XCTAssertEqual(Darwin.fsync(externalDescriptor), 0)
        var changedBytes = snapshot.file.bytes
        changedBytes[changedBytes.startIndex] = marker
        await barrier.release()

        await XCTAssertThrowsIdentityError(.fileIdentityChanged) { try await task.value }
        XCTAssertEqual(try Data(contentsOf: destination), changedBytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path).contains {
            $0.hasPrefix(".siteforge-stage-")
        })
    }

    // SF-0301-004, SF-1504-004, SF-1603-004, SF-1604-004
    func testSparseOversizeAndLinkedFilePoliciesBoundWorkAndPreventUnsafeReplacement() async throws {
        let sparse = fixture("Sparse.siteforge")
        let descriptor = Darwin.open(sparse.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(Darwin.ftruncate(descriptor, off_t(ProjectPackageStore.maximumPackageBytes + 1)), 0)
        Darwin.close(descriptor)
        var sparseInfo = stat()
        XCTAssertEqual(Darwin.lstat(sparse.path, &sparseInfo), 0)
        XCTAssertLessThan(Int64(sparseInfo.st_blocks) * 512, sparseInfo.st_size)
        await XCTAssertThrowsIdentityError(.oversizedInput) {
            try await ProjectPackageStore().readSnapshot(from: sparse)
        }

        let destination = fixture("Linked.siteforge")
        let hardLink = fixture("LinkedCopy.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Linked", project: 11), to: destination)
        XCTAssertEqual(Darwin.link(destination.path, hardLink.path), 0)
        let linked = try await store.readSnapshot(from: destination)
        XCTAssertEqual(linked.file.metadata.linkCount, 2)
        let before = linked.file.bytes
        await XCTAssertThrowsIdentityError(.unsafeFileMetadata) {
            try await store.write(
                self.package(named: "Unsafe Edit", project: 11),
                to: destination,
                expected: linked.file.fingerprint
            )
        }
        XCTAssertEqual(try Data(contentsOf: destination), before)
        XCTAssertEqual(try Data(contentsOf: hardLink), before)

        let foreignOwner = PackageSecurityMetadata(
            owner: geteuid() &+ 1,
            group: getegid(),
            mode: 0o600,
            linkCount: 1,
            extendedACL: nil,
            approvedExtendedAttributes: [:]
        )
        XCTAssertThrowsError(try foreignOwner.validateForReplacement()) {
            XCTAssertEqual($0 as? ProjectPackageError, .unsafeFileMetadata)
        }
    }

    // SF-0301-004, SF-0306-004, SF-1603-004, SF-1604-004
    func testReplacementPreservesOwnerPermissionsACLAndApprovedXattrsOnly() async throws {
        let destination = fixture("Metadata.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Metadata Before", project: 12), to: destination)
        XCTAssertEqual(Darwin.chmod(destination.path, mode_t(0o640)), 0)
        try setXattr("app.siteforge.project-identity", value: Data("stable-project".utf8), at: destination)
        try setXattr("app.siteforge.unapproved", value: Data("must-not-copy".utf8), at: destination)
        try run("/bin/chmod", arguments: ["+a", "everyone allow read", destination.path])
        let before = try await store.readSnapshot(from: destination)
        XCTAssertNotNil(before.file.metadata.extendedACL)

        try await store.write(
            package(named: "Metadata After", project: 12),
            to: destination,
            expected: before.file.fingerprint
        )
        let after = try await store.readSnapshot(from: destination)
        XCTAssertEqual(after.file.metadata, before.file.metadata)
        XCTAssertEqual(
            after.file.metadata.approvedExtendedAttributes["app.siteforge.project-identity"],
            Data("stable-project".utf8)
        )
        XCTAssertEqual(xattrLength("app.siteforge.unapproved", at: destination), -1)
        XCTAssertEqual(errno, ENOATTR)
    }

    // SF-0306-003, SF-0306-004, SF-1504-004, SF-1702-004
    func testMismatchedAndMalformedRecoveryCollisionsAreNeverOverwritten() async throws {
        let recoveryDirectory = fixture("Recovery", isDirectory: true)
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let expectedProject = projectID(13)
        let collisionProject = projectID(14)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: expectedProject, in: recoveryDirectory)
        let collision = package(named: "Unrelated Recovery", project: 14)
        try await store.write(collision, to: recoveryURL, policy: .recovery(collisionProject))
        let collisionBytes = try Data(contentsOf: recoveryURL)

        let backend = DocumentLifecycleBackend(store: store)
        let history = DocumentSession().historySnapshot()
        let expectedRecovery = package(named: "Expected Recovery", project: 13)
        do {
            _ = try await backend.write(
                expectedRecovery,
                history: history,
                recoveryBoundary: 0,
                to: recoveryURL,
                expected: nil,
                identity: operationIdentity(for: expectedRecovery, at: recoveryURL, intent: .autosave)
            )
            XCTFail("Expected recovery ownership conflict")
        } catch {
            XCTAssertEqual(error as? DocumentLifecycleFailure, .recoveryArtifactConflict)
        }
        XCTAssertEqual(try Data(contentsOf: recoveryURL), collisionBytes)

        try FileManager.default.removeItem(at: recoveryURL)
        let malformed = Data("malformed-recovery".utf8)
        try malformed.write(to: recoveryURL)
        XCTAssertEqual(Darwin.chmod(recoveryURL.path, mode_t(0o600)), 0)
        do {
            _ = try await backend.write(
                expectedRecovery,
                history: history,
                recoveryBoundary: 0,
                to: recoveryURL,
                expected: nil,
                identity: operationIdentity(for: expectedRecovery, at: recoveryURL, intent: .autosave)
            )
            XCTFail("Expected malformed recovery rejection")
        } catch {
            XCTAssertEqual(error as? DocumentLifecycleFailure, .malformedPackage)
        }
        XCTAssertEqual(try Data(contentsOf: recoveryURL), malformed)
    }

    // SF-0306-003, SF-0306-004, SF-1504-004, SF-1603-004
    func testRecoveryDeletionFailureRetainsCandidateAndRetryDeletesOwnedArtifact() async throws {
        let recoveryDirectory = fixture("OwnedRecovery", isDirectory: true)
        let durableURL = fixture("Durable.siteforge")
        let identifier = projectID(15)
        let durable = package(named: "Durable", project: 15, revision: 0)
        let recovered = package(named: "Recovered", project: 15, revision: 1)
        let writer = ProjectPackageStore()
        try await writer.prepareRecoveryDirectory(recoveryDirectory)
        try await writer.write(durable, to: durableURL)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: identifier, in: recoveryDirectory)
        try await writer.write(recovered, to: recoveryURL, policy: .recovery(identifier))
        let recoveryBytes = try Data(contentsOf: recoveryURL)

        let barrier = PackageIOBarrier(.recoveryValidatedForDeletion)
        let guardedStore = ProjectPackageStore(ioObserver: barrier)
        let backend = DocumentLifecycleBackend(store: guardedStore)
        let controller = DocumentLifecycleController(
            session: DocumentSession(),
            backend: backend,
            recoveryDirectory: recoveryDirectory
        )
        let openResult = await controller.requestOpen(durableURL)
        XCTAssertEqual(openResult, .completed)
        XCTAssertNotNil(controller.recoveryCandidate)

        let discard = Task { await controller.discardRecovery() }
        await barrier.waitUntilReached()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: recoveryDirectory.path)
        await barrier.release()
        await discard.value
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: recoveryDirectory.path)

        XCTAssertNotNil(controller.recoveryCandidate)
        XCTAssertEqual(controller.failure, .recoveryDeletionFailed)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), recoveryBytes)

        await controller.discardRecovery()
        XCTAssertNil(controller.recoveryCandidate)
        XCTAssertNil(controller.failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))
    }

    // SF-0301-005, SF-1504-003, SF-1702-004
    func testLifecycleConflictAtCommitPreservesCanonicalStateAndExternalBytesExactly() async throws {
        let durableURL = fixture("Lifecycle.siteforge")
        let externalURL = fixture("LifecycleExternal.siteforge")
        let initial = package(named: "Lifecycle Initial", project: 16)
        let external = package(named: "External Winner", project: 17)
        let writer = ProjectPackageStore()
        try await writer.write(initial, to: durableURL)
        try await writer.write(external, to: externalURL)
        let externalBytes = try Data(contentsOf: externalURL)

        let barrier = PackageIOBarrier(.destinationValidated)
        let backend = DocumentLifecycleBackend(store: ProjectPackageStore(ioObserver: barrier))
        let controller = DocumentLifecycleController(
            session: DocumentSession(),
            backend: backend,
            recoveryDirectory: fixture("LifecycleRecovery", isDirectory: true)
        )
        let openResult = await controller.requestOpen(durableURL)
        XCTAssertEqual(openResult, .completed)
        let pageID = controller.session.document.pages[0].id
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Local Edit")))
        let before = controller.stateSnapshot

        let save = Task { await controller.save() }
        await barrier.waitUntilReached()
        try rename(externalURL, durableURL)
        await barrier.release()
        let saved = await save.value
        XCTAssertFalse(saved)

        XCTAssertEqual(controller.session.document, before.document)
        XCTAssertEqual(controller.session.historySnapshot(), before.history)
        XCTAssertEqual(controller.currentProjectID, before.projectID)
        XCTAssertEqual(controller.fileURL, before.fileURL)
        XCTAssertEqual(controller.stateSnapshot.durableFingerprint, before.durableFingerprint)
        XCTAssertEqual(controller.failure, .externalModification)
        XCTAssertEqual(try Data(contentsOf: durableURL), externalBytes)
    }

    private func fixture(_ name: String, isDirectory: Bool = false) -> URL {
        fixtureDirectory.appendingPathComponent(name, isDirectory: isDirectory)
    }

    private func package(named name: String, project: UInt8, revision: UInt64 = 7) -> ProjectPackage {
        ProjectPackage(
            projectID: projectID(project),
            createdAt: ProjectTimestamp("2026-07-19T12:00:00.000Z"),
            modifiedAt: ProjectTimestamp("2026-07-19T12:30:00.000Z"),
            document: CanonicalDocument(
                id: DocumentID(uuid(project, domain: 2)),
                revision: revision,
                pages: [DocumentPage(
                    id: PageID(uuid(project, domain: 3)),
                    name: name,
                    route: PageRoute(rawValue: "/project-\(project)")
                )]
            )
        )
    }

    private func projectID(_ value: UInt8) -> ProjectID {
        ProjectID(uuid(value, domain: 1))
    }

    private func uuid(_ value: UInt8, domain: UInt8) -> UUID {
        UUID(uuid: (domain, value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    private func rename(_ source: URL, _ destination: URL) throws {
        guard Darwin.rename(source.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func identity(of url: URL) throws -> PackageFileIdentity {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return PackageFileIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func operationIdentity(
        for package: ProjectPackage,
        at url: URL,
        intent: LifecycleOperationIntent
    ) -> LifecycleOperationIdentity {
        LifecycleOperationIdentity(
            id: LifecycleOperationID(),
            epoch: LifecycleEpoch(),
            documentID: package.document.id,
            projectID: package.projectID,
            revision: package.document.revision,
            destination: .file(url, kind: intent == .autosave ? .recovery : .durable),
            intent: intent
        )
    }

    private func setXattr(_ name: String, value: Data, at url: URL) throws {
        let result = value.withUnsafeBytes { bytes in
            url.path.withCString { path in
                name.withCString { attribute in
                    Darwin.setxattr(path, attribute, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func xattrLength(_ name: String, at url: URL) -> Int {
        url.path.withCString { path in
            name.withCString { Darwin.getxattr(path, $0, nil, 0, 0, 0) }
        }
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw POSIXError(.EPERM)
        }
    }
}

private actor PackageIOBarrier: ProjectPackageIOObserving {
    private let checkpoint: ProjectPackageIOCheckpoint
    private var hasReached = false
    private var hasBlocked = false
    private var reachWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(_ checkpoint: ProjectPackageIOCheckpoint) {
        self.checkpoint = checkpoint
    }

    func reached(_ checkpoint: ProjectPackageIOCheckpoint) async {
        guard checkpoint == self.checkpoint, !hasBlocked else { return }
        hasBlocked = true
        hasReached = true
        let waiters = reachWaiters
        reachWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilReached() async {
        if hasReached { return }
        await withCheckedContinuation { reachWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private func XCTAssertThrowsIdentityError<T>(
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
