import XCTest
@testable import SiteForge

final class AuthoringEngineRunwayTests: XCTestCase {
    // SF-1901-001, SF-1901-003, SF-1901-008; evidence only, not production SF-0401 implementation.
    func testCoordinateRoundTripsZoomAnchorAndPanAreExactWithinTolerance() throws {
        let transform = try RunwayViewportTransform(
            zoom: 2.75,
            pan: RunwayPoint(x: 31.25, y: -17.5),
            backingScale: 2
        )
        let world = RunwayPoint(x: -91.125, y: 204.0625)
        let device = transform.viewToDevice(transform.worldToView(world))
        let recovered = transform.viewToWorld(transform.deviceToView(device))
        XCTAssertEqual(recovered.x, world.x, accuracy: 1e-12)
        XCTAssertEqual(recovered.y, world.y, accuracy: 1e-12)

        let cursor = RunwayPoint(x: 400.5, y: 250.25)
        let anchor = transform.viewToWorld(cursor)
        let zoomed = try transform.zoomed(to: 5.5, around: cursor)
        XCTAssertEqual(zoomed.worldToView(anchor).x, cursor.x, accuracy: 1e-12)
        XCTAssertEqual(zoomed.worldToView(anchor).y, cursor.y, accuracy: 1e-12)

        let panned = try transform.panned(by: RunwayPoint(x: 8, y: -3))
        XCTAssertEqual(panned.worldToView(world).x - transform.worldToView(world).x, 8, accuracy: 1e-12)
        XCTAssertEqual(panned.worldToView(world).y - transform.worldToView(world).y, -3, accuracy: 1e-12)
        XCTAssertThrowsError(try RunwayViewportTransform(
            zoom: 0, pan: RunwayPoint(x: 0, y: 0), backingScale: 2
        ))
    }

    // SF-1901-001, SF-1901-003, SF-1901-007, SF-1901-008; downstream SF-0501 evidence.
    func testTypedLayoutSubsetIsDeterministicResponsiveAndNested() throws {
        let engine = RunwayLayoutEngine()
        let root = RunwayFixtures.parityLayout()
        let wide = try engine.layout(root: root, viewport: RunwaySize(width: 800, height: 360), revision: 4)
        XCTAssertEqual(wide.frames.count, 6)
        XCTAssertEqual(wide.frames[RunwayStableID("fixed")]?.origin.x, 20)
        XCTAssertEqual(wide.frames[RunwayStableID("fixed")]?.origin.y, 144)
        XCTAssertEqual(wide.frames[RunwayStableID("nested")]?.size.width, 480)
        XCTAssertEqual(wide.frames[RunwayStableID("nested-fixed")]?.origin.y, 128)

        let repeatWide = try engine.layout(root: root, viewport: RunwaySize(width: 800, height: 360), revision: 4)
        XCTAssertEqual(wide, repeatWide)
        XCTAssertEqual(wide.deterministicDigest(), repeatWide.deterministicDigest())

        let narrow = try engine.layout(root: root, viewport: RunwaySize(width: 320, height: 360), revision: 5)
        XCTAssertEqual(narrow.frames[RunwayStableID("nested")]?.size.width, 120)
        XCTAssertNotEqual(wide.deterministicDigest(), narrow.deterministicDigest())
    }

    // SF-1901-004, SF-1901-007, SF-1901-008.
    func testLargeLayoutCancellationAndStaleResultAreStateNeutral() throws {
        let fixture = RunwayFixtures.largeLayout(nodeCount: 10_000)
        let engine = RunwayLayoutEngine()
        XCTAssertThrowsError(try engine.layout(
            root: fixture,
            viewport: RunwaySize(width: 1_200, height: 800),
            revision: 11,
            cancellation: { $0 >= 128 }
        )) { XCTAssertEqual($0 as? RunwayError, .cancelled) }

        let valid = try engine.layout(
            root: RunwayFixtures.largeLayout(nodeCount: 100),
            viewport: RunwaySize(width: 1_200, height: 800),
            revision: 10
        )
        let result = RunwayVersionedResult(revision: 10, value: valid)
        XCTAssertNil(result.value(ifCurrent: 11))
        XCTAssertEqual(result.value(ifCurrent: 10), valid)
    }

    // SF-1901-003, SF-1901-004, SF-1901-008.
    func testInvalidLayoutInputIsRejectedAndHTMLExportRemainsAnAdapter() throws {
        var invalid = RunwayFixtures.parityLayout()
        invalid.gap = -1
        XCTAssertThrowsError(try RunwayLayoutEngine().layout(
            root: invalid, viewport: RunwaySize(width: 800, height: 360), revision: 1
        )) { XCTAssertEqual($0 as? RunwayError, .invalidConstraints) }

        var unsupported = RunwayFixtures.parityLayout()
        unsupported.axis = nil
        XCTAssertThrowsError(try RunwayLayoutEngine().layout(
            root: unsupported, viewport: RunwaySize(width: 800, height: 360), revision: 1
        )) { XCTAssertEqual($0 as? RunwayError, .unsupportedLayout) }

        let html = try RunwayHTMLExport().document(
            root: RunwayFixtures.parityLayout(), viewport: RunwaySize(width: 800, height: 360)
        )
        XCTAssertTrue(html.contains("data-runway-id=\"root\""))
        XCTAssertTrue(html.contains("display:flex"))
        XCTAssertFalse(html.contains("webkit"))
        XCTAssertFalse(html.contains("contenteditable"))
    }

    // SF-1901-003, SF-1901-006, SF-1901-007; downstream SF-0407 evidence.
    func testHitTestingUsesStableIdentityAndRemainsSeparateFromOverlays() throws {
        let objects = RunwayFixtures.canvasObjects(count: 10_000)
        let index = RunwayHitIndex(objects: objects)
        let target = try XCTUnwrap(objects.dropFirst(5_000).first)
        XCTAssertEqual(index.hitTest(RunwayPoint(
            x: target.bounds.origin.x + 1,
            y: target.bounds.origin.y + 1
        )), target.id)
        XCTAssertNil(index.hitTest(RunwayPoint(x: -10_000, y: -10_000)))

        let overlay = RunwayOverlay(target: target.id, bounds: target.bounds)
        XCTAssertEqual(overlay.target, target.id)
        XCTAssertEqual(objects.count, 10_000)
    }
}
