import XCTest
@testable import SiteForge

final class DiagnosticSupportTests: XCTestCase {
    func testRingBufferEvictsOldestAndReportsMonotonicSequencesAndDrops() {
        var buffer = BoundedDiagnosticBuffer<String>(capacity: 3)

        XCTAssertEqual(buffer.append("zero"), 0)
        XCTAssertEqual(buffer.append("one"), 1)
        XCTAssertEqual(buffer.append("two"), 2)
        XCTAssertEqual(buffer.append("three"), 3)
        XCTAssertEqual(buffer.append("four"), 4)

        XCTAssertEqual(buffer.snapshot(), ["two", "three", "four"])
        XCTAssertEqual(buffer.sequencedSnapshot().map(\.sequence), [2, 3, 4])
        XCTAssertEqual(buffer.droppedRecordCount, 2)
    }

    func testStableIdentifierIsDomainSeparatedAndDoesNotLeakInput() {
        let privateValue = "00000000-0000-4000-8000-000000000099/private/path"
        let selection = DiagnosticStableIdentifier.sanitize(
            privateValue,
            domain: .selection,
            kind: "node"
        )
        let transform = DiagnosticStableIdentifier.sanitize(
            privateValue,
            domain: .transform,
            kind: "node"
        )

        XCTAssertNotEqual(selection, transform)
        XCTAssertFalse(selection.contains(privateValue))
        XCTAssertFalse(selection.contains("00000000"))
        XCTAssertFalse(selection.contains("private"))
        XCTAssertEqual(selection.count, "node-".count + 24)
    }

    func testUntypedErrorClassificationIsClosedAndDoesNotSerializeReason() {
        struct PrivateFailure: Error, CustomStringConvertible {
            var description: String { "private authored reason" }
        }

        XCTAssertEqual(DiagnosticErrorCategory.closedCategory(for: CancellationError()), .cancelled)
        let category = DiagnosticErrorCategory.closedCategory(for: PrivateFailure())
        XCTAssertEqual(category, .unknown)
        XCTAssertFalse(category.rawValue.contains("private authored reason"))
    }
}
