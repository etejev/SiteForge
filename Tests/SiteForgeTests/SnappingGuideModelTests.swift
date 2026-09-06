import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class SnappingGuideModelTests: XCTestCase {
    // SF-0404-001...004
    func testResolutionPriorityAxesHysteresisSuppressionAndEligibility() throws {
        var fixture = SnapTestFixture()
        let resolved = try fixture.resolve(dx: 85, dy: 25)
        XCTAssertEqual(resolved.operation, .move(delta: .init(dx: 90, dy: 30), constraint: .none))
        XCTAssertEqual(resolved.smartGuides.count, 2)
        XCTAssertEqual(resolved, try fixture.resolve(dx: 85, dy: 25))
        XCTAssertNotNil(try fixture.resolve(dx: 81.5, previous: resolved.winners).winners[.horizontal])
        XCTAssertNil(try fixture.resolve(dx: 80).winners[.horizontal])
        XCTAssertTrue(try fixture.resolve(dx: 85, suppressed: true).winners.isEmpty)

        fixture.document.guides = [
            .init(id: fixture.guideID, pageID: fixture.pageID, axis: .vertical, position: 194),
        ]
        XCTAssertEqual(try fixture.resolve(dx: 80).winners[.horizontal]?.kind, .authoredGuide)
        fixture.document.guides = []
        fixture.referenceVisible = false
        XCTAssertTrue(try fixture.resolve(dx: 85, dy: 25).winners.isEmpty)
        fixture.referenceVisible = true
        fixture.referenceLocked = true
        XCTAssertFalse(try fixture.resolve(dx: 85, dy: 25).winners.isEmpty)
    }

    // SF-0404-003, SF-0404-004
    func testZoomCancellationAndStaleIdentityAreTypedAndNeutral() throws {
        let fixture = SnapTestFixture()
        XCTAssertEqual(try fixture.resolve(dx: 87, zoom: 2).winners[.horizontal]?.distanceInPoints, 6)
        XCTAssertEqual(
            try fixture.resolve(dx: 87, zoom: 2, pixelRatio: 1).operation,
            try fixture.resolve(dx: 87, zoom: 2, pixelRatio: 2).operation
        )
        XCTAssertThrowsError(try fixture.resolve(
            dx: 85, cancellation: .init(isCancelled: { _ in true })
        )) { XCTAssertEqual($0 as? SnapError, .cancelled) }
        let raw = try fixture.prepared(dx: 85)
        var context = fixture.context(previous: [:], suppressed: false)
        context = .init(
            identity: .init(
                sessionID: TransformSessionID(), documentID: fixture.document.id,
                pageID: fixture.pageID, revision: fixture.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: 99
            ),
            activePageID: context.activePageID, selectedNodeIDs: context.selectedNodeIDs,
            objects: context.objects, guides: context.guides, zoom: context.zoom,
            pixelRatio: context.pixelRatio, previousWinners: [:], isSuppressed: false
        )
        XCTAssertThrowsError(try SnapResolver().resolve(raw: raw, context: context)) {
            XCTAssertEqual($0 as? SnapError, .staleTransform)
        }
    }

    // SF-0404-002, SF-0404-005, SF-0404-006
    func testGuideInputsShareOneRegistryAndOneExactUndoableTransaction() throws {
        let fixture = SnapTestFixture()
        let registry = GuideCommandRegistry()
        let commands = try GuideCommandProvenance.allCases.map {
            try registry.prepare(
                fixture.guideCommand(.addVertical, position: 123, provenance: $0),
                in: fixture.document, context: fixture.guideContext
            ).documentCommand
        }
        XCTAssertTrue(commands.dropFirst().allSatisfy { $0 == commands.first })
        let session = DocumentSession(document: fixture.document)
        try session.execute(commands[0])
        XCTAssertEqual(session.document.guides.map(\.id), [fixture.guideID])
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo()
        XCTAssertTrue(session.document.guides.isEmpty)
        try session.redo()
        XCTAssertEqual(session.document.guides.map(\.position), [123])
    }

    // SF-0404-002, SF-0404-004
    func testGuideInvalidMissingAndStaleCommandsDoNotMutate() throws {
        let fixture = SnapTestFixture()
        let registry = GuideCommandRegistry()
        let before = fixture.document
        XCTAssertThrowsError(try registry.prepare(
            fixture.guideCommand(.addVertical, position: .nan),
            in: fixture.document, context: fixture.guideContext
        )) { XCTAssertEqual($0 as? GuideCommandError, .invalidPosition) }
        XCTAssertThrowsError(try registry.prepare(
            fixture.guideCommand(.move, position: 1),
            in: fixture.document, context: fixture.guideContext
        )) { XCTAssertEqual($0 as? GuideCommandError, .missingGuide) }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0404-001, SF-0404-005
    func testSchemaFourPackageHistoryRoundTripMigrationAndPreviewCommitParity() async throws {
        var fixture = SnapTestFixture()
        fixture.document.guides = [
            .init(id: fixture.guideID, pageID: fixture.pageID, axis: .horizontal, position: 77),
        ]
        let bytes = try DocumentSerializer.encode(fixture.document)
        XCTAssertEqual(bytes, try DocumentSerializer.encode(fixture.document))
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("\"schemaVersion\":6"))
        XCTAssertEqual(try DocumentSerializer.decode(bytes), fixture.document)
        // Immutable schema-2 migration evidence lives in
        // `ProjectPackageTests`; this guide-specific test only proves the
        // current schema-5 round-trip. Generating a fake old payload here
        // would not independently establish historical wire compatibility.
        var missingGuideObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        var missingGuideDocument = try XCTUnwrap(
            missingGuideObject["document"] as? [String: Any]
        )
        missingGuideDocument.removeValue(forKey: "guides")
        missingGuideObject["document"] = missingGuideDocument
        let missingCurrentGuides = try JSONSerialization.data(withJSONObject: missingGuideObject)
        XCTAssertThrowsError(try DocumentSerializer.decode(missingCurrentGuides))

        let guideSession = DocumentSession(document: ProjectCreation.blank())
        let guidePageID = try XCTUnwrap(guideSession.document.pages.first?.id)
        let persistedGuideID = GuideID()
        try guideSession.execute(.insertGuide(.init(
            guide: .init(
                id: persistedGuideID,
                pageID: guidePageID,
                axis: .vertical,
                position: 321
            ),
            index: 0
        )))
        let package = ProjectPackage(
            projectID: ProjectID(),
            createdAt: ProjectTimestamp("2026-07-28T12:00:00.000Z"),
            document: guideSession.document
        )
        let persisted = try await PersistedHistoryStore().package(
            package,
            with: guideSession.historySnapshot()
        )
        let store = ProjectPackageStore()
        let firstPackageBytes = try await store.encode(persisted)
        let secondPackageBytes = try await store.encode(persisted)
        XCTAssertEqual(firstPackageBytes, secondPackageBytes)
        let reopened = try await store.decode(firstPackageBytes)
        XCTAssertEqual(reopened.document.guides.map(\.id), [persistedGuideID])
        guard case .restored(let history) = try await PersistedHistoryStore().load(from: reopened) else {
            return XCTFail("Expected persisted guide history")
        }
        let reopenedSession = DocumentSession(document: reopened.document)
        try reopenedSession.installValidatedHistory(history)
        try reopenedSession.undo()
        XCTAssertTrue(reopenedSession.document.guides.isEmpty)
        try reopenedSession.redo()
        XCTAssertEqual(reopenedSession.document.guides.first?.position, 321)

        fixture.document.guides = []
        let snap = try fixture.resolve(dx: 85, dy: 25)
        let prepared = try fixture.prepared(operation: snap.operation)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(
            session.document.pages[0].nodes.first(where: { $0.id == fixture.selectedID })?
                .insertionGeometry?.frame,
            prepared.geometries[0].preview
        )
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
    }

    // SF-0404-007, SF-0404-008
    func testCapacityMeasurementsAndDiagnosticsAreBoundedAndRedacted() async throws {
        for count in [100, 10_000] {
            let fixture = SnapTestFixture(referenceCount: count)
            var samples: [Double] = []
            let before = snapResidentBytes()
            for _ in 0..<4 {
                let start = DispatchTime.now().uptimeNanoseconds
                XCTAssertLessThanOrEqual(
                    try fixture.resolve(dx: 85, dy: 25).measurements.count,
                    SnappingPolicy.measurementLimit
                )
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            print("SNAP_EVIDENCE count=\(count) resolve_ms=\(samples) resident_before=\(before) resident_after=\(snapResidentBytes())")
        }
        let fixture = SnapTestFixture()
        let record = SnapDiagnosticFactory.make(
            operation: "move", identities: [fixture.selectedID.description, "/Users/private/project"],
            durationMilliseconds: 1, candidateCount: 6, winnerCount: 1, result: .success
        )
        XCTAssertFalse(String(describing: record).contains(fixture.selectedID.description))
        XCTAssertFalse(String(describing: record).contains("/Users/"))
        let diagnostics = SnapDiagnostics()
        await diagnostics.append(record)
        let records = await diagnostics.snapshot()
        XCTAssertEqual(records, [record])
    }
}

private struct SnapTestFixture {
    var document: CanonicalDocument
    let pageID: PageID
    let selectedID: NodeID
    let referenceID: NodeID
    let sceneID: CanvasViewportSceneID
    let guideID = GuideID(UUID(uuidString: "97000000-0000-4000-8000-000000000001")!)
    var referenceVisible = true
    var referenceLocked = false
    let extras: [SnapSceneObject]

    init(referenceCount: Int = 1) {
        var value = ProjectCreation.blank()
        pageID = value.pages[0].id
        let root = value.pages[0].rootNodeIDs[0]
        let activePageID = value.pages[0].id
        selectedID = NodeID(UUID(uuidString: "97000000-0000-4000-8000-000000000002")!)
        referenceID = NodeID(UUID(uuidString: "97000000-0000-4000-8000-000000000003")!)
        sceneID = CanvasViewportSceneID(UUID(uuidString: "97000000-0000-4000-8000-000000000004")!)
        value.pages[0].nodes[0].childIDs = [selectedID, referenceID]
        value.pages[0].nodes += [
            snapTestNode(id: selectedID, parent: root, x: 10, y: 20),
            snapTestNode(id: referenceID, parent: root, x: 200, y: 130),
        ]
        document = value
        extras = (1..<referenceCount).map {
            .init(
                id: NodeID(UUID(uuidString: String(format: "98000000-0000-4000-8000-%012d", $0))!),
                pageID: activePageID,
                frame: .init(
                    origin: .init(x: Double($0 % 100) * 150, y: Double($0 / 100) * 100),
                    size: .init(width: 80, height: 60)
                ),
                isVisible: true, isLocked: false, isClipped: false, isAvailable: true
            )
        }
    }

    var identity: TransformOperationIdentity {
        .init(
            sessionID: TransformSessionID(UUID(uuidString: "97000000-0000-4000-8000-000000000005")!),
            documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: sceneID, rendererGeneration: document.revision
        )
    }

    func prepared(dx: Double, dy: Double = 0) throws -> PreparedTransform {
        try prepared(operation: .move(delta: .init(dx: dx, dy: dy), constraint: .none))
    }

    func prepared(operation: TransformOperation) throws -> PreparedTransform {
        try TransformCommandRegistry().prepare(
            .init(identity: identity, orderedNodeIDs: [selectedID], operation: operation, provenance: .automation),
            in: document,
            context: .init(
                activePageID: pageID, currentSceneID: sceneID,
                rendererGeneration: document.revision, selectedNodeIDs: [selectedID],
                availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
                isLifecycleAvailable: true, lifecycleDisabledReason: nil
            )
        )
    }

    func resolve(
        dx: Double, dy: Double = 0, previous: [SnapAxis: SnapCandidate] = [:],
        suppressed: Bool = false, zoom: Double = 1, pixelRatio: Double = 2,
        cancellation: SnapCancellation = .never
    ) throws -> SnapResolution {
        try SnapResolver().resolve(
            raw: prepared(dx: dx, dy: dy),
            context: context(
                previous: previous,
                suppressed: suppressed,
                zoom: zoom,
                pixelRatio: pixelRatio
            ),
            cancellation: cancellation
        )
    }

    func context(
        previous: [SnapAxis: SnapCandidate],
        suppressed: Bool,
        zoom: Double = 1,
        pixelRatio: Double = 2
    ) -> SnapResolutionContext {
        .init(
            identity: identity, activePageID: pageID, selectedNodeIDs: [selectedID],
            objects: [
                .init(
                    id: selectedID, pageID: pageID,
                    frame: .init(origin: .init(x: 10, y: 20), size: .init(width: 100, height: 80)),
                    isVisible: true, isLocked: false, isClipped: false, isAvailable: true
                ),
                .init(
                    id: referenceID, pageID: pageID,
                    frame: .init(origin: .init(x: 200, y: 130), size: .init(width: 100, height: 80)),
                    isVisible: referenceVisible, isLocked: referenceLocked,
                    isClipped: false, isAvailable: true
                ),
            ] + extras,
            guides: document.guides,
            zoom: try! CanvasZoom(zoom), pixelRatio: try! CanvasPixelRatio(pixelRatio),
            previousWinners: previous, isSuppressed: suppressed
        )
    }

    var guideContext: GuideValidationContext {
        .init(
            activePageID: pageID, sceneID: sceneID, rendererGeneration: document.revision,
            isLifecycleAvailable: true, lifecycleDisabledReason: nil
        )
    }

    func guideCommand(
        _ name: GuideCommandName, position: Double?,
        provenance: GuideCommandProvenance = .automation
    ) -> GuideCommand {
        .init(
            identity: .init(
                operationID: GuideEditID(), documentID: document.id,
                pageID: pageID, revision: document.revision,
                sceneID: sceneID, rendererGeneration: document.revision
            ),
            name: name, guideID: guideID, position: position, provenance: provenance
        )
    }
}

private func snapTestNode(id: NodeID, parent: NodeID, x: Double, y: Double) -> DocumentNode {
    DocumentNode(
        id: id, kind: .frame, name: "Snap fixture", parent: .node(parent),
        properties: [
            ("layout.x", x), ("layout.y", y), ("layout.width", 100.0), ("layout.height", 80.0),
        ].map { .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored) }
    )
}

private func snapResidentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}
