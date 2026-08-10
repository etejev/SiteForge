import CryptoKit
import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class IdentityBoundFileSystemTests: XCTestCase {
    nonisolated(unsafe) private var fixtureDirectory: URL!
    nonisolated(unsafe) private var fixtureLease: ApplicationOwnedTestFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureLease = try ApplicationOwnedTestFixture.create("identity")
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
    func testPostSwapModificationRetainsExternalBytesWithoutReversingCommittedDestination() async throws {
        let destination = fixture("PostSwap.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Initial", project: 18), to: destination)
        let snapshot = try await store.readSnapshot(from: destination)
        let replacement = package(named: "SiteForge Replacement", project: 18)
        let replacementBytes = try await store.encode(replacement)
        let externalDescriptor = Darwin.open(destination.path, O_WRONLY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(externalDescriptor, 0)
        defer { Darwin.close(externalDescriptor) }

        let barrier = PackageIOBarrier(.afterAtomicSwap)
        let guardedStore = ProjectPackageStore(ioObserver: barrier)
        let task = Task {
            try await guardedStore.write(
                replacement,
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

        _ = try await task.value
        XCTAssertEqual(try Data(contentsOf: destination), replacementBytes)
        // macOS has no identity-conditional unlink. Retaining the displaced
        // external artifact is safer than reopening and potentially deleting
        // an unrelated same-UID file substituted at this name.
        let stagingNames = try FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)
            .filter { $0.hasPrefix(".siteforge-stage-") }
        XCTAssertEqual(stagingNames.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixtureDirectory.appendingPathComponent(try XCTUnwrap(stagingNames.first))), changedBytes)
    }

    // SF-0301-004, SF-0301-005, SF-1504-003, SF-1702-004 — a replacement
    // after atomic exchange is not rolled over or removed by SiteForge.
    func testPostSwapDestinationReplacementPreservesExternalBytesExactly() async throws {
        let destination = fixture("PostSwapExternal.siteforge")
        let external = fixture("ExternalAfterSwap.siteforge")
        let store = ProjectPackageStore()
        try await store.write(package(named: "Initial", project: 19), to: destination)
        try await store.write(package(named: "External", project: 20), to: external)
        let expected = try await store.readSnapshot(from: destination).file.fingerprint
        let externalBytes = try Data(contentsOf: external)

        let barrier = PackageIOBarrier(.afterAtomicSwap)
        let guarded = ProjectPackageStore(ioObserver: barrier)
        let task = Task {
            try await guarded.write(
                self.package(named: "SiteForge Replacement", project: 19),
                to: destination,
                expected: expected
            )
        }
        await barrier.waitUntilReached()
        try rename(external, destination)
        await barrier.release()

        await XCTAssertThrowsIdentityError(.fileIdentityChanged) { try await task.value }
        XCTAssertEqual(try Data(contentsOf: destination), externalBytes)
    }

    // SF-0301-004, SF-0301-005, SF-1504-003, SF-1702-004 — a staging name is
    // revalidated immediately before its conditional exchange, so a controlled
    // replacement at the pre-commit seam cannot become the public package.
    func testPreCommitStagingReplacementIsRejectedWithoutInstallingExternalBytes() async throws {
        let destination = fixture("PreCommitStage.siteforge")
        let external = fixture("PreCommitExternal.siteforge")
        let displaced = fixture("PreCommitDisplaced.siteforge")
        let store = ProjectPackageStore()
        let initial = package(named: "Initial", project: 30)
        let replacement = package(named: "Replacement", project: 30)
        let externalPackage = package(named: "External", project: 31)
        try await store.write(initial, to: destination)
        try await store.write(externalPackage, to: external)
        let expected = try await store.readSnapshot(from: destination).file
        let initialBytes = expected.bytes
        let externalBytes = try Data(contentsOf: external)

        let barrier = PackageIOBarrier(.beforeConditionalCommit)
        let guarded = ProjectPackageStore(ioObserver: barrier)
        let task = Task {
            try await guarded.write(replacement, to: destination, expected: expected.fingerprint)
        }
        await barrier.waitUntilReached()
        let staging = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)
                .first { $0.hasPrefix(".siteforge-stage-") }
        )
        let stagingURL = fixtureDirectory.appendingPathComponent(staging)
        try rename(stagingURL, displaced)
        try rename(external, stagingURL)
        await barrier.release()

        await XCTAssertThrowsIdentityError(.fileIdentityChanged) { try await task.value }
        XCTAssertEqual(try Data(contentsOf: destination), initialBytes)
        XCTAssertEqual(try Data(contentsOf: stagingURL), externalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: displaced.path))
    }

    // SF-0301-004, SF-0301-005, SF-1504-003, SF-1702-004 — a substituted
    // displaced staging name is never used to roll back into the public path.
    func testPostSwapStagingReplacementCannotInstallExternalBytesAtDestination() async throws {
        let destination = fixture("PostSwapStage.siteforge")
        let external = fixture("ExternalStage.siteforge")
        let displaced = fixture("DisplacedStage.siteforge")
        let store = ProjectPackageStore()
        let replacement = package(named: "SiteForge Replacement", project: 21)
        let replacementBytes = try await store.encode(replacement)
        try await store.write(package(named: "Initial", project: 21), to: destination)
        try await store.write(package(named: "External staging", project: 22), to: external)
        let expected = try await store.readSnapshot(from: destination).file.fingerprint
        let externalBytes = try Data(contentsOf: external)

        let barrier = PackageIOBarrier(.afterAtomicSwap)
        let guarded = ProjectPackageStore(ioObserver: barrier)
        let task = Task {
            try await guarded.write(replacement, to: destination, expected: expected)
        }
        await barrier.waitUntilReached()
        let staging = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)
                .first { $0.hasPrefix(".siteforge-stage-") }
        )
        try rename(fixtureDirectory.appendingPathComponent(staging), displaced)
        try rename(external, fixtureDirectory.appendingPathComponent(staging))
        await barrier.release()

        _ = try await task.value
        XCTAssertEqual(try Data(contentsOf: destination), replacementBytes)
        XCTAssertEqual(try Data(contentsOf: fixtureDirectory.appendingPathComponent(staging)), externalBytes)
        XCTAssertNotEqual(try Data(contentsOf: destination), externalBytes)
    }

    // SF-0301-004, SF-1504-003 — no-follow reads reject special files without
    // blocking a worker on a FIFO writer.
    func testSpecialFileIsRejectedWithoutAPathRead() async throws {
        let fifo = fixture("Package.pipe")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, mode_t(0o600)), 0)
        await XCTAssertThrowsIdentityError(.packageIsSymbolicLink) {
            try await ProjectPackageStore().readSnapshot(from: fifo)
        }
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

    // SF-0306-003, SF-0306-004, SF-1504-004, SF-1603-004 — a foreign empty
    // owner-restricted file must not be mistaken for the versioned,
    // project-bound logical-retirement marker.
    func testEmptySecureRecoveryCollisionIsNeverTreatedAsOwnedTombstone() async throws {
        let recoveryDirectory = fixture("EmptyCollisionRecovery", isDirectory: true)
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let owner = projectID(61)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: owner, in: recoveryDirectory)
        let externalBytes = Data()
        try externalBytes.write(to: recoveryURL)
        XCTAssertEqual(Darwin.chmod(recoveryURL.path, mode_t(0o600)), 0)

        let replacement = package(named: "Expected Recovery", project: 61)
        do {
            _ = try await DocumentLifecycleBackend(store: store).write(
                replacement,
                history: DocumentSession().historySnapshot(),
                recoveryBoundary: 0,
                to: recoveryURL,
                expected: nil,
                identity: operationIdentity(for: replacement, at: recoveryURL, intent: .autosave)
            )
            XCTFail("Expected empty collision rejection")
        } catch {
            XCTAssertEqual(error as? DocumentLifecycleFailure, .malformedPackage)
        }
        XCTAssertEqual(try Data(contentsOf: recoveryURL), externalBytes)
        let isRetired = try await store.isRetiredRecoveryTombstone(
            at: recoveryURL,
            projectID: owner
        )
        XCTAssertFalse(isRetired)
    }

    // SF-0301-005, SF-0306-003, SF-0306-004, SF-1504-004 — a tombstone is
    // project-bound proof, not a generic file-shape marker. Moving a valid
    // marker to another project's public recovery name must not hide that
    // name during untitled discovery or authorize any mutation.
    func testForeignProjectTombstoneCannotHideAnotherRecoveryName() async throws {
        let recoveryDirectory = fixture("ForeignTombstoneRecovery", isDirectory: true)
        let owner = projectID(62)
        let foreign = projectID(63)
        let ownerURL = DocumentLifecycleBackend.recoveryURL(for: owner, in: recoveryDirectory)
        let foreignURL = DocumentLifecycleBackend.recoveryURL(for: foreign, in: recoveryDirectory)
        let foreignPackage = package(named: "Foreign Recovery", project: 63, revision: 1)
        let store = ProjectPackageStore()

        try await store.prepareRecoveryDirectory(recoveryDirectory)
        try await store.write(foreignPackage, to: foreignURL, policy: .recovery(foreign))
        let snapshot = try await store.readOwnedRecoverySnapshot(
            from: foreignURL,
            expectedProjectID: foreign
        )
        try await store.removeOwnedRecovery(
            at: foreignURL,
            projectID: foreign,
            expected: snapshot.file.fingerprint
        )
        let foreignTombstoneBytes = try Data(contentsOf: foreignURL)
        try rename(foreignURL, ownerURL)

        let ownerRecognizesTombstone = try await store.isRetiredRecoveryTombstone(
            at: ownerURL,
            projectID: owner
        )
        let foreignRecognizesTombstone = try await store.isRetiredRecoveryTombstone(
            at: ownerURL,
            projectID: foreign
        )
        XCTAssertFalse(ownerRecognizesTombstone)
        XCTAssertTrue(foreignRecognizesTombstone)

        let backend = DocumentLifecycleBackend(store: store)
        let artifacts = try await backend.recoveryURLs(
            in: recoveryDirectory,
            identity: operationIdentity(for: foreignPackage, at: ownerURL, intent: .discoverRecovery)
        )
        XCTAssertEqual(
            artifacts,
            [.init(url: ownerURL, expectedProjectID: owner)]
        )
        XCTAssertEqual(try Data(contentsOf: ownerURL), foreignTombstoneBytes)
    }

    // SF-0306-003, SF-0306-004, SF-1504-004 — a caller-supplied project ID
    // is not sufficient authority to retire an otherwise valid recovery
    // package. The project identity must be parsed from the exact
    // descriptor-bound snapshot that matched the expected fingerprint.
    func testRecoveryRetirementRejectsMismatchedPackageProjectOwnership() async throws {
        let recoveryDirectory = fixture("MismatchedRecoveryOwnership", isDirectory: true)
        let requestedOwner = projectID(64)
        let actualOwner = projectID(65)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: actualOwner, in: recoveryDirectory)
        let package = package(named: "Actual owner recovery", project: 65, revision: 2)
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        try await store.write(package, to: recoveryURL, policy: .recovery(actualOwner))
        let snapshot = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL,
            expectedProjectID: actualOwner
        )
        let originalBytes = try Data(contentsOf: recoveryURL)

        do {
            try await store.removeOwnedRecovery(
                at: recoveryURL,
                projectID: requestedOwner,
                expected: snapshot.file.fingerprint
            )
            XCTFail("Mismatched recovery ownership must not retire the artifact")
        } catch {
            XCTAssertEqual(error as? ProjectPackageError, .unsafeRecoveryArtifact)
        }

        XCTAssertEqual(try Data(contentsOf: recoveryURL), originalBytes)
        let preserved = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL,
            expectedProjectID: actualOwner
        )
        XCTAssertEqual(preserved.package, package)
        let incorrectlyRetired = try await store.isRetiredRecoveryTombstone(
            at: recoveryURL,
            projectID: requestedOwner
        )
        XCTAssertFalse(incorrectlyRetired)
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
        // macOS does not provide an identity-conditional unlink. Successful
        // retirement leaves an exact versioned, project-bound marker that discovery ignores,
        // rather than risking deletion of a same-UID replacement.
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        let retired = try await writer.isRetiredRecoveryTombstone(
            at: recoveryURL,
            projectID: identifier
        )
        XCTAssertTrue(retired)
    }

    // SF-0306-003, SF-0306-004, SF-1504-004 — a durable write is not reported
    // as a fully successful Save when the separately owned recovery artifact
    // cannot be retired. The committed durable bytes stay valid, while the
    // external replacement remains untouched and is never adopted as a
    // recovery candidate.
    func testSaveReportsRecoveryRetirementConflictWithoutDeletingExternalArtifact() async throws {
        let recoveryDirectory = fixture("SaveRetirementRecovery", isDirectory: true)
        let durableURL = fixture("SaveRetirementDurable.siteforge")
        let externalURL = fixture("SaveRetirementExternal.siteforge")
        let displacedURL = fixture("SaveRetirementDisplaced.siteforge")
        let identifier = projectID(51)
        let durable = package(named: "Durable", project: 51, revision: 0)
        let recovery = package(named: "Owned recovery", project: 51, revision: 1)
        let external = package(named: "External recovery", project: 52, revision: 3)
        let writer = ProjectPackageStore()
        try await writer.prepareRecoveryDirectory(recoveryDirectory)
        try await writer.write(durable, to: durableURL)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: identifier, in: recoveryDirectory)
        try await writer.write(recovery, to: recoveryURL, policy: .recovery(identifier))
        // The replacement is an unrelated normal package, deliberately not an
        // app-owned recovery artifact. Moving it into the recovery name must
        // make retirement reject rather than bless or remove it.
        try await writer.write(external, to: externalURL)
        let externalBytes = try Data(contentsOf: externalURL)

        let barrier = PackageIOBarrier(.recoveryValidatedForDeletion)
        let controller = DocumentLifecycleController(
            session: DocumentSession(),
            backend: DocumentLifecycleBackend(store: ProjectPackageStore(ioObserver: barrier)),
            recoveryDirectory: recoveryDirectory
        )
        let openResult = await controller.requestOpen(durableURL)
        XCTAssertEqual(openResult, .completed)
        let recoveryCandidate = try XCTUnwrap(controller.recoveryCandidate)
        let pageID = controller.session.document.pages[0].id
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Committed durable edit")))

        let save = Task { await controller.save() }
        await barrier.waitUntilReached()
        try rename(recoveryURL, displacedURL)
        try rename(externalURL, recoveryURL)
        await barrier.release()

        let saved = await save.value
        XCTAssertFalse(saved)
        XCTAssertEqual(controller.failure, .recoveryArtifactConflict)
        // A rejected identity-bound retirement keeps the exact candidate for
        // explicit retry or inspection. It must never adopt the external
        // replacement now occupying the public recovery name.
        XCTAssertEqual(controller.recoveryCandidate, recoveryCandidate)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), externalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: displacedURL.path))
        let persisted = try await ProjectPackageStore().read(from: durableURL)
        XCTAssertEqual(persisted.document.pages[0].name, "Committed durable edit")
    }

    // SF-0306-003, SF-0306-004, SF-1504-004 — recovery presentation is not
    // authority to adopt. A replacement after discovery remains on disk and
    // refreshes the retryable candidate without changing the durable document.
    func testRestoreRejectsARecoveryArtifactReplacedAfterDiscovery() async throws {
        let recoveryDirectory = fixture("RestoreReplacementRecovery", isDirectory: true)
        let durableURL = fixture("RestoreReplacementDurable.siteforge")
        let displacedURL = fixture("RestoreReplacementDisplaced.siteforge")
        let writer = ProjectPackageStore()
        let identifier = projectID(47)
        let durable = package(named: "Durable", project: 47, revision: 0)
        let firstRecovery = package(named: "First recovery", project: 47, revision: 1)
        let replacementRecovery = package(named: "Replacement recovery", project: 47, revision: 2)
        try await writer.prepareRecoveryDirectory(recoveryDirectory)
        try await writer.write(durable, to: durableURL)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: identifier, in: recoveryDirectory)
        try await writer.write(firstRecovery, to: recoveryURL, policy: .recovery(identifier))
        let externalURL = recoveryDirectory.appendingPathComponent("external-recovery.siteforge")
        try await writer.write(replacementRecovery, to: externalURL, policy: .recovery(identifier))
        let externalBytes = try Data(contentsOf: externalURL)
        let replacementFingerprint = try await writer.readOwnedRecoverySnapshot(
            from: externalURL,
            expectedProjectID: identifier
        ).file.fingerprint

        // Arm the seam only after durable open and recovery discovery have
        // completed. This binds the interleave to Restore itself without
        // coupling the test to unrelated internal reads.
        let barrier = ArmedPackageIOBarrier(.beforeRead)
        let controller = DocumentLifecycleController(
            session: DocumentSession(),
            backend: DocumentLifecycleBackend(store: ProjectPackageStore(ioObserver: barrier)),
            recoveryDirectory: recoveryDirectory
        )
        let openResult = await controller.requestOpen(durableURL)
        XCTAssertEqual(openResult, .completed)
        let before = controller.stateSnapshot
        XCTAssertEqual(before.recoveryCandidate?.package.document.revision, 1)

        await barrier.arm()
        let restore = Task { await controller.requestRestoreRecovery() }
        await barrier.waitUntilReached()
        try rename(recoveryURL, displacedURL)
        try rename(externalURL, recoveryURL)
        await barrier.release()

        let restoreResult = await restore.value
        XCTAssertEqual(restoreResult, DocumentTransitionResult.failed(.recoveryArtifactConflict))
        XCTAssertEqual(controller.session.document, before.document)
        XCTAssertEqual(controller.session.historySnapshot(), before.history)
        XCTAssertEqual(controller.currentProjectID, before.projectID)
        XCTAssertEqual(controller.fileURL, before.fileURL)
        XCTAssertEqual(controller.stateSnapshot.durableFingerprint, before.durableFingerprint)
        XCTAssertEqual(controller.failure, DocumentLifecycleFailure.recoveryArtifactConflict)
        XCTAssertEqual(controller.recoveryCandidate?.fingerprint, replacementFingerprint)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), externalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: displacedURL.path))
    }

    // SF-0306-003, SF-0306-004, SF-1504-004, SF-1702-004 — an external
    // replacement after validation must remain at the public recovery name.
    func testRecoveryDeletionFinalNameSwapPreservesExternalArtifactExactly() async throws {
        let recoveryDirectory = fixture("FinalRecovery", isDirectory: true)
        let recoveryURL = recoveryDirectory.appendingPathComponent("candidate.siteforge")
        let displaced = fixture("DisplacedRecovery.siteforge")
        let external = fixture("ExternalRecovery.siteforge")
        let owner = projectID(44)
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        try await store.write(package(named: "Owned Recovery", project: 44), to: recoveryURL, policy: .recovery(owner))
        let expected = try await store.readOwnedRecoverySnapshot(from: recoveryURL, expectedProjectID: owner).file.fingerprint
        let originalBytes = try Data(contentsOf: recoveryURL)
        try await store.write(package(named: "External Replacement", project: 45), to: external)
        let externalBytes = try Data(contentsOf: external)

        let barrier = PackageIOBarrier(.recoveryDeletionReadyToCommit)
        let guarded = ProjectPackageStore(ioObserver: barrier)
        let deletion = Task {
            try await guarded.removeOwnedRecovery(at: recoveryURL, projectID: owner, expected: expected)
        }
        await barrier.waitUntilReached()
        try rename(recoveryURL, displaced)
        try rename(external, recoveryURL)
        await barrier.release()

        await XCTAssertThrowsIdentityError(.unsafeRecoveryArtifact) { try await deletion.value }
        XCTAssertEqual(try Data(contentsOf: recoveryURL), externalBytes)
        XCTAssertEqual(try Data(contentsOf: displaced), originalBytes)
    }

    // SF-0306-003, SF-0306-004, SF-1603-004 — mode bits alone do not make
    // recovery artifacts owner-confidential when an extended ACL grants read.
    func testRecoveryDirectoryAndArtifactRejectExtendedACLs() async throws {
        let recoveryDirectory = fixture("RecoveryACL", isDirectory: true)
        let recoveryURL = recoveryDirectory.appendingPathComponent("candidate.siteforge")
        let owner = projectID(46)
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        try run("/bin/chmod", arguments: ["+a", "everyone allow search", recoveryDirectory.path])
        do {
            try await store.validateRecoveryDirectory(recoveryDirectory)
            XCTFail("Expected unsafe recovery directory rejection")
        } catch {
            XCTAssertEqual(error as? ProjectPackageError, .unsafeRecoveryArtifact)
        }
        try run("/bin/chmod", arguments: ["-a", "everyone allow search", recoveryDirectory.path])

        try await store.write(package(named: "Owned Recovery", project: 46), to: recoveryURL, policy: .recovery(owner))
        try run("/bin/chmod", arguments: ["+a", "everyone allow read", recoveryURL.path])
        await XCTAssertThrowsIdentityError(.unsafeRecoveryArtifact) {
            try await store.readOwnedRecoverySnapshot(from: recoveryURL, expectedProjectID: owner)
        }
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
    private var released = false
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
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func waitUntilReached() async {
        if hasReached { return }
        await withCheckedContinuation { reachWaiters.append($0) }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ArmedPackageIOBarrier: ProjectPackageIOObserving {
    private let checkpoint: ProjectPackageIOCheckpoint
    private var armed = false
    private var hasReached = false
    private var released = false
    private var reachWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(_ checkpoint: ProjectPackageIOCheckpoint) {
        self.checkpoint = checkpoint
    }

    func arm() {
        armed = true
    }

    func reached(_ checkpoint: ProjectPackageIOCheckpoint) async {
        guard checkpoint == self.checkpoint, armed, !hasReached else { return }
        hasReached = true
        let waiters = reachWaiters
        reachWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func waitUntilReached() async {
        if hasReached { return }
        await withCheckedContinuation { reachWaiters.append($0) }
    }

    func release() {
        released = true
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
