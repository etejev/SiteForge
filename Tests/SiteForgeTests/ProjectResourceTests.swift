import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    // SF-0801-001...008 — import performs native raster validation away
    // from the document actor, retains exact bytes, and never stores a path.
    func testImageImportPreservesExactBytesMetadataAndRejectsCorruptInput() async throws {
        let fixture = try makeFixture()
        let imageURL = fixture.url.appendingPathComponent("Calm sample.png")
        let original = try makePNG(width: 7, height: 5)
        try original.write(to: imageURL)

        let prepared = try await ImageImportWorker().prepare(url: imageURL)
        XCTAssertEqual(prepared.data, original)
        XCTAssertEqual(prepared.asset.pixelWidth, 7)
        XCTAssertEqual(prepared.asset.pixelHeight, 5)
        XCTAssertEqual(prepared.asset.format, .png)
        XCTAssertEqual(prepared.asset.displayName, "Calm sample")
        XCTAssertEqual(prepared.asset.contentHash, ProjectResourceStore.digest(original))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(prepared.asset), as: UTF8.self).contains(fixture.url.path))
        try prepared.asset.validate()

        let corruptURL = fixture.url.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: corruptURL)
        do {
            _ = try await ImageImportWorker().prepare(url: corruptURL)
            XCTFail("corrupt raster bytes must not become an asset")
        } catch {
            XCTAssertEqual(error as? ImageImportError, .corrupt)
        }
    }

    func testImageCanonicalNamespaceAndMetadataRejectIncompleteUnknownAndOversizedValues() throws {
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty {
            NodeProperty(key: PropertyKey(rawValue: CanonicalImageStyle.namespace + key), value: value, origin: .authored)
        }
        let assetID = AssetID()
        let valid: [NodeProperty] = [
            property("assetID", .string(assetID.description)),
            property("fit", .string(ImageFitMode.fit.rawValue)),
            property("focal.x", .number(0.5)),
            property("focal.y", .number(0.5)),
            property("alt", .string("Product photograph")),
            property("decorative", .boolean(false)),
        ]
        let parent = NodeParent.node(NodeID())
        XCTAssertNoThrow(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .image, name: "Image", parent: parent, properties: valid)
        ))
        XCTAssertThrowsError(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .image, name: "Image", parent: parent, properties: Array(valid.dropLast()))
        )) { XCTAssertEqual($0 as? ModelValidationError, .invalidImageReference) }
        XCTAssertThrowsError(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .image, name: "Image", parent: parent, properties: valid + [property("unknown", .string("value"))])
        )) { XCTAssertEqual($0 as? ModelValidationError, .invalidImageReference) }
        XCTAssertThrowsError(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .frame, name: "Frame", parent: parent, properties: valid)
        )) { XCTAssertEqual($0 as? ModelValidationError, .invalidImageReference) }

        let oversizedFilename = String(repeating: "a", count: ImageAsset.maximumOriginalFilenameBytes + 1)
        let asset = ImageAsset(
            resourceID: ResourceID(), displayName: "Image", originalFilename: oversizedFilename,
            format: .png, pixelWidth: 1, pixelHeight: 1, byteCount: 1,
            contentHash: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try asset.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidImageAsset)
        }
    }

    // SF-0801-001, SF-0801-004, SF-0802-004 — canonical index remains in
    // the bounded package while original bytes use the existing sidecar.
    func testImageResourceSidecarRoundTripPreservesBytesAndMissingIntent() async throws {
        let fixture = try makeFixture()
        let projectURL = fixture.url.appendingPathComponent("Images.siteforge")
        let original = try makePNG(width: 4, height: 3)
        let hash = ProjectResourceStore.digest(original)
        let descriptor = ProjectResourceDescriptor(
            id: ResourceID(), filename: "hero.png", mediaType: "image/png",
            byteCount: original.count, sha256: hash
        )
        let asset = ImageAsset(
            resourceID: descriptor.id, displayName: "Hero", originalFilename: "hero.png",
            format: .png, pixelWidth: 4, pixelHeight: 3,
            byteCount: original.count, contentHash: hash
        )
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        let transient = try ProjectPackage(document: document).withResource(descriptor, data: original)
        let backend = DocumentLifecycleBackend()
        let identity = LifecycleOperationIdentity(
            id: LifecycleOperationID(), epoch: LifecycleEpoch(),
            documentID: document.id, projectID: transient.projectID,
            revision: document.revision,
            destination: .file(projectURL, kind: .durable), intent: .saveAs
        )
        let history = PersistedHistorySnapshot(
            documentID: document.id, documentRevision: document.revision,
            boundaryRevision: document.revision, undoEntries: [], redoEntries: []
        )
        let completed = try await backend.write(
            transient, history: history,
            to: projectURL, expected: nil, identity: identity
        )
        XCTAssertEqual(completed.destinationURL, projectURL)
        let packageBytes = try Data(contentsOf: projectURL)
        XCTAssertFalse(packageBytes.range(of: original) != nil, "resource bytes must not be embedded in the package")
        let sidecar = ProjectResourceStore(root: ProjectResourceStore.sidecarURL(for: projectURL))
        let persistedBytes = try await sidecar.data(for: descriptor)
        XCTAssertEqual(persistedBytes, original)

        let readIdentity = LifecycleOperationIdentity(
            id: LifecycleOperationID(), epoch: LifecycleEpoch(),
            documentID: document.id, projectID: transient.projectID,
            revision: document.revision,
            destination: .file(projectURL, kind: .durable), intent: .open
        )
        let reopened = try await backend.read(from: projectURL, identity: readIdentity)
        XCTAssertEqual(try reopened.package.resourceData(for: descriptor), original)
        XCTAssertEqual(reopened.package.document.imageAssets, [asset])

        try FileManager.default.removeItem(at: ProjectResourceStore.sidecarURL(for: projectURL))
        let missing = try await backend.read(from: projectURL, identity: readIdentity)
        XCTAssertEqual(missing.package.document.imageAssets, [asset], "missing bytes retain authored AssetID intent")
        XCTAssertThrowsError(try missing.package.resourceData(for: descriptor)) {
            XCTAssertEqual($0 as? ProjectResourceError, .missingBlob)
        }
    }

    @MainActor
    func testRejectedAssetMutationRollsBackStagedResourceBytes() throws {
        let fixture = try makeFixture()
        let controller = DocumentLifecycleController(
            session: DocumentSession(),
            recoveryDirectory: fixture.url.appendingPathComponent("recovery", isDirectory: true)
        )
        let bytes = try makePNG(width: 2, height: 2)
        let descriptor = ProjectResourceDescriptor(
            id: ResourceID(), filename: "rollback.png", mediaType: "image/png",
            byteCount: bytes.count, sha256: ProjectResourceStore.digest(bytes)
        )
        enum Expected: Error { case rejected }
        XCTAssertThrowsError(try controller.installingProjectResource(descriptor, data: bytes) {
            throw Expected.rejected
        }) { XCTAssertTrue($0 is Expected) }
        XCTAssertThrowsError(try controller.projectResourceData(for: descriptor.id)) {
            XCTAssertEqual($0 as? ProjectResourceError, .missingBlob)
        }

        let result: String = try controller.installingProjectResource(descriptor, data: bytes) { "committed" }
        XCTAssertEqual(result, "committed")
        XCTAssertEqual(try controller.projectResourceData(for: descriptor.id), bytes)
    }

    @MainActor
    func testImageAssetRenameAndReplacementPreserveIdentityWithExactUndoRedo() throws {
        let firstBytes = try makePNG(width: 3, height: 2)
        let secondBytes = try makePNG(width: 5, height: 4)
        let stableID = AssetID()
        let original = ImageAsset(
            id: stableID, resourceID: ResourceID(), displayName: "Hero",
            originalFilename: "hero.png", format: .png, pixelWidth: 3, pixelHeight: 2,
            byteCount: firstBytes.count, contentHash: ProjectResourceStore.digest(firstBytes)
        )
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: original, index: 0)))

        var renamed = original
        renamed.displayName = "Primary hero"
        try session.execute(.updateImageAsset(.init(asset: renamed)))
        XCTAssertEqual(session.document.imageAssets[0].id, stableID)
        XCTAssertEqual(session.document.imageAssets[0].displayName, "Primary hero")

        var replaced = renamed
        replaced.resourceID = ResourceID()
        replaced.originalFilename = "replacement.png"
        replaced.pixelWidth = 5; replaced.pixelHeight = 4
        replaced.byteCount = secondBytes.count
        replaced.contentHash = ProjectResourceStore.digest(secondBytes)
        try session.execute(.updateImageAsset(.init(asset: replaced)))
        XCTAssertEqual(session.document.imageAssets, [replaced])
        try session.undo()
        XCTAssertEqual(session.document.imageAssets, [renamed])
        try session.undo()
        XCTAssertEqual(session.document.imageAssets, [original])
        try session.redo(); try session.redo()
        XCTAssertEqual(session.document.imageAssets, [replaced])

        let duplicate = ImageAsset(
            resourceID: ResourceID(), displayName: "Duplicate",
            originalFilename: "duplicate.png", format: replaced.format,
            pixelWidth: replaced.pixelWidth, pixelHeight: replaced.pixelHeight,
            byteCount: replaced.byteCount, contentHash: replaced.contentHash
        )
        let duplicateCommand = DocumentCommand.insertImageAsset(.init(asset: duplicate, index: 1))
        XCTAssertFalse(CommandRegistry().availability(for: duplicateCommand, in: session.document).isEnabled)
    }

    // SF-0801-004, SF-0802-001...008 — asset/node insertion and Image
    // Inspector edits use exact command inverses and preserve stable IDs.
    @MainActor
    func testImageAssetInsertionInspectorUndoRedoAndSchemaMigration() throws {
        var document = ProjectCreation.blank()
        let bytes = try makePNG(width: 9, height: 6)
        let hash = ProjectResourceStore.digest(bytes)
        let asset = ImageAsset(
            resourceID: ResourceID(), displayName: "Product", originalFilename: "product.png",
            format: .png, pixelWidth: 9, pixelHeight: 6,
            byteCount: bytes.count, contentHash: hash
        )
        let session = DocumentSession(document: document)
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let nodeID = NodeID()
        let sceneID = CanvasViewportSceneID()
        let command = AuthoringInsertionCommand.image(.init(
            identity: .init(documentID: session.document.id, pageID: pageID, revision: session.document.revision, generation: 1),
            nodeID: nodeID, parentID: rootID, index: 0,
            geometry: .defaultValue(for: .image, at: .init(x: 80, y: 90)),
            assetID: asset.id, provenance: .menu
        ))
        let prepared = try InsertionCommandRegistry().prepare(command, in: session.document, context: .init(
            activePageID: pageID, activeRoute: .init(rawValue: "/"), operationGeneration: 1,
            availableNodeIDs: Set(session.document.pages[0].nodes.map(\.id))
        ))
        try session.execute(prepared.documentCommand)
        let inserted = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID })
        XCTAssertEqual(inserted.kind, .image)
        XCTAssertEqual(CanonicalImageStyle.resolve(inserted)?.assetID, asset.id)

        let context = TransformValidationContext(
            activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 7,
            selectedNodeIDs: [nodeID], availableNodeIDs: [nodeID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil
        )
        let identity = ImageInspectorOperationIdentity(
            documentID: session.document.id, pageID: pageID, revision: session.document.revision,
            sceneID: sceneID, rendererGeneration: 7, selectedNodeIDs: [nodeID]
        )
        let edit = try ImageInspectorCommandRegistry().prepare(
            .init(identity: identity, edit: .focal(x: 0.2, y: 0.8)),
            in: session.document, context: context
        )
        try session.execute(edit.command)
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID }))?.focalX, 0.2)
        try session.undo()
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID }))?.focalX, 0.5)
        try session.redo()
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID }))?.focalY, 0.8)

        XCTAssertFalse(CommandRegistry().availability(
            for: .removeImageAsset(.init(assetID: asset.id)), in: session.document
        ).isEnabled, "an in-use asset requires explicit detach resolution")
        let roundTrip = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(roundTrip.imageAssets, [asset])
        XCTAssertEqual(roundTrip.pages[0].nodes.first { $0.id == nodeID }?.id, nodeID)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(ProjectCreation.blank())) as? [String: Any])
        legacyObject["schemaVersion"] = 4
        var legacyDocument = try XCTUnwrap(legacyObject["document"] as? [String: Any])
        legacyDocument.removeValue(forKey: "imageAssets")
        legacyObject["document"] = legacyDocument
        let migrated = try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertTrue(migrated.imageAssets.isEmpty)
        XCTAssertTrue(String(decoding: try DocumentSerializer.encode(migrated), as: UTF8.self).contains("\"schemaVersion\":6"))
    }

    func testImageInspectorRejectsInvalidStaleAndInapplicableEditsWithoutMutation() throws {
        let document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let nodeID = document.pages[0].rootNodeIDs[0]
        let sceneID = CanvasViewportSceneID()
        let context = TransformValidationContext(
            activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 4,
            selectedNodeIDs: [nodeID], availableNodeIDs: [nodeID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil
        )
        let identity = ImageInspectorOperationIdentity(
            documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: sceneID, rendererGeneration: 4, selectedNodeIDs: [nodeID]
        )
        let registry = ImageInspectorCommandRegistry()
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: identity, edit: .focal(x: .nan, y: 0.5)), in: document, context: context
        )) { XCTAssertEqual($0 as? ImageInspectorError, .invalidFocalPoint) }
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: identity, edit: .fit(.fill)), in: document, context: context, cancelled: true
        )) { XCTAssertEqual($0 as? ImageInspectorError, .cancelled) }
        let stale = ImageInspectorOperationIdentity(
            documentID: document.id, pageID: pageID, revision: document.revision + 1,
            sceneID: sceneID, rendererGeneration: 4, selectedNodeIDs: [nodeID]
        )
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: stale, edit: .fit(.fill)), in: document, context: context
        )) { XCTAssertEqual($0 as? ImageInspectorError, .staleRevision) }
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: identity, edit: .fit(.fill)), in: document, context: context
        )) { XCTAssertEqual($0 as? ImageInspectorError, .noApplicableTarget) }
    }

    func testImageThumbnailIsBoundedDerivativeWithoutChangingOriginalBytes() async throws {
        let original = try makePNG(width: 640, height: 360)
        let thumbnail = try await ImageThumbnailWorker().thumbnailPNG(from: original, maximumPixelSize: 80)
        XCTAssertNotEqual(thumbnail, original)
        XCTAssertEqual(ProjectResourceStore.digest(original), ProjectResourceStore.digest(original))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 80)
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int), 80)
    }

    @MainActor
    func testExplicitInUseAssetResolutionIsOneExactUndoableBatch() throws {
        let bytes = try makePNG(width: 16, height: 9)
        let asset = ImageAsset(
            resourceID: ResourceID(), displayName: "Hero", originalFilename: "hero.png",
            format: .png, pixelWidth: 16, pixelHeight: 9,
            byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes)
        )
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let page = session.document.pages[0]
        let rootID = page.rootNodeIDs[0]
        func property(_ key: String, _ value: PropertyValue, _ origin: PropertyOrigin) -> NodeProperty {
            NodeProperty(id: PropertyID(), key: PropertyKey(rawValue: key), value: value, origin: origin)
        }
        let node = DocumentNode(
            kind: .image, name: "Image", parent: .node(rootID), childIDs: [], properties: [
                property("layout.x", .number(20), .authored),
                property("layout.y", .number(20), .authored),
                property("layout.width", .number(320), .authored),
                property("layout.height", .number(240), .authored),
                property(CanonicalImageStyle.namespace + "assetID", .string(asset.id.description), .authored),
                property(CanonicalImageStyle.namespace + "fit", .string(ImageFitMode.fit.rawValue), .defaulted),
                property(CanonicalImageStyle.namespace + "focal.x", .number(0.5), .defaulted),
                property(CanonicalImageStyle.namespace + "focal.y", .number(0.5), .defaulted),
                property(CanonicalImageStyle.namespace + "alt", .string(""), .defaulted),
                property(CanonicalImageStyle.namespace + "decorative", .boolean(false), .defaulted),
            ]
        )
        try session.execute(.insertNode(.init(pageID: page.id, node: node, index: 0)))
        let beforeResolution = session.document
        try session.execute(.batch([
            .removeNode(.init(pageID: page.id, nodeID: node.id)),
            .removeImageAsset(.init(assetID: asset.id)),
        ]))
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertFalse(session.document.pages[0].nodes.contains(where: { $0.id == node.id }))
        try session.undo()
        XCTAssertEqual(session.document.id, beforeResolution.id)
        XCTAssertEqual(session.document.pages, beforeResolution.pages)
        XCTAssertEqual(session.document.imageAssets, beforeResolution.imageAssets)
        XCTAssertGreaterThan(session.document.revision, beforeResolution.revision)
        try session.redo()
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertFalse(session.document.pages[0].nodes.contains(where: { $0.id == node.id }))
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

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.16, green: 0.48, blue: 0.72, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
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
