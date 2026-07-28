import CryptoKit
import Foundation

// SF-0404-001...008 — deterministic snapping, authored guides, rulers, and measurement.

enum GuideEditIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "guide-edit"
}
typealias GuideEditID = StableIdentifier<GuideEditIdentifierDomain>

enum SnapAxis: String, CaseIterable, Sendable {
    case horizontal
    case vertical
}

enum SnapFeature: String, CaseIterable, Sendable {
    case minimum
    case center
    case maximum
    case authoredGuide

    var stableOrder: Int {
        switch self {
        case .minimum: 0
        case .center: 1
        case .maximum: 2
        case .authoredGuide: 3
        }
    }
}

enum SnapSourceIdentity: Hashable, Sendable {
    case object(NodeID)
    case guide(GuideID)

    var stableDescription: String {
        switch self {
        case .object(let id): "object-\(id.description)"
        case .guide(let id): "guide-\(id.description)"
        }
    }
}

enum SnapCandidateKind: Int, Sendable {
    case authoredGuide = 0
    case objectEdge = 1
    case objectCenter = 2
}

struct SnapCandidateID: Hashable, Sendable {
    let axis: SnapAxis
    let source: SnapSourceIdentity
    let sourceFeature: SnapFeature
    let movingFeature: SnapFeature
}

struct SnapCandidate: Equatable, Sendable {
    let id: SnapCandidateID
    let kind: SnapCandidateKind
    let targetPosition: Double
    let correction: Double
    let distanceInPoints: Double
    let explanation: String
}

struct SnapSceneObject: Equatable, Sendable {
    let id: NodeID
    let pageID: PageID
    let frame: WorldRect
    let isVisible: Bool
    let isLocked: Bool
    let isClipped: Bool
    let isAvailable: Bool
}

struct SmartGuideLine: Equatable, Sendable {
    let id: SnapCandidateID
    let axis: SnapAxis
    let position: Double
    let explanation: String
}

struct DistanceMeasurement: Equatable, Sendable {
    let axis: SnapAxis
    let start: Double
    let end: Double
    let crossPosition: Double
    let points: Double
}

struct SnapResolution: Equatable, Sendable {
    let operation: TransformOperation
    let candidateCount: Int
    let winners: [SnapAxis: SnapCandidate]
    let smartGuides: [SmartGuideLine]
    let measurements: [DistanceMeasurement]
    let dirtyWorldRegions: [WorldRect]
}

struct SnapResolutionContext: Sendable {
    let identity: TransformOperationIdentity
    let activePageID: PageID
    let selectedNodeIDs: [NodeID]
    let objects: [SnapSceneObject]
    let guides: [AuthoredGuide]
    let zoom: CanvasZoom
    let pixelRatio: CanvasPixelRatio
    let previousWinners: [SnapAxis: SnapCandidate]
    let isSuppressed: Bool
}

struct SnapCancellation: Sendable {
    let isCancelled: @Sendable (Int) -> Bool
    static let never = Self(isCancelled: { _ in false })
}

enum SnapError: Error, Equatable, LocalizedError, Sendable {
    case staleTransform
    case invalidGeometry
    case duplicateSource
    case objectLimitExceeded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .staleTransform: "A newer transform session superseded this snap result."
        case .invalidGeometry: "Snapping requires finite transform and reference geometry."
        case .duplicateSource: "Snap reference identities must be unique."
        case .objectLimitExceeded: "The active page exceeds the bounded snap-reference limit."
        case .cancelled: "Snapping was cancelled; committed geometry is unchanged."
        }
    }
}

enum SnappingPolicy {
    static let entryThresholdPoints = 6.0
    static let exitThresholdPoints = 9.0
    static let maximumReferenceObjects = 20_000
    static let cancellationStride = 64
    static let measurementLimit = 4
    static let rulerThicknessPoints = 20.0
    static let rulerMinimumTickSpacingPoints = 8.0
}

