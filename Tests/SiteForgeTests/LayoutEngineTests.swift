import Foundation
import XCTest
@testable import SiteForge

final class LayoutEngineTests: XCTestCase {
    private let engine = DeterministicLayoutEngine()

    // SF-0501-001, SF-0501-003, SF-0501-008
    func testFixedIntrinsicFillPaddingGapAlignmentAndProvenance() throws {
        let fixture = LayoutFixtures.parity()
        let result = try engine.layout(fixture.request(width: 800, height: 400, revision: 7, generation: 3))
        let frames = result.fragmentsByID

        XCTAssertEqual(frames[fixture.root]?.frame, LayoutRect(
            origin: LayoutPoint(x: 0, y: 0), size: LayoutSize(width: 800, height: 400)
        ))
        XCTAssertEqual(frames[fixture.fixed]?.frame, LayoutRect(
            origin: LayoutPoint(x: 20, y: 175), size: LayoutSize(width: 100, height: 50)
        ))
        XCTAssertEqual(frames[fixture.intrinsic]?.frame, LayoutRect(
            origin: LayoutPoint(x: 130, y: 185), size: LayoutSize(width: 80, height: 30)
        ))
        XCTAssertEqual(frames[fixture.fill]?.frame, LayoutRect(
            origin: LayoutPoint(x: 220, y: 10), size: LayoutSize(width: 560, height: 380)
        ))
        XCTAssertEqual(frames[fixture.fixed]?.widthResolution.source, .fixed)
        XCTAssertEqual(frames[fixture.intrinsic]?.widthResolution.source, .intrinsic)
        XCTAssertEqual(frames[fixture.fill]?.widthResolution.source, .fill)
    }

    // SF-0501-003
    func testMinMaxConstraintsAndVerticalNestingAreDeterministic() throws {
        let fixture = LayoutFixtures.nested()
        let result = try engine.layout(fixture.request(width: 360, height: 300))
        let fragments = result.fragmentsByID

        XCTAssertEqual(fragments[fixture.nested]?.frame.size.width, 200)
        XCTAssertEqual(fragments[fixture.nested]?.widthResolution.constraint, .maximum)
        XCTAssertEqual(fragments[fixture.minimum]?.frame.size.height, 40)
        XCTAssertEqual(fragments[fixture.minimum]?.heightResolution.constraint, .minimum)
        XCTAssertEqual(fragments[fixture.trailing]?.frame.origin.y, 52)
        XCTAssertEqual(result.fragments.map(\.id), [fixture.root, fixture.nested, fixture.minimum, fixture.trailing])
    }

    // SF-0501-003, SF-0501-004
    func testOverflowClipIsExplicitAndVisibleOverflowIsNotMarkedClipped() throws {
        let clip = LayoutFixtures.overflow(.clip)
        let clipped = try engine.layout(clip.request(width: 100, height: 100))
        XCTAssertTrue(try XCTUnwrap(clipped.fragmentsByID[clip.child]).clippedByParent)

        let visible = LayoutFixtures.overflow(.visible)
        let unbounded = try engine.layout(visible.request(width: 100, height: 100))
        XCTAssertFalse(try XCTUnwrap(unbounded.fragmentsByID[visible.child]).clippedByParent)
    }

    // SF-0501-003, SF-0501-007
    func testResponsiveWidthsProduceStableFramesAndDigests() throws {
        let fixture = LayoutFixtures.parity()
        for width in [320.0, 768.0, 1_440.0] {
            let request = fixture.request(width: width, height: 400, revision: 9, generation: 2)
            let first = try engine.layout(request)
            for _ in 0..<20 {
                let repeated = try engine.layout(request)
                XCTAssertEqual(repeated, first)
                XCTAssertEqual(repeated.deterministicDigest, first.deterministicDigest)
            }
            XCTAssertEqual(first.identity.viewportWidth, width)
        }
        XCTAssertNotEqual(
            try engine.layout(fixture.request(width: 320, height: 400)).deterministicDigest,
            try engine.layout(fixture.request(width: 768, height: 400)).deterministicDigest
        )
    }

