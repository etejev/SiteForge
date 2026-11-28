import Darwin
import AppKit
import Combine
import XCTest
@testable import SiteForge

@MainActor
final class TransformModelTests: XCTestCase {
    // SF-0508-001/002/004/005/008, SF-1101-001/004/005: closed configuration,
    // normal command history and strict backward-compatible envelope policy.
    func testDecorativeEffectsTypedValidationHistoryAndHistoricalSchema() throws {
        var fixture = try formattingFixture()
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        fixture.document.pages[0].nodes[index].properties.removeAll { $0.key.rawValue.hasPrefix("style.fill.layers.") }
        let gradient = CanonicalFillLayer.linearGradient(angleDegrees: 35, stops: [
            .init(id: .init(), position: 0, color: .init(red: 1, green: 0, blue: 0, alpha: 1)),
            .init(id: .init(), position: 1, color: .init(red: 0, green: 0, blue: 1, alpha: 0.4))])
        fixture.document.pages[0].nodes[index].properties += CanonicalFillLayerCodec.propertyValues(for: [gradient]).map {
            .init(key: .init(rawValue: $0.key), value: $0.value) }
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, revision: UInt64? = nil) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: revision ?? document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: [fixture.frame], document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: [fixture.frame], availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        let before = session.document.pages
        try session.execute(prepare(.flow(.defaults)).documentCommand)
        let after = session.document.pages
        XCTAssertEqual(try CanonicalFlowGradient.resolve(session.document.pages[0].nodes[index]), .defaults)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, after)
        let propertyIDs = session.document.pages[0].nodes[index].properties.filter { $0.key.rawValue.hasPrefix(CanonicalFlowGradient.namespace) }.map(\.id)
        var changed = CanonicalFlowGradient.defaults; changed.radius = 360
        try session.execute(prepare(.flow(changed)).documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[index].properties.filter { $0.key.rawValue.hasPrefix(CanonicalFlowGradient.namespace) }.map(\.id), propertyIDs)
        XCTAssertThrowsError(try prepare(.flow(.defaults), revision: 0))
        for invalid in [Double.nan, .infinity, -1, 1_201] {
            var bad = changed; bad.radius = invalid
            XCTAssertThrowsError(try prepare(.flow(bad)))
        }
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old["schemaVersion"] = 20
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: old)))
        var unknown = session.document
        unknown.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: "style.flow.v2.radius"), value: .number(240)))
        XCTAssertThrowsError(try unknown.validate())
        var wrong = session.document.pages[0].nodes[index]; wrong.kind = .text
        XCTAssertThrowsError(try CanonicalFlowGradient.resolve(wrong))
        try session.execute(prepare(.flow(nil)).documentCommand)
        XCTAssertNil(try CanonicalFlowGradient.resolve(session.document.pages[0].nodes[index]))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(fixture.document)) as? [String: Any])
        legacy["schemaVersion"] = 20
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)).pages, fixture.document.pages)
    }

    func testDecorativeEffectsOutputRetainsStaticFallbackAndReportsUnsupportedIntent() throws {
        var fixture = try formattingFixture()
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        fixture.document.pages[0].nodes[index].properties += CanonicalFlowGradient.defaults.properties.map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        // Multiple enabled layers are retained as authored, with an actionable
        // build finding rather than silently exporting an unrelated effect.
        let invalid = StaticBuildCompiler.compile(document: fixture.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertFalse(invalid.canWrite)
        XCTAssertTrue(invalid.findings.contains { $0.code == "flow-configuration-unavailable" })
        let gradient = try XCTUnwrap(DesignInspectorCommandRegistry.resolvedLayers(for: fixture.document.pages[0].nodes[index]).last)
        fixture.document.pages[0].nodes[index].properties.removeAll { $0.key.rawValue.hasPrefix("style.fill.layers.") }
        fixture.document.pages[0].nodes[index].properties += CanonicalFillLayerCodec.propertyValues(for: [gradient]).map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        let plan = try MultiPageStaticBuildPlanner.plan(document: fixture.document)
        let html = try XCTUnwrap(plan.files.first { $0.path.hasSuffix(".html") }?.contents)
        XCTAssertTrue(html.contains("data-siteforge-flow=")); XCTAssertTrue(html.contains("siteforge-effects.js"))
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-effects.js" && $0.contents == DecorativeEffectRuntime.javascript })
        XCTAssertTrue(plan.files.contains { $0.path == "styles.css" && $0.contents.contains("linear-gradient(") })
        let config = try XCTUnwrap(DecorativeEffectOutput.configuration(fixture.document.pages[0].nodes[index]))
        XCTAssertEqual(try JSONDecoder().decode(FlowOutputConfiguration.self, from: Data(config.json.utf8)), config)
    }

    // SF-1101-005 (OD-039): copies keep interactions pointed at the copied
    // objects; targets outside the copy stay as they are; projections keep
    // their identities so output is deterministic.
    func testCopiedInteractionsFollowCopiedTargetsAndKeepOutsideTargets() throws {
        let inside = NodeID(), outside = NodeID(), copy = NodeID()
        let sourcePage = PageID(), destinationPage = PageID()
        let original = CanonicalInteraction(id: UUID(), trigger: .click, actions: [
            .init(kind: .show, target: inside), .init(kind: .hide, target: outside),
            .init(kind: .navigate, page: sourcePage)])
        let text = try XCTUnwrap(CanonicalEventGraph.encode([original]))
        guard case .string(let copied) = CanonicalEventGraph.remappingTargets(.string(text), nodeMap: [inside: copy],
                                                                             pageMap: [sourcePage: destinationPage]) else {
            return XCTFail("Interactions stay text")
        }
        let decoded = try CanonicalEventGraph.decode(copied)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNotEqual(decoded[0].id, original.id, "A copy gets its own interaction identity")
        XCTAssertEqual(decoded[0].trigger, .click)
        XCTAssertEqual(decoded[0].actions.map(\.target), [copy, outside, nil], "Only copied targets follow the copy")
        XCTAssertEqual(decoded[0].actions.last?.page, destinationPage)

        guard case .string(let projected) = CanonicalEventGraph.remappingTargets(.string(text), nodeMap: [inside: copy],
                                                                                freshIdentity: false) else {
            return XCTFail("Interactions stay text")
        }
        XCTAssertEqual(try CanonicalEventGraph.decode(projected).first?.id, original.id)
        XCTAssertEqual(CanonicalEventGraph.remappingTargets(.string(text), nodeMap: [inside: copy], freshIdentity: false),
                       CanonicalEventGraph.remappingTargets(.string(text), nodeMap: [inside: copy], freshIdentity: false),
                       "A projection is deterministic")
        XCTAssertEqual(CanonicalEventGraph.remappingTargets(.number(3), nodeMap: [inside: copy]), .number(3))
        XCTAssertEqual(CanonicalEventGraph.remappingTargets(.string("not interactions"), nodeMap: [inside: copy]),
                       .string("not interactions"))
    }

    // SF-0508-001/004/005/008, SF-1204-003/004, SF-0305-001, SF-0306-001:
    // glass is closed optional typed data with opaque light/dark fallbacks.
    // Edits use the shared effect registry, skip unsupported kinds truthfully,
    // retain property identity, undo once, and stay out of schema 20.
    func testGlassSurfaceTypedValidationHistoryFallbackOutputAndHistoricalSchema() throws {
        let fixture = try formattingFixture()
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID], revision: UInt64? = nil) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: revision ?? document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        func node(_ id: NodeID) throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }) }
        func glassPropertyIDs() throws -> [PropertyID] {
            try node(fixture.frame).properties.filter { $0.key.rawValue.hasPrefix(CanonicalGlassSurface.namespace) }.map(\.id)
        }
        let white = CanonicalSolidColor(red: 1, green: 1, blue: 1, alpha: 1)
        let black = CanonicalSolidColor(red: 0, green: 0, blue: 0, alpha: 1)
        let glass = CanonicalGlassSurface(blur: 18, fallback: white, darkFallback: black)
        XCTAssertTrue(glass.isValid)

        // A mixed selection edits the supported Frame and names the skipped Text.
        let before = session.document.pages
        let mixed = try prepare(.glass(glass), [fixture.text, fixture.frame])
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.frame])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.text])
        XCTAssertNotNil(mixed.skippedReasons[fixture.text])
        try session.execute(mixed.documentCommand)
        let after = session.document.pages
        XCTAssertEqual(try CanonicalGlassSurface.resolve(node(fixture.frame)), glass)
        XCTAssertNil(try CanonicalGlassSurface.resolve(node(fixture.text)))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, after)

        // One changed value keeps every authored property identity; an
        // unchanged, stale, unsupported or invalid edit never mutates.
        let identities = try glassPropertyIDs()
        XCTAssertEqual(identities.count, glass.properties.count)
        var softer = glass; softer.blur = 32
        try session.execute(prepare(.glass(softer), [fixture.frame]).documentCommand)
        XCTAssertEqual(try glassPropertyIDs(), identities)
        let edited = session.document
        XCTAssertThrowsError(try prepare(.glass(softer), [fixture.frame])) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
        XCTAssertThrowsError(try prepare(.glass(glass), [fixture.frame], revision: 0)) { XCTAssertEqual($0 as? DesignInspectorError, .stale) }
        XCTAssertThrowsError(try prepare(.glass(glass), [fixture.text]))
        let invalid: [CanonicalGlassSurface] = [
            .init(blur: .nan, fallback: white), .init(blur: -1, fallback: white), .init(blur: 61, fallback: white),
            .init(blur: 12, fallback: .init(red: 1, green: 1, blue: 1, alpha: 0.5)),
            .init(blur: 12, fallback: white, darkFallback: .init(red: 0, green: 0, blue: 0, alpha: 0.9)),
            .init(blur: 12, fallback: .init(red: 1.2, green: 1, blue: 1, alpha: 1)),
        ]
        for value in invalid {
            XCTAssertFalse(value.isValid)
            XCTAssertThrowsError(try prepare(.glass(value), [fixture.frame])) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        }
        XCTAssertEqual(session.document, edited)

        // Closed namespace: unknown versions, partial fallbacks and unsupported
        // kinds are rejected by canonical validation rather than ignored.
        let frameIndex = try XCTUnwrap(edited.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let textIndex = try XCTUnwrap(edited.pages[0].nodes.firstIndex { $0.id == fixture.text })
        var unknown = edited
        unknown.pages[0].nodes[frameIndex].properties.append(.init(key: .init(rawValue: "style.glass.v2.blur"), value: .number(8)))
        XCTAssertThrowsError(try unknown.validate())
        var partial = edited
        partial.pages[0].nodes[frameIndex].properties.removeAll { $0.key.rawValue == CanonicalGlassSurface.namespace + "darkFallback.alpha" }
        XCTAssertThrowsError(try partial.validate())
        var onText = edited
        onText.pages[0].nodes[textIndex].properties += glass.properties.map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        XCTAssertThrowsError(try onText.validate())
        try edited.validate()

        // Output blurs only where backdrop filters are supported and reduced
        // transparency is not requested; otherwise opaque light/dark fallbacks.
        let plan = try MultiPageStaticBuildPlanner.plan(document: edited)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let selector = ".sf-node-" + fixture.frame.description
        XCTAssertTrue(css.contains("\(selector) { backdrop-filter:blur(32px);-webkit-backdrop-filter:blur(32px); }"), css)
        XCTAssertTrue(css.contains("@supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) { \(selector) { background:rgb(255 255 255)!important; } }"), css)
        XCTAssertTrue(css.contains("@media (prefers-reduced-transparency:reduce) { \(selector) { background:rgb(255 255 255)!important;backdrop-filter:none;-webkit-backdrop-filter:none; } }"), css)
        XCTAssertTrue(css.contains("\(selector) { background:rgb(0 0 0)!important; }"), css)
        XCTAssertFalse(css.contains(".sf-node-" + fixture.text.description + " { backdrop-filter"), css)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("styles.css"), html)
        XCTAssertFalse(plan.files.contains { $0.path == "siteforge-effects.js" })

        // Persistence and the strict historical envelope.
        let encoded = try DocumentSerializer.encode(edited)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), edited)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical["schemaVersion"] = 20
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))

        // Removal restores the ordinary appearance with no residual output.
        try session.execute(prepare(.glass(nil), [fixture.frame]).documentCommand)
        XCTAssertNil(try CanonicalGlassSurface.resolve(node(fixture.frame)))
        XCTAssertFalse(try node(fixture.frame).properties.contains { $0.key.rawValue.hasPrefix("style.glass.") })
        XCTAssertFalse(try MultiPageStaticBuildPlanner.plan(document: session.document).files.contains { $0.contents.contains("backdrop-filter") })
    }

    // OD-040, SF-1103-001/002/004/005, SF-1104-001/005: motion is closed typed
    // data in `motion.v1.`. Edits use the shared effect registry, undo once,
    // keep property identity, refuse invalid values without mutation, reject
    // unknown or partial data, and stay out of schema 26 documents.
    func testMotionTypedValidationHistoryPropertyIdentityAndSchemaGate() throws {
        let fixture = try formattingFixture()
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID], revision: UInt64? = nil) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: revision ?? document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        func node(_ id: NodeID) throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }) }
        func motionPropertyIDs(_ id: NodeID) throws -> [PropertyID] {
            try node(id).properties.filter { $0.key.rawValue.hasPrefix(CanonicalMotion.prefix) }.map(\.id)
        }
        let motion = CanonicalMotion(transition: CanonicalMotion.defaultTransition, entrance: CanonicalMotion.defaultEntrance)
        XCTAssertTrue(motion.isValid)
        XCTAssertEqual(motion.properties.count, 8)

        // Text and Frame both support motion; one transaction, one undo entry.
        let before = session.document.pages
        let prepared = try prepare(.motion(motion), [fixture.text, fixture.frame])
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.text, fixture.frame])
        XCTAssertTrue(prepared.skippedNodeIDs.isEmpty)
        try session.execute(prepared.documentCommand)
        let after = session.document.pages
        XCTAssertEqual(try CanonicalMotion.resolve(node(fixture.frame)), motion)
        XCTAssertEqual(try CanonicalMotion.resolve(node(fixture.text)), motion)
        XCTAssertNil(try CanonicalMotion.resolve(node(fixture.targetFrame)))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, after)

        // One changed value keeps every property identity; unchanged, stale
        // and invalid edits never mutate the document.
        let identities = try motionPropertyIDs(fixture.frame)
        XCTAssertEqual(identities.count, 8)
        var slower = motion; slower.entrance?.milliseconds = 900
        try session.execute(prepare(.motion(slower), [fixture.frame]).documentCommand)
        XCTAssertEqual(try motionPropertyIDs(fixture.frame), identities)
        let edited = session.document
        XCTAssertThrowsError(try prepare(.motion(slower), [fixture.frame])) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
        XCTAssertThrowsError(try prepare(.motion(motion), [fixture.frame], revision: 0)) { XCTAssertEqual($0 as? DesignInspectorError, .stale) }
        var invalid: [CanonicalMotion] = []
        for value in [Double.nan, .infinity, 49, 2_001, 120.5] as [Double] { var bad = motion; bad.transition?.milliseconds = value; invalid.append(bad) }
        for value in [-1, 401, 12.5] as [Double] { var bad = motion; bad.entrance?.distance = value; invalid.append(bad) }
        for value in [-1, 51, 10.5] as [Double] { var bad = motion; bad.entrance?.offsetPercent = value; invalid.append(bad) }
        for value in [99, 3_001] as [Double] { var bad = motion; bad.entrance?.milliseconds = value; invalid.append(bad) }
        var late = motion; late.entrance?.delayMilliseconds = 3_001; invalid.append(late)
        for value in invalid {
            XCTAssertFalse(value.isValid)
            XCTAssertThrowsError(try prepare(.motion(value), [fixture.frame])) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        }
        XCTAssertEqual(session.document, edited)

        // Closed namespace: unknown versions, partial groups, unknown values
        // and unsupported kinds are rejected rather than ignored. A complete
        // single group is valid on its own.
        let frameIndex = try XCTUnwrap(edited.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        var unknown = edited
        unknown.pages[0].nodes[frameIndex].properties.append(.init(key: .init(rawValue: "motion.v2.entrance.effect"), value: .string("fade")))
        XCTAssertThrowsError(try unknown.validate())
        var partial = edited
        partial.pages[0].nodes[frameIndex].properties.removeAll { $0.key.rawValue == CanonicalMotion.entranceNamespace + "offset" }
        XCTAssertThrowsError(try partial.validate())
        var unknownEasing = edited
        let easingIndex = try XCTUnwrap(unknownEasing.pages[0].nodes[frameIndex].properties.firstIndex {
            $0.key.rawValue == CanonicalMotion.transitionNamespace + "easing" })
        unknownEasing.pages[0].nodes[frameIndex].properties[easingIndex].value = .string("bounce")
        XCTAssertThrowsError(try unknownEasing.validate())
        var wrongType = edited
        let durationIndex = try XCTUnwrap(wrongType.pages[0].nodes[frameIndex].properties.firstIndex {
            $0.key.rawValue == CanonicalMotion.entranceNamespace + "duration" })
        wrongType.pages[0].nodes[frameIndex].properties[durationIndex].value = .string("600")
        XCTAssertThrowsError(try wrongType.validate())
        var transitionOnly = edited
        transitionOnly.pages[0].nodes[frameIndex].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalMotion.entranceNamespace) }
        try transitionOnly.validate()
        XCTAssertEqual(try CanonicalMotion.resolve(transitionOnly.pages[0].nodes[frameIndex]), CanonicalMotion(transition: CanonicalMotion.defaultTransition))
        var wrongKind = try node(fixture.frame); wrongKind.kind = .component
        XCTAssertThrowsError(try CanonicalMotion.resolve(wrongKind)) { XCTAssertEqual($0 as? ModelValidationError, .invalidMotionState) }
        try edited.validate()

        // Persistence and the strict historical envelope: schema 26 refuses
        // motion but still reads the same document without it.
        let encoded = try DocumentSerializer.encode(edited)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), edited)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(fixture.document)) as? [String: Any])
        legacy["schemaVersion"] = 26
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)).pages, fixture.document.pages)

        // Removal (nil or an empty value) leaves no residual properties.
        try session.execute(prepare(.motion(nil), [fixture.frame]).documentCommand)
        XCTAssertNil(try CanonicalMotion.resolve(node(fixture.frame)))
        XCTAssertNotNil(try CanonicalMotion.resolve(node(fixture.text)))
        try session.execute(prepare(.motion(CanonicalMotion()), [fixture.text]).documentCommand)
        XCTAssertFalse(try node(fixture.text).properties.contains { $0.key.rawValue.hasPrefix(CanonicalMotion.prefix) })
        XCTAssertThrowsError(try prepare(.motion(nil), [fixture.frame])) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
    }

    // OD-039, SF-1101-001/002/003/004/005/006: the event graph is closed,
    // canonical, ordered data on the trigger node. Edits undo once; invalid
    // or forged graphs never enter the document; click needs a button or
    // link; deleted targets keep their reference; schema 26 refuses it.
    func testEventGraphTypedValidationHistoryClickPolicyAndSchemaGate() throws {
        let fixture = try formattingFixture()
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID], revision: UInt64? = nil) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: revision ?? document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        func node(_ id: NodeID) throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }) }
        let reveal = CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [
            CanonicalInteraction.Action(kind: .show, target: fixture.targetFrame),
            CanonicalInteraction.Action(kind: .scrollTo, target: fixture.targetFrame)])
        let leave = CanonicalInteraction(id: UUID(), trigger: .focusOut, actions: [CanonicalInteraction.Action(kind: .hide, target: fixture.targetFrame)])
        let graph = CanonicalEventGraph(interactions: [reveal, leave])
        XCTAssertTrue(graph.isValid)

        let before = session.document.pages
        try session.execute(prepare(.events(graph), [fixture.frame]).documentCommand)
        let after = session.document.pages
        XCTAssertEqual(try CanonicalEventGraph.resolve(node(fixture.frame)), graph)
        XCTAssertEqual(try CanonicalEventGraph.resolve(node(fixture.frame))?.interactions.map(\.id), [reveal.id, leave.id])
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, after)
        let edited = session.document

        // Click is refused on Text (not keyboard-operable) with its reason.
        let click = CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .click,
            actions: [CanonicalInteraction.Action(kind: .toggle, target: fixture.frame)])])
        XCTAssertTrue(click.isValid)
        XCTAssertFalse(click.isAllowed(on: .text))
        XCTAssertTrue(click.isAllowed(on: .button))
        XCTAssertThrowsError(try prepare(.events(click), [fixture.text])) {
            XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalEventGraph.clickReason))
        }
        XCTAssertThrowsError(try prepare(.events(graph), [fixture.frame], revision: 0)) { XCTAssertEqual($0 as? DesignInspectorError, .stale) }
        XCTAssertThrowsError(try prepare(.events(graph), [fixture.frame])) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
        let many = (0..<9).map { _ in CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [CanonicalInteraction.Action(kind: .hide, target: fixture.frame)]) }
        let invalid: [CanonicalEventGraph] = [
            CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [])]),
            CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [CanonicalInteraction.Action(kind: .show)])]),
            CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
                actions: [CanonicalInteraction.Action(kind: .navigate, target: fixture.frame)])]),
            CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
                actions: [CanonicalInteraction.Action(kind: .hide, target: fixture.frame, page: session.document.pages[0].id)])]),
            CanonicalEventGraph(interactions: [reveal, reveal]),
            CanonicalEventGraph(interactions: many),
            CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
                actions: Array(repeating: CanonicalInteraction.Action(kind: .hide, target: fixture.frame), count: 9))]),
        ]
        for value in invalid {
            XCTAssertFalse(value.isValid)
            XCTAssertThrowsError(try prepare(.events(value), [fixture.frame])) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        }
        XCTAssertEqual(session.document, edited)

        // Forged or non-canonical stored text, unknown keys, a false start
        // flag and click on a Frame are rejected by canonical validation.
        let frameIndex = try XCTUnwrap(edited.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let propertyIndex = try XCTUnwrap(edited.pages[0].nodes[frameIndex].properties.firstIndex { $0.key.rawValue == CanonicalEventGraph.interactionsKey })
        guard case .string(let text) = edited.pages[0].nodes[frameIndex].properties[propertyIndex].value else { return XCTFail("Interactions are stored as text") }
        XCTAssertEqual(try CanonicalEventGraph.decode(text), graph.interactions)
        for forged in [text.replacingOccurrences(of: "\"trigger\"", with: "\"script\":\"alert(1)\",\"trigger\""), " " + text, "[]", "{}", "not json",
                       text.replacingOccurrences(of: "focus-out", with: "keydown")] {
            var copy = edited
            copy.pages[0].nodes[frameIndex].properties[propertyIndex].value = .string(forged)
            XCTAssertThrowsError(try copy.validate(), forged)
        }
        var unknown = edited
        unknown.pages[0].nodes[frameIndex].properties.append(.init(key: .init(rawValue: "event.v1.handler"), value: .string("run()")))
        XCTAssertThrowsError(try unknown.validate())
        var falseHidden = edited
        falseHidden.pages[0].nodes[frameIndex].properties.append(.init(key: .init(rawValue: CanonicalEventGraph.startsHiddenKey), value: .boolean(false)))
        XCTAssertThrowsError(try falseHidden.validate())
        var clickOnFrame = edited
        clickOnFrame.pages[0].nodes[frameIndex].properties[propertyIndex].value = .string(try XCTUnwrap(CanonicalEventGraph.encode(click.interactions)))
        XCTAssertThrowsError(try clickOnFrame.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidInteractionGraphState) }

        // Deleting a target keeps the reference (diagnosed at build time).
        var orphaned = edited
        orphaned.pages[0].nodes.removeAll { $0.id == fixture.targetFrame }
        orphaned.pages[0].nodes[0].childIDs.removeAll { $0 == fixture.targetFrame }
        try orphaned.validate()
        XCTAssertEqual(try CanonicalEventGraph.resolve(XCTUnwrap(orphaned.pages[0].nodes.first { $0.id == fixture.frame })), graph)

        // Persistence and the schema 27 gate.
        let encoded = try DocumentSerializer.encode(edited)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), edited)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))

        // Removal leaves nothing behind.
        try session.execute(prepare(.events(nil), [fixture.frame]).documentCommand)
        XCTAssertFalse(try node(fixture.frame).properties.contains { $0.key.rawValue.hasPrefix(CanonicalEventGraph.prefix) })
    }

    // OD-039, SF-1101-003/004/006/007/008: output compiles the fixed action set
    // to escaped data, drops missing targets, starts hidden objects with
    // `hidden`, ships one fixed runtime, and reports missing targets,
    // pointer-only interactions and focus loops as warnings.
    func testEventGraphOutputCompilesFixedActionsStartHiddenAndDiagnostics() throws {
        var fixture = try formattingFixture()
        let pageID = fixture.document.pages[0].id
        let missing = NodeID()
        func add(_ graph: CanonicalEventGraph, to id: NodeID) throws {
            let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == id })
            fixture.document.pages[0].nodes[index].properties += graph.properties.sorted { $0.key < $1.key }
                .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        }
        try add(CanonicalEventGraph(interactions: [
            CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [
                CanonicalInteraction.Action(kind: .show, target: fixture.targetFrame),
                CanonicalInteraction.Action(kind: .focus, target: fixture.targetFrame),
                CanonicalInteraction.Action(kind: .hide, target: missing)]),
            CanonicalInteraction(id: UUID(), trigger: .pointerEnter, actions: [CanonicalInteraction.Action(kind: .navigate, page: pageID)]),
        ]), to: fixture.frame)
        try add(CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
            actions: [CanonicalInteraction.Action(kind: .focus, target: fixture.frame)])], startsHidden: true), to: fixture.targetFrame)
        try add(CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .pointerEnter,
            actions: [CanonicalInteraction.Action(kind: .toggle, target: fixture.targetFrame)])]), to: fixture.text)
        try fixture.document.validate()

        let plan = try MultiPageStaticBuildPlanner.plan(document: fixture.document)
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: fixture.document).integrityDigest, plan.integrityDigest)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        func events(for id: NodeID) throws -> [EventOutputConfiguration] {
            let end = try XCTUnwrap(html.range(of: "\" data-siteforge-node=\"\(id.description)\""), html)
            let start = try XCTUnwrap(html.range(of: "data-siteforge-events=\"", options: .backwards, range: html.startIndex..<end.lowerBound))
            let json = String(html[start.upperBound..<end.lowerBound]).replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
            return try JSONDecoder().decode([EventOutputConfiguration].self, from: Data(json.utf8))
        }
        let frame = fixture.frame.description, target = fixture.targetFrame.description, text = fixture.text.description
        XCTAssertEqual(try events(for: fixture.frame), [
            EventOutputConfiguration(trigger: "focus-in", actions: [.init(kind: "show", target: target), .init(kind: "focus", target: target)]),
            EventOutputConfiguration(trigger: "pointer-enter", actions: [.init(kind: "navigate", href: "index.html")]),
        ])
        XCTAssertEqual(try events(for: fixture.targetFrame), [EventOutputConfiguration(trigger: "focus-in", actions: [.init(kind: "focus", target: frame)])])
        XCTAssertEqual(try events(for: fixture.text), [EventOutputConfiguration(trigger: "pointer-enter", actions: [.init(kind: "toggle", target: target)])])
        XCTAssertFalse(html.contains(missing.description), html)
        XCTAssertTrue(html.contains("class=\"sf-node-\(target)\" hidden"), html)
        XCTAssertFalse(html.contains("class=\"sf-node-\(frame)\" hidden"), html)
        XCTAssertTrue(html.contains("<script src=\"siteforge-events.js\" defer></script>"), html)
        XCTAssertTrue(html.contains("styles.css"), html)
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-events.js" && $0.contents == EventGraphRuntime.javascript })
        XCTAssertTrue(css.contains(EventGraphOutput.hiddenCSS), css)

        let compiled = StaticBuildCompiler.compile(document: fixture.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        let codes = compiled.findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertTrue(codes.contains("interaction-target-missing:\(frame)"), "\(codes)")
        XCTAssertFalse(codes.contains("interaction-target-missing:\(text)"), "\(codes)")
        XCTAssertTrue(codes.contains("interaction-pointer-only:\(text)"), "\(codes)")
        XCTAssertFalse(codes.contains("interaction-pointer-only:\(frame)"), "\(codes)")
        XCTAssertTrue(codes.contains("interaction-focus-loop:\(frame)"), "\(codes)")
        XCTAssertTrue(codes.contains("interaction-focus-loop:\(target)"), "\(codes)")
        XCTAssertTrue(compiled.findings.filter { $0.code.hasPrefix("interaction-") }.allSatisfy { $0.severity == .warning })
        XCTAssertFalse(compiled.findings.contains { $0.code.hasPrefix("interaction-") && $0.explanation.contains("Source") })

        // The runtime is fixed SiteForge code with a re-entry guard.
        let script = EventGraphRuntime.javascript
        for forbidden in ["eval(", "innerHTML", "new Function", "fetch(", "XMLHttpRequest", "localStorage", "document.write"] {
            XCTAssertFalse(script.contains(forbidden), forbidden)
        }
        XCTAssertTrue(script.contains("if (depth >= 4) return;"))
        XCTAssertTrue(script.contains("reduce.matches ? 'auto' : 'smooth'"))

        let plain = try MultiPageStaticBuildPlanner.plan(document: formattingFixture().document)
        XCTAssertFalse(plain.files.contains { $0.path == "siteforge-events.js" || $0.contents.contains("data-siteforge-events")
            || $0.contents.contains(EventGraphOutput.hiddenCSS) })
    }

    // OD-039, SF-1105-001/002/004/005, SF-1106-001/002/004/005: page
    // variables live on the page Root, overlays on containers and visibility
    // conditions on supported objects. Each edit undoes once; invalid or
    // forged data never enters the document; removed variables keep their
    // references; schema 26 refuses all of it.
    func testRuntimeVariablesOverlaysAndVisibilityTypedValidationHistoryAndSchemaGate() throws {
        typealias Action = CanonicalInteraction.Action
        let fixture = try formattingFixture()
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID]) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        func node(_ id: NodeID) throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }) }
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: session.document.pages[0])).id
        let open = CanonicalStateVariable(id: UUID(), name: "Menu open", type: .boolean, initial: .boolean(false))
        let step = CanonicalStateVariable(id: UUID(), name: "Step", type: .number, initial: .number(2))

        // Variables: page Root only, one undoable edit.
        let before = session.document.pages
        try session.execute(prepare(.pageVariables([open, step]), [root]).documentCommand)
        XCTAssertEqual(try CanonicalPageState.storedVariables(node(root)), [open, step])
        XCTAssertEqual(CanonicalPageState.variables(on: session.document.pages[0]), [open, step])
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo()
        XCTAssertThrowsError(try prepare(.pageVariables([open]), [fixture.frame])) {
            XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalPageState.variablesReason))
        }
        var sameName = open; sameName.id = UUID()
        var wrongType = step; wrongType.initial = .boolean(true)
        var fractional = step; fractional.initial = .number(1.5)
        var huge = step; huge.initial = .number(2_000_000_000)
        var control = open; control.name = "Menu\nopen"
        var blank = open; blank.name = " "
        let tooMany = (0..<17).map { CanonicalStateVariable(id: UUID(), name: "V\($0)", type: .boolean, initial: .boolean(false)) }
        for invalid in [[open, sameName], [open, open], [wrongType], [fractional], [huge], [control], [blank], tooMany] {
            XCTAssertFalse(CanonicalPageState.isValid(invalid))
            XCTAssertThrowsError(try prepare(.pageVariables(invalid), [root])) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        }

        // Overlays: containers only, never the page Root.
        let modal = CanonicalOverlay(kind: .modal, dismissesOnOutsideClick: false)
        try session.execute(prepare(.overlay(modal), [fixture.targetFrame]).documentCommand)
        XCTAssertEqual(try CanonicalOverlay.resolve(node(fixture.targetFrame)), modal)
        XCTAssertThrowsError(try prepare(.overlay(modal), [root])) { XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalPageState.rootReason)) }
        XCTAssertThrowsError(try prepare(.overlay(modal), [fixture.text])) { XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalOverlay.unsupportedReason)) }

        // Visibility conditions: typed values, never on the page Root.
        let condition = CanonicalPageState.Condition(variable: open.id, equals: .boolean(true))
        try session.execute(prepare(.visibility(condition), [fixture.text]).documentCommand)
        XCTAssertEqual(try CanonicalPageState.condition(node(fixture.text)), condition)
        XCTAssertThrowsError(try prepare(.visibility(condition), [root])) { XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalPageState.rootReason)) }
        XCTAssertThrowsError(try prepare(.visibility(CanonicalPageState.Condition(variable: open.id, equals: .string(String(repeating: "x", count: 257)))), [fixture.text])) {
            XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue)
        }
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 3)

        // Actions carry exactly the fields their kind uses.
        XCTAssertTrue(Action(kind: .setVariable, variable: open.id, value: .boolean(true)).isValid)
        XCTAssertTrue(Action(kind: .toggleVariable, variable: open.id).isValid)
        XCTAssertTrue(Action(kind: .openOverlay, target: fixture.targetFrame).isValid)
        XCTAssertFalse(Action(kind: .setVariable, variable: open.id).isValid)
        XCTAssertFalse(Action(kind: .setVariable, variable: step.id, value: .number(0.5)).isValid)
        XCTAssertFalse(Action(kind: .toggleVariable, variable: open.id, value: .boolean(true)).isValid)
        XCTAssertFalse(Action(kind: .openOverlay, target: fixture.targetFrame, variable: open.id).isValid)
        let graph = CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [
            Action(kind: .setVariable, variable: step.id, value: .number(3)), Action(kind: .openOverlay, target: fixture.targetFrame)])])
        try session.execute(prepare(.events(graph), [fixture.frame]).documentCommand)
        XCTAssertEqual(try CanonicalEventGraph.resolve(node(fixture.frame)), graph)
        let edited = session.document

        // Forged, misplaced, partial or unknown data is refused by validation.
        let pageNodes = edited.pages[0].nodes
        let rootIndex = try XCTUnwrap(pageNodes.firstIndex { $0.id == root })
        let frameIndex = try XCTUnwrap(pageNodes.firstIndex { $0.id == fixture.frame })
        let overlayIndex = try XCTUnwrap(pageNodes.firstIndex { $0.id == fixture.targetFrame })
        let variablesIndex = try XCTUnwrap(pageNodes[rootIndex].properties.firstIndex { $0.key.rawValue == CanonicalPageState.variablesKey })
        guard case .string(let stored) = pageNodes[rootIndex].properties[variablesIndex].value else { return XCTFail("Variables are stored as text") }
        for forged in [" " + stored, "[]", "{}", "not json", stored.replacingOccurrences(of: "\"name\"", with: "\"script\":1,\"name\""),
                       stored.replacingOccurrences(of: "\"boolean\"", with: "\"date\"")] {
            var copy = edited
            copy.pages[0].nodes[rootIndex].properties[variablesIndex].value = .string(forged)
            XCTAssertThrowsError(try copy.validate(), forged)
        }
        var misplaced = edited
        misplaced.pages[0].nodes[frameIndex].properties.append(.init(key: .init(rawValue: CanonicalPageState.variablesKey), value: .string(stored)))
        XCTAssertThrowsError(try misplaced.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidRuntimeState) }
        var unknown = edited
        unknown.pages[0].nodes[rootIndex].properties.append(.init(key: .init(rawValue: "state.v1.persist"), value: .boolean(true)))
        XCTAssertThrowsError(try unknown.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidRuntimeState) }
        var rootOverlay = edited
        rootOverlay.pages[0].nodes[rootIndex].properties += modal.properties.sorted { $0.key < $1.key }
            .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        XCTAssertThrowsError(try rootOverlay.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidOverlayState) }
        var partial = edited
        partial.pages[0].nodes[overlayIndex].properties.removeAll { $0.key.rawValue == CanonicalOverlay.dismissKey }
        XCTAssertThrowsError(try partial.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidOverlayState) }
        try edited.validate()

        // Removing a variable keeps the condition and action that use it.
        try session.execute(prepare(.pageVariables([step]), [root]).documentCommand)
        XCTAssertEqual(try CanonicalPageState.condition(node(fixture.text)), condition)
        try session.document.validate()

        // Persistence and the schema 27 gate.
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))

        // Removal leaves nothing behind.
        try session.execute(prepare(.overlay(nil), [fixture.targetFrame]).documentCommand)
        try session.execute(prepare(.visibility(nil), [fixture.text]).documentCommand)
        try session.execute(prepare(.pageVariables([]), [root]).documentCommand)
        XCTAssertFalse(session.document.pages[0].nodes.contains { $0.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalPageState.prefix) || $0.key.rawValue.hasPrefix(CanonicalOverlay.prefix)
        } })
    }

    // OD-039, SF-1105-003/004/006/007, SF-1106-003/004/006/007: output is
    // hydration-safe (initial `hidden` matches the starting values), drops
    // actions of the wrong type or target, carries variables as escaped data,
    // ships one fixed runtime with a modal focus trap and stacking, and
    // reports invalid conditions and unreachable or unnamed overlays.
    func testRuntimeVariablesOverlaysOutputHydrationRuntimeAndDiagnostics() throws {
        typealias Action = CanonicalInteraction.Action
        var fixture = try formattingFixture()
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: fixture.document.pages[0])).id
        let open = CanonicalStateVariable(id: UUID(), name: "Menu open", type: .boolean, initial: .boolean(false))
        let label = CanonicalStateVariable(id: UUID(), name: "Label", type: .string, initial: .string("A"))
        func add(_ values: [String: PropertyValue], to id: NodeID) throws {
            let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == id })
            fixture.document.pages[0].nodes[index].properties += values.sorted { $0.key < $1.key }
                .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        }
        try add(CanonicalPageState.properties(variables: [open, label]), to: root)
        try add(CanonicalOverlay(kind: .modal, dismissesOnOutsideClick: true).properties, to: fixture.targetFrame)
        try add(CanonicalPageState.properties(condition: .init(variable: open.id, equals: .boolean(true))), to: fixture.text)
        try add(CanonicalPageState.properties(condition: .init(variable: label.id, equals: .string("A"))), to: fixture.targetText)
        try add(CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [
            Action(kind: .toggleVariable, variable: open.id),
            Action(kind: .openOverlay, target: fixture.targetFrame),
            Action(kind: .setVariable, variable: label.id, value: .number(1)),
            Action(kind: .toggleVariable, variable: label.id),
            Action(kind: .setVariable, variable: UUID(), value: .boolean(true)),
            Action(kind: .openOverlay, target: fixture.text),
            Action(kind: .setVariable, variable: label.id, value: .string("B")),
        ])]).properties, to: fixture.frame)
        try fixture.document.validate()

        func unescape(_ value: String) -> String {
            value.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
        }
        func tag(_ id: NodeID, in html: String) throws -> String {
            let marker = try XCTUnwrap(html.range(of: "data-siteforge-node=\"\(id.description)\""), html)
            let start = try XCTUnwrap(html.range(of: "<", options: .backwards, range: html.startIndex..<marker.lowerBound)).lowerBound
            let end = try XCTUnwrap(html.range(of: ">", range: marker.upperBound..<html.endIndex)).upperBound
            return String(html[start..<end])
        }
        func attribute(_ name: String, in text: String) throws -> String {
            let start = try XCTUnwrap(text.range(of: name + "=\""), text)
            let end = try XCTUnwrap(text.range(of: "\"", range: start.upperBound..<text.endIndex))
            return unescape(String(text[start.upperBound..<end.lowerBound]))
        }
        let plan = try MultiPageStaticBuildPlanner.plan(document: fixture.document)
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: fixture.document).integrityDigest, plan.integrityDigest)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let decoder = JSONDecoder()

        let overlayTag = try tag(fixture.targetFrame, in: html)
        XCTAssertTrue(overlayTag.hasSuffix(" data-siteforge-overlay=\"modal\" role=\"dialog\" aria-modal=\"true\" data-siteforge-dismiss-outside hidden>"), overlayTag)
        let hiddenTag = try tag(fixture.text, in: html), shownTag = try tag(fixture.targetText, in: html)
        XCTAssertTrue(hiddenTag.hasSuffix(" hidden>"), hiddenTag)
        XCTAssertFalse(shownTag.contains(" hidden"), shownTag)
        XCTAssertEqual(try decoder.decode(EventGraphOutput.ConditionOutput.self, from: Data(attribute("data-siteforge-visible-when", in: hiddenTag).utf8)),
                       EventGraphOutput.ConditionOutput(equals: .boolean(true), variable: open.id.uuidString.lowercased()))
        XCTAssertEqual(try decoder.decode(EventGraphOutput.ConditionOutput.self, from: Data(attribute("data-siteforge-visible-when", in: shownTag).utf8)),
                       EventGraphOutput.ConditionOutput(equals: .string("A"), variable: label.id.uuidString.lowercased()))
        XCTAssertEqual(try decoder.decode([EventGraphOutput.VariableOutput].self, from: Data(attribute("data-siteforge-state", in: html).utf8)), [
            EventGraphOutput.VariableOutput(id: open.id.uuidString.lowercased(), type: "boolean", value: .boolean(false)),
            EventGraphOutput.VariableOutput(id: label.id.uuidString.lowercased(), type: "string", value: .string("A")),
        ])
        XCTAssertTrue(html.contains("<div hidden data-siteforge-state=\""), html)
        XCTAssertEqual(try decoder.decode([EventOutputConfiguration].self, from: Data(attribute("data-siteforge-events", in: tag(fixture.frame, in: html)).utf8)), [
            EventOutputConfiguration(trigger: "focus-in", actions: [
                .init(kind: "toggle-variable", variable: open.id.uuidString.lowercased()),
                .init(kind: "open-overlay", target: fixture.targetFrame.description),
                .init(kind: "set-variable", variable: label.id.uuidString.lowercased(), value: .string("B")),
            ]),
        ])
        XCTAssertTrue(html.contains("<script src=\"siteforge-events.js\" defer></script>"), html)
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-events.js" && $0.contents == EventGraphRuntime.javascript })
        XCTAssertTrue(css.contains(EventGraphOutput.hiddenCSS), css)
        XCTAssertTrue(css.contains(EventGraphOutput.overlayCSS), css)
        let release = LocalBuildProfileCompiler.compile(plan, profile: .staticRelease).0
        let releaseCSS = try XCTUnwrap(release.files.first { $0.path == "styles.css" }?.contents)
        for line in EventGraphOutput.overlayCSS.split(separator: "\n") { XCTAssertTrue(releaseCSS.contains(StaticCSSOptimizer.minify(String(line))), String(line)) }

        let compiled = StaticBuildCompiler.compile(document: fixture.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        let codes = compiled.findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertTrue(codes.contains("interaction-target-missing:\(fixture.frame.description)"), "\(codes)")
        XCTAssertTrue(codes.contains("overlay-unnamed:\(fixture.targetFrame.description)"), "\(codes)")
        XCTAssertFalse(codes.contains("overlay-unreachable:\(fixture.targetFrame.description)"), "\(codes)")
        XCTAssertFalse(codes.contains { $0.hasPrefix("state-binding-invalid") }, "\(codes)")

        // Removing a variable and the only opener: the condition is dropped
        // (the object is shown) and both problems are reported.
        var changed = fixture.document
        let rootIndex = try XCTUnwrap(changed.pages[0].nodes.firstIndex { $0.id == root })
        let frameIndex = try XCTUnwrap(changed.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let variablesIndex = try XCTUnwrap(changed.pages[0].nodes[rootIndex].properties.firstIndex { $0.key.rawValue == CanonicalPageState.variablesKey })
        changed.pages[0].nodes[rootIndex].properties[variablesIndex].value = try XCTUnwrap(CanonicalPageState.properties(variables: [open])[CanonicalPageState.variablesKey])
        changed.pages[0].nodes[frameIndex].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalEventGraph.prefix) }
        try changed.validate()
        let changedCodes = StaticBuildCompiler.compile(document: changed, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
            .findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertTrue(changedCodes.contains("state-binding-invalid:\(fixture.targetText.description)"), "\(changedCodes)")
        XCTAssertTrue(changedCodes.contains("overlay-unreachable:\(fixture.targetFrame.description)"), "\(changedCodes)")
        let changedHTML = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: changed).files.first { $0.path == "index.html" }?.contents)
        XCTAssertFalse(try tag(fixture.targetText, in: changedHTML).contains("data-siteforge-visible-when"))
        XCTAssertTrue(changedHTML.contains("siteforge-events.js"), changedHTML)

        // SF-1101-003: an action after Go To Page in the same interaction never runs.
        var unreachable = fixture.document
        let unreachableIndex = try XCTUnwrap(unreachable.pages[0].nodes.firstIndex { $0.id == fixture.text })
        unreachable.pages[0].nodes[unreachableIndex].properties += CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
            actions: [Action(kind: .navigate, page: unreachable.pages[0].id), Action(kind: .show, target: fixture.frame)])]).properties
            .sorted { $0.key < $1.key }.map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        try unreachable.validate()
        let unreachableCodes = StaticBuildCompiler.compile(document: unreachable, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
            .findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertTrue(unreachableCodes.contains("interaction-action-unreachable:\(fixture.text.description)"), "\(unreachableCodes)")
        XCTAssertFalse(unreachableCodes.contains("interaction-action-unreachable:\(fixture.frame.description)"), "\(unreachableCodes)")

        // The runtime is fixed SiteForge code: typed writes, Escape, modal
        // focus trap, nested stacking and focus restore; no author text.
        let script = EventGraphRuntime.javascript
        for expected in ["typeOf(value) !== variable.type", "event.key === 'Escape'", "event.key !== 'Tab' || !entry.modal",
                         "const closing = stack.splice(index);", "restore.focus()", "1000 + stack.length * 2", "if (depth >= 4) return;",
                         "document.body.appendChild(element);", "entry.home.replaceWith(entry.element);"] {
            XCTAssertTrue(script.contains(expected), expected)
        }
        for forbidden in ["eval(", "innerHTML", "new Function", "fetch(", "XMLHttpRequest", "localStorage", "sessionStorage", "document.cookie", "document.write"] {
            XCTAssertFalse(script.contains(forbidden), forbidden)
        }
    }

    // SF-1101-004, SF-1105-003/004, SF-1106-003 (lane R review): every page
    // that runs interactions ships the hidden rule (static layout gives each
    // object an explicit `display`); a visibility condition, not Start
    // hidden, decides the first render; an overlay ignores a visibility
    // condition and Show opens it through the overlay stack; containers on a
    // page without page flow are reported because static layout writes
    // their contents separately.
    func testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers() throws {
        typealias Action = CanonicalInteraction.Action
        var fixture = try formattingFixture()
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: fixture.document.pages[0])).id
        XCTAssertFalse(fixture.document.pages[0].usesConnectedOutput, "The fixture page uses static layout")
        func add(_ values: [String: PropertyValue], to id: NodeID) throws {
            let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == id })
            fixture.document.pages[0].nodes[index].properties += values.sorted { $0.key < $1.key }
                .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        }
        func openingTag(_ id: NodeID, in html: String) throws -> String {
            let marker = try XCTUnwrap(html.range(of: "data-siteforge-node=\"\(id.description)\""), html)
            let start = try XCTUnwrap(html.range(of: "<", options: .backwards, range: html.startIndex..<marker.lowerBound)).lowerBound
            let end = try XCTUnwrap(html.range(of: ">", range: marker.upperBound..<html.endIndex)).upperBound
            return String(html[start..<end])
        }
        func builtPage(_ document: CanonicalDocument) throws -> (html: String, css: String) {
            let plan = try MultiPageStaticBuildPlanner.plan(document: document)
            let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
            let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
            return (html, css)
        }

        // Nothing starts hidden, yet Hide needs the rule to beat `display: block`.
        try add(CanonicalEventGraph(interactions: [
            CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [Action(kind: .show, target: fixture.targetFrame)]),
            CanonicalInteraction(id: UUID(), trigger: .focusOut, actions: [Action(kind: .hide, target: fixture.targetFrame)]),
        ]).properties, to: fixture.frame)
        try fixture.document.validate()
        let hideOnly = try builtPage(fixture.document)
        XCTAssertFalse(try openingTag(fixture.targetFrame, in: hideOnly.html).hasSuffix(" hidden>"), hideOnly.html)
        XCTAssertTrue(hideOnly.css.contains(EventGraphOutput.hiddenCSS), hideOnly.css)

        // A condition that is true at the start shows a Start hidden object;
        // an overlay keeps starting hidden and drops its condition.
        let open = CanonicalStateVariable(id: UUID(), name: "Panel open", type: .boolean, initial: .boolean(true))
        try add(CanonicalPageState.properties(variables: [open]), to: root)
        try add(CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
            actions: [Action(kind: .toggleVariable, variable: open.id)])], startsHidden: true).properties, to: fixture.text)
        try add(CanonicalPageState.properties(condition: .init(variable: open.id, equals: .boolean(true))), to: fixture.text)
        try add(CanonicalOverlay(kind: .popover, dismissesOnOutsideClick: false).properties, to: fixture.targetFrame)
        try add(CanonicalPageState.properties(condition: .init(variable: open.id, equals: .boolean(true))), to: fixture.targetFrame)
        // Hiding the page Root, a container with separately written contents.
        try add(CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
            actions: [Action(kind: .hide, target: root)])]).properties, to: fixture.targetText)
        try fixture.document.validate()
        let bound = try builtPage(fixture.document)
        let textTag = try openingTag(fixture.text, in: bound.html)
        XCTAssertTrue(textTag.contains("data-siteforge-visible-when"), textTag)
        XCTAssertFalse(textTag.contains(" hidden"), textTag)
        let overlayTag = try openingTag(fixture.targetFrame, in: bound.html)
        // ADR-0065: the overlay is also part of the page Root, which an interaction hides.
        XCTAssertTrue(overlayTag.hasSuffix(" data-siteforge-overlay=\"popover\" role=\"dialog\" data-siteforge-within=\"\(root.description)\" hidden>"), overlayTag)
        XCTAssertFalse(overlayTag.contains("data-siteforge-visible-when"), overlayTag)

        let codes = StaticBuildCompiler.compile(document: fixture.document, profileSelection: .init(profile: .development),
                                                resourceDescriptors: [:], resourceData: [:])
            .findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertTrue(codes.contains("overlay-condition-ignored:\(fixture.targetFrame.description)"), "\(codes)")
        XCTAssertFalse(codes.contains("overlay-unreachable:\(fixture.targetFrame.description)"), "Show opens the overlay: \(codes)")
        // ADR-0065: static-layout containers are supported, so nothing is reported;
        // the Root's contents name it and hide with it.
        XCTAssertFalse(codes.contains { $0.hasPrefix("interaction-container-flat") }, "\(codes)")
        XCTAssertTrue(textTag.contains(" data-siteforge-within=\"\(root.description)\""), textTag)
        XCTAssertTrue(bound.css.contains("[data-siteforge-node=\"\(root.description)\"][hidden] ~ [data-siteforge-within~=\"\(root.description)\"] { display:none !important; }"), bound.css)
        XCTAssertFalse(codes.contains { $0.hasPrefix("state-binding-invalid") }, "\(codes)")

        // Show, Hide and Show or Hide on an overlay go through the overlay stack.
        let script = EventGraphRuntime.javascript
        XCTAssertTrue(script.contains("overlay && target.hidden && (action.kind === 'show' || action.kind === 'toggle')"))
        XCTAssertTrue(script.contains("overlay && !target.hidden && (action.kind === 'hide' || action.kind === 'toggle')"))
    }

    // OD-039, SF-1105-002/005/006, SF-1101-004, SF-1104-004 (ADR-0065): a
    // popover or menu can open next to its trigger (one optional key, one
    // undoable edit, kept on save, refused on a modal); the runtime places and
    // flips it, moves through a menu with arrow keys and runs Scrolled Into
    // View without IntersectionObserver. On a static-layout page a
    // container's contents name it, hide and reveal with it and count as part
    // of an overlay. Create Component refuses inbound interaction targets.
    func testOverlayPlacementMenuKeysAndStaticLayoutContainerContents() throws {
        typealias Action = CanonicalInteraction.Action
        var fixture = try formattingFixture()
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: fixture.document.pages[0])).id
        XCTAssertFalse(fixture.document.pages[0].usesConnectedOutput, "The fixture page uses static layout")
        // The target text moves inside the source Frame, which becomes a container.
        let rootIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == root })
        let frameIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let targetText = fixture.targetText
        let contentIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == targetText })
        fixture.document.pages[0].nodes[rootIndex].childIDs.removeAll { $0 == targetText }
        fixture.document.pages[0].nodes[frameIndex].childIDs = [fixture.targetText]
        fixture.document.pages[0].nodes[contentIndex].parent = .node(fixture.frame)
        for (key, value) in [("layout.x", 40.0), ("layout.y", 200.0)] {
            let index = try XCTUnwrap(fixture.document.pages[0].nodes[contentIndex].properties.firstIndex { $0.key.rawValue == key })
            fixture.document.pages[0].nodes[contentIndex].properties[index].value = .number(value)
        }
        try fixture.document.validate()

        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID]) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        func node(_ id: NodeID) throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }) }
        func otherOverlayPropertyIDs() throws -> [PropertyID] {
            try node(fixture.frame).properties.filter {
                $0.key.rawValue.hasPrefix(CanonicalOverlay.prefix) && $0.key.rawValue != CanonicalOverlay.placementKey
            }.map(\.id)
        }

        // Placement: one optional key for a popover or menu, never for a modal.
        let menu = CanonicalOverlay(kind: .menu, dismissesOnOutsideClick: true, placement: .below)
        XCTAssertEqual(menu.properties[CanonicalOverlay.placementKey], .string("below"))
        XCTAssertNil(CanonicalOverlay(kind: .modal, dismissesOnOutsideClick: true, placement: .below).properties[CanonicalOverlay.placementKey],
                     "A modal is always centred")
        let before = session.document.pages
        try session.execute(prepare(.overlay(menu), [fixture.frame]).documentCommand)
        let after = session.document.pages
        XCTAssertEqual(try CanonicalOverlay.resolve(node(fixture.frame)), menu)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, after)
        let identities = try otherOverlayPropertyIDs()
        XCTAssertEqual(identities.count, 2)
        var beside = menu; beside.placement = .end
        try session.execute(prepare(.overlay(beside), [fixture.frame]).documentCommand)
        XCTAssertEqual(try otherOverlayPropertyIDs(), identities, "Changing the placement keeps the other property identities")
        var drawn = beside; drawn.placement = nil
        try session.execute(prepare(.overlay(drawn), [fixture.frame]).documentCommand)
        XCTAssertFalse(try node(fixture.frame).properties.contains { $0.key.rawValue == CanonicalOverlay.placementKey })
        try session.undo()
        XCTAssertEqual(try CanonicalOverlay.resolve(node(fixture.frame))?.placement, .end)
        XCTAssertThrowsError(try prepare(.overlay(beside), [fixture.frame])) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
        let placed = session.document

        // Unknown, mistyped or modal placements are refused by validation.
        let placedIndex = try XCTUnwrap(placed.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let placementIndex = try XCTUnwrap(placed.pages[0].nodes[placedIndex].properties.firstIndex { $0.key.rawValue == CanonicalOverlay.placementKey })
        let kindIndex = try XCTUnwrap(placed.pages[0].nodes[placedIndex].properties.firstIndex { $0.key.rawValue == CanonicalOverlay.kindKey })
        for forged in [PropertyValue.string("left"), .string(""), .number(1), .boolean(true)] {
            var copy = placed
            copy.pages[0].nodes[placedIndex].properties[placementIndex].value = forged
            XCTAssertThrowsError(try copy.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidOverlayState) }
        }
        var modalPlaced = placed
        modalPlaced.pages[0].nodes[placedIndex].properties[kindIndex].value = .string("modal")
        XCTAssertThrowsError(try modalPlaced.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidOverlayState) }
        var twice = placed
        twice.pages[0].nodes[placedIndex].properties.append(.init(key: .init(rawValue: CanonicalOverlay.placementKey), value: .string("above")))
        XCTAssertThrowsError(try twice.validate())
        try placed.validate()

        // Persistence and the schema 27 gate.
        let encoded = try DocumentSerializer.encode(placed)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), placed)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))

        // Output: the menu opens from the text; the page Root reveals on scroll.
        var site = placed
        func add(_ values: [String: PropertyValue], to id: NodeID) throws {
            let index = try XCTUnwrap(site.pages[0].nodes.firstIndex { $0.id == id })
            site.pages[0].nodes[index].properties += values.sorted { $0.key < $1.key }
                .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        }
        try add(CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
            actions: [Action(kind: .openOverlay, target: fixture.frame)])]).properties, to: fixture.text)
        try add(CanonicalMotion(entrance: CanonicalMotion.defaultEntrance).properties, to: root)
        try site.validate()
        let plan = try MultiPageStaticBuildPlanner.plan(document: site)
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: site).integrityDigest, plan.integrityDigest)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        func placedTag(_ id: NodeID) throws -> String {
            let marker = try XCTUnwrap(html.range(of: "data-siteforge-node=\"\(id.description)\""), html)
            let start = try XCTUnwrap(html.range(of: "<", options: .backwards, range: html.startIndex..<marker.lowerBound)).lowerBound
            let end = try XCTUnwrap(html.range(of: ">", range: marker.upperBound..<html.endIndex)).upperBound
            return String(html[start..<end])
        }
        let rootName = root.description, frameName = fixture.frame.description
        let menuTag = try placedTag(fixture.frame)
        XCTAssertTrue(menuTag.hasSuffix(" data-siteforge-overlay=\"menu\" role=\"dialog\" data-siteforge-dismiss-outside data-siteforge-placement=\"end\" data-siteforge-within=\"\(rootName)\" data-siteforge-flat hidden>"), menuTag)
        let contentTag = try placedTag(fixture.targetText)
        XCTAssertTrue(contentTag.hasSuffix(" data-siteforge-within=\"\(rootName) \(frameName)\">"), contentTag)
        XCTAssertTrue(try placedTag(fixture.text).contains(" data-siteforge-within=\"\(rootName)\""), html)
        XCTAssertFalse(try placedTag(root).contains("data-siteforge-within"), html)
        XCTAssertTrue(css.contains("[data-siteforge-node=\"\(frameName)\"][hidden] ~ [data-siteforge-within~=\"\(frameName)\"] { display:none !important; }"), css)
        XCTAssertFalse(css.contains("[data-siteforge-node=\"\(rootName)\"][hidden] ~"), "Nothing hides the Root: \(css)")
        XCTAssertTrue(css.contains("@media screen and (prefers-reduced-motion:no-preference) { .sf-motion-ready [data-siteforge-within~=\"\(rootName)\"]:not(.sf-motion-entered) { opacity:0; } }"), css)
        XCTAssertTrue(css.contains("@media screen and (prefers-reduced-motion:no-preference) { .sf-motion-ready [data-siteforge-within~=\"\(rootName)\"].sf-motion-entered { animation:sf-entrance-\(rootName) 600ms ease-out 0ms both; } }"), css)
        XCTAssertTrue(css.contains(EventGraphOutput.hiddenCSS), css)
        let release = LocalBuildProfileCompiler.compile(plan, profile: .staticRelease).0
        let releaseCSS = try XCTUnwrap(release.files.first { $0.path == "styles.css" }?.contents)
        for line in css.split(separator: "\n") where line.contains("data-siteforge-within~=") {
            XCTAssertTrue(releaseCSS.contains(StaticCSSOptimizer.minify(String(line))), String(line))
        }
        let codes = StaticBuildCompiler.compile(document: site, profileSelection: .init(profile: .development),
                                                resourceDescriptors: [:], resourceData: [:])
            .findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertFalse(codes.contains { $0.hasPrefix("interaction-container-flat") }, "\(codes)")
        XCTAssertFalse(codes.contains("overlay-unreachable:\(frameName)"), "\(codes)")

        // The runtimes: placement and flipping, menu keys, contents as part of
        // an overlay, Scrolled Into View without IntersectionObserver, reveal.
        let script = EventGraphRuntime.javascript
        for expected in ["entry.element.getAttribute('data-siteforge-placement')", "const prefersRight = (side === 'end') !== rtl;",
                         "y = side === 'below' ? (fitsBelow || !fitsAbove ? below : above) : (fitsAbove || !fitsBelow ? above : below);",
                         "for (const part of group) part.style.translate = shift;", "['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)",
                         "if (modal && !entry.flat) {", "open(target, source.matches(focusable) ? source : document.activeElement, source);",
                         "else for (const [element, lists] of entering) for (const actions of lists) run(element, actions);"] {
            XCTAssertTrue(script.contains(expected), expected)
        }
        XCTAssertTrue(MotionRuntime.javascript.contains("member.classList.add('sf-motion-entered')"))
        XCTAssertTrue(EventGraphOutput.overlayCSS.hasPrefix("[data-siteforge-overlay=\"modal\"]:not([hidden]):not([data-siteforge-flat]) {"))

        // Create Component refuses an interaction elsewhere that targets the
        // container's contents; one on the container itself is kept.
        var inbound = fixture.document
        let textIndex = try XCTUnwrap(inbound.pages[0].nodes.firstIndex { $0.id == fixture.text })
        inbound.pages[0].nodes[textIndex].properties += CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
            actions: [Action(kind: .show, target: fixture.targetText)])]).properties.sorted { $0.key < $1.key }
            .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        try inbound.validate()
        XCTAssertThrowsError(try ComponentCommandRegistry.creationSourceIDs(fixture.frame, page: inbound.pages[0], document: inbound)) {
            XCTAssertEqual($0 as? CommandExecutionError, .disabled(ComponentCommandRegistry.inboundInteractionReason))
        }
        let interactionsIndex = try XCTUnwrap(inbound.pages[0].nodes[textIndex].properties.firstIndex {
            $0.key.rawValue == CanonicalEventGraph.interactionsKey })
        inbound.pages[0].nodes[textIndex].properties[interactionsIndex].value = try XCTUnwrap(CanonicalEventGraph(interactions: [
            CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [Action(kind: .show, target: fixture.frame)])])
            .properties[CanonicalEventGraph.interactionsKey])
        XCTAssertEqual(try ComponentCommandRegistry.creationSourceIDs(fixture.frame, page: inbound.pages[0], document: inbound),
                       [fixture.frame, fixture.targetText])
    }

    // OD-039, SF-1106-001/002/003/004/005 (C6, ADR-0066): a Text shows a page
    // variable's value. The binding is one undoable edit that keeps its
    // property identity, names a variable the page has, is refused on other
    // kinds, keeps the authored text, survives save and reopen, stays out of
    // schema 26, and forged or misplaced data is rejected. Renaming or removing
    // the variable keeps the reference; the Inspector status explains it.
    func testTextValueBindingTypedValidationHistoryPersistenceAndInspectorStatus() throws {
        let fixture = try formattingFixture()
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID]) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        func node(_ id: NodeID) throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }) }
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: session.document.pages[0])).id
        let label = CanonicalStateVariable(id: UUID(), name: "Label", type: .string, initial: .string("Ready"))
        let count = CanonicalStateVariable(id: UUID(), name: "Count", type: .number, initial: .number(42))
        try session.execute(prepare(.pageVariables([label, count]), [root]).documentCommand)

        // Refusals change nothing and say why.
        let unchanged = session.document
        XCTAssertThrowsError(try prepare(.textBinding(CanonicalTextBinding(variable: UUID())), [fixture.text])) {
            XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalTextBinding.missingVariableReason))
        }
        XCTAssertThrowsError(try prepare(.textBinding(CanonicalTextBinding(variable: label.id)), [fixture.frame])) {
            XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalTextBinding.unsupportedReason))
        }
        XCTAssertThrowsError(try prepare(.textBinding(nil), [fixture.text])) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
        XCTAssertEqual(session.document, unchanged)

        // One undoable transaction; the authored text stays as the fallback.
        let before = session.document.pages
        let entries = session.historySnapshot().undoEntries.count
        try session.execute(prepare(.textBinding(CanonicalTextBinding(variable: label.id)), [fixture.text]).documentCommand)
        XCTAssertEqual(try CanonicalTextBinding.resolve(node(fixture.text)), CanonicalTextBinding(variable: label.id))
        XCTAssertEqual(try node(fixture.text).insertionStringProperty("content.text"), "Source stays unchanged")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, entries + 1)
        let bound = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, bound)
        // Re-pointing keeps the property identity; the same value again is no change.
        let propertyID = try XCTUnwrap(node(fixture.text).insertionProperty(CanonicalTextBinding.key)?.id)
        try session.execute(prepare(.textBinding(CanonicalTextBinding(variable: count.id)), [fixture.text]).documentCommand)
        XCTAssertEqual(try node(fixture.text).insertionProperty(CanonicalTextBinding.key)?.id, propertyID)
        XCTAssertThrowsError(try prepare(.textBinding(CanonicalTextBinding(variable: count.id)), [fixture.text])) {
            XCTAssertEqual($0 as? DesignInspectorError, .noChanges)
        }

        // Canonical stored text; forged, misplaced or mistyped data is refused.
        let edited = session.document
        let textIndex = try XCTUnwrap(edited.pages[0].nodes.firstIndex { $0.id == fixture.text })
        let frameIndex = try XCTUnwrap(edited.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let propertyIndex = try XCTUnwrap(edited.pages[0].nodes[textIndex].properties.firstIndex { $0.key.rawValue == CanonicalTextBinding.key })
        guard case .string(let stored) = edited.pages[0].nodes[textIndex].properties[propertyIndex].value else {
            return XCTFail("A text binding is stored as text")
        }
        XCTAssertEqual(stored, "{\"variable\":\"\(count.id.uuidString)\"}")
        for forged in [" " + stored, "{}", "[]", "not json", stored.lowercased(),
                       stored.replacingOccurrences(of: "{", with: "{\"format\":\"currency\",")] {
            var copy = edited
            copy.pages[0].nodes[textIndex].properties[propertyIndex].value = .string(forged)
            XCTAssertThrowsError(try copy.validate(), forged) { XCTAssertEqual($0 as? ModelValidationError, .invalidRuntimeState) }
        }
        var numeric = edited
        numeric.pages[0].nodes[textIndex].properties[propertyIndex].value = .number(1)
        XCTAssertThrowsError(try numeric.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidRuntimeState) }
        var misplaced = edited
        misplaced.pages[0].nodes[frameIndex].properties.append(.init(key: .init(rawValue: CanonicalTextBinding.key), value: .string(stored)))
        XCTAssertThrowsError(try misplaced.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidRuntimeState) }
        try edited.validate()

        // Formatting follows the variables' canonical text in every language.
        XCTAssertEqual([CanonicalTextBinding.displayText(.number(1_000_000)), CanonicalTextBinding.displayText(.number(-7)),
                        CanonicalTextBinding.displayText(.boolean(true)), CanonicalTextBinding.displayText(.string("A & B"))],
                       ["1000000", "-7", "true", "A & B"])
        // Inspector status: the variable, its type and starting value, or why the own text is shown.
        let status = CanonicalTextBinding.status(CanonicalTextBinding(variable: count.id), variables: [label, count])
        XCTAssertTrue(status.contains("Count (Whole Number)") && status.contains("\u{201C}42\u{201D}"), status)
        XCTAssertEqual(CanonicalTextBinding.status(CanonicalTextBinding(variable: UUID()), variables: [label, count]),
                       CanonicalTextBinding.missingStatus)

        // Renaming keeps the binding; removing the variable keeps the reference
        // (reported at build time) and only removal is offered for it.
        var renamed = count; renamed.name = "Items"
        try session.execute(prepare(.pageVariables([label, renamed]), [root]).documentCommand)
        XCTAssertEqual(try CanonicalTextBinding.resolve(node(fixture.text))?.variable, count.id)
        XCTAssertTrue(CanonicalTextBinding.status(CanonicalTextBinding(variable: count.id), variables: [label, renamed]).contains("Items"))
        try session.execute(prepare(.pageVariables([label]), [root]).documentCommand)
        XCTAssertEqual(try CanonicalTextBinding.resolve(node(fixture.text))?.variable, count.id)
        try session.document.validate()
        XCTAssertThrowsError(try prepare(.textBinding(CanonicalTextBinding(variable: count.id)), [fixture.text])) {
            XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalTextBinding.missingVariableReason))
        }

        // Persistence and the schema 27 gate.
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))

        // Removal leaves nothing behind.
        try session.execute(prepare(.textBinding(nil), [fixture.text]).documentCommand)
        XCTAssertNil(try node(fixture.text).insertionProperty(CanonicalTextBinding.key))
    }

    // SF-1106-002/003/004/006 (C6, ADR-0066): bound text is hydration-safe.
    // The static HTML already shows the variable's starting value (so the page
    // reads correctly without scripts) and names the variable for the runtime
    // with a polite live region. The variable wins over translations in every
    // language tree and over collection fields on item pages; when the page
    // has no such variable the text's own (or translated) content is written,
    // the binding is left out and Check Website reports it.
    func testTextValueBindingOutputIsHydrationSafeAcrossLanguagesItemPagesAndMissingVariables() throws {
        var fixture = try formattingFixture()
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: fixture.document.pages[0])).id
        let label = CanonicalStateVariable(id: UUID(), name: "Label", type: .string, initial: .string("Ready <now>"))
        let count = CanonicalStateVariable(id: UUID(), name: "Count", type: .number, initial: .number(-42))
        func add(_ values: [String: PropertyValue], to id: NodeID) throws {
            let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == id })
            fixture.document.pages[0].nodes[index].properties += values.sorted { $0.key < $1.key }
                .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        }
        try add(CanonicalPageState.properties(variables: [label, count]), to: root)
        try add(CanonicalTextBinding.properties(.init(variable: label.id)), to: fixture.text)
        try add(CanonicalTextBinding.properties(.init(variable: count.id)), to: fixture.targetText)
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &localization)
        fixture.document.localization = localization
        let frenchKey = PropertyKey(rawValue: SiteTranslationKey(localeID: french.id, field: .text).rawValue)
        for id in [fixture.text, fixture.targetText] {
            let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == id })
            fixture.document.pages[0].nodes[index].properties.append(NodeProperty(key: frenchKey, value: .string("Texte traduit"), origin: .authored))
        }
        try fixture.document.validate()
        func openingTag(_ id: NodeID, in html: String) throws -> String {
            let marker = try XCTUnwrap(html.range(of: "data-siteforge-node=\"\(id.description)\""), html)
            let start = try XCTUnwrap(html.range(of: "<", options: .backwards, range: html.startIndex..<marker.lowerBound)).lowerBound
            let end = try XCTUnwrap(html.range(of: ">", range: marker.upperBound..<html.endIndex)).upperBound
            return String(html[start..<end])
        }
        /// The opening tag and the text up to the next tag.
        func element(_ id: NodeID, in html: String) throws -> String {
            let tag = try openingTag(id, in: html)
            let start = try XCTUnwrap(html.range(of: tag))
            let end = try XCTUnwrap(html.range(of: "<", range: start.upperBound..<html.endIndex))
            return String(html[start.lowerBound..<end.lowerBound])
        }

        let plan = try MultiPageStaticBuildPlanner.plan(document: fixture.document)
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: fixture.document).integrityDigest, plan.integrityDigest)
        for path in ["index.html", "fr/index.html"] {
            let html = try XCTUnwrap(plan.files.first { $0.path == path }?.contents, path)
            let labelElement = try element(fixture.text, in: html), countElement = try element(fixture.targetText, in: html)
            XCTAssertTrue(labelElement.hasSuffix(">Ready &lt;now&gt;"), "\(path): \(labelElement)")
            XCTAssertTrue(countElement.hasSuffix(">-42"), "\(path): \(countElement)")
            XCTAssertTrue(labelElement.contains(" data-siteforge-text-variable=\"\(label.id.uuidString.lowercased())\" aria-live=\"polite\" aria-atomic=\"true\""), labelElement)
            XCTAssertFalse(html.contains("Texte traduit") || html.contains("Source stays unchanged") || html.contains("Target content retained"),
                           "\(path): the variable wins over the translation and the own text")
            XCTAssertTrue(html.contains("<div hidden data-siteforge-state=\""), path)
            XCTAssertTrue(html.contains("siteforge-events.js\" defer></script>"), path)
        }
        let script = EventGraphRuntime.javascript
        for expected in ["[data-siteforge-text-variable]", "element.textContent = text", "querySelector('[data-siteforge-text]') || element"] {
            XCTAssertTrue(script.contains(expected), expected)
        }
        let codes = StaticBuildCompiler.compile(document: fixture.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
            .findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertFalse(codes.contains { $0.hasPrefix("state-text-binding-missing") }, "\(codes)")

        // Collection item pages: the template is a duplicate of the page (its
        // variables keep their identities) and the item's field fills both
        // texts first; the bound one still shows the variable, the other the field.
        var site = fixture.document
        let templateID = PageID()
        let clone = try CanonicalPageGraphClone.prepare(page: site.pages[0], destinationPageID: templateID)
        site.pages.append(DocumentPage(id: templateID, name: "Post", route: .init(rawValue: "/post"), role: .standard,
            rootNodeIDs: try site.pages[0].rootNodeIDs.map { try XCTUnwrap(clone.nodeIDs[$0]) }, nodes: clone.nodes))
        let copiedLabel = try XCTUnwrap(clone.nodeIDs[fixture.text]), copiedCount = try XCTUnwrap(clone.nodeIDs[fixture.targetText])
        let templateIndex = try XCTUnwrap(site.pages.firstIndex { $0.id == templateID })
        let copiedCountIndex = try XCTUnwrap(site.pages[templateIndex].nodes.firstIndex { $0.id == copiedCount })
        site.pages[templateIndex].nodes[copiedCountIndex].properties.removeAll { $0.key.rawValue == CanonicalTextBinding.key }
        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        var first = CollectionItem(slug: "first", status: .published)
        first.setValue(.text("From the item"), for: title.id)
        posts.items = [first]
        CollectionEditing.setTemplatePage(templateID, in: &posts)
        XCTAssertTrue(CollectionEditing.setTextBinding("title", node: copiedLabel, in: &posts))
        XCTAssertTrue(CollectionEditing.setTextBinding("title", node: copiedCount, in: &posts))
        site.collections = [posts]
        try site.validate()
        let itemHTML = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: site).files.first { $0.path == "posts/first.html" }?.contents)
        XCTAssertTrue(try element(copiedLabel, in: itemHTML).hasSuffix(">Ready &lt;now&gt;"), itemHTML)
        XCTAssertTrue(try element(copiedCount, in: itemHTML).hasSuffix(">From the item"), itemHTML)

        // Without the variable: the own text (and its translation) is written,
        // the binding is left out and Check Website names the object.
        var missing = fixture.document
        let rootIndex = try XCTUnwrap(missing.pages[0].nodes.firstIndex { $0.id == root })
        let variablesIndex = try XCTUnwrap(missing.pages[0].nodes[rootIndex].properties.firstIndex { $0.key.rawValue == CanonicalPageState.variablesKey })
        missing.pages[0].nodes[rootIndex].properties[variablesIndex].value = try XCTUnwrap(CanonicalPageState.properties(variables: [count])[CanonicalPageState.variablesKey])
        try missing.validate()
        let missingPlan = try MultiPageStaticBuildPlanner.plan(document: missing)
        let english = try XCTUnwrap(missingPlan.files.first { $0.path == "index.html" }?.contents)
        let translated = try XCTUnwrap(missingPlan.files.first { $0.path == "fr/index.html" }?.contents)
        XCTAssertTrue(try element(fixture.text, in: english).hasSuffix(">Source stays unchanged"), english)
        XCTAssertTrue(try element(fixture.text, in: translated).hasSuffix(">Texte traduit"), translated)
        XCTAssertFalse(try openingTag(fixture.text, in: english).contains("data-siteforge-text-variable"))
        XCTAssertTrue(try element(fixture.targetText, in: english).hasSuffix(">-42"), english)
        let missingCodes = StaticBuildCompiler.compile(document: missing, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
            .findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertTrue(missingCodes.contains("state-text-binding-missing:\(fixture.text.description)"), "\(missingCodes)")
        XCTAssertFalse(missingCodes.contains("state-text-binding-missing:\(fixture.targetText.description)"), "\(missingCodes)")
    }

    // SF-1106-002/005 (C6, ADR-0066): copies keep the binding valid where its
    // variable exists. A duplicated page copies its variables with their
    // identities, so its bound text shows the variable; Create Component keeps
    // the binding inside the definition and the instance on the same page
    // still shows the variable. Paste: ClipboardTransferTests.
    func testTextValueBindingStaysValidThroughPageDuplicateAndCreateComponent() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id, root = document.pages[0].rootNodeIDs[0]
        let label = CanonicalStateVariable(id: UUID(), name: "Label", type: .string, initial: .string("Ready"))
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].properties += CanonicalPageState.properties(variables: [label])
            .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        func layout(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)]
                .map { NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1)) }
        }
        var card = DocumentNode(kind: .frame, name: "Card", parent: .node(root), properties: layout(40, 40, 300, 120))
        let text = DocumentNode(kind: .text, name: "Status", parent: .node(card.id), properties: layout(60, 60, 200, 40)
            + [NodeProperty(key: .init(rawValue: "content.text"), value: .string("Own text"))]
            + CanonicalTextBinding.properties(.init(variable: label.id)).map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) })
        card.childIDs = [text.id]
        document.pages[0].nodes[rootIndex].childIDs.append(card.id)
        document.pages[0].nodes += [card, text]
        try document.validate()

        // Page duplicate (CanonicalPageGraphClone, as Duplicate Page uses it).
        let copyID = PageID()
        let clone = try CanonicalPageGraphClone.prepare(page: document.pages[0], destinationPageID: copyID)
        let copiedText = try XCTUnwrap(clone.nodes.first { $0.id == clone.nodeIDs[text.id] })
        XCTAssertEqual(try CanonicalTextBinding.resolve(copiedText), CanonicalTextBinding(variable: label.id))
        let copy = DocumentPage(id: copyID, name: "Copy", route: .init(rawValue: "/copy"), role: .standard,
            rootNodeIDs: try document.pages[0].rootNodeIDs.map { try XCTUnwrap(clone.nodeIDs[$0]) }, nodes: clone.nodes)
        XCTAssertEqual(CanonicalPageState.variables(on: copy), [label], "The copy's variables keep their identities")
        XCTAssertFalse(EventGraphOutput.findings(copy, availablePageIDs: [copyID]).contains { $0.code == "state-text-binding-missing" })
        XCTAssertEqual(CanonicalTextBinding.outputPage(copy).nodes.first { $0.id == copiedText.id }?.insertionStringProperty("content.text"), "Ready")

        // Create Component on the same page, then component expansion.
        let session = DocumentSession(document: document), scene = CanvasViewportSceneID()
        let prepared = try ComponentCommandRegistry().prepare(.create(card.id), identity: .init(
            documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: scene, rendererGeneration: document.revision), in: document,
            context: .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: document.revision,
                selectedNodeIDs: [card.id], availableNodeIDs: [card.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        try session.execute(prepared.command)
        try session.document.validate()
        let definition = try XCTUnwrap(session.document.componentDefinitions.first)
        let source = try XCTUnwrap(definition.nodes.first { $0.kind == .text })
        XCTAssertEqual(try CanonicalTextBinding.resolve(source), CanonicalTextBinding(variable: label.id), "The definition keeps the binding")
        let page = try XCTUnwrap(session.document.pages.first { $0.id == pageID })
        let resolved = try ComponentGraphResolver.resolvedPage(page, in: session.document, breakpoint: .desktop)
        let expanded = try XCTUnwrap(resolved.nodes.first { $0.kind == .text && (try? CanonicalTextBinding.resolve($0)) != nil })
        XCTAssertEqual(try CanonicalTextBinding.resolve(expanded)?.variable, label.id)
        XCTAssertFalse(EventGraphOutput.findings(resolved, availablePageIDs: [pageID]).contains { $0.code == "state-text-binding-missing" })
        let html = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document).files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("data-siteforge-text-variable=\"\(label.id.uuidString.lowercased())\""), html)
        XCTAssertTrue(html.contains(">Ready</"), html)
        XCTAssertFalse(html.contains("Own text"), html)
    }

    // OD-039, SF-1101-001/002/003/005/006 (C7, ADR-0066): key-press triggers
    // (Enter, Escape, arrow keys) are typed triggers of the event graph. They
    // are one undoable edit, persist, compile to the fixed runtime and run only
    // while their own object has keyboard focus: buttons and links have it; any
    // other object is added to the Tab order with a warning. A key press is
    // keyboard access for pointer interactions. The page overview lists every
    // trigger and its actions in Layers order, with missing targets counted.
    func testKeyPressTriggersFocusabilityOutputAndPageInteractionsOverview() throws {
        typealias Action = CanonicalInteraction.Action
        let fixture = try formattingFixture()
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID]) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        func node(_ id: NodeID) throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }) }
        XCTAssertEqual(CanonicalInteraction.Trigger.allCases.compactMap(\.keyboardKey), ["Enter", "Escape", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"])
        XCTAssertEqual(CanonicalInteraction.Trigger.keyArrowDown.rawValue, "key-arrow-down")
        let enter = CanonicalInteraction(id: UUID(), trigger: .keyEnter, actions: [Action(kind: .show, target: fixture.targetFrame)])
        let escape = CanonicalInteraction(id: UUID(), trigger: .keyEscape, actions: [Action(kind: .hide, target: fixture.targetFrame)])
        let pointer = CanonicalInteraction(id: UUID(), trigger: .pointerEnter, actions: [Action(kind: .toggle, target: fixture.targetFrame)])
        let graph = CanonicalEventGraph(interactions: [enter, escape, pointer])
        XCTAssertTrue(graph.isValid)
        XCTAssertTrue(graph.isAllowed(on: .frame), "The website makes other objects focusable for key presses")

        // One undoable transaction per edit.
        let before = session.document.pages
        try session.execute(prepare(.events(graph), [fixture.frame]).documentCommand)
        XCTAssertEqual(try CanonicalEventGraph.resolve(node(fixture.frame)), graph)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let after = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, after)
        try session.execute(prepare(.events(CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .keyArrowDown,
            actions: [Action(kind: .focus, target: fixture.frame)])])), [fixture.text]).documentCommand)

        // An unknown key is not a trigger; persistence keeps the key triggers.
        let frameIndex = try XCTUnwrap(session.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let propertyIndex = try XCTUnwrap(session.document.pages[0].nodes[frameIndex].properties.firstIndex { $0.key.rawValue == CanonicalEventGraph.interactionsKey })
        guard case .string(let stored) = session.document.pages[0].nodes[frameIndex].properties[propertyIndex].value else {
            return XCTFail("Interactions are stored as text")
        }
        XCTAssertTrue(stored.contains("\"trigger\":\"key-enter\""), stored)
        for forged in [stored.replacingOccurrences(of: "key-enter", with: "key-space"), stored.replacingOccurrences(of: "key-escape", with: "keydown")] {
            var copy = session.document
            copy.pages[0].nodes[frameIndex].properties[propertyIndex].value = .string(forged)
            XCTAssertThrowsError(try copy.validate(), forged) { XCTAssertEqual($0 as? ModelValidationError, .invalidInteractionGraphState) }
        }
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)

        // Output: a button keeps its own focus; a frame and a text join the Tab order.
        var document = session.document
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: document.pages[0])).id
        let buttonValues: [String: PropertyValue] = ["layout.x": .number(20), "layout.y": .number(400), "layout.width": .number(120),
                                                     "layout.height": .number(40), CanonicalLinkTarget.labelKey: .string("Go")]
        let buttonGraph = CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .keyEnter,
            actions: [Action(kind: .show, target: fixture.targetFrame)])])
        let button = DocumentNode(kind: .button, name: "Go", parent: .node(root),
            properties: buttonValues.merging(buttonGraph.properties) { first, _ in first }.sorted { $0.key < $1.key }
                .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) })
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].childIDs.append(button.id)
        document.pages[0].nodes.append(button)
        try document.validate()
        let output = try EventGraphOutput.page(document.pages[0], staticRoutes: [:], prefix: "")
        XCTAssertEqual(output.attributes[fixture.frame], " tabindex=\"0\"")
        XCTAssertEqual(output.attributes[fixture.text], " tabindex=\"0\"")
        XCTAssertNil(output.attributes[button.id], "A button already has keyboard focus")
        let configurations = try JSONDecoder().decode([EventOutputConfiguration].self,
            from: Data(try XCTUnwrap(output.configurations[fixture.frame]).utf8))
        XCTAssertEqual(configurations.map(\.trigger), ["key-enter", "key-escape", "pointer-enter"])
        XCTAssertEqual(configurations.first?.actions, [EventOutputConfiguration.Action(kind: "show", target: fixture.targetFrame.description)])
        let html = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: document).files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("class=\"sf-node-\(fixture.frame.description)\" tabindex=\"0\""), html)
        XCTAssertTrue(html.contains("<script src=\"siteforge-events.js\" defer></script>"), html)
        let codes = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
            .findings.map { "\($0.code):\($0.affectedNodeID?.description ?? "")" }
        XCTAssertTrue(codes.contains("interaction-key-focus-added:\(fixture.frame.description)"), "\(codes)")
        XCTAssertTrue(codes.contains("interaction-key-focus-added:\(fixture.text.description)"), "\(codes)")
        XCTAssertFalse(codes.contains("interaction-key-focus-added:\(button.id.description)"), "\(codes)")
        XCTAssertFalse(codes.contains("interaction-pointer-only:\(fixture.frame.description)"), "A key press is keyboard access: \(codes)")
        let script = EventGraphRuntime.javascript
        for expected in ["'key-enter': 'Enter'", "'key-arrow-right': 'ArrowRight'", "event.target !== element", "event.isComposing",
                         "if (key.startsWith('Arrow')) event.preventDefault();", "!event.defaultPrevented",
                         "element.setAttribute('aria-haspopup', 'dialog');", "entry.backdrop.setAttribute('aria-hidden', 'true');",
                         "opener.tagName === 'A'"] {
            XCTAssertTrue(script.contains(expected), expected)
        }

        // Page overview: Layers order, then each object's order; names authors see.
        let summaries = PageInteractionOverview.summaries(document.pages[0], websitePages: document.websitePages)
        XCTAssertEqual(summaries.map(\.nodeID), [fixture.text, fixture.frame, fixture.frame, fixture.frame, button.id])
        XCTAssertEqual(summaries.map(\.trigger), [.keyArrowDown, .keyEnter, .keyEscape, .pointerEnter, .keyEnter])
        XCTAssertEqual(summaries[0].actions, ["Move Focus To Source appearance"])
        XCTAssertEqual(summaries[1].actions, ["Show Target appearance"])
        XCTAssertEqual(summaries[1].accessibilityLabel, "Source appearance, Enter Key Pressed: Show Target appearance")
        XCTAssertEqual(Set(summaries.map(\.id)).count, summaries.count)
        XCTAssertEqual(summaries.map(\.unavailableActions), [0, 0, 0, 0, 0])
        var orphaned = document
        orphaned.pages[0].nodes.removeAll { $0.id == fixture.targetFrame }
        let orphanedRoot = try XCTUnwrap(orphaned.pages[0].nodes.firstIndex { $0.id == root })
        orphaned.pages[0].nodes[orphanedRoot].childIDs.removeAll { $0 == fixture.targetFrame }
        let orphanedSummaries = PageInteractionOverview.summaries(orphaned.pages[0], websitePages: orphaned.websitePages)
        XCTAssertEqual(orphanedSummaries.map(\.unavailableActions), [0, 1, 1, 1, 1])
        XCTAssertEqual(orphanedSummaries[1].actions, ["Show (missing object)"])
        XCTAssertTrue(orphanedSummaries[1].accessibilityLabel.hasSuffix(". 1 action cannot run"), orphanedSummaries[1].accessibilityLabel)
        XCTAssertEqual(PageInteractionOverview.describe(Action(kind: .navigate, page: PageID()), names: [:], pageNames: [:], variables: [:]),
                       "Go To Page (missing page)")
        XCTAssertEqual(PageInteractionOverview.describe(Action(kind: .setVariable, variable: UUID(), value: .number(3)), names: [:],
                                                        pageNames: [:], variables: [:]), "Set (missing variable) to 3")
        XCTAssertTrue(PageInteractionOverview.summaries(try formattingFixture().document.pages[0], websitePages: []).isEmpty)
    }

    // SF-1101-007, SF-1103-007, SF-1104-007, SF-1105-007, SF-1106-007 (lane C
    // 007, ADR-0066): validation, one Inspector edit, interaction and motion
    // output, Check Website findings, the page overview and a full build stay
    // within generous safety bounds on the standard (100) and large (10,000
    // objects) fixtures with motion, interactions, key presses, a page-long
    // focus loop, visibility conditions, text bindings and overlays. The bounds
    // catch accidental quadratic work (focus-loop detection is linear), not
    // machine speed.
    func testMotionAndInteractionChecksAndOutputStayWithinBoundsOnStandardAndLargeFixtures() throws {
        executionTimeAllowance = 180
        continueAfterFailure = false
        typealias Action = CanonicalInteraction.Action
        let clock = ContinuousClock()
        for (count, bound) in [(100, Duration.seconds(10)), (10_000, .seconds(120))] {
            var document = ProjectCreation.blank()
            let root = document.pages[0].rootNodeIDs[0]
            let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
            let open = CanonicalStateVariable(id: UUID(), name: "Open", type: .boolean, initial: .boolean(false))
            let label = CanonicalStateVariable(id: UUID(), name: "Label", type: .string, initial: .string("Ready"))
            document.pages[0].nodes[rootIndex].properties += CanonicalPageState.properties(variables: [open, label])
                .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
            let ids = (0..<count).map { _ in NodeID() }
            // Every tenth object is a popover; the others are texts in one page-long Focus In loop.
            let texts = ids.indices.filter { !$0.isMultiple(of: 10) }
            let positions = Dictionary(uniqueKeysWithValues: texts.enumerated().map { ($0.element, $0.offset) })
            var nodes: [DocumentNode] = []
            for index in ids.indices {
                var values: [String: PropertyValue] = ["layout.x": .number(Double(index % 40) * 30), "layout.y": .number(Double(index / 40) * 30),
                                                       "layout.width": .number(28), "layout.height": .number(28)]
                if index.isMultiple(of: 3) {
                    values.merge(CanonicalMotion(transition: CanonicalMotion.defaultTransition, entrance: CanonicalMotion.defaultEntrance).properties) { first, _ in first }
                }
                if index.isMultiple(of: 10) {
                    values.merge(CanonicalOverlay(kind: .popover, dismissesOnOutsideClick: true, placement: .below).properties) { first, _ in first }
                } else {
                    let position = try XCTUnwrap(positions[index])
                    let next = ids[texts[(position + 1) % texts.count]]
                    var pressed = [Action(kind: .setVariable, variable: label.id, value: .string("Go"))]
                    if (index + 1).isMultiple(of: 10), index + 1 < count { pressed.append(Action(kind: .openOverlay, target: ids[index + 1])) }
                    values.merge(CanonicalEventGraph(interactions: [
                        CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [Action(kind: .show, target: next), Action(kind: .focus, target: next)]),
                        CanonicalInteraction(id: UUID(), trigger: .keyEnter, actions: pressed),
                        CanonicalInteraction(id: UUID(), trigger: .keyEscape, actions: [Action(kind: .toggleVariable, variable: open.id)]),
                    ]).properties) { first, _ in first }
                    values["content.text"] = .string("Item \(index)")
                    if index.isMultiple(of: 5) { values.merge(CanonicalTextBinding.properties(.init(variable: label.id))) { first, _ in first } }
                    if index.isMultiple(of: 7) {
                        values.merge(CanonicalPageState.properties(condition: .init(variable: open.id, equals: .boolean(false)))) { first, _ in first }
                    }
                }
                nodes.append(DocumentNode(id: ids[index], kind: index.isMultiple(of: 10) ? .frame : .text, name: "Item \(index)", parent: .node(root),
                    properties: values.sorted { $0.key < $1.key }.map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }))
            }
            document.pages[0].nodes[rootIndex].childIDs += ids
            document.pages[0].nodes += nodes
            let boundTexts = texts.filter { $0.isMultiple(of: 5) }.count

            let started = clock.now
            try document.validate()
            let page = document.pages[0]
            let output = try EventGraphOutput.page(page, staticRoutes: [:], prefix: "")
            let findings = EventGraphOutput.findings(page, availablePageIDs: [page.id])
            let motion = try MotionOutput.css(page.nodes) + FlatContainerOutput.css([page])
            let summaries = PageInteractionOverview.summaries(page, websitePages: document.websitePages)
            let written = CanonicalTextBinding.outputPage(page)
            let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id, revision: document.revision,
                sceneID: CanvasViewportSceneID(), rendererGeneration: document.revision)
            let edit = try DecorativeEffectCommandRegistry.prepare(.textBinding(nil), identity: identity, orderedNodeIDs: [ids[5]], document: document,
                context: .init(activePageID: page.id, currentSceneID: identity.sceneID, rendererGeneration: document.revision,
                    selectedNodeIDs: [ids[5]], availableNodeIDs: Set(page.nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil))
            let plan = try MultiPageStaticBuildPlanner.plan(document: document)
            XCTAssertLessThan(started.duration(to: clock.now), bound, "\(count) objects: safety bound only")

            XCTAssertEqual(output.configurations.count, texts.count)
            XCTAssertEqual(output.attributes.values.filter { $0.contains("data-siteforge-text-variable") }.count, boundTexts)
            XCTAssertEqual(output.attributes.values.filter { $0.contains("tabindex=\"0\"") }.count, texts.count)
            XCTAssertEqual(findings.filter { $0.code == "interaction-focus-loop" }.count, texts.count, "\(count): one page-long loop")
            XCTAssertEqual(findings.filter { $0.code == "interaction-key-focus-added" }.count, texts.count)
            XCTAssertFalse(findings.contains { $0.code == "interaction-target-missing" || $0.code == "state-text-binding-missing" })
            XCTAssertEqual(summaries.count, texts.count * 3)
            XCTAssertEqual(written.nodes.filter { $0.insertionStringProperty("content.text") == "Ready" }.count, boundTexts)
            XCTAssertFalse(motion.isEmpty)
            XCTAssertEqual(edit.applicableNodeIDs, [ids[5]])
            XCTAssertTrue(plan.files.contains { $0.path == "siteforge-events.js" })
        }
    }

    // SF-1101-008, SF-1104-004/006/008, SF-1105-002/006/008 (C10, ADR-0065):
    // the interaction and motion runtimes run in an owned headless browser
    // against actual compiled output (Tests/Tooling/interaction_runtime_browser.py,
    // which reuses the Flow harness's owned Chrome, loopback DevTools client and
    // loopback server). Pure helper checks run first so a helper defect cannot
    // pass as a browser result. The ledger and captures attach.
    func testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal() throws {
        let root = interactionBrowserToolingRoot
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        let sites = folder.appendingPathComponent("sites", isDirectory: true)
        let captures = folder.appendingPathComponent("captures", isDirectory: true)
        let report = folder.appendingPathComponent("interaction-runtime-browser-report.json")
        let plan = try MultiPageStaticBuildPlanner.plan(document: interactionBrowserFixture())
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-events.js" && $0.contents == EventGraphRuntime.javascript })
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-motion.js" && $0.contents == MotionRuntime.javascript })
        XCTAssertTrue(plan.binaryFiles.isEmpty)
        for file in plan.files {
            let components = file.path.split(separator: "/")
            guard !file.path.isEmpty, !file.path.hasPrefix("/"), !components.contains(".."), !components.contains(".") else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let destination = sites.appendingPathComponent("interactions/" + file.path)
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: destination)
        }
        func python(_ arguments: [String]) throws -> (status: Int32, output: Data) {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.currentDirectoryURL = root
            process.arguments = arguments
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, output)
        }
        let helpers = try python([root.appendingPathComponent("Tests/Tooling/test_interaction_runtime_browser.py").path])
        let helperLog = XCTAttachment(data: helpers.output, uniformTypeIdentifier: "public.plain-text")
        helperLog.name = "Interaction runtime harness helper checks"; helperLog.lifetime = .keepAlways; add(helperLog)
        XCTAssertEqual(helpers.status, 0, String(data: helpers.output, encoding: .utf8) ?? "Helper checks failed")
        let browser = try python([root.appendingPathComponent("Tests/Tooling/interaction_runtime_browser.py").path,
            "--root", sites.path, "--report", report.path, "--captures", captures.path])
        let log = XCTAttachment(data: browser.output, uniformTypeIdentifier: "public.plain-text")
        log.name = "Interaction runtime actual browser log"; log.lifetime = .keepAlways; add(log)
        if let data = try? Data(contentsOf: report) {
            let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            receipt.name = "Interaction runtime actual browser case ledger"; receipt.lifetime = .keepAlways; add(receipt)
        }
        let images = (try? files.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil)) ?? []
        for image in images.filter({ $0.pathExtension == "png" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let attachment = XCTAttachment(data: try Data(contentsOf: image), uniformTypeIdentifier: "public.png")
            attachment.name = "Interaction runtime capture " + image.lastPathComponent; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(browser.status, 0, String(data: browser.output, encoding: .utf8) ?? "Browser checks failed")
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [String: Any])
        let cases = try XCTUnwrap(result["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.compactMap { $0["case"] as? String }, Self.interactionBrowserCases)
        for entry in cases where entry["outcome"] as? String != "passed" {
            XCTFail("\(entry["case"] ?? "case"): \(entry["detail"] ?? "failed")")
        }
        XCTAssertEqual(result["failed"] as? Int, 0)
        XCTAssertEqual(result["passed"] as? Int, Self.interactionBrowserCases.count)
    }

    /// Case names of Tests/Tooling/interaction_runtime_browser.py, in order.
    private static let interactionBrowserCases = [
        "runtimes-load-from-the-site", "modal-opens-centred-with-backdrop-and-focus", "modal-keeps-tab-focus-inside",
        "escape-closes-modal-and-restores-focus", "menu-opens-below-trigger-and-arrow-keys-move",
        "menu-flips-above-at-viewport-edge", "reveal-on-scroll-includes-container-contents",
        "reduced-motion-and-no-javascript-keep-content-visible",
        "key-press-runs-only-on-the-focused-object", "bound-text-starts-with-value-and-follows-variable",
        "openers-announce-popup-and-expanded-state",
    ]

    /// Tooling inputs prepared beside the products (owner-local testing), else
    /// the checkout (hosted or direct XCTest), as for the Flow browser test.
    private var interactionBrowserToolingRoot: URL {
        if let prepared = Bundle.main.object(forInfoDictionaryKey: "SiteForgeTestToolingRoot") as? String {
            return URL(fileURLWithPath: prepared, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// C10 fixture on a static-layout page: "Open dialog" opens a modal whose
    /// two buttons are its contents; "Open menu" opens a menu placed below it
    /// with three buttons; a container far down the page reveals on scroll
    /// with its text. C6/C7 (ADR-0066): a "Key panel" frame (added to the Tab
    /// order by the website) sets variables on Enter, Down Arrow and Escape, and
    /// two texts show those variables. Labels and values match
    /// Tests/Tooling/interaction_runtime_browser.py.
    private func interactionBrowserFixture() throws -> CanonicalDocument {
        typealias Action = CanonicalInteraction.Action
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        func node(_ kind: NodeKind, _ name: String, parent: NodeID, _ box: (Double, Double, Double, Double),
                  _ values: [String: PropertyValue] = [:]) -> DocumentNode {
            var all = values
            all["layout.x"] = .number(box.0); all["layout.y"] = .number(box.1)
            all["layout.width"] = .number(box.2); all["layout.height"] = .number(box.3)
            if kind == .button { all[CanonicalLinkTarget.labelKey] = .string(name) }
            return DocumentNode(kind: kind, name: name, parent: .node(parent),
                                properties: all.sorted { $0.key < $1.key }.map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) })
        }
        func opener(_ label: String, _ box: (Double, Double, Double, Double), opens target: NodeID) -> DocumentNode {
            node(.button, label, parent: root, box, CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .click,
                actions: [Action(kind: .openOverlay, target: target)])]).properties)
        }
        func dismissButton(_ label: String, _ box: (Double, Double, Double, Double), overlay: NodeID) -> DocumentNode {
            node(.button, label, parent: overlay, box, CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .click,
                actions: [Action(kind: .closeOverlay, target: overlay)])]).properties)
        }
        var modal = node(.frame, "Dialog", parent: root, (520, 300, 400, 200), CanonicalOverlay(kind: .modal, dismissesOnOutsideClick: true).properties)
        let confirm = dismissButton("Confirm", (560, 420, 140, 40), overlay: modal.id)
        let cancel = dismissButton("Cancel", (740, 420, 140, 40), overlay: modal.id)
        modal.childIDs = [confirm.id, cancel.id]
        var menu = node(.frame, "Menu", parent: root, (900, 100, 200, 150),
                        CanonicalOverlay(kind: .menu, dismissesOnOutsideClick: true, placement: .below).properties)
        let items = [("First", 110.0), ("Second", 155.0), ("Third", 200.0)].map {
            dismissButton($0.0, (920, $0.1, 160, 36), overlay: menu.id)
        }
        menu.childIDs = items.map(\.id)
        var reveal = node(.frame, "Reveal", parent: root, (40, 2000, 600, 200), CanonicalMotion(entrance: CanonicalMotion.defaultEntrance).properties)
        let revealText = node(.text, "Revealed text", parent: reveal.id, (60, 2040, 400, 80), ["content.text": .string("Revealed with its container")])
        reveal.childIDs = [revealText.id]
        let openDialog = opener("Open dialog", (40, 40, 160, 40), opens: modal.id)
        let openMenu = opener("Open menu", (40, 560, 160, 40), opens: menu.id)
        let status = CanonicalStateVariable(id: UUID(), name: "Status", type: .string, initial: .string("Ready"))
        let step = CanonicalStateVariable(id: UUID(), name: "Step", type: .number, initial: .number(0))
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].properties += CanonicalPageState.properties(variables: [status, step])
            .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        let keyPanel = node(.frame, "Key panel", parent: root, (40, 120, 300, 60), CanonicalEventGraph(interactions: [
            CanonicalInteraction(id: UUID(), trigger: .keyEnter, actions: [Action(kind: .setVariable, variable: status.id, value: .string("Entered"))]),
            CanonicalInteraction(id: UUID(), trigger: .keyArrowDown, actions: [Action(kind: .setVariable, variable: step.id, value: .number(2))]),
            CanonicalInteraction(id: UUID(), trigger: .keyEscape, actions: [Action(kind: .setVariable, variable: status.id, value: .string("Escaped"))]),
        ]).properties)
        let statusText = node(.text, "Status text", parent: root, (40, 200, 300, 40),
            ["content.text": PropertyValue.string("Status")].merging(CanonicalTextBinding.properties(.init(variable: status.id))) { first, _ in first })
        let stepText = node(.text, "Step text", parent: root, (40, 260, 300, 40),
            ["content.text": PropertyValue.string("Step")].merging(CanonicalTextBinding.properties(.init(variable: step.id))) { first, _ in first })
        document.pages[0].nodes[0].childIDs += [openDialog.id, modal.id, openMenu.id, menu.id, reveal.id, keyPanel.id, statusText.id, stepText.id]
        document.pages[0].nodes += [openDialog, modal, confirm, cancel, openMenu, menu] + items + [reveal, revealText, keyPanel, statusText, stepText]
        try document.validate()
        XCTAssertFalse(document.pages[0].usesConnectedOutput, "The browser fixture uses static layout")
        return document
    }

    // OD-040, SF-1103-003/006/007, SF-1104-003/004/006/007: output is CSS-first
    // and deterministic, sits behind prefers-reduced-motion, hides content only
    // once the runtime marks the page ready, ships the runtime only for reveal
    // nodes, and every motion CSS line survives the release profile.
    func testMotionOutputIsReducedMotionSafeProgressiveDeterministicAndReleaseStable() throws {
        var fixture = try formattingFixture()
        let frameIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        let textIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.text })
        var entrance = CanonicalMotion.defaultEntrance
        entrance.offsetPercent = 20; entrance.delayMilliseconds = 150
        let reveal = CanonicalMotion(entrance: entrance)
        let hover = CanonicalMotion(transition: CanonicalMotion.Transition(milliseconds: 250, easing: .easeInOut))
        fixture.document.pages[0].nodes[frameIndex].properties += reveal.properties.sorted { $0.key < $1.key }
            .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        fixture.document.pages[0].nodes[textIndex].properties += hover.properties.sorted { $0.key < $1.key }
            .map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        try fixture.document.validate()

        let plan = try MultiPageStaticBuildPlanner.plan(document: fixture.document)
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: fixture.document).integrityDigest, plan.integrityDigest)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let frame = fixture.frame.description, text = fixture.text.description
        XCTAssertTrue(html.contains(" data-siteforge-entrance=\"20\" data-siteforge-node=\"\(frame)\""), html)
        XCTAssertEqual(html.components(separatedBy: "data-siteforge-entrance=").count, 2, html)
        XCTAssertTrue(html.contains("<script src=\"siteforge-motion.js\" defer></script>"), html)
        XCTAssertTrue(html.contains("styles.css"), html)
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-motion.js" && $0.contents == MotionRuntime.javascript })
        XCTAssertTrue(css.contains("@keyframes sf-entrance-\(frame) { from { opacity:0;transform:translate3d(0,24px,0); } }"), css)
        XCTAssertTrue(css.contains("@media screen and (prefers-reduced-motion:no-preference) { .sf-motion-ready .sf-node-\(frame)[data-siteforge-entrance]:not(.sf-motion-entered) { opacity:0; } }"), css)
        XCTAssertTrue(css.contains("{ .sf-motion-ready .sf-node-\(frame).sf-motion-entered { animation:sf-entrance-\(frame) 600ms ease-out 150ms both; } }"), css)
        XCTAssertTrue(css.contains("@media (prefers-reduced-motion:no-preference) { .sf-node-\(text) { transition-property:background-color,opacity; transition-duration:250ms; transition-timing-function:ease-in-out; } }"), css)
        XCTAssertFalse(css.contains("sf-entrance-\(text)"), css)
        // Every motion rule is a single gated line, so nothing hides content
        // outside `prefers-reduced-motion:no-preference`, and Static Release,
        // which minifies whole rules (ADR-0120), keeps each line's minified form.
        let motionLines = css.split(separator: "\n").filter { $0.contains("sf-motion") || $0.contains("sf-entrance") || $0.contains("transition-property") }
        XCTAssertEqual(motionLines.count, 4)
        for line in motionLines {
            XCTAssertTrue(line.hasPrefix("@media") || line.hasPrefix("@keyframes"), String(line))
            XCTAssertTrue(line.hasPrefix("@keyframes") || line.contains("prefers-reduced-motion:no-preference"), String(line))
            XCTAssertEqual(line.filter { $0 == "{" }.count, line.filter { $0 == "}" }.count, String(line))
        }
        let release = LocalBuildProfileCompiler.compile(plan, profile: .staticRelease).0
        let releaseCSS = try XCTUnwrap(release.files.first { $0.path == "styles.css" }?.contents)
        for line in motionLines { XCTAssertTrue(releaseCSS.contains(StaticCSSOptimizer.minify(String(line))), String(line)) }

        // The runtime is fixed SiteForge code: it reveals immediately with
        // Reduce Motion or without IntersectionObserver, on keyboard focus and
        // at the end of the page; it has no author text or network access.
        let script = MotionRuntime.javascript
        XCTAssertTrue(script.contains("matchMedia('(prefers-reduced-motion: reduce)')"))
        XCTAssertTrue(script.contains("typeof IntersectionObserver !== 'function'"))
        XCTAssertTrue(script.contains("document.addEventListener('focusin', focus, true)"))
        XCTAssertTrue(script.contains("document.documentElement.scrollHeight - 2"))
        for forbidden in ["eval(", "innerHTML", "fetch(", "XMLHttpRequest", "localStorage"] { XCTAssertFalse(script.contains(forbidden), forbidden) }

        // A transition alone links the stylesheet without the runtime; no
        // motion at all leaves no motion output.
        var hoverOnly = fixture.document
        hoverOnly.pages[0].nodes[frameIndex].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalMotion.prefix) }
        let hoverPlan = try MultiPageStaticBuildPlanner.plan(document: hoverOnly)
        let hoverHTML = try XCTUnwrap(hoverPlan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(hoverHTML.contains("styles.css"), hoverHTML)
        XCTAssertFalse(hoverHTML.contains("siteforge-motion.js"), hoverHTML)
        XCTAssertFalse(hoverPlan.files.contains { $0.path == "siteforge-motion.js" })
        var still = hoverOnly
        still.pages[0].nodes[textIndex].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalMotion.prefix) }
        let plain = try MultiPageStaticBuildPlanner.plan(document: still)
        XCTAssertFalse(plain.files.contains { $0.path == "siteforge-motion.js" || $0.contents.contains("sf-entrance")
            || $0.contents.contains("data-siteforge-entrance") || $0.contents.contains("transition-property") })
    }

    // SF-0508-004, SF-1101-003/004, SF-1204-003/004: Flow eligibility follows
    // the resolved enabled fill stack (disabled layers ignored, at most 64
    // stops); disabled intent is retained without runtime output; preflight
    // enforces four enabled flows per page; and the emitted configuration is
    // escaped numeric data whose angle matches the static CSS gradient.
    func testFlowEligibilityDisabledIntentPageBudgetAndEscapedOutputConfiguration() throws {
        let fixture = try formattingFixture()
        let root = fixture.document.pages[0].rootNodeIDs[0]
        let red = CanonicalSolidColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = CanonicalSolidColor(red: 0, green: 0, blue: 1, alpha: 1)
        func gradient(angle: Double, stops count: Int = 2) -> CanonicalFillLayer {
            .linearGradient(angleDegrees: angle, stops: (0..<count).map {
                CanonicalGradientStop(id: .init(), position: Double($0) / Double(count - 1), color: $0.isMultiple(of: 2) ? red : blue)
            })
        }
        func properties(_ values: [String: PropertyValue]) -> [NodeProperty] {
            values.sorted { $0.key < $1.key }.map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        }
        func replacingFill(_ node: DocumentNode, _ layers: [CanonicalFillLayer]) -> DocumentNode {
            var copy = node
            copy.properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalFillLayerCodec.namespaceRoot) }
            copy.properties += properties(CanonicalFillLayerCodec.propertyValues(for: layers))
            return copy
        }
        let source = try XCTUnwrap(fixture.document.pages[0].nodes.first { $0.id == fixture.frame })
        XCTAssertNil(CanonicalFlowGradient.gradient(on: source), "Two enabled layers are not one flowing gradient")
        let diagonal = gradient(angle: -45)
        let withDisabled = replacingFill(source, [.solid(color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), isEnabled: false), diagonal])
        XCTAssertEqual(CanonicalFlowGradient.gradient(on: withDisabled)?.id, diagonal.id)
        XCTAssertNotNil(CanonicalFlowGradient.gradient(on: replacingFill(source, [gradient(angle: 0, stops: 64)])))
        XCTAssertNil(CanonicalFlowGradient.gradient(on: replacingFill(source, [gradient(angle: 0, stops: 65)])))
        XCTAssertNil(CanonicalFlowGradient.gradient(on: replacingFill(source, [.solid(color: red)])))

        // Enabling on an ineligible fill is refused; disabled intent is kept
        // as authored data and produces no runtime, attribute or finding.
        let session = DocumentSession(document: fixture.document)
        func prepare(_ edit: DecorativeEffectEdit, _ ids: [NodeID]) throws -> PreparedDesignInspectorEdit {
            let document = session.document, page = document.pages[0]
            return try DecorativeEffectCommandRegistry.prepare(edit,
                identity: .init(documentID: document.id, pageID: page.id, revision: document.revision,
                    sceneID: fixture.scene, rendererGeneration: document.revision),
                orderedNodeIDs: ids, document: document,
                context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                    selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)),
                    isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        let unchanged = session.document
        XCTAssertThrowsError(try prepare(.flow(.defaults), [fixture.frame])) {
            XCTAssertEqual($0 as? DesignInspectorError, .unavailable(CanonicalFlowGradient.unavailableReason))
        }
        XCTAssertEqual(session.document, unchanged)
        var disabled = CanonicalFlowGradient.defaults; disabled.enabled = false
        try session.execute(prepare(.flow(disabled), [fixture.frame]).documentCommand)
        let frame = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.frame })
        XCTAssertEqual(try CanonicalFlowGradient.resolve(frame), disabled)
        XCTAssertNil(try DecorativeEffectOutput.configuration(frame))
        let retained = try MultiPageStaticBuildPlanner.plan(document: session.document)
        XCTAssertFalse(retained.files.contains { $0.path == "siteforge-effects.js" })
        XCTAssertFalse(retained.files.contains { $0.contents.contains("data-siteforge-flow") })
        XCTAssertFalse(StaticBuildCompiler.compile(document: session.document, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:]).findings.contains { $0.code == "flow-configuration-unavailable" })

        // Page budget: four enabled flows compile; a fifth is an actionable
        // preflight error rather than a silently dropped effect.
        var budget = fixture.document
        var flowIDs: [NodeID] = []
        for offset in 0..<5 {
            var values = CanonicalFillLayerCodec.propertyValues(for: [gradient(angle: offset == 0 ? -45 : 90)])
            for (key, value) in CanonicalFlowGradient.defaults.properties { values[key] = value }
            values["layout.x"] = .number(20 + Double(offset) * 130); values["layout.y"] = .number(420)
            values["layout.width"] = .number(120); values["layout.height"] = .number(80)
            let node = DocumentNode(kind: .frame, name: "Flow \(offset)", parent: .node(root), properties: properties(values))
            budget.pages[0].nodes.append(node)
            budget.pages[0].nodes[0].childIDs.append(node.id)
            flowIDs.append(node.id)
        }
        try budget.validate()
        let over = StaticBuildCompiler.compile(document: budget, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertFalse(over.canWrite)
        XCTAssertTrue(over.findings.contains { $0.code == "flow-configuration-unavailable" })
        XCTAssertThrowsError(try MultiPageStaticBuildPlanner.plan(document: budget))
        let fifth = try XCTUnwrap(budget.pages[0].nodes.firstIndex { $0.id == flowIDs[4] })
        budget.pages[0].nodes[fifth].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalFlowGradient.namespace) }
        try budget.validate()
        XCTAssertFalse(StaticBuildCompiler.compile(document: budget, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:]).findings.contains { $0.code == "flow-configuration-unavailable" })
        let plan = try MultiPageStaticBuildPlanner.plan(document: budget)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertEqual(html.components(separatedBy: "data-siteforge-flow=").count - 1, 4)
        XCTAssertEqual(html.components(separatedBy: "siteforge-effects.js").count - 1, 1)
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-effects.js" && $0.contents == DecorativeEffectRuntime.javascript })

        // The attribute carries escaped validated numbers; the runtime angle is
        // the canonical normalized angle that the static CSS gradient uses.
        let first = try XCTUnwrap(budget.pages[0].nodes.first { $0.id == flowIDs[0] })
        let config = try XCTUnwrap(DecorativeEffectOutput.configuration(first))
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.angle, 315)
        XCTAssertEqual(config.radius, CanonicalFlowGradient.defaults.radius)
        XCTAssertEqual(config.returnSeconds, CanonicalFlowGradient.defaults.returnSeconds)
        XCTAssertEqual(config.stops.map(\.position), [0, 1])
        let escaped = config.json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        XCTAssertTrue(html.contains("data-siteforge-flow=\"\(escaped)\""), html)
        XCTAssertFalse(html.contains("data-siteforge-flow=\"{\""), html)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("linear-gradient(45.0deg"), css)
        XCTAssertTrue(css.contains(DecorativeEffectRuntime.css), "The decorative canvas rules ship with the runtime")
        XCTAssertTrue(DecorativeEffectRuntime.css.contains("pointer-events:none"))
    }

    // SF-0508-001/004/005/008, SF-1204-003/004, SF-0305-001, SF-0306-001: an
    // optional dark website variant is project data. It edits through the
    // token registry with one undo, survives light recolor and rename, stays
    // out of schema 20, and compiles to a prefers-color-scheme override only
    // when a variant exists. The native app appearance is never consulted.
    func testLocalColorTokenDarkVariantHistorySchemaGateAndThemedStaticOutput() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let light = CanonicalSolidColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        let dark = CanonicalSolidColor(red: 1, green: 0, blue: 0, alpha: 1)
        document.pages[0].nodes[0].properties += CanonicalFillLayerCodec.propertyValues(for: [
            .solid(color: .init(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
        }
        try document.validate()
        let session = DocumentSession(document: document)
        func prepare(_ edit: LocalColorTokenEdit, ids: [NodeID] = []) throws -> DocumentCommand {
            try LocalColorTokenCommandRegistry.prepare(edit, in: session.document, expectedDocumentID: session.document.id,
                expectedRevision: session.document.revision, pageID: pageID, selectedNodeIDs: ids)
        }
        func stylesheet() throws -> String {
            try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document).files.first { $0.path == "styles.css" }?.contents)
        }
        func failure(_ error: Error) -> LocalColorTokenCommandError? { error as? LocalColorTokenCommandError }
        try session.execute(prepare(.create(name: "Brand", color: light)))
        let tokenID = try XCTUnwrap(session.document.colorTokens.first?.id)
        try session.execute(prepare(.bindTarget(tokenID, .fill), ids: [rootID]))
        XCTAssertNil(session.document.colorTokens.first?.darkColor)
        let unthemed = try stylesheet()
        XCTAssertTrue(unthemed.contains("rgba(0.0, 127.5, 255.0, 1.0)"), unthemed)
        XCTAssertFalse(unthemed.contains("prefers-color-scheme"), unthemed)
        XCTAssertFalse(unthemed.contains("color-scheme:light dark"), unthemed)

        // One transaction adds only the variant; bindings and light color stay.
        let beforeVariant = session.document
        let undoCount = session.historySnapshot().undoEntries.count
        try session.execute(prepare(.darkVariant(tokenID, dark)))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, undoCount + 1)
        XCTAssertEqual(session.document.colorTokens.first?.darkColor, dark)
        XCTAssertEqual(session.document.colorTokens.first?.color, light)
        XCTAssertEqual(session.document.pages, beforeVariant.pages)
        let themedDocument = session.document
        XCTAssertThrowsError(try prepare(.darkVariant(tokenID, dark))) {
            guard case .unchanged? = failure($0) else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try prepare(.darkVariant(tokenID, .init(red: 1.5, green: 0, blue: 0, alpha: 1)))) {
            guard case .invalid? = failure($0) else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try prepare(.darkVariant(ColorTokenID(), dark))) {
            guard case .invalid? = failure($0) else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(session.document, themedDocument)

        // Output: light values stay first; the variant is a scoped dark override.
        let themed = try stylesheet()
        let parts = themed.components(separatedBy: "@media (prefers-color-scheme:dark) {")
        XCTAssertEqual(parts.count, 2, themed)
        XCTAssertTrue(parts[0].contains("rgba(0.0, 127.5, 255.0, 1.0)"), themed)
        XCTAssertFalse(parts[0].contains("rgba(255.0, 0.0, 0.0, 1.0)"), themed)
        XCTAssertTrue(parts[0].contains(":root { color-scheme:light dark; }"), themed)
        XCTAssertTrue(parts[1].contains("rgba(255.0, 0.0, 0.0, 1.0)"), themed)
        XCTAssertTrue(parts[1].contains(CanonicalCSSRule.selector(for: rootID)), themed)

        try session.undo()
        XCTAssertEqual(session.document.colorTokens, beforeVariant.colorTokens)
        XCTAssertFalse(try stylesheet().contains("prefers-color-scheme"))
        try session.redo()
        XCTAssertEqual(session.document.colorTokens, themedDocument.colorTokens)

        // Editing the light color or name never drops the dark variant.
        let recolored = CanonicalSolidColor(red: 0, green: 0.25, blue: 0.5, alpha: 1)
        try session.execute(prepare(.recolor(tokenID, recolored)))
        try session.execute(prepare(.rename(tokenID, "Accent")))
        try session.execute(prepare(.update(tokenID, name: "Accent Ink", color: light)))
        XCTAssertEqual(session.document.colorTokens.first?.darkColor, dark)
        XCTAssertEqual(session.document.colorTokens.first?.name, "Accent Ink")

        // Canonical validation and the strict historical envelope.
        var invalid = session.document
        invalid.colorTokens[0].darkColor = .init(red: 0, green: -0.1, blue: 0, alpha: 1)
        XCTAssertThrowsError(try invalid.validate())
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical["schemaVersion"] = 20
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))

        // Removing the variant returns to schema-20-compatible, unthemed output.
        try session.execute(prepare(.darkVariant(tokenID, nil)))
        XCTAssertNil(session.document.colorTokens.first?.darkColor)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(session.document)) as? [String: Any])
        legacy["schemaVersion"] = 20
        let reopened = try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(reopened.colorTokens, session.document.colorTokens)
        XCTAssertEqual(reopened.pages, session.document.pages)
        XCTAssertFalse(try stylesheet().contains("prefers-color-scheme"))
    }

    // SF-LOCAL-BUILDER-016 / SF-0702-003, SF-0302-004.
    func testLegacyDesignTextDraftCleanDefaultsMixedAndDisplayRefreshDoNotBlockNavigation() {
        let context = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank())).responsiveInspectorEditContext
        for text in ["", "#F0F0F0FF", "1.0", "0, 8, 18, 0"] {
            var draft = InspectorTextDraftState(text: text, committed: text, context: context)
            XCTAssertFalse(draft.isDirty); XCTAssertFalse(draft.isConflicted)
            let next = ResponsiveInspectorEditContext(scope: context.scope, revision: context.revision + 1)
            draft.adopt(committed: "", context: next)
            XCTAssertEqual(draft.text, ""); XCTAssertEqual(draft.context, next)
            XCTAssertFalse(draft.isDirty); XCTAssertFalse(draft.isConflicted)
            draft.adopt(committed: "2.0", context: next)
            XCTAssertEqual(draft.text, "2.0"); XCTAssertFalse(draft.isDirty)
        }
    }

    func testLegacyDesignTextDraftRetainsInvalidInputAndRejectsEveryChangedOwnershipBoundary() {
        let original = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank())).responsiveInspectorEditContext
        let scope = original.scope
        let scopes: [LayoutInspectorDraftScope] = [
            .init(documentID: DocumentID(), pageID: scope.pageID, sceneID: scope.sceneID, orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            .init(documentID: scope.documentID, pageID: PageID(), sceneID: scope.sceneID, orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            .init(documentID: scope.documentID, pageID: scope.pageID, sceneID: CanvasViewportSceneID(), orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            .init(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID, orderedNodeIDs: [NodeID()], breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            .init(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID, orderedNodeIDs: scope.orderedNodeIDs, breakpoint: .mobile, viewportWidth: 390),
            .init(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID, orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: 430)
        ]
        let contexts = scopes.map { ResponsiveInspectorEditContext(scope: $0, revision: original.revision) }
            + [.init(scope: scope, revision: original.revision + 1)]
        for text in ["#GG", "1e", "", "0, , 3, 4"] {
            for next in contexts {
                var draft = InspectorTextDraftState(text: text, committed: "12.0", context: original)
                draft.adopt(committed: "12.0", context: original)
                XCTAssertEqual(draft.text, text); XCTAssertTrue(draft.canCommit(in: original))
                draft.adopt(committed: "24.0", context: next)
                XCTAssertEqual(draft.text, text); XCTAssertTrue(draft.isConflicted)
                XCTAssertFalse(draft.canCommit(in: next)); XCTAssertFalse(draft.canCommit(in: original))
            }
        }
    }

    func testLegacyDesignTextDraftAcknowledgementNeverDiscardsAnotherFieldAndEscapeReloads() {
        let context = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank())).responsiveInspectorEditContext
        var drafts = ["fill": InspectorTextDraftState(text: "#123456FF", committed: "#FFFFFFFF", context: context),
                      "radius": InspectorTextDraftState(text: "1e", committed: "8.0", context: context)]
        drafts["fill"] = nil // only a successfully committed field is acknowledged
        let updated = ResponsiveInspectorEditContext(scope: context.scope, revision: context.revision + 1)
        drafts["radius"]?.adopt(committed: "8.0", context: updated)
        XCTAssertEqual(drafts["radius"]?.text, "1e"); XCTAssertTrue(drafts["radius"]?.isConflicted == true)
        drafts.removeAll() // Escape removes scene-local drafts, never canonical properties
        let clean = InspectorTextDraftState(text: "8.0", committed: "8.0", context: updated)
        XCTAssertFalse(clean.isDirty); XCTAssertFalse(clean.isConflicted)
    }

    func testShadowInspectorDraftRejectsEmptyExtraMalformedAndNonfiniteComponentsWithoutCoercion() {
        let color = CanonicalSolidColor(red: 0, green: 0, blue: 0, alpha: 0.25)
        XCTAssertEqual(ShadowInspectorDraftParser.parse(" 2, -4, 18, 0 ", color: color),
            CanonicalShadow(color: color, offsetX: 2, offsetY: -4, blur: 18, spread: 0))
        for text in ["", "1,2,3", "1,,2,3,4", "1,2,x,3,4", "1,2,3,4,", "nan,2,3,4", "1,inf,3,4", "1,2,-3,4", "1,2,3,1001"] {
            XCTAssertNil(ShadowInspectorDraftParser.parse(text, color: color), text)
        }
    }

    // SF-LOCAL-BUILDER-009 / SF-0702/0703/0308. New source only, UNRUN.
    private struct FormattingFixture {
        var document: CanonicalDocument
        let text: NodeID, targetText: NodeID, frame: NodeID, targetFrame: NodeID
        let scene = CanvasViewportSceneID()
    }
    private func formattingFixture() throws -> FormattingFixture {
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        func node(_ kind: NodeKind, _ name: String, _ x: Double, _ y: Double, _ extras: [NodeProperty]) -> DocumentNode {
            .init(kind: kind, name: name, parent: .node(root), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(x)),
                .init(key: .init(rawValue: "layout.y"), value: .number(y)),
                .init(key: .init(rawValue: "layout.width"), value: .number(240)),
                .init(key: .init(rawValue: "layout.height"), value: .number(kind == .text ? 80 : 160))] + extras)
        }
        let typography: [(String, PropertyValue)] = [("family", .string("Menlo")), ("weight", .string("semibold")),
            ("size", .number(22)), ("lineHeight", .number(30)), ("tracking", .number(1.25)), ("alignment", .string("center"))]
        var text = node(.text, "Source text", 20, 20, typography.map { .init(key: .init(rawValue: CanonicalTypography.namespace + $0.0), value: $0.1) }
            + [.init(key: .init(rawValue: "content.text"), value: .string("Source stays unchanged"))])
        text.properties += zip(CanonicalTextForeground.channels, [0.2, 0.4, 0.6, 1.0]).map {
            .init(key: .init(rawValue: CanonicalTextForeground.prefix + $0.0), value: .number($0.1)) }
        let targetText = node(.text, "Target text", 300, 20, [.init(key: .init(rawValue: "content.text"), value: .string("Target content retained"))])
        let layers: [CanonicalFillLayer] = [.solid(color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            .linearGradient(angleDegrees: 45, stops: [
                .init(id: .init(), position: 0, color: .init(red: 1, green: 0, blue: 0, alpha: 1)),
                .init(id: .init(), position: 1, color: .init(red: 0, green: 0, blue: 1, alpha: 0.5))])]
        var frame = node(.frame, "Source appearance", 20, 180, CanonicalFillLayerCodec.propertyValues(for: layers).map {
            .init(key: .init(rawValue: $0.key), value: $0.value) })
        frame.properties += [("style.opacity", PropertyValue.number(0.6)), ("style.box.v1.border.width", .number(2)),
            ("style.box.v1.border.style", .string("dashed")), ("style.box.v1.radius.uniform", .number(12)),
            ("style.box.v1.shadow.offsetX", .number(2)), ("style.box.v1.shadow.offsetY", .number(3)),
            ("style.box.v1.shadow.blur", .number(6)), ("style.box.v1.shadow.spread", .number(0)),
            ("style.box.v1.shadow.enabled", .boolean(false)), ("style.box.v1.padding.uniform", .number(18)),
            ("style.box.v1.clip.content", .boolean(true))].map { .init(key: .init(rawValue: $0.0), value: $0.1) }
        for prefix in ["style.box.v1.border.color.", "style.box.v1.shadow.color."] {
            frame.properties += zip(CanonicalTextForeground.channels, [0.1, 0.2, 0.3, 0.8]).map {
                .init(key: .init(rawValue: prefix + $0.0), value: .number($0.1)) }
        }
        let targetFrame = node(.frame, "Target appearance", 300, 180, [
            .init(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted),
            .init(key: .init(rawValue: "style.box.v1.padding.uniform"), value: .number(9)),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(150))])
        document.pages[0].nodes[0].childIDs = [text.id, targetText.id, frame.id, targetFrame.id]
        document.pages[0].nodes += [text, targetText, frame, targetFrame]
        try document.validate()
        return .init(document: document, text: text.id, targetText: targetText.id, frame: frame.id, targetFrame: targetFrame.id)
    }
    private func formattingPaste(_ transfer: FormattingTransfer, fixture: FormattingFixture, document: CanonicalDocument,
                                 ids: [NodeID], cancelled: Bool = false) throws -> PreparedDesignInspectorEdit {
        let page = document.pages[0]
        return try DesignInspectorCommandRegistry().prepare(FormattingPasteCommand(
            identity: .init(documentID: document.id, pageID: page.id, revision: document.revision,
                sceneID: fixture.scene, rendererGeneration: document.revision), orderedNodeIDs: ids, transfer: transfer, cancelled: cancelled),
            in: document, context: .init(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil))
    }
    private func copyFormatting(_ family: FormattingFamily, fixture: FormattingFixture, source: NodeID) throws -> FormattingTransfer {
        try FormattingTransfer.capture(family: family, document: fixture.document, pageID: fixture.document.pages[0].id, orderedNodeIDs: [source])
    }

    func testFormattingTextBundlePreservesRawTypographyForegroundAndFluidIntent() throws {
        var fixture = try formattingFixture()
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.text })
        fixture.document.pages[0].nodes[index].properties += [
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.fontSize)), value: .string(try CanonicalFluidValueCodec.encode(.init(minimum: 16, preferred: 22, maximum: 28), target: .fontSize)))]
        let before = try DocumentSerializer.encode(fixture.document)
        let transfer = try copyFormatting(.textStyle, fixture: fixture, source: fixture.text)
        XCTAssertEqual(try FormattingTransfer.decode(transfer.encoded()), transfer)
        let session = DocumentSession(document: fixture.document)
        try session.execute(formattingPaste(transfer, fixture: fixture, document: session.document, ids: [fixture.targetText]).documentCommand)
        let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetText })
        XCTAssertEqual(CanonicalTypography.resolved(for: node)?.family, "Menlo")
        XCTAssertEqual(CanonicalTypography.resolved(for: node)?.tracking, 1.25)
        XCTAssertNotNil(CanonicalFluidValueCodec.value(for: .fontSize, node: node))
        XCTAssertEqual(CanonicalTextForeground.literal(for: node)?.blue, 0.6)
        XCTAssertEqual(node.insertionStringProperty("content.text"), "Target content retained")
        XCTAssertEqual(try DocumentSerializer.encode(fixture.document), before)
    }

    func testFormattingAppearanceTransfersCompleteLayersEffectsAndKeepsTargetGeometry() throws {
        let fixture = try formattingFixture()
        let target = DocumentSession(document: fixture.document)
        let before = try XCTUnwrap(target.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        let transfer = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        try target.execute(formattingPaste(transfer, fixture: fixture, document: target.document, ids: [fixture.targetFrame]).documentCommand)
        let after = try XCTUnwrap(target.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        XCTAssertEqual(after.id, before.id); XCTAssertEqual(after.parent, before.parent)
        XCTAssertEqual(after.insertionGeometry, before.insertionGeometry)
        XCTAssertEqual(after.insertionProperty("style.box.v1.padding.uniform"), before.insertionProperty("style.box.v1.padding.uniform"))
        XCTAssertEqual(after.insertionProperty(ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), before.insertionProperty(ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: after).count, 2)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: after)?.cornerRadius, 12)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: after)?.shadowEnabled, false)
        XCTAssertEqual(after.insertionNumberProperty("style.opacity"), 0.6)
        XCTAssertNil(after.insertionProperty("style.fill"), "Paste never revives the retired legacy solid fields")
    }

    func testFormattingCodecRejectsUnknownDuplicateOversizedNestedAndInvalidValues() throws {
        let fixture = try formattingFixture()
        let transfer = try copyFormatting(.textStyle, fixture: fixture, source: fixture.text)
        let data = try transfer.encoded(), text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for malformed in ["{}", text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
                          text.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"version\":1"),
                          text.replacingOccurrences(of: "\"version\":1", with: "\"extra\":0,\"version\":1"),
                          String(repeating: "[", count: 17) + "0" + String(repeating: "]", count: 17)] {
            XCTAssertThrowsError(try FormattingTransfer.decode(Data(malformed.utf8)))
        }
        XCTAssertThrowsError(try FormattingTransfer.decode(Data(repeating: 32, count: FormattingTransfer.maximumBytes + 1)))
        for property in [FormattingProperty(key: "layout.x", value: .number(42), origin: .authored),
                         .init(key: CanonicalTypography.namespace + "size", value: .number(.nan), origin: .authored),
                         .init(key: CanonicalTypography.namespace + "weight", value: .string("invented"), origin: .authored)] {
            let invalid = FormattingTransfer(family: .textStyle, sourceDocumentID: fixture.document.id,
                sourcePageID: fixture.document.pages[0].id, sourceRevision: 0, properties: [property])
            XCTAssertThrowsError(try invalid.encoded())
        }
    }

    func testFormattingCommonSourceDoesNotBorrowMixedPrimaryOrLayerIDs() throws {
        var fixture = try formattingFixture()
        let sourceIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.text })
        let targetIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.targetText })
        fixture.document.pages[0].nodes[targetIndex].properties += fixture.document.pages[0].nodes[sourceIndex].properties
            .filter { FormattingFamily.textStyle.owns($0.key.rawValue) }.map { .init(key: $0.key, value: $0.value, origin: $0.origin) }
        XCTAssertNoThrow(try FormattingTransfer.capture(family: .textStyle, document: fixture.document,
            pageID: fixture.document.pages[0].id, orderedNodeIDs: [fixture.text, fixture.targetText]))
        let size = try XCTUnwrap(fixture.document.pages[0].nodes[targetIndex].properties.firstIndex { $0.key.rawValue == CanonicalTypography.namespace + "size" })
        fixture.document.pages[0].nodes[targetIndex].properties[size].value = .number(20)
        XCTAssertThrowsError(try FormattingTransfer.capture(family: .textStyle, document: fixture.document,
            pageID: fixture.document.pages[0].id, orderedNodeIDs: [fixture.text, fixture.targetText])) { XCTAssertEqual($0 as? FormattingTransferError, .mixedSource) }
        XCTAssertThrowsError(try FormattingTransfer.capture(family: .textStyle, document: fixture.document,
            pageID: fixture.document.pages[0].id, orderedNodeIDs: [fixture.text, fixture.frame]))
    }

    func testFormattingPasteReportsApplicableSubsetAndSkipsLockedAndIncompatible() throws {
        var fixture = try formattingFixture()
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.text })
        fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: "locked"), value: .boolean(true)))
        let transfer = try copyFormatting(.textStyle, fixture: fixture, source: fixture.text)
        let session = DocumentSession(document: fixture.document)
        let prepared = try formattingPaste(transfer, fixture: fixture, document: session.document,
            ids: [fixture.targetText, fixture.frame, fixture.text])
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.targetText])
        XCTAssertEqual(prepared.skippedNodeIDs, [fixture.frame, fixture.text])
        XCTAssertTrue(prepared.skippedReasons[fixture.text]?.contains("Unlock") == true)
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == fixture.frame }, fixture.document.pages[0].nodes.first { $0.id == fixture.frame })
        XCTAssertThrowsError(try formattingPaste(transfer, fixture: fixture, document: session.document, ids: [fixture.frame]))
    }

    func testFormattingMultipleTargetsKeepIndependentLayerIDsAndOneHistoryEntry() throws {
        var fixture = try formattingFixture()
        let originalTarget = try XCTUnwrap(fixture.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        let second = DocumentNode(kind: .frame, name: "Second target", parent: originalTarget.parent,
            properties: originalTarget.properties.map { .init(key: $0.key, value: $0.value, origin: $0.origin) })
        fixture.document.pages[0].nodes[0].childIDs.append(second.id)
        fixture.document.pages[0].nodes.append(second)
        try fixture.document.validate()
        let transfer = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        let session = DocumentSession(document: fixture.document), before = session.document.pages
        let prepared = try formattingPaste(transfer, fixture: fixture, document: session.document, ids: [fixture.targetFrame, second.id])
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.targetFrame, second.id])
        XCTAssertTrue(prepared.skippedNodeIDs.isEmpty)
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let first = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        let last = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == second.id })
        XCTAssertNotEqual(first.insertionStringProperty(CanonicalFillLayerCodec.orderKey), last.insertionStringProperty(CanonicalFillLayerCodec.orderKey))
        XCTAssertEqual(try FormattingTransfer.normalizedIntent(for: first, family: .appearance),
            try FormattingTransfer.normalizedIntent(for: last, family: .appearance))
        XCTAssertNoThrow(try FormattingTransfer.capture(family: .appearance, document: session.document,
            pageID: session.document.pages[0].id, orderedNodeIDs: [fixture.frame, fixture.targetFrame, second.id]))
        let after = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, after)
    }

    func testFormattingPasteAtomicInverseUndoRedoBranchAndRepeatedNoOp() throws {
        let fixture = try formattingFixture(), session = DocumentSession(document: fixture.document)
        let transfer = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        let before = session.document.pages
        let prepared = try formattingPaste(transfer, fixture: fixture, document: session.document, ids: [fixture.targetFrame])
        XCTAssertThrowsError(try session.execute(prepared.documentCommand, cancellation: .init(isCancelled: { true })))
        XCTAssertEqual(session.document.pages, before); XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
        try session.execute(prepared.documentCommand)
        let pasted = session.document.pages
        XCTAssertThrowsError(try formattingPaste(transfer, fixture: fixture, document: session.document, ids: [fixture.targetFrame])) { XCTAssertEqual($0 as? FormattingTransferError, .noChanges) }
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, pasted)
        try session.undo()
        let target = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        try session.execute(.setProperty(.init(pageID: session.document.pages[0].id, nodeID: target.id,
            property: .init(key: .init(rawValue: "style.opacity"), value: .number(0.4)))))
        XCTAssertTrue(session.historySnapshot().redoEntries.isEmpty)
    }

    func testFormattingPasteRejectsStaleCancelledMissingAndMalformedAtomically() throws {
        let fixture = try formattingFixture(), page = fixture.document.pages[0]
        let transfer = try copyFormatting(.textStyle, fixture: fixture, source: fixture.text)
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: 0,
            selectedNodeIDs: [fixture.targetText], availableNodeIDs: Set(page.nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let identities: [DesignInspectorOperationIdentity] = [
            .init(documentID: DocumentID(), pageID: page.id, revision: 0, sceneID: fixture.scene, rendererGeneration: 0),
            .init(documentID: fixture.document.id, pageID: PageID(), revision: 0, sceneID: fixture.scene, rendererGeneration: 0),
            .init(documentID: fixture.document.id, pageID: page.id, revision: 1, sceneID: fixture.scene, rendererGeneration: 0),
            .init(documentID: fixture.document.id, pageID: page.id, revision: 0, sceneID: .init(), rendererGeneration: 0),
            .init(documentID: fixture.document.id, pageID: page.id, revision: 0, sceneID: fixture.scene, rendererGeneration: 1)]
        for identity in identities {
            XCTAssertThrowsError(try DesignInspectorCommandRegistry().prepare(FormattingPasteCommand(identity: identity,
                orderedNodeIDs: [fixture.targetText], transfer: transfer, cancelled: false), in: fixture.document, context: context))
        }
        XCTAssertThrowsError(try formattingPaste(transfer, fixture: fixture, document: fixture.document, ids: [fixture.targetText], cancelled: true))
        XCTAssertThrowsError(try formattingPaste(transfer, fixture: fixture, document: fixture.document, ids: [NodeID()]))
        XCTAssertThrowsError(try formattingPaste(transfer, fixture: fixture, document: fixture.document, ids: [fixture.targetText, fixture.targetText]))
        XCTAssertEqual(fixture.document.revision, 0)
    }

    func testFormattingReferencesStayLinkedAndForeignOrMissingDependenciesReject() throws {
        var fixture = try formattingFixture()
        let token = LocalColorToken(name: "Ink", color: .init(red: 0.8, green: 0.1, blue: 0.2, alpha: 1))
        fixture.document.colorTokens = [token]
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.text })
        fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .textForeground)), value: .string(token.id.description)))
        let transfer = try copyFormatting(.textStyle, fixture: fixture, source: fixture.text)
        let session = DocumentSession(document: fixture.document)
        try session.execute(formattingPaste(transfer, fixture: fixture, document: session.document, ids: [fixture.targetText]).documentCommand)
        let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetText })
        XCTAssertEqual(LocalColorTokenBinding.id(for: node, target: .textForeground), token.id)
        let sourceFrameIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        for target in [LocalColorTarget.border, .outerShadow] {
            fixture.document.pages[0].nodes[sourceFrameIndex].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: target)), value: .string(token.id.description)))
        }
        let appearance = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        let appearanceSession = DocumentSession(document: fixture.document)
        try appearanceSession.execute(formattingPaste(appearance, fixture: fixture, document: appearanceSession.document, ids: [fixture.targetFrame]).documentCommand)
        let box = try XCTUnwrap(appearanceSession.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        XCTAssertEqual(LocalColorTokenBinding.id(for: box, target: .border), token.id)
        XCTAssertEqual(LocalColorTokenBinding.id(for: box, target: .outerShadow), token.id)
        var missing = fixture.document; missing.colorTokens = []
        XCTAssertThrowsError(try transfer.validateDependencies(in: missing))
        XCTAssertThrowsError(try transfer.validateDependencies(in: ProjectCreation.blank())) { XCTAssertEqual($0 as? FormattingTransferError, .foreignDocument) }
        let image = FormattingTransfer(family: .appearance, sourceDocumentID: fixture.document.id,
            sourcePageID: fixture.document.pages[0].id, sourceRevision: 0,
            properties: [.init(key: CanonicalImageFill.assetKey, value: .string(AssetID().description), origin: .authored)])
        XCTAssertThrowsError(try image.validateDependencies(in: fixture.document))
    }

    func testFormattingOmittedExplicitNoneLegacyDefaultsAndNamedInheritanceRemainDistinct() throws {
        var fixture = try formattingFixture()
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        fixture.document.pages[0].nodes[index].properties.removeAll { FormattingFamily.appearance.owns($0.key.rawValue) }
        let style = ReusableStyleID(), prefix = CanonicalReusableStyleIndex.namespace + "definition.\(style.description)."
        fixture.document.pages[0].nodes[0].properties += [.init(key: .init(rawValue: prefix + "name"), value: .string("Linked")),
            .init(key: .init(rawValue: prefix + "fill"), value: .string("#204060FF"))]
        fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(style.description)))
        let inherited = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        XCTAssertFalse(inherited.properties.contains { $0.key == CanonicalFillLayerCodec.orderKey })
        let session = DocumentSession(document: fixture.document)
        try session.execute(formattingPaste(inherited, fixture: fixture, document: session.document, ids: [fixture.targetFrame]).documentCommand)
        let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(node), [style])
        XCTAssertNil(node.insertionProperty(CanonicalFillLayerCodec.orderKey))
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: node, index: CanonicalReusableStyleIndex(document: session.document)).fill?.hexadecimalRGBA, "#204060FF")
        fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: CanonicalFillLayerCodec.orderKey), value: .string("")))
        let none = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        XCTAssertNotEqual(inherited, none)
        XCTAssertTrue(none.properties.contains { $0.key == CanonicalFillLayerCodec.orderKey && $0.value == .string("") })
        try session.execute(formattingPaste(none, fixture: fixture, document: session.document, ids: [fixture.targetFrame]).documentCommand)
        let noneNode = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        XCTAssertNil(try CanonicalResolvedAppearance.resolve(node: noneNode, index: CanonicalReusableStyleIndex(document: session.document)).fill)
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.targetFrame }?.insertionProperty(CanonicalFillLayerCodec.orderKey))
        let legacy = try copyFormatting(.appearance, fixture: fixture, source: fixture.targetFrame)
        XCTAssertFalse(legacy.properties.contains { FormattingFamily.retiredFillKeys.contains($0.key) })
        XCTAssertTrue(legacy.properties.filter { $0.key.hasPrefix(CanonicalFillLayerCodec.namespaceRoot) }.allSatisfy { $0.origin == .defaulted })
        XCTAssertThrowsError(try formattingPaste(legacy, fixture: fixture, document: fixture.document, ids: [fixture.targetFrame])) { XCTAssertEqual($0 as? FormattingTransferError, .noChanges) }
    }

    func testFormattingImageFillValidatesExistingResourceBytesAndSkipsUnsupportedKinds() async throws {
        var fixture = try formattingFixture()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<2 { for x in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Formatting fixture", originalFilename: "formatting.png",
            format: .png, pixelWidth: 2, pixelHeight: 2, byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        fixture.document.imageAssets = [asset]
        let source = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        fixture.document.pages[0].nodes[source].properties += [
            .init(key: .init(rawValue: CanonicalImageFill.assetKey), value: .string(asset.id.description)),
            .init(key: .init(rawValue: CanonicalImageFill.modeKey), value: .string("fill"))]
        try fixture.document.validate()
        let transfer = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        let descriptor = ProjectResourceDescriptor(id: asset.resourceID, filename: asset.originalFilename,
            mediaType: "image/png", byteCount: bytes.count, sha256: asset.contentHash)
        let package = try ProjectPackage(document: fixture.document).withResource(descriptor, data: bytes)
        let page = fixture.document.pages[0], ids = [fixture.targetFrame, fixture.targetText]
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: fixture.scene, rendererGeneration: 0,
            selectedNodeIDs: ids, availableNodeIDs: Set(page.nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let identity = DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: page.id, revision: 0, sceneID: fixture.scene, rendererGeneration: 0)
        let worker = FormattingTransferWorker()
        let prepared = try await worker.paste(transfer.encoded(), family: .appearance, identity: identity, nodeIDs: ids,
            document: fixture.document, context: context, package: package, breakpoint: .desktop)
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.targetFrame]); XCTAssertEqual(prepared.skippedNodeIDs, [fixture.targetText])
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(CanonicalImageFill.resolve(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetFrame }))?.assetID, asset.id)
        do {
            _ = try await worker.paste(transfer.encoded(), family: .appearance, identity: identity, nodeIDs: ids,
                document: fixture.document, context: context, package: .init(document: fixture.document), breakpoint: .desktop)
            XCTFail("A reference without verified local bytes must not paste")
        } catch let error as FormattingTransferError { XCTAssertEqual(error, .missingDependency) }
    }

    func testFormattingDoesNotTransferLayoutContentOrStateAndRollsBackInvalidBundle() throws {
        let fixture = try formattingFixture(), session = DocumentSession(document: fixture.document)
        let source = try copyFormatting(.appearance, fixture: fixture, source: fixture.frame)
        XCTAssertFalse(source.properties.contains { $0.key == "style.box.v1.padding.uniform" || $0.key == "style.box.v1.clip.content" })
        let before = session.document.pages
        let invalid = FormattingTransfer(family: .appearance, sourceDocumentID: fixture.document.id, sourcePageID: fixture.document.pages[0].id,
            sourceRevision: 0, properties: source.properties.filter { $0.key != "style.box.v1.radius.uniform" }
                + [.init(key: "style.box.v1.radius.uniform", value: .number(-1), origin: .authored)])
        XCTAssertThrowsError(try formattingPaste(invalid, fixture: fixture, document: session.document, ids: [fixture.frame, fixture.targetFrame]))
        XCTAssertEqual(session.document.pages, before); XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
        try session.execute(formattingPaste(source, fixture: fixture, document: session.document, ids: [fixture.targetFrame]).documentCommand)
        let after = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.targetFrame })
        let old = try XCTUnwrap(before[0].nodes.first { $0.id == fixture.targetFrame })
        XCTAssertEqual(after.properties.filter { !FormattingFamily.appearance.owns($0.key.rawValue) }, old.properties.filter { !FormattingFamily.appearance.owns($0.key.rawValue) })
    }

    func testFormattingPackageRecoveryAndSharedRendererCompilerRetainCommittedIntent() async throws {
        let fixture = try formattingFixture(), session = DocumentSession(document: fixture.document)
        let transfer = try copyFormatting(.textStyle, fixture: fixture, source: fixture.text)
        try session.execute(formattingPaste(transfer, fixture: fixture, document: session.document, ids: [fixture.targetText]).documentCommand)
        let package = ProjectPackage(document: session.document), store = ProjectPackageStore()
        let data = try await store.encode(package), opened = try await store.decode(data)
        XCTAssertEqual(opened.document, session.document)
        let owned = try ApplicationOwnedTestFixture.create("formatting-recovery")
        defer { try? owned.cleanup() }
        let directory = owned.url.appendingPathComponent("recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(directory)
        let recovery = DocumentLifecycleBackend.recoveryURL(for: package.projectID, in: directory)
        try await store.write(package, to: recovery, policy: .recovery(package.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(from: recovery, expectedProjectID: package.projectID).package
        XCTAssertEqual(recovered, package)
        let page = session.document.pages[0], viewport = try CanvasViewportState()
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: session.document, activePageID: page.id,
            activeContainerID: nil, viewport: viewport, surfaceID: .init(), viewportWidth: 1440))
        let sourceObject = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == fixture.text })
        let targetObject = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == fixture.targetText })
        XCTAssertEqual(sourceObject.typography, targetObject.typography)
        XCTAssertEqual(targetObject.frame, page.resolvedStructuralGeometry(viewportWidth: 1440)[fixture.targetText]?.frame)
        let output = StaticBuildCompiler.compile(document: session.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertNotNil(output.plan)
        XCTAssertTrue(output.plan?.files.contains { $0.path == "styles.css" && $0.contents.contains("Menlo") } == true)
    }

    func testFormattingComponentInstancesAreNotArbitraryPropertyTargets() throws {
        let fixture = try formattingFixture()
        var document = fixture.document
        let definitionID = PageID(), rootID = NodeID(), textID = NodeID(), instanceID = NodeID()
        // The older geometry helper deliberately uses repeatable IDs for its
        // own fixtures. These three independent owners need fresh property IDs.
        func geometry(_ parent: NodeID, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            makeGeometryNode(id: NodeID(), parent: parent, x: x, y: y, width: width, height: height).properties.map {
                .init(key: $0.key, value: $0.value, origin: $0.origin)
            }
        }
        let root = DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(definitionID), childIDs: [textID],
            properties: geometry(rootID, 0, 0, 240, 160))
        let text = DocumentNode(id: textID, kind: .text, name: "Definition Text", parent: .node(rootID),
            properties: geometry(rootID, 12, 12, 120, 24)
                + [.init(key: .init(rawValue: "content.text"), value: .string("Definition content"))])
        document.pages.append(.init(id: definitionID, name: "Definition", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [rootID], nodes: [root, text]))
        let homeRoot = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs.append(instanceID)
        document.pages[0].nodes.append(.init(id: instanceID, kind: .component, name: "Instance", parent: .node(homeRoot),
            properties: geometry(homeRoot, 600, 20, 240, 160)
                + [.init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(definitionID.description))]))
        try document.validate()
        let transfer = try copyFormatting(.textStyle, fixture: fixture, source: fixture.text)
        XCTAssertThrowsError(try formattingPaste(transfer, fixture: fixture, document: document, ids: [instanceID]))
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: definitionID, revision: document.revision, sceneID: fixture.scene, rendererGeneration: document.revision)
        let prepared = try DesignInspectorCommandRegistry().prepare(FormattingPasteCommand(identity: identity, orderedNodeIDs: [textID], transfer: transfer, cancelled: false),
            in: document, context: .init(activePageID: definitionID, currentSceneID: fixture.scene, rendererGeneration: document.revision,
                selectedNodeIDs: [textID], availableNodeIDs: [textID], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        let session = DocumentSession(document: document)
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == instanceID }, document.pages[0].nodes.first { $0.id == instanceID })
        XCTAssertEqual(session.document.pages.last?.nodes.first { $0.id == textID }?.insertionStringProperty("content.text"), "Definition content")
    }

    func testFormattingCopyCleanGateRejectsPendingIMEWithoutClipboardOrHistoryMutation() async throws {
        let fixture = try formattingFixture(), state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        let deadline = ContinuousClock.now + .seconds(3)
        while state.canvasRenderPlan == nil, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertNotNil(state.canvasRenderPlan)
        state.selectLayer(fixture.text); await state.prepareFormattingCopies()
        XCTAssertTrue(state.formattingCopyAvailability(.textStyle).isEnabled)
        XCTAssertTrue(state.beginTextEditing(nodeID: fixture.text, provenance: .keyboard))
        state.updateTextEditingDraft(text: "A", selection: .init(location: 1, length: 0), markedRange: .init(location: 0, length: 1))
        let clipboardChange = NSPasteboard.general.changeCount, before = state.documentSession.document
        state.copyFormatting(.textStyle)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChange)
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertTrue(state.documentSession.historySnapshot().undoEntries.isEmpty)
        state.cancelTextEditing()
        try state.documentSession.establishBaseline(ProjectCreation.blank())
        XCTAssertFalse(state.formattingCopyAvailability(.textStyle).isEnabled)
        XCTAssertFalse(String(describing: state.lastFormattingDiagnostic).contains(fixture.document.id.description))
    }

    // SF-0508-002/003, SF-0701-003 — selection routing must not guess a Root.
    func testPageBackgroundPolicyRequiresSingleStructuralWebsiteRoot() throws {
        var document = ProjectCreation.blank()
        var page = try XCTUnwrap(document.pages.first)
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: page))
        XCTAssertNil(root.insertionGeometry)
        XCTAssertNil(PageBackgroundPolicy.unavailableReason(in: page))
        let before = document
        XCTAssertNil(PageBackgroundPolicy.root(in: nil))
        page.rootNodeIDs.append(NodeID())
        XCTAssertNil(PageBackgroundPolicy.root(in: page), "Multiple roots must not pick an arbitrary background owner")
        page = before.pages[0]
        for (key, value) in [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", 100.0), ("layout.height", 100.0)] {
            page.nodes[0].properties.append(.init(key: .init(rawValue: key), value: .number(value)))
        }
        XCTAssertNil(PageBackgroundPolicy.root(in: page), "An authored geometric Frame is not silently promoted to page background ownership")
        page = before.pages[0]
        page.nodes[0].properties.append(.init(key: .init(rawValue: "hidden"), value: .boolean(true)))
        XCTAssertNotNil(PageBackgroundPolicy.unavailableReason(in: page))
        XCTAssertEqual(PageBackgroundPolicy.root(in: page)?.id, root.id, "Hidden intent is retained, not replaced")
        document = before
        XCTAssertEqual(document, before, "Discoverability is a read-only projection")
    }

    // SF-0508-002/005 — None clears gradient/solid/token state in one existing
    // property transaction; exact inverse restores IDs, origins and bindings.
    func testPageBackgroundTransparentNonePreservesTokenHistoryAndPersistence() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let color = CanonicalSolidColor(red: 0.2, green: 0.1, blue: 0.4, alpha: 1)
        let token = LocalColorToken(name: "Page Ink", color: color)
        document.colorTokens = [token]
        let layer = CanonicalFillLayer.solid(color: color)
        document.pages[0].nodes[0].properties += CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
        }
        document.pages[0].nodes[0].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description), origin: .authored))
        let original = document.pages[0].nodes[0]
        let scene = CanvasViewportSceneID()
        func context(_ value: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: value.revision,
                  selectedNodeIDs: [rootID], availableNodeIDs: [rootID],
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func request(_ value: CanonicalDocument, cancelled: Bool = false) -> DesignFillLayerCommand {
            .init(identity: .init(documentID: value.id, pageID: pageID, revision: value.revision,
                                 sceneID: scene, rendererGeneration: value.revision),
                  orderedNodeIDs: [rootID], edit: .clearAll, provenance: .keyboard, cancelled: cancelled)
        }
        let registry = DesignInspectorCommandRegistry()
        let prepared = try registry.prepare(request(document), in: document, context: context(document))
        let session = DocumentSession(document: document)
        _ = try session.execute(prepared.documentCommand)
        let cleared = session.document.pages[0].nodes[0]
        XCTAssertEqual(cleared.id, original.id)
        XCTAssertEqual(CanonicalFillLayerCodec.layers(for: cleared), [])
        XCTAssertNil(LocalColorTokenBinding.id(for: cleared))
        XCTAssertEqual(session.document.colorTokens, [token], "None unbinds; it does not delete the shared token")
        XCTAssertNil(cleared.insertionGeometry)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try registry.prepare(request(session.document), in: session.document, context: context(session.document))) {
            XCTAssertEqual($0 as? DesignInspectorError, .noChanges)
        }
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[0], original)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes[0], cleared)
        let beforeRejected = session.document
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected, cancelled: true), in: beforeRejected, context: context(beforeRejected)))
        XCTAssertThrowsError(try registry.prepare(request(document), in: beforeRejected, context: context(beforeRejected)))
        var changedPage = context(beforeRejected)
        changedPage = .init(activePageID: PageID(), currentSceneID: scene, rendererGeneration: beforeRejected.revision,
                            selectedNodeIDs: [rootID], availableNodeIDs: [rootID], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected), in: beforeRejected, context: changedPage))
        let changedSelection = TransformValidationContext(activePageID: pageID, currentSceneID: scene,
            rendererGeneration: beforeRejected.revision, selectedNodeIDs: [], availableNodeIDs: [rootID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected), in: beforeRejected, context: changedSelection))
        let changedScene = TransformValidationContext(activePageID: pageID, currentSceneID: CanvasViewportSceneID(),
            rendererGeneration: beforeRejected.revision, selectedNodeIDs: [rootID], availableNodeIDs: [rootID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected), in: beforeRejected, context: changedScene))
        XCTAssertEqual(session.document, beforeRejected)
        var omitted = document
        omitted.pages[0].nodes[0].properties.removeAll()
        XCTAssertThrowsError(try registry.prepare(request(omitted), in: omitted, context: context(omitted))) {
            XCTAssertEqual($0 as? DesignInspectorError, .noChanges)
        }
        let styleID = ReusableStyleID()
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        omitted.pages[0].nodes[0].properties = [
            .init(key: .init(rawValue: prefix + "name"), value: .string("Page Style")),
            .init(key: .init(rawValue: prefix + "fill"), value: .string(color.hexadecimalRGBA)),
            .init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description))
        ]
        let inherited = omitted.pages[0].nodes[0]
        let styledSession = DocumentSession(document: omitted)
        let none = try registry.prepare(request(omitted), in: omitted, context: context(omitted))
        try styledSession.execute(none.documentCommand)
        let styledRoot = styledSession.document.pages[0].nodes[0]
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(styledRoot), [styleID])
        XCTAssertNil(try CanonicalResolvedAppearance.resolve(node: styledRoot,
            index: CanonicalReusableStyleIndex(document: styledSession.document)).fill)
        try styledSession.undo()
        XCTAssertEqual(styledSession.document.pages[0].nodes[0], inherited)
    }

    // SF-0508-003/005 — renderer/output inputs remain immutable canonical data.
    func testPageBackgroundGradientProjectsThroughSharedCompilerWithoutMutation() throws {
        var document = ProjectCreation.blank()
        let rootID = document.pages[0].rootNodeIDs[0]
        let layers = [CanonicalFillLayer.linearGradient(angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            .init(id: GradientStopID(), position: 1, color: .init(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
        ])]
        document.pages[0].nodes[0].properties += CanonicalFillLayerCodec.propertyValues(for: layers).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
        }
        let before = document
        let snapshot = try InternalDocumentRenderTreeCompiler.compile(page: document.pages[0], documentID: document.id, revision: document.revision)
        XCTAssertEqual(try XCTUnwrap(snapshot.nodes.first { $0.id == rootID }).fillLayers, layers)
        document.pages[0].nodes[0].properties.removeAll()
        XCTAssertEqual(try XCTUnwrap(snapshot.nodes.first { $0.id == rootID }).fillLayers, layers, "Adopted output cannot mix a later draft")
        XCTAssertEqual(PageBackgroundPolicy.root(in: before.pages[0])?.id, rootID)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(before)), before)
    }

    func testPageBackgroundEntrySelectsStructuralRootWithoutCanvasGhostOrMutation() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.canvasRenderPlan == nil || state.layerTargets.isEmpty {
            if ContinuousClock.now >= deadline { XCTFail("Initial scene was not adopted"); return }
            await Task.yield()
        }
        let before = session.document
        let pageID = before.pages[0].id
        let rootID = before.pages[0].rootNodeIDs[0]
        state.revealPageBackground(pageID: pageID)
        XCTAssertEqual(state.selectionState.orderedIDs, [rootID])
        XCTAssertTrue(state.isInspectingPageBackground)
        XCTAssertTrue(state.canEditDesignSolidFill, "An omitted Root fill remains editable without creating a default")
        XCTAssertEqual(state.inspectorTab, .design)
        let root = try XCTUnwrap(state.layerTargets.first { $0.id == rootID })
        XCTAssertTrue(root.isVisible)
        XCTAssertTrue(root.isStructuralRoot)
        XCTAssertFalse(root.participatesInCanvasTraversal)
        XCTAssertEqual(root.layerVisibilityDescription, "Page structure")
        state.revealPageBackground(pageID: PageID())
        XCTAssertEqual(state.selectionState.orderedIDs, [rootID], "An obsolete page action must not retarget")
        XCTAssertEqual(session.document, before)
        XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
    }

    func testDuplicateInlineDraftNotificationsDoNotRepublishOrMutateCanonicalState() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != session.document.revision
                    || state.selectionState.sceneIdentity?.revision != session.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle(); state.performDefaultInsertion(.text, provenance: .menu); try await settle()
        XCTAssertTrue(state.beginTextEditing(nodeID: try XCTUnwrap(state.selectionState.primaryID), provenance: .menu))
        let before = session.document, history = session.historySnapshot()
        let initial = try XCTUnwrap(state.textEditingSession.draft)
        var publications = 0
        let subscription = state.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        for _ in 0..<100 {
            state.updateTextEditingDraft(text: initial.text, selection: initial.selection, markedRange: initial.markedRange)
        }
        XCTAssertEqual(publications, 0)
        let text = "An actual draft", range = TextEditRange(location: 15, length: 0)
        state.updateTextEditingDraft(text: text, selection: range, markedRange: nil)
        XCTAssertGreaterThan(publications, 0, "Changed native input still publishes immediately")
        publications = 0
        state.updateTextEditingDraft(text: text, selection: range, markedRange: nil)
        XCTAssertEqual(publications, 0)
        state.updateTextEditingDraft(text: text, selection: .init(location: 0, length: 2), markedRange: .init(location: 0, length: 2))
        XCTAssertGreaterThan(publications, 0, "Selection and IME composition remain distinct draft changes")
        XCTAssertEqual(state.textEditingSession.draft?.markedRange, .init(location: 0, length: 2))
        XCTAssertEqual(session.document, before); XCTAssertEqual(session.historySnapshot(), history)
    }

    func testWorkspaceAvailabilityMemoKeepsOperationsDistinctAndStorageBounded() {
        var cache = WorkspaceAvailabilityCache<Int, Int, Int>(), evaluations = 0
        func prepare(_ value: Int) -> Int { evaluations += 1; return value }
        XCTAssertEqual(cache.resolve(1, key: 0) { prepare(10) }, 10)
        XCTAssertEqual(cache.resolve(2, key: 0) { prepare(20) }, 20)
        for _ in 0..<1000 {
            XCTAssertEqual(cache.resolve(1, key: 0) { prepare(-1) }, 10)
            XCTAssertEqual(cache.resolve(2, key: 0) { prepare(-1) }, 20)
        }
        XCTAssertEqual(evaluations, 2)
        for operation in 3...40 { _ = cache.resolve(operation, key: 0) { prepare(operation) } }
        let beforeEviction = evaluations
        XCTAssertEqual(cache.resolve(1, key: 0) { prepare(11) }, 11)
        XCTAssertEqual(evaluations, beforeEviction + 1, "Arbitrary transform deltas cannot grow a permanent cache")
        XCTAssertEqual(cache.resolve(1, key: 1) { prepare(12) }, 12)
        XCTAssertEqual(evaluations, beforeEviction + 2, "Any context change requires fresh central validation")
        var rows = WorkspaceAvailabilityCache<Int, Int, Int>(capacity: 256)
        var rowPreparations = 0
        for _ in 0..<3 {
            for action in 0..<200 {
                XCTAssertEqual(rows.resolve(action, key: 1) { rowPreparations += 1; return action }, action)
            }
        }
        XCTAssertEqual(rowPreparations, 200, "Visible Layers context actions must not evict each other every redraw")
    }

    func testLayersMoveAvailabilityInvalidatesAfterLockAndUndo() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != session.document.revision
                    || state.selectionState.sceneIdentity?.revision != session.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        let rootID = try XCTUnwrap(session.document.pages[0].rootNodeIDs.first)
        state.performDefaultInsertion(.frame, provenance: .menu); try await settle()
        let sourceID = try XCTUnwrap(state.selectionState.primaryID)
        state.selectLayer(rootID); state.performDefaultInsertion(.frame, provenance: .menu); try await settle()
        state.selectLayer(sourceID)
        let destination = DragDestination.container(rootID, index: 2)
        for _ in 0..<100 { XCTAssertTrue(state.dragDropAvailability(sourceID: sourceID, destination: destination).isEnabled) }
        try session.execute(.setProperty(.init(pageID: session.document.pages[0].id, nodeID: sourceID,
            property: .init(key: .init(rawValue: "locked"), value: .boolean(true)))))
        try await settle(); state.selectLayer(sourceID)
        XCTAssertFalse(state.dragDropAvailability(sourceID: sourceID, destination: destination).isEnabled)
        state.undo(); try await settle(); state.selectLayer(sourceID)
        XCTAssertTrue(state.dragDropAvailability(sourceID: sourceID, destination: destination).isEnabled)
    }

    func testWorkspaceInsertionAndTransformAvailabilityInvalidateAfterLockAndUndo() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != session.document.revision
                    || state.selectionState.sceneIdentity?.revision != session.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.frame, provenance: .menu)
        try await settle()
        let frameID = try XCTUnwrap(state.selectionState.primaryID)
        let pageID = try XCTUnwrap(state.effectiveSelectedPageID)
        let operation = TransformOperation.move(delta: .init(dx: 1, dy: 0), constraint: .none)
        let unchanged = session.document
        for _ in 0..<100 {
            XCTAssertTrue(state.insertionAvailability(.text).isEnabled)
            XCTAssertTrue(state.transformAvailability(operation).isEnabled)
        }
        XCTAssertEqual(session.document, unchanged)
        try session.execute(.setProperty(.init(pageID: pageID, nodeID: frameID,
            property: .init(key: .init(rawValue: "locked"), value: .boolean(true)))))
        try await settle()
        state.selectLayer(frameID)
        XCTAssertFalse(state.insertionAvailability(.text).isEnabled)
        XCTAssertFalse(state.transformAvailability(operation).isEnabled)
        state.undo(); try await settle(); state.selectLayer(frameID)
        XCTAssertTrue(state.insertionAvailability(.text).isEnabled)
        XCTAssertTrue(state.transformAvailability(operation).isEnabled)
        state.selectLayer(try XCTUnwrap(session.document.pages[0].rootNodeIDs.first))
        XCTAssertTrue(state.insertionAvailability(.text).isEnabled)
        XCTAssertFalse(state.transformAvailability(operation).isEnabled, "A prior frame cannot remain the menu target")
        XCTAssertEqual(session.document.pages, unchanged.pages)
    }

    // SF-0507-002/003, SF-0403-003: typing a scene-local draft must not
    // revalidate the entire canonical document for each Inspector field render.
    func testGeometryAvailabilityReusesOnlyIdenticalCommandContext() throws {
        let fixture = makeFixture()
        let scope = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
            sceneID: fixture.sceneID, orderedNodeIDs: [fixture.nodeID], breakpoint: .desktop, viewportWidth: 1440)
        let renderer = CanvasRenderRequestIdentity(documentID: fixture.document.id, revision: fixture.document.revision,
            sceneID: fixture.sceneID, sceneGeneration: fixture.rendererGeneration,
            viewportGeneration: 0, scale: try .init(1))
        func key(_ newScope: LayoutInspectorDraftScope? = nil, revision: UInt64? = nil,
                 renderer newRenderer: CanvasRenderRequestIdentity? = nil,
                 context: TransformValidationContext? = nil) -> GeometryInspectorAvailabilityCache.Key {
            .init(scope: newScope ?? scope, revision: revision ?? fixture.document.revision,
                renderer: newRenderer ?? renderer, context: context ?? fixture.context)
        }
        var cache = GeometryInspectorAvailabilityCache(), evaluations = 0
        let before = fixture.document
        for _ in 0..<1000 {
            XCTAssertEqual(cache.resolve(.width, key: key()) { evaluations += 1; return .enabled }, .enabled)
        }
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(cache.resolve(.height, key: key()) { evaluations += 1; return .disabled("Computed by Hug") }, .disabled("Computed by Hug"))
        XCTAssertEqual(evaluations, 2, "Fields have independent availability")
        let variants: [GeometryInspectorAvailabilityCache.Key] = [
            key(revision: fixture.document.revision + 1),
            key(.init(documentID: DocumentID(), pageID: scope.pageID, sceneID: scope.sceneID,
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: PageID(), sceneID: scope.sceneID,
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: scope.pageID, sceneID: CanvasViewportSceneID(),
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID,
                orderedNodeIDs: [NodeID()], breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID,
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: .mobile, viewportWidth: 390)),
            key(renderer: .init(documentID: renderer.documentID, revision: renderer.revision, sceneID: renderer.sceneID,
                sceneGeneration: renderer.sceneGeneration + 1, viewportGeneration: 1, scale: try .init(2))),
            key(context: .init(activePageID: fixture.pageID, currentSceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration, selectedNodeIDs: [fixture.nodeID], availableNodeIDs: [],
                isLifecycleAvailable: true, lifecycleDisabledReason: nil)),
            key(context: .init(activePageID: fixture.pageID, currentSceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration, selectedNodeIDs: [fixture.nodeID], availableNodeIDs: [fixture.nodeID],
                isLifecycleAvailable: false, lifecycleDisabledReason: "Resolve conflict")),
        ]
        for variant in variants {
            let previous = evaluations
            XCTAssertEqual(cache.resolve(.width, key: variant) { evaluations += 1; return .disabled("Changed context") }, .disabled("Changed context"))
            XCTAssertEqual(evaluations, previous + 1, "No stale enabled result may survive a context change")
        }
        XCTAssertEqual(fixture.document, before, "Availability is never an authored mutation")
    }

    func testInspectorAccessibilityAnnouncesRetainedDraftInsteadOfCommittedValue() {
        let committed = "75; Computed by responsive layout"
        XCTAssertEqual(InspectorDraftAccessibility.value(draft: nil, committed: committed), committed)
        for draft in ["-", "1e", "nan", "22", "Missing Family"] {
            XCTAssertEqual(InspectorDraftAccessibility.value(draft: draft, committed: committed), "\(draft); uncommitted draft")
            XCTAssertFalse(InspectorDraftAccessibility.value(draft: draft, committed: committed).contains("75"))
        }
        XCTAssertEqual(InspectorDraftAccessibility.value(draft: "", committed: committed), "Empty; uncommitted draft")
        XCTAssertEqual(InspectorDraftAccessibility.value(draft: nil, committed: "Mixed values"), "Mixed values")
    }

    func testRetainedNumericNoOpRecognizesEquivalentInputWithoutDiscardingConflict() {
        let scope = LayoutInspectorDraftScope(documentID: DocumentID(), pageID: PageID(), sceneID: CanvasViewportSceneID(),
            orderedNodeIDs: [NodeID()], breakpoint: .desktop, viewportWidth: 1440)
        for text in ["160", "160.0", " 160 "] {
            let draft = LayoutInspectorNumericDraft(text: text, committed: "160", scope: scope)
            XCTAssertTrue(draft.hasUnchangedNumericValue)
        }
        for text in ["-", "nan", "infinity", "161"] {
            XCTAssertFalse(LayoutInspectorNumericDraft(text: text, committed: "160", scope: scope).hasUnchangedNumericValue)
        }
        var stale = LayoutInspectorNumericDraft(text: "160", committed: "160", scope: scope)
        stale.adopt(committed: "160", scope: .init(documentID: scope.documentID, pageID: scope.pageID,
            sceneID: scope.sceneID, orderedNodeIDs: [NodeID()], breakpoint: .desktop, viewportWidth: 1440))
        XCTAssertFalse(stale.hasUnchangedNumericValue)
        XCTAssertEqual(stale.conflict, .contextChanged)
        XCTAssertEqual(stale.text, "160")
    }
    func testSizingDimensionWinnerAndExactResetPreserveOtherOverridesAndHistory() throws {
        var fixture = makeFixture()
        let widthKey = ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)
        let heightKey = ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)
        let fluid = CanonicalFluidValue(minimum: 180, preferred: 280, maximum: 480)
        fixture.document.pages[0].nodes[1].properties += [
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "widthMode"), value: .string("fill")),
            .init(key: .init(rawValue: widthKey), value: .number(240)),
            .init(key: .init(rawValue: heightKey), value: .number(160)),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.width)), value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .width)))
        ]
        let session = DocumentSession(document: fixture.document), registry = SizingConstraintCommandRegistry()
        func resolution() -> SizingDimensionResolution {
            CanonicalSizingConstraints.dimensionResolution(.width, node: session.document.pages[0].nodes[1], breakpoint: .mobile, width: 390)
        }
        func reset(_ source: ResponsiveGeometrySource) throws -> DocumentCommand {
            try registry.prepareDimensionReset(.width, source: source,
                identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
                    revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], breakpoint: .mobile, in: session.document, context: fixture.context)
        }
        XCTAssertEqual(resolution().declaredMode, .fill)
        XCTAssertEqual(resolution().effectiveMode, .fixed)
        XCTAssertEqual(resolution().numericSource, .override(.mobile))
        XCTAssertThrowsError(try reset(.fluid), "Do not remove a concealed lower-priority source")
        try session.execute(reset(.override(.mobile)))
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty(widthKey))
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(heightKey), fixture.document.pages[0].nodes[1].insertionProperty(heightKey))
        XCTAssertEqual(resolution().numericSource, .fluid)
        let inheritedFluid = session.document.pages
        try session.execute(reset(.fluid))
        XCTAssertEqual(resolution().effectiveMode, .fill)
        XCTAssertNil(resolution().numericSource)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionGeometry, fixture.document.pages[0].nodes[1].insertionGeometry)
        try session.undo(); XCTAssertEqual(session.document.pages, inheritedFluid)
        try session.undo(); XCTAssertEqual(session.document.pages, fixture.document.pages)
        try session.redo(); try session.redo()
        let beforeHeightReset = session.document.pages
        try session.execute(registry.prepareDimensionReset(.height, source: .override(.mobile),
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], breakpoint: .mobile, in: session.document, context: fixture.context))
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty(heightKey))
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: session.document.pages[0].nodes[1]).widthMode, .fill)
        try session.undo(); XCTAssertEqual(session.document.pages, beforeHeightReset)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testSizingExactDimensionResetRejectsStaleLockedMixedAndCancelledWithoutMutation() throws {
        var fixture = makeFixture()
        let key = ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)
        fixture.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: .number(360)))
        let registry = SizingConstraintCommandRegistry(), document = fixture.document
        func prepare(_ candidate: CanonicalDocument, selected: [NodeID], revision: UInt64? = nil, cancelled: Bool = false) throws {
            _ = try registry.prepareDimensionReset(.width, source: .override(.tablet),
                identity: .init(editID: GeometryInspectorEditID(), documentID: document.id, pageID: fixture.pageID,
                    revision: revision ?? document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: selected, breakpoint: .tablet, in: candidate,
                context: fixture.context(selectedIDs: selected), cancelled: cancelled)
        }
        XCTAssertThrowsError(try prepare(document, selected: [fixture.nodeID], cancelled: true))
        XCTAssertThrowsError(try prepare(document, selected: [fixture.nodeID], revision: document.revision + 1))
        XCTAssertThrowsError(try prepare(document, selected: [fixture.nodeID, fixture.secondNodeID]))
        var locked = document
        locked.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: "locked"), value: .boolean(true)))
        XCTAssertThrowsError(try prepare(locked, selected: [fixture.nodeID]))
        XCTAssertEqual(fixture.document, document)
    }

    func testSizingModeEligibilityAndConversionScopeUseTheSameSupportedSubset() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .stack
        fixture.document.pages[0].nodes[1].childIDs = [fixture.secondNodeID]
        fixture.document.pages[0].nodes[0].childIDs = [fixture.nodeID]
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        fixture.document.pages[0].nodes[2].parent = .node(fixture.nodeID)
        let page = fixture.document.pages[0]
        var image = page.nodes[2]; image.kind = .image
        XCTAssertFalse(SizingConstraintCommandRegistry.supportsMode(.height, .hug, node: image, page: page))
        XCTAssertFalse(SizingConstraintCommandRegistry.supportsMode(.width, .hug, node: page.nodes[1], page: page))
        XCTAssertTrue(SizingConstraintCommandRegistry.supportsMode(.width, .fill, node: page.nodes[1], page: page))
        let context = fixture.context
        let scope = SizingConstraintCommandRegistry.conversionScope(page: page, context: context)
        XCTAssertEqual(scope.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(scope.skippedNodeIDs, [fixture.secondNodeID])
        let prepared = try SizingConstraintCommandRegistry().prepare(.init(identity:
            .init(editID: GeometryInspectorEditID(), documentID: fixture.document.id, pageID: fixture.pageID,
                revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .convertContent, cancelled: false), in: fixture.document, context: context)
        XCTAssertEqual(prepared.applicableNodeIDs, scope.applicableNodeIDs)
        XCTAssertEqual(prepared.skippedNodeIDs, scope.skippedNodeIDs)
        let cancelled = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: fixture.document.id,
            pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .convertContent, cancelled: true)
        XCTAssertThrowsError(try SizingConstraintCommandRegistry().prepare(cancelled, in: fixture.document, context: context))
        var locked = fixture.document
        locked.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: "locked"), value: .boolean(true)))
        XCTAssertTrue(SizingConstraintCommandRegistry.conversionScope(page: locked.pages[0], context: context).applicableNodeIDs.isEmpty)
    }

    func testLayoutNumericDraftRetainsInvalidInputAndRejectsContextChanges() {
        let fixture = makeFixture()
        let scope = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
            sceneID: fixture.sceneID, orderedNodeIDs: [fixture.nodeID], breakpoint: .desktop, viewportWidth: 1440)
        for text in ["320", "-", "1e", ""] {
            var draft = LayoutInspectorNumericDraft(text: text, committed: "120", scope: scope)
            draft.adopt(committed: "120", scope: scope)
            draft.adopt(committed: nil, scope: scope)
            XCTAssertEqual(draft.text, text)
            XCTAssertTrue(draft.canCommit(in: scope), "Parsing remains the existing registry/locale parser's responsibility")
            let other = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
                sceneID: fixture.sceneID, orderedNodeIDs: [fixture.nodeID], breakpoint: .mobile, viewportWidth: 390)
            draft.adopt(committed: "120", scope: other)
            XCTAssertEqual(draft.conflict, .contextChanged)
            XCTAssertEqual(draft.text, text)
            XCTAssertFalse(draft.canCommit(in: other))
            XCTAssertFalse(draft.canCommit(in: scope), "Switching back cannot silently rearm a conflicted edit")
        }
        var changed = LayoutInspectorNumericDraft(text: "320", committed: "120", scope: scope)
        changed.adopt(committed: "240", scope: scope)
        XCTAssertEqual(changed.conflict, .valueChanged)
        XCTAssertFalse(changed.canCommit(in: scope))
        for (selected, width) in [([fixture.secondNodeID], 1440.0), ([fixture.nodeID], 1200.0)] {
            let other = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
                sceneID: fixture.sceneID, orderedNodeIDs: selected, breakpoint: .desktop, viewportWidth: width)
            var retained = LayoutInspectorNumericDraft(text: "1e", committed: "120", scope: scope)
            retained.adopt(committed: nil, scope: other)
            XCTAssertEqual(retained.conflict, .contextChanged)
            XCTAssertEqual(retained.text, "1e")
            XCTAssertFalse(retained.canCommit(in: other))
        }
    }

    func testSizingDiagnosticsRemainBoundedAndExcludeRawObjectIdentity() {
        let fixture = makeFixture(), diagnostics = CommandDiagnostics(capacity: 2)
        for succeeded in [false, true, false] {
            diagnostics.recordSizingOperation(pageID: fixture.pageID, nodeIDs: [fixture.nodeID], succeeded: succeeded, durationMilliseconds: 1)
        }
        XCTAssertEqual(diagnostics.records.count, 2)
        XCTAssertEqual(diagnostics.droppedRecordCount, 1)
        for record in diagnostics.records {
            XCTAssertTrue(record.requirementIDs.contains("SF-0505-003"))
            XCTAssertTrue(record.requirementIDs.contains("SF-0604-005"))
            XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
            XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.pageID.description))
        }
    }

    func testHugFlowContainerRejectsFillHeightCycleWithoutChangingCanonicalIntent() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[0].childIDs = [fixture.nodeID]
        fixture.document.pages[0].nodes[1].kind = .stack
        fixture.document.pages[0].nodes[1].childIDs = [fixture.secondNodeID]
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        fixture.document.pages[0].nodes[2].parent = .node(fixture.nodeID)
        fixture.document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"), value: .string("fill")))
        try fixture.document.validate()
        let before = fixture.document
        let command = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: before.id,
            pageID: fixture.pageID, revision: before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .setMode(.height, .hug), cancelled: false)
        XCTAssertThrowsError(try SizingConstraintCommandRegistry().prepare(command, in: before, context: fixture.context)) {
            XCTAssertTrue($0.localizedDescription.contains("hug a fill-height child"))
        }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0508-002/005: native Return of an unchanged angle clears its draft
    // without inventing history or displaying an error; invalid input remains rejected.
    func testWorkspaceFillLayerUnchangedAngleIsSuccessfulAndHistoryNeutral() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != state.documentSession.document.revision
                    || state.selectionState.sceneIdentity?.revision != state.documentSession.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.frame, provenance: .menu)
        try await settle()
        let id = FillLayerID()
        XCTAssertTrue(state.commitDesignFillLayer(.addLinearGradient(id: id, angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: .legacySurface),
            .init(id: GradientStopID(), position: 1, color: .init(red: 0.4, green: 0.2, blue: 0.8, alpha: 1)),
        ]), operation: "add gradient"))
        try await settle()
        let before = state.documentSession.document
        let history = state.documentSession.historySnapshot()
        XCTAssertTrue(state.commitDesignFillLayer(.setGradientAngle(id, 45), operation: "angle", provenance: .keyboard))
        XCTAssertNil(state.designInspectorFailure)
        XCTAssertEqual(state.lastDesignInspectorAnnouncement, "Design appearance is unchanged.")
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
        XCTAssertFalse(state.commitDesignFillLayer(.setGradientAngle(id, .nan), operation: "angle", provenance: .keyboard))
        XCTAssertNotNil(state.designInspectorFailure)
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
    }

    // SF-0505-002/004/005: unchanged valid drafts finish without a false error
    // or history entry; invalid and stale attempts remain rejected.
    func testWorkspaceSizingUnchangedDraftIsSuccessfulAndHistoryNeutral() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != state.documentSession.document.revision
                    || state.selectionState.sceneIdentity?.revision != state.documentSession.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.frame, provenance: .menu)
        try await settle()
        XCTAssertTrue(state.commitSizingConstraint(.set(.minWidth, 80)))
        try await settle()
        let before = state.documentSession.document
        let history = state.documentSession.historySnapshot()
        let selection = state.selectionState.orderedIDs
        XCTAssertTrue(state.commitSizingConstraint(.set(.minWidth, 80)))
        XCTAssertEqual(state.lastSizingConstraintAnnouncement, "Sizing is unchanged.")
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
        XCTAssertEqual(state.selectionState.orderedIDs, selection)
        XCTAssertFalse(state.commitSizingConstraint(.set(.minWidth, -.infinity)))
        XCTAssertFalse(state.commitSizingConstraint(.set(.minWidth, 80), expectedContext: "stale"))
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
    }

    // SF-SOURCE-BATCH-20261027-01: new source only, not executed.
    func testSiteSetupOpeningPageIdentityCannotCommitAfterPageSwitch() async throws {
        let session = DocumentSession()
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.websiteSettingsIdentity == nil {
            if ContinuousClock.now >= deadline { XCTFail("Opening scene did not become available"); return }
            await Task.yield()
        }
        let opening = try XCTUnwrap(state.websiteSettingsIdentity)
        let destination = try XCTUnwrap(session.document.websitePages.first { $0.id != opening.pageID })
        state.presentWebsiteSettings()
        state.selectPage(destination.id)
        let nextDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.websiteSettingsIdentity?.pageID != destination.id {
            if ContinuousClock.now >= nextDeadline { XCTFail("Destination scene did not adopt"); return }
            await Task.yield()
        }
        let before = session.document, history = session.historySnapshot()
        XCTAssertFalse(state.commitWebsiteSettings(.init(siteName: "Stale draft", pages: [
            .init(pageID: opening.pageID, title: "Old page title", allowsIndexing: false)
        ]), identity: opening))
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.historySnapshot(), history)
        XCTAssertEqual(state.effectiveSelectedPageID, destination.id)
    }

    func testWebsiteSettingsNoChangeIsNeutralAndStillRejectsStaleIdentity() async throws {
        var document = ProjectCreation.blank()
        document.websiteMetadata = .init(siteName: "Aurora")
        let session = DocumentSession(document: document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.websiteSettingsIdentity == nil {
            guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
            await Task.yield()
        }
        let identity = try XCTUnwrap(state.websiteSettingsIdentity)
        let before = session.document
        XCTAssertTrue(state.commitWebsiteSettings(before.websiteMetadata, identity: identity))
        XCTAssertEqual(state.websiteSettingsStatus, "Site Settings are unchanged.")
        XCTAssertEqual(session.document, before)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(state.lifecycle.isModified)
        let stale = DesignInspectorOperationIdentity(documentID: identity.documentID,
            pageID: identity.pageID, revision: identity.revision + 1,
            sceneID: identity.sceneID, rendererGeneration: identity.rendererGeneration)
        XCTAssertFalse(state.commitWebsiteSettings(before.websiteMetadata, identity: stale))
        XCTAssertEqual(session.document, before)
        XCTAssertFalse(session.canUndo)
    }
    // SF-0402-003/005, SF-0403-003, SF-0701-003: ordinary edits must not
    // mistake a Layers-selected nested parent for an isolation transition.
    func testNestedLayersSelectionSurvivesTextGeometryAndRendererAdoptionWithoutIsolation() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != state.documentSession.document.revision
                    || state.selectionState.sceneIdentity?.revision != state.documentSession.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.section, provenance: .menu)
        try await settle()
        let section = try XCTUnwrap(state.selectionState.primaryID)
        state.selectLayer(section)
        state.performDefaultInsertion(.text, provenance: .menu)
        try await settle()
        let text = try XCTUnwrap(state.selectionState.primaryID)
        state.selectLayer(text)
        XCTAssertEqual(state.selectionState.activeContainerID, section)
        XCTAssertNil(state.isolationRootID)
        XCTAssertTrue(state.beginTextEditing(nodeID: text, provenance: .menu))
        state.updateTextEditingDraft(text: "The Journal", selection: .init(location: 11, length: 0), markedRange: nil)
        state.commitTextEditing()
        XCTAssertEqual(state.selectionState.primaryID, text)
        try await settle()
        XCTAssertEqual(state.selectionState.activeContainerID, section)
        XCTAssertEqual(state.selectionState.primaryID, text)
        XCTAssertTrue(state.commitGeometryInspectorValue(600, field: .width, provenance: .keyboard))
        XCTAssertEqual(state.selectionState.primaryID, text)
        try await settle()
        XCTAssertEqual(state.selectionState.primaryID, text)
        XCTAssertEqual(state.selectionState.activeContainerID, section)
        state.undo(); try await settle()
        XCTAssertEqual(state.selectionState.primaryID, text)
        state.redo(); try await settle()
        XCTAssertEqual(state.selectionState.primaryID, text)
        XCTAssertNil(state.isolationRootID)
    }

    func testFrameSectionImageFillIsAtomicScopedAndMissingSafe() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        fixture.document.pages[0].nodes[2].kind = .section
        applyStructuralDefaults(for: .section, to: &fixture.document.pages[0].nodes[2])
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Card",
            originalFilename: "card.png", format: .png, pixelWidth: 4, pixelHeight: 3,
            byteCount: 16, contentHash: String(repeating: "a", count: 64))
        fixture.document.imageAssets = [asset]
        let session = DocumentSession(document: fixture.document)
        let ids = [fixture.nodeID, fixture.secondNodeID]
        func node(_ id: NodeID) -> DocumentNode {
            session.document.pages[0].nodes.first { $0.id == id }!
        }
        func prepare(_ edit: ImageFillEdit, ids: [NodeID] = []) throws -> PreparedImageInspectorEdit {
            let selected = ids.isEmpty ? [fixture.nodeID, fixture.secondNodeID] : ids
            return try ImageFillCommandRegistry().prepare(edit, identity: .init(
                documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration, selectedNodeIDs: selected),
                in: session.document, context: fixture.context(selectedIDs: selected))
        }
        let applied = try prepare(.setAsset(asset.id))
        XCTAssertEqual(applied.applicableNodeIDs, ids)
        try session.execute(applied.command)
        XCTAssertEqual(CanonicalImageFill.resolve(node(fixture.nodeID))?.mode, .fill)
        let propertyID = try XCTUnwrap(node(fixture.nodeID).insertionProperty(CanonicalImageFill.assetKey)?.id)
        XCTAssertFalse(CommandRegistry().availability(for: .removeImageAsset(.init(assetID: asset.id)),
            in: session.document).isEnabled)
        let mode = try prepare(.setMode(.fit))
        try session.execute(mode.command)
        XCTAssertEqual(CanonicalImageFill.resolve(node(fixture.secondNodeID))?.mode, .fit)
        try session.undo()
        XCTAssertEqual(CanonicalImageFill.resolve(node(fixture.nodeID))?.mode, .fill)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let staticTree = try InternalDocumentRenderTreeCompiler.compile(page: session.document.pages[0],
            documentID: session.document.id, revision: session.document.revision)
        XCTAssertEqual(staticTree.nodes.first { $0.id == fixture.nodeID }?.imageFill?.assetID, asset.id)
        let plannedTree = try InternalDocumentRenderTreeCompiler.compile(page: session.document.pages[0],
            documentID: session.document.id, revision: session.document.revision,
            imageOutputPaths: [asset.id: "assets/\(asset.contentHash).png"],
            imageAssets: [asset.id: asset])
        let style = StaticFillLayerStyleOutputEmitter.emit(nodes: plannedTree.nodes)
        XCTAssertTrue(style.contains("url(\"assets/\(asset.contentHash).png\")"), style)
        XCTAssertTrue(style.contains("background-size: contain;"), style)
        XCTAssertFalse(style.contains("/Users/"))
        var missing = session.document
        missing.imageAssets = []
        XCTAssertNoThrow(try missing.validate())
        XCTAssertEqual(CanonicalImageFill.resolve(missing.pages[0].nodes[1])?.assetID, asset.id)
        XCTAssertThrowsError(try prepare(.setMode(.stretch)))
        XCTAssertThrowsError(try ImageFillCommandRegistry().prepare(.remove, identity: .init(
            documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration,
            selectedNodeIDs: ids), in: session.document,
            context: fixture.context(selectedIDs: ids), cancelled: true))
        try session.execute(prepare(.remove).command)
        XCTAssertNil(CanonicalImageFill.resolve(node(fixture.nodeID)))
        try session.undo()
        XCTAssertEqual(node(fixture.nodeID).insertionProperty(CanonicalImageFill.assetKey)?.id, propertyID)
        let detachedProperties: [DocumentCommand] = ids.flatMap { id in
            [CanonicalImageFill.assetKey, CanonicalImageFill.modeKey].compactMap { key in
                node(id).insertionProperty(key).map {
                    .removeProperty(.init(pageID: fixture.pageID, nodeID: id, propertyID: $0.id))
                }
            }
        }
        try session.execute(.batch(detachedProperties + [.removeImageAsset(.init(assetID: asset.id))]))
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertTrue(ids.allSatisfy { CanonicalImageFill.resolve(node($0)) == nil })
        try session.undo()
        XCTAssertEqual(node(fixture.nodeID).insertionProperty(CanonicalImageFill.assetKey)?.id, propertyID)
        XCTAssertEqual(session.document.imageAssets.first?.id, asset.id)
        var malformed = session.document
        let malformedIndex = try XCTUnwrap(malformed.pages[0].nodes[1].properties.firstIndex {
            $0.key.rawValue == CanonicalImageFill.modeKey
        })
        malformed.pages[0].nodes[1].properties[malformedIndex].value = .string("stretch")
        XCTAssertThrowsError(try malformed.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidImageReference)
        }
    }

    func testTextForegroundLiteralTokenFallbackHistoryAndValidation() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[2].kind = .button
        let token = LocalColorToken(name: "Ink", color: .init(red: 0.8, green: 0.1, blue: 0.2, alpha: 1))
        fixture.document.colorTokens = [token]
        let literal = CanonicalSolidColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        let session = DocumentSession(document: fixture.document)
        let ids = [fixture.nodeID, fixture.secondNodeID]
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        func typography(_ edit: TypographyEdit) throws {
            let command = TypographyCommand(identity: .init(documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: false)
            let prepared = try TypographyCommandRegistry().prepare(command, in: session.document,
                context: fixture.context(selectedIDs: ids))
            XCTAssertEqual(prepared.applicableNodeIDs, ids)
            try session.execute(prepared.documentCommand)
        }
        func tokenEdit(_ edit: LocalColorTokenEdit) throws {
            try session.execute(LocalColorTokenCommandRegistry.prepare(edit, in: session.document,
                expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
                pageID: fixture.pageID, selectedNodeIDs: ids))
        }
        XCTAssertNil(CanonicalTextForeground.literal(for: node()))
        try typography(.foreground(literal))
        let channelIDs = CanonicalTextForeground.channels.compactMap {
            node().insertionProperty(CanonicalTextForeground.prefix + $0)?.id
        }
        XCTAssertEqual(channelIDs.count, 4)
        XCTAssertEqual(CanonicalTextForeground.literal(for: node()), literal)
        XCTAssertEqual(CanonicalTextForeground.literal(for: session.document.pages[0].nodes[2]), literal)
        let literalCSS = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document)
            .files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(literalCSS.contains("color: rgba(51.0, 76.5, 102.0, 1.0)"), literalCSS)
        try tokenEdit(.bindTarget(token.id, .textForeground))
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: node(), tokens: session.document.colorTokens), token.color)
        XCTAssertEqual(CanonicalTextForeground.literal(for: node()), literal)
        let tokenCSS = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document)
            .files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(tokenCSS.contains("color: rgba(204.0, 25.5, 51.0, 1.0)"), tokenCSS)
        XCTAssertThrowsError(try tokenEdit(.delete(token.id)))
        try tokenEdit(.recolor(token.id, .init(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)))
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: node(), tokens: session.document.colorTokens)?.green, 0.7)
        try session.undo()
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: node(), tokens: session.document.colorTokens), token.color)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        var missing = session.document
        missing.colorTokens = []
        XCTAssertNoThrow(try missing.validate())
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: missing.pages[0].nodes[1], tokens: []), literal)
        try tokenEdit(.unbindTarget(.textForeground))
        XCTAssertNil(LocalColorTokenBinding.id(for: node(), target: .textForeground))
        XCTAssertEqual(CanonicalTextForeground.literal(for: node())?.green, 0.7)
        try session.undo()
        XCTAssertEqual(CanonicalTextForeground.literal(for: node()), literal)
        XCTAssertEqual(CanonicalTextForeground.channels.compactMap {
            node().insertionProperty(CanonicalTextForeground.prefix + $0)?.id
        }, channelIDs)
        try session.redo()
        try typography(.foreground(nil))
        XCTAssertNil(CanonicalTextForeground.literal(for: node()))
        try session.undo()
        XCTAssertEqual(CanonicalTextForeground.literal(for: node())?.green, 0.7)
        XCTAssertThrowsError(try typography(.foreground(.init(red: .nan, green: 0, blue: 0, alpha: 1))))
        var malformed = session.document
        malformed.pages[0].nodes[1].properties.removeAll { $0.key.rawValue == CanonicalTextForeground.prefix + "alpha" }
        XCTAssertThrowsError(try malformed.validate())
        malformed = session.document
        malformed.pages[0].nodes[1].kind = .frame
        XCTAssertThrowsError(try malformed.validate())
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testLocalColorTokenBorderShadowBindingHistoryAndStaticResolution() throws {
        var fixture = makeFixture()
        let literalBorder = CanonicalSolidColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        let literalShadow = CanonicalSolidColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        let tokenColor = CanonicalSolidColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        let token = LocalColorToken(name: "Accent", color: tokenColor)
        fixture.document.colorTokens = [token]
        let box = CanonicalBoxStyle(border: .init(color: literalBorder, width: 2, style: .solid),
            cornerRadius: 8, shadow: .init(color: literalShadow, offsetX: 2, offsetY: 4,
                blur: 8, spread: 0))
        fixture.document.pages[0].nodes[1].properties += DesignBoxStyleCommandRegistry.propertyValues(for: box)
            .sorted { $0.key < $1.key }.map { .init(key: .init(rawValue: $0.key), value: $0.value, origin: .authored) }
        let session = DocumentSession(document: fixture.document)
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        func edit(_ value: LocalColorTokenEdit) throws {
            let command = try LocalColorTokenCommandRegistry.prepare(value, in: session.document,
                expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
                pageID: fixture.pageID, selectedNodeIDs: [fixture.nodeID])
            try session.execute(command)
        }
        try edit(.bindTarget(token.id, .border))
        try edit(.bindTarget(token.id, .outerShadow))
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.border?.color, tokenColor)
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.shadow?.color, tokenColor)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.border?.color, literalBorder)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.shadow?.color, literalShadow)
        let blockedRemoval = DesignBoxStyleCommand(identity: .init(documentID: session.document.id,
            pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .border(nil),
            provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try DesignBoxStyleCommandRegistry().prepare(blockedRemoval,
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        let staticPlan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let css = try XCTUnwrap(staticPlan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("border: 2.0px solid rgba(204.0, 25.5, 51.0, 1.0)"), css)
        XCTAssertTrue(css.contains("box-shadow: 2.0px 4.0px 8.0px 0.0px rgba(204.0, 25.5, 51.0, 1.0)"), css)
        XCTAssertThrowsError(try edit(.delete(token.id)))
        let borderID = try XCTUnwrap(node().insertionProperty(LocalColorTokenBinding.key(for: .border))?.id)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        try edit(.recolor(token.id, .init(red: 0.1, green: 0.7, blue: 0.3, alpha: 0.6)))
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.border?.color.green, 0.7)
        try session.undo()
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.border?.color, tokenColor)
        try session.redo()
        try edit(.unbindTarget(.border))
        XCTAssertNil(LocalColorTokenBinding.id(for: node(), target: .border))
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.border?.color.green, 0.7)
        try session.undo()
        XCTAssertEqual(node().insertionProperty(LocalColorTokenBinding.key(for: .border))?.id, borderID)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.border?.color, literalBorder)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testLocalColorTokenSchemaNineFillBindingMigratesToTargetKeyedIdentity() throws {
        var fixture = makeFixture()
        let token = LocalColorToken(name: "Accent", color: .legacySurface)
        fixture.document.colorTokens = [token]
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted))
        let binding = NodeProperty(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description), origin: .authored)
        fixture.document.pages[0].nodes[1].properties.append(binding)
        let current = try DocumentSerializer.encode(fixture.document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        var body = try XCTUnwrap(envelope["document"] as? [String: Any])
        var pages = try XCTUnwrap(body["pages"] as? [[String: Any]])
        var nodes = try XCTUnwrap(pages[0]["nodes"] as? [[String: Any]])
        let nodeIndex = try XCTUnwrap(nodes.firstIndex { ($0["id"] as? String) == fixture.nodeID.description })
        var properties = try XCTUnwrap(nodes[nodeIndex]["properties"] as? [[String: Any]])
        let propertyIndex = try XCTUnwrap(properties.firstIndex { ($0["key"] as? String) == LocalColorTokenBinding.key(for: .fill) })
        properties[propertyIndex]["key"] = LocalColorTokenBinding.legacyKey
        nodes[nodeIndex]["properties"] = properties
        pages[0]["nodes"] = nodes; body["pages"] = pages
        body.removeValue(forKey: "websiteMetadata") // Historical schema 9 has no metadata field.
        envelope["document"] = body
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)))
        envelope["schemaVersion"] = 9
        let migrated = try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope))
        let migratedNode = try XCTUnwrap(migrated.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(migratedNode.insertionProperty(LocalColorTokenBinding.key(for: .fill))?.id, binding.id)
        XCTAssertNil(migratedNode.insertionProperty(LocalColorTokenBinding.legacyKey))
        XCTAssertEqual(LocalColorTokenBinding.id(for: migratedNode), token.id)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(migrated)), migrated)
    }

    func testLocalColorTokenTargetValidationFallbackMixedAndNeutralFailures() throws {
        var fixture = makeFixture()
        let literal = CanonicalSolidColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let token = LocalColorToken(name: "Accent", color: .legacySurface)
        fixture.document.colorTokens = [token]
        let box = CanonicalBoxStyle(border: .init(color: literal, width: 2, style: .solid),
            cornerRadius: nil, shadow: nil)
        fixture.document.pages[0].nodes[1].properties += DesignBoxStyleCommandRegistry.propertyValues(for: box)
            .sorted { $0.key < $1.key }.map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        fixture.document.pages[0].nodes[2].kind = .text
        let selected = [fixture.nodeID, fixture.secondNodeID]
        let prepared = try LocalColorTokenCommandRegistry.prepare(.bindTarget(token.id, .border),
            in: fixture.document, expectedDocumentID: fixture.document.id,
            expectedRevision: fixture.document.revision, pageID: fixture.pageID,
            selectedNodeIDs: selected)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared)
        let bound = session.document.pages[0].nodes[1]
        XCTAssertEqual(LocalColorTokenBinding.id(for: bound, target: .border), token.id)
        XCTAssertEqual(session.document.pages[0].nodes[2], fixture.document.pages[0].nodes[2])
        var missing = session.document
        missing.colorTokens = []
        XCTAssertNoThrow(try missing.validate())
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: missing.pages[0].nodes[1], tokens: [])?.border?.color, literal)
        let original = try DocumentSerializer.encode(session.document)
        XCTAssertThrowsError(try LocalColorTokenCommandRegistry.prepare(.bindTarget(token.id, .outerShadow),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, pageID: fixture.pageID,
            selectedNodeIDs: [fixture.nodeID]))
        XCTAssertThrowsError(try LocalColorTokenCommandRegistry.prepare(.unbindTarget(.border),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision + 1, pageID: fixture.pageID,
            selectedNodeIDs: [fixture.nodeID]))
        XCTAssertThrowsError(try LocalColorTokenCommandRegistry.prepare(.unbindTarget(.border),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, pageID: fixture.pageID,
            selectedNodeIDs: [fixture.nodeID], cancelled: true))
        XCTAssertEqual(try DocumentSerializer.encode(session.document), original)
        var invalid = session.document
        invalid.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .outerShadow)),
            value: .string(token.id.description)))
        XCTAssertThrowsError(try invalid.validate())
        invalid = session.document
        invalid.pages[0].nodes[2].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .border)),
            value: .string(token.id.description)))
        XCTAssertThrowsError(try invalid.validate())
    }

    func testSizingNamespaceRejectsMalformedUnsupportedAndContradictoryProperties() throws {
        let fixture = makeFixture()
        func expectInvalid(_ properties: [NodeProperty], kind: NodeKind = .frame,
                           expected: ModelValidationError = .invalidSizingConstraints) {
            var document = fixture.document
            document.pages[0].nodes[1].kind = kind
            document.pages[0].nodes[1].properties.append(contentsOf: properties)
            XCTAssertThrowsError(try document.validate()) { error in
                XCTAssertEqual(error as? ModelValidationError, expected)
            }
        }
        func property(_ suffix: String, _ value: PropertyValue) -> NodeProperty {
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + suffix),
                value: value, origin: .authored)
        }
        expectInvalid([property("minWidth", .number(.nan))])
        expectInvalid([property("minWidth", .string("10"))])
        expectInvalid([property("minWidth", .number(300)), property("maxWidth", .number(100))])
        expectInvalid([property("maxWidth", .number(0))])
        expectInvalid([property("aspectEnabled", .boolean(true))])
        expectInvalid([property("aspectRatio", .number(0))])
        expectInvalid([property("minWidth", .number(100)), property("maxHeight", .number(2)),
            property("aspectRatio", .number(1)), property("aspectEnabled", .boolean(true))])
        expectInvalid([property("minWidth", .number(100)), property("minWidth", .number(100))],
            expected: .duplicatePropertyKey)
        expectInvalid([property("minWidth", .number(10))], kind: .text)
    }

    func testResponsiveContentConversionIsExplicitAtomicAndRestoresOverridesAndIDs() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[0].childIDs = [fixture.nodeID]
        fixture.document.pages[0].nodes[1].kind = .stack
        fixture.document.pages[0].nodes[1].childIDs = [fixture.secondNodeID]
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[2].parent = .node(fixture.nodeID)
        let override = NodeProperty(key: .init(rawValue: ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)),
            value: .number(280), origin: .authored)
        fixture.document.pages[0].nodes[2].properties.append(override)
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        let selected = [fixture.nodeID, fixture.secondNodeID]
        let context = fixture.context(selectedIDs: selected)
        let command = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: selected, edit: .convertContent, cancelled: false)
        let prepared = try SizingConstraintCommandRegistry().prepare(command, in: session.document, context: context)
        XCTAssertEqual(prepared.applicableNodeIDs, selected, "An ancestor and child selection converts each node exactly once")
        try session.execute(prepared.documentCommand)
        let committed = session.document
        for node in committed.pages[0].nodes.dropFirst() {
            let sizing = CanonicalSizingConstraints.resolved(for: node)
            XCTAssertEqual(sizing.widthMode, .fill)
            XCTAssertEqual(sizing.heightMode, .hug)
            XCTAssertNil(node.insertionProperty(override.key.rawValue))
        }
        XCTAssertEqual(committed.pages[0].nodes.map(\.id), fixture.document.pages[0].nodes.map(\.id))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(committed)), committed)
        XCTAssertThrowsError(try SizingConstraintCommandRegistry().prepare(command, in: committed, context: context))
        try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)
        XCTAssertEqual(session.document.pages[0].nodes[2].insertionProperty(override.key.rawValue), override)
        try session.redo()
        XCTAssertEqual(session.document.pages, committed.pages)
    }

    func testSizingModesCommitSeparatelyPreserveFallbackAndExactInverse() throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let context = fixture.context(selectedIDs: [fixture.nodeID])
        let original = session.document.pages
        func prepared(_ edit: SizingConstraintEdit, cancelled: Bool = false, revision: UInt64? = nil) throws -> SizingConstraintCommandRegistry.Prepared {
            try SizingConstraintCommandRegistry().prepare(.init(identity: .init(editID: GeometryInspectorEditID(),
                documentID: session.document.id, pageID: fixture.pageID,
                revision: revision ?? session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID],
                edit: edit, cancelled: cancelled), in: session.document, context: context)
        }
        try session.execute(prepared(.setMode(.width, .fill)).documentCommand)
        let widthState = session.document.pages
        let widthID = try XCTUnwrap(widthState[0].nodes[1].insertionProperty(CanonicalSizingConstraints.prefix + "widthMode")?.id)
        try session.execute(prepared(.setMode(.height, .hug)).documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionGeometry, original[0].nodes[1].insertionGeometry)
        XCTAssertEqual(session.document.pages[0].nodes[1].id, fixture.nodeID)
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: session.document.pages[0].nodes[1]).heightMode, .hug)
        let committed = session.document
        XCTAssertThrowsError(try prepared(.setMode(.width, .hug)))
        XCTAssertThrowsError(try prepared(.setMode(.height, .fixed), cancelled: true))
        XCTAssertThrowsError(try prepared(.reset, revision: 0))
        XCTAssertEqual(session.document, committed)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(committed)), committed)
        try session.undo()
        XCTAssertEqual(session.document.pages, widthState)
        try session.undo()
        XCTAssertEqual(session.document.pages, original)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(CanonicalSizingConstraints.prefix + "widthMode")?.id, widthID)
        try session.redo()
        XCTAssertEqual(session.document.pages, committed.pages)
        try session.execute(prepared(.reset).documentCommand)
        XCTAssertEqual(session.document.pages, original)
        try session.undo()
        XCTAssertEqual(session.document.pages, committed.pages)
    }

    // SF-0703-001/002/005: "+=" / "-=" changes every selected object by the
    // same amount from its own value in one transaction; objects whose result
    // would be out of range are skipped and reported, never clamped; when
    // nothing applies the edit is refused; Undo restores every object.
    func testRelativeGeometryEditChangesEachObjectFromItsOwnValueInOneTransaction() throws {
        let fixture = makeFixture()
        let ids = [fixture.nodeID, fixture.secondNodeID]
        let session = DocumentSession(document: fixture.document)
        let registry = GeometryInspectorCommandRegistry()
        func command(_ field: GeometryInspectorField, delta: Double) -> GeometryInspectorCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids, field: field, value: 0, provenance: .automation, relativeDelta: delta)
        }
        XCTAssertEqual(registry.value(for: .x, in: session.document, context: fixture.context(selectedIDs: ids)), .mixed,
                       "Different X values show as Mixed")
        let moved = try registry.prepare(command(.x, delta: 15), in: session.document, context: fixture.context(selectedIDs: ids))
        XCTAssertTrue(moved.skippedNodeIDs.isEmpty)
        try session.execute(moved.documentCommand)
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.origin.x, 25)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.origin.x, 215)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1, "One transaction for the whole selection")

        let narrowed = try registry.prepare(command(.width, delta: -100), in: session.document,
                                            context: fixture.context(selectedIDs: ids))
        XCTAssertEqual(narrowed.skippedNodeIDs, [fixture.secondNodeID], "90 − 100 is out of range: skipped, not clamped")
        try session.execute(narrowed.documentCommand)
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.size.width, 20)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.size.width, 90)
        XCTAssertThrowsError(try registry.prepare(command(.width, delta: -1_000), in: session.document,
                                                  context: fixture.context(selectedIDs: ids))) {
            XCTAssertEqual($0 as? GeometryInspectorError, .noApplicableTargets)
        }
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)

        let posix = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(GeometryInspectorRelativeInput.delta("+=10", locale: posix), 10)
        XCTAssertEqual(GeometryInspectorRelativeInput.delta(" -= 4 ", locale: posix), -4)
        XCTAssertEqual(GeometryInspectorRelativeInput.delta("−=2.5", locale: posix), -2.5)
        for input in ["10", "+=", "+=-3", "+=0", "=+5", "+=abc", "+=5.", "*=2"] {
            XCTAssertNil(GeometryInspectorRelativeInput.delta(input, locale: posix), input)
        }
    }

    func testSizingConstraintsSetClampAspectResetAndExactHistory() throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let registry = SizingConstraintCommandRegistry()
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        func command(_ edit: SizingConstraintEdit, cancelled: Bool = false,
                     revision: UInt64? = nil) -> SizingConstraintCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: revision ?? session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: edit, cancelled: cancelled)
        }
        func execute(_ edit: SizingConstraintEdit) throws {
            let prepared = try registry.prepare(command(edit), in: session.document,
                context: fixture.context(selectedIDs: [fixture.nodeID]))
            XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
            try session.execute(prepared.documentCommand)
        }
        try execute(.set(.minWidth, 150))
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 150)
        let minID = try XCTUnwrap(node().insertionProperty(CanonicalSizingConstraints.prefix + "minWidth")?.id)
        try execute(.setAspectEnabled(true))
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: node()).aspectRatio, 150.0 / 80.0)
        let geometry = GeometryInspectorCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], field: .width, value: 200, provenance: .automation)
        let numeric = try GeometryInspectorCommandRegistry().prepare(geometry, in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))
        try session.execute(numeric.documentCommand)
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 200)
        XCTAssertEqual(node().insertionGeometry?.frame.size.height ?? 0, 200 / (150.0 / 80.0), accuracy: 0.0001)
        try execute(.set(.maxWidth, 160))
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 160)
        let resize = GeometryTransformCommand(identity: .init(sessionID: TransformSessionID(),
            documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision, sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID],
            operation: .resize(handle: .left, delta: .init(dx: 40, dy: 0), constraint: .none),
            provenance: .automation)
        let resized = try TransformCommandRegistry().prepare(resize, in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))
        XCTAssertEqual(resized.geometries[0].preview.size.width, 150)
        XCTAssertEqual(resized.geometries[0].preview.origin.x, 20)
        try session.execute(resized.documentCommand)
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 150)
        XCTAssertThrowsError(try registry.prepare(command(.set(.minWidth, 500)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(.set(.minHeight, .nan)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(.reset, cancelled: true),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(.reset, revision: 0),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        let beforeReset = session.document
        try execute(.reset)
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: node()), .unconstrained)
        try session.undo()
        XCTAssertEqual(session.document.pages, beforeReset.pages)
        XCTAssertEqual(node().insertionProperty(CanonicalSizingConstraints.prefix + "minWidth")?.id, minID)
        try session.redo()
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: node()), .unconstrained)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testSizingConstraintMixedSelectionSkipsTextAndPreservesIdentity() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[2].kind = .text
        let originalText = fixture.document.pages[0].nodes[2]
        let session = DocumentSession(document: fixture.document)
        let selected = [fixture.nodeID, originalText.id]
        let context = fixture.context(selectedIDs: selected)
        let command = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision, sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: selected,
            edit: .set(.maxWidth, 180), cancelled: false)
        let prepared = try SizingConstraintCommandRegistry().prepare(command,
            in: session.document, context: context)
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(prepared.skippedNodeIDs, [originalText.id])
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[2], originalText)
        XCTAssertEqual(session.document.pages[0].nodes[1].id, fixture.nodeID)
        try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)
    }

    // SF-0509-001...005 — one stable local token propagates to bound solid
    // fills while exact history and the literal fallback remain intact.
    func testLocalColorTokenCreateBindRecolorUnbindHistoryAndPersistence() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted))
        let session = DocumentSession(document: fixture.document)
        let registry = LocalColorTokenCommandRegistry.self
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        func prepare(_ edit: LocalColorTokenEdit, ids: [NodeID] = []) throws -> DocumentCommand {
            try registry.prepare(edit, in: session.document, expectedDocumentID: session.document.id,
                expectedRevision: session.document.revision, pageID: fixture.pageID, selectedNodeIDs: ids)
        }
        try session.execute(prepare(.create(name: "Brand", color: blue)))
        let token = try XCTUnwrap(session.document.colorTokens.first)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try prepare(.create(name: "brand", color: blue)))
        XCTAssertThrowsError(try prepare(.create(name: " ", color: blue)))
        try session.execute(prepare(.bind(token.id), ids: [fixture.nodeID]))
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, blue)
        XCTAssertEqual(LocalColorTokenResolver.fillValue(nodes: [node()], in: session.document), .single(blue, .authored))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: node()).last?.solidColor, .legacySurface)
        let literalEdit = DesignFillLayerCommand(
            identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .replaceSolid(blue),
            provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try DesignInspectorCommandRegistry().prepare(literalEdit,
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try prepare(.delete(token.id)))
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#C02030E0"))
        try session.execute(prepare(.update(token.id, name: "Accent", color: red)))
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, red)
        XCTAssertTrue(LocalColorTokenResolver.status(for: node(), in: session.document)?.contains("Accent") == true)
        try session.undo()
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, blue)
        try session.redo()
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, red)
        try session.execute(prepare(.unbind, ids: [fixture.nodeID]))
        XCTAssertNil(LocalColorTokenBinding.id(for: node()))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: node()).last?.solidColor, red)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        try session.undo()
        XCTAssertEqual(LocalColorTokenBinding.id(for: node()), token.id)
        try session.redo()
        try session.execute(prepare(.delete(token.id)))
        XCTAssertTrue(session.document.colorTokens.isEmpty)
    }

    func testLocalColorTokenSchemaEightMigrationAndStrictCurrentDecode() throws {
        let fixture = makeFixture()
        let encoded = try DocumentSerializer.encode(fixture.document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var document = try XCTUnwrap(envelope["document"] as? [String: Any])
        document.removeValue(forKey: "colorTokens")
        document.removeValue(forKey: "websiteMetadata")
        envelope["schemaVersion"] = 8
        envelope["document"] = document
        let historical = try JSONSerialization.data(withJSONObject: envelope)
        let migrated = try DocumentSerializer.decode(historical)
        XCTAssertEqual(migrated.id, fixture.document.id)
        XCTAssertEqual(migrated.pages, fixture.document.pages)
        XCTAssertTrue(migrated.colorTokens.isEmpty)
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        let session = DocumentSession(document: migrated)
        try session.execute(LocalColorTokenCommandRegistry.prepare(.create(name: "Brand", color: color),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, pageID: fixture.pageID))
        let roundTrip = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(roundTrip, session.document)
        XCTAssertEqual(roundTrip.colorTokens.first?.name, "Brand")
        var current = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(session.document)) as? [String: Any])
        var currentDocument = try XCTUnwrap(current["document"] as? [String: Any])
        var tokens = try XCTUnwrap(currentDocument["colorTokens"] as? [[String: Any]])
        tokens[0]["unexpected"] = true
        currentDocument["colorTokens"] = tokens
        current["document"] = currentDocument
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: current)))
    }

    func testLocalColorTokenRegistryRejectsStaleCancelledAndInapplicableEditsWithoutMutation() throws {
        let fixture = makeFixture()
        let document = fixture.document
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        let registry = LocalColorTokenCommandRegistry.self
        let original = try DocumentSerializer.encode(document)
        XCTAssertThrowsError(try registry.prepare(.create(name: "Brand", color: color), in: document,
            expectedDocumentID: DocumentID(), expectedRevision: document.revision, pageID: fixture.pageID))
        XCTAssertThrowsError(try registry.prepare(.create(name: "Brand", color: color), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision + 1, pageID: fixture.pageID))
        XCTAssertThrowsError(try registry.prepare(.create(name: "Brand", color: color), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision,
            pageID: fixture.pageID, cancelled: true))
        XCTAssertThrowsError(try registry.prepare(.bind(ColorTokenID()), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision,
            pageID: fixture.pageID, selectedNodeIDs: [fixture.nodeID]))
        XCTAssertThrowsError(try registry.prepare(.unbind, in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision,
            pageID: fixture.pageID, selectedNodeIDs: [fixture.nodeID, fixture.nodeID]))
        XCTAssertEqual(try DocumentSerializer.encode(document), original)
    }

    func testLocalColorTokenResolvesAllSupportedStructuralKindsAndMissingFallback() throws {
        let fixture = makeFixture()
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        let token = LocalColorToken(name: "Brand", color: color)
        var document = fixture.document
        document.colorTokens = [token]
        for kind in [NodeKind.frame, .section, .stack, .grid] {
            let node = DocumentNode(kind: kind, name: "Structure", parent: .page(fixture.pageID), properties: [
                .init(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted),
                .init(key: .init(rawValue: LocalColorTokenBinding.key), value: .string(token.id.description), origin: .authored),
            ])
            XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node, in: document).last?.solidColor, color)
            document.colorTokens = []
            XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node, in: document).last?.solidColor, .legacySurface)
            XCTAssertTrue(LocalColorTokenResolver.status(for: node, in: document)?.contains("Missing") == true)
            document.colorTokens = [token]
        }
    }
    // SF-0403-001, SF-0403-002, SF-0403-003
    func testMoveResolutionIsExactAndAxisConstrained() throws {
        let frame = WorldRect(
            origin: .init(x: 10, y: 20),
            size: .init(width: 120, height: 80)
        )
        XCTAssertEqual(
            try TransformCommandRegistry.resolve(
                frame,
                operation: .move(delta: .init(dx: 7, dy: -3), constraint: .none)
            ),
            .init(origin: .init(x: 17, y: 17), size: frame.size)
        )
        XCTAssertEqual(
            try TransformCommandRegistry.resolve(
                frame,
                operation: .move(delta: .init(dx: 7, dy: -3), constraint: .horizontal)
            ).origin,
            .init(x: 17, y: 20)
        )
        XCTAssertEqual(
            try TransformCommandRegistry.resolve(
                frame,
                operation: .move(delta: .init(dx: 7, dy: -3), constraint: .vertical)
            ).origin,
            .init(x: 10, y: 17)
        )
    }

    // SF-0403-001, SF-0403-002, SF-0403-003
    func testEveryResizeHandleProducesDeterministicPositiveGeometry() throws {
        let frame = WorldRect(
            origin: .init(x: 20, y: 30),
            size: .init(width: 100, height: 60)
        )
        let expectations: [TransformHandle: WorldRect] = [
            .topLeft: .init(origin: .init(x: 25, y: 34), size: .init(width: 95, height: 56)),
            .top: .init(origin: .init(x: 20, y: 34), size: .init(width: 100, height: 56)),
            .topRight: .init(origin: .init(x: 20, y: 34), size: .init(width: 105, height: 56)),
            .right: .init(origin: .init(x: 20, y: 30), size: .init(width: 105, height: 60)),
            .bottomRight: .init(origin: .init(x: 20, y: 30), size: .init(width: 105, height: 64)),
            .bottom: .init(origin: .init(x: 20, y: 30), size: .init(width: 100, height: 64)),
            .bottomLeft: .init(origin: .init(x: 25, y: 30), size: .init(width: 95, height: 64)),
            .left: .init(origin: .init(x: 25, y: 30), size: .init(width: 95, height: 60)),
        ]
        for handle in TransformHandle.allCases {
            XCTAssertEqual(
                try TransformCommandRegistry.resolve(
                    frame,
                    operation: .resize(
                        handle: handle,
                        delta: .init(dx: 5, dy: 4),
                        constraint: .none
                    )
                ),
                expectations[handle],
                handle.rawValue
            )
        }
    }

    // SF-0403-002, SF-0403-004
    func testInvalidGeometryAndCancellationAreStateNeutral() throws {
        let fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let before = fixture.document
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: .move(delta: .init(dx: .nan, dy: 0), constraint: .none)),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? TransformError, .invalidDelta) }
        let clampedResize = try registry.prepare(
            fixture.command(operation: .resize(
                handle: .left,
                delta: .init(dx: 500, dy: 0),
                constraint: .none
            )),
            in: fixture.document,
            context: fixture.context
        )
        XCTAssertEqual(clampedResize.geometries[0].preview.size.width, TransformPolicy.minimumDimension)
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: .move(delta: .init(dx: 1, dy: 1), constraint: .none)),
            in: fixture.document,
            context: fixture.context,
            cancellation: .init(isCancelled: { true })
        )) { XCTAssertEqual($0 as? TransformError, .cancelled) }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0403-002, SF-0403-003, SF-0403-004
    func testIdentityScopeStateAndSelectionValidationRejectWithoutMutation() throws {
        var fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let before = fixture.document
        let operation = TransformOperation.move(delta: .init(dx: 2, dy: 3), constraint: .none)
        let missingID = NodeID(UUID(uuidString: "91000000-0000-4000-8000-000000000099")!)
        let crossPageID = fixture.document.pages[1].rootNodeIDs[0]
        let cases: [(GeometryTransformCommand, TransformValidationContext, TransformError)] = [
            (fixture.command(operation: operation, documentID: DocumentID()), fixture.context, .staleDocument),
            (fixture.command(operation: operation, revision: fixture.document.revision + 1), fixture.context, .staleRevision),
            (fixture.command(operation: operation, rendererGeneration: 8), fixture.context, .staleRenderer),
            (fixture.command(operation: operation, orderedIDs: []), fixture.context, .emptySelection),
            (fixture.command(operation: operation, orderedIDs: [fixture.nodeID, fixture.nodeID]),
             fixture.context(selectedIDs: [fixture.nodeID, fixture.nodeID]), .duplicateTarget),
            (fixture.command(operation: operation), fixture.context(selectedIDs: []), .selectionMismatch),
            (fixture.command(operation: operation, orderedIDs: [missingID]),
             fixture.context(selectedIDs: [missingID]), .missingTarget),
            (fixture.command(operation: operation, orderedIDs: [crossPageID]),
             fixture.context(selectedIDs: [crossPageID]), .crossPageTarget),
            (fixture.command(operation: operation),
             fixture.context(selectedIDs: fixture.selectedIDs, availableIDs: []), .unavailableTarget),
            (fixture.command(operation: operation),
             fixture.context(selectedIDs: fixture.selectedIDs, lifecycleAvailable: false),
             .lifecycleUnavailable("A document transition is active.")),
        ]
        for (command, context, error) in cases {
            XCTAssertThrowsError(try registry.prepare(command, in: fixture.document, context: context)) {
                XCTAssertEqual($0 as? TransformError, error)
            }
            XCTAssertEqual(fixture.document, before)
        }
        fixture.document.pages[0].nodes[1].properties.append(booleanProperty("locked", true))
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: operation),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? TransformError, .lockedTarget) }
        fixture.document.pages[0].nodes[1].properties.removeLast()
        fixture.document.pages[0].nodes[1].properties.append(booleanProperty("hidden", true))
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: operation),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? TransformError, .hiddenTarget) }
    }

    // SF-0403-002, SF-0403-003
    func testMultipleMovePreservesOrderAndResizeRejectsIncompatibleSelection() throws {
        let fixture = makeFixture(selectedIDs: nil)
        let ids = [fixture.nodeID, fixture.secondNodeID]
        let context = fixture.context(selectedIDs: ids)
        let move = fixture.command(
            operation: .move(delta: .init(dx: 5, dy: 6), constraint: .none),
            orderedIDs: ids
        )
        let prepared = try TransformCommandRegistry().prepare(
            move, in: fixture.document, context: context
        )
        XCTAssertEqual(prepared.geometries.map(\.nodeID), ids)
        XCTAssertEqual(prepared.geometries.map(\.preview.origin), [
            .init(x: 15, y: 26), .init(x: 205, y: 56),
        ])
        XCTAssertThrowsError(try TransformCommandRegistry().prepare(
            fixture.command(
                operation: .resize(
                    handle: .bottomRight,
                    delta: .init(dx: 5, dy: 5),
                    constraint: .none
                ),
                orderedIDs: ids
            ),
            in: fixture.document,
            context: context
        )) { XCTAssertEqual($0 as? TransformError, .incompatibleMultipleResize) }
    }

    // SF-0403-002, SF-0403-006, SF-0403-008
    func testEveryInputProvenanceUsesOneRegistryAndSpecificDisabledReasons() throws {
        let fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let operation = TransformOperation.move(
            delta: .init(dx: 3, dy: -2),
            constraint: .none
        )
        let commands = try TransformProvenance.allCases.map { provenance in
            var command = fixture.command(operation: operation)
            command = GeometryTransformCommand(
                identity: command.identity,
                orderedNodeIDs: command.orderedNodeIDs,
                operation: command.operation,
                provenance: provenance
            )
            return try registry.prepare(
                command,
                in: fixture.document,
                context: fixture.context
            ).documentCommand
        }
        XCTAssertTrue(commands.dropFirst().allSatisfy { $0 == commands.first })

        let unavailable = registry.availability(
            for: fixture.command(operation: operation),
            in: fixture.document,
            context: fixture.context(
                selectedIDs: fixture.selectedIDs,
                lifecycleAvailable: false
            )
        )
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertEqual(unavailable.disabledReason, "A document transition is active.")
    }

    // SF-0403-001, SF-0403-005
    func testCommitIsOneAtomicTransactionWithExactUndoRedoAndBranchInvalidation() throws {
        let fixture = makeFixture()
        let prepared = try TransformCommandRegistry().prepare(
            fixture.command(operation: .move(
                delta: .init(dx: 14, dy: -8),
                constraint: .none
            )),
            in: fixture.document,
            context: fixture.context
        )
        let session = DocumentSession(document: fixture.document)
        let before = session.document
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.revision, before.revision + 1)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].preview)
        try session.undo()
        XCTAssertEqual(session.document, before.withRevision(before.revision + 2))
        try session.redo()
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].preview)
        try session.undo()
        let branch = try TransformCommandRegistry().prepare(
            fixture.with(document: session.document).command(operation: .move(
                delta: .init(dx: 1, dy: 0),
                constraint: .horizontal
            )),
            in: session.document,
            context: fixture.with(document: session.document).context
        )
        try session.execute(branch.documentCommand)
        XCTAssertFalse(session.canRedo)

        var exhausted = fixture.document
        exhausted.revision = UInt64.max
        let exhaustedFixture = fixture.with(document: exhausted)
        XCTAssertThrowsError(try TransformCommandRegistry().prepare(
            exhaustedFixture.command(operation: .move(
                delta: .init(dx: 1, dy: 0),
                constraint: .horizontal
            )),
            in: exhausted,
            context: exhaustedFixture.context
        )) { XCTAssertEqual($0 as? TransformError, .revisionExhausted) }
    }

    // SF-0403-001, SF-0403-004, SF-0403-005
    func testDeterministicPersistenceHistoryAndPreviewExclusion() async throws {
        let fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let prepared = try registry.prepare(
            fixture.command(operation: .resize(
                handle: .bottomRight,
                delta: .init(dx: 20, dy: 10),
                constraint: .none
            )),
            in: fixture.document,
            context: fixture.context
        )
        var transformSession = TransformSession()
        let identity = transformSession.begin(
            documentID: fixture.document.id,
            pageID: fixture.pageID,
            revision: fixture.document.revision,
            sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration
        )
        transformSession.preview(.init(
            identity: identity,
            operation: prepared.operation,
            geometries: prepared.geometries
        ))
        let baselineBytes = try DocumentSerializer.encode(fixture.document)
        XCTAssertFalse(String(decoding: baselineBytes, as: UTF8.self).contains(identity.sessionID.description))

        let documentSession = DocumentSession(document: fixture.document)
        try documentSession.execute(prepared.documentCommand)
        let package = ProjectPackage(
            projectID: ProjectID(),
            createdAt: ProjectTimestamp("2026-07-26T12:00:00.000Z"),
            document: documentSession.document
        )
        let persisted = try await PersistedHistoryStore().package(
            package,
            with: documentSession.historySnapshot()
        )
        let store = ProjectPackageStore()
        let first = try await store.encode(persisted)
        let second = try await store.encode(persisted)
        XCTAssertEqual(first, second)
        let reopened = try await store.decode(first)
        XCTAssertEqual(reopened.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].preview)
        guard case .restored(let history) = try await PersistedHistoryStore().load(from: reopened) else {
            return XCTFail("Expected transform history")
        }
        let reopenedSession = DocumentSession(document: reopened.document)
        try reopenedSession.installValidatedHistory(history)
        try reopenedSession.undo()
        XCTAssertEqual(reopenedSession.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].original)
    }

    // SF-0403-002, SF-0403-004
    func testSessionStateMachineRejectsStalePreviewAndCancelsExactly() {
        let fixture = makeFixture()
        var session = TransformSession()
        let identity = session.begin(
            documentID: fixture.document.id,
            pageID: fixture.pageID,
            revision: fixture.document.revision,
            sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration
        )
        XCTAssertEqual(session.currentIdentity, identity)
        let stale = TransformOperationIdentity(
            sessionID: TransformSessionID(),
            documentID: identity.documentID,
            pageID: identity.pageID,
            revision: identity.revision,
            sceneID: identity.sceneID,
            rendererGeneration: identity.rendererGeneration
        )
        session.preview(.init(
            identity: stale,
            operation: .move(delta: .init(dx: 1, dy: 1), constraint: .none),
            geometries: []
        ))
        XCTAssertEqual(session.phase, .drafting(identity))
        session.cancel()
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertNil(session.currentIdentity)
        session.deactivate()
        XCTAssertEqual(session.phase, .inactive)
    }

    // SF-0403-001 through SF-0403-008
    func testWorkspaceTransactionKeepsSelectionAndSynchronizesLayoutRendererAndUndo() async throws {
        let state = WorkspaceShellState(
            documentSession: DocumentSession(document: ProjectCreation.blank())
        )
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }
        state.selectTool(.frame)
        state.performDefaultInsertion(.frame, provenance: .automation)
        for _ in 0..<200 where state.selectionState.isEmpty { await Task.yield() }

        let nodeID = try XCTUnwrap(state.selectionState.primaryID)
        for _ in 0..<200 where state.canvasRenderPlan?.authoredObjects
            .contains(where: { $0.id == nodeID }) != true {
            await Task.yield()
        }
        let original = try XCTUnwrap(
            state.documentSession.document.nodeGeometry(nodeID)?.frame
        )
        let historyCount = state.documentSession.historySnapshot().undoEntries.count
        state.selectTool(.select)
        state.setSnappingSuppressed(true)
        let beforeCancelledPreview = try DocumentSerializer.encode(state.documentSession.document)
        XCTAssertTrue(state.beginPointerTransform(at: .init(
            x: original.origin.x + original.size.width / 2,
            y: original.origin.y + original.size.height / 2
        )))
        state.updatePointerTransform(delta: .init(dx: 30, dy: 20), constrainAxis: false)
        guard case .previewing(let preview) = state.transformSession.phase else {
            return XCTFail("Expected an editor-only transform preview")
        }
        XCTAssertEqual(preview.geometries[0].preview.origin, .init(
            x: original.origin.x + 30,
            y: original.origin.y + 20
        ))
        XCTAssertEqual(try DocumentSerializer.encode(state.documentSession.document), beforeCancelledPreview)
        state.performEscape()
        XCTAssertEqual(state.transformSession.phase, .cancelled)
        XCTAssertEqual(try DocumentSerializer.encode(state.documentSession.document), beforeCancelledPreview)
        XCTAssertEqual(state.selectionState.primaryID, nodeID)

        state.performTransform(
            .move(delta: .init(dx: 16, dy: 9), constraint: .none),
            provenance: .automation
        )
        for _ in 0..<200 where state.canvasRenderPlan?.identity.revision
            != state.documentSession.document.revision {
            await Task.yield()
        }

        XCTAssertEqual(state.selectionState.primaryID, nodeID)
        XCTAssertEqual(
            state.documentSession.document.nodeGeometry(nodeID)?.frame.origin,
            .init(x: original.origin.x + 16, y: original.origin.y + 9)
        )
        XCTAssertEqual(
            state.documentSession.historySnapshot().undoEntries.count,
            historyCount + 1
        )
        XCTAssertEqual(
            state.canvasRenderPlan?.authoredObjects.first(where: { $0.id == nodeID })?.frame,
            state.documentSession.document.nodeGeometry(nodeID)?.frame
        )
        XCTAssertEqual(state.transformOverlays.filter {
            $0.kind.hasPrefix("transform-handle")
        }.count, 8)

        state.undo()
        XCTAssertEqual(state.documentSession.document.nodeGeometry(nodeID)?.frame, original)
        XCTAssertEqual(state.selectionState.primaryID, nodeID)
    }

    // SF-0403-002, SF-0403-005, SF-0403-008
    func testRendererHitTestingAndDirtyRegionsFollowCommittedGeometry() throws {
        let fixture = makeFixture()
        let beforeFrame = try XCTUnwrap(fixture.document.nodeGeometry(fixture.nodeID)?.frame)
        let afterFrame = try TransformCommandRegistry.resolve(
            beforeFrame,
            operation: .move(delta: .init(dx: 50, dy: 40), constraint: .none)
        )
        let identity1 = fixture.renderIdentity(revision: 1)
        let identity2 = fixture.renderIdentity(revision: 2)
        let beforeScene = fixture.scene(identity: identity1, frame: beforeFrame)
        let afterScene = fixture.scene(identity: identity2, frame: afterFrame)
        let viewport = try CanvasViewportState(
            viewportSize: .init(width: 800, height: 600),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)),
            pixelRatio: .init(2)
        )
        let core = CanvasRendererCore()
        let plan = try core.prepare(
            scene: afterScene,
            overlays: .init(identity: identity2, overlays: []),
            viewport: viewport,
            previous: beforeScene
        )
        XCTAssertEqual(plan.invalidation, .dirtyRegions)
        XCTAssertEqual(plan.dirtyWorldRegions, [beforeFrame, afterFrame])
        XCTAssertNil(core.hitTest(.init(x: 11, y: 21), in: plan))
        XCTAssertEqual(core.hitTest(.init(x: 61, y: 61), in: plan), fixture.nodeID)
    }

    // Shared resolved-frame contract: authored tile pixels, hit testing,
    // selection, accessibility, and Inspector all begin with one world frame.
    // A centered overlay stroke may extend half a device pixel; its path never
    // applies a separate logical inset.
    func testResolvedGeometryIsSharedAcrossRendererSelectionAccessibilityAndStyles() throws {
        let fixture = makeFixture()
        let core = CanvasRendererCore()
        let kinds: [NodeKind] = [.frame, .text, .section, .stack, .grid]
        for scale in [1.0, 2.0] {
            for zoom in [0.25, 1.0, 8.0] {
                for origin in [WorldPoint(x: 512, y: 512), WorldPoint(x: -80, y: 40)] {
                    // Keep the object visible at every zoom while placing its device
                    // raster near a tile boundary as the transform changes.
                    let frame = WorldRect(origin: .init(x: origin.x + 31, y: origin.y + 29), size: .init(width: 96, height: 48))
                    let identity = fixture.renderIdentity(revision: fixture.document.revision)
                    let objects = kinds.enumerated().map { index, kind in CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil, paintOrder: index, style: kind == .text ? .textPlaceholder : .frameSurface, isVisible: true, accessibilityLabel: kind.rawValue, plainText: kind == .text ? "Text" : nil, fillRGBA: [0.2, 0.4, 0.6, 0.5], opacity: 0.4) }
                    let viewport = try CanvasViewportState(worldOrigin: origin, viewportSize: .init(width: 800, height: 600), contentBounds: .init(origin: .init(x: -2_000, y: -2_000), size: .init(width: 8_000, height: 8_000)), zoom: try .init(zoom), pixelRatio: .init(scale))
                    let scene = CanvasRenderSceneSnapshot(identity: identity, surfaceID: CanvasRenderSurfaceID(), objects: objects)
                    let plan = try core.prepare(scene: scene, overlays: .init(identity: identity, overlays: []), viewport: viewport)
                    for object in plan.authoredObjects {
                        XCTAssertEqual(object.frame, frame)
                        XCTAssertEqual(core.hitTest(.init(x: frame.origin.x + 10, y: frame.origin.y + 10), in: plan), objects.last?.id)
                        let accessible = try XCTUnwrap(plan.accessibilityElements.first(where: { $0.objectID == object.id }))
                        // Accessibility virtualizes only the visible authored
                        // intersection. At 800% this object intentionally
                        // crosses the viewport edge, while canonical/render/
                        // selection geometry remains the complete world rect.
                        let visible = viewport.visibleWorldRect
                        let visibleFrame = WorldRect(
                            origin: .init(
                                x: max(frame.minX, visible.minX),
                                y: max(frame.minY, visible.minY)
                            ),
                            size: .init(
                                width: max(0, min(frame.maxX, visible.maxX) - max(frame.minX, visible.minX)),
                                height: max(0, min(frame.maxY, visible.maxY) - max(frame.minY, visible.minY))
                            )
                        )
                        let expected = try viewport.transform.worldToViewport(visibleFrame.origin)
                        XCTAssertEqual(accessible.frame.origin, expected)
                        XCTAssertEqual(accessible.frame.size.width, visibleFrame.size.width * zoom, accuracy: 1 / scale)
                    }
                    let targets = plan.authoredObjects.enumerated().map { index, object in SelectionTargetSnapshot(id: object.id, pageID: fixture.pageID, parentID: nil, name: "node", kind: kinds[index], frame: object.frame, clipRect: nil, paintOrder: index, isVisible: true, isLocked: false, isAvailable: true) }
                    let selectionScene = SelectionSceneSnapshot(identity: identity, activePageID: fixture.pageID, activeContainerID: nil, targets: targets)
                    var selection = SelectionState(); selection.establishScene(selectionScene); selection.setSelection([objects[0].id], primary: objects[0].id, anchor: objects[0].id, provenance: .pointer)
                    let overlay = try SelectionOverlayPlanner().plan(selection: selection, scene: selectionScene, renderPlan: plan)
                    XCTAssertEqual(overlay.overlays.first?.frame, frame)
                }
            }
        }
    }

    // SF-0403-007, SF-0403-008
    func testTransformCapacityEvidence() throws {
        var maximumResidentBytes: UInt64 = 0
        for count in [100, 10_000] {
            let fixture = makeCapacityFixture(count: count)
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = try TransformCommandRegistry().prepare(
                    fixture.command,
                    in: fixture.document,
                    context: fixture.context
                )
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            maximumResidentBytes = max(maximumResidentBytes, residentBytes())
            print("TRANSFORM_EVIDENCE count=\(count) prepare=\(samples)")
        }
        print("TRANSFORM_EVIDENCE maximumResidentBytes=\(maximumResidentBytes)")
    }

    // SF-0403-008
    func testDiagnosticsAreRedactedAndActionable() async {
        let fixture = makeFixture()
        let command = fixture.command(operation: .move(
            delta: .init(dx: 1, dy: 0),
            constraint: .horizontal
        ))
        let record = TransformDiagnosticFactory.make(
            command: command,
            durationMilliseconds: 0.2,
            resultRevision: fixture.document.revision + 1,
            result: .success,
            failure: nil
        )
        XCTAssertEqual(record.requirementIDs, (1...8).map { "SF-0403-00\($0)" })
        XCTAssertEqual(record.affectedObjectCount, 1)
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertFalse(String(describing: record).contains("/Users/"))
        let diagnostics = TransformDiagnostics()
        await diagnostics.append(record)
        let records = await diagnostics.snapshot()
        XCTAssertEqual(records, [record])
    }

    // SF-0403-001, SF-0403-002, SF-0403-004, SF-0403-005, SF-0403-008
    func testInspectorPropertyClipboardStrictTypedRoundTripAndInvalidNeutrality() throws {
        for field in GeometryInspectorField.allCases {
            let value = InspectorGeometryTransfer(field: field, value: field.requiresPositiveValue ? 120 : -24)
            XCTAssertEqual(try InspectorGeometryTransfer.decode(value.encoded()), value)
        }
        for text in ["{}", "[]", "{\"version\":2,\"field\":\"width\",\"value\":120}",
                     "{\"version\":1,\"field\":\"script\",\"value\":120}",
                     "{\"field\":\"width\",\"value\":true,\"version\":1}",
                     "{\"field\":\"width\",\"value\":0,\"version\":1}",
                     "{\"field\":\"width\",\"value\":120,\"value\":200,\"version\":1}",
                     "{\"field\":\"width\",\"value\":120,\"version\":1,\"command\":\"execute\"}"] {
            XCTAssertThrowsError(try InspectorGeometryTransfer.decode(Data(text.utf8)))
        }
        XCTAssertThrowsError(try InspectorGeometryTransfer.decode(Data(repeating: 32, count: 2049)))
        for invalid in [Double.nan, Double.infinity, -1, LayoutPolicy.maximumDimension + 1] {
            XCTAssertThrowsError(try InspectorGeometryTransfer(field: .width, value: invalid).encoded())
        }
    }

    func testInspectorPropertyPasteAtomicHistoryPersistenceAndResponsiveIsolation() throws {
        var fixture = makeFixture()
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let live = DocumentSession(document: fixture.document)
        let copied = InspectorGeometryTransfer(field: .x, value: 42)
        let prepared = try copied.prepare(identity: fixture.inspectorCommand(field: .x, value: 42).identity,
            orderedNodeIDs: fixture.selectedIDs, document: fixture.document, context: fixture.context, breakpoint: .desktop)
        try live.execute(prepared.documentCommand)
        XCTAssertEqual(live.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 42)
        XCTAssertEqual(live.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 42)
        XCTAssertEqual(live.historySnapshot().undoEntries.count, 1)
        let authored = live.document
        try live.undo(); XCTAssertEqual(live.document.pages, fixture.document.pages)
        try live.redo(); XCTAssertEqual(live.document.pages, authored.pages)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(live.document)), live.document)
        let tablet = try copied.prepare(identity: fixture.inspectorCommand(field: .x, value: 42).identity,
            orderedNodeIDs: fixture.selectedIDs, document: fixture.document, context: fixture.context, breakpoint: .tablet)
        let responsive = DocumentSession(document: fixture.document)
        try responsive.execute(tablet.documentCommand)
        XCTAssertEqual(responsive.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: try XCTUnwrap(responsive.document.pages.first?.nodes.first { $0.id == fixture.nodeID }), breakpoint: .tablet)?.0, 42)
    }

    func testInspectorPropertyPasteRejectsStaleCancelledAndSelectionMismatch() throws {
        var fixture = makeFixture()
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let copied = InspectorGeometryTransfer(field: .x, value: 42)
        let identity = fixture.inspectorCommand(field: .x, value: 42).identity
        XCTAssertThrowsError(try copied.prepare(identity: identity, orderedNodeIDs: fixture.selectedIDs,
            document: fixture.document, context: fixture.context, breakpoint: .desktop,
            cancellation: .init(isCancelled: { true })))
        XCTAssertThrowsError(try copied.prepare(identity: fixture.inspectorCommand(field: .x, value: 42, revision: fixture.document.revision + 1).identity,
            orderedNodeIDs: fixture.selectedIDs, document: fixture.document, context: fixture.context, breakpoint: .desktop))
        XCTAssertThrowsError(try copied.prepare(identity: identity, orderedNodeIDs: [fixture.nodeID],
            document: fixture.document, context: fixture.context, breakpoint: .desktop))
        XCTAssertEqual(GeometryInspectorCommandRegistry().value(for: .x, in: fixture.document, context: fixture.context), .mixed)
        var subset = makeFixture(selectedIDs: [])
        subset.document.pages[0].nodes[2].kind = .form
        subset.document.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == "layout.y" }
        subset.selectedIDs = [subset.nodeID, subset.secondNodeID]
        let partial = try InspectorGeometryTransfer(field: .y, value: 55).prepare(
            identity: subset.inspectorCommand(field: .y, value: 55).identity,
            orderedNodeIDs: subset.selectedIDs, document: subset.document, context: subset.context, breakpoint: .desktop)
        XCTAssertEqual(partial.skippedNodeIDs, [subset.secondNodeID])
        let session = DocumentSession(document: subset.document)
        let untouched = subset.document.pages[0].nodes[2]
        try session.execute(partial.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[2], untouched)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
    }

    func testGeometryInspectorCommitsApplicableSubsetAtomicallyWithUndoAndPersistence() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let registry = GeometryInspectorCommandRegistry()

        XCTAssertEqual(registry.value(for: .x, in: fixture.document, context: fixture.context), .mixed)
        let prepared = try registry.prepare(
            fixture.inspectorCommand(field: .x, value: 42),
            in: fixture.document,
            context: fixture.context
        )
        XCTAssertEqual(prepared.skippedNodeIDs, [])
        guard case let .batch(children) = prepared.documentCommand else {
            return XCTFail("Inspector edit must be one atomic property batch")
        }
        XCTAssertEqual(children.count, 2)

        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 42)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 42)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        _ = try session.undo()
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 10)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 200)
        _ = try session.redo()
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 42)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 42)
    }

    // SF-0403-003, SF-0403-004, SF-0403-006, SF-0403-008
    func testGeometryInspectorRejectsInvalidStaleAndUnavailableValuesWithoutMutation() throws {
        let fixture = makeFixture()
        let registry = GeometryInspectorCommandRegistry()
        let original = try DocumentSerializer.encode(fixture.document)

        for value in [Double.nan, Double.infinity, -1, LayoutPolicy.maximumDimension + 1] {
            XCTAssertThrowsError(try registry.prepare(
                fixture.inspectorCommand(field: .width, value: value),
                in: fixture.document,
                context: fixture.context
            ))
        }
        XCTAssertThrowsError(try registry.prepare(
            fixture.inspectorCommand(field: .x, value: 33, revision: fixture.document.revision + 1),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .staleRevision) }
        XCTAssertThrowsError(try registry.prepare(
            fixture.inspectorCommand(field: .x, value: 33),
            in: fixture.document,
            context: fixture.context(selectedIDs: fixture.selectedIDs, availableIDs: [])
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .unavailableTarget) }
        XCTAssertEqual(try DocumentSerializer.encode(fixture.document), original)

        XCTAssertEqual(GeometryInspectorNumberParser.parse("", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("-", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("12.", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("12abc", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("12,5", locale: Locale(identifier: "fr_FR")), .success(12.5))
    }

    // SF-0403-001, SF-0403-004, SF-0403-008
    func testGeometryInspectorSupportsOnlyDeclaredNodeKindsAndRedactsDiagnostics() throws {
        let registry = GeometryInspectorCommandRegistry()
        for kind in [NodeKind.frame, .text, .section, .stack, .grid, .component] {
            var fixture = makeFixture()
            fixture.document.pages[0].nodes[1].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[1])
            let prepared = try registry.prepare(
                fixture.inspectorCommand(field: .height, value: 88),
                in: fixture.document,
                context: fixture.context
            )
            XCTAssertEqual(prepared.skippedNodeIDs, [], "\(kind) must use fixed geometry when declared applicable")
        }
        XCTAssertTrue(GeometryInspectorCommandRegistry.supportsFixedGeometry(.image))

        var unsupported = makeFixture()
        unsupported.document.pages[0].nodes[1].kind = .component
        // Components now support fixed geometry. An omitted requested property
        // still has no base value to edit and must remain mutation-neutral.
        unsupported.document.pages[0].nodes[1].properties.removeAll { $0.key.rawValue == "layout.x" }
        XCTAssertThrowsError(try registry.prepare(
            unsupported.inspectorCommand(field: .x, value: 20),
            in: unsupported.document,
            context: unsupported.context
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .noApplicableTargets) }

        var subset = makeFixture(selectedIDs: [])
        subset.document.pages[0].nodes[2].kind = .component
        subset.document.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == "layout.y" }
        subset.selectedIDs = [subset.nodeID, subset.secondNodeID]
        let partial = try registry.prepare(
            subset.inspectorCommand(field: .y, value: 55),
            in: subset.document,
            context: subset.context
        )
        XCTAssertEqual(partial.skippedNodeIDs, [subset.secondNodeID])
        guard case let .batch(commands) = partial.documentCommand else {
            return XCTFail("Applicable subset must still be one atomic batch")
        }
        XCTAssertEqual(commands.count, 1)

        let fixture = makeFixture()
        let command = fixture.inspectorCommand(field: .width, value: 222)
        let record = GeometryInspectorDiagnosticFactory.make(
            command: command,
            durationMilliseconds: 0.2,
            resultRevision: fixture.document.revision + 1,
            result: .success,
            failure: nil
        )
        XCTAssertEqual(record.operationType, "geometry-inspector.width")
        XCTAssertEqual(record.requirementIDs, (1...8).map { "SF-0403-00\($0)" })
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertFalse(String(describing: record).contains("/Users/"))
    }

    // SF-0601-001...006, SF-0601-008; SF-0602-001...006, SF-0602-008
    func testResponsiveGeometryOverridesResolveAtomicallyResetAndRoundTrip() throws {
        var fixture = makeFixture()
        let registry = GeometryInspectorCommandRegistry()
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 1_440), .desktop)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 768), .tablet)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 390), .mobile)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 1_023.9), .tablet)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 599.9), .mobile)
        XCTAssertEqual(Set(ResponsiveBreakpoint.allCases.map(\.id)).count, 3)

        var tablet = fixture.inspectorCommand(field: .x, value: 84, breakpoint: .tablet)
        let prepared = try registry.prepare(tablet, in: fixture.document, context: fixture.context)
        XCTAssertEqual(prepared.breakpoint, .tablet)
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        fixture.document = session.document
        let node = fixture.document.pages[0].nodes.first { $0.id == fixture.nodeID }!
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .desktop)?.0, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .tablet)?.0, 84)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .mobile)?.0, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .tablet)?.2, .override(.tablet))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(fixture.document)), fixture.document)

        _ = try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.nodeID }?
            .insertionProperty(ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)))
        _ = try session.redo()
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x,
            node: session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!, breakpoint: .tablet)?.0, 84)

        fixture.document = session.document
        tablet = fixture.inspectorCommand(field: .x, value: 0, breakpoint: .tablet, removesOverride: true)
        let reset = try registry.prepare(tablet, in: fixture.document, context: fixture.context)
        _ = try session.execute(reset.documentCommand)
        let resetNode = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: resetNode, breakpoint: .tablet)?.0, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: resetNode, breakpoint: .tablet)?.2, .baseDesktop)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2)
    }

    func testResponsiveGeometryRejectsStaleCancelledAndPreservesIndependentBreakpoints() throws {
        var fixture = makeFixture()
        let registry = GeometryInspectorCommandRegistry()
        var mobile = fixture.inspectorCommand(field: .width, value: 180, breakpoint: .mobile)
        XCTAssertThrowsError(try registry.prepare(
            fixture.inspectorCommand(field: .width, value: 180, revision: fixture.document.revision + 1,
                breakpoint: .mobile), in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .staleRevision) }
        XCTAssertThrowsError(try registry.prepare(mobile, in: fixture.document, context: fixture.context,
            cancellation: .init { true })) { XCTAssertEqual($0 as? GeometryInspectorError, .cancelled) }
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(try registry.prepare(mobile, in: fixture.document, context: fixture.context).documentCommand)
        fixture.document = session.document
        let tablet = fixture.inspectorCommand(field: .width, value: 300, breakpoint: .tablet)
        _ = try session.execute(try registry.prepare(tablet, in: fixture.document, context: fixture.context).documentCommand)
        let node = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .desktop)?.0, 120)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .tablet)?.0, 300)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .mobile)?.0, 180)

        var malformed = session.document
        malformed.pages[0].nodes[1].properties.append(NodeProperty(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)),
            value: .string("not-a-number"), origin: .authored
        ))
        XCTAssertThrowsError(try malformed.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidResponsiveGeometryState)
        }

        mobile = fixture.inspectorCommand(field: .width, value: 200, breakpoint: .mobile)
        let record = GeometryInspectorDiagnosticFactory.make(
            command: mobile, durationMilliseconds: 0.1,
            resultRevision: nil, result: .stale, failure: .staleRevision
        )
        XCTAssertEqual(record.requirementIDs, GeometryInspectorCommandRegistry.responsiveRequirementIDs.sorted())
        XCTAssertFalse(String(describing: record).contains(fixture.nodeID.description))
    }
    // SF-0508-001...006, SF-0508-008 — canonical RGBA channels preserve
    // legacy defaults and never store a display hexadecimal string.
    func testDesignSolidFillAndOpacityResolveCommitUndoAndPersist() throws {
        var fixture = makeFixture()
        var node = fixture.document.pages[0].nodes[1]
        node.kind = .frame
        node.properties.append(NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted))
        fixture.document.pages[0].nodes[1] = node
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: node).0, .legacySurface)
        XCTAssertEqual(CanonicalSolidColor.parse(hexadecimal: "#20406080")?.hexadecimalRGBA, "#20406080")
        XCTAssertNil(CanonicalSolidColor.parse(hexadecimal: "#zzzzzz"))

        let color = CanonicalSolidColor(red: 0.125, green: 0.25, blue: 0.375, alpha: 0.5)
        let keys = ["style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"]
        let values = [color.red, color.green, color.blue, color.alpha]
        let commands = zip(keys, values).map { key, value in
            DocumentCommand.setProperty(SetPropertyCommand(pageID: fixture.pageID, nodeID: fixture.nodeID, property: NodeProperty(key: .init(rawValue: key), value: .number(value), origin: .authored)))
        } + [.setProperty(SetPropertyCommand(pageID: fixture.pageID, nodeID: fixture.nodeID, property: NodeProperty(key: .init(rawValue: "style.opacity"), value: .number(0.4), origin: .authored)))]
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(.batch(commands))
        let committed = session.document.pages[0].nodes[1]
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: committed).0, color)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: committed)?.0, 0.4)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: session.document.pages[0].nodes[1]).0, .legacySurface)
        try session.redo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: session.document.pages[0].nodes[1]).0, color)
    }

    // SF-0402-001, SF-0508-004 — a selection replacement clears feedback
    // from a prior mixed Design transaction instead of exposing it for the
    // new, potentially inapplicable target.
    func testDesignInspectorSelectionContextAnnouncementIsSelectionScoped() {
        XCTAssertEqual(
            DesignInspectorSelectionPresentation.contextAnnouncement(selectionCount: 2),
            "Design Inspector updated for current selection."
        )
        XCTAssertEqual(
            DesignInspectorSelectionPresentation.contextAnnouncement(selectionCount: 1),
            "Design Inspector updated for current selection."
        )
        XCTAssertEqual(
            DesignInspectorSelectionPresentation.contextAnnouncement(selectionCount: 0),
            "Design Inspector requires a selection."
        )
    }

    // SF-0508-001...008 — registry is the single pre-mutation gate.
    func testDesignInspectorRegistryAdversarialIdentitySubsetAndHistoryMatrix() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(
            NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted)
        )
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let registry = DesignInspectorCommandRegistry()
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: " #20406080 "))
        XCTAssertEqual(color.hexadecimalRGBA, "#20406080")
        XCTAssertEqual(CanonicalSolidColor.parse(hexadecimal: "20406080"), color)
        XCTAssertEqual(CanonicalSolidColor.parse(hexadecimal: "#204060")?.alpha, 1)
        for source in ["#20406", "#204060800", "#20GG60", "#"] { XCTAssertNil(CanonicalSolidColor.parse(hexadecimal: source)) }
        func command(_ edit: DesignInspectorEdit, identity: DesignInspectorOperationIdentity? = nil, ids: [NodeID]? = nil, cancelled: Bool = false) -> DesignInspectorCommand {
            .init(identity: identity ?? .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: ids ?? fixture.selectedIDs, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let prepared = try registry.prepare(command(.fill(color)), in: fixture.document, context: fixture.context)
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID]); XCTAssertEqual(prepared.skippedNodeIDs, [fixture.secondNodeID])
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        let opacity = try registry.prepare(command(.opacity(0.4), identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), ids: [fixture.nodeID]), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(opacity.documentCommand)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2)
        try session.undo(); XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty("style.opacity")); try session.redo()
        for value in [0.0, 1.0, 0.4] { XCTAssertNoThrow(try registry.prepare(command(.opacity(value)), in: fixture.document, context: fixture.context)) }
        for value in [Double.nan, Double.infinity, -0.01, 1.01] { XCTAssertThrowsError(try registry.prepare(command(.opacity(value)), in: fixture.document, context: fixture.context)) }
        let stale = DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration)
        XCTAssertThrowsError(try registry.prepare(command(.fill(color), identity: stale), in: fixture.document, context: fixture.context))
        XCTAssertThrowsError(try registry.prepare(command(.fill(color), ids: [fixture.nodeID, fixture.nodeID]), in: fixture.document, context: fixture.context))
        XCTAssertThrowsError(try registry.prepare(command(.fill(color), cancelled: true), in: fixture.document, context: fixture.context))
    }

    // SF-0508-001...006, SF-0508-008 — each view entry path uses exactly the
    // same strict normalizer and one registry-owned transaction boundary.
    func testDesignInspectorRegistryNormalizesValuesAndKeepsNoOpsNeutral() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .frame
        let registry = DesignInspectorCommandRegistry()
        let lowercase = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: " #20406080 "))
        let picker = CanonicalSolidColor(red: 32 / 255, green: 64 / 255, blue: 96 / 255, alpha: 128 / 255)
        XCTAssertEqual(lowercase, picker)
        XCTAssertEqual(lowercase.hexadecimalRGBA, "#20406080")
        for invalid in ["", "#2040608", "#204060800", "#20406G", "#20406080 \\n"] {
            XCTAssertNil(CanonicalSolidColor.parse(hexadecimal: invalid))
        }
        let command = DesignInspectorCommand(
            identity: .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .fill(lowercase), provenance: .hexadecimal, cancelled: false
        )
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(registry.prepare(command, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])).documentCommand)
        let authored = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: authored).0, picker)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: authored).1, .authored)
        let authoredIDs = authored.properties
            .filter { $0.key.rawValue.hasPrefix("\(CanonicalFillLayerCodec.namespaceRoot).") }
            .map(\.id)
        XCTAssertFalse(authoredIDs.isEmpty)
        for legacyKey in ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"] {
            XCTAssertNil(authored.insertionProperty(legacyKey), "Compatibility fill commands must not write legacy key \(legacyKey).")
        }

        let noOp = DesignInspectorCommand(
            identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .fill(picker), provenance: .picker, cancelled: false
        )
        XCTAssertThrowsError(try registry.prepare(noOp, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? DesignInspectorError, .noChanges)
        }
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let unchanged = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID }))
        XCTAssertEqual(
            authoredIDs,
            unchanged.properties
                .filter { $0.key.rawValue.hasPrefix("\(CanonicalFillLayerCodec.namespaceRoot).") }
                .map(\.id)
        )

        for value in [0.0, 0.4, 1.0] {
            let opacity = DesignInspectorCommand(
                identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: .opacity(value), provenance: .keyboard, cancelled: false
            )
            _ = try session.execute(registry.prepare(opacity, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])).documentCommand)
        }
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID })))?.0, 1)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 4, "Fill and each completed opacity edit retain separate exact history entries.")
        try session.undo(); try session.undo(); try session.undo()
        XCTAssertNil(try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID })).insertionProperty("style.opacity"))
        try session.redo(); try session.redo(); try session.redo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID })))?.0, 1)
        _ = try session.execute(registry.prepare(
            .init(identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID], edit: .opacity(0.25), provenance: .automation, cancelled: false),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        ).documentCommand)
        XCTAssertTrue(session.historySnapshot().redoEntries.isEmpty, "A later opacity commit invalidates only its redo branch.")
    }

    // SF-0508-002...006 — stale and invalid inputs must be entirely neutral;
    // mixed valid selection edits name unsupported skips instead of coercing.
    func testDesignInspectorRegistryRejectsAllBoundariesAndReportsMixedApplicableSubset() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(
            NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted)
        )
        let registry = DesignInspectorCommandRegistry()
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#10203040"))
        func command(
            identity: DesignInspectorOperationIdentity? = nil,
            ids: [NodeID] = [fixture.nodeID, fixture.secondNodeID],
            edit: DesignInspectorEdit = .fill(color),
            cancelled: Bool = false
        ) -> DesignInspectorCommand {
            .init(identity: identity ?? .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let before = fixture.document
        let mixed = try registry.prepare(command(), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertEqual(mixed.skippedReasons[fixture.secondNodeID], "This object kind does not support background fill layers.")
        XCTAssertEqual(DesignInspectorCommandRegistry.fillValue(nodes: [fixture.document.pages[0].nodes[1], fixture.document.pages[0].nodes[2]]), .mixed)

        let staleIdentities = [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: PageID(), revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision + 1, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration + 1),
        ]
        for identity in staleIdentities {
            XCTAssertThrowsError(try registry.prepare(command(identity: identity), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .stale) }
        }
        let invalidOpacityEdits: [DesignInspectorEdit] = [.opacity(.nan), .opacity(.infinity), .opacity(-0.01), .opacity(1.01)]
        for edit in invalidOpacityEdits {
            XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID], edit: edit), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        }
        XCTAssertThrowsError(try registry.prepare(command(ids: [], edit: .fill(color)), in: fixture.document, context: fixture.context(selectedIDs: [])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID, fixture.nodeID]), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [NodeID()], edit: .fill(color)), in: fixture.document, context: fixture.context(selectedIDs: [NodeID()])))
        XCTAssertThrowsError(try registry.prepare(command(cancelled: true), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])))

        var locked = fixture.document
        locked.pages[0].nodes[1].properties.append(booleanProperty("locked", true))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: locked, context: fixture.context(selectedIDs: [fixture.nodeID])))
        var hidden = fixture.document
        hidden.pages[0].nodes[1].properties.append(booleanProperty("hidden", true))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: hidden, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID], availableIDs: [])))
        fixture.document.pages[0].nodes[1].kind = .image
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .noApplicableTargets) }
        XCTAssertEqual(before.revision, 0)
    }
    func testCanonicalFillLayerFoundationValidatesStableOrderAndGradientDefaults() {
        let start = CanonicalGradientStop(id: GradientStopID(UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!), position: 0, color: .legacySurface)
        let end = CanonicalGradientStop(id: GradientStopID(UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!), position: 1, color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))
        let layerID = FillLayerID(UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!)
        let gradient = CanonicalFillLayer.linearGradient(id: layerID, angleDegrees: -180, stops: [start, end])
        XCTAssertTrue(gradient.isValid)
        XCTAssertEqual(gradient.normalizedAngleDegrees, 180)
        XCTAssertTrue(CanonicalFillLayer.solid(color: .legacySurface).isValid)
        XCTAssertTrue(CanonicalFillLayer.linearGradient(stops: [end, start]).isValid, "Stable stop order is distinct from interpolation position.")
        XCTAssertFalse(CanonicalFillLayer.linearGradient(stops: [start, start]).isValid)
        let replacement = CanonicalSolidColor(red: 0.1, green: 0.3, blue: 0.5, alpha: 0.7)
        let migrated = try? [CanonicalFillLayer.solid(color: .legacySurface)].applying(.replaceSolid(replacement))
        XCTAssertEqual(migrated?.count, 1)
        XCTAssertEqual(migrated?.first?.solidColor, replacement)
        XCTAssertEqual(try? migrated?.applying(.replaceSolid(nil)), [])
    }

    // SF-0301-004...006, SF-0303-005, SF-0508-001...008 — namespace
    // absence is legacy-compatible and distinct from an explicitly authored
    // empty layer order. Complete generated stacks decode exactly.
    func testCanonicalFillLayerStrictDecoderDistinguishesAbsentEmptyLegacyAndValidStacks() throws {
        var node = makeGeometryNode(id: NodeID(), parent: NodeID(), x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: node), .absent)

        node.properties.append(NodeProperty(
            key: .init(rawValue: CanonicalFillLayerCodec.orderKey),
            value: .string("")
        ))
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: node), .layers([]))

        var legacy = makeGeometryNode(id: NodeID(), parent: NodeID(), x: 0, y: 0, width: 100, height: 100)
        legacy.properties.append(NodeProperty(
            key: .init(rawValue: "style.fill"),
            value: .string("surface"),
            origin: .defaulted
        ))
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: legacy), .absent)
        XCTAssertEqual(CanonicalFillLayerCodec.legacySolidLayer(for: legacy)?.solidColor, .legacySurface)

        let layer = CanonicalFillLayer.solid(
            id: FillLayerID(UUID(uuidString: "A0600000-0000-4000-8000-000000000001")!),
            color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        )
        node.properties.removeAll { $0.key.rawValue.hasPrefix("\(CanonicalFillLayerCodec.namespaceRoot).") }
        node.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: node), .layers([layer]))

        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        XCTAssertNoThrow(try fixture.document.validate())
    }

    // SF-0301-004...006, SF-0303-005, SF-0508-001...008 — every owned
    // namespace field must be reachable, complete, typed, canonical, and
    // valid. Corruption may not collapse into the same state as authored
    // "no fill" or be adopted by the canonical document.
    func testCanonicalFillLayerStrictDecoderRejectsMalformedNamespaceMatrix() throws {
        let fixture = makeFixture()
        let layerID = FillLayerID(UUID(uuidString: "A0610000-0000-4000-8000-000000000001")!)
        let startID = GradientStopID(UUID(uuidString: "A0610000-0000-4000-8000-000000000002")!)
        let endID = GradientStopID(UUID(uuidString: "A0610000-0000-4000-8000-000000000003")!)
        let gradient = CanonicalFillLayer.linearGradient(
            id: layerID,
            angleDegrees: 45,
            stops: [
                .init(id: startID, position: 0, color: .legacySurface),
                .init(id: endID, position: 1, color: .init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)),
            ]
        )
        var valid = fixture.document.pages[0].nodes[1]
        valid.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [gradient]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: valid), .layers([gradient]))

        let layerPrefix = "\(CanonicalFillLayerCodec.namespaceRoot).\(layerID.description)"
        let startPrefix = "\(layerPrefix).stop.\(startID.description)"
        func replacing(_ key: String, with value: PropertyValue?, in input: DocumentNode) -> DocumentNode {
            var node = input
            node.properties.removeAll { $0.key.rawValue == key }
            if let value {
                node.properties.append(NodeProperty(key: .init(rawValue: key), value: value))
            }
            return node
        }
        func assertMalformed(
            _ label: String,
            _ candidate: DocumentNode,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertThrowsError(
                try CanonicalFillLayerCodec.decodeLayers(for: candidate),
                label,
                file: file,
                line: line
            )
            var document = fixture.document
            document.pages[0].nodes[1] = candidate
            XCTAssertThrowsError(try document.validate(), label, file: file, line: line) { error in
                XCTAssertEqual(error as? ModelValidationError, .invalidFillLayerState, file: file, line: line)
            }
        }

        assertMalformed("namespace properties without order", replacing(CanonicalFillLayerCodec.orderKey, with: nil, in: valid))
        assertMalformed("wrong order type", replacing(CanonicalFillLayerCodec.orderKey, with: .boolean(true), in: valid))
        assertMalformed("trailing empty layer token", replacing(CanonicalFillLayerCodec.orderKey, with: .string("\(layerID.description),"), in: valid))
        assertMalformed("duplicate layer identity", replacing(CanonicalFillLayerCodec.orderKey, with: .string("\(layerID.description),\(layerID.description)"), in: valid))
        assertMalformed("unknown layer kind", replacing("\(layerPrefix).kind", with: .string("radialGradient"), in: valid))
        assertMalformed("missing enabled field", replacing("\(layerPrefix).enabled", with: nil, in: valid))
        assertMalformed("noncanonical angle", replacing("\(layerPrefix).angle", with: .number(360), in: valid))
        assertMalformed("trailing empty stop token", replacing("\(layerPrefix).stops", with: .string("\(startID.description),\(endID.description),"), in: valid))
        assertMalformed("duplicate stop identity", replacing("\(layerPrefix).stops", with: .string("\(startID.description),\(startID.description)"), in: valid))
        assertMalformed("insufficient gradient stops", replacing("\(layerPrefix).stops", with: .string(startID.description), in: valid))
        assertMalformed("missing stop field", replacing("\(startPrefix).position", with: nil, in: valid))
        assertMalformed("invalid stop position", replacing("\(startPrefix).position", with: .number(1.1), in: valid))
        assertMalformed("invalid stop color", replacing("\(startPrefix).alpha", with: .number(-0.1), in: valid))
        assertMalformed("orphaned namespace property", replacing("\(layerPrefix).unused", with: .number(1), in: valid))

        var unsupported = valid
        unsupported.kind = .text
        assertMalformed("unsupported node kind", unsupported)

        let solid = CanonicalFillLayer.solid(id: layerID, color: .legacySurface)
        var invalidSolid = fixture.document.pages[0].nodes[1]
        invalidSolid.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [solid]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        invalidSolid = replacing("\(layerPrefix).red", with: .number(1.1), in: invalidSolid)
        assertMalformed("invalid solid color", invalidSolid)
    }

    // SF-0508-002, SF-0508-004, SF-0508-006 — ordered rows are shared across
    // a multiple selection only when every applicable object owns the exact
    // same stable layer/stop identities and values. Differing stacks remain a
    // truthful non-editable mixed state; unsupported objects are counted and
    // left unchanged by the same registry command.
    func testFillLayerMultipleSelectionDistinguishesSharedMixedAndSkippedStacks() throws {
        var fixture = makeFixture(selectedIDs: [])
        let selected = [fixture.nodeID, fixture.secondNodeID]
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .frame
        let layerID = FillLayerID(UUID(uuidString: "A0500000-0000-4000-8000-000000000001")!)
        let sharedLayers = [CanonicalFillLayer.solid(
            id: layerID,
            color: .init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        )]
        func install(_ layers: [CanonicalFillLayer], on node: inout DocumentNode) {
            node.properties.removeAll {
                $0.key.rawValue.hasPrefix("style.fill.layers.v1.")
                    || ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"].contains($0.key.rawValue)
            }
            node.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: layers)
                .sorted(by: { $0.key < $1.key })
                .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored) })
        }
        install(sharedLayers, on: &fixture.document.pages[0].nodes[1])
        install(sharedLayers, on: &fixture.document.pages[0].nodes[2])
        let frame = fixture.document.pages[0].nodes[1]
        let secondFrame = fixture.document.pages[0].nodes[2]
        XCTAssertEqual(
            DesignInspectorCommandRegistry.fillLayerSelectionValue(nodes: [frame, secondFrame]),
            .shared(layers: sharedLayers, applicableCount: 2, skippedCount: 0)
        )

        var text = secondFrame
        text.kind = .text
        XCTAssertEqual(
            DesignInspectorCommandRegistry.fillLayerSelectionValue(nodes: [frame, text]),
            .shared(layers: sharedLayers, applicableCount: 1, skippedCount: 1)
        )
        var different = secondFrame
        install([.solid(id: layerID, color: .legacySurface)], on: &different)
        XCTAssertEqual(
            DesignInspectorCommandRegistry.fillLayerSelectionValue(nodes: [frame, different]),
            .mixed(applicableCount: 2, skippedCount: 0)
        )

        let registry = DesignInspectorCommandRegistry()
        let prepared = try registry.prepare(
            .init(
                identity: .init(
                    documentID: fixture.document.id,
                    pageID: fixture.pageID,
                    revision: fixture.document.revision,
                    sceneID: fixture.sceneID,
                    rendererGeneration: fixture.rendererGeneration
                ),
                orderedNodeIDs: selected,
                edit: .setEnabled(layerID, false),
                provenance: .accessibility,
                cancelled: false
            ),
            in: fixture.document,
            context: fixture.context(selectedIDs: selected)
        )
        XCTAssertEqual(prepared.applicableNodeIDs, selected)
        XCTAssertTrue(prepared.skippedNodeIDs.isEmpty)
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        let edited = session.document.pages[0].nodes.filter { selected.contains($0.id) }
        XCTAssertEqual(edited.count, 2)
        XCTAssertTrue(edited.allSatisfy {
            DesignInspectorCommandRegistry.resolvedLayers(for: $0).first?.isEnabled == false
        })
    }

    // SF-0508-001...008 — each layer reducer result is compiled by the
    // central registry into one identity-gated, invertible property batch.
    func testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(
            .init(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted)
        )
        let registry = DesignInspectorCommandRegistry()
        let solidID = FillLayerID(UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!)
        let gradientID = FillLayerID(UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!)
        let startID = GradientStopID(UUID(uuidString: "A1000000-0000-4000-8000-000000000003")!)
        let endID = GradientStopID(UUID(uuidString: "A1000000-0000-4000-8000-000000000004")!)
        let middleID = GradientStopID(UUID(uuidString: "A1000000-0000-4000-8000-000000000005")!)
        let red = CanonicalSolidColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = CanonicalSolidColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let stops = [
            CanonicalGradientStop(id: startID, position: 0, color: red),
            CanonicalGradientStop(id: endID, position: 1, color: blue),
        ]
        func command(
            _ document: CanonicalDocument,
            ids: [NodeID],
            _ edit: DesignFillLayerEdit,
            cancelled: Bool = false,
            identity: DesignInspectorOperationIdentity? = nil
        ) -> DesignFillLayerCommand {
            .init(
                identity: identity ?? .init(documentID: document.id, pageID: fixture.pageID, revision: document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids,
                edit: edit,
                provenance: .automation,
                cancelled: cancelled
            )
        }
        func context(_ ids: [NodeID]) -> TransformValidationContext {
            fixture.context(selectedIDs: ids)
        }

        let addSolid = try registry.prepare(
            command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], .addSolid(id: solidID, color: red)),
            in: fixture.document,
            context: context([fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(addSolid.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(addSolid.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertEqual(addSolid.skippedReasons[fixture.secondNodeID], "This object kind does not support background fill layers.")
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(addSolid.documentCommand)
        func currentFrame(in document: CanonicalDocument) throws -> DocumentNode {
            try XCTUnwrap(document.pages[0].nodes.first(where: { $0.id == fixture.nodeID }))
        }
        var frame = try currentFrame(in: session.document)
        let legacyLayerID = try XCTUnwrap(DesignInspectorCommandRegistry.resolvedLayers(for: frame).first?.id)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: frame), [
            .solid(id: legacyLayerID, color: .legacySurface),
            .solid(id: solidID, color: red),
        ])
        XCTAssertNil(frame.insertionProperty("style.fill"), "Legacy fallback is consumed and removed atomically on the first v1 write.")
        XCTAssertNotNil(frame.insertionProperty(CanonicalFillLayerCodec.orderKey))
        let solidPropertyIDs = frame.properties.filter { $0.key.rawValue.contains(solidID.description) }.map { $0.id }

        let replacement = CanonicalSolidColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let replaceSolid = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setSolidColor(solidID, replacement)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(replaceSolid.documentCommand)

        let addGradient = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .addLinearGradient(id: gradientID, angleDegrees: 90, stops: stops)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(addGradient.documentCommand)
        let reorder = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .reorder(gradientID, to: 0)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(reorder.documentCommand)
        let addStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .addStop(gradientID, .init(id: middleID, position: 0.5, color: .legacySurface), at: 1)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(addStop.documentCommand)
        let changeAngle = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setGradientAngle(gradientID, 495)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(changeAngle.documentCommand)
        let editStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setStop(gradientID, middleID, position: 0.75, color: replacement)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(editStop.documentCommand)
        let reorderStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .reorderStop(gradientID, middleID, to: 2)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(reorderStop.documentCommand)
        let removeStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .removeStop(gradientID, middleID)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(removeStop.documentCommand)
        let disable = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setEnabled(solidID, false)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(disable.documentCommand)

        frame = try currentFrame(in: session.document)
        let layers = DesignInspectorCommandRegistry.resolvedLayers(for: frame)
        XCTAssertEqual(layers.map { $0.id }, [gradientID, legacyLayerID, solidID])
        XCTAssertEqual(layers[0].normalizedAngleDegrees, 135)
        XCTAssertEqual(layers[0].stops.map { $0.id }, [startID, endID])
        XCTAssertEqual(layers[2].solidColor, replacement)
        XCTAssertFalse(layers[2].isEnabled)
        XCTAssertEqual(frame.properties.filter { $0.key.rawValue.hasPrefix("style.fill.layers.v1.") && $0.key.rawValue.contains(solidID.description) }.map { $0.id }.filter { solidPropertyIDs.contains($0) }.count, solidPropertyIDs.count)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let removeGradient = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .remove(gradientID)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(removeGradient.documentCommand)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: try currentFrame(in: session.document)).map { $0.id }, [legacyLayerID, solidID])
        let snapshot = session.document
        try session.undo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: try currentFrame(in: session.document)).first?.id, gradientID)
        try session.redo()
        XCTAssertEqual(try currentFrame(in: session.document).properties, try currentFrame(in: snapshot).properties, "Redo restores the complete ordered v1 layer representation exactly.")
        while session.historySnapshot().undoEntries.count > 0 { try session.undo() }
        frame = try currentFrame(in: session.document)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: frame).0, .legacySurface)
        XCTAssertNil(frame.insertionProperty(CanonicalFillLayerCodec.orderKey))
    }

    // SF-0508-002...006 — invalid/stale/cancelled layer inputs remain fully
    // neutral and diagnostics disclose category only, never stable IDs.
    func testDesignFillLayerRegistryRejectsInvalidStaleCancelAndAllInapplicableEdits() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        let registry = DesignInspectorCommandRegistry()
        let layerID = FillLayerID(UUID(uuidString: "A2000000-0000-4000-8000-000000000001")!)
        let invalidColor = CanonicalSolidColor(red: .nan, green: 0, blue: 0, alpha: 1)
        func command(
            ids: [NodeID],
            edit: DesignFillLayerEdit,
            cancelled: Bool = false,
            identity: DesignInspectorOperationIdentity? = nil
        ) -> DesignFillLayerCommand {
            .init(
                identity: identity ?? .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids, edit: edit, provenance: .accessibility, cancelled: cancelled
            )
        }
        let before = fixture.document
        let base = command(ids: [fixture.nodeID], edit: .addSolid(id: layerID, color: .legacySurface))
        for identity in [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: PageID(), revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision + 1, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration + 1),
        ] {
            XCTAssertThrowsError(try registry.prepare(.init(identity: identity, orderedNodeIDs: base.orderedNodeIDs, edit: base.edit, provenance: base.provenance, cancelled: false), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .stale) }
        }
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID], edit: .addSolid(id: layerID, color: invalidColor)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) { error in
            XCTAssertFalse(error.localizedDescription.contains(layerID.description))
        }
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID], edit: .addSolid(id: layerID, color: .legacySurface), cancelled: true), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.secondNodeID], edit: .addSolid(id: layerID, color: .legacySurface)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.secondNodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .noApplicableTargets) }
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID, fixture.nodeID], edit: .addSolid(id: layerID, color: .legacySurface)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.nodeID])))
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0508-004/005 — Inspector numeric drafts must fail visibly instead of
    // silently disappearing on Return or focus loss, while valid values are
    // normalized before the transactional command is prepared.
    func testGradientStopInsertionPreservesRampAndIdentityWithoutRepeatedMidpoints() throws {
        let first = CanonicalGradientStop(id: GradientStopID(), position: 0, color: .init(red: 1, green: 0, blue: 0, alpha: 0.2))
        let last = CanonicalGradientStop(id: GradientStopID(), position: 1, color: .init(red: 0, green: 0, blue: 1, alpha: 0.8))
        let layer = CanonicalFillLayer.linearGradient(angleDegrees: 45, stops: [last, first])
        let inserted = try XCTUnwrap(GradientAuthoringInsertion.stop(in: layer))
        XCTAssertEqual(inserted.position, 0.5)
        XCTAssertEqual(inserted.color, .init(red: 0.2, green: 0, blue: 0.8, alpha: 0.5))
        let next = CanonicalFillLayer.linearGradient(id: layer.id, angleDegrees: 45, stops: [last, first, inserted])
        XCTAssertEqual(next.stops.map(\.id), [last.id, first.id, inserted.id])
        let second = try XCTUnwrap(GradientAuthoringInsertion.stop(in: next))
        XCTAssertTrue(second.position == 0.25 || second.position == 0.75)
        XCTAssertNotEqual(second.id, inserted.id)
        func snapshot(_ value: CanonicalFillLayer) -> CanvasAuthoredFillLayer {
            .init(id: value.id.rawValue, kind: .linearGradient, isEnabled: true, rgba: nil, angleDegrees: 0,
                stops: value.stops.map { .init(id: $0.id.rawValue, position: $0.position,
                    rgba: [$0.color.red, $0.color.green, $0.color.blue, $0.color.alpha]) })
        }
        for x in stride(from: 0.0, through: 1.0, by: 0.01) {
            let a = try XCTUnwrap(CanvasAuthoredFillCompositor.color(for: snapshot(layer), atNormalizedPoint: (x, 0.5)))
            let b = try XCTUnwrap(CanvasAuthoredFillCompositor.color(for: snapshot(next), atNormalizedPoint: (x, 0.5)))
            for index in 0..<4 { XCTAssertEqual(a[index], b[index], accuracy: 0.000001) }
        }
    }

    func testFillLayerNumericDraftValidationIsExplicitAndCanonical() throws {
        XCTAssertEqual(try FillLayerNumericDraftValidator.angle(" 495 ").get(), 135)
        XCTAssertEqual(try FillLayerNumericDraftValidator.angle("-180").get(), 180)
        XCTAssertEqual(FillLayerNumericDraftValidator.angle(" "), .failure(.empty))
        XCTAssertEqual(FillLayerNumericDraftValidator.angle("nan"), .failure(.notFinite))

        XCTAssertEqual(try FillLayerNumericDraftValidator.percentage("25").get(), 0.25)
        XCTAssertEqual(try FillLayerNumericDraftValidator.percentage("100").get(), 1)
        XCTAssertEqual(FillLayerNumericDraftValidator.percentage("-1"), .failure(.outsidePercentageRange))
        XCTAssertEqual(FillLayerNumericDraftValidator.percentage("101"), .failure(.outsidePercentageRange))
        XCTAssertEqual(FillLayerNumericDraftValidator.percentage("invalid"), .failure(.notFinite))
    }

    // SF-0506-001...006/008 — the bounded box appearance uses one typed,
    // identity-gated property transaction and exact CommandRegistry inverse.
    func testDesignBoxStyleRegistryCommitsValidatesMixesPersistsAndUndoRedo() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        fixture.document.pages[0].nodes[2].kind = .text
        let registry = DesignBoxStyleCommandRegistry()
        let border = CanonicalBorder(
            color: .init(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
            width: 3, style: .dashed
        )
        let shadow = CanonicalShadow(
            color: .init(red: 0, green: 0, blue: 0, alpha: 0.3),
            offsetX: 2, offsetY: 8, blur: 16, spread: 1
        )
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: DesignBoxStyleEdit, cancelled: Bool = false) -> DesignBoxStyleCommand {
            .init(
                identity: .init(
                    documentID: document.id, pageID: fixture.pageID,
                    revision: document.revision, sceneID: fixture.sceneID,
                    rendererGeneration: fixture.rendererGeneration
                ), orderedNodeIDs: ids, edit: edit, provenance: .automation,
                cancelled: cancelled
            )
        }
        let mixed = try registry.prepare(
            command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], edit: .border(border)),
            in: fixture.document,
            context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertFalse(mixed.skippedReasons.values.joined().contains(fixture.nodeID.description))

        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(mixed.documentCommand)
        let radius = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .cornerRadius(14)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(radius.documentCommand)
        let shadowEdit = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadow(shadow)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(shadowEdit.documentCommand)
        let disabledShadow = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadowEnabled(false)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(disabledShadow.documentCommand)

        func currentStyle() throws -> CanonicalBoxStyle {
            let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
            return try XCTUnwrap(DesignBoxStyleCommandRegistry.resolvedStyle(for: node))
        }
        XCTAssertEqual(try currentStyle(), .init(border: border, cornerRadius: 14, shadow: shadow, shadowEnabled: false))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let propertyIDs = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(DesignBoxStyleCommandRegistry.namespace) }.map(\.id)
        try session.undo()
        XCTAssertNil(try currentStyle().shadowEnabled)
        try session.redo()
        XCTAssertEqual(try currentStyle().shadowEnabled, false)
        let reopenedIDs = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(DesignBoxStyleCommandRegistry.namespace) }.map(\.id)
        XCTAssertEqual(propertyIDs, reopenedIDs)

        let beforeZero = session.document
        let zero = try registry.prepare(command(session.document, ids: [fixture.nodeID],
            edit: .border(.init(color: border.color, width: 0, style: .solid))),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(zero.documentCommand)
        XCTAssertEqual(try currentStyle().border?.width, 0)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        XCTAssertEqual(session.document.pages, beforeZero.pages)
        try session.redo()
        XCTAssertEqual(try currentStyle().border?.width, 0)

        let invalid = CanonicalShadow(color: shadow.color, offsetX: 0, offsetY: 0, blur: -.infinity, spread: 0)
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadow(invalid)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        let invalidBorder = CanonicalBorder(color: border.color, width: -1, style: .solid)
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .border(invalidBorder)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .cornerRadius(8), cancelled: true),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .cancelled) }
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadowEnabled(true), cancelled: true),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .cancelled) }
        let stale = DesignBoxStyleCommand(
            identity: .init(documentID: DocumentID(), pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .border(nil), provenance: .automation, cancelled: false
        )
        XCTAssertThrowsError(try registry.prepare(stale, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? DesignBoxStyleError, .stale)
        }
    }

    // SF-0506-001...005/008 — Frame/Section content padding and clipping
    // share the existing box-style transaction; unsupported structural kinds
    // cannot inherit a primary Frame's content-box value.
    func testDesignBoxStyleContentPaddingAndClipAreTypedReversibleAndScoped() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        let frameIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.nodeID })
        fixture.document.pages[0].nodes[frameIndex].kind = .frame
        let registry = DesignBoxStyleCommandRegistry()
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: DesignBoxStyleEdit, cancelled: Bool = false) -> DesignBoxStyleCommand {
            .init(identity: .init(documentID: document.id, pageID: fixture.pageID, revision: document.revision,
                                  sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                  orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let session = DocumentSession(document: fixture.document)
        let padding = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .padding(32)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        XCTAssertEqual(padding.applicableNodeIDs, [fixture.nodeID])
        XCTAssertTrue(padding.skippedNodeIDs.isEmpty)
        XCTAssertFalse(DesignBoxStyleCommandRegistry.supports(.padding(12), kind: .stack))
        XCTAssertFalse(DesignBoxStyleCommandRegistry.supports(.clipsContent(true), kind: .grid))
        _ = try session.execute(padding.documentCommand)
        let clipped = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .clipsContent(true)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(clipped.documentCommand)
        let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding, 32)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.clipsContent, true)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        let afterUndo = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertNil(DesignBoxStyleCommandRegistry.resolvedStyle(for: afterUndo)?.clipsContent)
        try session.redo()
        let afterRedo = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: afterRedo)?.clipsContent, true)
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .padding(.infinity)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .clipsContent(false), cancelled: true),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .cancelled) }
        var malformed = session.document
        let propertyIndex = try XCTUnwrap(malformed.pages[0].nodes[frameIndex].properties.firstIndex {
            $0.key.rawValue == "style.box.v1.padding.uniform"
        })
        malformed.pages[0].nodes[frameIndex].properties[propertyIndex].value = .string("not-a-number")
        XCTAssertEqual(DesignBoxStyleCommandRegistry.selectionValue(nodes: [malformed.pages[0].nodes[frameIndex]]),
                       .unavailable("A selected object has invalid persisted content-box data and cannot be edited safely."))
        XCTAssertThrowsError(try registry.prepare(
            command(malformed, ids: [fixture.nodeID], edit: .padding(12)), in: malformed,
            context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
    }

    // SF-0507-002/003/005: installed family+weight is one authored
    // choice, preserving semantics, per-node metrics, fluid intent and exact IDs.
    func testFontFamilyWeightChoiceIsAtomicForMixedTextAndPreservesExactHistory() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[2].kind = .button
        let family = NodeProperty(key: .init(rawValue: CanonicalTypography.namespace + "family"),
            value: .string("Missing prior family"), origin: .defaulted)
        let weight = NodeProperty(key: .init(rawValue: CanonicalTypography.namespace + "weight"),
            value: .string("bold"), origin: .defaulted)
        let fluid = NodeProperty(key: .init(rawValue: CanonicalFluidValueCodec.key(.fontSize)),
            value: .string(try CanonicalFluidValueCodec.encode(.init(minimum: 10, preferred: 14, maximum: 18), target: .fontSize)))
        fixture.document.pages[0].nodes[1].properties += [family, weight, fluid,
            .init(key: .init(rawValue: CanonicalSemanticElement.key), value: .string("h2")),
            .init(key: .init(rawValue: "content.text"), value: .string("Heading\nSecond line"))]
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID, fixture.rootID]
        let session = DocumentSession(document: fixture.document), registry = TypographyCommandRegistry()
        func request(_ choice: CanonicalFontWeight) -> TypographyCommand {
            .init(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: fixture.selectedIDs, edit: .fontFace(family: "System", weight: choice), provenance: .picker, cancelled: false)
        }
        let original = session.document.pages
        let edit = try registry.prepare(request(.medium), in: session.document, context: fixture.context)
        XCTAssertEqual(edit.applicableNodeIDs, [fixture.nodeID, fixture.secondNodeID])
        XCTAssertEqual(edit.skippedNodeIDs, [fixture.rootID])
        try session.execute(edit.documentCommand)
        let authored = session.document.pages
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        for node in authored[0].nodes[1...2] {
            let style = try XCTUnwrap(TypographyCommandRegistry.resolvedTypography(for: node))
            XCTAssertEqual(style.family, "System"); XCTAssertEqual(style.weight, .medium)
            XCTAssertEqual(style.size, 14); XCTAssertEqual(style.lineHeight, 17); XCTAssertEqual(style.tracking, 0)
        }
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: authored[0].nodes[1])?.alignment, .leading)
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: authored[0].nodes[2])?.alignment, .center)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(family.key.rawValue)?.id, family.id)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(weight.key.rawValue)?.id, weight.id)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(family.key.rawValue)?.origin, .authored)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(fluid.key.rawValue), fluid)
        XCTAssertEqual(authored[0].nodes[1].insertionStringProperty(CanonicalSemanticElement.key), "h2")
        XCTAssertEqual(authored[0].nodes.map(\.id), original[0].nodes.map(\.id))
        XCTAssertEqual(authored[0].nodes[1].insertionGeometry, original[0].nodes[1].insertionGeometry)
        XCTAssertEqual(authored[0].nodes[0], original[0].nodes[0])
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try registry.prepare(request(.medium), in: session.document,
            context: fixture.with(document: session.document).context)) { XCTAssertEqual($0 as? TypographyCommandError, .noChanges) }
        try session.undo(); XCTAssertEqual(session.document.pages, original)
        try session.redo(); XCTAssertEqual(session.document.pages, authored)
        try session.undo()
        try session.execute(try registry.prepare(request(.bold), in: session.document,
            context: fixture.with(document: session.document).context).documentCommand)
        XCTAssertTrue(session.historySnapshot().redoEntries.isEmpty)
    }

    // SF-0507-004/005: syntax/stale/cancel/unavailable failures never
    // leave a new family with the previous weight or mutate a partial subset.
    func testFontFamilyWeightChoiceRejectsInvalidStaleCancelledAndUnavailableTargets() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        let registry = TypographyCommandRegistry(), before = fixture.document
        func request(_ family: String = "System", cancelled: Bool = false,
                     revision: UInt64? = nil, ids: [NodeID]? = nil) -> TypographyCommand {
            .init(identity: .init(documentID: before.id, pageID: fixture.pageID,
                revision: revision ?? before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids ?? fixture.selectedIDs, edit: .fontFace(family: family, weight: .semibold),
                provenance: .keyboard, cancelled: cancelled)
        }
        for invalid in ["", " System", "System ", "Bad\nFamily", String(repeating: "x", count: 129)] {
            XCTAssertThrowsError(try registry.prepare(request(invalid), in: before, context: fixture.context)) {
                XCTAssertEqual($0 as? TypographyCommandError, .invalidValue)
            }
        }
        XCTAssertThrowsError(try registry.prepare(request(cancelled: true), in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? TypographyCommandError, .cancelled)
        }
        XCTAssertThrowsError(try registry.prepare(request(revision: before.revision + 1), in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? TypographyCommandError, .stale)
        }
        XCTAssertThrowsError(try registry.prepare(request(ids: [fixture.secondNodeID]), in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? TypographyCommandError, .stale)
        }
        XCTAssertThrowsError(try registry.prepare(request(), in: before,
            context: fixture.context(selectedIDs: fixture.selectedIDs, availableIDs: [])))
        for key in ["locked", "hidden"] {
            var blocked = fixture
            blocked.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: .boolean(true)))
            XCTAssertThrowsError(try registry.prepare(request(), in: blocked.document, context: blocked.context))
        }
        let unsupported = fixture.context(selectedIDs: [fixture.secondNodeID])
        XCTAssertThrowsError(try registry.prepare(request(ids: [fixture.secondNodeID]), in: before, context: unsupported)) {
            XCTAssertEqual($0 as? TypographyCommandError, .noApplicableTargets)
        }
        XCTAssertNil(CanonicalFontWeight(rawValue: "unlisted-weight"))
        XCTAssertEqual(fixture.document, before)
    }

    func testTypographyRegistryValidatesMixesResetsPersistsAndUndoRedo() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[2].kind = .frame
        let registry = TypographyCommandRegistry()
        func command(
            _ document: CanonicalDocument,
            ids: [NodeID],
            edit: TypographyEdit,
            cancelled: Bool = false,
            documentID: DocumentID? = nil
        ) -> TypographyCommand {
            .init(identity: .init(
                documentID: documentID ?? document.id, pageID: fixture.pageID,
                revision: document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration
            ), orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let mixed = try registry.prepare(
            command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], edit: .family("Menlo")),
            in: fixture.document,
            context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertFalse(mixed.skippedReasons.values.joined().contains(fixture.nodeID.description))

        var compatibleDocument = fixture.document
        compatibleDocument.pages[0].nodes[2].kind = .text
        let compatibleFixture = fixture.with(document: compatibleDocument)
        let compatible = try registry.prepare(
            command(compatibleDocument, ids: [fixture.nodeID, fixture.secondNodeID], edit: .size(19)),
            in: compatibleDocument,
            context: compatibleFixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(compatible.applicableNodeIDs, [fixture.nodeID, fixture.secondNodeID])
        XCTAssertTrue(compatible.skippedNodeIDs.isEmpty)
        let compatibleSession = DocumentSession(document: compatibleDocument)
        _ = try compatibleSession.execute(compatible.documentCommand)
        XCTAssertEqual(
            compatibleSession.document.pages[0].nodes.filter { $0.id == fixture.nodeID || $0.id == fixture.secondNodeID }
                .compactMap { TypographyCommandRegistry.resolvedTypography(for: $0) }.map(\.size),
            [19, 19]
        )
        try compatibleSession.undo()
        XCTAssertEqual(
            compatibleSession.document.pages[0].nodes.filter { $0.id == fixture.nodeID || $0.id == fixture.secondNodeID }
                .compactMap { TypographyCommandRegistry.resolvedTypography(for: $0) }.map(\.size),
            [14, 14]
        )
        try compatibleSession.redo()

        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(mixed.documentCommand)
        for (edit, expected) in [
            (TypographyEdit.weight(.bold), CanonicalTypography(family: "Menlo", weight: .bold, size: 14, lineHeight: 17, tracking: 0, alignment: .leading)),
            (.size(24), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 17, tracking: 0, alignment: .leading)),
            (.lineHeight(30), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 30, tracking: 0, alignment: .leading)),
            (.tracking(1.5), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 30, tracking: 1.5, alignment: .leading)),
            (.alignment(.center), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 30, tracking: 1.5, alignment: .center)),
        ] {
            let prepared = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: edit), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
            _ = try session.execute(prepared.documentCommand)
            let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
            XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: node), expected)
        }
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        let propertyIDs = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(TypographyCommandRegistry.namespace) }.map(\.id)
        try session.undo(); try session.redo()
        XCTAssertEqual(propertyIDs, session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(TypographyCommandRegistry.namespace) }.map(\.id))

        let reset = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .reset), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(reset.documentCommand)
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!), .defaultValue)
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(TypographyCommandRegistry.namespace) }.map(\.id), propertyIDs)

        for edit in [TypographyEdit.size(.nan), .size(0), .lineHeight(.infinity), .tracking(101), .family(" bad "), .family("Bad\nFamily")] {
            XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: edit), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
                XCTAssertEqual($0 as? TypographyCommandError, .invalidValue)
            }
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .size(18), cancelled: true), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? TypographyCommandError, .cancelled)
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .size(18), documentID: DocumentID()), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? TypographyCommandError, .stale)
        }
    }

    // SF-1203-001...006 — semantic tags are provenance-aware canonical
    // metadata and use the same identity-gated history boundary as Inspector
    // appearance and typography edits.
    func testSemanticElementRegistryValidatesMixedSelectionAndExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        let registry = SemanticElementCommandRegistry()
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: SemanticElementEdit, cancelled: Bool = false) -> SemanticElementCommand {
            .init(identity: .init(documentID: document.id, pageID: fixture.pageID, revision: document.revision,
                                  sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                  orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let initial = fixture.document.pages[0].nodes[1]
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: initial)?.0, .div)
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: initial)?.1, .defaulted)

        let mixed = try registry.prepare(command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], edit: .set(.article)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(mixed.documentCommand)
        var node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        let property = try XCTUnwrap(node.insertionProperty(CanonicalSemanticElement.key))
        XCTAssertEqual(property.origin, .authored)
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: node)?.0, .article)
        let propertyID = property.id
        try session.undo()
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertNil(node.insertionProperty(CanonicalSemanticElement.key))
        try session.redo()
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(node.insertionProperty(CanonicalSemanticElement.key)?.id, propertyID)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let reset = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .reset), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(reset.documentCommand)
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertNil(node.insertionProperty(CanonicalSemanticElement.key))
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: node)?.0, .div)

        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .set(.h1)), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? SemanticElementCommandError, .noApplicableTargets)
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .set(.article), cancelled: true), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? SemanticElementCommandError, .cancelled)
        }
        let stale = SemanticElementCommand(identity: .init(documentID: DocumentID(), pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID], edit: .set(.article), provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try registry.prepare(stale, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? SemanticElementCommandError, .stale)
        }
    }

    // SF-AUTHORING-098, SF-0701-002/004, SF-0702-002/004 — general
    // accessibility metadata shares the identity-gated atomic Inspector path,
    // preserves PropertyID through exact history, and skips dedicated schemas.
    func testAccessibilityMetadataRegistryCommitsMixedSubsetAndExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .form
        let registry = AccessibilityMetadataCommandRegistry()
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: AccessibilityMetadataEdit,
                     cancelled: Bool = false) -> AccessibilityMetadataCommand {
            .init(identity: .init(documentID: document.id, pageID: fixture.pageID,
                                  revision: document.revision, sceneID: fixture.sceneID,
                                  rendererGeneration: fixture.rendererGeneration),
                  orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        XCTAssertEqual(AccessibilityMetadataCommandRegistry.selectionValue(
            field: .name, nodes: [fixture.document.pages[0].nodes[1]]), .single(nil, .defaulted))
        let prepared = try registry.prepare(command(fixture.document,
            ids: [fixture.nodeID, fixture.secondNodeID], edit: .set(.name, "Hero region")),
            in: fixture.document,
            context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(prepared.skippedNodeIDs, [fixture.secondNodeID])
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        var node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        let property = try XCTUnwrap(node.insertionProperty(CanonicalAccessibilityMetadata.Field.name.key))
        XCTAssertEqual(property.value, .string("Hero region"))
        XCTAssertEqual(property.origin, .authored)
        try session.undo(); try session.redo()
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(node.insertionProperty(CanonicalAccessibilityMetadata.Field.name.key)?.id, property.id)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let reset = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .reset),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(reset.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.nodeID }?
            .insertionProperty(CanonicalAccessibilityMetadata.Field.name.key))
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID],
            edit: .set(.help, String(repeating: "x", count: 513))), in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? AccessibilityMetadataCommandError, .invalid)
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID],
            edit: .set(.name, "Name"), cancelled: true), in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? AccessibilityMetadataCommandError, .cancelled)
        }
    }

    // SF-0502-003/006, SF-0503-003/006: inspection uses the same
    // viewport-dependent winner as layout, including partially applicable sets.
    func testContainerFluidSpacingInspectionUsesViewportAndReportsMixedValues() throws {
        var fixture = makeFixture()
        for (index, kind) in [(1, NodeKind.stack), (2, NodeKind.grid)] {
            fixture.document.pages[0].nodes[index].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[index])
            let fluid = CanonicalFluidValue(minimum: 8, preferred: 16, maximum: 32)
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: CanonicalFluidValueCodec.key(.gap)),
                value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .gap)), origin: .authored))
        }
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID, fixture.rootID]
        let before = fixture.document
        let registry = ContainerLayoutCommandRegistry()
        for width in [320.0, 390, 574, 768, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let fluid = try XCTUnwrap(CanonicalFluidValueCodec.value(for: .gap, node: fixture.document.pages[0].nodes[1]))
            let expected = try XCTUnwrap(fluid.0.resolved(viewportWidth: width))
            XCTAssertEqual(registry.value(for: .gap, in: fixture.document, context: fixture.context,
                breakpoint: breakpoint, viewportWidth: width),
                .single(.number(expected), .authored, applicableCount: 2, skippedCount: 1))
            for node in fixture.document.pages[0].nodes[1...2] {
                let resolved = try XCTUnwrap(ResponsiveContainerLayoutResolver.value(
                    for: .gap, node: node, breakpoint: breakpoint, viewportWidth: width))
                XCTAssertEqual(resolved.0, .number(expected))
                XCTAssertEqual(resolved.2, .fluid)
            }
        }
        XCTAssertEqual(fixture.document, before, "Inspection must not write sampled fluid values")
        fixture.document.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == CanonicalFluidValueCodec.key(.gap) }
        XCTAssertEqual(registry.value(for: .gap, in: fixture.document, context: fixture.context,
            breakpoint: .desktop, viewportWidth: 1440), .mixed(applicableCount: 2, skippedCount: 1))
        let key = ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .tablet)
        for index in 1...2 {
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: key), value: .number(4), origin: .authored))
        }
        XCTAssertEqual(registry.value(for: .gap, in: fixture.document, context: fixture.context,
            breakpoint: .tablet, viewportWidth: 768),
            .single(.number(4), .authored, applicableCount: 2, skippedCount: 1))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .gap,
            node: fixture.document.pages[0].nodes[1], breakpoint: .tablet, viewportWidth: 768)?.2, .override(.tablet))
    }

    // SF-0502-003/005, SF-0503-003/005: fixed fallback edits cannot
    // silently replace fluid intent. Override/remove/fixed are separate history.
    func testContainerFluidSpacingCommandsPreserveOverridesAndExactHistory() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .stack
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        let fluid = CanonicalFluidValue(minimum: 8, preferred: 16, maximum: 32)
        let fluidProperty = NodeProperty(key: .init(rawValue: CanonicalFluidValueCodec.key(.gap)),
            value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .gap)), origin: .authored)
        fixture.document.pages[0].nodes[1].properties.append(fluidProperty)
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let session = DocumentSession(document: fixture.document), registry = ContainerLayoutCommandRegistry()
        func command(_ value: ContainerLayoutValue?, breakpoint: ResponsiveBreakpoint = .desktop,
                     reset: Bool = false, cancelled: Bool = false,
                     revision: UInt64? = nil) -> ContainerLayoutCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
                revision: revision ?? session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: fixture.selectedIDs,
                field: .gap, value: value, provenance: .keyboard, cancelled: cancelled,
                breakpoint: breakpoint, removesOverride: reset)
        }
        func prepare(_ value: ContainerLayoutCommand) throws -> PreparedContainerLayoutEdit {
            try registry.prepare(value, in: session.document, context: fixture.with(document: session.document).context)
        }
        let ignoredEdits: [ContainerLayoutValue?] = [.number(7), nil]
        for value in ignoredEdits {
            XCTAssertThrowsError(try prepare(command(value))) {
                XCTAssertEqual($0 as? ContainerLayoutError, .fluidValueWins)
            }
        }
        XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
        XCTAssertThrowsError(try prepare(command(.number(7), cancelled: true))) {
            XCTAssertEqual($0 as? ContainerLayoutError, .cancelled)
        }
        XCTAssertThrowsError(try prepare(command(.number(.nan)))) {
            XCTAssertEqual($0 as? ContainerLayoutError, .invalidValue)
        }
        let oldRevision = session.document.revision
        let original = session.document.pages[0].nodes
        let edit = try prepare(command(.number(6), breakpoint: .tablet))
        XCTAssertEqual(edit.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(edit.skippedNodeIDs, [fixture.secondNodeID])
        try session.execute(edit.documentCommand)
        let authored = session.document.pages[0].nodes
        XCTAssertEqual(authored[1].insertionProperty(fluidProperty.key.rawValue), fluidProperty)
        XCTAssertEqual(authored[1].insertionNumberProperty("layout.gap"), 24)
        XCTAssertEqual(registry.value(for: .gap, in: session.document,
            context: fixture.with(document: session.document).context, breakpoint: .tablet, viewportWidth: 768),
            .single(.number(6), .authored, applicableCount: 1, skippedCount: 1))
        XCTAssertThrowsError(try prepare(command(.number(5), breakpoint: .tablet, revision: oldRevision))) {
            XCTAssertEqual($0 as? ContainerLayoutError, .staleRevision)
        }
        try session.undo(); XCTAssertEqual(session.document.pages[0].nodes, original)
        try session.redo(); XCTAssertEqual(session.document.pages[0].nodes, authored)
        try session.execute(try prepare(command(nil, breakpoint: .tablet, reset: true)).documentCommand)
        XCTAssertEqual(registry.value(for: .gap, in: session.document,
            context: fixture.with(document: session.document).context, breakpoint: .tablet, viewportWidth: 768),
            .single(.number(16), .authored, applicableCount: 1, skippedCount: 1))
        let identity = GeometryInspectorOperationIdentity(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration)
        let remove = try FluidValueCommandRegistry().prepare(.init(identity: identity,
            orderedNodeIDs: fixture.selectedIDs, target: .gap, value: nil, provenance: .keyboard, cancelled: false),
            in: session.document, context: fixture.with(document: session.document).context)
        try session.execute(remove.documentCommand)
        try session.execute(try prepare(command(.number(7))).documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionNumberProperty("layout.gap"), 7)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(fluidProperty.key.rawValue), fluidProperty)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionNumberProperty("layout.gap"), 24)
    }

    // SF-0502-005, SF-0503-005: one fluid member rejects an ignored
    // multi-edit atomically, without leaking authored text into diagnostics.
    func testContainerFluidSpacingMixedRejectionIsAtomicAndRedacted() throws {
        var fixture = makeFixture()
        for (index, kind) in [(1, NodeKind.stack), (2, NodeKind.grid)] {
            fixture.document.pages[0].nodes[index].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[index])
        }
        fixture.document.pages[0].nodes[2].properties.append(.init(
            key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)),
            value: .string(try CanonicalFluidValueCodec.encode(.init(minimum: 4, preferred: 8, maximum: 16), target: .padding))))
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let before = fixture.document
        let command = ContainerLayoutCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: before.id, pageID: fixture.pageID,
            revision: before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: fixture.selectedIDs, field: .padding, value: .number(12), provenance: .keyboard, cancelled: false)
        XCTAssertThrowsError(try ContainerLayoutCommandRegistry().prepare(command, in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? ContainerLayoutError, .fluidValueWins)
        }
        XCTAssertEqual(fixture.document, before)
        let record = ContainerLayoutDiagnosticFactory.make(command: command, durationMilliseconds: 0,
            resultRevision: nil, result: .failure, failure: .fluidValueWins)
        XCTAssertEqual(record.failureCategory, "fluid-value-wins")
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertTrue(ContainerLayoutError.fluidValueWins.localizedDescription.contains("Smooth scaling"))
    }

    // SF-0501-003, SF-0505-003/005: empty Hug containers use fluid
    // padding and explicit bounds, not a placeholder child or rewritten height.
    func testEmptyFluidContainersResolveHugWithinBoundsWithoutRewritingFallbacks() throws {
        var fixture = makeFixture()
        let padding = CanonicalFluidValue(minimum: 0, preferred: 8, maximum: 16)
        for (index, kind) in [(1, NodeKind.stack), (2, NodeKind.grid)] {
            fixture.document.pages[0].nodes[index].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[index])
            let record = CanonicalFluidValue(minimum: padding.minimum, preferred: padding.preferred, maximum: padding.maximum)
            fixture.document.pages[0].nodes[index].properties += [
                .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)),
                    value: .string(try CanonicalFluidValueCodec.encode(record, target: .padding))),
                .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"), value: .string("hug")),
                .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "minHeight"), value: .number(12)),
                .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "maxHeight"), value: .number(24))
            ]
        }
        try fixture.document.validate()
        let before = fixture.document
        for width in [320.0, 390, 574, 768, 1024, 1440] {
            let frames = before.pages[0].resolvedStructuralGeometry(breakpoint: .resolving(width: width), viewportWidth: width)
            let expected = max(12, min(24, 2 * (try XCTUnwrap(padding.resolved(viewportWidth: width)))))
            for node in before.pages[0].nodes[1...2] {
                XCTAssertTrue(node.childIDs.isEmpty)
                let frame = try XCTUnwrap(frames[node.id])
                XCTAssertEqual(frame.size.height, expected, accuracy: 0.001)
                XCTAssertTrue(frame.size.width.isFinite)
                XCTAssertGreaterThan(frame.size.width, 0)
            }
        }
        XCTAssertEqual(fixture.document, before)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(before)), before)
    }

    // SF-0502-001...006 / SF-0503-001...006 / SF-0506-001...006
    func testContainerLayoutRegistryValidatesMixesResetsAndPreservesExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        var stack = fixture.document.pages[0].nodes[1]
        stack.kind = .stack
        applyStructuralDefaults(for: .stack, to: &stack)
        var grid = fixture.document.pages[0].nodes[2]
        grid.kind = .grid
        applyStructuralDefaults(for: .grid, to: &grid)
        fixture.document.pages[0].nodes[1] = stack
        fixture.document.pages[0].nodes[2] = grid
        fixture.selectedIDs = [stack.id, grid.id]
        let registry = ContainerLayoutCommandRegistry()

        func command(
            _ document: CanonicalDocument,
            field: ContainerLayoutField,
            value: ContainerLayoutValue?,
            ids: [NodeID]? = nil,
            cancelled: Bool = false,
            revision: UInt64? = nil,
            documentID: DocumentID? = nil,
            pageID: PageID? = nil,
            sceneID: CanvasViewportSceneID? = nil,
            rendererGeneration: UInt64? = nil
        ) -> ContainerLayoutCommand {
            .init(identity: .init(
                editID: GeometryInspectorEditID(), documentID: documentID ?? document.id,
                pageID: pageID ?? fixture.pageID, revision: revision ?? document.revision,
                sceneID: sceneID ?? fixture.sceneID,
                rendererGeneration: rendererGeneration ?? fixture.rendererGeneration
            ), orderedNodeIDs: ids ?? fixture.selectedIDs, field: field,
            value: value, provenance: .automation, cancelled: cancelled)
        }

        XCTAssertEqual(
            registry.value(for: .padding, in: fixture.document, context: fixture.context),
            .single(.number(24), .defaulted, applicableCount: 2, skippedCount: 0)
        )
        XCTAssertEqual(
            registry.value(for: .axis, in: fixture.document, context: fixture.context),
            .single(.axis(.vertical), .defaulted, applicableCount: 1, skippedCount: 1)
        )

        let padding = try registry.prepare(
            command(fixture.document, field: .padding, value: .number(36)),
            in: fixture.document, context: fixture.context
        )
        XCTAssertEqual(padding.applicableNodeIDs, fixture.selectedIDs)
        XCTAssertTrue(padding.skippedNodeIDs.isEmpty)
        let originalIDs = fixture.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.id
        }
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(padding.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionNumberProperty("layout.padding")
        }, [36, 36])
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.origin
        }, [.authored, .authored])
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionNumberProperty("layout.padding")
        }, [24, 24])
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.id
        }, originalIDs)
        try session.redo()

        let currentFixture = fixture.with(document: session.document)
        let axis = try registry.prepare(
            command(session.document, field: .axis, value: .axis(.horizontal), ids: fixture.selectedIDs),
            in: session.document, context: currentFixture.context(selectedIDs: fixture.selectedIDs)
        )
        XCTAssertEqual(axis.applicableNodeIDs, [stack.id])
        XCTAssertEqual(axis.skippedNodeIDs, [grid.id])
        _ = try session.execute(axis.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionStringProperty("layout.axis"), "horizontal")

        let resetFixture = fixture.with(document: session.document)
        let reset = try registry.prepare(
            command(session.document, field: .padding, value: nil, ids: fixture.selectedIDs),
            in: session.document, context: resetFixture.context(selectedIDs: fixture.selectedIDs)
        )
        _ = try session.execute(reset.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionNumberProperty("layout.padding")
        }, [24, 24])
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.origin
        }, [.defaulted, .defaulted])
        XCTAssertNoThrow(try session.document.validate())
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .columns, value: .number(0)),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .gap, value: .number(.nan)),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), cancelled: true),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .cancelled) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), revision: fixture.document.revision + 1),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleRevision) }

        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12),
                    documentID: DocumentID()),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleDocument) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12),
                    sceneID: CanvasViewportSceneID()),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleRenderer) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12),
                    rendererGeneration: fixture.rendererGeneration + 1),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleRenderer) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), ids: [stack.id, stack.id]),
            in: fixture.document, context: fixture.context(selectedIDs: [stack.id, stack.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .duplicateTarget) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), ids: [stack.id]),
            in: fixture.document, context: fixture.context(selectedIDs: [grid.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .selectionMismatch) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), ids: [stack.id]),
            in: fixture.document,
            context: fixture.context(selectedIDs: [stack.id], availableIDs: [grid.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .unavailableTarget) }

        var lockedDocument = fixture.document
        lockedDocument.pages[0].nodes[1].properties.append(booleanProperty("locked", true))
        XCTAssertThrowsError(try registry.prepare(
            command(lockedDocument, field: .padding, value: .number(12), ids: [stack.id]),
            in: lockedDocument,
            context: fixture.with(document: lockedDocument).context(selectedIDs: [stack.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .lockedTarget) }

        var hiddenDocument = fixture.document
        hiddenDocument.pages[0].nodes[1].properties.append(booleanProperty("hidden", true))
        XCTAssertThrowsError(try registry.prepare(
            command(hiddenDocument, field: .padding, value: .number(12), ids: [stack.id]),
            in: hiddenDocument,
            context: fixture.with(document: hiddenDocument).context(selectedIDs: [stack.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .hiddenTarget) }

        let diagnosticCommand = command(fixture.document, field: .padding, value: .number(72))
        let record = ContainerLayoutDiagnosticFactory.make(
            command: diagnosticCommand,
            durationMilliseconds: 0.25,
            resultRevision: fixture.document.revision + 1,
            result: .success,
            failure: nil
        )
        XCTAssertEqual(record.operationType, "container-layout.padding")
        XCTAssertEqual(record.requirementIDs, ContainerLayoutCommandRegistry.requirementIDs.sorted())
        XCTAssertFalse(String(describing: record).contains(stack.id.description))
        XCTAssertFalse(String(describing: record).contains("/Users/"))
    }

    // SF-0601-001...006 / SF-0603-001...006
    func testResponsiveContainerAndVisibilityRegistriesSetResetValidateAndPreserveExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        var stack = fixture.document.pages[0].nodes[1]
        stack.kind = .stack
        applyStructuralDefaults(for: .stack, to: &stack)
        fixture.document.pages[0].nodes[1] = stack
        fixture.selectedIDs = [stack.id]
        let context = fixture.context(selectedIDs: [stack.id])
        let identity = GeometryInspectorOperationIdentity(
            editID: GeometryInspectorEditID(), documentID: fixture.document.id,
            pageID: fixture.pageID, revision: fixture.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration
        )
        let layoutRegistry = ContainerLayoutCommandRegistry()
        let rootID = fixture.document.pages[0].nodes[0].id
        let partial = try layoutRegistry.prepare(.init(
            identity: identity, orderedNodeIDs: [stack.id, rootID], field: .gap,
            value: .number(11), provenance: .accessibility, cancelled: false,
            breakpoint: .mobile
        ), in: fixture.document, context: fixture.context(selectedIDs: [stack.id, rootID]))
        XCTAssertEqual(partial.applicableNodeIDs, [stack.id])
        XCTAssertEqual(partial.skippedNodeIDs, [rootID])

        let layout = try layoutRegistry.prepare(.init(
            identity: identity, orderedNodeIDs: [stack.id], field: .axis,
            value: .axis(.horizontal), provenance: .automation, cancelled: false,
            breakpoint: .tablet
        ), in: fixture.document, context: context)
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(layout.documentCommand)
        var node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == stack.id })
        let key = ResponsiveContainerLayoutResolver.key(.axis, breakpoint: .tablet)
        let authoredProperty = try XCTUnwrap(node.insertionProperty(key))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .axis, node: node, breakpoint: .tablet)?.0, .axis(.horizontal))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .axis, node: node, breakpoint: .mobile)?.0, .axis(.vertical))
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 768), .tablet)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 390), .mobile)
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(key))
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(key)?.id, authoredProperty.id)

        let current = fixture.with(document: session.document)
        let reset = try layoutRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], field: .axis, value: nil,
            provenance: .automation, cancelled: false, breakpoint: .tablet,
            removesOverride: true
        ), in: session.document, context: current.context(selectedIDs: [stack.id]))
        _ = try session.execute(reset.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(key))

        let visibilityRegistry = ResponsiveVisibilityCommandRegistry()
        var partialDocument = session.document
        partialDocument.pages[0].nodes[2].kind = .component
        // A linked instance is applicable; a non-rendering node without a
        // complete geometry is not. Preserve explicit subset rejection proof.
        partialDocument.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == "layout.width" }
        let partialFixture = fixture.with(document: partialDocument)
        let partialVisibility = try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: partialDocument.id,
                pageID: fixture.pageID, revision: partialDocument.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id, fixture.secondNodeID], breakpoint: .mobile, visible: false,
            provenance: .accessibility, cancelled: false
        ), in: partialDocument, context: partialFixture.context(selectedIDs: [stack.id, fixture.secondNodeID]))
        XCTAssertEqual(partialVisibility.applicableNodeIDs, [stack.id])
        XCTAssertEqual(partialVisibility.skippedNodeIDs, [fixture.secondNodeID])

        var mixedDocument = session.document
        mixedDocument.pages[0].nodes[2].properties.append(.init(
            key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)),
            value: .boolean(false), origin: .authored
        ))
        let mixedFixture = fixture.with(document: mixedDocument)
        XCTAssertEqual(visibilityRegistry.value(in: mixedDocument,
            context: mixedFixture.context(selectedIDs: [stack.id, fixture.secondNodeID]), breakpoint: .mobile),
            .mixed(applicableCount: 2, skippedCount: 0))

        let visibility = try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: false,
            provenance: .automation, cancelled: false
        ), in: session.document, context: fixture.with(document: session.document).context(selectedIDs: [stack.id]))
        _ = try session.execute(visibility.documentCommand)
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == stack.id })
        let visibilityKey = ResponsiveVisibilityResolver.key(.mobile)
        let visibilityProperty = try XCTUnwrap(node.insertionProperty(visibilityKey))
        XCTAssertFalse(ResponsiveVisibilityResolver.isVisible(node, breakpoint: .mobile))
        XCTAssertTrue(ResponsiveVisibilityResolver.isVisible(node, breakpoint: .tablet))
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey))
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey)?.id,
                       visibilityProperty.id)

        let visibilityCurrent = fixture.with(document: session.document)
        let visibilityReset = try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: nil,
            provenance: .keyboard, cancelled: false
        ), in: session.document, context: visibilityCurrent.context(selectedIDs: [stack.id]))
        _ = try session.execute(visibilityReset.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey))
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey)?.id,
                       visibilityProperty.id)
        try session.redo()

        XCTAssertNoThrow(try session.document.validate())
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        XCTAssertThrowsError(try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision + 1,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: true,
            provenance: .automation, cancelled: false
        ), in: session.document, context: fixture.with(document: session.document).context(selectedIDs: [stack.id]))) {
            XCTAssertEqual($0 as? ResponsiveVisibilityError, .staleRevision)
        }
        XCTAssertThrowsError(try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: true,
            provenance: .automation, cancelled: true
        ), in: session.document, context: fixture.with(document: session.document).context(selectedIDs: [stack.id]))) {
            XCTAssertEqual($0 as? ResponsiveVisibilityError, .cancelled)
        }

        let diagnostic = ResponsiveVisibilityDiagnosticFactory.make(
            command: .init(
                identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                    pageID: fixture.pageID, revision: session.document.revision,
                    sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: false,
                provenance: .accessibility, cancelled: false
            ),
            durationMilliseconds: 1.5, resultRevision: session.document.revision + 1,
            result: .success, failure: nil
        )
        XCTAssertEqual(diagnostic.requirementIDs, ResponsiveVisibilityCommandRegistry.requirementIDs.sorted())
        XCTAssertEqual(diagnostic.provenance, "accessibility")
        XCTAssertFalse(String(describing: diagnostic).contains(stack.id.description))
        XCTAssertFalse(String(describing: diagnostic).contains("/Users/"))

        var malformedContainer = session.document
        malformedContainer.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.axis, breakpoint: .tablet)),
            value: .string("diagonal"), origin: .authored
        ))
        XCTAssertThrowsError(try malformedContainer.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidResponsiveContainerState)
        }
        var malformedVisibility = session.document
        malformedVisibility.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveVisibilityResolver.key(.tablet)),
            value: .number(1), origin: .authored
        ))
        XCTAssertThrowsError(try malformedVisibility.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidResponsiveVisibilityState)
        }
    }

    // SF-0502/SF-0503/SF-0601 — every bounded structural kind uses the same
    // breakpoint override representation and reset semantics.
    func testResponsiveSectionAndGridOverridesResolveAndResetIndependently() throws {
        let registry = ContainerLayoutCommandRegistry()

        func prepared(
            _ field: ContainerLayoutField,
            _ value: ContainerLayoutValue?,
            breakpoint: ResponsiveBreakpoint,
            removesOverride: Bool = false,
            fixture: TransformFixture
        ) throws -> PreparedContainerLayoutEdit {
            try registry.prepare(.init(
                identity: .init(editID: GeometryInspectorEditID(), documentID: fixture.document.id,
                    pageID: fixture.pageID, revision: fixture.document.revision,
                    sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: fixture.selectedIDs, field: field, value: value,
                provenance: .keyboard, cancelled: false, breakpoint: breakpoint,
                removesOverride: removesOverride
            ), in: fixture.document, context: fixture.context)
        }

        var sectionFixture = makeFixture()
        sectionFixture.document.pages[0].nodes[1].kind = .section
        applyStructuralDefaults(for: .section, to: &sectionFixture.document.pages[0].nodes[1])
        let sectionSession = DocumentSession(document: sectionFixture.document)
        _ = try sectionSession.execute(try prepared(.padding, .number(72), breakpoint: .tablet,
            fixture: sectionFixture).documentCommand)
        var section = try XCTUnwrap(sectionSession.document.pages[0].nodes.first { $0.id == sectionFixture.nodeID })
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: section, breakpoint: .tablet)?.0, .number(72))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: section, breakpoint: .mobile)?.0, .number(48))
        sectionFixture.document = sectionSession.document
        _ = try sectionSession.execute(try prepared(.padding, nil, breakpoint: .tablet,
            removesOverride: true, fixture: sectionFixture).documentCommand)
        section = try XCTUnwrap(sectionSession.document.pages[0].nodes.first { $0.id == sectionFixture.nodeID })
        XCTAssertNil(section.insertionProperty(ResponsiveContainerLayoutResolver.key(.padding, breakpoint: .tablet)))

        var gridFixture = makeFixture()
        gridFixture.document.pages[0].nodes[1].kind = .grid
        applyStructuralDefaults(for: .grid, to: &gridFixture.document.pages[0].nodes[1])
        let gridSession = DocumentSession(document: gridFixture.document)
        for (field, value) in [
            (ContainerLayoutField.columns, ContainerLayoutValue.number(3)),
            (.gap, .number(12)),
            (.padding, .number(16)),
        ] {
            gridFixture.document = gridSession.document
            _ = try gridSession.execute(try prepared(field, value, breakpoint: .mobile,
                fixture: gridFixture).documentCommand)
        }
        let grid = try XCTUnwrap(gridSession.document.pages[0].nodes.first { $0.id == gridFixture.nodeID })
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .columns, node: grid, breakpoint: .mobile)?.0, .number(3))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .gap, node: grid, breakpoint: .mobile)?.0, .number(12))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: grid, breakpoint: .mobile)?.0, .number(16))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .columns, node: grid, breakpoint: .tablet)?.0, .number(2))
    }

    // SF-1006-001...008 — one Inspector transaction configures only Text
    // children of Form, preserving option/property identities through history.
    func testFormInspectorRegistryCommitsExactMetadataHistoryAndMixedSubset() throws {
        let formID = NodeID(UUID(uuidString: "A6100000-0000-4000-8000-000000000001")!)
        let fieldID = NodeID(UUID(uuidString: "A6100000-0000-4000-8000-000000000002")!)
        let frameID = NodeID(UUID(uuidString: "A6100000-0000-4000-8000-000000000003")!)
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID, frameID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Contact", parent: .node(rootID), childIDs: [fieldID]),
            .init(id: fieldID, kind: .text, name: "Plan", parent: .node(formID)),
            .init(id: frameID, kind: .frame, name: "Not a field", parent: .node(rootID)),
        ]
        try document.validate()

        let sceneID = CanvasViewportSceneID(UUID(uuidString: "A6100000-0000-4000-8000-000000000004")!)
        let registry = FormInspectorCommandRegistry()
        let configuration = FormFieldConfiguration(
            kind: .select, label: "Plan", name: "plan", help: "Choose a plan.", required: true,
            options: [
                .init(id: FormOptionID(UUID(uuidString: "A6100000-0000-4000-8000-000000000005")!), label: "Starter", value: "starter"),
                .init(id: FormOptionID(UUID(uuidString: "A6100000-0000-4000-8000-000000000006")!), label: "Pro", value: "pro"),
            ]
        )
        func context(_ current: CanonicalDocument, _ selected: [NodeID]) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 17,
                  selectedNodeIDs: selected, availableNodeIDs: Set(current.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func command(_ current: CanonicalDocument, _ selected: [NodeID], edit: FormInspectorEdit, cancelled: Bool = false) -> FormInspectorCommand {
            .init(identity: .init(documentID: current.id, pageID: pageID, revision: current.revision,
                                 sceneID: sceneID, rendererGeneration: 17, selectedNodeIDs: selected),
                  edit: edit, cancelled: cancelled)
        }

        let prepared = try registry.prepare(command(document, [fieldID, frameID], edit: .configure(configuration)),
                                            in: document, context: context(document, [fieldID, frameID]))
        XCTAssertEqual(prepared.applicableNodeIDs, [fieldID])
        XCTAssertEqual(prepared.skippedNodeIDs, [frameID])
        let session = DocumentSession(document: document)
        try session.execute(prepared.command)
        let configured = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID })
        XCTAssertEqual(configured.insertionStringProperty(CanonicalFormField.kindKey), "select")
        XCTAssertEqual(configured.insertionStringProperty(CanonicalFormField.nameKey), "plan")
        XCTAssertEqual(try CanonicalFormSelectOptions.decode(try XCTUnwrap(configured.insertionStringProperty(CanonicalFormField.optionsKey))), configuration.options)
        let propertyIDs = configured.properties.filter { $0.key.rawValue.hasPrefix("form.field.v1.") }.map(\.id)
        XCTAssertFalse(propertyIDs.isEmpty)
        XCTAssertTrue(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == frameID }).properties.isEmpty)

        try session.undo()
        XCTAssertTrue(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.isEmpty)
        try session.redo()
        XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.filter { $0.key.rawValue.hasPrefix("form.field.v1.") }.map(\.id), propertyIDs)

        let reordered = FormFieldConfiguration(kind: .select, label: "Plan", name: "plan",
            help: "Choose a plan.", required: true, options: Array(configuration.options.reversed()))
        let reorder = try registry.prepare(command(session.document, [fieldID], edit: .configure(reordered)),
            in: session.document, context: context(session.document, [fieldID]))
        try session.execute(reorder.command)
        let reorderedOptions = try CanonicalFormSelectOptions.decode(try XCTUnwrap(
            session.document.pages[0].nodes.first { $0.id == fieldID }?.insertionStringProperty(CanonicalFormField.optionsKey)
        ))
        XCTAssertEqual(reorderedOptions.map(\.id), configuration.options.reversed().map(\.id))

        let removal = try registry.prepare(command(session.document, [fieldID], edit: .removeConfiguration),
                                           in: session.document, context: context(session.document, [fieldID]))
        try session.execute(removal.command)
        XCTAssertTrue(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.isEmpty)
        try session.undo()
        XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.filter { $0.key.rawValue.hasPrefix("form.field.v1.") }.map(\.id), propertyIDs)
    }

    // SF-1006-002, SF-1006-005, SF-1006-008 — invalid drafts, cancellation,
    // and stale identity have no command and leave canonical content untouched.
    func testFormInspectorRegistryRejectsInvalidCancelledAndStaleEdits() throws {
        let formID = NodeID(), fieldID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [fieldID]),
            .init(id: fieldID, kind: .text, name: "Field", parent: .node(formID)),
        ]
        let sceneID = CanvasViewportSceneID()
        let context = TransformValidationContext(activePageID: pageID, currentSceneID: sceneID,
            rendererGeneration: 9, selectedNodeIDs: [fieldID], availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let identity = FormInspectorOperationIdentity(documentID: document.id, pageID: pageID,
            revision: document.revision, sceneID: sceneID, rendererGeneration: 9, selectedNodeIDs: [fieldID])
        let registry = FormInspectorCommandRegistry()
        let invalid = FormFieldConfiguration(kind: .select, label: " ", name: "1 bad", help: nil,
                                             required: false, options: [])
        XCTAssertThrowsError(try registry.prepare(.init(identity: identity, edit: .configure(invalid), cancelled: false), in: document, context: context)) {
            XCTAssertEqual($0 as? FormInspectorError, .invalidConfiguration)
        }
        XCTAssertThrowsError(try registry.prepare(.init(identity: identity, edit: .removeConfiguration, cancelled: true), in: document, context: context)) {
            XCTAssertEqual($0 as? FormInspectorError, .cancelled)
        }
        let stale = FormInspectorOperationIdentity(documentID: document.id, pageID: pageID,
            revision: document.revision + 1, sceneID: sceneID, rendererGeneration: 9, selectedNodeIDs: [fieldID])
        XCTAssertThrowsError(try registry.prepare(.init(identity: stale, edit: .removeConfiguration, cancelled: false), in: document, context: context)) {
            XCTAssertEqual($0 as? FormInspectorError, .stale)
        }
        XCTAssertEqual(document.pages[0].nodes.first { $0.id == fieldID }?.properties, [])
    }

    // SF-1006-001/002/003/004/005/008 — authored bounded validation remains
    // an optional canonical rule, is transactional, and never accepts an
    // inapplicable kind or out-of-range draft.
    func testFormInspectorValidationBoundCommitsAndRejectsInvalidKinds() throws {
        let formID = NodeID(), fieldID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [.init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [fieldID]),
                                   .init(id: fieldID, kind: .text, name: "Email", parent: .node(formID))]
        try document.validate()
        let sceneID = CanvasViewportSceneID()
        func context(_ current: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 3, selectedNodeIDs: [fieldID], availableNodeIDs: Set(current.pages[0].nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func input(_ current: CanonicalDocument, _ configuration: FormFieldConfiguration) -> FormInspectorCommand {
            .init(identity: .init(documentID: current.id, pageID: pageID, revision: current.revision, sceneID: sceneID, rendererGeneration: 3, selectedNodeIDs: [fieldID]), edit: .configure(configuration), cancelled: false)
        }
        let registry = FormInspectorCommandRegistry()
        let bounded = FormFieldConfiguration(kind: .email, label: "Email", name: "email", help: nil, required: true, options: [], maximumLength: 128)
        let prepared = try registry.prepare(input(document, bounded), in: document, context: context(document))
        let session = DocumentSession(document: document)
        try session.execute(prepared.command)
        let field = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID })
        XCTAssertEqual(field.insertionNumberProperty(CanonicalFormField.maximumLengthKey), 128)
        let propertyID = try XCTUnwrap(field.insertionProperty(CanonicalFormField.maximumLengthKey)).id
        try session.undo(); XCTAssertNil(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).insertionProperty(CanonicalFormField.maximumLengthKey))
        try session.redo(); XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).insertionProperty(CanonicalFormField.maximumLengthKey)?.id, propertyID)
        let invalid = FormFieldConfiguration(kind: .checkbox, label: "Consent", name: "consent", help: nil, required: true, options: [], maximumLength: 2)
        XCTAssertThrowsError(try registry.prepare(input(session.document, invalid), in: session.document, context: context(session.document))) { XCTAssertEqual($0 as? FormInspectorError, .invalidConfiguration) }
    }

    // SF-0701-003/004/006, SF-0702-003/004/006, SF-0705-003/004/006,
    // SF-1006-003/004/006 — Content and Accessibility consume one truthful,
    // read-only projection without borrowing the primary field's mixed value.
    func testFormInspectorAccessibilityPresentationPreservesMixedValuesAndProvenance() throws {
        let formID = NodeID(), emailID = NodeID(), selectID = NodeID(), frameID = NodeID()
        var document = ProjectCreation.blank()
        let rootID = document.pages[0].rootNodeIDs[0]
        let options = try CanonicalFormSelectOptions.encode([
            .init(label: "Starter", value: "starter"), .init(label: "Pro", value: "pro"),
        ])
        func property(_ key: String, _ value: PropertyValue, _ origin: PropertyOrigin) -> NodeProperty {
            .init(key: .init(rawValue: key), value: value, origin: origin)
        }
        let email = DocumentNode(id: emailID, kind: .text, name: "Email", parent: .node(formID), properties: [
            property(CanonicalFormField.kindKey, .string("email"), .defaulted),
            property(CanonicalFormField.labelKey, .string("Email"), .defaulted),
            property(CanonicalFormField.nameKey, .string("email"), .defaulted),
            property(CanonicalFormField.requiredKey, .boolean(true), .authored),
        ])
        let select = DocumentNode(id: selectID, kind: .text, name: "Plan", parent: .node(formID), properties: [
            property(CanonicalFormField.kindKey, .string("select"), .authored),
            property(CanonicalFormField.labelKey, .string("Plan"), .authored),
            property(CanonicalFormField.nameKey, .string("plan"), .authored),
            property(CanonicalFormField.requiredKey, .boolean(true), .authored),
            property(CanonicalFormField.optionsKey, .string(options), .authored),
        ])
        let form = DocumentNode(id: formID, kind: .form, name: "Contact", parent: .node(rootID),
                                childIDs: [emailID, selectID])
        document.pages[0].nodes[0].childIDs = [formID, frameID]
        document.pages[0].nodes += [form, email, select,
            .init(id: frameID, kind: .frame, name: "Incompatible", parent: .node(rootID))]
        try document.validate()

        let presentation = FormFieldInspectorPresentation.resolve(
            fields: [email, select], totalSelectionCount: 3)
        XCTAssertEqual(presentation.applicableCount, 2)
        XCTAssertEqual(presentation.skippedCount, 1)
        XCTAssertEqual(presentation.kind, .mixed)
        XCTAssertEqual(presentation.accessibleName, .mixed)
        XCTAssertEqual(presentation.required, .value("Required", provenance: "Set here"))
        XCTAssertTrue(presentation.configurationStatus.contains("incompatible"))

        let formPresentation = FormContainerAccessibilityPresentation.resolve(
            form: form, page: document.pages[0])
        XCTAssertEqual(formPresentation.fieldCount, 2)
        XCTAssertEqual(formPresentation.configuredCount, 2)
        XCTAssertEqual(formPresentation.requiredCount, 2)
        XCTAssertEqual(formPresentation.submitCount, 0)
        XCTAssertTrue(formPresentation.status.contains("canonical accessible labels"))
    }

    // SF-1006-001/003/004/008 — visitor input has one local, noncanonical
    // resolver. Required, email, select membership, checkbox and text bounds
    // return only stable identities and categories, never entered values.
    func testLocalFormValidationResolvesValidInvalidControlsAndRedactsValues() throws {
        let formID = NodeID(), textID = NodeID(), emailID = NodeID(), checkboxID = NodeID(), selectID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [textID, emailID, checkboxID, selectID]),
            .init(id: textID, kind: .text, name: "Text", parent: .node(formID)),
            .init(id: emailID, kind: .text, name: "Email", parent: .node(formID)),
            .init(id: checkboxID, kind: .text, name: "Consent", parent: .node(formID)),
            .init(id: selectID, kind: .text, name: "Plan", parent: .node(formID)),
        ]
        let sceneID = CanvasViewportSceneID()
        func context(_ current: CanonicalDocument, selected: [NodeID] = [textID]) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 4,
                  selectedNodeIDs: selected, availableNodeIDs: Set(current.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        let session = DocumentSession(document: document)
        let registry = FormInspectorCommandRegistry()
        for (id, configuration) in [
            (textID, FormFieldConfiguration(kind: .text, label: "Name", name: "name", help: nil, required: true, options: [])),
            (emailID, FormFieldConfiguration(kind: .email, label: "Email", name: "email", help: nil, required: true, options: [])),
            (checkboxID, FormFieldConfiguration(kind: .checkbox, label: "Consent", name: "consent", help: nil, required: true, options: [])),
            (selectID, FormFieldConfiguration(kind: .select, label: "Plan", name: "plan", help: nil, required: true,
                options: [.init(label: "Basic", value: "basic"), .init(label: "Pro", value: "pro")])),
        ] {
            let command = FormInspectorCommand(identity: .init(documentID: session.document.id, pageID: pageID,
                revision: session.document.revision, sceneID: sceneID, rendererGeneration: 4, selectedNodeIDs: [id]),
                edit: .configure(configuration), cancelled: false)
            try session.execute(registry.prepare(command, in: session.document, context: context(session.document, selected: [id])).command)
        }
        let before = session.document
        let engine = LocalFormValidationEngine()
        let valid = try engine.validate(.init(documentID: before.id, pageID: pageID, formID: formID,
            revision: before.revision, sceneID: sceneID, rendererGeneration: 4,
            values: [textID: .text("Ada"), emailID: .text("ada@example.test"), checkboxID: .checkbox(true), selectID: .select("pro")]),
            in: before, context: context(before))
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(valid.staticOutputCompatibility, .unavailableSubmission)
        XCTAssertEqual(valid.fields.map(\.identity.fieldID), [textID, emailID, checkboxID, selectID])

        let invalid = try engine.validate(.init(documentID: before.id, pageID: pageID, formID: formID,
            revision: before.revision, sceneID: sceneID, rendererGeneration: 4,
            values: [textID: .text(""), emailID: .text("visitor-secret"), checkboxID: .checkbox(false), selectID: .select("unknown")]),
            in: before, context: context(before))
        XCTAssertEqual(invalid.fields.map(\.failures), [[.required], [.invalidEmail], [.required], [.invalidSelection]])
        XCTAssertFalse(String(describing: invalid).contains("visitor-secret"))
        let malformedValues = try engine.validate(.init(documentID: before.id, pageID: pageID, formID: formID,
            revision: before.revision, sceneID: sceneID, rendererGeneration: 4,
            values: [textID: .text(String(repeating: "x", count: LocalFormValidationEngine.maximumTextLength + 1)),
                     emailID: .checkbox(true), checkboxID: .text("yes"), selectID: .checkbox(true)]),
            in: before, context: context(before))
        XCTAssertEqual(malformedValues.fields.map(\.failures), [[.textTooLong], [.invalidValueType], [.invalidValueType], [.invalidValueType]])
        XCTAssertEqual(session.document, before, "Validation must not mutate canonical state.")
    }

    // SF-1006-001/004/005/008 — cancellation, stale scene/revision and an
    // invalid schema are neutral; recovery/reopen can validate the same local
    // input without serializing any visitor value.
    func testLocalFormValidationRejectsCancelledStaleAndInvalidSchemasWithoutMutation() throws {
        let formID = NodeID(), fieldID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [fieldID]),
            .init(id: fieldID, kind: .text, name: "Email", parent: .node(formID)),
        ]
        let sceneID = CanvasViewportSceneID()
        let formRegistry = FormInspectorCommandRegistry()
        func context(_ current: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 8,
                  selectedNodeIDs: [fieldID], availableNodeIDs: Set(current.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        let session = DocumentSession(document: document)
        let configure = FormInspectorCommand(identity: .init(documentID: document.id, pageID: pageID,
            revision: document.revision, sceneID: sceneID, rendererGeneration: 8, selectedNodeIDs: [fieldID]),
            edit: .configure(.init(kind: .email, label: "Email", name: "email", help: nil, required: true, options: [])), cancelled: false)
        try session.execute(formRegistry.prepare(configure, in: document, context: context(document)).command)
        let persisted = try DocumentSerializer.decode(try DocumentSerializer.encode(session.document))
        let before = persisted
        let input = FormVisitorValueSnapshot(documentID: persisted.id, pageID: pageID, formID: formID,
            revision: persisted.revision, sceneID: sceneID, rendererGeneration: 8, values: [fieldID: .text("visitor@example.test")])
        let engine = LocalFormValidationEngine()
        XCTAssertTrue(try engine.validate(input, in: persisted, context: context(persisted)).isValid)
        XCTAssertThrowsError(try engine.validate(input, in: persisted, context: context(persisted), cancelled: true)) {
            XCTAssertEqual($0 as? FormValidationError, .cancelled)
        }
        var stale = input
        stale = .init(documentID: stale.documentID, pageID: stale.pageID, formID: stale.formID,
            revision: stale.revision + 1, sceneID: stale.sceneID, rendererGeneration: stale.rendererGeneration, values: stale.values)
        XCTAssertThrowsError(try engine.validate(stale, in: persisted, context: context(persisted))) {
            XCTAssertEqual($0 as? FormValidationError, .stale)
        }
        var malformed = persisted
        let index = try XCTUnwrap(malformed.pages[0].nodes.firstIndex { $0.id == fieldID })
        malformed.pages[0].nodes[index].properties.removeAll { $0.key.rawValue == CanonicalFormField.requiredKey }
        XCTAssertThrowsError(try engine.validate(input, in: malformed, context: context(malformed))) {
            XCTAssertEqual($0 as? FormValidationError, .invalidSchema)
        }
        let emptyFormID = NodeID()
        var empty = persisted
        empty.pages[0].nodes[0].childIDs.append(emptyFormID)
        empty.pages[0].nodes.append(.init(id: emptyFormID, kind: .form, name: "Empty", parent: .node(rootID)))
        let emptyInput = FormVisitorValueSnapshot(documentID: empty.id, pageID: pageID, formID: emptyFormID,
            revision: empty.revision, sceneID: sceneID, rendererGeneration: 8, values: [:])
        XCTAssertThrowsError(try engine.validate(emptyInput, in: empty, context: context(empty))) {
            XCTAssertEqual($0 as? FormValidationError, .invalidSchema)
        }
        XCTAssertEqual(persisted, before)
        XCTAssertFalse(try DocumentSerializer.encode(persisted).contains(Data("visitor@example.test".utf8)))
    }

    // SF-AUTHORING-101, SF-0601-003/006, SF-0602-002/003/004/006/008,
    // SF-0603-002/003/006 — review is a pure projection of the established
    // responsive resolvers and cannot mutate canonical content.
    func testResponsiveBreakpointReviewProjectsResolvedDifferencesWithoutMutation() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let stackID = NodeID()
        let stack = DocumentNode(id: stackID, kind: .stack, name: "Feature Stack", parent: .node(rootID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(120), origin: .authored),
            .init(key: .init(rawValue: "layout.y"), value: .number(80), origin: .authored),
            .init(key: .init(rawValue: "layout.width"), value: .number(480), origin: .authored),
            .init(key: .init(rawValue: "layout.height"), value: .number(320), origin: .authored),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)), value: .number(40), origin: .authored),
            .init(key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .tablet)), value: .number(12), origin: .authored),
            .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false), origin: .authored),
        ])
        document.pages[0].nodes[0].childIDs = [stackID]
        document.pages[0].nodes.append(stack)
        let before = document

        let reviews = ResponsiveBreakpointReviewPolicy.reviews(
            page: try XCTUnwrap(document.pages.first { $0.id == pageID }),
            selectedNodeIDs: [stackID]
        )
        XCTAssertEqual(reviews.map(\.breakpoint), [.desktop, .tablet, .mobile])
        XCTAssertEqual(reviews.map(\.viewportWidth), [1_440, 768, 390])
        XCTAssertEqual(reviews[0].visibleCount, 1)
        XCTAssertEqual(reviews[0].changedFromDesktopCount, 0)
        XCTAssertEqual(reviews[1].geometryOverrideCount, 1)
        XCTAssertEqual(reviews[1].containerOverrideCount, 1)
        XCTAssertEqual(reviews[1].primaryGeometry?.origin.x, 40)
        XCTAssertEqual(reviews[1].primaryProvenance, "authored geometry, inherited visibility")
        XCTAssertEqual(reviews[2].visibilityOverrideCount, 1)
        XCTAssertEqual(reviews[2].visibleCount, 0)
        XCTAssertEqual(reviews[2].changedFromDesktopCount, 1)
        XCTAssertEqual(reviews[2].primaryIsVisible, false)
        XCTAssertEqual(document, before, "Responsive review must remain scene-local and mutation-neutral.")
    }

    // SF-AUTHORING-102, SF-0604-001/003/004/005/008 — the closed v1 payload
    // round-trips stable identity and resolves one monotonic value at the
    // product reference widths; malformed and inverted payloads are rejected.
    // SF-0602-003, SF-0604-003: inspection and rendering resolve the
    // same continuous range; a device literal is never mistaken for fluid.
    func testEffectiveFluidTypographyAndGeometryResolveAtBreakpointBoundaries() throws {
        var fixture = makeFixture()
        let fontSize = CanonicalFluidValue(minimum: 12, preferred: 16, maximum: 20)
        let lineHeight = CanonicalFluidValue(minimum: 18, preferred: 24, maximum: 30)
        let widthRange = CanonicalFluidValue(minimum: 100, preferred: 150, maximum: 200)
        for index in 1...2 {
            fixture.document.pages[0].nodes[index].kind = .text
            for (target, value) in [(FluidValueTarget.fontSize, fontSize), (.lineHeight, lineHeight), (.width, widthRange)] {
                let record = CanonicalFluidValue(minimum: value.minimum, preferred: value.preferred, maximum: value.maximum)
                fixture.document.pages[0].nodes[index].properties.append(.init(
                    key: .init(rawValue: CanonicalFluidValueCodec.key(target)),
                    value: .string(try CanonicalFluidValueCodec.encode(record, target: target)), origin: .authored))
            }
        }
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)),
            value: .number(180), origin: .authored))
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        try fixture.document.validate()
        let before = fixture.document
        let nodes = Array(before.pages[0].nodes[1...2])
        let ranges = try nodes.map { try XCTUnwrap(CanonicalFluidValueCodec.value(for: .fontSize, node: $0)?.0) }
        XCTAssertNotEqual(ranges[0].id, ranges[1].id)
        XCTAssertEqual(FluidValueCommandRegistry().value(for: .fontSize, in: before, context: fixture.context),
            .single(ranges[0], .authored, applicableCount: 2, skippedCount: 0),
            "Separate stable identities do not make identical authored ranges Mixed")
        for width in [320.0, 390, 599, 600, 767, 768, 1023, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let size = try XCTUnwrap(fontSize.resolved(viewportWidth: width))
            let height = try XCTUnwrap(lineHeight.resolved(viewportWidth: width))
            let typography = try XCTUnwrap(TypographyCommandRegistry.resolvedTypography(for: nodes[0], viewportWidth: width))
            XCTAssertEqual(typography.size, size, accuracy: 0.0001)
            XCTAssertEqual(typography.lineHeight, height, accuracy: 0.0001)
            XCTAssertEqual(TypographyCommandRegistry.selectionValue(nodes: nodes, viewportWidth: width), .single(typography, .authored))
            let resolved = try XCTUnwrap(FluidValueCommandRegistry.effectiveValue(for: .fontSize,
                node: nodes[0], breakpoint: breakpoint, viewportWidth: width))
            XCTAssertEqual(resolved.0, size, accuracy: 0.0001)
            XCTAssertEqual(resolved.1, .fluid)
            let geometry = try XCTUnwrap(FluidValueCommandRegistry.effectiveValue(for: .width,
                node: nodes[0], breakpoint: breakpoint, viewportWidth: width))
            XCTAssertEqual(geometry.0, breakpoint == .mobile ? 180 : try XCTUnwrap(widthRange.resolved(viewportWidth: width)), accuracy: 0.0001)
            XCTAssertEqual(geometry.1, breakpoint == .mobile ? .override(.mobile) : .fluid)
        }
        for width in [Double.nan, .infinity, 0, -1] {
            XCTAssertNil(FluidValueCommandRegistry.effectiveValue(for: .fontSize,
                node: nodes[0], breakpoint: .desktop, viewportWidth: width))
        }
        XCTAssertNil(FluidValueCommandRegistry.effectiveValue(for: .gap, node: nodes[0], breakpoint: .desktop, viewportWidth: 1440))
        XCTAssertEqual(TypographyCommandRegistry.selectionValue(nodes: nodes), .single(.defaultValue, .defaulted),
            "Fixed fallback inspection stays separate from effective fluid typography")
        var mixed = fixture
        let propertyIndex = try XCTUnwrap(mixed.document.pages[0].nodes[2].properties.firstIndex {
            $0.key.rawValue == CanonicalFluidValueCodec.key(.fontSize)
        })
        mixed.document.pages[0].nodes[2].properties[propertyIndex].value = .string(try CanonicalFluidValueCodec.encode(
            .init(id: ranges[1].id, minimum: 13, preferred: 17, maximum: 21), target: .fontSize))
        XCTAssertEqual(FluidValueCommandRegistry().value(for: .fontSize, in: mixed.document, context: mixed.context),
            .mixed(applicableCount: 2, skippedCount: 0))
        XCTAssertEqual(TypographyCommandRegistry.selectionValue(nodes: mixed.document.pages[0].nodes, viewportWidth: 390),
            .mixed(applicableCount: 2, skippedCount: 1))
        let session = DocumentSession(document: before)
        let unified = FluidValueCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: before.id,
            pageID: fixture.pageID, revision: before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: fixture.selectedIDs, target: .fontSize,
            value: .init(minimum: 13, preferred: 17, maximum: 21), provenance: .keyboard, cancelled: false)
        try session.execute(try FluidValueCommandRegistry().prepare(unified, in: before, context: fixture.context).documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            CanonicalFluidValueCodec.value(for: .fontSize, node: $0)?.0.id
        }, ranges.map(\.id))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let committed = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, committed)
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0604-002/005: invalid/cancel/stale ranges cannot replace
    // authored IDs, device overrides, fallback typography or exact inverses.
    func testFluidTypographyInvalidStaleAndCancelledRangesPreserveCanonicalIntent() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(180)))
        let session = DocumentSession(document: fixture.document), registry = FluidValueCommandRegistry()
        func request(_ value: CanonicalFluidValue?, cancelled: Bool = false, revision: UInt64? = nil) -> FluidValueCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: revision ?? session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], target: .fontSize, value: value, provenance: .keyboard, cancelled: cancelled)
        }
        func prepare(_ value: FluidValueCommand) throws -> PreparedFluidValueEdit {
            try registry.prepare(value, in: session.document, context: fixture.with(document: session.document).context)
        }
        let before = session.document.pages
        for invalid in [CanonicalFluidValue(minimum: 20, preferred: 10, maximum: 30),
                        .init(minimum: .nan, preferred: 10, maximum: 20),
                        .init(minimum: 10, preferred: 20, maximum: .infinity),
                        .init(minimum: 0, preferred: 12, maximum: 20)] {
            XCTAssertThrowsError(try prepare(request(invalid))) { XCTAssertEqual($0 as? FluidValueCommandError, .invalidValue) }
        }
        XCTAssertThrowsError(try prepare(request(.init(minimum: 10, preferred: 14, maximum: 18), cancelled: true))) {
            XCTAssertEqual($0 as? FluidValueCommandError, .cancelled)
        }
        let oldRevision = session.document.revision
        try session.execute(try prepare(request(.init(minimum: 10, preferred: 14, maximum: 18))).documentCommand)
        let authored = session.document.pages
        XCTAssertThrowsError(try prepare(request(nil, revision: oldRevision))) { XCTAssertEqual($0 as? FluidValueCommandError, .stale) }
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionNumberProperty(ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), 180)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, authored)
    }

    func testFluidValueCodecResolutionValidationAndRoundTrip() throws {
        let value = CanonicalFluidValue(minimum: 24, preferred: 36, maximum: 60)
        let encoded = try CanonicalFluidValueCodec.encode(value, target: .padding)
        let decoded = try CanonicalFluidValueCodec.decode(encoded, target: .padding)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.resolved(viewportWidth: 390), 24)
        XCTAssertEqual(decoded.resolved(viewportWidth: 768), 36)
        XCTAssertEqual(decoded.resolved(viewportWidth: 1_440), 60)
        XCTAssertEqual(try XCTUnwrap(decoded.resolved(viewportWidth: 579)), 30, accuracy: 0.001)
        XCTAssertThrowsError(try CanonicalFluidValueCodec.encode(
            .init(minimum: 40, preferred: 20, maximum: 60), target: .padding))
        XCTAssertThrowsError(try CanonicalFluidValueCodec.decode("{}", target: .padding))
        var malformed = ProjectCreation.blank()
        malformed.pages[0].nodes[0].properties.append(.init(
            key: .init(rawValue: CanonicalFluidValueCodec.key(.width)),
            value: .string("{\"schemaVersion\":1}"), origin: .authored))
        XCTAssertThrowsError(try DocumentSerializer.encode(malformed)) {
            XCTAssertEqual($0 as? DocumentSerializationError, .invalidModel(.invalidFluidValueState))
        }
        let legacyOmitted = ProjectCreation.blank()
        let reopened = try DocumentSerializer.decode(try DocumentSerializer.encode(legacyOmitted))
        XCTAssertFalse(reopened.pages.flatMap(\.nodes).flatMap(\.properties).contains {
            $0.key.rawValue.hasPrefix(CanonicalFluidValueCodec.namespace)
        }, "Existing fixed packages remain omitted rather than acquiring synthetic fluid values.")
    }

    // SF-0604-001...006/008 — one identity-gated transaction owns creation,
    // exact history restoration, persistence, subset reporting, reset, and
    // fixed-value fallback without rewriting the fallback literal.
    func testFluidValueRegistryCommitsApplicableSubsetPersistsAndRestoresExactInverse() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        let frameID = NodeID(), unsupportedID = NodeID(), sceneID = CanvasViewportSceneID()
        document.pages[0].nodes[0].childIDs = [frameID, unsupportedID]
        document.pages[0].nodes += [
            .init(id: frameID, kind: .frame, name: "Fluid Frame", parent: .node(rootID), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
                .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
            ]),
            .init(id: unsupportedID, kind: .form, name: "Form", parent: .node(rootID)),
        ]
        let selected = [frameID, unsupportedID]
        func context(_ value: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 7,
                  selectedNodeIDs: selected, availableNodeIDs: Set(value.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func command(_ value: CanonicalFluidValue?) -> FluidValueCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: document.id,
                pageID: pageID, revision: document.revision, sceneID: sceneID, rendererGeneration: 7),
                orderedNodeIDs: selected, target: .width, value: value,
                provenance: .keyboard, cancelled: false)
        }
        let registry = FluidValueCommandRegistry()
        let fluid = CanonicalFluidValue(minimum: 180, preferred: 240, maximum: 360)
        let prepared = try registry.prepare(command(fluid), in: document, context: context(document))
        XCTAssertEqual(prepared.applicableNodeIDs, [frameID]); XCTAssertEqual(prepared.skippedNodeIDs, [unsupportedID])
        let diagnostic = FluidValueDiagnosticFactory.make(
            command: command(fluid), durationMilliseconds: 1, resultRevision: 1,
            result: .success, failure: nil)
        XCTAssertEqual(diagnostic.requirementIDs, FluidValueCommandRegistry.requirementIDs.sorted())
        XCTAssertFalse(String(describing: diagnostic).contains(frameID.description))
        // Sanitized identity hashes can coincidentally contain a decimal value.
        // Prove content independence instead of inspecting arbitrary hash digits.
        let differentContentDiagnostic = FluidValueDiagnosticFactory.make(
            command: command(.init(minimum: 120, preferred: 300, maximum: 480)),
            durationMilliseconds: 1, resultRevision: 1, result: .success, failure: nil)
        XCTAssertEqual(diagnostic, differentContentDiagnostic,
                       "Authored fluid values must not affect support diagnostics.")
        let cancelled = FluidValueCommand(identity: command(fluid).identity, orderedNodeIDs: selected,
            target: .width, value: fluid, provenance: .keyboard, cancelled: true)
        XCTAssertThrowsError(try registry.prepare(cancelled, in: document, context: context(document))) {
            XCTAssertEqual($0 as? FluidValueCommandError, .cancelled)
        }
        let stale = FluidValueCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: document.id, pageID: pageID, revision: document.revision + 1,
            sceneID: sceneID, rendererGeneration: 7), orderedNodeIDs: selected,
            target: .width, value: fluid, provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try registry.prepare(stale, in: document, context: context(document))) {
            XCTAssertEqual($0 as? FluidValueCommandError, .stale)
        }
        let session = DocumentSession(document: document)
        try session.execute(prepared.documentCommand)
        let property = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width)))
        let propertyID = property.id
        let reopened = try DocumentSerializer.decode(try DocumentSerializer.encode(session.document))
        XCTAssertEqual(try CanonicalFluidValueCodec.decode(try XCTUnwrap(reopened.pages[0].nodes.first {
            $0.id == frameID
        }?.insertionStringProperty(CanonicalFluidValueCodec.key(.width))), target: .width), fluid)
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width)))
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width))?.id, propertyID)
        let reviews = ResponsiveBreakpointReviewPolicy.reviews(
            page: session.document.pages[0], selectedNodeIDs: [frameID])
        XCTAssertEqual(reviews.map(\.fluidValueCount), [1, 1, 1])
        XCTAssertTrue(reviews[0].primaryFluidSummary?.contains("Width 360") == true)
        XCTAssertTrue(reviews[2].primaryFluidSummary?.contains("Width 180") == true)
        let remove = FluidValueCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: pageID, revision: session.document.revision,
            sceneID: sceneID, rendererGeneration: 7), orderedNodeIDs: selected,
            target: .width, value: nil, provenance: .pointer, cancelled: false)
        try session.execute(try registry.prepare(remove, in: session.document,
            context: context(session.document)).documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width)))
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionNumberProperty("layout.width"), 240)
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width))?.id, propertyID)
    }

    // SF-0604-002/003/006/008 — renderer/layout and safe static output consume
    // the same canonical clamp, while a breakpoint literal remains the winner.
    func testFluidValueFeedsLayoutTypographyContainerAndSafeStaticOutputWithOverridePrecedence() throws {
        let width = CanonicalFluidValue(minimum: 160, preferred: 240, maximum: 400)
        let padding = CanonicalFluidValue(minimum: 12, preferred: 24, maximum: 48)
        let encodedWidth = try CanonicalFluidValueCodec.encode(width, target: .width)
        let encodedPadding = try CanonicalFluidValueCodec.encode(padding, target: .padding)
        var node = DocumentNode(kind: .section, name: "Fluid Section", parent: .page(PageID()), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
            .init(key: .init(rawValue: "layout.padding"), value: .number(24), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.width)), value: .string(encodedWidth), origin: .authored),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)), value: .string(encodedPadding), origin: .authored),
        ])
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .tablet,
                                                        viewportWidth: 768)?.0, 240)
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: node, breakpoint: .mobile,
                                                               viewportWidth: 390)?.0, .number(12))
        node.properties.append(.init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)),
                                     value: .number(222), origin: .authored))
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .tablet,
                                                        viewportWidth: 768)?.0, 222)
        let css = StaticFluidValueOutputEmitter.emit(nodes: [node])
        XCTAssertTrue(css.contains("width: clamp(160px")); XCTAssertTrue(css.contains("padding: clamp(12px"))
        XCTAssertTrue(css.contains("@media (min-width: 768px)"))
    }

    // SF-0504/SF-0510/SF-0511 — positioning, reusable appearance, and the
    // bounded state vocabulary share one identity-gated transactional path.
    private func preparedReusableEdit(_ edit: AdvancedStyleEdit, session: DocumentSession,
                                     fixture: TransformFixture, ids: [NodeID]? = nil,
                                     cancelled: Bool = false) throws -> PreparedDesignInspectorEdit {
        let current = fixture.with(document: session.document), selected = ids ?? [fixture.nodeID]
        return try AdvancedStyleCommandRegistry().prepare(.init(identity: .init(documentID: session.document.id,
            pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: selected, edit: edit,
            provenance: .keyboard, cancelled: cancelled), in: session.document,
            context: current.context(selectedIDs: selected))
    }

    // SF-0510-002/003/005: link/reorder/unlink preserve other links
    // independently on mixed selections, with one exact reversible transaction.
    func testReusableStyleLinksPreserveMixedOrderingAndExactHistory() throws {
        var fixture = makeFixture()
        let text = DocumentNode(kind: .text, name: "Caption", parent: .node(fixture.rootID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(0)),
            .init(key: .init(rawValue: "layout.width"), value: .number(120)), .init(key: .init(rawValue: "layout.height"), value: .number(24))])
        fixture.document.pages[0].nodes[0].childIDs.append(text.id); fixture.document.pages[0].nodes.append(text)
        let session = DocumentSession(document: fixture.document), a = ReusableStyleID(), b = ReusableStyleID()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#0000FFFF"))
        for (id, name, color) in [(a, "First", red), (b, "Second", blue)] {
            try session.execute(try preparedReusableEdit(.createReusableStyle(id: id, name: name, fill: color, opacity: nil),
                session: session, fixture: fixture).documentCommand)
        }
        try session.execute(try preparedReusableEdit(.linkReusableStyle(a), session: session, fixture: fixture).documentCommand)
        try session.execute(try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture,
            ids: [fixture.secondNodeID]).documentCommand)
        let before = session.document.pages
        let propertyID = try XCTUnwrap(before[0].nodes[1].insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id)
        let ids = [fixture.nodeID, fixture.secondNodeID, text.id]
        let edit = try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture, ids: ids)
        XCTAssertEqual(edit.skippedNodeIDs, [text.id])
        try session.execute(edit.documentCommand)
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(session.document.pages[0].nodes[1]), [a, b])
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(session.document.pages[0].nodes[2]), [b])
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id, propertyID)
        let linked = session.document.pages
        XCTAssertThrowsError(try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture, ids: ids)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .noChanges)
        }
        try session.execute(try preparedReusableEdit(.moveReusableStyle(b, offset: -1), session: session, fixture: fixture, ids: ids).documentCommand)
        let reordered = session.document.pages
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(reordered[0].nodes[1]), [b, a])
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(reordered[0].nodes[2]), [b])
        let index = try CanonicalReusableStyleIndex(document: session.document)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: reordered[0].nodes[1], index: index).fill, red)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: reordered[0].nodes[2], index: index).fill, blue)
        try session.undo(); XCTAssertEqual(session.document.pages, linked)
        try session.redo(); XCTAssertEqual(session.document.pages, reordered)
        try session.execute(try preparedReusableEdit(.unlinkReusableStyle(b), session: session, fixture: fixture, ids: ids).documentCommand)
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(session.document.pages[0].nodes[1]), [a])
        XCTAssertNil(session.document.pages[0].nodes[2].insertionProperty(CanonicalReusableStyleIndex.appliedKey))
        try session.undo(); XCTAssertEqual(session.document.pages, reordered)
        try session.undo(); try session.undo(); XCTAssertEqual(session.document.pages, before)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try preparedReusableEdit(.moveReusableStyle(a, offset: 99), session: session, fixture: fixture))
        XCTAssertThrowsError(try preparedReusableEdit(.linkReusableStyle(ReusableStyleID()), session: session, fixture: fixture))
        XCTAssertThrowsError(try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture, cancelled: true)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .cancelled)
        }
        func diagnostic(_ styleID: ReusableStyleID) -> AdvancedStyleDiagnosticRecord {
            let command = AdvancedStyleCommand(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids, edit: .linkReusableStyle(styleID), provenance: .keyboard, cancelled: false)
            return AdvancedStyleDiagnosticFactory.make(command: command, resultRevision: nil, result: .stale, failure: .stale)
        }
        XCTAssertEqual(diagnostic(a), diagnostic(b), "Style values/names/targets must not enter diagnostic payloads")
        XCTAssertEqual(diagnostic(a).operationType, "reusable.link")
    }

    // SF-0510-001/004: linked box appearance uses one strict, grouped field
    // codec. A partial group, non-canonical color, wrong type, out-of-range
    // value or unknown field is invalid instead of silently dropped.
    func testReusableStyleLinkedBoxAppearanceUsesOneStrictGroupedCodec() throws {
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF")),
                                     width: 2, style: .dashed)
        let shadow = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00000040")),
                                     offsetX: 0, offsetY: 4, blur: 12, spread: -2)
        let box = CanonicalReusableBoxAppearance(border: border, cornerRadius: 8, shadow: shadow)
        XCTAssertTrue(box.isValid)
        XCTAssertFalse(box.isEmpty)
        XCTAssertTrue(CanonicalReusableBoxAppearance().isEmpty)
        let map = Dictionary(uniqueKeysWithValues: box.fieldValues.map { ($0.field, $0.value) })
        XCTAssertEqual(Set(map.keys), CanonicalReusableBoxAppearance.fields)
        XCTAssertEqual(box.fieldValues.map { $0.field }, CanonicalReusableBoxAppearance.borderFields
            + CanonicalReusableBoxAppearance.cornerRadiusFields + CanonicalReusableBoxAppearance.shadowFields)
        XCTAssertEqual(map["borderColor"], .string("#204060FF"))
        XCTAssertEqual(map["borderStyle"], .string("dashed"))
        XCTAssertEqual(map["shadowSpread"], .number(-2))
        XCTAssertEqual(try CanonicalReusableBoxAppearance.decode(map), box)
        XCTAssertEqual(try CanonicalReusableBoxAppearance.decode([:]), CanonicalReusableBoxAppearance())
        XCTAssertEqual(CanonicalReusableBoxAppearance(cornerRadius: 6).fieldValues.map { $0.field }, ["cornerRadius"])

        var invalid: [[String: PropertyValue]] = []
        for field in CanonicalReusableBoxAppearance.borderFields + CanonicalReusableBoxAppearance.shadowFields {
            var partial = map
            partial.removeValue(forKey: field)
            invalid.append(partial)
        }
        let replacements: [(String, PropertyValue)] = [
            ("borderColor", .string("#204060ff")), ("shadowColor", .string("#000000")),
            ("borderStyle", .string("double")), ("borderWidth", .number(101)), ("cornerRadius", .number(-1)),
            ("cornerRadius", .number(10_001)), ("shadowBlur", .number(.nan)), ("shadowOffsetX", .number(.infinity)),
            ("cornerRadius", .string("8")), ("borderWidth", .boolean(true)), ("borderGlow", .number(1)),
        ]
        for (field, value) in replacements {
            var changed = map
            changed[field] = value
            invalid.append(changed)
        }
        for values in invalid {
            XCTAssertThrowsError(try CanonicalReusableBoxAppearance.decode(values)) {
                XCTAssertEqual($0 as? ModelValidationError, .invalidReusableStyleState)
            }
        }

        // Off-grid colors are stored as RGBA8, like linked fills; storing twice is stable.
        let fine = CanonicalReusableBoxAppearance(border: CanonicalBorder(
            color: CanonicalSolidColor(red: 0.1234, green: 0.5, blue: 0.75, alpha: 1), width: 1, style: .solid))
        let stored = try CanonicalReusableBoxAppearance.decode(
            Dictionary(uniqueKeysWithValues: fine.fieldValues.map { ($0.field, $0.value) }))
        XCTAssertEqual(stored, fine.quantized)
        XCTAssertNotEqual(stored, fine)
        XCTAssertEqual(fine.quantized.quantized, fine.quantized)
        XCTAssertEqual(box.semanticFingerprint, box.quantized.semanticFingerprint)
        XCTAssertNotEqual(box.semanticFingerprint, CanonicalReusableBoxAppearance(border: border).semanticFingerprint)
    }

    // SF-0510-001/004/005: linked box values validate as part of the document,
    // need document schema 23, and a schema-22 project reopens unchanged.
    func testLinkedBoxStylesValidateInTheDocumentAndRequireSchemaTwentyThree() throws {
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 3, style: .solid)
        let box = CanonicalReusableBoxAppearance(border: border, cornerRadius: 12)
        let styleID = ReusableStyleID()
        var document = CanonicalDocument()
        document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Rounded card", box: box)
        try document.validate()
        let index = try CanonicalReusableStyleIndex(document: document)
        XCTAssertEqual(index.byID[styleID]?.box, box)
        XCTAssertNil(index.byID[styleID]?.fill, "A box-only style needs no fill or opacity")
        XCTAssertNil(index.byID[styleID]?.opacity)
        XCTAssertEqual(index.byID[styleID]?.hasAppearance, true)

        XCTAssertEqual(CanonicalReusableBoxAppearance.documentSchema, 23)
        XCTAssertGreaterThanOrEqual(DocumentSerializer.currentSchemaVersion, CanonicalReusableBoxAppearance.documentSchema)
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, DocumentSerializer.currentSchemaVersion)
        for older in [22, 21, 18] {
            envelope["schemaVersion"] = older
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "\(older)")
        }

        var plain = CanonicalDocument()
        plain.pages[0].nodes[0].properties += linkedBoxStyleProperties(ReusableStyleID(), name: "Fill only",
            box: .init(), fill: "#FF0000FF")
        try plain.validate()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(plain)) as? [String: Any])
        legacy["schemaVersion"] = 22
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)), plain)

        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        var partial = document
        partial.pages[0].nodes[0].properties.removeAll { $0.key.rawValue == prefix + "borderStyle" }
        XCTAssertThrowsError(try partial.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidReusableStyleState)
        }
        var repeated = document
        repeated.pages[0].nodes[0].properties.append(.init(key: .init(rawValue: prefix + "cornerRadius"), value: .number(4)))
        XCTAssertThrowsError(try repeated.validate())
        var nameOnly = CanonicalDocument()
        nameOnly.pages[0].nodes[0].properties += linkedBoxStyleProperties(ReusableStyleID(), name: "Empty", box: .init())
        XCTAssertThrowsError(try nameOnly.validate(), "A style must supply at least one appearance value")
        var unknown = document
        unknown.pages[0].nodes[0].properties.append(.init(key: .init(rawValue: prefix + "borderGlow"), value: .number(1)))
        XCTAssertThrowsError(try unknown.validate())
    }

    // SF-0510-003: group by group, the object's own value wins, then the last
    // applied style that supplies the group, then nothing; each value reports
    // the rule that supplied it. Tokens, shadow enable and padding stay local.
    func testLinkedBoxResolutionIsLocalFirstThenLastLinkedStyleWithProvenance() throws {
        let thin = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#111111FF")), width: 1, style: .solid)
        let thick = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#222222FF")), width: 4, style: .dotted)
        let soft = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00000033")),
                                   offsetX: 0, offsetY: 2, blur: 6, spread: 0)
        let a = ReusableStyleID(), b = ReusableStyleID()
        var document = CanonicalDocument()
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].properties += linkedBoxStyleProperties(a, name: "Base",
            box: .init(border: thin, cornerRadius: 6, shadow: soft))
            + linkedBoxStyleProperties(b, name: "Emphasis", box: .init(border: thick))
        var card = DocumentNode(kind: .frame, name: "Card", parent: .node(rootID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(20)), .init(key: .init(rawValue: "layout.y"), value: .number(20)),
            .init(key: .init(rawValue: "layout.width"), value: .number(200)), .init(key: .init(rawValue: "layout.height"), value: .number(120)),
            .init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string("\(a.description),\(b.description)")),
        ])
        document.pages[0].nodes[0].childIDs.append(card.id)
        document.pages[0].nodes.append(card)
        try document.validate()
        let index = try CanonicalReusableStyleIndex(document: document)
        func resolve(_ node: DocumentNode, tokens: [LocalColorToken] = []) throws -> CanonicalBoxStyleResolution {
            try XCTUnwrap(CanonicalLinkedBoxStyleResolver.resolve(node: node, tokens: tokens, index: index))
        }

        let linked = try resolve(card)
        XCTAssertEqual(linked.style.border, thick, "The later applied style wins its group")
        XCTAssertEqual(linked.borderSource, .linked(b))
        XCTAssertEqual(linked.style.cornerRadius, 6, "An earlier style still supplies groups the later one omits")
        XCTAssertEqual(linked.cornerRadiusSource, .linked(a))
        XCTAssertEqual(linked.style.shadow, soft)
        XCTAssertEqual(linked.shadowSource, .linked(a))
        XCTAssertNil(linked.style.shadowEnabled, "A linked shadow is always enabled")
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: card, tokens: [], reusableStyles: index), linked.style)

        card.properties = card.properties.map { property in
            guard property.key.rawValue == CanonicalReusableStyleIndex.appliedKey else { return property }
            return NodeProperty(id: property.id, key: property.key, value: .string("\(b.description),\(a.description)"),
                                origin: property.origin)
        }
        XCTAssertEqual(try resolve(card).style.border, thin)
        XCTAssertEqual(try resolve(card).borderSource, .linked(a))

        // Local values win group by group, including an authored zero radius
        // and a zero-width border; local tokens and a disabled local shadow apply.
        let token = LocalColorToken(name: "Brand", color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF8800FF")))
        var local = card
        local.properties += localBoxProperties(border: CanonicalBorder(color: thin.color, width: 0, style: .solid),
                                               radius: 0, shadow: soft, shadowEnabled: false)
        local.properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .border)), value: .string(token.id.description)))
        let overridden = try resolve(local, tokens: [token])
        XCTAssertEqual(overridden.borderSource, .local)
        XCTAssertEqual(overridden.style.border?.width, 0)
        XCTAssertEqual(overridden.style.border?.color, token.color)
        XCTAssertEqual(overridden.cornerRadiusSource, .local)
        XCTAssertEqual(overridden.style.cornerRadius, 0)
        XCTAssertEqual(overridden.shadowSource, .local)
        XCTAssertEqual(overridden.style.shadowEnabled, false)

        // No applied styles, or no index: nothing linked is resolved.
        var unlinked = card
        unlinked.properties.removeAll { $0.key.rawValue == CanonicalReusableStyleIndex.appliedKey }
        let none = try resolve(unlinked)
        XCTAssertEqual([none.borderSource, none.cornerRadiusSource, none.shadowSource], [.unset, .unset, .unset])
        XCTAssertNil(none.style.border)
        XCTAssertEqual(CanonicalLinkedBoxStyleResolver.resolve(node: card, tokens: [], index: nil)?.style,
                       LocalColorTokenResolver.resolvedBoxStyle(for: card, tokens: []))
        XCTAssertNil(CanonicalLinkedBoxStyleResolver.resolve(node: card, tokens: [], index: nil)?.style.border)

        // Box appearance applies only to box kinds.
        let text = DocumentNode(kind: .text, name: "Label", parent: .node(rootID), properties: [
            .init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(a.description))])
        XCTAssertNil(CanonicalLinkedBoxStyleResolver.resolve(node: text, tokens: [], index: index))
    }

    // SF-0510-002/004/005: a style's linked border, corners and shadow are set,
    // replaced and removed as one exact, undoable transaction; colors store as
    // RGBA8; every linked object picks the change up; diagnostics are value-free.
    func testSetReusableStyleBoxReplacesLinkedValuesInOneUndoableTransaction() throws {
        var fixture = makeFixture()
        let styleID = ReusableStyleID()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        fixture.document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Card",
            box: .init(), fill: red.hexadecimalRGBA)
        for index in [1, 2] {
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)))
        }
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        func set(_ box: CanonicalReusableBoxAppearance, id: ReusableStyleID? = nil, cancelled: Bool = false) throws -> DocumentCommand {
            try preparedReusableEdit(.setReusableStyleBox(id: id ?? styleID, box: box), session: session,
                                     fixture: fixture, cancelled: cancelled).documentCommand
        }
        func resolved(_ nodeIndex: Int) throws -> CanonicalBoxStyleResolution {
            try XCTUnwrap(CanonicalLinkedBoxStyleResolver.resolve(node: session.document.pages[0].nodes[nodeIndex],
                tokens: [], index: CanonicalReusableStyleIndex(document: session.document)))
        }
        func storedBox() throws -> CanonicalReusableBoxAppearance {
            try XCTUnwrap(CanonicalReusableStyleIndex(document: session.document).byID[styleID]?.box)
        }

        let offGrid = CanonicalBorder(color: CanonicalSolidColor(red: 0.1234, green: 0.5, blue: 0.75, alpha: 1),
                                      width: 2, style: .dashed)
        let shadow = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00000040")),
                                     offsetX: 0, offsetY: 4, blur: 10, spread: 0)
        let first = CanonicalReusableBoxAppearance(border: offGrid, cornerRadius: 8, shadow: shadow)
        try session.execute(set(first))
        XCTAssertEqual(try storedBox(), first.quantized, "Colors are stored as RGBA8, like linked fills")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        for nodeIndex in [1, 2] {
            XCTAssertEqual(try resolved(nodeIndex).style.border, first.quantized.border)
            XCTAssertEqual(try resolved(nodeIndex).borderSource, .linked(styleID))
            XCTAssertEqual(try resolved(nodeIndex).style.cornerRadius, 8)
        }
        let afterFirst = session.document.pages
        XCTAssertThrowsError(try set(first)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .noChanges, "An off-grid source equal once stored is no change")
        }

        // Replace: keep the radius, drop border and shadow; name and fill untouched.
        try session.execute(set(.init(cornerRadius: 12)))
        XCTAssertEqual(try storedBox(), .init(cornerRadius: 12))
        XCTAssertNil(try resolved(1).style.border)
        XCTAssertEqual(try resolved(1).borderSource, .unset)
        let definition = try XCTUnwrap(CanonicalReusableStyleIndex(document: session.document).byID[styleID])
        XCTAssertEqual(definition.name, "Card")
        XCTAssertEqual(definition.fill, red)
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        XCTAssertFalse(session.document.pages[0].nodes[0].properties.contains {
            $0.key.rawValue.hasPrefix(prefix + "border") || $0.key.rawValue.hasPrefix(prefix + "shadow")
        }, "Removed groups leave no partial fields")
        try session.undo()
        XCTAssertEqual(session.document.pages, afterFirst)
        try session.redo()
        XCTAssertEqual(try storedBox(), .init(cornerRadius: 12))

        // Removing every box value is allowed while the fill remains.
        try session.execute(set(.init()))
        XCTAssertEqual(try storedBox(), .init())
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(session.document.pages[0].nodes[1]), [styleID],
                       "Objects stay linked")
        try session.undo()

        // Rejections leave the document unchanged.
        let before = session.document
        let invalid = CanonicalReusableBoxAppearance(cornerRadius: -1)
        XCTAssertThrowsError(try set(invalid)) { XCTAssertEqual($0 as? AdvancedStyleCommandError, .invalidValue) }
        XCTAssertThrowsError(try set(.init(border: .init(color: red, width: 101, style: .solid)))) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .invalidValue)
        }
        XCTAssertThrowsError(try set(first, id: ReusableStyleID())) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .unavailable("The reusable style no longer exists."))
        }
        XCTAssertThrowsError(try set(first, cancelled: true)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .cancelled)
        }
        let stale = AdvancedStyleCommand(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision + 1, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .setReusableStyleBox(id: styleID, box: first), provenance: .keyboard,
            cancelled: false)
        XCTAssertThrowsError(try AdvancedStyleCommandRegistry().prepare(stale, in: session.document,
            context: fixture.with(document: session.document).context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .stale)
        }
        XCTAssertEqual(session.document, before)

        // A box-only style cannot drop its last value.
        let boxOnly = ReusableStyleID()
        var boxOnlyDocument = session.document
        boxOnlyDocument.pages[0].nodes[0].properties += linkedBoxStyleProperties(boxOnly, name: "Corners",
            box: .init(cornerRadius: 4))
        try boxOnlyDocument.validate()
        let boxOnlySession = DocumentSession(document: boxOnlyDocument)
        XCTAssertThrowsError(try preparedReusableEdit(.setReusableStyleBox(id: boxOnly, box: .init()),
            session: boxOnlySession, fixture: fixture)) {
            guard case .unavailable(let reason)? = $0 as? AdvancedStyleCommandError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("at least one value"))
        }
        XCTAssertEqual(boxOnlySession.document, boxOnlyDocument)

        // Diagnostics name the operation only, never the values.
        func diagnostic(_ box: CanonicalReusableBoxAppearance) -> AdvancedStyleDiagnosticRecord {
            let command = AdvancedStyleCommand(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: .setReusableStyleBox(id: styleID, box: box), provenance: .keyboard,
                cancelled: false)
            return AdvancedStyleDiagnosticFactory.make(command: command, resultRevision: nil, result: .stale, failure: .stale)
        }
        XCTAssertEqual(diagnostic(first), diagnostic(.init(cornerRadius: 99)))
        XCTAssertEqual(diagnostic(first).operationType, "reusable.box.set")

        // Deleting the style (after unlinking) removes its box fields too.
        try session.execute(try preparedReusableEdit(.applyReusableStyles([]), session: session, fixture: fixture,
            ids: [fixture.nodeID, fixture.secondNodeID]).documentCommand)
        try session.execute(try preparedReusableEdit(.removeReusableStyle(styleID), session: session,
            fixture: fixture).documentCommand)
        XCTAssertFalse(session.document.pages[0].nodes[0].properties.contains { $0.key.rawValue.hasPrefix(prefix) })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0510-003/004/005: Use Linked Border / Corners / Shadow removes only
    // the objects' own value for that group, as one transaction with an exact
    // inverse. It is refused for the whole selection when any object has no
    // linked style supplying the group, or a token is bound to its own color.
    func testUseLinkedBoxHandsEachGroupBackToLinkedStylesAtomically() throws {
        var fixture = makeFixture()
        let styleID = ReusableStyleID()
        let linkedBorder = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                           width: 2, style: .solid)
        let linkedShadow = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00000040")),
                                           offsetX: 0, offsetY: 4, blur: 10, spread: 0)
        fixture.document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Card",
            box: .init(border: linkedBorder, cornerRadius: 8, shadow: linkedShadow))
        let localBorder = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF")),
                                          width: 5, style: .dotted)
        let localShadow = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF000080")),
                                          offsetX: 2, offsetY: 2, blur: 0, spread: 1)
        for index in [1, 2] {
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)))
        }
        fixture.document.pages[0].nodes[1].properties += localBoxProperties(border: localBorder, radius: 0,
            shadow: localShadow, shadowEnabled: false)
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        let both = [fixture.nodeID, fixture.secondNodeID]
        func useLinked(_ property: ReusableBoxProperty, ids: [NodeID]) throws -> PreparedDesignInspectorEdit {
            try preparedReusableEdit(.useLinkedBox(property), session: session, fixture: fixture, ids: ids)
        }
        func resolved(_ nodeIndex: Int) throws -> CanonicalBoxStyleResolution {
            try XCTUnwrap(CanonicalLinkedBoxStyleResolver.resolve(node: session.document.pages[0].nodes[nodeIndex],
                tokens: [], index: CanonicalReusableStyleIndex(document: session.document)))
        }
        XCTAssertEqual(try resolved(1).borderSource, .local)
        XCTAssertEqual(try resolved(1).style.cornerRadius, 0)

        let original = session.document.pages
        try session.execute(useLinked(.border, ids: both).documentCommand)
        XCTAssertEqual(try resolved(1).style.border, linkedBorder)
        XCTAssertEqual(try resolved(1).borderSource, .linked(styleID))
        XCTAssertEqual(try resolved(1).cornerRadiusSource, .local, "Other groups keep their own values")
        XCTAssertEqual(try resolved(1).shadowSource, .local)
        XCTAssertFalse(session.document.pages[0].nodes[1].properties.contains {
            $0.key.rawValue.hasPrefix(DesignBoxStyleCommandRegistry.namespace + "border.")
        })
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo()
        XCTAssertEqual(session.document.pages, original, "Undo restores the exact local border properties")
        try session.redo()

        try session.execute(useLinked(.cornerRadius, ids: both).documentCommand)
        XCTAssertEqual(try resolved(1).style.cornerRadius, 8)
        try session.execute(useLinked(.shadow, ids: both).documentCommand)
        XCTAssertEqual(try resolved(1).style.shadow, linkedShadow)
        XCTAssertNil(try resolved(1).style.shadowEnabled, "The local disabled flag goes with the local shadow")
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty(DesignBoxStyleCommandRegistry.namespace + "shadow.enabled"))
        XCTAssertThrowsError(try useLinked(.shadow, ids: both)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .noChanges)
        }
        let allLinked = session.document.pages
        try session.undo(); try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages, original)
        try session.redo(); try session.redo(); try session.redo()
        XCTAssertEqual(session.document.pages, allLinked)

        // Refused for the whole selection when one object has no linked supply.
        var mixedDocument = fixture.document
        mixedDocument.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == CanonicalReusableStyleIndex.appliedKey }
        try mixedDocument.validate()
        let mixedSession = DocumentSession(document: mixedDocument)
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedBox(.border), session: mixedSession,
            fixture: fixture, ids: both)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .unavailable("Link a reusable style with a border first."))
        }
        XCTAssertEqual(mixedSession.document, mixedDocument)

        // A token bound to the object's own border color is kept, not detached silently.
        let token = LocalColorToken(name: "Brand", color: localBorder.color)
        var tokenDocument = fixture.document
        tokenDocument.colorTokens = [token]
        tokenDocument.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .border)),
            value: .string(token.id.description)))
        try tokenDocument.validate()
        let tokenSession = DocumentSession(document: tokenDocument)
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedBox(.border), session: tokenSession, fixture: fixture)) {
            guard case .unavailable(let reason)? = $0 as? AdvancedStyleCommandError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("token binding is retained"))
        }
        XCTAssertEqual(tokenSession.document, tokenDocument)
        XCTAssertNoThrow(try preparedReusableEdit(.useLinkedBox(.cornerRadius), session: tokenSession, fixture: fixture),
                         "Groups without a bound token are unaffected")

        // Incompatible kinds are skipped and reported, not changed.
        var withText = fixture.document
        let text = DocumentNode(kind: .text, name: "Caption", parent: .node(fixture.rootID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(0)),
            .init(key: .init(rawValue: "layout.width"), value: .number(120)), .init(key: .init(rawValue: "layout.height"), value: .number(24))])
        withText.pages[0].nodes[0].childIDs.append(text.id)
        withText.pages[0].nodes.append(text)
        let textSession = DocumentSession(document: withText)
        let skipped = try preparedReusableEdit(.useLinkedBox(.border), session: textSession,
            fixture: fixture.with(document: withText), ids: [fixture.nodeID, text.id])
        XCTAssertEqual(skipped.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(skipped.skippedNodeIDs, [text.id])

        let command = AdvancedStyleCommand(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: both, edit: .useLinkedBox(.cornerRadius), provenance: .keyboard, cancelled: false)
        XCTAssertEqual(AdvancedStyleDiagnosticFactory.make(command: command, resultRevision: nil, result: .stale,
            failure: .stale).operationType, "reusable.inherit.corner-radius")
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0510-002/003: capture stores what the selection actually shows (own
    // value first, then linked styles), reports groups that differ instead of
    // guessing, ignores a disabled shadow and snapshots token colors.
    func testCaptureBoxSelectionStoresWhatTheSelectionShows() throws {
        var fixture = makeFixture()
        let styleID = ReusableStyleID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let shadowA = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00000040")),
                                      offsetX: 0, offsetY: 4, blur: 10, spread: 0)
        let shadowB = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00000040")),
                                      offsetX: 0, offsetY: 8, blur: 20, spread: 0)
        fixture.document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Outline", box: .init(border: border))
        for index in [1, 2] {
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)))
        }
        fixture.document.pages[0].nodes[1].properties += localBoxProperties(radius: 6, shadow: shadowA)
        fixture.document.pages[0].nodes[2].properties += localBoxProperties(radius: 6, shadow: shadowB)
        try fixture.document.validate()
        let nodes = Array(fixture.document.pages[0].nodes[1...2])

        let capture = try AdvancedStyleCommandRegistry.captureBoxSelection(nodes, in: fixture.document)
        XCTAssertEqual(capture.box, .init(border: border, cornerRadius: 6), "Linked border and shared local radius")
        XCTAssertEqual(capture.mixed, [.shadow])
        XCTAssertEqual(capture.applicableCount, 2)
        XCTAssertEqual(capture.skippedCount, 0)
        XCTAssertEqual(capture.tokenColorCount, 0)

        // A disabled shadow shows nothing, so it is not captured.
        var disabled = fixture.document
        disabled.pages[0].nodes[2].properties.removeAll { $0.key.rawValue.hasPrefix(DesignBoxStyleCommandRegistry.namespace + "shadow.") }
        disabled.pages[0].nodes[2].properties += localBoxProperties(shadow: shadowA, shadowEnabled: false)
        try disabled.validate()
        let disabledCapture = try AdvancedStyleCommandRegistry.captureBoxSelection(
            Array(disabled.pages[0].nodes[1...2]), in: disabled)
        XCTAssertEqual(disabledCapture.mixed, [.shadow], "Shown shadow vs. hidden shadow differ")
        let onlyHidden = try AdvancedStyleCommandRegistry.captureBoxSelection([disabled.pages[0].nodes[2]], in: disabled)
        XCTAssertNil(onlyHidden.box.shadow)

        // Token colors are captured as plain values and counted.
        let token = LocalColorToken(name: "Brand", color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF8800FF")))
        var tokenDocument = fixture.document
        tokenDocument.colorTokens = [token]
        tokenDocument.pages[0].nodes[1].properties += localBoxProperties(
            border: .init(color: border.color, width: 3, style: .solid))
        tokenDocument.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .border)),
            value: .string(token.id.description)))
        try tokenDocument.validate()
        let tokenCapture = try AdvancedStyleCommandRegistry.captureBoxSelection([tokenDocument.pages[0].nodes[1]], in: tokenDocument)
        XCTAssertEqual(tokenCapture.box.border, .init(color: token.color, width: 3, style: .solid))
        XCTAssertEqual(tokenCapture.tokenColorCount, 1)

        // Skipped kinds, nothing applicable, and nothing to store.
        let text = DocumentNode(kind: .text, name: "Caption", parent: .node(fixture.rootID))
        XCTAssertEqual(try AdvancedStyleCommandRegistry.captureBoxSelection(nodes + [text], in: fixture.document).skippedCount, 1)
        XCTAssertThrowsError(try AdvancedStyleCommandRegistry.captureBoxSelection([text], in: fixture.document)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .noSelection)
        }
        let plain = ProjectCreation.blank()
        XCTAssertThrowsError(try AdvancedStyleCommandRegistry.captureBoxSelection([plain.pages[0].nodes[0]], in: plain)) {
            guard case .unavailable(let reason)? = $0 as? AdvancedStyleCommandError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("no border, corner radius or shadow"))
        }

        // Storing the capture in a new style reproduces it on a plain object.
        let session = DocumentSession(document: fixture.document)
        let copyID = ReusableStyleID()
        let undoCount = session.historySnapshot().undoEntries.count
        try session.execute(try preparedReusableEdit(.createReusableStyle(id: copyID, name: "Captured",
            fill: nil, opacity: nil, box: capture.box), session: session, fixture: fixture).documentCommand)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, undoCount + 1,
                       "A box-only style is created from the capture in one step")
        var probe = DocumentNode(kind: .frame, name: "Probe", parent: .node(fixture.rootID))
        probe.properties.append(.init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(copyID.description)))
        let reproduced = try XCTUnwrap(CanonicalLinkedBoxStyleResolver.resolve(node: probe, tokens: [],
            index: CanonicalReusableStyleIndex(document: session.document)))
        XCTAssertEqual(reproduced.style.border, border)
        XCTAssertEqual(reproduced.style.cornerRadius, 6)
    }

    // SF-0510-002/004/005: Create and Update carry
    // border, corners and shadow in the same transaction as name, fill and
    // opacity, so a box-only style can be created and Update from Selection is
    // one undo step. Update without box values keeps the style's existing ones.
    func testCreateAndUpdateReusableStyleCarryBoxValuesInOneTransaction() throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        func definition(_ id: ReusableStyleID) throws -> CanonicalReusableStyleDefinition {
            try XCTUnwrap(CanonicalReusableStyleIndex(document: session.document).byID[id])
        }
        func run(_ edit: AdvancedStyleEdit) throws {
            try session.execute(try preparedReusableEdit(edit, session: session, fixture: fixture).documentCommand)
        }

        let boxOnly = ReusableStyleID()
        try run(.createReusableStyle(id: boxOnly, name: "Outline", fill: nil, opacity: nil,
                                     box: .init(border: border, cornerRadius: 6)))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try definition(boxOnly).box, .init(border: border, cornerRadius: 6))
        XCTAssertNil(try definition(boxOnly).fill)

        let card = ReusableStyleID()
        try run(.createReusableStyle(id: card, name: "Card", fill: red, opacity: 0.9, box: .init(cornerRadius: 12)))
        XCTAssertEqual(try definition(card).fill, red)
        XCTAssertEqual(try definition(card).opacity, 0.9)
        XCTAssertEqual(try definition(card).box, .init(cornerRadius: 12))
        let afterCreate = session.document.pages

        // Update with new box values: one transaction replacing fill and box.
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#0000FFFF"))
        try run(.updateReusableStyle(id: card, name: "Card", fill: blue, opacity: 0.9, box: .init(border: border)))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 3)
        XCTAssertEqual(try definition(card).fill, blue)
        XCTAssertEqual(try definition(card).box, .init(border: border), "The radius is replaced, not merged")
        try session.undo()
        XCTAssertEqual(session.document.pages, afterCreate, "One undo restores fill and box together")
        try session.redo()

        // Update without box values keeps them; a same-value update is no change.
        try run(.updateReusableStyle(id: card, name: "Card Renamed", fill: blue, opacity: 0.9))
        XCTAssertEqual(try definition(card).box, .init(border: border))
        for unchanged in [AdvancedStyleEdit.updateReusableStyle(id: card, name: "Card Renamed", fill: blue, opacity: 0.9),
                          .updateReusableStyle(id: card, name: "Card Renamed", fill: blue, opacity: 0.9, box: .init(border: border))] {
            XCTAssertThrowsError(try preparedReusableEdit(unchanged, session: session, fixture: fixture)) {
                XCTAssertEqual($0 as? AdvancedStyleCommandError, .noChanges)
            }
        }

        // Clearing the box is allowed while a fill remains; never for a style
        // that would be left with nothing.
        try run(.updateReusableStyle(id: card, name: "Card Renamed", fill: blue, opacity: 0.9, box: .init()))
        XCTAssertTrue(try definition(card).box.isEmpty)
        let before = session.document
        let refused: [AdvancedStyleEdit] = [
            .updateReusableStyle(id: boxOnly, name: "Outline", fill: nil, opacity: nil, box: .init()),
            .createReusableStyle(id: ReusableStyleID(), name: "Nothing", fill: nil, opacity: nil, box: .init()),
            .createReusableStyle(id: ReusableStyleID(), name: "Bad radius", fill: nil, opacity: nil, box: .init(cornerRadius: -4)),
            .updateReusableStyle(id: boxOnly, name: "Outline", fill: nil, opacity: nil,
                                 box: .init(shadow: .init(color: red, offsetX: 0, offsetY: 0, blur: -1, spread: 0))),
        ]
        for edit in refused {
            XCTAssertThrowsError(try preparedReusableEdit(edit, session: session, fixture: fixture)) {
                XCTAssertEqual($0 as? AdvancedStyleCommandError, .invalidValue)
            }
        }
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0510-007: linked border/corners/shadow resolve for every object, and
    // one style edit propagates as one transaction, within bounds on the
    // standard (100), large (10,000) and stress (20,000-node) fixtures. The
    // index is built once per resolution pass, in one pass over properties.
    func testLinkedBoxStylesStayResponsiveOnStandardLargeAndStressFixtures() throws {
        let clock = ContinuousClock()
        let styleID = ReusableStyleID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let box = CanonicalReusableBoxAppearance(border: border, cornerRadius: 8)
        let scene = CanvasViewportSceneID()
        for scale in [WorkspaceFixtureScale.standard, .large, .stress] {
            var document = scale.document()
            document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Card", box: box)
            for pageIndex in document.pages.indices {
                for nodeIndex in document.pages[pageIndex].nodes.indices {
                    document.pages[pageIndex].nodes[nodeIndex].properties.append(.init(
                        key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)))
                }
            }
            try document.validate()
            let nodes = document.pages.flatMap(\.nodes)
            XCTAssertEqual(nodes.count, scale == .stress ? InsertionPolicy.maximumNodeCount : scale.pageCount)

            var index: CanonicalReusableStyleIndex?
            let build = try clock.measure { index = try CanonicalReusableStyleIndex(document: document) }
            var linkedCount = 0
            let resolution = clock.measure {
                for node in nodes where CanonicalLinkedBoxStyleResolver.resolve(node: node, tokens: [],
                    index: index)?.borderSource == .linked(styleID) { linkedCount += 1 }
            }
            XCTAssertEqual(linkedCount, nodes.count, "Every linked object resolves the style's border")

            let session = DocumentSession(document: document)
            let page = document.pages[0], root = page.nodes[0]
            let command = AdvancedStyleCommand(identity: .init(documentID: document.id, pageID: page.id,
                revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
                orderedNodeIDs: [root.id], edit: .setReusableStyleBox(id: styleID, box: .init(cornerRadius: 12)),
                provenance: .keyboard, cancelled: false)
            let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
                rendererGeneration: document.revision, selectedNodeIDs: [root.id], availableNodeIDs: [root.id],
                isLifecycleAvailable: true, lifecycleDisabledReason: nil)
            let update = try clock.measure {
                let prepared = try AdvancedStyleCommandRegistry().prepare(command, in: session.document, context: context)
                try session.execute(prepared.documentCommand)
                try session.undo()
                try session.redo()
            }
            XCTAssertEqual(session.historySnapshot().undoEntries.count, 1, "One style edit is one transaction for every linked object")
            XCTAssertEqual(try CanonicalReusableStyleIndex(document: session.document).byID[styleID]?.box, .init(cornerRadius: 12))

            // Safety bounds only; named-hardware timings belong in retained evidence.
            let (indexBound, resolveBound, updateBound): (Duration, Duration, Duration) = switch scale {
            case .standard: (.seconds(1), .seconds(1), .seconds(2))
            case .large: (.seconds(5), .seconds(5), .seconds(20))
            case .stress: (.seconds(10), .seconds(10), .seconds(40))
            }
            XCTAssertLessThan(build, indexBound, "\(scale)")
            XCTAssertLessThan(resolution, resolveBound, "\(scale)")
            XCTAssertLessThan(update, updateBound, "\(scale)")
        }
    }

    // SF-0510-007 (index cost): many styles on one owner still build an
    // identical index, so grouping definition fields cannot change results.
    func testReusableStyleIndexGroupsManyDefinitionsOnOneOwnerIdentically() throws {
        var document = CanonicalDocument()
        let ids = (0..<300).map { _ in ReusableStyleID() }
        for (offset, id) in ids.enumerated() {
            let box: CanonicalReusableBoxAppearance = offset.isMultiple(of: 3)
                ? .init(cornerRadius: Double(offset % 50)) : .init()
            document.pages[0].nodes[0].properties += linkedBoxStyleProperties(id, name: "Style \(offset)", box: box,
                fill: offset.isMultiple(of: 3) ? nil : "#102030FF")
        }
        try document.validate()
        let clock = ContinuousClock()
        var index: CanonicalReusableStyleIndex?
        let elapsed = try clock.measure { index = try CanonicalReusableStyleIndex(document: document) }
        let built = try XCTUnwrap(index)
        XCTAssertEqual(built.orderedDefinitions.map(\.id), ids, "Definition order is the stored order")
        for (offset, id) in ids.enumerated() {
            let definition = try XCTUnwrap(built.byID[id])
            XCTAssertEqual(definition.name, "Style \(offset)")
            if offset.isMultiple(of: 3) {
                XCTAssertEqual(definition.box, .init(cornerRadius: Double(offset % 50)))
                XCTAssertNil(definition.fill)
            } else {
                XCTAssertTrue(definition.box.isEmpty)
                XCTAssertEqual(definition.fill?.hexadecimalRGBA, "#102030FF")
            }
        }
        XCTAssertLessThan(elapsed, .seconds(1), "Safety bound only")
    }

    // SF-0510-003/004/006: the Design Inspector shows
    // what the canvas draws, names the rule that supplies each border, corner
    // and shadow value, enables "Use Linked …" only when it would succeed, and
    // never offers Remove for a value that only a linked style supplies.
    func testInspectorReportsLinkedBoxSourcesAndGuardsLinkedOnlyRemoval() async throws {
        var fixture = makeFixture()
        let styleID = ReusableStyleID()
        let linkedBorder = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                           width: 2, style: .solid)
        let localBorder = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF")),
                                          width: 5, style: .dotted)
        fixture.document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Card",
            box: .init(border: linkedBorder, cornerRadius: 8))
        for index in [1, 2] {
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)))
        }
        fixture.document.pages[0].nodes[2].properties += localBoxProperties(border: localBorder)
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func adopt() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while (state.canvasRenderPlan?.identity.revision != session.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation),
                  ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, session.document.revision)
        }
        func shownStyle() -> CanonicalBoxStyle? {
            if case .single(let style, _) = state.designInspectorBoxStyleValue() { return style }
            return nil
        }
        await adopt()

        // Linked-only object: Inspector value equals the canvas; sources name the style.
        state.selectLayer(fixture.nodeID)
        XCTAssertEqual(shownStyle()?.border, linkedBorder)
        XCTAssertEqual(shownStyle()?.cornerRadius, 8)
        let drawn = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == fixture.nodeID })
        XCTAssertEqual(drawn.border?.width, shownStyle()?.border?.width)
        XCTAssertEqual(drawn.cornerRadius, shownStyle()?.cornerRadius)
        XCTAssertEqual(state.reusableBoxSource(.border), "Base linked border: Card")
        XCTAssertEqual(state.reusableBoxSource(.cornerRadius), "Base linked corner radius: Card")
        XCTAssertEqual(state.reusableBoxSource(.shadow), "Default / omitted shadow")
        XCTAssertTrue(state.selectionBoxGroupIsLinked(.border))
        XCTAssertTrue(state.selectionBoxGroupIsLinked(.cornerRadius))
        XCTAssertFalse(state.selectionBoxGroupIsLinked(.shadow), "Nothing supplies a shadow")
        XCTAssertFalse(state.linkedBoxAvailability(.border).isEnabled)
        XCTAssertEqual(state.linkedBoxAvailability(.border).disabledReason, "No local border override remains to reset.")
        XCTAssertFalse(state.linkedBoxAvailability(.shadow).isEnabled)

        // Overriding object: own border wins; Use Linked Border is available.
        state.selectLayer(fixture.secondNodeID)
        XCTAssertEqual(shownStyle()?.border, localBorder)
        XCTAssertEqual(shownStyle()?.cornerRadius, 8, "Other groups still come from the style")
        XCTAssertEqual(state.reusableBoxSource(.border), "Base local border")
        XCTAssertFalse(state.selectionBoxGroupIsLinked(.border))
        XCTAssertTrue(state.linkedBoxAvailability(.border).isEnabled)

        // Mixed selection: sources say so.
        state.selectLayer(fixture.nodeID, modifier: .add)
        XCTAssertEqual(state.reusableBoxSource(.border), "Mixed border sources")
        XCTAssertEqual(state.reusableBoxSource(.cornerRadius), "Base linked corner radius: Card")
        XCTAssertFalse(state.selectionBoxGroupIsLinked(.border), "Remove stays available while an own border exists")
        if case .mixed = state.designInspectorBoxStyleValue() {} else { XCTFail("Different borders are mixed") }

        // Use Linked Border through the shell: one transaction, canvas follows.
        state.selectLayer(fixture.secondNodeID)
        let before = session.historySnapshot().undoEntries.count
        XCTAssertTrue(state.commitAdvancedStyle(.useLinkedBox(.border), operation: "Use Linked Border",
                                                expectedContext: state.responsiveInspectorEditContext))
        await adopt()
        XCTAssertEqual(session.historySnapshot().undoEntries.count, before + 1)
        XCTAssertEqual(state.reusableBoxSource(.border), "Base linked border: Card")
        XCTAssertEqual(state.canvasRenderPlan?.authoredObjects.first { $0.id == fixture.secondNodeID }?.border?.width, 2)
        try session.undo()
        await adopt()
        XCTAssertEqual(state.reusableBoxSource(.border), "Base local border")

        // Capture and Create Box Style from the selection.
        let capture = try XCTUnwrap(try? state.reusableBoxCapture.get())
        XCTAssertEqual(capture.box, .init(border: localBorder, cornerRadius: 8))
        let created = ReusableStyleID()
        XCTAssertTrue(state.commitAdvancedStyle(.createReusableStyle(id: created, name: "Dotted", fill: nil, opacity: nil,
            box: capture.box), operation: "Reusable box style creation", expectedContext: state.responsiveInspectorEditContext))
        let definition = try XCTUnwrap(state.reusableStyleDefinitions.first { $0.id == created })
        XCTAssertEqual(definition.box, capture.box)
        XCTAssertEqual(ReusableStyleSummary.definition(definition), "5 pt dotted border #FF0000FF · 8 pt corners")
        XCTAssertNotNil(state.currentReusableStyleIndex()?.byID[created], "The cached index follows the new document value")
        try session.undo()
        XCTAssertNil(state.currentReusableStyleIndex()?.byID[created], "Undo also refreshes the cached index")
        XCTAssertEqual(ReusableStyleSummary.box(.init()), "no border, corners or shadow")
        XCTAssertEqual(WorkspaceShellState.boxPropertyTitle(.cornerRadius), "corner radius")
    }

    // SF-0510-007: passing a prebuilt style index to the
    // registry and to capture gives exactly the same result as building it
    // there, and an invalid document still fails the same way.
    func testPrebuiltStyleIndexGivesIdenticalRegistryAndCaptureResults() throws {
        var fixture = makeFixture()
        let styleID = ReusableStyleID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        fixture.document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Card",
            box: .init(border: border, cornerRadius: 8))
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)))
        fixture.document.pages[0].nodes[1].properties += localBoxProperties(radius: 2)
        try fixture.document.validate()
        let document = fixture.document
        let index = try CanonicalReusableStyleIndex(document: document)
        let registry = AdvancedStyleCommandRegistry()
        for edit in [AdvancedStyleEdit.useLinkedBox(.cornerRadius), .setReusableStyleBox(id: styleID, box: .init(cornerRadius: 4)),
                     .useLinkedBox(.shadow)] {
            let command = AdvancedStyleCommand(identity: .init(documentID: document.id, pageID: fixture.pageID,
                revision: document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: edit, provenance: .keyboard, cancelled: false)
            let context = fixture.context(selectedIDs: [fixture.nodeID])
            let built = Result { try registry.prepare(command, in: document, context: context) }
            let cached = Result { try registry.prepare(command, in: document, context: context, styleIndex: index) }
            switch (built, cached) {
            case (.success(let a), .success(let b)):
                XCTAssertEqual(a.documentCommand, b.documentCommand)
                XCTAssertEqual(a.applicableNodeIDs, b.applicableNodeIDs)
            case (.failure(let a), .failure(let b)):
                XCTAssertEqual(a as? AdvancedStyleCommandError, b as? AdvancedStyleCommandError)
            default:
                XCTFail("Prebuilt and built indexes disagree for \(edit)")
            }
        }
        let nodes = [document.pages[0].nodes[1]]
        XCTAssertEqual(try AdvancedStyleCommandRegistry.captureBoxSelection(nodes, in: document),
                       try AdvancedStyleCommandRegistry.captureBoxSelection(nodes, in: document, styleIndex: index))

        // No prebuilt index for an invalid document: the registry still rejects it.
        var invalid = document
        invalid.pages[0].nodes[0].properties.append(.init(key: .init(rawValue:
            CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description).borderGlow"), value: .number(1)))
        XCTAssertThrowsError(try CanonicalReusableStyleIndex(document: invalid))
        XCTAssertThrowsError(try AdvancedStyleCommandRegistry.captureBoxSelection([invalid.pages[0].nodes[1]], in: invalid,
                                                                                  styleIndex: nil))
    }

    private func linkedBoxStyleProperties(_ id: ReusableStyleID, name: String, box: CanonicalReusableBoxAppearance,
                                          fill: String? = nil) -> [NodeProperty] {
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(id.description)."
        var result = [NodeProperty(key: .init(rawValue: prefix + "name"), value: .string(name), origin: .authored)]
        if let fill { result.append(.init(key: .init(rawValue: prefix + "fill"), value: .string(fill), origin: .authored)) }
        result += box.fieldValues.map { NodeProperty(key: .init(rawValue: prefix + $0.field), value: $0.value, origin: .authored) }
        return result
    }

    private func localBoxProperties(border: CanonicalBorder? = nil, radius: Double? = nil,
                                    shadow: CanonicalShadow? = nil, shadowEnabled: Bool? = nil) -> [NodeProperty] {
        let ns = DesignBoxStyleCommandRegistry.namespace
        func color(_ prefix: String, _ value: CanonicalSolidColor) -> [NodeProperty] {
            [("red", value.red), ("green", value.green), ("blue", value.blue), ("alpha", value.alpha)].map {
                NodeProperty(key: .init(rawValue: ns + prefix + "." + $0.0), value: .number($0.1), origin: .authored)
            }
        }
        var result: [NodeProperty] = []
        if let border {
            result.append(.init(key: .init(rawValue: ns + "border.width"), value: .number(border.width), origin: .authored))
            result.append(.init(key: .init(rawValue: ns + "border.style"), value: .string(border.style.rawValue), origin: .authored))
            result += color("border.color", border.color)
        }
        if let radius { result.append(.init(key: .init(rawValue: ns + "radius.uniform"), value: .number(radius), origin: .authored)) }
        if let shadow {
            result += [("shadow.offsetX", shadow.offsetX), ("shadow.offsetY", shadow.offsetY),
                       ("shadow.blur", shadow.blur), ("shadow.spread", shadow.spread)].map {
                NodeProperty(key: .init(rawValue: ns + $0.0), value: .number($0.1), origin: .authored)
            }
            result += color("shadow.color", shadow.color)
        }
        if let shadowEnabled {
            result.append(.init(key: .init(rawValue: ns + "shadow.enabled"), value: .boolean(shadowEnabled), origin: .authored))
        }
        return result
    }

    // SF-0510-002/004: updating a style that supplies
    // only border, corners or shadow keeps those values and no longer needs a
    // fill or opacity. A new style, or one with nothing else, still needs one.
    func testUpdatingABoxOnlyReusableStyleKeepsItsLinkedBoxValues() throws {
        var fixture = makeFixture()
        let styleID = ReusableStyleID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let box = CanonicalReusableBoxAppearance(border: border, cornerRadius: 8)
        fixture.document.pages[0].nodes[0].properties += linkedBoxStyleProperties(styleID, name: "Card", box: box)
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        func definition(_ id: ReusableStyleID) throws -> CanonicalReusableStyleDefinition {
            try XCTUnwrap(CanonicalReusableStyleIndex(document: session.document).byID[id])
        }
        func update(_ id: ReusableStyleID, name: String, fill: CanonicalSolidColor?) throws -> DocumentCommand {
            try preparedReusableEdit(.updateReusableStyle(id: id, name: name, fill: fill, opacity: nil),
                                     session: session, fixture: fixture).documentCommand
        }

        try session.execute(update(styleID, name: "Rounded card", fill: nil))
        XCTAssertEqual(try definition(styleID).name, "Rounded card")
        XCTAssertEqual(try definition(styleID).box, box)
        XCTAssertNil(try definition(styleID).fill)
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        try session.execute(update(styleID, name: "Rounded card", fill: red))
        XCTAssertEqual(try definition(styleID).fill, red)
        XCTAssertEqual(try definition(styleID).box, box)
        try session.execute(update(styleID, name: "Rounded card", fill: nil))
        XCTAssertNil(try definition(styleID).fill)
        XCTAssertEqual(try definition(styleID).box, box, "Removing the fill never removes linked box values")
        XCTAssertThrowsError(try update(styleID, name: "Rounded card", fill: nil)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .noChanges)
        }

        try session.undo()
        XCTAssertEqual(try definition(styleID).fill, red)
        try session.undo()
        XCTAssertNil(try definition(styleID).fill)
        XCTAssertEqual(try definition(styleID).name, "Rounded card")
        try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)

        XCTAssertThrowsError(try preparedReusableEdit(.createReusableStyle(id: ReusableStyleID(), name: "Empty",
            fill: nil, opacity: nil), session: session, fixture: fixture)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .invalidValue)
        }
        let fillOnly = ReusableStyleID()
        try session.execute(try preparedReusableEdit(.createReusableStyle(id: fillOnly, name: "Fill only",
            fill: red, opacity: nil), session: session, fixture: fixture).documentCommand)
        let beforeInvalid = session.document
        XCTAssertThrowsError(try update(fillOnly, name: "Fill only", fill: nil),
                             "A style with nothing else to supply still needs a fill or opacity") {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .invalidValue)
        }
        XCTAssertEqual(session.document, beforeInvalid)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0508-003/005, SF-0509-003/005, SF-0510-003/005: reset is
    // explicit inheritance, not None, token detach, or a baked equivalent fill.
    func testReusableResetProtectsNoneAndTokensAndRestoresGradientIdentities() throws {
        var fixture = makeFixture()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#0000FFFF"))
        let token = LocalColorToken(name: "Retained", color: blue)
        fixture.document.colorTokens = [token]
        let gradient = CanonicalFillLayer.linearGradient(angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: red), .init(id: GradientStopID(), position: 1, color: blue)])
        let layers = [gradient, CanonicalFillLayer.solid(color: blue)]
        for (key, value) in CanonicalFillLayerCodec.propertyValues(for: layers).sorted(by: { $0.key < $1.key }) {
            fixture.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: value))
        }
        let opacity = NodeProperty(key: .init(rawValue: "style.opacity"), value: .number(0.9))
        fixture.document.pages[0].nodes[1].properties.append(opacity)
        fixture.document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: CanonicalFillLayerCodec.orderKey), value: .string("")))
        let session = DocumentSession(document: fixture.document), styleID = ReusableStyleID()
        try session.execute(try preparedReusableEdit(.createReusableStyle(id: styleID, name: "Linked", fill: red, opacity: 0.4),
            session: session, fixture: fixture).documentCommand)
        try session.execute(try preparedReusableEdit(.linkReusableStyle(styleID), session: session, fixture: fixture,
            ids: [fixture.nodeID, fixture.secondNodeID]).documentCommand)
        let original = session.document
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedAppearance(.fill), session: session, fixture: fixture,
            ids: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(session.document, original, "A protected None member rejects the entire reset, not just the later object")
        try session.execute(try preparedReusableEdit(.useLinkedAppearance(.fill), session: session, fixture: fixture).documentCommand)
        XCTAssertNil(CanonicalFillLayerCodec.layers(for: session.document.pages[0].nodes[1]))
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty("style.opacity"), opacity)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: session.document.pages[0].nodes[1],
            index: CanonicalReusableStyleIndex(document: session.document)).fill, red)
        let resetFill = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, original.pages)
        XCTAssertEqual(CanonicalFillLayerCodec.layers(for: session.document.pages[0].nodes[1]), layers)
        try session.redo(); XCTAssertEqual(session.document.pages, resetFill)
        try session.execute(try preparedReusableEdit(.useLinkedAppearance(.opacity), session: session, fixture: fixture).documentCommand)
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty("style.opacity"))
        let current = session.document
        XCTAssertEqual(DesignInspectorCommandRegistry.opacityValue(nodes: [current.pages[0].nodes[1]],
            reusableStyles: try CanonicalReusableStyleIndex(document: current)), .single(0.4, .authored))
        let unchangedOpacity = DesignInspectorCommand(identity: .init(documentID: current.id, pageID: fixture.pageID,
            revision: current.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .opacity(0.4), provenance: .keyboard, cancelled: false)
        XCTAssertThrowsError(try DesignInspectorCommandRegistry().prepare(unchangedOpacity, in: current,
            context: fixture.with(document: current).context)) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
        try session.undo(); XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty("style.opacity"), opacity)
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedAppearance(.fill), session: session, fixture: fixture,
            ids: [fixture.secondNodeID]))
        try session.execute(try preparedReusableEdit(.updateReusableStyle(id: styleID, name: "Linked", fill: blue, opacity: 0.6),
            session: session, fixture: fixture).documentCommand)
        let index = try CanonicalReusableStyleIndex(document: session.document)
        XCTAssertNil(try CanonicalResolvedAppearance.resolve(node: session.document.pages[0].nodes[2], index: index).fill)
        XCTAssertEqual(CanonicalFillLayerCodec.layers(for: session.document.pages[0].nodes[2]), [])
        XCTAssertEqual(session.document.colorTokens, [token])
        var bound = original
        bound.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description)))
        try bound.validate()
        let boundSession = DocumentSession(document: bound)
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedAppearance(.fill), session: boundSession, fixture: fixture))
        XCTAssertEqual(boundSession.document, bound)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0510-002/003, SF-0509-003: snapshots are explicit solid/opacity
    // values, never accidental gradient flattening or source-token detachment.
    func testReusableCaptureRejectsMixedComplexAndNoneWithoutDetachingTokens() throws {
        var fixture = makeFixture()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#CC2233FF"))
        let token = LocalColorToken(name: "Source", color: red)
        fixture.document.colorTokens = [token]
        for index in 1...2 {
            for (key, value) in CanonicalFillLayerCodec.propertyValues(for: [.solid(color: red)]).sorted(by: { $0.key < $1.key }) {
                fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: key), value: value))
            }
            fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: "style.opacity"), value: .number(0.5)))
        }
        fixture.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description)))
        try fixture.document.validate()
        let before = fixture.document
        let capture = try AdvancedStyleCommandRegistry.captureSelection(Array(before.pages[0].nodes[1...2]), in: before)
        XCTAssertEqual(capture.fill, red); XCTAssertEqual(capture.opacity, 0.5); XCTAssertEqual(capture.boundFillCount, 1)
        var mixed = before
        let opacityIndex = try XCTUnwrap(mixed.pages[0].nodes[2].properties.firstIndex { $0.key.rawValue == "style.opacity" })
        mixed.pages[0].nodes[2].properties[opacityIndex].value = .number(0.6)
        XCTAssertThrowsError(try AdvancedStyleCommandRegistry.captureSelection(Array(mixed.pages[0].nodes[1...2]), in: mixed))
        for layers in [[CanonicalFillLayer](), [.linearGradient(angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: red), .init(id: GradientStopID(), position: 1, color: red)])]] {
            var unsupported = before
            unsupported.pages[0].nodes[1].properties.removeAll {
                $0.key.rawValue.hasPrefix("style.fill.layers.v1.") || $0.key.rawValue == LocalColorTokenBinding.key(for: .fill)
            }
            unsupported.pages[0].nodes[1].properties += CanonicalFillLayerCodec.propertyValues(for: layers).map {
                .init(key: .init(rawValue: $0.key), value: $0.value)
            }
            XCTAssertThrowsError(try AdvancedStyleCommandRegistry.captureSelection([unsupported.pages[0].nodes[1]], in: unsupported))
        }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0510-003/005/006, SF-0508-003, SF-0509-003: immutable native
    // adoption, effective Inspector and compiler agree without recoloring None
    // or breaking a different page's/token-bound local override.
    func testReusableLinksAdoptSharedAppearanceWithoutRevivingNoneOrTokenOverrides() async throws {
        var fixture = makeFixture()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#0000FFFF"))
        let orange = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF8800FF"))
        let green = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00FF00FF"))
        let token = LocalColorToken(name: "Local green", color: green)
        fixture.document.colorTokens = [token]
        fixture.document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: CanonicalFillLayerCodec.orderKey), value: .string("")))
        func frame(parent: NodeID, name: String) -> DocumentNode {
            .init(kind: .frame, name: name, parent: .node(parent), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(400)), .init(key: .init(rawValue: "layout.y"), value: .number(40)),
                .init(key: .init(rawValue: "layout.width"), value: .number(120)), .init(key: .init(rawValue: "layout.height"), value: .number(80))])
        }
        var tokenNode = frame(parent: fixture.rootID, name: "Token local")
        tokenNode.properties += CanonicalFillLayerCodec.propertyValues(for: [.solid(color: blue)]).map {
            .init(key: .init(rawValue: $0.key), value: $0.value)
        }
        tokenNode.properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)), value: .string(token.id.description)))
        fixture.document.pages[0].nodes[0].childIDs.append(tokenNode.id); fixture.document.pages[0].nodes.append(tokenNode)
        let setup = DocumentSession(document: fixture.document), a = ReusableStyleID(), b = ReusableStyleID()
        for (id, name, color, opacity) in [(a, "First", red, 0.4), (b, "Second", blue, 0.7)] {
            try setup.execute(try preparedReusableEdit(.createReusableStyle(id: id, name: name, fill: color, opacity: opacity),
                session: setup, fixture: fixture).documentCommand)
        }
        try setup.execute(try preparedReusableEdit(.applyReusableStyles([a, b]), session: setup, fixture: fixture).documentCommand)
        try setup.execute(try preparedReusableEdit(.linkReusableStyle(a), session: setup, fixture: fixture,
            ids: [fixture.secondNodeID, tokenNode.id]).documentCommand)
        var document = setup.document, peerPage = DocumentPage(name: "Peer style page")
        var peer = frame(parent: peerPage.rootNodeIDs[0], name: "Peer linked")
        peer.properties.append(.init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(a.description)))
        peerPage.nodes[0].childIDs.append(peer.id); peerPage.nodes.append(peer); document.pages.append(peerPage)
        try document.validate()
        let session = DocumentSession(document: document)
        let state = WorkspaceShellState(documentSession: session)
        let live = state.documentSession
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func adopt() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while (state.canvasRenderPlan?.identity.revision != live.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation), ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, live.document.revision)
        }
        await adopt(); state.selectLayer(fixture.nodeID)
        XCTAssertEqual(state.designInspectorFillValue(), .single(blue, .authored))
        XCTAssertEqual(state.designInspectorOpacityValue(), .single(0.7, .authored))
        let initialObject = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == fixture.nodeID })
        let opening = state.responsiveInspectorEditContext
        XCTAssertEqual(state.reusableStyleUsage[a]?.objects, 4)
        XCTAssertEqual(state.reusableStyleUsage[a]?.pages, 2)
        XCTAssertTrue(state.commitAdvancedStyle(.updateReusableStyle(id: a, name: "First", fill: orange, opacity: 0.6),
            operation: "confirmed shared update", expectedContext: opening))
        await adopt()
        XCTAssertEqual(state.designInspectorFillValue(), .single(blue, .authored), "Later linked values still win")
        let none = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == fixture.secondNodeID })
        XCTAssertEqual(none.fillRGBA, [0, 0, 0, 0])
        let bound = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == tokenNode.id })
        XCTAssertEqual(bound.fillLayers.first?.rgba, [green.red, green.green, green.blue, green.alpha])
        XCTAssertEqual(live.document.colorTokens, document.colorTokens)
        XCTAssertEqual(live.document.pages[0].nodes.first { $0.id == tokenNode.id }?.properties,
            document.pages[0].nodes.first { $0.id == tokenNode.id }?.properties)
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1000, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let peerScene = try await WorkspaceScenePreparationWorker().prepare(.init(document: live.document, activePageID: peerPage.id,
            activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(), breakpoint: .desktop, viewportWidth: 1440))
        XCTAssertEqual(peerScene.renderScene.objects.first { $0.id == peer.id }?.fillRGBA, [orange.red, orange.green, orange.blue, orange.alpha])
        XCTAssertEqual(peerScene.renderScene.objects.first { $0.id == peer.id }?.opacity, 0.6)
        XCTAssertTrue(state.commitAdvancedStyle(.moveReusableStyle(b, offset: -1), operation: "earlier link",
            expectedContext: state.responsiveInspectorEditContext))
        await adopt()
        XCTAssertEqual(state.designInspectorFillValue(), .single(orange, .authored))
        XCTAssertEqual(state.designInspectorOpacityValue(), .single(0.6, .authored))
        XCTAssertTrue(state.reusableAppearanceSource(.opacity).contains("First"))
        let count = live.historySnapshot().undoEntries.count
        XCTAssertTrue(state.commitDesignOpacity(percent: 60, provenance: .focusLoss))
        XCTAssertNil(live.document.pages[0].nodes[1].insertionProperty("style.opacity"))
        XCTAssertEqual(live.historySnapshot().undoEntries.count, count)
        let current = live.document
        XCTAssertFalse(state.commitDesignOpacity(percent: 70, provenance: .focusLoss, expectedContext: opening),
            "A queued field from the prior shared-style revision must not create a local opacity override")
        XCTAssertEqual(live.document, current)
        XCTAssertEqual(live.historySnapshot().undoEntries.count, count)
        XCTAssertFalse(state.commitAdvancedStyle(.unlinkReusableStyle(a), operation: "stale dialog", expectedContext: opening))
        XCTAssertEqual(live.document, current)
        XCTAssertEqual(initialObject.fillRGBA, [blue.red, blue.green, blue.blue, blue.alpha], "Earlier immutable snapshots do not mix with current style order")
        let plan = try MultiPageStaticBuildPlanner.plan(document: current)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let selectedRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: fixture.nodeID) + " {") }.joined()
        XCTAssertTrue(selectedRules.contains("background-color: rgba(255.0, 136.0, 0.0, 1.0)"))
        let noneRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: fixture.secondNodeID) + " {") }.joined()
        XCTAssertFalse(noneRules.contains("background-color: rgba("))
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: DocumentSerializer.decode(DocumentSerializer.encode(current))).files, plan.files)
    }

    func testAdvancedStyleRegistryHistoryPersistenceAndSafeStaticProjection() throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let styleID = ReusableStyleID(UUID(uuidString: "97000000-0000-4000-8000-000000000001")!)
        let stateID = UUID(uuidString: "97000000-0000-4000-8000-000000000002")!
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#CC1A33FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#1A33CCFF"))
        let registry = AdvancedStyleCommandRegistry()
        func node() -> DocumentNode { session.document.pages[0].nodes.first { $0.id == fixture.nodeID }! }
        func prepare(_ edit: AdvancedStyleEdit, cancelled: Bool = false) throws -> PreparedDesignInspectorEdit {
            let command = AdvancedStyleCommand(identity: .init(
                documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: edit,
                provenance: .automation, cancelled: cancelled)
            return try registry.prepare(command, in: session.document,
                context: fixture.context(selectedIDs: [fixture.nodeID]))
        }

        try session.execute(try prepare(.createReusableStyle(
            id: styleID, name: "Card", fill: red, opacity: 0.75)).documentCommand)
        try session.execute(try prepare(.applyReusableStyles([styleID])).documentCommand)
        let appliedID = try XCTUnwrap(node().insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id)
        try session.execute(try prepare(.positionMode(.absolute)).documentCommand)
        try session.execute(try prepare(.positionInset(.top, 24)).documentCommand)
        try session.execute(try prepare(.zIndex(7)).documentCommand)
        try session.execute(try prepare(.setState(
            state: .hover, id: stateID, fill: blue, opacity: 0.5)).documentCommand)

        let index = try CanonicalReusableStyleIndex(document: session.document)
        XCTAssertEqual(index.byID[styleID]?.name, "Card")
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: node(), index: index).fill, red)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: node(), index: index, state: .hover).fill, blue)
        XCTAssertEqual(CanonicalPositioning.resolve(node())?.top, 24)
        XCTAssertEqual(CanonicalPositioning.resolve(node())?.zIndex, 7)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let css = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document)
            .files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("position: absolute"), css)
        XCTAssertTrue(css.contains("top: 24.0px"), css)
        XCTAssertTrue(css.contains("z-index: 7"), css)
        XCTAssertTrue(css.contains(":hover"), css)
        XCTAssertTrue(css.contains("background-color: rgba(26.0, 51.0, 204.0, 1.0)"), css)
        XCTAssertFalse(css.contains("Card"), css)

        try session.undo()
        XCTAssertNil(node().insertionProperty(CanonicalReusableStyleIndex.stateNamespace + "hover.id"))
        try session.redo()
        XCTAssertEqual(node().insertionStringProperty(CanonicalReusableStyleIndex.stateNamespace + "hover.id"),
                       stateID.uuidString.lowercased())
        XCTAssertEqual(node().insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id, appliedID)
        XCTAssertThrowsError(try prepare(.positionInset(.left, .infinity)))
        XCTAssertThrowsError(try prepare(.applyReusableStyles([styleID]), cancelled: true))
    }

    func testAdvancedStyleMixedSelectionStaleValidationAndRedactedDiagnostics() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[2].kind = .text
        let styleID = ReusableStyleID(UUID(uuidString: "97000000-0000-4000-8000-000000000003")!)
        let session = DocumentSession(document: fixture.document)
        let registry = AdvancedStyleCommandRegistry()
        func command(_ edit: AdvancedStyleEdit, revision: UInt64? = nil) -> AdvancedStyleCommand {
            .init(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: revision ?? session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID, fixture.secondNodeID], edit: edit,
                provenance: .automation, cancelled: false)
        }
        let create = AdvancedStyleCommand(identity: command(.zIndex(0)).identity,
            orderedNodeIDs: [fixture.nodeID], edit: .createReusableStyle(
                id: styleID, name: "Surface", fill: .legacySurface, opacity: 1),
            provenance: .automation, cancelled: false)
        try session.execute(try registry.prepare(create, in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID])).documentCommand)
        let mixed = command(.applyReusableStyles([styleID]))
        let prepared = try registry.prepare(mixed, in: session.document,
            context: fixture.context(selectedIDs: mixed.orderedNodeIDs))
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(prepared.skippedNodeIDs, [fixture.secondNodeID])
        try session.execute(prepared.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.secondNodeID }?
            .insertionProperty(CanonicalReusableStyleIndex.appliedKey))
        XCTAssertThrowsError(try registry.prepare(command(.zIndex(1), revision: 0),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])))

        var malformed = session.document
        let rootIndex = try XCTUnwrap(malformed.pages[0].nodes.firstIndex { $0.id == fixture.rootID })
        malformed.pages[0].nodes[rootIndex].properties.append(.init(
            key: .init(rawValue: CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description).fill"),
            value: .string("not-a-color"), origin: .authored))
        XCTAssertThrowsError(try malformed.validate())

        let record = AdvancedStyleDiagnosticFactory.make(
            command: mixed, resultRevision: session.document.revision,
            result: .success, failure: nil)
        XCTAssertEqual(record.sanitizedIdentifiers.count, 2)
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertTrue(record.requirementIDs.contains("SF-0511-008"))
    }
}

private struct TransformFixture {
    var document: CanonicalDocument
    let pageID: PageID
    let rootID: NodeID
    let nodeID: NodeID
    let secondNodeID: NodeID
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    var selectedIDs: [NodeID]

    var context: TransformValidationContext { context(selectedIDs: selectedIDs) }

    func context(
        selectedIDs: [NodeID],
        availableIDs: Set<NodeID>? = nil,
        lifecycleAvailable: Bool = true
    ) -> TransformValidationContext {
        TransformValidationContext(
            activePageID: pageID,
            currentSceneID: sceneID,
            rendererGeneration: rendererGeneration,
            selectedNodeIDs: selectedIDs,
            availableNodeIDs: availableIDs ?? Set(document.pages[0].nodes.map(\.id)),
            isLifecycleAvailable: lifecycleAvailable,
            lifecycleDisabledReason: lifecycleAvailable ? nil : "A document transition is active."
        )
    }

    func command(
        operation: TransformOperation,
        orderedIDs: [NodeID]? = nil,
        documentID: DocumentID? = nil,
        revision: UInt64? = nil,
        rendererGeneration: UInt64? = nil
    ) -> GeometryTransformCommand {
        GeometryTransformCommand(
            identity: TransformOperationIdentity(
                sessionID: TransformSessionID(UUID(uuidString: "94000000-0000-4000-8000-000000000001")!),
                documentID: documentID ?? document.id,
                pageID: pageID,
                revision: revision ?? document.revision,
                sceneID: sceneID,
                rendererGeneration: rendererGeneration ?? self.rendererGeneration
            ),
            orderedNodeIDs: orderedIDs ?? selectedIDs,
            operation: operation,
            provenance: .automation
        )
    }

    func inspectorCommand(
        field: GeometryInspectorField,
        value: Double,
        revision: UInt64? = nil,
        breakpoint: ResponsiveBreakpoint = .desktop,
        removesOverride: Bool = false
    ) -> GeometryInspectorCommand {
        GeometryInspectorCommand(
            identity: .init(
                editID: GeometryInspectorEditID(UUID(uuidString: "94000000-0000-4000-8000-000000000099")!),
                documentID: document.id,
                pageID: pageID,
                revision: revision ?? document.revision,
                sceneID: sceneID,
                rendererGeneration: rendererGeneration
            ),
            orderedNodeIDs: selectedIDs,
            field: field,
            value: value,
            provenance: .automation,
            breakpoint: breakpoint,
            removesOverride: removesOverride
        )
    }

    func with(document: CanonicalDocument) -> Self {
        Self(
            document: document, pageID: pageID, rootID: rootID,
            nodeID: nodeID, secondNodeID: secondNodeID, sceneID: sceneID,
            rendererGeneration: rendererGeneration, selectedIDs: selectedIDs
        )
    }

    func renderIdentity(revision: UInt64) -> CanvasRenderRequestIdentity {
        CanvasRenderRequestIdentity(
            documentID: document.id,
            revision: revision,
            sceneID: sceneID,
            sceneGeneration: revision,
            viewportGeneration: 1,
            scale: try! .init(2)
        )
    }

    func scene(identity: CanvasRenderRequestIdentity, frame: WorldRect) -> CanvasRenderSceneSnapshot {
        CanvasRenderSceneSnapshot(
            identity: identity,
            surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "95000000-0000-4000-8000-000000000001")!),
            objects: [
                CanvasRenderObject(
                    id: nodeID, frame: frame, clipRect: nil, paintOrder: 0,
                    style: .container, isVisible: true, accessibilityLabel: "Frame"
                ),
            ]
        )
    }
}

private func makeFixture(selectedIDs: [NodeID]? = nil) -> TransformFixture {
    var document = ProjectCreation.blank()
    let pageID = document.pages[0].id
    let rootID = document.pages[0].rootNodeIDs[0]
    let nodeID = NodeID(UUID(uuidString: "91000000-0000-4000-8000-000000000001")!)
    let secondNodeID = NodeID(UUID(uuidString: "91000000-0000-4000-8000-000000000002")!)
    document.pages[0].nodes[0].childIDs = [nodeID, secondNodeID]
    document.pages[0].nodes.append(makeGeometryNode(
        id: nodeID, parent: rootID, x: 10, y: 20, width: 120, height: 80
    ))
    document.pages[0].nodes.append(makeGeometryNode(
        id: secondNodeID, parent: rootID, x: 200, y: 50, width: 90, height: 70
    ))
    return TransformFixture(
        document: document,
        pageID: pageID,
        rootID: rootID,
        nodeID: nodeID,
        secondNodeID: secondNodeID,
        sceneID: CanvasViewportSceneID(UUID(uuidString: "93000000-0000-4000-8000-000000000001")!),
        rendererGeneration: document.revision,
        selectedIDs: selectedIDs ?? [nodeID]
    )
}

private func makeGeometryNode(
    id: NodeID,
    parent: NodeID,
    x: Double,
    y: Double,
    width: Double,
    height: Double
) -> DocumentNode {
    let keys: [(String, Double)] = [
        ("layout.x", x), ("layout.y", y),
        ("layout.width", width), ("layout.height", height),
    ]
    return DocumentNode(
        id: id,
        kind: .frame,
        name: "Frame",
        parent: .node(parent),
        properties: keys.enumerated().map { index, item in
            NodeProperty(
                id: PropertyID(UUID(uuidString: String(
                    format: "92000000-0000-4000-8000-%012d",
                    index + (id.rawValue.uuidString.hasSuffix("2") ? 10 : 0) + 1
                ))!),
                key: PropertyKey(rawValue: item.0),
                value: .number(item.1),
                origin: .authored
            )
        }
    )
}

private func applyStructuralDefaults(for kind: NodeKind, to node: inout DocumentNode) {
    let values: [(String, PropertyValue)]
    switch kind {
    case .section:
        values = [("layout.container.kind", .string("section")), ("layout.padding", .number(48)), ("layout.axis", .string("vertical"))]
    case .stack:
        values = [("layout.container.kind", .string("stack")), ("layout.axis", .string("vertical")), ("layout.padding", .number(24)), ("layout.gap", .number(24)), ("layout.align", .string("start"))]
    case .grid:
        values = [("layout.container.kind", .string("grid")), ("layout.padding", .number(24)), ("layout.gap", .number(24)), ("layout.grid.columns", .number(2)), ("layout.grid.placement", .string("row-major"))]
    case .frame, .text, .image, .button, .link, .form, .component:
        values = []
    }
    node.properties.append(contentsOf: values.map { key, value in
        NodeProperty(key: PropertyKey(rawValue: key), value: value, origin: .defaulted)
    })
}

private func booleanProperty(_ key: String, _ value: Bool) -> NodeProperty {
    NodeProperty(key: .init(rawValue: key), value: .boolean(value))
}

private extension CanonicalDocument {
    func nodeGeometry(_ id: NodeID) -> InsertionGeometry? {
        pages.flatMap(\.nodes).first(where: { $0.id == id })?.insertionGeometry
    }

    func withRevision(_ value: UInt64) -> CanonicalDocument {
        var copy = self
        copy.revision = value
        return copy
    }
}

private struct TransformCapacityFixture {
    let document: CanonicalDocument
    let command: GeometryTransformCommand
    let context: TransformValidationContext
}

private func makeCapacityFixture(count: Int) -> TransformCapacityFixture {
    var document = ProjectCreation.blank()
    let pageID = document.pages[0].id
    let rootID = document.pages[0].rootNodeIDs[0]
    let selectedID = NodeID(UUID(uuidString: "96000000-0000-4000-8000-000000000001")!)
    document.pages[0].nodes[0].childIDs = [selectedID]
    document.pages[0].nodes.append(makeGeometryNode(
        id: selectedID, parent: rootID, x: 10, y: 10, width: 100, height: 100
    ))
    if count > 1 {
        for index in 1..<count {
            let value = String(format: "96000000-0000-4000-8001-%012d", index)
            let id = NodeID(UUID(uuidString: value)!)
            document.pages[0].nodes[0].childIDs.append(id)
            document.pages[0].nodes.append(DocumentNode(
                id: id, kind: .frame, name: "Capacity \(index)", parent: .node(rootID)
            ))
        }
    }
    let sceneID = CanvasViewportSceneID()
    let context = TransformValidationContext(
        activePageID: pageID,
        currentSceneID: sceneID,
        rendererGeneration: document.revision,
        selectedNodeIDs: [selectedID],
        availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
        isLifecycleAvailable: true,
        lifecycleDisabledReason: nil
    )
    let command = GeometryTransformCommand(
        identity: .init(
            sessionID: TransformSessionID(),
            documentID: document.id,
            pageID: pageID,
            revision: document.revision,
            sceneID: sceneID,
            rendererGeneration: document.revision
        ),
        orderedNodeIDs: [selectedID],
        operation: .move(delta: .init(dx: 1, dy: 1), constraint: .none),
        provenance: .automation
    )
    return TransformCapacityFixture(document: document, command: command, context: context)
}

private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}