struct SnapResolver: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0404-001", "SF-0404-002", "SF-0404-003", "SF-0404-004",
        "SF-0404-005", "SF-0404-006", "SF-0404-007", "SF-0404-008",
    ]

    func resolve(
        raw: PreparedTransform,
        context: SnapResolutionContext,
        cancellation: SnapCancellation = .never
    ) throws -> SnapResolution {
        guard raw.identity == context.identity else { throw SnapError.staleTransform }
        guard raw.geometries.allSatisfy({
            $0.original.isValid && $0.preview.isValid
        }) else { throw SnapError.invalidGeometry }
        guard context.objects.count <= SnappingPolicy.maximumReferenceObjects else {
            throw SnapError.objectLimitExceeded
        }
        guard Set(context.objects.map(\.id)).count == context.objects.count else {
            throw SnapError.duplicateSource
        }
        guard !cancellation.isCancelled(0) else { throw SnapError.cancelled }
        guard !context.isSuppressed else {
            return SnapResolution(
                operation: raw.operation,
                candidateCount: 0,
                winners: [:],
                smartGuides: [],
                measurements: measurements(
                    moving: boundingFrame(raw.geometries.map(\.preview)),
                    references: eligibleReferences(context),
                    zoom: context.zoom
                ),
                dirtyWorldRegions: raw.geometries.flatMap { [$0.original, $0.preview] }
            )
        }

        let movingFrame = boundingFrame(raw.geometries.map(\.preview))
        let movingFeatures = applicableMovingFeatures(raw.operation, frame: movingFrame)
        let references = eligibleReferences(context)
        var candidates: [SnapCandidate] = []
        // Only candidates inside the hysteresis envelope can ever win. Avoid
        // allocating and sorting the otherwise O(objects × features) set.
        candidates.reserveCapacity(min((references.count * 2) + context.guides.count, 4_096))

        for (index, object) in references.enumerated() {
            if index.isMultiple(of: SnappingPolicy.cancellationStride),
               cancellation.isCancelled(index) {
                throw SnapError.cancelled
            }
            for axis in SnapAxis.allCases {
                guard let moving = movingFeatures[axis] else { continue }
                for sourceFeature in [SnapFeature.minimum, .center, .maximum] {
                    let target = position(sourceFeature, axis: axis, frame: object.frame)
                    for movingFeature in moving {
                        let movingPosition = position(movingFeature, axis: axis, frame: movingFrame)
                        let correction = target - movingPosition
                        let distance = abs(correction) * context.zoom.value
                        guard distance <= SnappingPolicy.exitThresholdPoints else { continue }
                        let kind: SnapCandidateKind = sourceFeature == .center
                            ? .objectCenter : .objectEdge
                        candidates.append(SnapCandidate(
                            id: SnapCandidateID(
                                axis: axis,
                                source: .object(object.id),
                                sourceFeature: sourceFeature,
                                movingFeature: movingFeature
                            ),
                            kind: kind,
                            targetPosition: target,
                            correction: correction,
                            distanceInPoints: distance,
                            explanation: "\(movingFeature.rawValue.capitalized) aligned to \(sourceFeature.rawValue) of object"
                        ))
                    }
                }
            }
        }

        for guide in context.guides where guide.pageID == context.activePageID {
            let axis: SnapAxis = guide.axis == .vertical ? .horizontal : .vertical
            guard let moving = movingFeatures[axis] else { continue }
            for movingFeature in moving {
                let correction = guide.position
                    - position(movingFeature, axis: axis, frame: movingFrame)
                let distance = abs(correction) * context.zoom.value
                guard distance <= SnappingPolicy.exitThresholdPoints else { continue }
                candidates.append(SnapCandidate(
                    id: SnapCandidateID(
                        axis: axis,
                        source: .guide(guide.id),
                        sourceFeature: .authoredGuide,
                        movingFeature: movingFeature
                    ),
                    kind: .authoredGuide,
                    targetPosition: guide.position,
                    correction: correction,
                    distanceInPoints: distance,
                    explanation: "\(movingFeature.rawValue.capitalized) aligned to authored \(guide.axis.rawValue) guide"
                ))
            }
        }
        guard !cancellation.isCancelled(context.objects.count) else {
            throw SnapError.cancelled
        }

        var winners: [SnapAxis: SnapCandidate] = [:]
        for axis in SnapAxis.allCases {
            let axisCandidates = candidates.filter { $0.id.axis == axis }
            if let retained = context.previousWinners[axis],
               let current = axisCandidates.first(where: { $0.id == retained.id }),
               current.distanceInPoints <= SnappingPolicy.exitThresholdPoints {
                winners[axis] = current
                continue
            }
            winners[axis] = axisCandidates
                .filter { $0.distanceInPoints <= SnappingPolicy.entryThresholdPoints }
                .sorted(by: candidatePrecedes)
                .first
        }

        let correction = WorldVector(
            dx: winners[.horizontal]?.correction ?? 0,
            dy: winners[.vertical]?.correction ?? 0
        )
        let operation = applying(correction, to: raw.operation)
        let snappedFrames = try raw.geometries.map {
            try TransformCommandRegistry.resolve($0.original, operation: operation)
        }
        let smartGuides = SnapAxis.allCases.compactMap { axis -> SmartGuideLine? in
            guard let winner = winners[axis] else { return nil }
            return SmartGuideLine(
                id: winner.id,
                axis: axis,
                position: winner.targetPosition,
                explanation: winner.explanation
            )
        }
        return SnapResolution(
            operation: operation,
            candidateCount: candidates.count,
            winners: winners,
            smartGuides: smartGuides,
            measurements: measurements(
                moving: boundingFrame(snappedFrames),
                references: references,
                zoom: context.zoom
            ),
            dirtyWorldRegions: unique(raw.geometries.flatMap { [$0.original, $0.preview] } + snappedFrames)
        )
    }

    private func eligibleReferences(_ context: SnapResolutionContext) -> [SnapSceneObject] {
        let selected = Set(context.selectedNodeIDs)
        return context.objects.filter {
            $0.pageID == context.activePageID
                && !selected.contains($0.id)
                && $0.isVisible
                && !$0.isClipped
                && $0.isAvailable
                && $0.frame.isValid
            // Locked objects are immutable but remain stable alignment references.
        }.sorted { $0.id.description < $1.id.description }
    }

    private func applicableMovingFeatures(
        _ operation: TransformOperation,
        frame: WorldRect
    ) -> [SnapAxis: [SnapFeature]] {
        switch operation {
        case .move:
            return [
                .horizontal: [.minimum, .center, .maximum],
                .vertical: [.minimum, .center, .maximum],
            ]
        case .resize(let handle, _, _):
            var result: [SnapAxis: [SnapFeature]] = [:]
            if [.topLeft, .left, .bottomLeft].contains(handle) {
                result[.horizontal] = [.minimum]
            } else if [.topRight, .right, .bottomRight].contains(handle) {
                result[.horizontal] = [.maximum]
            }
            if [.topLeft, .top, .topRight].contains(handle) {
                result[.vertical] = [.minimum]
            } else if [.bottomLeft, .bottom, .bottomRight].contains(handle) {
                result[.vertical] = [.maximum]
            }
            _ = frame
            return result
        }
    }

    private func position(_ feature: SnapFeature, axis: SnapAxis, frame: WorldRect) -> Double {
        switch (axis, feature) {
        case (.horizontal, .minimum): frame.minX
        case (.horizontal, .center): (frame.minX + frame.maxX) / 2
        case (.horizontal, .maximum): frame.maxX
        case (.vertical, .minimum): frame.minY
        case (.vertical, .center): (frame.minY + frame.maxY) / 2
        case (.vertical, .maximum): frame.maxY
        case (_, .authoredGuide): 0
        }
    }

    private func candidatePrecedes(_ lhs: SnapCandidate, _ rhs: SnapCandidate) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.distanceInPoints != rhs.distanceInPoints {
            return lhs.distanceInPoints < rhs.distanceInPoints
        }
        if lhs.id.source.stableDescription != rhs.id.source.stableDescription {
            return lhs.id.source.stableDescription < rhs.id.source.stableDescription
        }
        if lhs.id.sourceFeature.stableOrder != rhs.id.sourceFeature.stableOrder {
            return lhs.id.sourceFeature.stableOrder < rhs.id.sourceFeature.stableOrder
        }
        return lhs.id.movingFeature.stableOrder < rhs.id.movingFeature.stableOrder
    }

    private func applying(_ correction: WorldVector, to operation: TransformOperation) -> TransformOperation {
        switch operation {
        case .move(let delta, let constraint):
            return .move(
                delta: WorldVector(dx: delta.dx + correction.dx, dy: delta.dy + correction.dy),
                constraint: constraint
            )
        case .resize(let handle, let delta, let constraint):
            return .resize(
                handle: handle,
                delta: WorldVector(dx: delta.dx + correction.dx, dy: delta.dy + correction.dy),
                constraint: constraint
            )
        }
    }

    private func boundingFrame(_ frames: [WorldRect]) -> WorldRect {
        guard let first = frames.first else {
            return WorldRect(origin: .init(x: 0, y: 0), size: .init(width: 0, height: 0))
        }
        let minX = frames.dropFirst().reduce(first.minX) { min($0, $1.minX) }
        let minY = frames.dropFirst().reduce(first.minY) { min($0, $1.minY) }
        let maxX = frames.dropFirst().reduce(first.maxX) { max($0, $1.maxX) }
        let maxY = frames.dropFirst().reduce(first.maxY) { max($0, $1.maxY) }
        return WorldRect(
            origin: .init(x: minX, y: minY),
            size: .init(width: maxX - minX, height: maxY - minY)
        )
    }

    private func measurements(
        moving: WorldRect,
        references: [SnapSceneObject],
        zoom: CanvasZoom
    ) -> [DistanceMeasurement] {
        var values: [DistanceMeasurement] = []
        values.reserveCapacity(SnappingPolicy.measurementLimit + 1)
        for reference in references {
            if reference.frame.maxX <= moving.minX {
                retainNearest(.init(
                    axis: .horizontal, start: reference.frame.maxX, end: moving.minX,
                    crossPosition: max(reference.frame.minY, moving.minY),
                    points: (moving.minX - reference.frame.maxX) * zoom.value
                ), in: &values)
            } else if reference.frame.minX >= moving.maxX {
                retainNearest(.init(
                    axis: .horizontal, start: moving.maxX, end: reference.frame.minX,
                    crossPosition: max(reference.frame.minY, moving.minY),
                    points: (reference.frame.minX - moving.maxX) * zoom.value
                ), in: &values)
            }
            if reference.frame.maxY <= moving.minY {
                retainNearest(.init(
                    axis: .vertical, start: reference.frame.maxY, end: moving.minY,
                    crossPosition: max(reference.frame.minX, moving.minX),
                    points: (moving.minY - reference.frame.maxY) * zoom.value
                ), in: &values)
            } else if reference.frame.minY >= moving.maxY {
                retainNearest(.init(
                    axis: .vertical, start: moving.maxY, end: reference.frame.minY,
                    crossPosition: max(reference.frame.minX, moving.minX),
                    points: (reference.frame.minY - moving.maxY) * zoom.value
                ), in: &values)
            }
        }
        return values.sorted(by: measurementPrecedes)
    }

    private func retainNearest(
        _ measurement: DistanceMeasurement,
        in values: inout [DistanceMeasurement]
    ) {
        guard measurement.points.isFinite, measurement.points >= 0 else { return }
        values.append(measurement)
        if values.count > SnappingPolicy.measurementLimit,
           let leastUseful = values.indices.max(by: {
               measurementPrecedes(values[$0], values[$1])
           }) {
            values.remove(at: leastUseful)
        }
    }

    private func measurementPrecedes(
        _ lhs: DistanceMeasurement,
        _ rhs: DistanceMeasurement
    ) -> Bool {
        lhs.points == rhs.points
            ? (lhs.axis.rawValue, lhs.start, lhs.end) < (rhs.axis.rawValue, rhs.start, rhs.end)
            : lhs.points < rhs.points
    }

    private func unique(_ regions: [WorldRect]) -> [WorldRect] {
        var seen = Set<WorldRect>()
        return regions.filter { seen.insert($0).inserted }
    }
}