    // SF-0501-001, SF-0501-003
    func testVersionedSnapshotSerializationRoundTripPreservesStableIdentity() throws {
        let fixture = LayoutFixtures.parity()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let first = try encoder.encode(fixture.snapshot)
        let second = try encoder.encode(fixture.snapshot)
        XCTAssertEqual(first, second)
        let decoded = try JSONDecoder().decode(LayoutSnapshot.self, from: first)
        XCTAssertEqual(decoded, fixture.snapshot)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.nodes.map(\.id), fixture.snapshot.nodes.map(\.id))
    }

    // SF-0501-004, SF-0501-008
    func testInvalidNonfiniteImpossibleMissingAndUnsupportedInputsAreTyped() throws {
        let fixture = LayoutFixtures.parity()
        XCTAssertLayoutError(
            fixture.replacingRoot { root in
                LayoutNodeSnapshot(
                    id: root.id, axis: root.axis, width: root.width, height: root.height,
                    constraints: LayoutConstraints(minWidth: 20, maxWidth: 10), childIDs: root.childIDs
                )
            }.request(width: 800, height: 400),
            equals: .impossibleConstraints(fixture.root)
        )
        XCTAssertLayoutError(fixture.request(width: .nan, height: 400), category: .invalidInput)
        XCTAssertLayoutError(fixture.removingIntrinsicMeasurement().request(width: 800, height: 400), category: .invalidInput)
        XCTAssertLayoutError(fixture.replacingNode(fixture.fixed) { node in
            LayoutNodeSnapshot(id: node.id, width: .percentage(0.5), height: node.height)
        }.request(width: 800, height: 400), category: .unsupported)
        XCTAssertLayoutError(fixture.replacingNode(fixture.fixed) { node in
            LayoutNodeSnapshot(id: node.id, width: .automatic, height: node.height)
        }.request(width: 800, height: 400), category: .unsupported)
        XCTAssertLayoutError(fixture.replacingRoot { root in
            LayoutNodeSnapshot(
                id: root.id, axis: root.axis, width: root.width, height: root.height,
                padding: root.padding, gap: root.gap, alignment: .baseline,
                overflow: root.overflow, childIDs: root.childIDs
            )
        }.request(width: 800, height: 400), category: .unsupported)
        XCTAssertLayoutError(fixture.replacingRoot { root in
            LayoutNodeSnapshot(
                id: root.id, axis: nil, width: root.width, height: root.height,
                padding: root.padding, gap: root.gap, alignment: root.alignment,
                overflow: root.overflow, childIDs: root.childIDs
            )
        }.request(width: 800, height: 400), category: .unsupported)
        XCTAssertLayoutError(LayoutFixtures.request(
            root: fixture.snapshot.rootID,
            nodes: fixture.snapshot.nodes,
            catalog: fixture.snapshot.intrinsicCatalog,
            width: 800,
            height: 400,
            schemaVersion: 2
        ), equals: .unsupportedSchema(2))
        XCTAssertLayoutError(fixture.replacingRoot { root in
            LayoutNodeSnapshot(
                id: root.id, axis: root.axis, width: root.width, height: root.height,
                padding: root.padding, gap: root.gap, alignment: root.alignment,
                overflow: .scroll, childIDs: root.childIDs
            )
        }.request(width: 800, height: 400), category: .unsupported)
    }

    // SF-0501-004, SF-0501-007
    func testGraphValidationRejectsDuplicateMissingMultipleParentCycleOrphanDepthAndLimits() throws {
        let root = LayoutFixtures.id(1)
        let child = LayoutFixtures.id(2)
        let leaf = LayoutNodeSnapshot(id: child, width: .fixed(10), height: .fixed(10))
        func request(_ nodes: [LayoutNodeSnapshot], rootID: NodeID = root) -> LayoutRequest {
            LayoutFixtures.request(root: rootID, nodes: nodes, width: 100, height: 100)
        }

        XCTAssertLayoutError(request([leaf, leaf], rootID: child), equals: .duplicateNode(child))
        XCTAssertLayoutError(request([
            LayoutNodeSnapshot(id: root, axis: .vertical, width: .fill, height: .fill, childIDs: [child]),
        ]), equals: .missingNode(child))
        XCTAssertLayoutError(request([
            LayoutNodeSnapshot(id: root, axis: .vertical, width: .fill, height: .fill, childIDs: [child, child]), leaf,
        ]), equals: .duplicateChild(parent: root, child: child))

        let other = LayoutFixtures.id(3)
        XCTAssertLayoutError(request([
            LayoutNodeSnapshot(id: root, axis: .vertical, width: .fill, height: .fill, childIDs: [child, other]),
            LayoutNodeSnapshot(id: child, axis: .vertical, width: .fixed(10), height: .fixed(10), childIDs: [other]),
            LayoutNodeSnapshot(id: other, width: .fixed(1), height: .fixed(1)),
        ]), equals: .multipleParents(other))
        XCTAssertLayoutError(request([
            LayoutNodeSnapshot(id: root, axis: .vertical, width: .fill, height: .fill, childIDs: [child]),
            LayoutNodeSnapshot(id: child, axis: .vertical, width: .fixed(10), height: .fixed(10), childIDs: [root]),
        ]), category: .invalidGraph)
        XCTAssertLayoutError(request([
            LayoutNodeSnapshot(id: root, width: .fill, height: .fill), leaf,
        ]), equals: .orphan(child))

        var deep: [LayoutNodeSnapshot] = []
        for index in 0...LayoutPolicy.maximumDepth {
            let id = LayoutFixtures.id(index + 100)
            let children = index == LayoutPolicy.maximumDepth ? [] : [LayoutFixtures.id(index + 101)]
            deep.append(LayoutNodeSnapshot(
                id: id, axis: children.isEmpty ? nil : .vertical,
                width: .fixed(1), height: .fixed(1), childIDs: children
            ))
        }
        XCTAssertLayoutError(request(deep, rootID: deep[0].id), category: .invalidGraph)

        let tooMany = (0...LayoutPolicy.maximumNodeCount).map { index in
            LayoutNodeSnapshot(id: LayoutFixtures.id(index + 1_000), width: .fixed(1), height: .fixed(1))
        }
        XCTAssertLayoutError(request(tooMany, rootID: tooMany[0].id), category: .resourceLimit)
    }

    // SF-0501-004, SF-0501-007
    func testCancellationAndStaleResultsAreStateNeutral() throws {
        let fixture = LayoutFixtures.large(count: 10_000)
        let cancellationVisits = LayoutVisitRecorder()
        XCTAssertThrowsError(try engine.layout(
            fixture.request(width: 1_200, height: 800, revision: 4, generation: 8),
            cancellation: LayoutCancellation { visited in
                cancellationVisits.append(visited)
                return visited >= 128
            }
        )) { XCTAssertEqual($0 as? LayoutEngineError, .cancelled) }
        XCTAssertEqual(cancellationVisits.last, 128)

        let valid = try engine.layout(LayoutFixtures.large(count: 100).request(
            width: 1_200, height: 800, revision: 4, generation: 8
        ))
        XCTAssertNoThrow(try LayoutResultAdoptionGate().validate(valid, expected: valid.identity))
        let stale = LayoutRequestIdentity(
            documentID: valid.identity.documentID,
            revision: 5,
            generation: 9,
            viewportWidth: valid.identity.viewportWidth
        )
        XCTAssertThrowsError(try LayoutResultAdoptionGate().validate(valid, expected: stale)) {
            XCTAssertEqual($0 as? LayoutEngineError, .staleResult)
        }
        let staleGeneration = LayoutRequestIdentity(
            documentID: valid.identity.documentID,
            revision: valid.identity.revision,
            generation: valid.identity.generation + 1,
            viewportWidth: valid.identity.viewportWidth
        )
        XCTAssertThrowsError(try LayoutResultAdoptionGate().validate(valid, expected: staleGeneration)) {
            XCTAssertEqual($0 as? LayoutEngineError, .staleResult)
        }
    }

    // SF-0501-007, SF-0501-008
    @MainActor
    func testActorWorkerLeavesMainActorResponsive() async throws {
        let worker = LayoutEngineWorker()
        let request = LayoutFixtures.large(count: 10_000).request(width: 1_200, height: 800)
        let task = Task { try await worker.layout(request) }
        await Task.yield()
        XCTAssertTrue(Thread.isMainThread)
        let result = try await task.value
        XCTAssertEqual(result.fragments.count, 10_000)
    }

    // SF-0501-007, SF-0501-008
    func testStandardAndLargeFixturesAreDeterministicWithinBoundedLocalTiming() throws {
        let clock = ContinuousClock()
        for count in [100, 10_000] {
            let request = LayoutFixtures.large(count: count).request(width: 1_200, height: 800)
            let start = clock.now
            let first = try engine.layout(request)
            let duration = start.duration(to: clock.now)
            XCTAssertEqual(first.fragments.count, count)
            XCTAssertEqual(try engine.layout(request).deterministicDigest, first.deterministicDigest)
            XCTAssertLessThan(duration, .seconds(5), "Safety bound only; retained evidence records named-host timings")
        }
    }

    // SF-0501-008
    func testDiagnosticsUseSanitizedStableIdentityAndExcludeContent() throws {
        let fixture = LayoutFixtures.parity()
        let rawDocument = fixture.request(width: 800, height: 400).identity.documentID.description
        let rawNode = fixture.fixed.description
        let record = LayoutDiagnosticRecord.make(
            requirementID: "SF-0501-008",
            operation: .layout,
            documentID: fixture.request(width: 800, height: 400).identity.documentID,
            nodeIDs: [fixture.fixed],
            revision: 1,
            generation: 1,
            durationMilliseconds: 1.25,
            result: .success,
            failureCategory: nil
        )
        let data = try JSONEncoder().encode(record)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains(rawDocument))
        XCTAssertFalse(text.contains(rawNode))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertTrue(record.sanitizedDocumentID.hasPrefix("document-"))
    }

    private func XCTAssertLayoutError(
        _ request: LayoutRequest,
        equals expected: LayoutEngineError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try engine.layout(request), file: file, line: line) {
            XCTAssertEqual($0 as? LayoutEngineError, expected, file: file, line: line)
        }
    }

    private func XCTAssertLayoutError(
        _ request: LayoutRequest,
        category: LayoutFailureCategory,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try engine.layout(request), file: file, line: line) { error in
            XCTAssertEqual((error as? LayoutEngineError)?.failureCategory, category, file: file, line: line)
        }
    }
}

