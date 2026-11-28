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
        XCTAssertTrue(text.contains("\"documentSchemaVersion\":\(DocumentSerializer.currentSchemaVersion)"))
        XCTAssertTrue(text.contains(projectID.description))
        XCTAssertTrue(text.contains("\"sha256\""))
    }

    /// OD-032: the blank project plus `pages` pages of `framesPerPage` frames.
    private func framedPackage(pages: Int, framesPerPage: Int) throws -> ProjectPackage {
        var document = ProjectCreation.blank()
        for pageIndex in 0..<pages {
            var page = DocumentPage(name: "Framed Page \(pageIndex + 1)", route: PageRoute(rawValue: "/framed-\(pageIndex + 1)"))
            let rootID = try XCTUnwrap(page.rootNodeIDs.first)
            let rootIndex = try XCTUnwrap(page.nodes.firstIndex { $0.id == rootID })
            for index in 0..<framesPerPage {
                let frame = DocumentNode(kind: .frame, name: "Frame \(index + 1)", parent: .node(rootID), properties:
                    [("layout.x", Double(index % 40 * 30)), ("layout.y", Double(index / 40 * 30)), ("layout.width", 24), ("layout.height", 24)]
                        .map { NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1)) })
                page.nodes[rootIndex].childIDs.append(frame.id)
                page.nodes.append(frame)
            }
            document.pages.append(page)
        }
        try document.validate()
        return ProjectPackage(projectID: projectID, createdAt: ProjectTimestamp("2026-11-26T03:00:00.000Z"), document: document)
    }

    // SF-0301-001/003/004, SF-1702-001, OD-032: a document that fits one
    // member is still written as package v1 (older builds open it); a larger
    // one is written as package v2: a root without pages, then ordered page
    // members each within the member limit, each with its own checksum. The
    // bytes are deterministic and the package reopens identical.
    func testPackageVersionTwoSplitsALargeDocumentIntoBoundedPageMembersAndRoundTrips() async throws {
        let store = ProjectPackageStore()
        let small = try await store.encode(package())
        let smallManifest = try XCTUnwrap(decodeArchive(small).first { $0.path == "manifest.json" })
        XCTAssertTrue(String(decoding: smallManifest.data, as: UTF8.self).contains("\"packageVersion\":1"))
        XCTAssertFalse(try decodeArchive(small).contains { $0.path.hasPrefix("pages/") })

        let large = try framedPackage(pages: 2, framesPerPage: 4_000)
        let envelope = try DocumentSerializer.encode(large.document)
        XCTAssertGreaterThan(envelope.count, ProjectPackageStore.maximumMemberBytes, "Precondition")
        let first = try await store.encode(large)
        let second = try await store.encode(large)
        XCTAssertEqual(second, first, "Deterministic")
        let members = try decodeArchive(first)
        let manifestData = try XCTUnwrap(members.first { $0.path == "manifest.json" }).data
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifest["packageVersion"] as? Int, 2)
        XCTAssertEqual((manifest["compatibility"] as? [String: Any])?["minimumPackageReaderVersion"] as? Int, 2)
        let pageMembers = members.filter { $0.path.hasPrefix("pages/") }.sorted { $0.path < $1.path }
        XCTAssertGreaterThanOrEqual(pageMembers.count, 2)
        XCTAssertEqual(pageMembers.map(\.path), (0..<pageMembers.count).map { String(format: "pages/%04d.json", $0) })
        XCTAssertTrue(pageMembers.allSatisfy { $0.data.count <= ProjectPackageStore.maximumMemberBytes })
        let descriptors = try XCTUnwrap(manifest["members"] as? [[String: Any]])
        for member in pageMembers {
            let descriptor = try XCTUnwrap(descriptors.first { $0["path"] as? String == member.path })
            XCTAssertEqual(descriptor["role"] as? String, "pages")
            XCTAssertEqual(descriptor["sha256"] as? String, SHA256.hash(data: member.data).map { String(format: "%02x", $0) }.joined())
        }
        let root = try XCTUnwrap(members.first { $0.path == "document.json" }).data
        XCTAssertLessThan(root.count, 64 * 1_024, "The root holds no pages")
        XCTAssertNotNil(root.range(of: ProjectPackagePageSplit.marker))
        XCTAssertNil(root.range(of: Data("Framed Page 1".utf8)))
        XCTAssertEqual(try ProjectPackagePageSplit.join(root: root, members: pageMembers.map(\.data)), envelope,
                       "Joining reproduces the exact canonical document")

        let decoded = try await store.decode(first)
        XCTAssertEqual(decoded.document, large.document)
        XCTAssertEqual(decoded.projectID, large.projectID)
        XCTAssertEqual(decoded.compatibility.minimumPackageReaderVersion, 2)
        XCTAssertFalse(decoded.optionalMembers.contains { $0.path.hasPrefix("pages/") }, "Page members are not optional members")
        // Written again after it shrinks, the project is package v1 again.
        var shrunk = decoded.document
        shrunk.pages.removeLast(2)
        let rewritten = try await store.encode(ProjectPackage(projectID: decoded.projectID, createdAt: decoded.createdAt,
            document: shrunk, compatibility: decoded.compatibility))
        let rewrittenManifest = try XCTUnwrap(decodeArchive(rewritten).first { $0.path == "manifest.json" })
        XCTAssertTrue(String(decoding: rewrittenManifest.data, as: UTF8.self).contains("\"packageVersion\":1"))
        XCTAssertTrue(String(decoding: rewrittenManifest.data, as: UTF8.self).contains("\"minimumPackageReaderVersion\":1"))
    }

    // OD-032: packing keeps page order, fills each member up to the limit,
    // never splits a page (a page above the limit is refused), and joining
    // is the exact inverse. A root or member that could inject document
    // fields or reorder content is refused.
    func testPageSplitPacksWholePagesInOrderAndRefusesTamperedMembers() throws {
        let pages = (1...5).map { Data(#"{"n":\#($0),"pad":"\#(String(repeating: "x", count: 10))"}"#.utf8) }
        let list = "[" + pages.map { String(decoding: $0, as: UTF8.self) }.joined(separator: ",") + "]"
        let envelope = Data(#"{"document":{"id":"d","pages":\#(list),"revision":1},"schemaVersion":26}"#.utf8)
        let limit = pages[0].count * 2 + 3
        let split = try ProjectPackagePageSplit.split(envelope: envelope, pages: pages, memberLimit: limit)
        XCTAssertEqual(split.members.count, 3, "Two pages per member, then one")
        XCTAssertTrue(split.members.allSatisfy { $0.count <= limit })
        XCTAssertEqual(split.largestPageBytes, pages.map(\.count).max())
        XCTAssertEqual(String(decoding: split.root, as: UTF8.self),
                       #"{"document":{"id":"d","pages":"app.siteforge.package-v2.pages","revision":1},"schemaVersion":26}"#)
        XCTAssertEqual(try ProjectPackagePageSplit.join(root: split.root, members: split.members), envelope)
        XCTAssertEqual(try ProjectPackagePageSplit.split(envelope: envelope, pages: pages, memberLimit: 10_000).members.count, 1)

        XCTAssertThrowsError(try ProjectPackagePageSplit.split(envelope: envelope, pages: pages, memberLimit: pages[0].count + 1)) {
            XCTAssertEqual($0 as? ProjectPackageError, .oversizedInput, "A page is never split")
        }
        XCTAssertThrowsError(try ProjectPackagePageSplit.split(envelope: envelope, pages: Array(pages.reversed()), memberLimit: limit)) {
            XCTAssertEqual($0 as? ProjectPackageError, .corruptDocument, "Pages must match the document's own encoding")
        }
        func refusesJoin(_ root: Data, _ members: [Data], _ label: String) {
            XCTAssertThrowsError(try ProjectPackagePageSplit.join(root: root, members: members), label) {
                XCTAssertEqual($0 as? ProjectPackageError, .corruptDocument, label)
            }
        }
        refusesJoin(split.root, [], "no page members")
        refusesJoin(split.root, [Data(#"[{"n":1}],"revision":9,"x":[{"n":2}]"#.utf8)], "member closes the list early")
        refusesJoin(split.root, [Data("[]".utf8)], "empty member")
        refusesJoin(split.root, [Data("[1,2]".utf8)], "members hold pages, not other values")
        refusesJoin(split.root, [Data(#"{"n":1}"#.utf8)], "not an array")
        refusesJoin(envelope, split.members, "root without the marker")
        let doubled = Data(#"{"document":{"a":"x","pages":"app.siteforge.package-v2.pages","b":{"pages":"app.siteforge.package-v2.pages"}},"schemaVersion":26}"#.utf8)
        refusesJoin(doubled, split.members, "two markers")
        let misplaced = Data(#"{"document":{"pages":[],"websiteMetadata":{"pages":"app.siteforge.package-v2.pages"}},"schemaVersion":26}"#.utf8)
        refusesJoin(misplaced, split.members, "marker outside the document's page list")

        XCTAssertEqual(ProjectPackagePageSplit.memberIndex("pages/0007.json"), 7)
        for path in ["pages/7.json", "pages/00007.json", "pages/-001.json", "pages/0007.JSON", "page/0007.json"] {
            XCTAssertNil(ProjectPackagePageSplit.memberIndex(path), path)
        }
    }

    // SF-0301-004, SF-1702-008, OD-032: the v2 reader refuses a missing page
    // member, a gap in numbering, a page member with another role, a v1
    // manifest carrying page members, a v2 manifest that older readers could
    // open, and a tampered page member, each with a specific error and
    // without returning a document.
    func testPackageVersionTwoReaderRefusesMalformedPageMembers() async throws {
        let store = ProjectPackageStore()
        let members = try decodeArchive(try await store.encode(try framedPackage(pages: 2, framesPerPage: 4_000)))
        let pagePaths = members.map(\.path).filter { $0.hasPrefix("pages/") }.sorted()
        XCTAssertGreaterThanOrEqual(pagePaths.count, 2)
        func withoutMember(_ path: String) throws -> [ArchiveMember] {
            try editingManifest(in: members.filter { $0.path != path }) { manifest in
                manifest["members"] = (manifest["members"] as! [[String: Any]]).filter { $0["path"] as? String != path }
            }
        }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(try withoutMember(pagePaths[0])))
        }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(try editingManifest(in: members) { manifest in
                manifest["members"] = (manifest["members"] as! [[String: Any]]).map { descriptor in
                    var descriptor = descriptor
                    if descriptor["path"] as? String == pagePaths[1] { descriptor["role"] = "optional" }
                    return descriptor
                }
            }))
        }
        let lastPage = try XCTUnwrap(pagePaths.last)
        let renamed = members.map { $0.path == lastPage ? ArchiveMember(path: "pages/0009.json", data: $0.data) : $0 }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(try editingManifest(in: renamed) { manifest in
                manifest["members"] = (manifest["members"] as! [[String: Any]]).map { descriptor in
                    var descriptor = descriptor
                    if descriptor["path"] as? String == lastPage { descriptor["path"] = "pages/0009.json" }
                    return descriptor
                }
            }))
        }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(try editingManifest(in: members) { manifest in
                manifest["packageVersion"] = 1
                manifest["compatibility"] = ["minimumPackageReaderVersion": 1,
                                             "minimumDocumentSchemaVersion": (manifest["compatibility"] as! [String: Any])["minimumDocumentSchemaVersion"]!]
            }))
        }
        await XCTAssertThrowsProjectPackageError(.corruptManifest) {
            try await store.decode(encodeArchive(try editingManifest(in: members) { manifest in
                var compatibility = manifest["compatibility"] as! [String: Any]
                compatibility["minimumPackageReaderVersion"] = 1
                manifest["compatibility"] = compatibility
            }))
        }
        var tampered = members
        let index = try XCTUnwrap(tampered.firstIndex { $0.path == pagePaths[0] })
        var bytes = tampered[index].data
        bytes[bytes.count / 2] ^= 0x01
        tampered[index] = ArchiveMember(path: pagePaths[0], data: bytes)
        await XCTAssertThrowsProjectPackageError(.memberIntegrityFailure) {
            try await store.decode(encodeArchive(tampered))
        }
        // An optional member may not use the page-member prefix on write.
        var forged = try framedPackage(pages: 0, framesPerPage: 1)
        forged = ProjectPackage(projectID: forged.projectID, createdAt: forged.createdAt, document: forged.document,
                                optionalMembers: [ProjectPackageMember(path: "pages/0000.json", data: Data("[]".utf8))])
        await XCTAssertThrowsProjectPackageError(.corruptManifest) { try await store.encode(forged) }
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

    // SF-1006-001, SF-1006-005 — form metadata remains ordinary canonical
    // package content: no visitor values, paths, or submission state are
    // serialized, while ordered option identity survives reopen unchanged.
    func testFormPackageRoundTripPreservesOrderedControlMetadata() async throws {
        let formID = NodeID(), selectID = NodeID(), checkboxID = NodeID(), submitID = NodeID()
        let options = try CanonicalFormSelectOptions.encode([
            .init(label: "Starter", value: "starter"),
            .init(label: "Professional", value: "professional"),
        ])
        func field(_ id: NodeID, _ kind: String, _ label: String, _ name: String, extra: [NodeProperty] = []) -> DocumentNode {
            .init(id: id, kind: .text, name: label, parent: .node(formID), properties: [
                .init(key: .init(rawValue: CanonicalFormField.kindKey), value: .string(kind)),
                .init(key: .init(rawValue: CanonicalFormField.labelKey), value: .string(label)),
                .init(key: .init(rawValue: CanonicalFormField.nameKey), value: .string(name)),
                .init(key: .init(rawValue: CanonicalFormField.requiredKey), value: .boolean(kind != "submit")),
            ] + extra)
        }
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [formID], nodes: [
                .init(id: formID, kind: .form, name: "Contact", parent: .page(pageID), childIDs: [selectID, checkboxID, submitID]),
                field(selectID, "select", "Plan", "plan", extra: [.init(key: .init(rawValue: CanonicalFormField.optionsKey), value: .string(options))]),
                field(checkboxID, "checkbox", "Terms", "terms"),
                field(submitID, "submit", "Send", "send"),
            ])
        let document = CanonicalDocument(id: documentID, pages: [page])
        let original = ProjectPackage(projectID: projectID,
            createdAt: ProjectTimestamp("2026-07-19T12:00:00.000Z"),
            modifiedAt: ProjectTimestamp("2026-07-19T12:30:00.000Z"), document: document)
        let store = ProjectPackageStore()
        let bytes = try await store.encode(original)
        let decoded = try await store.decode(bytes)
        XCTAssertEqual(decoded, original)
        let destination = try fixtureDirectory().appendingPathComponent("Form.siteforge")
        try await store.write(original, to: destination)
        let reopened = try await store.read(from: destination)
        XCTAssertEqual(reopened, original)
        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("form-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: projectID, in: recoveryDirectory)
        try await store.write(original, to: recoveryURL, policy: .recovery(projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL, expectedProjectID: projectID
        ).package
        XCTAssertEqual(recovered, original)
        let decodedOptions = try CanonicalFormSelectOptions.decode(try XCTUnwrap(decoded.document.pages[0].nodes.first { $0.id == selectID }?.insertionStringProperty(CanonicalFormField.optionsKey)))
        XCTAssertEqual(decodedOptions.map(\.value), ["starter", "professional"])
    }

    // SF-1006-001, SF-1006-004, SF-1006-005 — the Form Inspector's typed
    // transaction writes ordinary package content, so save/reopen and recovery
    // preserve field/property and select-option identity without UI drafts.
    @MainActor
    func testFormInspectorTransactionPersistsThroughPackageAndRecovery() async throws {
        let formID = NodeID(), fieldID = NodeID()
        let rootID = NodeID()
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [rootID], nodes: [
                .init(id: rootID, kind: .frame, name: "Root", parent: .page(pageID), childIDs: [formID]),
                .init(id: formID, kind: .form, name: "Contact", parent: .node(rootID), childIDs: [fieldID]),
                .init(id: fieldID, kind: .text, name: "Email", parent: .node(formID)),
            ])
        let initial = CanonicalDocument(id: documentID, pages: [page])
        let sceneID = CanvasViewportSceneID()
        let context = TransformValidationContext(activePageID: pageID, currentSceneID: sceneID,
            rendererGeneration: 4, selectedNodeIDs: [fieldID], availableNodeIDs: [rootID, formID, fieldID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let edit = FormFieldConfiguration(kind: .email, label: "Work email", name: "work_email",
            help: "We only use this to reply.", required: true, options: [])
        let command = FormInspectorCommand(identity: .init(documentID: initial.id, pageID: pageID,
            revision: initial.revision, sceneID: sceneID, rendererGeneration: 4, selectedNodeIDs: [fieldID]),
            edit: .configure(edit), cancelled: false)
        let session = DocumentSession(document: initial)
        let prepared = try FormInspectorCommandRegistry().prepare(command, in: initial, context: context)
        try session.execute(prepared.command)
        let authored = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID })
        let authoredPropertyIDs = authored.properties.map(\.id)

        let package = ProjectPackage(projectID: projectID,
            createdAt: ProjectTimestamp("2026-07-19T12:00:00.000Z"),
            modifiedAt: ProjectTimestamp("2026-07-19T12:30:00.000Z"), document: session.document)
        let store = ProjectPackageStore()
        let bytes = try await store.encode(package)
        let reopened = try await store.decode(bytes)
        let reopenedField = try XCTUnwrap(reopened.document.pages[0].nodes.first { $0.id == fieldID })
        XCTAssertEqual(reopenedField.properties.map(\.id), authoredPropertyIDs)
        XCTAssertEqual(reopenedField.insertionStringProperty(CanonicalFormField.nameKey), "work_email")
        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("form-inspector-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: projectID, in: recoveryDirectory)
        try await store.write(package, to: recoveryURL, policy: .recovery(projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(from: recoveryURL, expectedProjectID: projectID).package
        XCTAssertEqual(recovered.document, session.document)
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
        XCTAssertTrue(first.document.componentDefinitions.isEmpty)
        XCTAssertFalse(first.document.pages.flatMap(\.nodes).contains { $0.kind == .component })
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
        XCTAssertTrue(legacy.document.componentDefinitions.isEmpty)
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

    // SF-0507-001/004/005/008 — typography remains canonical through the
    // production package and owned-recovery paths. Editor caret, selection,
    // fallback availability, and draft state have no serialized counterpart.
    @MainActor
    func testTypographyPersistsAcrossPackageReopenAndOwnedRecovery() async throws {
        var document = ProjectCreation.blank()
        let page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let nodeID = NodeID(UUID(uuidString: "85000000-0000-4000-8000-000000000015")!)
        document.pages[0].nodes[0].childIDs.append(nodeID)
        document.pages[0].nodes.append(DocumentNode(
            id: nodeID,
            kind: .text,
            name: "Text",
            parent: .node(rootID),
            properties: [
                NodeProperty(key: PropertyKey(rawValue: "content.text"), value: .string("Typography"), origin: .authored),
                NodeProperty(key: PropertyKey(rawValue: "layout.x"), value: .number(40), origin: .authored),
                NodeProperty(key: PropertyKey(rawValue: "layout.y"), value: .number(56), origin: .authored),
                NodeProperty(key: PropertyKey(rawValue: "layout.width"), value: .number(260), origin: .authored),
                NodeProperty(key: PropertyKey(rawValue: "layout.height"), value: .number(80), origin: .authored),
            ]
        ))
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "86000000-0000-4000-8000-000000000015")!)
        let rendererGeneration: UInt64 = 15
        let registry = TypographyCommandRegistry()
        let session = DocumentSession(document: document)
        let context = TransformValidationContext(
            activePageID: page.id,
            currentSceneID: sceneID,
            rendererGeneration: rendererGeneration,
            selectedNodeIDs: [nodeID],
            availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
            isLifecycleAvailable: true,
            lifecycleDisabledReason: nil
        )
        func command(_ edit: TypographyEdit) -> TypographyCommand {
            .init(
                identity: .init(
                    documentID: session.document.id,
                    pageID: page.id,
                    revision: session.document.revision,
                    sceneID: sceneID,
                    rendererGeneration: rendererGeneration
                ),
                orderedNodeIDs: [nodeID],
                edit: edit,
                provenance: .automation,
                cancelled: false
            )
        }
        for edit in [
            TypographyEdit.family("Unavailable SiteForge Test Font"),
            .weight(.semibold), .size(26), .lineHeight(34), .tracking(1.25), .alignment(.trailing),
        ] {
            let prepared = try registry.prepare(command(edit), in: session.document, context: context)
            _ = try session.execute(prepared.documentCommand)
        }
        let expected = CanonicalTypography(
            family: "Unavailable SiteForge Test Font", weight: .semibold,
            size: 26, lineHeight: 34, tracking: 1.25, alignment: .trailing
        )

        let baseline = package()
        let authored = ProjectPackage(
            projectID: baseline.projectID,
            createdAt: baseline.createdAt,
            modifiedAt: baseline.modifiedAt,
            document: session.document,
            optionalMembers: baseline.optionalMembers,
            compatibility: baseline.compatibility
        )
        let store = ProjectPackageStore()
        let encoded = try await store.encode(authored)
        let reopened = try await store.decode(encoded)
        let reopenedNode = try XCTUnwrap(reopened.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: reopenedNode), expected)
        let resaved = try await store.encode(reopened)
        XCTAssertEqual(resaved, encoded)

        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("typography-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: baseline.projectID, in: recoveryDirectory)
        try await store.write(reopened, to: recoveryURL, policy: .recovery(baseline.projectID))
        let recoveredSnapshot = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL,
            expectedProjectID: baseline.projectID
        )
        let recovered = recoveredSnapshot.package
        let recoveredNode = try XCTUnwrap(recovered.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: recoveredNode), expected)

        // SF-0507-005: the paired chooser uses the same package/recovery
        // format, retaining existing property identity rather than a font store.
        let beforePair = session.document.pages
        let pairedEdit = try registry.prepare(command(.fontFace(family: "System", weight: .bold)),
            in: session.document, context: context)
        try session.execute(pairedEdit.documentCommand)
        let pairedNode = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID })
        XCTAssertEqual(pairedNode.insertionProperty(CanonicalTypography.namespace + "family")?.id,
            reopenedNode.insertionProperty(CanonicalTypography.namespace + "family")?.id)
        let pairedPackage = ProjectPackage(projectID: baseline.projectID, createdAt: baseline.createdAt,
            modifiedAt: baseline.modifiedAt, document: session.document,
            optionalMembers: baseline.optionalMembers, compatibility: baseline.compatibility)
        let pairedEncoded = try await store.encode(pairedPackage)
        let pairedReopened = try await store.decode(pairedEncoded)
        XCTAssertEqual(pairedReopened.document, session.document)
        let pairedResaved = try await store.encode(pairedReopened)
        XCTAssertEqual(pairedResaved, pairedEncoded)
        try await store.write(pairedReopened, to: recoveryURL, expected: recoveredSnapshot.file.fingerprint,
                              policy: .recovery(baseline.projectID))
        let pairedRecovery = try await store.readOwnedRecoverySnapshot(from: recoveryURL, expectedProjectID: baseline.projectID).package
        XCTAssertEqual(pairedRecovery.document, session.document)
        let style = try XCTUnwrap(TypographyCommandRegistry.resolvedTypography(for: pairedNode))
        XCTAssertEqual(style.family, "System"); XCTAssertEqual(style.weight, .bold)
        XCTAssertEqual(style.size, expected.size); XCTAssertEqual(style.lineHeight, expected.lineHeight)
        XCTAssertEqual(style.tracking, expected.tracking); XCTAssertEqual(style.alignment, expected.alignment)
        let afterPair = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, beforePair)
        try session.redo(); XCTAssertEqual(session.document.pages, afterPair)
    }

    @MainActor
    func testSemanticElementPersistsAcrossPackageReopenAndOwnedRecovery() async throws {
        var document = ProjectCreation.blank()
        let page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let nodeID = NodeID(UUID(uuidString: "87000000-0000-4000-8000-000000000026")!)
        document.pages[0].nodes[0].childIDs.append(nodeID)
        document.pages[0].nodes.append(DocumentNode(id: nodeID, kind: .frame, name: "Frame", parent: .node(rootID)))
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "88000000-0000-4000-8000-000000000026")!)
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: sceneID,
            rendererGeneration: 26, selectedNodeIDs: [nodeID],
            availableNodeIDs: Set(document.pages[0].nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let session = DocumentSession(document: document)
        let registry = SemanticElementCommandRegistry()
        let command = SemanticElementCommand(identity: .init(documentID: session.document.id, pageID: page.id,
            revision: session.document.revision, sceneID: sceneID, rendererGeneration: 26),
            orderedNodeIDs: [nodeID], edit: .set(.article), provenance: .automation, cancelled: false)
        _ = try session.execute(registry.prepare(command, in: session.document, context: context).documentCommand)
        let baseline = package()
        let authored = ProjectPackage(projectID: baseline.projectID, createdAt: baseline.createdAt,
            modifiedAt: baseline.modifiedAt, document: session.document, optionalMembers: baseline.optionalMembers,
            compatibility: baseline.compatibility)
        let store = ProjectPackageStore()
        let encoded = try await store.encode(authored)
        let reopened = try await store.decode(encoded)
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: try XCTUnwrap(reopened.document.pages[0].nodes.first(where: { $0.id == nodeID })) )?.0, .article)
        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("semantic-element-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: baseline.projectID, in: recoveryDirectory)
        try await store.write(reopened, to: recoveryURL, policy: .recovery(baseline.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(from: recoveryURL, expectedProjectID: baseline.projectID).package
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: try XCTUnwrap(recovered.document.pages[0].nodes.first(where: { $0.id == nodeID })) )?.0, .article)
    }

    // SF-0601-002/004/005; SF-0602-001/004/005 — breakpoint overrides use
    // the production package and owned-recovery paths while the selected
    // editor breakpoint remains scene-local and absent from canonical data.
    @MainActor
    func testResponsiveGeometryPersistsAcrossPackageReopenAndOwnedRecovery() async throws {
        var document = ProjectCreation.blank()
        let page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let nodeID = NodeID(UUID(uuidString: "87000000-0000-4000-8000-000000000016")!)
        document.pages[0].nodes[0].childIDs.append(nodeID)
        document.pages[0].nodes.append(DocumentNode(
            id: nodeID,
            kind: .frame,
            name: "Responsive Frame",
            parent: .node(rootID),
            properties: [
                NodeProperty(key: .init(rawValue: "layout.x"), value: .number(120), origin: .authored),
                NodeProperty(key: .init(rawValue: "layout.y"), value: .number(80), origin: .authored),
                NodeProperty(key: .init(rawValue: "layout.width"), value: .number(240), origin: .authored),
                NodeProperty(key: .init(rawValue: "layout.height"), value: .number(160), origin: .authored),
            ]
        ))
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "88000000-0000-4000-8000-000000000016")!)
        let generation: UInt64 = 16
        let registry = GeometryInspectorCommandRegistry()
        let session = DocumentSession(document: document)
        func commit(_ field: GeometryInspectorField, _ value: Double, at breakpoint: ResponsiveBreakpoint) throws {
            let command = GeometryInspectorCommand(
                identity: .init(
                    editID: GeometryInspectorEditID(), documentID: session.document.id,
                    pageID: page.id, revision: session.document.revision,
                    sceneID: sceneID, rendererGeneration: generation
                ),
                orderedNodeIDs: [nodeID], field: field, value: value,
                provenance: .automation, breakpoint: breakpoint
            )
            let context = TransformValidationContext(
                activePageID: page.id, currentSceneID: sceneID,
                rendererGeneration: generation, selectedNodeIDs: [nodeID],
                availableNodeIDs: [nodeID], isLifecycleAvailable: true,
                lifecycleDisabledReason: nil
            )
            _ = try session.execute(try registry.prepare(command, in: session.document, context: context).documentCommand)
        }
        try commit(.x, 48, at: .tablet)
        try commit(.width, 320, at: .mobile)

        let baseline = package()
        let authored = ProjectPackage(
            projectID: baseline.projectID, createdAt: baseline.createdAt,
            modifiedAt: baseline.modifiedAt, document: session.document,
            optionalMembers: baseline.optionalMembers, compatibility: baseline.compatibility
        )
        let store = ProjectPackageStore()
        let encoded = try await store.encode(authored)
        let reopened = try await store.decode(encoded)
        let reopenedNode = try XCTUnwrap(reopened.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(ResponsiveGeometryResolver.geometry(for: reopenedNode, breakpoint: .desktop)?.origin.x, 120)
        XCTAssertEqual(ResponsiveGeometryResolver.geometry(for: reopenedNode, breakpoint: .tablet)?.origin.x, 48)
        XCTAssertEqual(ResponsiveGeometryResolver.geometry(for: reopenedNode, breakpoint: .mobile)?.size.width, 320)
        let resaved = try await store.encode(reopened)
        XCTAssertEqual(resaved, encoded)

        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("responsive-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: baseline.projectID, in: recoveryDirectory)
        try await store.write(reopened, to: recoveryURL, policy: .recovery(baseline.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL, expectedProjectID: baseline.projectID
        ).package
        let recoveredNode = try XCTUnwrap(recovered.document.pages[0].nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(ResponsiveGeometryResolver.geometry(for: recoveredNode, breakpoint: .tablet)?.origin.x, 48)
        XCTAssertEqual(ResponsiveGeometryResolver.geometry(for: recoveredNode, breakpoint: .mobile)?.size.width, 320)
    }

    // SF-0502-001/005; SF-0503-001/005; SF-0506-001/005 — authored
    // container layout values and stable property identities use the real
    // package and owned-recovery boundaries.
    @MainActor
    func testContainerLayoutPersistsAcrossPackageReopenAndOwnedRecovery() async throws {
        var document = ProjectCreation.blank()
        let page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let stackID = NodeID(UUID(uuidString: "89000000-0000-4000-8000-000000000017")!)
        var stack = DocumentNode(
            id: stackID, kind: .stack, name: "Stack", parent: .node(rootID),
            properties: [
                NodeProperty(key: .init(rawValue: "layout.x"), value: .number(80), origin: .authored),
                NodeProperty(key: .init(rawValue: "layout.y"), value: .number(80), origin: .authored),
                NodeProperty(key: .init(rawValue: "layout.width"), value: .number(480), origin: .defaulted),
                NodeProperty(key: .init(rawValue: "layout.height"), value: .number(260), origin: .defaulted),
            ]
        )
        applyStructuralDefaultsForPackageTest(kind: .stack, node: &stack)
        document.pages[0].nodes[0].childIDs.append(stackID)
        document.pages[0].nodes.append(stack)
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "89000000-0000-4000-8000-000000000018")!)
        let registry = ContainerLayoutCommandRegistry()
        let session = DocumentSession(document: document)
        func commit(_ field: ContainerLayoutField, _ value: ContainerLayoutValue,
                    breakpoint: ResponsiveBreakpoint = .desktop) throws {
            let context = TransformValidationContext(
                activePageID: page.id, currentSceneID: sceneID,
                rendererGeneration: 17, selectedNodeIDs: [stackID],
                availableNodeIDs: [stackID], isLifecycleAvailable: true,
                lifecycleDisabledReason: nil
            )
            let command = ContainerLayoutCommand(
                identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                    pageID: page.id, revision: session.document.revision,
                    sceneID: sceneID, rendererGeneration: 17),
                orderedNodeIDs: [stackID], field: field, value: value,
                provenance: .automation, cancelled: false, breakpoint: breakpoint
            )
            _ = try session.execute(try registry.prepare(command, in: session.document, context: context).documentCommand)
        }
        try commit(.axis, .axis(.horizontal))
        try commit(.gap, .number(18))
        try commit(.padding, .number(30))
        try commit(.alignment, .alignment(.center))
        try commit(.axis, .axis(.vertical), breakpoint: .mobile)
        try commit(.gap, .number(8), breakpoint: .mobile)
        let visibilityRegistry = ResponsiveVisibilityCommandRegistry()
        let visibilityContext = TransformValidationContext(
            activePageID: page.id, currentSceneID: sceneID, rendererGeneration: 17,
            selectedNodeIDs: [stackID], availableNodeIDs: [stackID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil
        )
        let visibility = try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: page.id, revision: session.document.revision,
                sceneID: sceneID, rendererGeneration: 17),
            orderedNodeIDs: [stackID], breakpoint: .tablet, visible: false,
            provenance: .automation, cancelled: false
        ), in: session.document, context: visibilityContext)
        _ = try session.execute(visibility.documentCommand)

        let expectedIDs = session.document.pages[0].nodes.first { $0.id == stackID }!.properties
            .filter { ["layout.axis", "layout.gap", "layout.padding", "layout.align"].contains($0.key.rawValue) }
            .map(\.id)
        let baseline = package()
        let authored = ProjectPackage(
            projectID: baseline.projectID, createdAt: baseline.createdAt,
            modifiedAt: baseline.modifiedAt, document: session.document,
            optionalMembers: baseline.optionalMembers, compatibility: baseline.compatibility
        )
        let store = ProjectPackageStore()
        let encoded = try await store.encode(authored)
        let reopened = try await store.decode(encoded)
        let reopenedNode = try XCTUnwrap(reopened.document.pages[0].nodes.first { $0.id == stackID })
        XCTAssertEqual(reopenedNode.insertionStringProperty("layout.axis"), "horizontal")
        XCTAssertEqual(reopenedNode.insertionNumberProperty("layout.gap"), 18)
        XCTAssertEqual(reopenedNode.insertionNumberProperty("layout.padding"), 30)
        XCTAssertEqual(reopenedNode.insertionStringProperty("layout.align"), "center")
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .axis, node: reopenedNode, breakpoint: .mobile)?.0, .axis(.vertical))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .gap, node: reopenedNode, breakpoint: .mobile)?.0, .number(8))
        XCTAssertFalse(ResponsiveVisibilityResolver.isVisible(reopenedNode, breakpoint: .tablet))
        XCTAssertEqual(reopenedNode.properties.filter {
            ["layout.axis", "layout.gap", "layout.padding", "layout.align"].contains($0.key.rawValue)
        }.map(\.id), expectedIDs)

        let recoveryDirectory = try fixtureDirectory().appendingPathComponent("container-layout-recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: baseline.projectID, in: recoveryDirectory)
        try await store.write(reopened, to: recoveryURL, policy: .recovery(baseline.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(
            from: recoveryURL, expectedProjectID: baseline.projectID
        ).package
        let recoveredNode = try XCTUnwrap(recovered.document.pages[0].nodes.first { $0.id == stackID })
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .gap, node: recoveredNode, breakpoint: .mobile)?.0, .number(8))
        XCTAssertFalse(ResponsiveVisibilityResolver.isVisible(recoveredNode, breakpoint: .tablet))
        XCTAssertEqual(recoveredNode.insertionStringProperty("layout.axis"), "horizontal")
        XCTAssertEqual(recoveredNode.insertionNumberProperty("layout.gap"), 18)
        XCTAssertEqual(recoveredNode.insertionStringProperty("layout.align"), "center")
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

    // SF-1301-001, SF-1301-002, SF-1301-003, SF-1301-004 (OD-043, ADR-0038)
    func testNamedSnapshotsAreStrictBoundedAndRoundTripThroughThePackage() async throws {
        let base = package()
        let document = base.document
        let stamp = ProjectTimestamp("2026-11-26T15:00:00.000Z")
        let created = try ProjectSnapshots.creating(named: "  Launch draft  ", from: document, in: base, at: stamp)
        let first = created.entry
        XCTAssertEqual(first.name, "Launch draft")
        XCTAssertEqual(first.documentRevision, 7)
        XCTAssertEqual(first.documentSchemaVersion, DocumentSerializer.currentSchemaVersion)
        XCTAssertEqual(created.package.document, document, "Creating a snapshot never edits the document")
        XCTAssertEqual(try ProjectSnapshots.list(in: created.package, documentID: documentID), [first])
        XCTAssertEqual(created.package.optionalMembers.map(\.path),
                       [ProjectSnapshotIndex.indexMemberPath, ProjectSnapshotIndex.memberPath(for: first.id)].sorted())
        XCTAssertEqual(try ProjectSnapshots.list(in: base, documentID: documentID), [])

        let store = ProjectPackageStore()
        let encoded = try await store.encode(created.package)
        let decoded = try await store.decode(encoded)
        XCTAssertEqual(decoded.optionalMembers, created.package.optionalMembers)
        let reencoded = try await store.encode(decoded)
        XCTAssertEqual(reencoded, encoded)
        XCTAssertEqual(try ProjectSnapshots.document(for: first.id, documentID: documentID, in: decoded), document)

        XCTAssertThrowsError(try ProjectSnapshots.creating(named: "launch DRAFT", from: document, in: decoded, at: stamp)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .duplicateName)
        }
        for name in ["", "   ", "tab\tname", String(repeating: "a", count: ProjectSnapshotIndex.maximumNameBytes + 1)] {
            XCTAssertThrowsError(try ProjectSnapshots.validatedName(name)) {
                XCTAssertEqual($0 as? ProjectSnapshotError, .invalidName)
            }
        }

        var filled = decoded
        for number in 2...ProjectSnapshotIndex.maximumCount {
            filled = try ProjectSnapshots.creating(named: "Version \(number)", from: document, in: filled, at: stamp).package
        }
        XCTAssertEqual(try ProjectSnapshots.list(in: filled, documentID: documentID).count, ProjectSnapshotIndex.maximumCount)
        XCTAssertThrowsError(try ProjectSnapshots.creating(named: "One more", from: document, in: filled, at: stamp)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .limitReached)
        }

        let renamed = try ProjectSnapshots.renaming(first.id, to: "Approved", documentID: documentID, in: filled)
        let renamedEntry = try XCTUnwrap(try ProjectSnapshots.list(in: renamed, documentID: documentID).first)
        XCTAssertEqual(renamedEntry.id, first.id, "Rename keeps the snapshot's identity")
        XCTAssertEqual(renamedEntry.name, "Approved")
        XCTAssertEqual(renamedEntry.sha256, first.sha256)
        XCTAssertThrowsError(try ProjectSnapshots.renaming(first.id, to: "version 2", documentID: documentID, in: renamed)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .duplicateName)
        }
        XCTAssertThrowsError(try ProjectSnapshots.renaming(first.id, to: "Approved", documentID: documentID, in: renamed)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .sameName)
        }
        let deleted = try ProjectSnapshots.deleting(first.id, documentID: documentID, in: renamed)
        XCTAssertFalse(deleted.optionalMembers.contains { $0.path == first.memberPath })
        XCTAssertEqual(try ProjectSnapshots.list(in: deleted, documentID: documentID).count, ProjectSnapshotIndex.maximumCount - 1)
        XCTAssertThrowsError(try ProjectSnapshots.deleting(first.id, documentID: documentID, in: deleted)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .notFound)
        }
        XCTAssertThrowsError(try ProjectSnapshots.document(for: first.id, documentID: documentID, in: deleted)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .notFound)
        }
        let emptied = try ProjectSnapshots.deleting(first.id, documentID: documentID, in: created.package)
        XCTAssertEqual(emptied.optionalMembers, base.optionalMembers, "Deleting the last snapshot also removes the index")

        func replacingMember(_ path: String, in source: ProjectPackage, with data: Data?) -> ProjectPackage {
            var members = source.optionalMembers.filter { $0.path != path }
            if let data { members.append(ProjectPackageMember(path: path, role: .optional, data: data)) }
            return ProjectPackage(projectID: source.projectID, createdAt: source.createdAt, modifiedAt: source.modifiedAt,
                                  document: source.document, optionalMembers: members.sorted { $0.path < $1.path })
        }
        func editingIndex(_ edit: (inout [String: Any]) -> Void) throws -> ProjectPackage {
            let member = try XCTUnwrap(created.package.optionalMembers.first { $0.path == ProjectSnapshotIndex.indexMemberPath })
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: member.data) as? [String: Any])
            edit(&json)
            let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            return replacingMember(member.path, in: created.package, with: data)
        }
        let snapshotData = try XCTUnwrap(created.package.optionalMembers.first { $0.path == first.memberPath }?.data)
        let unknownKey = try editingIndex { $0["extra"] = true }
        let futureVersion = try editingIndex { $0["version"] = 2 }
        let damaged: [(String, ProjectPackage, ProjectSnapshotError)] = [
            ("changed bytes", replacingMember(first.memberPath, in: created.package, with: snapshotData + Data(" ".utf8)), .corrupt),
            ("missing document", replacingMember(first.memberPath, in: created.package, with: nil), .corrupt),
            ("missing index", replacingMember(ProjectSnapshotIndex.indexMemberPath, in: created.package, with: nil), .corrupt),
            ("unlisted member", replacingMember("snapshots/stray.json", in: created.package, with: snapshotData), .corrupt),
            ("unknown key", unknownKey, .corrupt),
            ("future version", futureVersion, .unsupportedVersion(2)),
        ]
        for (label, value, expected) in damaged {
            XCTAssertThrowsError(try ProjectSnapshots.list(in: value, documentID: documentID), label) {
                XCTAssertEqual($0 as? ProjectSnapshotError, expected, label)
            }
            XCTAssertThrowsError(try ProjectSnapshots.creating(named: "New", from: document, in: value, at: stamp), label)
            XCTAssertEqual(ProjectSnapshots.removingAll(in: value).optionalMembers, [], "Delete All repairs: \(label)")
            XCTAssertEqual(ProjectSnapshots.removingAll(in: value).document, document)
        }
        XCTAssertThrowsError(try ProjectSnapshots.list(in: created.package, documentID: DocumentID())) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .documentMismatch)
        }
        XCTAssertEqual(ProjectSnapshots.requirementIDs, Set((1...8).map { String(format: "SF-1301-%03d", $0) }))
    }

    // SF-0906-001, SF-0906-002, SF-0906-003, SF-0906-004, SF-0906-007 (OD-046, ADR-0041)
    @MainActor
    func testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach() async throws {
        let stamp = ProjectTimestamp("2026-11-26T17:00:00.000Z")
        let token = LocalColorToken(name: "Library Brand", color: CanonicalSolidColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1))
        func libraryGeometry(_ size: Double) -> [NodeProperty] {
            [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", size), ("layout.height", size)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            }
        }
        func libraryDefinition(_ name: String, token: ColorTokenID? = nil) -> DocumentPage {
            let id = PageID(), rootID = NodeID()
            let fill = token.map { [NodeProperty(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
                                                 value: .string($0.description))] } ?? []
            let root = DocumentNode(id: rootID, kind: .frame, name: name, parent: .page(id),
                                    properties: libraryGeometry(320) + fill)
            return DocumentPage(id: id, name: name, route: .init(rawValue: ""), role: .componentDefinition,
                                provenance: .authored, rootNodeIDs: [rootID], nodes: [root])
        }
        var source = CanonicalDocument()
        source.colorTokens = [token]
        source.pages += [libraryDefinition("Card", token: token.id), libraryDefinition("Badge")]
        try source.validate()
        let sourcePackage = ProjectPackage(createdAt: stamp, document: source)
        let blank = CanonicalDocument()
        XCTAssertThrowsError(try ComponentLibraries.exporting(named: "Empty", version: .initial, from: blank,
                                                              in: ProjectPackage(createdAt: stamp, document: blank), at: stamp)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .nothingToExport)
        }
        // SF-0906-004: what a library file cannot carry is refused by the component's name.
        func libraryRefusal(_ kind: NodeKind, _ properties: [NodeProperty], fonts: [FontAsset] = [],
                            homeProperties: [NodeProperty] = []) -> ComponentLibraryError? {
            let id = PageID(), rootID = NodeID()
            let root = DocumentNode(id: rootID, kind: kind, name: "Promo", parent: .page(id),
                                    properties: libraryGeometry(80) + properties)
            var project = CanonicalDocument()
            project.fontAssets = fonts
            if let homeRoot = project.pages[0].rootNodeIDs.first,
               let homeIndex = project.pages[0].nodes.firstIndex(where: { $0.id == homeRoot }) {
                project.pages[0].nodes[homeIndex].properties += homeProperties
            }
            project.pages.append(DocumentPage(id: id, name: "Promo", route: .init(rawValue: ""), role: .componentDefinition,
                                              provenance: .authored, rootNodeIDs: [rootID], nodes: [root]))
            do {
                _ = try ComponentLibraries.exporting(named: "Refused", version: .initial, from: project,
                                                     in: ProjectPackage(createdAt: stamp, document: project), at: stamp)
                return nil
            } catch {
                return error as? ComponentLibraryError
            }
        }
        func libraryString(_ key: String, _ value: String) -> NodeProperty {
            NodeProperty(key: .init(rawValue: key), value: .string(value))
        }
        XCTAssertEqual(libraryRefusal(.image, [libraryString(CanonicalMediaPlayback.assetKey, AssetID().description)]),
                       .usesVideoOrAudio("Promo"))
        XCTAssertEqual(libraryRefusal(.text, [libraryString(SiteTranslationKey.namespace + "unparsed", "Bonjour")]),
                       .usesTranslations("Promo"))
        let libraryFont = FontAsset(resourceID: ResourceID(), family: "Inter", format: .woff2,
            originalFilename: "inter.woff2", byteCount: 1, contentHash: String(repeating: "c", count: 64))
        XCTAssertEqual(libraryRefusal(.text, [libraryString(CanonicalTypography.namespace + "family", "inter")], fonts: [libraryFont]),
                       .usesProjectFonts("Promo"), "Font families match without regard to case")
        XCTAssertEqual(libraryRefusal(.button, [libraryString(CanonicalLinkTarget.namespace + "kind", "page"),
                                                libraryString(CanonicalLinkTarget.namespace + "pageID", PageID().description)]),
                       .linksOutside("Promo"))
        // Lane V02 finding: a reusable style defined on a website page does not travel; it is named, not "invalid content".
        let libraryStyleID = ReusableStyleID()
        let styleDefinition = CanonicalReusableStyleIndex.namespace + "definition.\(libraryStyleID.description)."
        let libraryStyle = [libraryString(styleDefinition + "name", "Brand Card"),
                            NodeProperty(key: .init(rawValue: styleDefinition + "opacity"), value: .number(0.5))]
        let appliesStyle = libraryString(CanonicalReusableStyleIndex.appliedKey, libraryStyleID.description)
        XCTAssertEqual(libraryRefusal(.frame, [appliesStyle], homeProperties: libraryStyle),
                       .usesReusableStyle("Promo", "Brand Card"))
        XCTAssertNotEqual(libraryRefusal(.frame, [appliesStyle] + libraryStyle), .usesReusableStyle("Promo", "Brand Card"),
                          "A style defined inside the exported component travels with it")
        XCTAssertEqual(ComponentLibraryError.usesReusableStyle("Promo", "Brand Card").diagnosticCategory, "uses-reusable-style")
        XCTAssertEqual(ComponentLibraryError.usesVideoOrAudio("Promo").diagnosticCategory, "uses-media")
        XCTAssertEqual(ComponentLibraryError.recordTooLarge.diagnosticCategory, "record-too-large")

        let v1 = try ComponentLibraries.exporting(named: "  UI Kit ", version: .initial, from: source, in: sourcePackage, at: stamp)
        XCTAssertEqual(v1.file.name, "UI Kit")
        XCTAssertEqual(v1.package.document, source, "Export never edits the document")
        XCTAssertEqual(try ComponentLibraries.index(in: v1.package, documentID: source.id)?.published?.version, .initial)
        XCTAssertThrowsError(try ComponentLibraries.exporting(named: "UI Kit", version: .initial, from: source,
                                                              in: v1.package, at: stamp)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .versionNotNewer(.initial))
        }
        let read1 = try ComponentLibraries.reading(v1.data)
        XCTAssertEqual(read1.file.libraryID, v1.file.libraryID)
        XCTAssertEqual(read1.content.definitions.map(\.name), ["Card", "Badge"])
        XCTAssertEqual(read1.content.colorTokens, [token], "Only tokens the components use are exported")
        XCTAssertThrowsError(try ComponentLibraries.importing(read1.file, read1.content, into: source,
                                                              package: v1.package, at: stamp)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .ownLibrary)
        }

        // Import into another project: one command, identities kept.
        let consumer = CanonicalDocument()
        let consumerPackage = ProjectPackage(createdAt: stamp, document: consumer)
        let imported = try ComponentLibraries.importing(read1.file, read1.content, into: consumer,
                                                        package: consumerPackage, at: stamp)
        let session = DocumentSession(document: consumer)
        try session.execute(imported.command)
        let afterImport = session.document
        XCTAssertEqual(afterImport.componentDefinitions.map(\.id), read1.content.definitions.map(\.id))
        XCTAssertEqual(afterImport.colorTokens.map(\.id), [token.id])
        XCTAssertEqual(ComponentLibraries.status(of: imported.record, in: afterImport), .current(.initial))
        XCTAssertEqual(ComponentLibraries.status(of: imported.record, in: consumer), .missing)
        try session.undo()
        XCTAssertEqual(session.document.pages, consumer.pages, "Undo removes the whole import")
        XCTAssertEqual(session.document.colorTokens, consumer.colorTokens)
        try session.redo()

        let store = ProjectPackageStore()
        let decoded = try await store.decode(try await store.encode(imported.package))
        XCTAssertEqual(decoded.optionalMembers, imported.package.optionalMembers)
        let index = try XCTUnwrap(try ComponentLibraries.index(in: decoded, documentID: consumer.id))
        XCTAssertEqual(index.imported, [imported.record])
        XCTAssertThrowsError(try ComponentLibraries.importing(read1.file, read1.content, into: afterImport,
                                                              package: imported.package, at: stamp)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .alreadyImported("UI Kit"))
        }
        XCTAssertThrowsError(try ComponentLibraries.importing(read1.file, read1.content, into: afterImport,
                                                              package: ProjectPackage(createdAt: stamp, document: afterImport), at: stamp)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .identityConflict)
        }

        // Read-only: library items cannot change; moving them is allowed.
        let protection = ComponentLibraries.protectedIdentifiers(in: index)
        func violation(_ edited: CanonicalDocument) -> ComponentLibraryError? {
            ComponentLibraries.readOnlyViolation(from: afterImport, to: edited, pages: protection.pages, tokens: protection.tokens)
        }
        let cardID = read1.content.definitions[0].id
        var renamed = afterImport
        renamed.pages[try XCTUnwrap(renamed.pages.firstIndex { $0.id == cardID })].name = "Mine"
        XCTAssertEqual(violation(renamed), .readOnly("UI Kit"))
        var removed = afterImport
        removed.pages.removeAll { $0.id == cardID }
        XCTAssertEqual(violation(removed), .readOnly("UI Kit"))
        var recolored = afterImport
        recolored.colorTokens[0].name = "Other"
        XCTAssertEqual(violation(recolored), .readOnly("UI Kit"))
        var moved = afterImport
        moved.pages.swapAt(moved.pages.count - 1, moved.pages.count - 2)
        XCTAssertNil(violation(moved))
        var ownEdit = afterImport
        ownEdit.pages[0].name = "Start"
        XCTAssertNil(violation(ownEdit))

        // A copy of Badge on the home page; version 1.1.0 renames Card, drops
        // Badge and adds Banner.
        var withCopy = afterImport
        let homeRoot = withCopy.pages[0].rootNodeIDs[0]
        let badgeID = read1.content.definitions[1].id
        let copy = DocumentNode(kind: .component, name: "Badge", parent: .node(homeRoot),
            properties: libraryGeometry(120) + [NodeProperty(key: .init(rawValue: CanonicalComponentReference.key),
                                                             value: .string(badgeID.description))])
        let rootIndex = try XCTUnwrap(withCopy.pages[0].nodes.firstIndex { $0.id == homeRoot })
        withCopy.pages[0].nodes[rootIndex].childIDs.append(copy.id)
        withCopy.pages[0].nodes.append(copy)
        try withCopy.validate()
        var source2 = source
        source2.pages[try XCTUnwrap(source2.pages.firstIndex { $0.id == cardID })].name = "Card Large"
        source2.pages.removeAll { $0.id == badgeID }
        source2.pages.append(libraryDefinition("Banner"))
        let v2version = try XCTUnwrap(ComponentLibraryVersion("1.1.0"))
        let v2 = try ComponentLibraries.exporting(named: "UI Kit", version: v2version, from: source2, in: v1.package, at: stamp)
        XCTAssertEqual(v2.file.libraryID, v1.file.libraryID, "Exporting again keeps the library's identity")
        let read2 = try ComponentLibraries.reading(v2.data)

        let preview = try ComponentLibraries.previewingUpdate(read2.file, read2.content, in: withCopy, package: imported.package)
        XCTAssertEqual(preview.fromVersion, .initial)
        XCTAssertEqual(preview.toVersion, v2version)
        XCTAssertFalse(preview.isDowngrade)
        XCTAssertEqual(preview.removedComponentNames, ["Badge"])
        XCTAssertEqual(preview.affectedCopyCount, 1)
        XCTAssertEqual(preview.comparison.filtered(area: .pages, kind: .added).count, 1)
        XCTAssertEqual(preview.comparison.filtered(area: .pages, kind: .removed).count, 1)
        XCTAssertEqual(preview.comparison.filtered(area: .pages, kind: .changed).map(\.subject), ["Component name"])

        let updated = try ComponentLibraries.updating(read2.file, read2.content, in: withCopy, package: imported.package)
        let updateSession = DocumentSession(document: withCopy)
        try updateSession.execute(try XCTUnwrap(updated.command))
        XCTAssertEqual(updateSession.document.componentDefinitions.map(\.name), ["Card Large", "Banner"])
        XCTAssertEqual(updateSession.document.pages.prefix(2).map(\.id), withCopy.pages.prefix(2).map(\.id),
                       "The project's own pages keep their place")
        let record2 = try XCTUnwrap(try ComponentLibraries.index(in: updated.package, documentID: consumer.id)?.imported.first)
        XCTAssertEqual(record2.knownVersions.map(\.version), [.initial, v2version])
        XCTAssertEqual(Set(record2.definitionIDs), Set(read1.content.definitions.map(\.id) + read2.content.definitions.map(\.id)),
                       "The record keeps every identity a version delivered, so Undo is recognised")
        XCTAssertEqual(ComponentLibraries.status(of: record2, in: updateSession.document), .current(v2version))
        try updateSession.undo()
        XCTAssertEqual(ComponentLibraries.status(of: record2, in: updateSession.document), .earlier(.initial),
                       "Undo of an update is reported, not hidden")
        try updateSession.redo()
        XCTAssertThrowsError(try ComponentLibraries.previewingUpdate(read2.file, read2.content, in: updateSession.document,
                                                                     package: updated.package)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .unchanged)
        }
        let back = try ComponentLibraries.previewingUpdate(read1.file, read1.content, in: updateSession.document,
                                                           package: updated.package)
        XCTAssertTrue(back.isDowngrade, "Going back to an older version is an explicit, reviewed update")

        let detached = try ComponentLibraries.detaching(read1.file.libraryID, documentID: consumer.id, in: updated.package)
        XCTAssertNil(try ComponentLibraries.index(in: detached, documentID: consumer.id), "The last record removes the member")
        XCTAssertThrowsError(try ComponentLibraries.detaching(read1.file.libraryID, documentID: consumer.id, in: detached)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .notImported)
        }

        // Files and records are strict.
        var tampered = try XCTUnwrap(try JSONSerialization.jsonObject(with: v1.data) as? [String: Any])
        tampered["name"] = ""
        let cases: [(String, Data, ComponentLibraryError)] = [
            ("not json", Data("library".utf8), .invalidFile),
            ("other format", Data(#"{"format":"x","version":1}"#.utf8), .invalidFile),
            ("future", Data(#"{"format":"app.siteforge.component-library","version":2}"#.utf8), .unsupportedVersion(2)),
            ("empty name", try JSONSerialization.data(withJSONObject: tampered), .invalidFile),
            ("too large", Data(count: ComponentLibraryFile.maximumBytes + 1), .fileTooLarge),
        ]
        for (label, data, expected) in cases {
            XCTAssertThrowsError(try ComponentLibraries.reading(data), label) {
                XCTAssertEqual($0 as? ComponentLibraryError, expected, label)
            }
        }
        func withMember(_ path: String, _ data: Data) -> ProjectPackage {
            ProjectPackage(projectID: projectID, createdAt: stamp, modifiedAt: stamp, document: consumer,
                           optionalMembers: [ProjectPackageMember(path: path, role: .optional, data: data)])
        }
        for damaged in [withMember(ComponentLibraryIndex.memberPath, Data("{}".utf8)),
                        withMember("libraries/stray.json", Data("{}".utf8))] {
            XCTAssertThrowsError(try ComponentLibraries.index(in: damaged, documentID: consumer.id)) {
                XCTAssertEqual($0 as? ComponentLibraryError, .corrupt)
            }
            XCTAssertEqual(ComponentLibraries.removingAll(in: damaged).optionalMembers, [])
        }
        XCTAssertThrowsError(try ComponentLibraries.index(in: imported.package, documentID: DocumentID())) {
            XCTAssertEqual($0 as? ComponentLibraryError, .documentMismatch)
        }

        XCTAssertEqual(ComponentLibraryVersion("1.2.3")?.description, "1.2.3")
        for bad in ["1.2", "01.0.0", "1.0.0-beta", "a.b.c", "1..0", ""] {
            XCTAssertNil(ComponentLibraryVersion(bad), bad)
        }
        XCTAssertLessThan(try XCTUnwrap(ComponentLibraryVersion("1.9.0")), try XCTUnwrap(ComponentLibraryVersion("1.10.0")))
        XCTAssertEqual(ComponentLibraryVersion.initial.nextMinor.description, "1.1.0")
        XCTAssertEqual(ComponentLibraries.requirementIDs, Set((1...8).map { String(format: "SF-0906-%03d", $0) }))
    }

    // SF-1306-001, SF-1306-002, SF-1306-003, SF-1306-004, SF-1306-007 (OD-043, ADR-0040)
    func testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded() throws {
        let rootID = NodeID(), heroID = NodeID(), cardID = NodeID(), footerID = NodeID()
        let oldID = NodeID(), badgeID = NodeID(), newID = NodeID()
        let aboutID = PageID(), retiredID = PageID(), addedID = PageID()
        let tokenID = ColorTokenID()
        let textProperty = NodeProperty(key: PropertyKey(rawValue: "text.content"), value: .string("Hello"))
        let widthProperty = NodeProperty(key: PropertyKey(rawValue: "geometry.width"), value: .number(320))
        func comparisonNode(_ id: NodeID, _ name: String, parent: NodeParent, children: [NodeID] = [],
                            properties: [NodeProperty] = []) -> DocumentNode {
            DocumentNode(id: id, kind: .frame, name: name, parent: parent, childIDs: children, properties: properties)
        }
        func comparisonSource(_ document: CanonicalDocument, _ name: String) -> ProjectComparisonSource {
            ProjectComparisonSource(snapshotID: nil, name: name, document: document)
        }
        let baselineHome = DocumentPage(id: pageID, name: "Home", route: PageRoute(rawValue: "/"), role: .home,
            rootNodeIDs: [rootID], nodes: [
                comparisonNode(rootID, "Root", parent: .page(pageID), children: [heroID, cardID, footerID, oldID]),
                comparisonNode(heroID, "Hero", parent: .node(rootID), children: [badgeID], properties: [textProperty]),
                comparisonNode(badgeID, "Badge", parent: .node(heroID)),
                comparisonNode(cardID, "Box", parent: .node(rootID), properties: [widthProperty]),
                comparisonNode(footerID, "Footer", parent: .node(rootID)),
                comparisonNode(oldID, "Old", parent: .node(rootID)),
            ])
        var editedText = textProperty
        editedText.value = .string("Hi")
        // Same key and value, new identity: a re-created property.
        let recreatedWidth = NodeProperty(key: widthProperty.key, value: .number(320))
        let targetHome = DocumentPage(id: pageID, name: "Home", route: PageRoute(rawValue: "/"), role: .home,
            rootNodeIDs: [rootID], nodes: [
                comparisonNode(rootID, "Root", parent: .page(pageID), children: [heroID, footerID, cardID, newID]),
                comparisonNode(heroID, "Hero", parent: .node(rootID), properties: [editedText]),
                comparisonNode(cardID, "Card", parent: .node(rootID), children: [badgeID], properties: [recreatedWidth]),
                comparisonNode(badgeID, "Badge", parent: .node(cardID)),
                comparisonNode(footerID, "Footer", parent: .node(rootID)),
                comparisonNode(newID, "New", parent: .node(rootID)),
            ])
        let about = DocumentPage(id: aboutID, name: "About")
        var renamedAbout = about
        renamedAbout.name = "About Us"
        let brand = LocalColorToken(id: tokenID, name: "Brand", color: CanonicalSolidColor(red: 1, green: 0, blue: 0, alpha: 1))
        let primary = LocalColorToken(id: tokenID, name: "Primary", color: CanonicalSolidColor(red: 0, green: 0, blue: 1, alpha: 1))
        let baseline = CanonicalDocument(id: documentID, revision: 3,
            pages: [baselineHome, about, DocumentPage(id: retiredID, name: "Retired")], colorTokens: [brand])
        let target = CanonicalDocument(id: documentID, revision: 9,
            pages: [renamedAbout, targetHome, DocumentPage(id: addedID, name: "Added")], colorTokens: [primary])

        let comparison = try ProjectComparer.compare(comparisonSource(baseline, "Launch"),
                                                     with: comparisonSource(target, ProjectComparisonSource.currentDocumentName))
        func changes(_ area: ProjectComparisonArea, _ kind: ProjectComparisonChangeKind) -> [ProjectComparisonChange] {
            comparison.filtered(area: area, kind: kind)
        }
        XCTAssertEqual(changes(.pages, .removed).map(\.pageID), [retiredID])
        XCTAssertEqual(changes(.pages, .added).map(\.pageID), [addedID])
        XCTAssertEqual(changes(.pages, .moved).map(\.pageID), [aboutID], "Only the page that changed place moves")
        XCTAssertEqual(changes(.pages, .changed).map(\.before), ["About"])
        XCTAssertEqual(changes(.pages, .changed).map(\.after), ["About Us"])
        XCTAssertEqual(changes(.layers, .removed).map(\.nodeID), [oldID])
        XCTAssertEqual(changes(.layers, .added).map(\.nodeID), [newID])
        XCTAssertEqual(Set(changes(.layers, .moved).compactMap(\.nodeID)), [footerID, badgeID],
                       "Removing and inserting siblings does not move their neighbours")
        let badge = try XCTUnwrap(changes(.layers, .moved).first { $0.nodeID == badgeID })
        XCTAssertEqual(badge.subject, "Container")
        XCTAssertEqual(badge.before, "Hero")
        XCTAssertEqual(badge.after, "Card")
        XCTAssertEqual(changes(.layers, .moved).first { $0.nodeID == footerID }?.subject, "Layer order")
        XCTAssertEqual(changes(.layers, .changed).map(\.subject), ["Layer name"])
        XCTAssertEqual(changes(.properties, .changed).map(\.before), ["\"Hello\""])
        XCTAssertEqual(changes(.properties, .changed).map(\.after), ["\"Hi\""])
        XCTAssertEqual(changes(.properties, .removed).map(\.before), ["320"],
                       "A re-created property is removed and added, never matched by its key")
        XCTAssertEqual(changes(.properties, .added).map(\.after), ["320"])
        XCTAssertEqual(changes(.colorTokens, .changed).map(\.subject), ["Token name", "Token color"])
        XCTAssertEqual(changes(.colorTokens, .changed).last?.after, "#0000FF")
        XCTAssertEqual(comparison.changes.map(\.id), Array(comparison.changes.indices))
        XCTAssertEqual(comparison.baselineRevision, 3)
        XCTAssertEqual(comparison.targetRevision, 9)
        XCTAssertFalse(comparison.isTruncated)
        XCTAssertEqual(comparison.filtered(query: "about us").map(\.pageID), [aboutID, aboutID])
        let again = try ProjectComparer.compare(comparisonSource(baseline, "Launch"),
                                                with: comparisonSource(target, ProjectComparisonSource.currentDocumentName))
        XCTAssertEqual(again, comparison, "The same two versions always give the same comparison")

        let report = comparison.report()
        XCTAssertTrue(report.contains("- Baseline: Launch (revision 3)"))
        XCTAssertTrue(report.contains("- Compared with: Current Document (revision 9)"))
        XCTAssertTrue(report.contains("## Layers"))
        XCTAssertTrue(report.contains("no viewport, data or font context"))
        XCTAssertFalse(report.contains("## Images"), "Areas without changes are left out")

        let identical = try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(target, "B"))
        XCTAssertTrue(identical.isIdentical)
        XCTAssertEqual(identical.countSummary, "No differences")
        // Fonts, and data without a dedicated comparison, are never reported as identical.
        var withFont = target
        withFont.fontAssets = [FontAsset(resourceID: ResourceID(), family: "Inter", format: .woff2,
            originalFilename: "inter.woff2", byteCount: 1, contentHash: String(repeating: "c", count: 64))]
        XCTAssertEqual(try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(withFont, "B"))
            .changes.map(\.subject), ["Project fonts"])
        var renumbered = target
        renumbered.revision += 5
        XCTAssertTrue(try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(renumbered, "B")).isIdentical,
                      "A different revision alone is not a change")
        var otherData = target
        otherData.creationKind = .migratedLegacy
        XCTAssertEqual(try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(otherData, "B"))
            .changes.map(\.subject), ["Other project data"])
        // ADR-0122: build settings are named on their own; grid choices stay "Project preferences".
        var withBuild = target
        withBuild.projectPreferences = ProjectPreferences(gridSpacing: 24, build: BuildProfileSettings(profile: .staticRelease))
        XCTAssertEqual(try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(withBuild, "B"))
            .changes.map(\.subject), ["Project preferences", "Build settings"])
        // ADR-0037 Amendment 1: a custom code review alone is a build settings change.
        var reviewedBuild = withBuild
        reviewedBuild.projectPreferences?.build?.reviewedCustomCodeDigest = String(repeating: "d", count: 64)
        XCTAssertEqual(try ProjectComparer.compare(comparisonSource(withBuild, "A"), with: comparisonSource(reviewedBuild, "B"))
            .changes.map(\.subject), ["Build settings"])
        // A page's origin has its own entry, so it is never hidden behind other changes.
        var reorigined = target
        reorigined.pages[0].provenance = .template
        XCTAssertEqual(try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(reorigined, "B"))
            .changes.map(\.subject), ["Page origin"])
        reorigined.creationKind = .migratedLegacy
        XCTAssertEqual(try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(reorigined, "B"))
            .changes.map(\.subject), ["Page origin", "Other project data"])
        // Order-only changes of color tokens (and images, guides) are moves, listed beside other changes.
        let accent = LocalColorToken(name: "Accent", color: CanonicalSolidColor(red: 0, green: 1, blue: 0, alpha: 1))
        var twoTokens = target
        twoTokens.colorTokens = [primary, accent]
        var swappedTokens = twoTokens
        swappedTokens.colorTokens = [accent, primary]
        swappedTokens.pages[0].name = "About Again"
        let reorderedTokens = try ProjectComparer.compare(comparisonSource(twoTokens, "A"), with: comparisonSource(swappedTokens, "B"))
        XCTAssertEqual(reorderedTokens.filtered(area: .colorTokens, kind: .moved).map(\.subject), ["Token order"])
        XCTAssertEqual(reorderedTokens.filtered(area: .colorTokens, kind: .moved).map(\.location), ["Accent"])
        XCTAssertEqual(reorderedTokens.filtered(area: .pages, kind: .changed).map(\.subject), ["Page name"])
        XCTAssertThrowsError(try ProjectComparer.compare(comparisonSource(baseline, "A"),
                                                         with: comparisonSource(CanonicalDocument(), "B"))) {
            XCTAssertEqual($0 as? ProjectComparisonError, .documentMismatch)
        }
        XCTAssertThrowsError(try ProjectComparer.compare(comparisonSource(baseline, "A"), with: comparisonSource(target, "B"),
                                                         checkpoint: { throw CancellationError() })) {
            XCTAssertTrue($0 is CancellationError)
        }

        var crowded = targetHome
        crowded.nodes += (0..<(ProjectComparer.maximumChanges + 10)).map {
            comparisonNode(NodeID(), "Item \($0)", parent: .node(rootID))
        }
        var large = target
        large.pages[1] = crowded
        let bounded = try ProjectComparer.compare(comparisonSource(baseline, "A"), with: comparisonSource(large, "B"))
        XCTAssertTrue(bounded.isTruncated)
        XCTAssertFalse(bounded.isIdentical)
        XCTAssertEqual(bounded.changes.count, ProjectComparer.maximumChanges)
        XCTAssertTrue(bounded.countSummary.hasSuffix("only the first \(ProjectComparer.maximumChanges) are listed"))
        // SF-1306-007: the large fixture (10,000 layers) checks for cancellation at least every 256 layers.
        var comparisonChecks = 0
        var tenThousand = target
        tenThousand.pages[1].nodes += (0..<10_000).map { comparisonNode(NodeID(), "Bulk \($0)", parent: .node(rootID)) }
        let largeFixture = try ProjectComparer.compare(comparisonSource(target, "A"), with: comparisonSource(tenThousand, "B"),
                                                       checkpoint: { comparisonChecks += 1 })
        XCTAssertTrue(largeFixture.isTruncated)
        XCTAssertGreaterThanOrEqual(comparisonChecks, 10_000 / 256)

        XCTAssertEqual(ProjectComparer.movedIdentifiers(from: [1, 2, 3, 4], to: [0, 1, 2, 3, 4]), [], "An insertion moves nothing")
        XCTAssertEqual(ProjectComparer.movedIdentifiers(from: [1, 2, 3, 4], to: [4, 1, 2, 3]), [4])
        XCTAssertEqual(ProjectComparer.valueText(.number(12)), "12")
        XCTAssertEqual(ProjectComparer.valueText(.number(0.5)), "0.5")
        XCTAssertEqual(ProjectComparer.valueText(.boolean(true)), "true")
        let long = ProjectComparer.valueText(.string(String(repeating: "a", count: 400) + "\nend"))
        XCTAssertTrue(long.hasSuffix("…\""))
        XCTAssertFalse(long.contains("\n"))
        XCTAssertEqual(ProjectComparer.requirementIDs, Set((1...8).map { String(format: "SF-1306-%03d", $0) }))
    }

    // SF-0309-001, SF-0309-003, SF-0309-004, SF-0309-008 (ADR-0130)
    func testDocumentMigrationRegistryIsContiguousAndDryRunReportsWithoutContent() throws {
        XCTAssertNoThrow(try DocumentMigrations.validateRegistry())
        XCTAssertEqual(DocumentMigrations.steps.count,
                       DocumentSerializer.currentSchemaVersion - DocumentSerializer.minimumSupportedSchemaVersion)
        XCTAssertEqual(try DocumentMigrations.path(from: DocumentSerializer.currentSchemaVersion), [])
        XCTAssertEqual(try DocumentMigrations.path(from: DocumentSerializer.currentSchemaVersion - 2).map(\.toSchema),
                       [DocumentSerializer.currentSchemaVersion - 1, DocumentSerializer.currentSchemaVersion])
        let newer = DocumentSerializer.currentSchemaVersion + 1
        XCTAssertThrowsError(try DocumentMigrations.path(from: newer)) {
            XCTAssertEqual($0 as? DocumentMigrationRefusal, .newerSchema(newer))
        }
        XCTAssertThrowsError(try DocumentMigrations.path(from: 0)) {
            XCTAssertEqual($0 as? DocumentMigrationRefusal, .unsupportedSchema(0))
        }

        let packageBytes = try legacyGolden(
            named: "schema-v1-rootless",
            sha256: "ef1455c5eb9055ec97fb5d41562686226e9db040313a4609e769cc5f7f44694d"
        )
        let stored = try ProjectPackageStore.storedDocument(in: packageBytes)
        XCTAssertEqual(stored.schemaVersion, 1)
        let identifiers = DocumentMigrations.storedIdentifiers(in: stored.data)
        XCTAssertEqual(identifiers.pages, ["31000000-0000-0000-0000-000000000002"])
        XCTAssertEqual(identifiers.nodes, [])
        let report = try DocumentMigrations.dryRun(stored.data)
        XCTAssertEqual(report, try DocumentMigrations.dryRun(stored.data), "A dry run is deterministic")
        XCTAssertEqual(report.sourceSchemaVersion, 1)
        XCTAssertEqual(report.targetSchemaVersion, DocumentSerializer.currentSchemaVersion)
        XCTAssertEqual(report.steps, DocumentMigrations.steps)
        XCTAssertEqual(report.sourcePageCount, 1)
        XCTAssertEqual(report.migratedPageCount, 1)
        XCTAssertEqual(report.addedNodeCount, 1, "Only the minimum root is added")
        XCTAssertEqual(report.sourceByteCount, stored.data.count)
        XCTAssertEqual(report.stepLines.count, report.steps.count)
        XCTAssertTrue(report.summary.contains("schema 1 to \(DocumentSerializer.currentSchemaVersion)"))
        XCTAssertFalse(report.summary.contains("Legacy Landing"), "Reports hold counts, never content")

        // The schema-2 golden needs one step fewer and adds nothing.
        let schemaTwo = try ProjectPackageStore.storedDocument(in: try legacyGolden(
            named: "schema-v2-minimum",
            sha256: "c2ebf92c01924cccd9fe6db5a48bbe4d23a6273d03526f41ed5f744efcbe7739"
        ))
        let twoReport = try DocumentMigrations.dryRun(schemaTwo.data)
        XCTAssertEqual(twoReport.steps.first?.fromSchema, 2)
        XCTAssertEqual(twoReport.steps.count, DocumentSerializer.currentSchemaVersion - 2)
        XCTAssertEqual(twoReport.addedPageCount + twoReport.addedNodeCount, 0)

        // Refusals: a newer schema and damaged data; each names a recovery action.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: stored.data) as? [String: Any])
        object["schemaVersion"] = newer
        let newerData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try DocumentMigrations.dryRun(newerData)) {
            XCTAssertEqual($0 as? DocumentMigrationRefusal, .newerSchema(newer))
        }
        for damaged in [Data("{}".utf8), Data("not json".utf8)] {
            XCTAssertThrowsError(try DocumentMigrations.dryRun(damaged)) {
                XCTAssertEqual($0 as? DocumentMigrationRefusal, .malformed)
            }
        }
        object["schemaVersion"] = 1
        object["document"] = ["id": "not-a-uuid"]
        let broken = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try DocumentMigrations.dryRun(broken)) {
            XCTAssertEqual($0 as? DocumentMigrationRefusal, .malformed)
        }
        let refusals: [DocumentMigrationRefusal] = [
            .newerSchema(newer), .unsupportedSchema(0), .malformed, .lostContent(pages: 1, nodes: 2), .unstableResult,
        ]
        for refusal in refusals {
            XCTAssertNotNil(refusal.recoverySuggestion)
            XCTAssertNotNil(refusal.errorDescription)
        }
        XCTAssertEqual(Set(refusals.map(\.diagnosticCategory)).count, refusals.count)
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
            compatibility["minimumDocumentSchemaVersion"] = DocumentSerializer.currentSchemaVersion + 1
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
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "siteforge.b64", subdirectory: "Legacy"))
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

private func applyStructuralDefaultsForPackageTest(kind: NodeKind, node: inout DocumentNode) {
    let values: [(String, PropertyValue)] = switch kind {
    case .section:
        [("layout.container.kind", .string("section")), ("layout.padding", .number(48)), ("layout.axis", .string("vertical"))]
    case .stack:
        [("layout.container.kind", .string("stack")), ("layout.axis", .string("vertical")),
         ("layout.padding", .number(24)), ("layout.gap", .number(24)), ("layout.align", .string("start"))]
    case .grid:
        [("layout.container.kind", .string("grid")), ("layout.padding", .number(24)),
         ("layout.gap", .number(24)), ("layout.grid.columns", .number(2)),
         ("layout.grid.placement", .string("row-major"))]
    case .frame, .text, .image, .button, .link, .form, .component: []
    }
    node.properties.append(contentsOf: values.map {
        NodeProperty(key: .init(rawValue: $0.0), value: $0.1, origin: .defaulted)
    })
}