enum GuideCommandName: String, CaseIterable, Sendable {
    case addHorizontal, addVertical, move, remove
}

enum GuideCommandProvenance: String, CaseIterable, Sendable {
    case pointer, keyboard, menu, contextualMenu, accessibility, automation
}

struct GuideOperationIdentity: Equatable, Sendable {
    let operationID: GuideEditID
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
}

struct GuideCommand: Equatable, Sendable {
    let identity: GuideOperationIdentity
    let name: GuideCommandName
    let guideID: GuideID
    let position: Double?
    let provenance: GuideCommandProvenance
}

enum GuideCommandError: Error, Equatable, LocalizedError, Sendable {
    case staleDocument, stalePage, staleRevision, staleRenderer
    case duplicateGuide, missingGuide, invalidPosition, revisionExhausted
    case lifecycleUnavailable(String), cancelled

    var errorDescription: String? {
        switch self {
        case .staleDocument: "A different document now owns this guide operation."
        case .stalePage: "A different page now owns this guide operation."
        case .staleRevision: "The document changed before the guide operation could commit."
        case .staleRenderer: "A newer rendered scene superseded this guide operation."
        case .duplicateGuide: "A guide with this stable identity already exists."
        case .missingGuide: "The authored guide no longer exists."
        case .invalidPosition: "Guide positions must be finite and within the supported canvas range."
        case .revisionExhausted: "The document revision cannot accept another guide transaction."
        case .lifecycleUnavailable(let reason): reason
        case .cancelled: "The guide operation was cancelled; committed guides are unchanged."
        }
    }
}