private final class LayoutVisitRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var last: Int? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }
}

private struct LayoutFixtures {
    let root: NodeID
    let fixed: NodeID
    let intrinsic: NodeID
    let fill: NodeID
    let nested: NodeID
    let minimum: NodeID
    let trailing: NodeID
    let child: NodeID
    let snapshot: LayoutSnapshot

    func request(
        width: Double,
        height: Double,
        revision: UInt64 = 1,
        generation: UInt64 = 1
    ) -> LayoutRequest {
        Self.request(
            root: snapshot.rootID,
            nodes: snapshot.nodes,
            catalog: snapshot.intrinsicCatalog,
            width: width,
            height: height,
            revision: revision,
            generation: generation,
            schemaVersion: snapshot.schemaVersion
        )
    }

    func replacingRoot(_ transform: (LayoutNodeSnapshot) -> LayoutNodeSnapshot) -> Self {
        replacingNode(root, transform)
    }

    func replacingNode(_ id: NodeID, _ transform: (LayoutNodeSnapshot) -> LayoutNodeSnapshot) -> Self {
        replacing(snapshot: LayoutSnapshot(
            schemaVersion: snapshot.schemaVersion,
            rootID: snapshot.rootID,
            nodes: snapshot.nodes.map { $0.id == id ? transform($0) : $0 },
            intrinsicCatalog: snapshot.intrinsicCatalog
        ))
    }

