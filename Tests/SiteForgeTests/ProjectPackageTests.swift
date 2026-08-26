import CryptoKit
import XCTest
@testable import SiteForge

final class ProjectPackageTests: XCTestCase {
    private let projectID = ProjectID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
    private let documentID = DocumentID(UUID(uuidString: "20000000-0000-0000-0000-000000000001")!)
    private let pageID = PageID(UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)

    private var fixtures: [ApplicationOwnedTestFixture] = []

    override func tearDownWithError() throws {
        for fixture in fixtures.reversed() { try fixture.cleanup() }
        fixtures.removeAll()
        try super.tearDownWithError()
    }

    private func fixtureDirectory() throws -> URL {
        // Package I/O is descriptor-bound production code. Exercise it below
        // the test host's owned temporary directory, not a checkout that may
        // itself be mediated by a File Provider.
        let fixture = try ApplicationOwnedTestFixture.create("packages")
        fixtures.append(fixture)
        return fixture.url
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
        XCTAssertTrue(text.contains("\"documentSchemaVersion\":4"))
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

    // SF-0301-004, SF-0301-007, SF-0301-008 — descriptor-backed reads retain
    // cancellation as a neutral result rather than misclassifying validation
    // cancellation as an I/O failure that a lifecycle caller could publish.
    func testCancellationDuringReadSnapshotRemainsNeutral() async throws {
        let destination = try fixtureDirectory().appendingPathComponent("cancel-read.siteforge")
        try await ProjectPackageStore().write(package(), to: destination)
        let barrier = DeterministicCancellationBarrier(blockAt: 4)
        let diagnostics = ProjectPackageDiagnostics()
        let store = ProjectPackageStore(
            diagnostics: diagnostics,
            cancellation: CooperativeCancellationCheckpoint(barrier.check)
        )
        let task = Task { try await store.readSnapshot(from: destination) }

        await barrier.waitUntilBlocked()
        task.cancel()
        barrier.release()

        do {
            _ = try await task.value
            XCTFail("Cancelled snapshot validation must not return a package")
        } catch is CancellationError {
            // Intentionally state-neutral.
        }
        let records = await diagnostics.records
        XCTAssertTrue(records.isEmpty)
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

    // SF-0301-004, SF-0301-006, SF-0303-005 — recovery discovery reads the
    // exact app-owned artifact through the same strict snapshot path used at
    // launch. The filename is bound to the package manifest's project ID,
    // which is intentionally not the document ID in this migration golden.
    func testOwnedLegacyRecoveryArtifactBindsManifestProjectIdentity() async throws {
        let store = ProjectPackageStore()
        let directory = try fixtureDirectory().appendingPathComponent("recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(directory)
        let projectID = ProjectID(UUID(uuidString: "11000000-0000-0000-0000-000000000002")!)
        let artifact = DocumentLifecycleBackend.recoveryURL(for: projectID, in: directory)
        let bytes = try legacyGolden(
            named: "schema-v1-rootless",
            sha256: "ef1455c5eb9055ec97fb5d41562686226e9db040313a4609e769cc5f7f44694d"
        )
        try bytes.write(to: artifact, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: artifact.path)

        let read = try await store.readOwnedRecoverySnapshot(
            from: artifact,
            expectedProjectID: projectID
        )
        XCTAssertEqual(read.package.projectID, projectID)
        XCTAssertEqual(read.package.document.revision, 4)
    }

    // SF-0301-005, SF-0303-005, SF-0303-008, SF-1702-008 — schema 2 is an
    // immutable retained compatibility input, not a dynamically relabeled
    // current payload. Its digest locks the historical on-disk shape.
    func testImmutableSchemaTwoGoldenMigratesGuidesToEmptyAndRoundTripsDeterministically() async throws {
        let store = ProjectPackageStore()
        let legacyPackage = try legacyGolden(
            named: "schema-v2-minimum",
            sha256: "c2ebf92c01924cccd9fe6db5a48bbe4d23a6273d03526f41ed5f744efcbe7739"
        )

        let first = try await store.decode(legacyPackage)
        let second = try await store.decode(legacyPackage)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.projectID.description, "12000000-0000-0000-0000-000000000002")
        XCTAssertEqual(first.document.id.description, "22000000-0000-0000-0000-000000000002")
        XCTAssertEqual(first.document.revision, 2)
        XCTAssertEqual(first.document.guides, [])
        XCTAssertEqual(first.document.pages.map(\.name), ["Schema Two Home"])
        XCTAssertNoThrow(try first.document.validate())

        let savedOnce = try await store.encode(first)
        let savedTwice = try await store.encode(first)
        XCTAssertEqual(savedOnce, savedTwice)
        let reopened = try await store.decode(savedOnce)
        XCTAssertEqual(reopened, first)
    }

    // SF-0508-001...005, SF-0508-008 — this checked-in package is a real
    // schema-v4 payload from before canonical RGBA existed. It exercises the
    // production container, integrity, strict decoder, transaction, and save
    // path rather than building a pretend legacy document inside the test.
    @MainActor
    func testImmutableSchemaFourLegacySurfaceFixtureResolvesAuthorsAndRemovesFillDeterministically() async throws {
        let store = ProjectPackageStore()
        let legacyData = try legacyGolden(
            named: "schema-v4-legacy-surface",
            sha256: "3ab14ab513e8932395579540750016e3a73f4742e9d463574c6443b3f4303b12"
        )
        let legacy = try await store.decode(legacyData)
        let page = try XCTUnwrap(legacy.document.pages.only)
        let nodeID = NodeID(UUID(uuidString: "63000000-0000-0000-0000-000000000004")!)
        let legacyNode = try XCTUnwrap(page.nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: legacyNode).0, .legacySurface)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: legacyNode).1, .defaulted)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: legacyNode)?.0, 1)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: legacyNode)?.1, .defaulted)

        let registry = DesignInspectorCommandRegistry()
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "83000000-0000-0000-0000-000000000004")!)
        func context(_ document: CanonicalDocument) -> TransformValidationContext {
            TransformValidationContext(
                activePageID: page.id, currentSceneID: sceneID, rendererGeneration: 4,
                selectedNodeIDs: [nodeID], availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
                isLifecycleAvailable: true, lifecycleDisabledReason: nil
            )
        }
        func command(_ document: CanonicalDocument, _ edit: DesignInspectorEdit) -> DesignInspectorCommand {
            .init(
                identity: .init(documentID: document.id, pageID: page.id, revision: document.revision, sceneID: sceneID, rendererGeneration: 4),
                orderedNodeIDs: [nodeID], edit: edit, provenance: .automation, cancelled: false
            )
        }

        let authored = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#20406080"))
        let session = DocumentSession(document: legacy.document)
        _ = try session.execute(registry.prepare(command(session.document, .fill(authored)), in: session.document, context: context(session.document)).documentCommand)
        let authoredNode = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: authoredNode).0, authored)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: authoredNode).1, .authored)

        _ = try session.execute(registry.prepare(command(session.document, .fill(nil)), in: session.document, context: context(session.document)).documentCommand)
        let removed = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: removed).0, nil)
        XCTAssertNil(removed.insertionProperty("style.fill"), "Removing an authored fill must not revive legacy surface fallback.")
        try session.undo()
        let undoneNode = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: undoneNode).0, authored)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: undoneNode).1, .authored)
        try session.redo()

        let resaved = ProjectPackage(
            projectID: legacy.projectID, createdAt: legacy.createdAt, modifiedAt: legacy.modifiedAt,
            document: session.document, optionalMembers: legacy.optionalMembers, compatibility: legacy.compatibility
        )
        let reopened = try await store.decode(try await store.encode(resaved))
        let reopenedNode = try XCTUnwrap(reopened.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: reopenedNode).0, nil)
        XCTAssertNil(reopenedNode.insertionProperty("style.fill"))

        var originallyOmitted = reopenedNode
        originallyOmitted.properties.removeAll { $0.key.rawValue.hasPrefix("style.fill") }
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: originallyOmitted).0, nil)
    }

    // SF-0301-004...006, SF-0303-005, SF-0508-001...008 — a retained
    // schema-v4 package migrates through the real layer registry, then keeps
    // exact authored identities and ordering across save/reopen and the owned
    // recovery path. Legacy fill keys are retired by the first v1 write and
    // must never become a fallback source again.
    @MainActor
    func testHistoricalSurfaceMigratesToOrderedLayersAcrossSaveReopenAndRecovery() async throws {
        let store = ProjectPackageStore()
        let legacyData = try legacyGolden(
            named: "schema-v4-legacy-surface",
            sha256: "3ab14ab513e8932395579540750016e3a73f4742e9d463574c6443b3f4303b12"
        )
        let legacy = try await store.decode(legacyData)
        let page = try XCTUnwrap(legacy.document.pages.only)
        let nodeID = NodeID(UUID(uuidString: "63000000-0000-0000-0000-000000000004")!)
        let originalNode = try XCTUnwrap(page.nodes.first(where: { $0.id == nodeID }))
        let migratedLegacyID = try XCTUnwrap(CanonicalFillLayerCodec.legacySolidLayer(for: originalNode)?.id)
        let gradientID = FillLayerID(UUID(uuidString: "A3000000-0000-4000-8000-000000000001")!)
        let startID = GradientStopID(UUID(uuidString: "A3000000-0000-4000-8000-000000000002")!)
        let endID = GradientStopID(UUID(uuidString: "A3000000-0000-4000-8000-000000000003")!)
        let startColor = CanonicalSolidColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let endColor = CanonicalSolidColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1)
        let stops = [
            CanonicalGradientStop(id: startID, position: 0.2, color: startColor),
            CanonicalGradientStop(id: endID, position: 0.85, color: endColor),
        ]
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "83000000-0000-0000-0000-000000000014")!)
        let registry = DesignInspectorCommandRegistry()
        func context(_ document: CanonicalDocument) -> TransformValidationContext {
            TransformValidationContext(
                activePageID: page.id,
                currentSceneID: sceneID,
                rendererGeneration: 14,
                selectedNodeIDs: [nodeID],
                availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
                isLifecycleAvailable: true,
                lifecycleDisabledReason: nil
            )
        }
        func command(_ document: CanonicalDocument, edit: DesignFillLayerEdit) -> DesignFillLayerCommand {
            .init(
                identity: .init(
                    documentID: document.id,
                    pageID: page.id,
                    revision: document.revision,
                    sceneID: sceneID,
                    rendererGeneration: 14
                ),
                orderedNodeIDs: [nodeID],
                edit: edit,
                provenance: .automation,
                cancelled: false
            )
        }
        func node(in package: ProjectPackage) throws -> DocumentNode {
            try XCTUnwrap(package.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        }

        let session = DocumentSession(document: legacy.document)
        let addGradient = try registry.prepare(
            command(session.document, edit: .addLinearGradient(
                id: gradientID,
                angleDegrees: 405,
                stops: stops
            )),
            in: session.document,
            context: context(session.document)
        )
        _ = try session.execute(addGradient.documentCommand)
        let reorder = try registry.prepare(
            command(session.document, edit: .reorder(gradientID, to: 0)),
            in: session.document,
            context: context(session.document)
        )
        _ = try session.execute(reorder.documentCommand)
        let disable = try registry.prepare(
            command(session.document, edit: .setEnabled(gradientID, false)),
            in: session.document,
            context: context(session.document)
        )
        _ = try session.execute(disable.documentCommand)

        let expected = [
            CanonicalFillLayer.linearGradient(
                id: gradientID,
                angleDegrees: 45,
                stops: stops,
                isEnabled: false
            ),
            CanonicalFillLayer.solid(id: migratedLegacyID, color: .legacySurface),
        ]
        let migratedNode = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: migratedNode), expected)
        for key in ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"] {
            XCTAssertNil(migratedNode.insertionProperty(key), "The first v1 write must retire legacy key \(key).")
        }

        let migratedPackage = ProjectPackage(
            projectID: legacy.projectID,
            createdAt: legacy.createdAt,
            modifiedAt: legacy.modifiedAt,
            document: session.document,
            optionalMembers: legacy.optionalMembers,
            compatibility: legacy.compatibility
        )
        let saved = try await store.encode(migratedPackage)
        let reopened = try await store.decode(saved)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: try node(in: reopened)), expected)
        let resaved = try await store.encode(reopened)
        XCTAssertEqual(resaved, saved, "Reopened v1 layer packages must remain byte-deterministic.")

        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("fill-layer-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: legacy.projectID, in: recoveryDirectory)
        try await store.write(reopened, to: recoveryURL, policy: .recovery(legacy.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL,
            expectedProjectID: legacy.projectID
        ).package
        let recoveredNode = try node(in: recovered)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: recoveredNode), expected)
        XCTAssertNotNil(recoveredNode.insertionProperty(CanonicalFillLayerCodec.orderKey))
        for key in ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"] {
            XCTAssertNil(recoveredNode.insertionProperty(key), "Recovery must not revive legacy key \(key).")
        }
    }

    // SF-0506-001/004/005/008 — box appearance is optional for historical
    // packages and becomes deterministic canonical state only after an edit.
    // Real package and owned-recovery paths preserve it exactly.
    @MainActor
    func testBoxAppearancePersistsAcrossPackageReopenAndOwnedRecovery() async throws {
        let baseline = package()
        let page = try XCTUnwrap(baseline.document.pages.first)
        let node = try XCTUnwrap(page.nodes.first(where: {
            [.frame, .section, .stack, .grid].contains($0.kind)
        }))
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "84000000-0000-4000-8000-000000000014")!)
        let rendererGeneration: UInt64 = 14
        func context(_ document: CanonicalDocument) -> TransformValidationContext {
            .init(
                activePageID: page.id,
                currentSceneID: sceneID,
                rendererGeneration: rendererGeneration,
                selectedNodeIDs: [node.id],
                availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
                isLifecycleAvailable: true,
                lifecycleDisabledReason: nil
            )
        }
        func command(_ document: CanonicalDocument, _ edit: DesignBoxStyleEdit) -> DesignBoxStyleCommand {
            .init(
                identity: .init(
                    documentID: document.id, pageID: page.id,
                    revision: document.revision, sceneID: sceneID,
                    rendererGeneration: rendererGeneration
                ),
                orderedNodeIDs: [node.id], edit: edit,
                provenance: .automation, cancelled: false
            )
        }
        let expected = CanonicalBoxStyle(
            border: .init(
                color: .init(red: 0.12, green: 0.24, blue: 0.72, alpha: 1),
                width: 3, style: .dotted
            ),
            cornerRadius: 18,
            shadow: .init(
                color: .init(red: 0, green: 0, blue: 0, alpha: 0.3),
                offsetX: 2, offsetY: 10, blur: 20, spread: 1
            )
        )
        let registry = DesignBoxStyleCommandRegistry()
        let session = DocumentSession(document: baseline.document)
        for edit in [
            DesignBoxStyleEdit.border(expected.border),
            .cornerRadius(expected.cornerRadius),
            .shadow(expected.shadow),
        ] {
            let prepared = try registry.prepare(
                command(session.document, edit),
                in: session.document,
                context: context(session.document)
            )
            _ = try session.execute(prepared.documentCommand)
        }

        let store = ProjectPackageStore()
        let authored = ProjectPackage(
            projectID: baseline.projectID,
            createdAt: baseline.createdAt,
            modifiedAt: baseline.modifiedAt,
            document: session.document,
            optionalMembers: baseline.optionalMembers,
            compatibility: baseline.compatibility
        )
        let encoded = try await store.encode(authored)
        let reopened = try await store.decode(encoded)
        let reopenedNode = try XCTUnwrap(reopened.document.pages[0].nodes.first(where: { $0.id == node.id }))
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: reopenedNode), expected)
        let resaved = try await store.encode(reopened)
        XCTAssertEqual(resaved, encoded)

        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("box-appearance-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: baseline.projectID, in: recoveryDirectory)
        try await store.write(reopened, to: recoveryURL, policy: .recovery(baseline.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL,
            expectedProjectID: baseline.projectID
        ).package
        let recoveredNode = try XCTUnwrap(recovered.document.pages[0].nodes.first(where: { $0.id == node.id }))
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: recoveredNode), expected)
    }

    // SF-0301-004...006, SF-0303-005, SF-0508-001...008 — recomputing the
    // package member checksum cannot make malformed current fill state valid.
    // Canonical validation rejects the candidate before lifecycle adoption.
    func testChecksumValidCurrentPackageRejectsMalformedFillLayerOrder() async throws {
        let store = ProjectPackageStore()
        let baseline = package()
        var document = baseline.document
        let layer = CanonicalFillLayer.solid(
            id: FillLayerID(UUID(uuidString: "A3100000-0000-4000-8000-000000000001")!),
            color: .init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        )
        document.pages[0].nodes[0].properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        let valid = ProjectPackage(
            projectID: baseline.projectID,
            createdAt: baseline.createdAt,
            modifiedAt: baseline.modifiedAt,
            document: document,
            optionalMembers: baseline.optionalMembers,
            compatibility: baseline.compatibility
        )
        var members = try decodeArchive(try await store.encode(valid))
        let documentMember = try XCTUnwrap(members.first(where: { $0.path == "document.json" }))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: documentMember.data) as? [String: Any])
        var documentJSON = try XCTUnwrap(envelope["document"] as? [String: Any])
        var pages = try XCTUnwrap(documentJSON["pages"] as? [[String: Any]])
        var page = try XCTUnwrap(pages.first)
        var nodes = try XCTUnwrap(page["nodes"] as? [[String: Any]])
        var node = try XCTUnwrap(nodes.first)
        var properties = try XCTUnwrap(node["properties"] as? [[String: Any]])
        let orderIndex = try XCTUnwrap(properties.firstIndex { $0["key"] as? String == CanonicalFillLayerCodec.orderKey })
        var orderProperty = properties[orderIndex]
        var value = try XCTUnwrap(orderProperty["value"] as? [String: Any])
        var stringPayload = try XCTUnwrap(value["string"] as? [String: Any])
        let validOrder = try XCTUnwrap(stringPayload["_0"] as? String)
        stringPayload["_0"] = validOrder + ","
        value["string"] = stringPayload
        orderProperty["value"] = value
        properties[orderIndex] = orderProperty
        node["properties"] = properties
        nodes[0] = node
        page["nodes"] = nodes
        pages[0] = page
        documentJSON["pages"] = pages
        envelope["document"] = documentJSON
        let malformedDocument = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        members = try replacingDocumentAndIntegrity(in: members, with: malformedDocument)

        await XCTAssertThrowsProjectPackageError(.corruptDocument) {
            try await store.decode(encodeArchive(members))
        }
    }

    // SF-0301-004, SF-0301-005, SF-1702-004 — a newer canonical payload
    // cannot be relabeled as an older schema and silently discard fields such
    // as guides during migration.
    func testCurrentDocumentCannotBeRelabeledAsHistoricalSchema() throws {
        var document = ProjectCreation.blank()
        document.guides = [
            AuthoredGuide(
                pageID: try XCTUnwrap(document.pages.first?.id),
                axis: .vertical,
                position: 120
            )
        ]
        let current = try DocumentSerializer.encode(document)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])

        for schema in [1, 2] {
            var relabeled = object
            relabeled["schemaVersion"] = schema
            let bytes = try JSONSerialization.data(withJSONObject: relabeled, options: [.sortedKeys])
            XCTAssertThrowsError(try DocumentSerializer.decode(bytes)) { error in
                XCTAssertEqual(error as? DocumentSerializationError, .malformedInput)
            }
        }
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
        // The descriptor-bound swap deliberately retains the displaced old
        // entry: a same-UID process could replace the staging name before an
        // unsafe pathname cleanup. Prove the retained artifact is complete
        // prior-package bytes, not a partial write or second destination.
        let stagingNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".siteforge-stage-") }
        XCTAssertEqual(stagingNames.count, 1)
        let retained = try await store.read(from: directory.appendingPathComponent(stagingNames[0]))
        XCTAssertEqual(retained.document.pages[0].name, "Before")
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

    // SF-0301-004, SF-0303-005, SF-1702-004 — manifest/document records are
    // closed at their current versions; opaque optional members remain separate.
    func testCurrentManifestAndDocumentUnknownFieldsAndSchemaMismatchAreRejected() async throws {
        let store = ProjectPackageStore()
        let valid = try await store.encode(package())
        let members = try decodeArchive(valid)

        let manifestUnknown = try editingManifest(in: members) { $0["futureManifestField"] = true }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(manifestUnknown))
        }
        let futureManifest = try editingManifest(in: members) {
            $0["packageVersion"] = ProjectPackage.currentPackageVersion + 1
            $0["futureManifestField"] = true
        }
        await XCTAssertThrowsProjectPackageError(.unsupportedPackageVersion(ProjectPackage.currentPackageVersion + 1)) {
            try await store.decode(encodeArchive(futureManifest))
        }
        let compatibilityUnknown = try editingManifest(in: members) { manifest in
            var compatibility = manifest["compatibility"] as! [String: Any]
            compatibility["futureCompatibilityField"] = true
            manifest["compatibility"] = compatibility
        }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(compatibilityUnknown))
        }
        let descriptorUnknown = try editingManifest(in: members) { manifest in
            var descriptors = manifest["members"] as! [[String: Any]]
            descriptors[0]["futureDescriptorField"] = true
            manifest["members"] = descriptors
        }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(descriptorUnknown))
        }
        let mismatchedSchema = try editingManifest(in: members) { $0["documentSchemaVersion"] = 2 }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(mismatchedSchema))
        }
        let incompatibleDeclaredMinimum = try editingManifest(in: members) { manifest in
            var compatibility = manifest["compatibility"] as! [String: Any]
            compatibility["minimumDocumentSchemaVersion"] = 5
            manifest["compatibility"] = compatibility
        }
        await XCTAssertThrowsProjectPackageError(.malformedMetadata) {
            try await store.decode(encodeArchive(incompatibleDeclaredMinimum))
        }

        let documentMember = try XCTUnwrap(members.first(where: { $0.path == "document.json" }))
        var documentEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: documentMember.data) as? [String: Any])
        var document = try XCTUnwrap(documentEnvelope["document"] as? [String: Any])
        document["futureDocumentField"] = true
        documentEnvelope["document"] = document
        let unknownDocument = try JSONSerialization.data(withJSONObject: documentEnvelope, options: [.sortedKeys])
        let repacked = try replacingDocumentAndIntegrity(in: members, with: unknownDocument)
        await XCTAssertThrowsProjectPackageError(.corruptDocument) {
            try await store.decode(encodeArchive(repacked))
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