struct GuideValidationContext: Sendable {
    let activePageID: PageID
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let isLifecycleAvailable: Bool
    let lifecycleDisabledReason: String?
}

struct PreparedGuideCommand: Equatable, Sendable {
    let command: GuideCommand
    let documentCommand: DocumentCommand
}

struct GuideCommandRegistry: Sendable {
    static let requirementIDs = SnapResolver.requirementIDs

    func prepare(
        _ command: GuideCommand,
        in document: CanonicalDocument,
        context: GuideValidationContext
    ) throws -> PreparedGuideCommand {
        guard context.isLifecycleAvailable else {
            throw GuideCommandError.lifecycleUnavailable(
                context.lifecycleDisabledReason ?? "Guides are unavailable during the current document operation."
            )
        }
        guard command.identity.documentID == document.id else {
            throw GuideCommandError.staleDocument
        }
        guard command.identity.pageID == context.activePageID,
              document.pages.contains(where: { $0.id == context.activePageID }) else {
            throw GuideCommandError.stalePage
        }
        guard command.identity.revision == document.revision else {
            throw GuideCommandError.staleRevision
        }
        guard command.identity.sceneID == context.sceneID,
              command.identity.rendererGeneration == context.rendererGeneration else {
            throw GuideCommandError.staleRenderer
        }
        guard document.revision < UInt64.max - 1 else {
            throw GuideCommandError.revisionExhausted
        }
        let documentCommand: DocumentCommand
        switch command.name {
        case .addHorizontal, .addVertical:
            guard !document.guides.contains(where: { $0.id == command.guideID }) else {
                throw GuideCommandError.duplicateGuide
            }
            let position = try validated(command.position)
            let axis: GuideAxis = command.name == .addHorizontal ? .horizontal : .vertical
            documentCommand = .insertGuide(InsertGuideCommand(
                guide: AuthoredGuide(
                    id: command.guideID,
                    pageID: command.identity.pageID,
                    axis: axis,
                    position: position
                ),
                index: document.guides.count
            ))
        case .move:
            guard let guide = document.guides.first(where: { $0.id == command.guideID }),
                  guide.pageID == command.identity.pageID else {
                throw GuideCommandError.missingGuide
            }
            documentCommand = .setGuidePosition(SetGuidePositionCommand(
                guideID: guide.id,
                position: try validated(command.position)
            ))
        case .remove:
            guard document.guides.contains(where: {
                $0.id == command.guideID && $0.pageID == command.identity.pageID
            }) else {
                throw GuideCommandError.missingGuide
            }
            documentCommand = .removeGuide(RemoveGuideCommand(guideID: command.guideID))
        }
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw GuideCommandError.invalidPosition
        }
        return PreparedGuideCommand(command: command, documentCommand: documentCommand)
    }

    private func validated(_ position: Double?) throws -> Double {
        guard let position, position.isFinite,
              abs(position) <= AuthoredGuide.maximumCoordinate else {
            throw GuideCommandError.invalidPosition
        }
        return position
    }
}