    func removingIntrinsicMeasurement() -> Self {
        replacing(snapshot: LayoutSnapshot(rootID: snapshot.rootID, nodes: snapshot.nodes))
    }

    private func replacing(snapshot: LayoutSnapshot) -> Self {
        Self(
            root: root, fixed: fixed, intrinsic: intrinsic, fill: fill,
            nested: nested, minimum: minimum, trailing: trailing, child: child,
            snapshot: snapshot
        )
    }

    static func parity() -> Self {
        let root = id(1), fixed = id(2), intrinsic = id(3), fill = id(4)
        let text = LayoutIntrinsicKey(rawValue: "text.system-17.en-US.headline")
        return Self(
            root: root, fixed: fixed, intrinsic: intrinsic, fill: fill,
            nested: id(90), minimum: id(91), trailing: id(92), child: id(93),
            snapshot: LayoutSnapshot(
                rootID: root,
                nodes: [
                    LayoutNodeSnapshot(
                        id: root, axis: .horizontal, width: .fill, height: .fill,
                        padding: LayoutInsets(top: 10, leading: 20, bottom: 10, trailing: 20),
                        gap: 10, alignment: .center, childIDs: [fixed, intrinsic, fill]
                    ),
                    LayoutNodeSnapshot(id: fixed, width: .fixed(100), height: .fixed(50)),
                    LayoutNodeSnapshot(
                        id: intrinsic, width: .intrinsic, height: .intrinsic, intrinsicKey: text
                    ),
                    LayoutNodeSnapshot(id: fill, width: .fill, height: .fill),
                ],
                intrinsicCatalog: LayoutIntrinsicCatalog(entries: [text: LayoutSize(width: 80, height: 30)])
            )
        )
    }