struct GuidePreview: Equatable, Sendable {
    let identity: GuideOperationIdentity
    let guideID: GuideID
    let axis: GuideAxis
    let position: Double
}

enum GuideEditingPhase: Equatable, Sendable {
    case inactive
    case drafting(GuideOperationIdentity)
    case previewing(GuidePreview)
    case committing(GuidePreview)
    case cancelled
    case failed(GuideCommandError)
}

struct GuideEditingSession: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var phase: GuideEditingPhase = .inactive

    mutating func begin(identity: GuideOperationIdentity) {
        generation &+= 1
        phase = .drafting(identity)
    }

    mutating func preview(_ preview: GuidePreview) {
        guard currentIdentity == preview.identity else { return }
        phase = .previewing(preview)
    }

    mutating func beginCommit(_ preview: GuidePreview) {
        guard currentIdentity == preview.identity else { return }
        phase = .committing(preview)
    }

    mutating func complete() { phase = .inactive }
    mutating func cancel() { generation &+= 1; phase = .cancelled }
    mutating func deactivate() { generation &+= 1; phase = .inactive }
    mutating func fail(_ error: GuideCommandError) { phase = .failed(error) }

    var currentIdentity: GuideOperationIdentity? {
        switch phase {
        case .drafting(let value): value
        case .previewing(let value), .committing(let value): value.identity
        case .inactive, .cancelled, .failed: nil
        }
    }
}

enum SnapDiagnosticResult: String, Sendable {
    case success, failure, cancelled, stale, suppressed
}

struct SnapDiagnosticRecord: Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let candidateCount: Int
    let winnerCount: Int
    let result: SnapDiagnosticResult
    let failureCategory: String?
}

actor SnapDiagnostics {
    private var records: [SnapDiagnosticRecord] = []
    func append(_ value: SnapDiagnosticRecord) { records.append(value) }
    func snapshot() -> [SnapDiagnosticRecord] { records }
}

enum SnapDiagnosticFactory {
    static func make(
        operation: String,
        identities: [String],
        durationMilliseconds: Double,
        candidateCount: Int,
        winnerCount: Int,
        result: SnapDiagnosticResult,
        failureCategory: String? = nil
    ) -> SnapDiagnosticRecord {
        SnapDiagnosticRecord(
            requirementIDs: SnapResolver.requirementIDs.sorted(),
            operationType: operation,
            sanitizedIdentifiers: identities.map(sanitize),
            durationMilliseconds: max(0, durationMilliseconds),
            candidateCount: max(0, candidateCount),
            winnerCount: max(0, winnerCount),
            result: result,
            failureCategory: failureCategory
        )
    }

    private static func sanitize(_ value: String) -> String {
        SHA256.hash(data: Data(("snap:" + value).utf8)).prefix(6)
            .map { String(format: "%02x", $0) }.joined()
    }
}