    static func nested() -> Self {
        let root = id(10), nested = id(11), minimum = id(12), trailing = id(13)
        return Self(
            root: root, fixed: id(94), intrinsic: id(95), fill: id(96),
            nested: nested, minimum: minimum, trailing: trailing, child: id(97),
            snapshot: LayoutSnapshot(rootID: root, nodes: [
                LayoutNodeSnapshot(
                    id: root, axis: .horizontal, width: .fill, height: .fill,
                    alignment: .start, childIDs: [nested]
                ),
                LayoutNodeSnapshot(
                    id: nested, axis: .vertical, width: .fixed(240), height: .fill,
                    constraints: LayoutConstraints(maxWidth: 200),
                    padding: LayoutInsets(all: 4), gap: 8, childIDs: [minimum, trailing]
                ),
                LayoutNodeSnapshot(
                    id: minimum, width: .fill, height: .fixed(20),
                    constraints: LayoutConstraints(minHeight: 40)
                ),
                LayoutNodeSnapshot(id: trailing, width: .fill, height: .fixed(30)),
            ])
        )
    }

    static func overflow(_ overflow: LayoutOverflow) -> Self {
        let root = id(20), child = id(21)
        return Self(
            root: root, fixed: id(98), intrinsic: id(99), fill: id(100),
            nested: id(101), minimum: id(102), trailing: id(103), child: child,
            snapshot: LayoutSnapshot(rootID: root, nodes: [
                LayoutNodeSnapshot(
                    id: root, axis: .horizontal, width: .fill, height: .fill,
                    overflow: overflow, childIDs: [child]
                ),
                LayoutNodeSnapshot(id: child, width: .fixed(160), height: .fixed(40)),
            ])
        )
    }

    static func large(count: Int) -> Self {
        precondition(count > 0)
        let root = id(30_000)
        let children = (1..<count).map { id(30_000 + $0) }
        let nodes = [LayoutNodeSnapshot(
            id: root, axis: .vertical, width: .fill, height: .fill,
            padding: LayoutInsets(all: 12), gap: 1, overflow: .clip, childIDs: children
        )] + children.enumerated().map { index, id in
            LayoutNodeSnapshot(
                id: id, width: .fill, height: .fixed(Double(8 + index % 24)),
                constraints: LayoutConstraints(minHeight: 8, maxHeight: 32)
            )
        }
        return Self(
            root: root, fixed: id(40_001), intrinsic: id(40_002), fill: id(40_003),
            nested: id(40_004), minimum: id(40_005), trailing: id(40_006), child: id(40_007),
            snapshot: LayoutSnapshot(rootID: root, nodes: nodes)
        )
    }

    static func request(
        root: NodeID,
        nodes: [LayoutNodeSnapshot],
        catalog: LayoutIntrinsicCatalog = LayoutIntrinsicCatalog(),
        width: Double,
        height: Double,
        revision: UInt64 = 1,
        generation: UInt64 = 1,
        schemaVersion: Int = 1
    ) -> LayoutRequest {
        LayoutRequest(
            identity: LayoutRequestIdentity(
                documentID: DocumentID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                revision: revision,
                generation: generation,
                viewportWidth: width
            ),
            snapshot: LayoutSnapshot(
                schemaVersion: schemaVersion,
                rootID: root,
                nodes: nodes,
                intrinsicCatalog: catalog
            ),
            containingBlock: LayoutSize(width: width, height: height)
        )
    }

    static func id(_ value: Int) -> NodeID {
        NodeID(uuidString: String(format: "20000000-0000-0000-0000-%012d", value))!
    }
}
