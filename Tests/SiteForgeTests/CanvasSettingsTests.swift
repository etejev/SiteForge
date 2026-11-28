import XCTest
@testable import SiteForge

@MainActor
final class CanvasSettingsTests: XCTestCase {
    // SF-0206-003/005: saved new-workspace defaults, never project data.
    func testCanvasCancelReloadsExternalDefaultWithoutReplayingOldHistory() throws {
        try withStore { defaults, store in
            let project = try DocumentSerializer.encode(ProjectCreation.blank())
            store.begin(); store.choose(false); XCTAssertTrue(store.apply())
            let count = store.transactions.count
            store.choose(true)
            let external = try JSONEncoder().encode(CanvasGridPreferenceRecord(visibleByDefault: true))
            defaults.set(external, forKey: CanvasSettingsStore.storageKey)
            XCTAssertFalse(store.apply()); store.cancel()
            XCTAssertTrue(store.choice); XCTAssertFalse(store.isDirty); XCTAssertFalse(store.canRestore)
            store.restorePrevious()
            XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), external)
            XCTAssertEqual(store.transactions.count, count)
            XCTAssertTrue(CanvasSettingsStore.committedGridVisibility(defaults: defaults))
            XCTAssertEqual(try DocumentSerializer.decode(project).revision, 0)
        }
    }

    private func withStore(_ body: (UserDefaults, CanvasSettingsStore) throws -> Void) rethrows {
        let name = "SiteForge.CanvasSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, CanvasSettingsStore(defaults: defaults))
    }

    // SF-0206-003/004: old/future records stay intact until explicit repair.
    func testGridDefaultStrictRecordFallbackAndExplicitReset() throws {
        let valid = CanvasGridPreferenceRecord(visibleByDefault: false)
        let encoded = try JSONEncoder().encode(valid)
        XCTAssertEqual(CanvasGridPreferenceRecord.decode(encoded), valid)
        for json in [
            "{}",
            "{\"version\":2,\"preferenceID\":\"application.canvas.gridVisibleByDefault\",\"origin\":\"authored\",\"visibleByDefault\":false}",
            "{\"version\":1,\"preferenceID\":\"wrong\",\"origin\":\"authored\",\"visibleByDefault\":false}",
            "{\"version\":1,\"preferenceID\":\"application.canvas.gridVisibleByDefault\",\"origin\":\"authored\",\"visibleByDefault\":\"no\"}",
        ] {
            let data = Data(json.utf8)
            XCTAssertNil(CanvasGridPreferenceRecord.decode(data))
            withStore { defaults, _ in
                defaults.set(data, forKey: CanvasSettingsStore.storageKey)
                let store = CanvasSettingsStore(defaults: defaults)
                XCTAssertTrue(store.resolved)
                XCTAssertTrue(store.status.contains("unavailable"))
                store.begin(); store.choose(false); store.cancel()
                XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), data)
                store.reset(); XCTAssertTrue(store.apply())
                XCTAssertNil(defaults.object(forKey: CanvasSettingsStore.storageKey))
                store.restorePrevious()
                XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), data)
            }
        }
    }

    // SF-0206-002/003/004: drafts and an external revision do not alter scenes.
    func testGridDefaultDraftCancelStaleAndNewWorkspaceIsolation() throws {
        try withStore { defaults, store in
            let existing = WorkspaceDocumentContext(initialWorldGridVisible: store.resolved)
            XCTAssertTrue(existing.shellState.isWorldGridVisible)
            let revision = existing.shellState.documentSession.document.revision
            store.begin(); store.choose(false)
            XCTAssertTrue(store.resolved)
            XCTAssertTrue(existing.shellState.isWorldGridVisible)
            store.cancel()
            XCTAssertTrue(store.resolved)
            XCTAssertTrue(store.transactions.isEmpty)

            store.choose(false)
            let external = try JSONEncoder().encode(CanvasGridPreferenceRecord(visibleByDefault: true))
            defaults.set(external, forKey: CanvasSettingsStore.storageKey)
            XCTAssertFalse(store.apply())
            XCTAssertEqual(store.lastDiagnostic.failureCategory, "stale-context")
            XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), external)
            store.close(); store.begin(); store.choose(false)
            XCTAssertTrue(store.apply())
            XCTAssertFalse(CanvasSettingsStore.committedGridVisibility(defaults: defaults))
            let fresh = WorkspaceDocumentContext(initialWorldGridVisible:
                CanvasSettingsStore.committedGridVisibility(defaults: defaults))
            XCTAssertFalse(fresh.shellState.isWorldGridVisible)
            XCTAssertTrue(existing.shellState.isWorldGridVisible)
            existing.shellState.isWorldGridVisible = false
            fresh.shellState.isWorldGridVisible = true
            XCTAssertFalse(existing.shellState.isWorldGridVisible)
            XCTAssertTrue(fresh.shellState.isWorldGridVisible)
            XCTAssertEqual(existing.shellState.documentSession.document.revision, revision)
            XCTAssertEqual(fresh.shellState.documentSession.document.revision, 0)
        }
    }

    // SF-0206-006/008: one app-local commit has an exact restoration record.
    func testGridDefaultApplyResetRestoreAndRelaunchPersistence() {
        withStore { defaults, store in
            defaults.set("unrelated", forKey: "other.preference")
            store.begin(); store.choose(false)
            XCTAssertTrue(store.apply())
            let authored = defaults.data(forKey: CanvasSettingsStore.storageKey)
            XCTAssertNotNil(authored)
            XCTAssertEqual(store.transactions.count, 1)
            XCTAssertNil(store.transactions[0].before)
            XCTAssertEqual(store.transactions[0].after, authored)
            XCTAssertFalse(CanvasSettingsStore(defaults: defaults).resolved)
            store.reset(); XCTAssertTrue(store.apply())
            XCTAssertNil(defaults.data(forKey: CanvasSettingsStore.storageKey))
            store.restorePrevious()
            XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), authored)
            XCTAssertFalse(store.resolved)
            XCTAssertEqual(defaults.string(forKey: "other.preference"), "unrelated")
            XCTAssertEqual(store.lastDiagnostic.requirementID, "SF-0206-008")
            XCTAssertEqual(store.lastDiagnostic.failureCategory, "none")
        }
    }

    // SF-0206-002/004: the two implemented application defaults reset as one
    // reversible group while document state and unrelated keys stay untouched.
    func testApplicationDefaultGroupResetRestoreAndRelaunch() throws {
        let name = "SiteForge.ApplicationGroupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let appearance = AppearanceSettingsStore(defaults: defaults, present: { _ in })
        let canvas = CanvasSettingsStore(defaults: defaults)
        let group = ApplicationSettingsGroupStore(defaults: defaults, appearance: appearance, canvas: canvas)
        let document = CanonicalDocument()
        defaults.set("unrelated", forKey: "other.preference")

        appearance.begin(); appearance.preview(.dark); XCTAssertTrue(appearance.apply())
        canvas.begin(); canvas.choose(false); XCTAssertTrue(canvas.apply())
        let previousAppearance = defaults.data(forKey: AppearanceSettingsStore.storageKey)
        let previousCanvas = defaults.data(forKey: CanvasSettingsStore.storageKey)
        XCTAssertNotNil(previousAppearance); XCTAssertNotNil(previousCanvas)

        group.stageReset()
        XCTAssertTrue(group.isPending)
        group.cancel()
        XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), previousAppearance)
        XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), previousCanvas)
        XCTAssertTrue(group.transactions.isEmpty)

        group.stageReset(); XCTAssertTrue(group.commitReset())
        XCTAssertNil(defaults.data(forKey: AppearanceSettingsStore.storageKey))
        XCTAssertNil(defaults.data(forKey: CanvasSettingsStore.storageKey))
        XCTAssertEqual(group.transactions.count, 1)
        XCTAssertEqual(group.transactions[0].before.appearance, previousAppearance)
        XCTAssertEqual(group.transactions[0].before.canvas, previousCanvas)
        XCTAssertEqual(appearance.resolved, .dark)
        XCTAssertTrue(canvas.resolved)
        XCTAssertTrue(group.restorePrevious())
        XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), previousAppearance)
        XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), previousCanvas)
        XCTAssertEqual(group.transactions.count, 2)
        XCTAssertEqual(AppearanceSettingsStore.committedAppearance(defaults: defaults), .dark)
        XCTAssertFalse(CanvasSettingsStore.committedGridVisibility(defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: "other.preference"), "unrelated")
        XCTAssertEqual(document.revision, 0)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
    }

    // SF-0206-004/008: draft, stale, and future-record paths are neutral.
    func testApplicationDefaultGroupRejectsDraftAndStaleStorageWithoutMutation() {
        let name = "SiteForge.ApplicationGroupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let appearance = AppearanceSettingsStore(defaults: defaults, present: { _ in })
        let canvas = CanvasSettingsStore(defaults: defaults)
        let group = ApplicationSettingsGroupStore(defaults: defaults, appearance: appearance, canvas: canvas)
        let future = Data("{\"version\":9,\"preferenceID\":\"future\"}".utf8)
        defaults.set(future, forKey: AppearanceSettingsStore.storageKey)
        appearance.begin(); canvas.begin()
        canvas.choose(false)
        group.stageReset()
        XCTAssertFalse(group.isPending)
        XCTAssertEqual(group.failureCategory, "unsaved-draft")
        XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), future)
        canvas.cancel()

        group.stageReset()
        XCTAssertTrue(group.isPending)
        defaults.set(Data("external".utf8), forKey: CanvasSettingsStore.storageKey)
        XCTAssertFalse(group.commitReset())
        XCTAssertEqual(group.failureCategory, "stale-or-unavailable")
        XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), future)
        XCTAssertEqual(defaults.data(forKey: CanvasSettingsStore.storageKey), Data("external".utf8))
        XCTAssertTrue(group.transactions.isEmpty)
        group.cancel()
        appearance.begin(); canvas.begin()
        group.stageReset()
        XCTAssertTrue(group.commitReset())
        XCTAssertNil(defaults.data(forKey: AppearanceSettingsStore.storageKey))
        XCTAssertNil(defaults.data(forKey: CanvasSettingsStore.storageKey))
        XCTAssertTrue(group.restorePrevious())
        XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), future)
    }

    // SF-0206-001/003/004: project preferences are closed, versioned data whose
    // omitted fields follow this Mac, then SiteForge. An authored value equal to
    // a default stays authored; invalid input is rejected, never clamped.
    func testProjectPreferencesResolutionPrecedenceValidationAndStrictCoding() throws {
        XCTAssertEqual(ProjectPreferenceResolver.gridVisibleOnOpen(nil, applicationDefault: nil),
                       .init(value: true, source: .builtIn))
        XCTAssertEqual(ProjectPreferenceResolver.gridVisibleOnOpen(nil, applicationDefault: false),
                       .init(value: false, source: .application))
        XCTAssertEqual(ProjectPreferenceResolver.gridVisibleOnOpen(.init(gridVisibleOnOpen: true), applicationDefault: false),
                       .init(value: true, source: .project))
        XCTAssertEqual(ProjectPreferenceResolver.gridVisibleOnOpen(.init(gridSpacing: 24), applicationDefault: false),
                       .init(value: false, source: .application), "An unrelated authored field does not change Grid precedence")
        XCTAssertEqual(ProjectPreferenceResolver.gridSpacing(nil), .init(value: 16, source: .builtIn))
        XCTAssertEqual(ProjectPreferenceResolver.gridSpacing(.init(gridSpacing: 16)), .init(value: 16, source: .project),
                       "An authored 16 pt is distinct from the SiteForge default")
        XCTAssertEqual(ProjectPreferenceResolver.gridSpacing(.init(gridSpacing: 24)), .init(value: 24, source: .project))
        XCTAssertEqual(ProjectPreferenceResolver.gridSpacing(.init(gridSpacing: 7.5)), .init(value: 16, source: .invalidProjectValue),
                       "A stored value that breaks its rule is reported, then the SiteForge default is used")
        XCTAssertEqual(ProjectPreferenceResolver.gridSpacing(.init(gridSpacing: 512)).source, .invalidProjectValue)

        // Stable identity, rule violations and change sets name preferences, not values.
        XCTAssertEqual(ProjectPreferenceID.allCases.map(\.rawValue),
                       ["project.canvas.gridVisibleOnOpen", "project.canvas.gridSpacing"])
        XCTAssertEqual(Set(ProjectPreferenceID.allCases.map(\.title)).count, ProjectPreferenceID.allCases.count)
        XCTAssertEqual(ProjectPreferences(gridSpacing: 200).invalidPreferenceIDs, [.gridSpacing])
        XCTAssertTrue(ProjectPreferences(gridSpacing: 200).isStructurallyValid)
        XCTAssertFalse(ProjectPreferences(gridSpacing: 200).isValid)
        XCTAssertFalse(ProjectPreferences(gridSpacing: .infinity).isStructurallyValid)
        XCTAssertTrue(ProjectPreferences(gridVisibleOnOpen: true).invalidPreferenceIDs.isEmpty)
        XCTAssertEqual(ProjectPreferences(gridVisibleOnOpen: true, gridSpacing: 24)
            .changedPreferenceIDs(from: .init(gridVisibleOnOpen: true)), [.gridSpacing])
        XCTAssertEqual(ProjectPreferences(gridVisibleOnOpen: false).changedPreferenceIDs(from: nil), [.gridVisibleOnOpen])
        XCTAssertTrue(ProjectPreferences(gridSpacing: 12).changedPreferenceIDs(from: .init(gridSpacing: 12)).isEmpty)

        XCTAssertTrue(ProjectPreferences().isEmpty)
        XCTAssertEqual(ProjectPreferences().version, ProjectPreferences.currentVersion)
        XCTAssertFalse(ProjectPreferences(gridVisibleOnOpen: false).isEmpty)
        for valid in [4.0, 16.0, 128.0] {
            XCTAssertTrue(ProjectPreferences(gridSpacing: valid).isValid, "\(valid)")
        }
        for invalid in [Double.nan, Double.infinity, 3.0, 129.0, 7.5, -16.0] {
            XCTAssertFalse(ProjectPreferences(gridSpacing: invalid).isValid, "\(invalid)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(ProjectPreferences(gridSpacing: 24)), as: UTF8.self),
                       "{\"gridSpacing\":24,\"version\":1}", "Unset fields are omitted, never null")
        let complete = ProjectPreferences(gridVisibleOnOpen: false, gridSpacing: 12)
        XCTAssertEqual(try JSONDecoder().decode(ProjectPreferences.self, from: encoder.encode(complete)), complete)
        XCTAssertEqual(try JSONDecoder().decode(ProjectPreferences.self, from: Data("{\"version\":1}".utf8)), ProjectPreferences())
        for json in [
            "{}",
            "{\"version\":2}",
            "{\"version\":1,\"gridSpacing\":null}",
            "{\"version\":1,\"gridVisibleOnOpen\":null}",
            "{\"version\":1,\"gridColor\":\"red\"}",
            "{\"version\":1,\"gridVisibleOnOpen\":\"yes\"}",
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(ProjectPreferences.self, from: Data(json.utf8)), json)
        }
    }

    // SF-0206-001/004/005: schema 22 carries the record only when something is
    // set. A schema-21 project reopens unchanged; an older envelope, explicit
    // null, unknown key, empty or invalid record is rejected without repair.
    func testProjectPreferencesDocumentSchemaGateAndBackwardCompatibleReopen() throws {
        var document = ProjectCreation.blank()
        let plain = try DocumentSerializer.encode(document)
        XCTAssertGreaterThanOrEqual(DocumentSerializer.currentSchemaVersion, ProjectPreferences.documentSchema)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("projectPreferences"))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        legacy["schemaVersion"] = 21
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)), document)

        document.projectPreferences = .init(gridVisibleOnOpen: false, gridSpacing: 24)
        try document.validate()
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, DocumentSerializer.currentSchemaVersion)
        for older in [21, 20, 17] {
            envelope["schemaVersion"] = older
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "\(older)")
        }
        envelope["schemaVersion"] = DocumentSerializer.currentSchemaVersion
        let current = envelope
        func decode(_ change: (inout [String: Any]) -> Void) throws -> CanonicalDocument {
            var copy = current
            var body = try XCTUnwrap(copy["document"] as? [String: Any])
            change(&body)
            copy["document"] = body
            let document = try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: copy))
            try document.validate()
            return document
        }
        XCTAssertEqual(try decode { _ in }, document)
        XCTAssertThrowsError(try decode { $0["projectPreferences"] = NSNull() })
        XCTAssertThrowsError(try decode { $0["projectPreferences"] = ["version": 1] as [String: Any] },
                             "An empty record is stored as no preferences")
        // SF-0206-004: a value that breaks its rule never makes the project
        // unopenable. It is retained exactly and resolution falls back.
        for stored in [7.5, 200.0, 0.0, -16.0] {
            let reopened = try decode { $0["projectPreferences"] = ["version": 1, "gridSpacing": stored] as [String: Any] }
            XCTAssertEqual(reopened.projectPreferences?.gridSpacing, stored)
            XCTAssertEqual(reopened.projectPreferences?.invalidPreferenceIDs, [.gridSpacing])
            XCTAssertEqual(ProjectPreferenceResolver.gridSpacing(reopened.projectPreferences),
                           .init(value: ProjectPreferences.defaultGridSpacing, source: .invalidProjectValue))
            XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(reopened)), reopened,
                           "Saving again preserves the stored value until the user repairs it")
        }
        XCTAssertThrowsError(try decode { $0["projectPreferences"] = ["version": 1, "gridSpacing": "16"] as [String: Any] })
        XCTAssertThrowsError(try decode { $0["projectPreferences"] = ["version": 1, "gridSpacing": 24, "theme": "dark"] as [String: Any] })
        XCTAssertThrowsError(try decode { $0["projectPreferences"] = ["version": 2, "gridSpacing": 24] as [String: Any] })
        XCTAssertThrowsError(try decode { $0["unknownProjectSetting"] = true })

        var empty = document
        empty.projectPreferences = ProjectPreferences()
        XCTAssertThrowsError(try empty.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidProjectPreferences) }
        var outOfRange = document
        outOfRange.projectPreferences = .init(gridSpacing: 200)
        XCTAssertNoThrow(try outOfRange.validate(), "A value-rule violation is recoverable, not corrupt")
        var nonFinite = document
        nonFinite.projectPreferences = .init(gridSpacing: .infinity)
        XCTAssertThrowsError(try nonFinite.validate()) { XCTAssertEqual($0 as? ModelValidationError, .invalidProjectPreferences) }
    }

    // SF-0206-004: a stored invalid value stays editable intent. Unrelated
    // preferences can change around it, repair removes it in one transaction,
    // Undo restores it, and no commit can introduce a new invalid value.
    func testProjectPreferencesInvalidStoredValueIsRetainedRepairedAndNeverIntroduced() throws {
        var damaged = ProjectCreation.blank()
        damaged.projectPreferences = .init(gridSpacing: 200)
        let session = DocumentSession(document: damaged)
        let registry = ProjectPreferencesCommandRegistry()
        func prepare(_ edit: ProjectPreferencesEdit) throws -> DocumentCommand {
            try registry.prepare(edit, expectedDocumentID: session.document.id,
                expectedRevision: session.document.revision, document: session.document, isLifecycleAvailable: true)
        }
        try session.execute(prepare(.gridVisibleOnOpen(false)))
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: false, gridSpacing: 200))
        try session.execute(prepare(.gridSpacing(nil)))
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: false))
        XCTAssertThrowsError(try prepare(.gridSpacing(200)),
                             "A repaired invalid value cannot be re-introduced") {
            XCTAssertEqual($0 as? ProjectPreferencesError, .invalidValue)
        }
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences?.gridSpacing, 200, "Undo restores the stored intent")
        try session.redo()
        XCTAssertNil(session.document.projectPreferences?.gridSpacing)

        let state = WorkspaceShellState(documentSession: DocumentSession(document: damaged))
        state.synchronizeProjectPreferences(damaged, applicationGridDefault: nil)
        XCTAssertEqual(state.worldGridSpacing, ProjectPreferences.defaultGridSpacing,
                       "The canvas never draws an invalid interval")
    }

    // Module checklist (preview/export semantics): project preferences are
    // editor-only. Preview planning and static output are byte-identical with
    // and without them, so no compatibility finding is needed.
    func testProjectPreferencesAreEditorOnlyAndNeverChangePreviewOrExportOutput() throws {
        var plain = ProjectCreation.blank()
        plain.websiteMetadata = .init(siteName: "Aurora")
        var preferred = plain
        preferred.projectPreferences = .init(gridVisibleOnOpen: false, gridSpacing: 24)
        try preferred.validate()
        let plainPlan = try MultiPageStaticBuildPlanner.plan(document: plain)
        let preferredPlan = try MultiPageStaticBuildPlanner.plan(document: preferred)
        XCTAssertFalse(plainPlan.files.isEmpty)
        XCTAssertEqual(plainPlan.files.map(\.path), preferredPlan.files.map(\.path))
        XCTAssertEqual(plainPlan.files.map(\.contents), preferredPlan.files.map(\.contents))
        XCTAssertFalse(preferredPlan.files.contains { $0.contents.contains("gridSpacing") || $0.contents.contains("projectPreferences") })
    }

    // SF-0206-001/002/004/005: every project-preference edit is one validated
    // document transaction with an exact inverse; rejected edits never mutate.
    func testProjectPreferencesRegistryUndoRedoAndRejectionsWithoutMutation() throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let registry = ProjectPreferencesCommandRegistry()
        func prepare(_ edit: ProjectPreferencesEdit, revision: UInt64? = nil, documentID: DocumentID? = nil,
                     available: Bool = true, cancelled: Bool = false) throws -> DocumentCommand {
            try registry.prepare(edit, expectedDocumentID: documentID ?? session.document.id,
                expectedRevision: revision ?? session.document.revision, document: session.document,
                isLifecycleAvailable: available,
                lifecycleDisabledReason: available ? nil : "Close Preview before transforming content.",
                cancelled: cancelled)
        }
        XCTAssertEqual(ProjectPreferencesCommandRegistry.requirementIDs.count, 8)
        let original = session.document
        try session.execute(prepare(.gridVisibleOnOpen(false)))
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: false))
        XCTAssertEqual(session.document.pages, original.pages, "Preferences never touch page content")
        let entry = try XCTUnwrap(session.historySnapshot().undoEntries.last)
        XCTAssertEqual(entry.commandName, .setProjectPreferences)
        XCTAssertEqual(entry.label, "Edit Project Preferences")
        XCTAssertEqual(entry.affectedIdentifiers, entry.forward.targets)
        XCTAssertEqual(entry.forward.minimumPersistedHistorySchema, 4)
        XCTAssertEqual(entry.inverse, .setProjectPreferences(.init(documentID: original.id, preferences: nil)))

        try session.execute(prepare(.gridSpacing(24)))
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: false, gridSpacing: 24))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2)
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: false))
        try session.redo()
        XCTAssertEqual(session.document.projectPreferences?.gridSpacing, 24)

        // Clearing every field stores no record.
        try session.execute(prepare(.gridVisibleOnOpen(nil)))
        XCTAssertEqual(session.document.projectPreferences, .init(gridSpacing: 24))
        try session.execute(prepare(.gridSpacing(nil)))
        XCTAssertNil(session.document.projectPreferences)
        try session.execute(prepare(.replace(.init(gridVisibleOnOpen: true, gridSpacing: 16))))
        let committed = session.document.projectPreferences
        try session.execute(prepare(.resetAll))
        XCTAssertNil(session.document.projectPreferences)
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences, committed)

        let before = session.document
        let failures: [(ProjectPreferencesError, () throws -> DocumentCommand)] = [
            (.noChanges, { try prepare(.replace(before.projectPreferences)) }),
            (.noChanges, { try prepare(.gridSpacing(16)) }),
            (.stale, { try prepare(.resetAll, revision: before.revision - 1) }),
            (.stale, { try prepare(.resetAll, documentID: DocumentID()) }),
            (.cancelled, { try prepare(.resetAll, cancelled: true) }),
            (.unavailable("Close Preview before transforming content."), { try prepare(.resetAll, available: false) }),
            (.invalidValue, { try prepare(.gridSpacing(7.5)) }),
            (.invalidValue, { try prepare(.gridSpacing(Double.nan)) }),
            (.invalidValue, { try prepare(.replace(.init(gridSpacing: 256))) }),
        ]
        for (expected, attempt) in failures {
            XCTAssertThrowsError(try attempt()) { XCTAssertEqual($0 as? ProjectPreferencesError, expected) }
            XCTAssertEqual(session.document, before)
        }
        // The command kernel enforces document identity independently.
        let foreign = DocumentCommand.setProjectPreferences(.init(documentID: DocumentID(), preferences: .init(gridSpacing: 32)))
        XCTAssertFalse(CommandRegistry().availability(for: foreign, in: session.document).isEnabled)
        XCTAssertThrowsError(try session.execute(foreign))
        XCTAssertEqual(session.document, before)
    }

    // SF-0206-002/003: an opened project adopts only a Grid value it authored;
    // a changed preference (Apply, Undo, Redo) re-applies the resolved value,
    // while unrelated edits never override the scene-local Grid toggle.
    func testWorkspaceAdoptsAuthoredProjectGridAndKeepsSceneToggleLocal() throws {
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 1, base: 24), 24)
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 0.25, base: 24), 96)
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 8, base: 24), 12)
        XCTAssertEqual(CanvasWorldGridPolicy.majorInterval(for: 1, base: 12), 48)
        for zoom in [0.25, 1.0, 8.0] {
            XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: zoom),
                           CanvasWorldGridPolicy.minorInterval(for: zoom, base: ProjectPreferences.defaultGridSpacing))
        }
        for invalid in [0.0, -4.0, Double.nan, Double.infinity] {
            XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 1, base: invalid), 16)
        }
        // SF-0206-007: a fine base never draws denser than the default grid's
        // densest band, so line count stays bounded at every zoom.
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 1, base: 4), 8)
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 2, base: 4), 4)
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 0.25, base: 4), 32)
        for base in [4.0, 5.0, 8.0, 16.0, 33.0, 128.0] {
            for zoom in [0.25, 0.3, 0.5, 0.75, 1.0, 2.0, 4.0, 4.5, 8.0] {
                let minor = CanvasWorldGridPolicy.minorInterval(for: zoom, base: base)
                XCTAssertGreaterThanOrEqual(minor * zoom, CanvasWorldGridPolicy.minimumScreenSpacing - 0.000_001, "\(base)@\(zoom)")
                XCTAssertEqual(CanvasWorldGridPolicy.majorInterval(for: zoom, base: base), minor * 4)
            }
        }

        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session, initialWorldGridVisible: true)
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertTrue(state.isWorldGridVisible, "A project without preferences keeps the workspace Grid")
        XCTAssertEqual(state.worldGridSpacing, ProjectPreferences.defaultGridSpacing)

        state.isWorldGridVisible = false
        try state.commitProjectPreferences(.replace(.init(gridVisibleOnOpen: true, gridSpacing: 24)),
            expectedDocumentID: session.document.id, expectedPreferences: nil)
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertTrue(state.isWorldGridVisible)
        XCTAssertEqual(state.worldGridSpacing, 24)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)

        // Scene-local toggling and unrelated edits never write or re-apply.
        state.isWorldGridVisible = false
        let committed = session.document.projectPreferences
        let pageID = try XCTUnwrap(session.document.pages.first?.id)
        try session.execute(.renamePage(.init(pageID: pageID, name: "Renamed Home")))
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertFalse(state.isWorldGridVisible)
        XCTAssertEqual(session.document.projectPreferences, committed)
        try session.undo()

        // Undo of the preference follows this Mac again; Redo re-applies it.
        state.isWorldGridVisible = true
        try session.undo()
        XCTAssertNil(session.document.projectPreferences)
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertFalse(state.isWorldGridVisible)
        XCTAssertEqual(state.worldGridSpacing, ProjectPreferences.defaultGridSpacing)
        try session.redo()
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertTrue(state.isWorldGridVisible)
        XCTAssertEqual(state.worldGridSpacing, 24)

        // A spacing-only change never touches the Grid toggle.
        state.isWorldGridVisible = false
        try state.commitProjectPreferences(.gridSpacing(32), expectedDocumentID: session.document.id,
                                           expectedPreferences: session.document.projectPreferences)
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertFalse(state.isWorldGridVisible)
        XCTAssertEqual(state.worldGridSpacing, 32)

        // A reviewed value that is no longer current is stale.
        let reviewed = session.document
        XCTAssertThrowsError(try state.commitProjectPreferences(.resetAll, expectedDocumentID: reviewed.id,
            expectedPreferences: nil)) { XCTAssertEqual($0 as? ProjectPreferencesError, .stale) }
        XCTAssertThrowsError(try state.commitProjectPreferences(.resetAll, expectedDocumentID: DocumentID(),
            expectedPreferences: reviewed.projectPreferences)) { XCTAssertEqual($0 as? ProjectPreferencesError, .stale) }
        XCTAssertEqual(session.document, reviewed)

        // Opening another project adopts only what that project authored.
        try session.establishBaseline(ProjectCreation.blank())
        state.isWorldGridVisible = true
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertTrue(state.isWorldGridVisible, "Opening a project without preferences keeps the scene Grid")
        XCTAssertEqual(state.worldGridSpacing, ProjectPreferences.defaultGridSpacing)
        var authored = ProjectCreation.blank()
        authored.projectPreferences = .init(gridVisibleOnOpen: false, gridSpacing: 12)
        try session.establishBaseline(authored)
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: true)
        XCTAssertFalse(state.isWorldGridVisible)
        XCTAssertEqual(state.worldGridSpacing, 12)
    }

    // SF-1208-001/002/004/005/008, SF-1211-002 (OD-042, ADR-0122): Check Website saves
    // build settings as one undoable project-preferences edit that keeps the grid
    // preferences, refuses a stale review, an invalid budget or no change without
    // touching the project, applies the saved profile, and its repairs are undoable.
    func testBuildSettingsSaveUndoRedoRepairsAndStaleReview() throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session, initialWorldGridVisible: true)
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertEqual(state.staticBuildProfile, .development)
        try state.commitProjectPreferences(.gridSpacing(24), expectedDocumentID: session.document.id,
                                           expectedPreferences: nil)

        let settings = BuildProfileSettings(profile: .staticRelease, pageBudgetKilobytes: 128,
                                            releasePolicy: .warningsBlockRelease)
        XCTAssertTrue(state.saveBuildSettings(settings, reviewed: nil))
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(gridSpacing: 24, build: settings),
                       "Grid preferences are kept")
        XCTAssertEqual(state.staticBuildProfile, .staticRelease, "The saved profile is where Check Website starts")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2)
        XCTAssertEqual(session.historySnapshot().undoEntries.last?.commandName, .setProjectPreferences)
        let diagnostic = try XCTUnwrap(state.lastBuildSettingsDiagnostic)
        XCTAssertEqual(diagnostic.failureCategory, "none")
        XCTAssertEqual(diagnostic.operation, "save-build-settings")
        XCTAssertEqual(diagnostic.settingIDs, ["project.build.profile", "project.build.pageBudget", "project.build.releasePolicy"])
        XCTAssertTrue(diagnostic.requirementIDs.contains("SF-1208-008"))
        XCTAssertFalse(diagnostic.sanitizedDocumentID.contains(session.document.id.description))

        // A stale review, a new invalid budget or no change leaves the project unchanged.
        let saved = session.document
        XCTAssertFalse(state.saveBuildSettings(BuildProfileSettings(pageBudgetKilobytes: 64), reviewed: nil))
        XCTAssertEqual(state.lastBuildSettingsDiagnostic?.failureCategory, "stale-context")
        XCTAssertFalse(state.saveBuildSettings(BuildProfileSettings(pageBudgetKilobytes: -1), reviewed: settings))
        XCTAssertEqual(state.lastBuildSettingsDiagnostic?.failureCategory, "invalid-value")
        XCTAssertFalse(state.saveBuildSettings(settings, reviewed: settings))
        XCTAssertEqual(state.lastBuildSettingsDiagnostic?.failureCategory, "no-changes")
        XCTAssertEqual(session.document, saved)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2)

        // Repairs: each settings repair is one undoable edit; choosing a profile is not an edit.
        XCTAssertTrue(state.applyBuildRepair(.raiseBudget(.page, kilobytes: 300)))
        XCTAssertEqual(session.document.projectPreferences?.build?.pageBudgetKilobytes, 300)
        XCTAssertTrue(state.applyBuildRepair(.allowWarnings))
        XCTAssertEqual(session.document.projectPreferences?.build?.releasePolicy, .errorsOnly)
        XCTAssertEqual(state.lastBuildSettingsDiagnostic?.operation, "repair-build-settings")
        XCTAssertTrue(state.applyBuildRepair(.useProfile(.development)))
        XCTAssertEqual(state.staticBuildProfile, .development)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 4)

        // Undo restores each previous value; Redo re-applies the saved profile.
        try session.undo()
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences?.build, settings)
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(gridSpacing: 24))
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertEqual(state.staticBuildProfile, .development)
        try session.redo()
        state.synchronizeProjectPreferences(session.document, applicationGridDefault: false)
        XCTAssertEqual(state.staticBuildProfile, .staticRelease)
        XCTAssertEqual(session.document.projectPreferences?.build, settings)

        // Save and reopen keep the settings; removing them restores the SiteForge defaults.
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertTrue(state.saveBuildSettings(nil, reviewed: settings))
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(gridSpacing: 24))
        XCTAssertEqual(BuildSettingsResolution(document: session.document).releasePolicy.source, .builtIn)
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences?.build, settings)

        // Settings › Project resets only the preferences it shows; build settings stay.
        let resetSuite = "SiteForge.BuildSettingsResetTests.\(UUID().uuidString)"
        let resetDefaults = try XCTUnwrap(UserDefaults(suiteName: resetSuite))
        defer { resetDefaults.removePersistentDomain(forName: resetSuite) }
        let projectPane = ProjectSettingsStore(defaults: resetDefaults, resolveTarget: { state })
        projectPane.begin()
        projectPane.reset()
        XCTAssertEqual(projectPane.draft, ProjectPreferences(build: settings))
        XCTAssertTrue(projectPane.apply())
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(build: settings))
    }

    // SF-1107-004, SF-1211-002/003/008 (OD-041, OD-042, ADR-0037 amendment): under
    // "Block Static Release on warnings" custom code blocks Static Release until the
    // author marks it as reviewed. The review is one undoable build-settings edit
    // that stores only a digest; the findings stay visible as information; any
    // change to the code blocks release again; a review of earlier code is refused.
    func testCustomCodeReviewUnblocksStrictStaticReleaseUntilTheCodeChanges() throws {
        var document = ProjectCreation.blank()
        let about = DocumentPage(name: "About", route: .init(rawValue: "/about"))
        document.pages.append(about)
        let strict = BuildProfileSettings(profile: .staticRelease, releasePolicy: .warningsBlockRelease)
        document.projectPreferences = ProjectPreferences(build: strict)
        // No search indexing, so the SEO audit adds no warnings of its own.
        document.websiteMetadata = WebsiteMetadata(siteName: "Studio", allowsIndexing: false)
        try document.validate()
        func checkStaticRelease(_ document: CanonicalDocument) -> StaticBuildCompilation {
            StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .staticRelease),
                                        resourceDescriptors: [:], resourceData: [:])
        }
        let plain = checkStaticRelease(document)
        XCTAssertTrue(plain.canWrite, "Precondition, no other warnings: \(plain.findings.map(\.code))")
        XCTAssertEqual(CustomCodeReview.status(document), .noCustomCode)
        XCTAssertNil(CustomCodeReview.digest(document.websiteMetadata))

        let session = DocumentSession(document: document)
        let state = WorkspaceShellState(documentSession: session, initialWorldGridVisible: true)
        let siteCode = CustomCodeBlock(headHTML: "<meta name=\"chat\" content=\"on\">", css: ".chat { color: teal; }")
        let pageCode = CustomCodeBlock(bodyHTML: "<button onclick=\"openChat()\">Chat</button>")
        let coded = WebsiteMetadata(siteName: "Studio", allowsIndexing: false,
            pages: [PageWebsiteMetadata(pageID: about.id, customCode: pageCode)], customCode: siteCode)
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id, metadata: coded)))

        // Not reviewed: its two warnings stop Static Release under the stricter policy.
        let blocked = checkStaticRelease(session.document)
        XCTAssertFalse(blocked.canWrite)
        XCTAssertTrue(blocked.findings.contains { $0.code == "release-policy-warnings" && $0.severity == .error })
        let unvalidated = try XCTUnwrap(blocked.findings.first { $0.code == "custom-code-unvalidated" })
        XCTAssertEqual(unvalidated.severity, .warning)
        XCTAssertEqual(blocked.findings.filter { $0.code == "custom-code-script" }.map(\.severity), [.warning])
        XCTAssertEqual(CustomCodeReview.status(session.document), .notReviewed)
        let digest = try XCTUnwrap(CustomCodeReview.digest(session.document.websiteMetadata))
        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(CustomCodeReview.digest(coded), digest, "Deterministic")
        var moved = coded
        moved.pages = [PageWebsiteMetadata(pageID: session.document.pages[0].id, customCode: pageCode)]
        XCTAssertNotEqual(CustomCodeReview.digest(moved), digest, "Code moved to another page needs its own review")
        var swapped = coded
        swapped.customCode = CustomCodeBlock(bodyHTML: "<meta name=\"chat\" content=\"on\">", css: ".chat { color: teal; }")
        XCTAssertNotEqual(CustomCodeReview.digest(swapped), digest, "Code moved to another field needs its own review")
        let settings = BuildSettingsResolution(document: session.document)
        let action = try XCTUnwrap(StaticBuildRepairAction.action(for: unvalidated, report: blocked.report,
            settings: settings, profile: .staticRelease, customCodeDigest: digest))
        XCTAssertEqual(action, .acknowledgeCustomCode(digest: digest))
        XCTAssertNil(StaticBuildRepairAction.action(for: unvalidated, report: blocked.report, settings: settings,
                                                    profile: .staticRelease), "Without the checked code's digest no review is offered")
        XCTAssertEqual(action.identifier, "acknowledge-custom-code", "The identifier carries no value")
        XCTAssertEqual(action.title, "Mark Custom Code as Reviewed")
        XCTAssertTrue(action.hint.contains("Undo"))

        // Marking it reviewed is one undoable build-settings edit that stores only the digest.
        let undoCount = session.historySnapshot().undoEntries.count
        XCTAssertTrue(state.applyBuildRepair(action))
        XCTAssertEqual(session.document.projectPreferences?.build,
                       BuildProfileSettings(profile: .staticRelease, releasePolicy: .warningsBlockRelease,
                                            reviewedCustomCodeDigest: digest))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, undoCount + 1)
        XCTAssertEqual(session.historySnapshot().undoEntries.last?.commandName, .setProjectPreferences)
        let diagnostic = try XCTUnwrap(state.lastBuildSettingsDiagnostic)
        XCTAssertEqual(diagnostic.operation, "review-custom-code")
        XCTAssertEqual(diagnostic.failureCategory, "none")
        XCTAssertEqual(diagnostic.settingIDs, ["project.build.customCodeReview"])
        XCTAssertEqual(CustomCodeReview.status(session.document), .reviewed)

        // Reviewed: Static Release can be written; both findings stay, as information.
        let allowed = checkStaticRelease(session.document)
        XCTAssertTrue(allowed.canWrite, "\(allowed.findings.map(\.code))")
        XCTAssertFalse(allowed.findings.contains { $0.code == "release-policy-warnings" })
        XCTAssertEqual(allowed.findings.filter { $0.code.hasPrefix("custom-code") }.map(\.severity),
                       [.information, .information])
        let reviewedFinding = try XCTUnwrap(allowed.findings.first { $0.code == "custom-code-unvalidated" })
        XCTAssertTrue(reviewedFinding.explanation.contains("marked as reviewed"))
        XCTAssertNil(StaticBuildRepairAction.action(for: reviewedFinding, report: allowed.report,
            settings: BuildSettingsResolution(document: session.document), profile: .staticRelease,
            customCodeDigest: digest), "Reviewed code needs no repair")
        XCTAssertFalse(allowed.redactedSummary.contains(digest), "Findings carry no digest")
        XCTAssertFalse(allowed.redactedSummary.contains("openChat"), "Findings carry no authored code")
        XCTAssertFalse(state.applyBuildRepair(action), "Marking the same code again changes nothing")
        XCTAssertEqual(state.lastBuildSettingsDiagnostic?.failureCategory, "no-changes")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, undoCount + 1)

        // Undo withdraws the review and blocks release again; Redo restores it.
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences?.build, strict)
        XCTAssertEqual(CustomCodeReview.status(session.document), .notReviewed)
        XCTAssertFalse(checkStaticRelease(session.document).canWrite)
        try session.redo()
        XCTAssertEqual(CustomCodeReview.status(session.document), .reviewed)
        XCTAssertTrue(checkStaticRelease(session.document).canWrite)

        // Save and reopen keep the review. The record holds the digest, never the
        // code; the key is omitted when unset and null is refused.
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        XCTAssertTrue(checkStaticRelease(reopened).canWrite)
        let record = String(decoding: try JSONEncoder().encode(try XCTUnwrap(reopened.projectPreferences?.build)), as: UTF8.self)
        XCTAssertTrue(record.contains("\"reviewedCustomCodeDigest\""))
        XCTAssertTrue(record.contains(digest))
        XCTAssertFalse(record.contains("openChat"))
        var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(strict)) as? [String: Any])
        XCTAssertNil(forged["reviewedCustomCodeDigest"], "Omitted when unset")
        forged["reviewedCustomCodeDigest"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(BuildProfileSettings.self,
                                                      from: JSONSerialization.data(withJSONObject: forged)))

        // Any change to the code ends the review: Static Release is blocked again,
        // and the review of the earlier code cannot be applied to the new code.
        var changed = coded
        changed.customCode = CustomCodeBlock(headHTML: "<meta name=\"chat\" content=\"off\">", css: ".chat { color: teal; }")
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id, metadata: changed)))
        XCTAssertEqual(CustomCodeReview.status(session.document), .changedSinceReview)
        let reblocked = checkStaticRelease(session.document)
        XCTAssertFalse(reblocked.canWrite)
        XCTAssertTrue(reblocked.findings.contains { $0.code == "release-policy-warnings" })
        let changedFinding = try XCTUnwrap(reblocked.findings.first { $0.code == "custom-code-unvalidated" })
        XCTAssertEqual(changedFinding.severity, .warning)
        XCTAssertTrue(changedFinding.explanation.contains("changed after it was marked as reviewed"))
        let beforeStaleReview = session.document
        XCTAssertFalse(state.applyBuildRepair(action), "A review of earlier code is refused")
        XCTAssertEqual(state.lastBuildSettingsDiagnostic?.operation, "review-custom-code")
        XCTAssertEqual(state.lastBuildSettingsDiagnostic?.failureCategory, "stale-context")
        XCTAssertEqual(session.document, beforeStaleReview)
        let newDigest = try XCTUnwrap(CustomCodeReview.digest(session.document.websiteMetadata))
        XCTAssertNotEqual(newDigest, digest)
        XCTAssertTrue(state.applyBuildRepair(.acknowledgeCustomCode(digest: newDigest)))
        XCTAssertTrue(checkStaticRelease(session.document).canWrite)

        // Use SiteForge Defaults resets the settings and keeps the review.
        XCTAssertEqual(session.document.projectPreferences?.build?.keepingCustomCodeReview,
                       BuildProfileSettings(reviewedCustomCodeDigest: newDigest))
        // Development is never blocked by unreviewed custom code.
        var unreviewed = session.document
        unreviewed.projectPreferences = ProjectPreferences(build: strict)
        XCTAssertTrue(StaticBuildCompiler.compile(document: unreviewed, profileSelection: .init(profile: .development),
                                                  resourceDescriptors: [:], resourceData: [:]).canWrite)
    }

    // SF-0206-002/004/006/008: the Settings Project pane edits only the active
    // project, through a draft. Apply is one transaction; Cancel, a stale or
    // different project, invalid input and "no project" leave the document
    // unchanged; diagnostics carry a sanitized identity and no values.
    func testProjectSettingsStoreDraftApplyCancelStaleResetAndNoProject() async throws {
        let name = "SiteForge.ProjectSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        let store = ProjectSettingsStore(defaults: defaults, resolveTarget: { state })
        func drainMainQueue() async {
            let drained = expectation(description: "main queue")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 2)
        }

        store.begin()
        XCTAssertTrue(store.hasProject)
        XCTAssertNil(store.committed)
        XCTAssertNil(store.draft)
        XCTAssertFalse(store.isDirty)
        XCTAssertFalse(store.canApply)
        XCTAssertEqual(store.gridVisibilityResolution, .init(value: true, source: .builtIn))
        XCTAssertTrue(store.gridVisibilityProvenance.hasPrefix("SiteForge default"))
        defaults.set(try JSONEncoder().encode(CanvasGridPreferenceRecord(visibleByDefault: false)),
                     forKey: CanvasSettingsStore.storageKey)
        XCTAssertEqual(store.gridVisibilityResolution, .init(value: false, source: .application))
        XCTAssertTrue(store.gridVisibilityProvenance.contains("this Mac"))
        XCTAssertEqual(store.gridSpacingResolution, .init(value: 16, source: .builtIn))

        // A draft stays in Settings until Apply; invalid input never replaces it.
        store.chooseGridSpacing(24)
        store.chooseGridVisibility(true)
        XCTAssertTrue(store.isDirty)
        XCTAssertTrue(store.canApply)
        XCTAssertTrue(store.gridSpacingProvenance.contains("Draft"))
        XCTAssertNil(session.document.projectPreferences)
        XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
        store.chooseGridSpacing(7.5)
        XCTAssertEqual(store.draft?.gridSpacing, 24)
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "invalid-value")
        XCTAssertTrue(store.apply())
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: true, gridSpacing: 24))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(store.committed, store.draft)
        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(store.gridVisibilityResolution.source, .project)
        XCTAssertEqual(store.lastDiagnostic.requirementIDs, ["SF-0206-001", "SF-0206-002", "SF-0206-005", "SF-0206-008"])
        XCTAssertEqual(store.lastDiagnostic.preferenceIDs, ["project.canvas.gridVisibleOnOpen", "project.canvas.gridSpacing"])
        XCTAssertEqual(store.lastDiagnostic.operation, "set-project-preferences")
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "none")
        let token = try XCTUnwrap(store.lastDiagnostic.sanitizedDocumentID)
        XCTAssertTrue(token.hasPrefix("document-"))
        XCTAssertFalse(token.contains(session.document.id.description))
        await drainMainQueue()
        XCTAssertFalse(store.isStale, "The pane's own commit is not a concurrent change")

        // Cancel restores the saved values without a transaction.
        store.chooseGridVisibility(nil)
        XCTAssertTrue(store.isDirty)
        store.cancel()
        XCTAssertEqual(store.draft, session.document.projectPreferences)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)

        // A concurrent change (Undo in the project) makes a dirty draft stale.
        store.chooseGridSpacing(32)
        try session.undo()
        await drainMainQueue()
        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.canApply)
        let undone = session.document
        XCTAssertFalse(store.apply())
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "stale-context")
        XCTAssertEqual(session.document, undone)
        store.cancel()
        XCTAssertFalse(store.isStale)
        XCTAssertNil(store.draft)

        // A clean pane follows external changes; Reset drafts removing them all.
        try session.redo()
        await drainMainQueue()
        XCTAssertEqual(store.committed, .init(gridVisibleOnOpen: true, gridSpacing: 24))
        XCTAssertFalse(store.isDirty)
        store.reset()
        XCTAssertNil(store.draft)
        XCTAssertTrue(store.isDirty)
        XCTAssertTrue(store.apply())
        XCTAssertNil(session.document.projectPreferences)
        XCTAssertEqual(store.lastDiagnostic.operation, "reset-project-preferences")
        try session.undo()
        await drainMainQueue()
        XCTAssertEqual(store.committed?.gridSpacing, 24)

        // Another project opening in the workspace never inherits a draft.
        store.chooseGridVisibility(false)
        try session.establishBaseline(ProjectCreation.blank())
        await drainMainQueue()
        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.apply())
        XCTAssertNil(session.document.projectPreferences)
        store.cancel()
        XCTAssertNil(store.committed)
        XCTAssertFalse(store.isStale)
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "none")

        // With no project open, the pane explains the first action and is inert.
        let empty = ProjectSettingsStore(defaults: defaults, resolveTarget: { nil })
        empty.begin()
        XCTAssertFalse(empty.hasProject)
        XCTAssertFalse(empty.canApply)
        XCTAssertEqual(empty.status, ProjectSettingsStore.noProjectStatus)
        empty.chooseGridSpacing(24)
        XCTAssertNil(empty.draft)
        XCTAssertFalse(empty.apply())
        XCTAssertEqual(empty.lastDiagnostic.failureCategory, "no-project")
        XCTAssertEqual(empty.lastDiagnostic.requirementIDs, ["SF-0206-004", "SF-0206-008"])
        XCTAssertNil(empty.lastDiagnostic.sanitizedDocumentID)
        XCTAssertEqual(ProjectSettingsStore.requirementIDs(operation: "load", failure: "none"), ["SF-0206-003", "SF-0206-008"])
        XCTAssertEqual(ProjectSettingsStore.requirementIDs(operation: "cancel", failure: "none"), ["SF-0206-002", "SF-0206-008"])
    }

    // SF-0206-004: busy, read-only and invalid states keep the draft, state
    // the governing rule, offer the specific repair, and never mutate silently.
    func testProjectSettingsStoreUnavailableInvalidRepairAndValueFreeDiagnostics() async throws {
        let name = "SiteForge.ProjectSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var damaged = ProjectCreation.blank()
        damaged.projectPreferences = .init(gridSpacing: 200)
        let session = DocumentSession(document: damaged)
        let state = WorkspaceShellState(documentSession: session)
        let store = ProjectSettingsStore(defaults: defaults, resolveTarget: { state })
        func drainMainQueue() async {
            let drained = expectation(description: "main queue")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 2)
        }

        store.begin()
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "invalid-stored-value")
        XCTAssertEqual(store.lastDiagnostic.preferenceIDs, ["project.canvas.gridSpacing"])
        XCTAssertEqual(store.lastDiagnostic.requirementIDs, ["SF-0206-004", "SF-0206-008"])
        XCTAssertTrue(store.status.contains("invalid grid spacing"))
        XCTAssertTrue(store.draftHasInvalidGridSpacing)
        XCTAssertEqual(store.gridSpacingResolution.source, .invalidProjectValue)
        XCTAssertTrue(store.gridSpacingProvenance.contains("4 through 128"))
        XCTAssertTrue(ProjectGridSpacingChoice.options(including: 200).contains(ProjectGridSpacingChoice(200)))
        XCTAssertTrue(ProjectGridSpacingChoice(200).title.contains("invalid"))
        XCTAssertEqual(session.document, damaged, "Loading never rewrites the stored value")

        // Unrelated edits keep the invalid value; re-selecting it is allowed,
        // a new invalid value is not.
        store.chooseGridVisibility(false)
        store.chooseGridSpacing(200)
        XCTAssertEqual(store.draft, .init(gridVisibleOnOpen: false, gridSpacing: 200))
        store.chooseGridSpacing(300)
        XCTAssertEqual(store.draft?.gridSpacing, 200)
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "invalid-value")
        XCTAssertTrue(store.canApply)
        XCTAssertTrue(store.apply())
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: false, gridSpacing: 200))
        await drainMainQueue()

        // Busy lifecycle (Preview open): Apply is blocked with the reason and
        // the draft is kept; closing Preview makes it applicable again.
        store.repairGridSpacing()
        XCTAssertFalse(store.draftHasInvalidGridSpacing)
        XCTAssertEqual(store.lastDiagnostic.operation, "repair-draft")
        XCTAssertEqual(store.lastDiagnostic.requirementIDs, ["SF-0206-004", "SF-0206-008"])
        state.isPreviewPresented = true
        await drainMainQueue()
        XCTAssertFalse(store.canApply)
        XCTAssertEqual(store.unavailableReason?.contains("Close Preview"), true)
        XCTAssertTrue(store.isDirty, "The draft survives the busy state")
        let busy = session.document
        XCTAssertFalse(store.apply())
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "lifecycle-unavailable")
        XCTAssertEqual(session.document, busy)
        state.isPreviewPresented = false
        await drainMainQueue()
        XCTAssertNil(store.unavailableReason)
        XCTAssertTrue(store.canApply)
        XCTAssertTrue(store.apply())
        XCTAssertEqual(session.document.projectPreferences, .init(gridVisibleOnOpen: false))
        XCTAssertEqual(store.lastDiagnostic.preferenceIDs, ["project.canvas.gridSpacing"])
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences?.gridSpacing, 200)

        // Diagnostics carry a sanitized identity, never the raw document ID.
        let recorded = String(describing: store.lastDiagnostic)
        XCTAssertFalse(recorded.contains(session.document.id.description))
        XCTAssertTrue(store.lastDiagnostic.sanitizedDocumentID?.hasPrefix("document-") == true)
    }

    // SF-0206-002/004/005 (ADR-0122, ADR-0140): build settings share the
    // project-preferences record but are edited in Check Website. The Project
    // pane offers Reset only while a grid preference is set, keeps a pending
    // grid draft when only the build settings change, still treats a changed
    // grid preference as a concurrent change, and its Reset keeps the build
    // settings in one undoable transaction.
    func testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges() async throws {
        let name = "SiteForge.ProjectSettingsBuildRebaseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        let store = ProjectSettingsStore(defaults: defaults, resolveTarget: { state })
        func drainBuildRebaseMainQueue() async {
            let drained = expectation(description: "main queue")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 2)
        }

        // Only build settings are stored: the grid follows the defaults and
        // Reset has nothing this pane could remove.
        let settings = BuildProfileSettings(profile: .staticRelease, pageBudgetKilobytes: 128)
        XCTAssertTrue(state.saveBuildSettings(settings, reviewed: nil))
        store.begin()
        XCTAssertEqual(store.committed, ProjectPreferences(build: settings))
        XCTAssertFalse(store.draftHasGridPreferences)
        XCTAssertTrue(store.status.contains("follows this Mac"))

        // A Check Website save while a grid draft is pending keeps the draft
        // on the new build settings; Apply saves both without losing either.
        store.chooseGridSpacing(24)
        XCTAssertTrue(store.draftHasGridPreferences)
        let changed = BuildProfileSettings(profile: .staticRelease, pageBudgetKilobytes: 256)
        XCTAssertTrue(state.saveBuildSettings(changed, reviewed: settings))
        await drainBuildRebaseMainQueue()
        XCTAssertFalse(store.isStale)
        XCTAssertEqual(store.committed, ProjectPreferences(build: changed))
        XCTAssertEqual(store.draft, ProjectPreferences(gridSpacing: 24, build: changed))
        XCTAssertTrue(store.status.contains("Check Website"))
        XCTAssertEqual(store.lastDiagnostic.operation, "rebase-draft")
        XCTAssertEqual(store.lastDiagnostic.requirementIDs, ["SF-0206-002", "SF-0206-008"])
        XCTAssertTrue(store.canApply)
        XCTAssertTrue(store.apply())
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(gridSpacing: 24, build: changed))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 3)
        await drainBuildRebaseMainQueue()

        // A changed grid preference (Undo of the Apply) is still a concurrent change.
        store.chooseGridVisibility(false)
        try session.undo()
        await drainBuildRebaseMainQueue()
        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.apply())
        XCTAssertEqual(store.lastDiagnostic.failureCategory, "stale-context")
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(build: changed))
        store.cancel()
        XCTAssertFalse(store.isStale)
        XCTAssertFalse(store.draftHasGridPreferences)

        // Reset removes only the grid preferences, as one undoable transaction.
        try session.redo()
        await drainBuildRebaseMainQueue()
        XCTAssertEqual(store.committed, ProjectPreferences(gridSpacing: 24, build: changed))
        XCTAssertTrue(store.draftHasGridPreferences)
        store.reset()
        XCTAssertEqual(store.draft, ProjectPreferences(build: changed))
        XCTAssertFalse(store.draftHasGridPreferences)
        XCTAssertTrue(store.isDirty)
        XCTAssertTrue(store.apply())
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(build: changed))
        XCTAssertTrue(store.status.contains("build settings stay"))
        try session.undo()
        XCTAssertEqual(session.document.projectPreferences, ProjectPreferences(gridSpacing: 24, build: changed))

        // ADR-0037 Amendment 1: the custom code review is a build setting too. Marking
        // code as reviewed while a grid draft is pending keeps the draft on top of the
        // review, and the pane's Reset and Apply never withdraw the review.
        await drainBuildRebaseMainQueue()
        XCTAssertEqual(store.committed, ProjectPreferences(gridSpacing: 24, build: changed))
        XCTAssertFalse(store.isDirty)
        store.chooseGridVisibility(true)
        let reviewedBuild = BuildProfileSettings(profile: .staticRelease, pageBudgetKilobytes: 256,
                                                 reviewedCustomCodeDigest: String(repeating: "e", count: 64))
        XCTAssertTrue(state.saveBuildSettings(reviewedBuild, reviewed: changed))
        await drainBuildRebaseMainQueue()
        XCTAssertFalse(store.isStale)
        XCTAssertEqual(store.committed, ProjectPreferences(gridSpacing: 24, build: reviewedBuild))
        XCTAssertEqual(store.draft, ProjectPreferences(gridVisibleOnOpen: true, gridSpacing: 24, build: reviewedBuild))
        XCTAssertEqual(store.lastDiagnostic.operation, "rebase-draft")
        store.reset()
        XCTAssertEqual(store.draft, ProjectPreferences(build: reviewedBuild))
        XCTAssertTrue(store.apply())
        XCTAssertEqual(session.document.projectPreferences?.build?.reviewedCustomCodeDigest,
                       reviewedBuild.reviewedCustomCodeDigest)
    }

    // SF-0206-007: the stress fixture is the documented practical limit, the
    // canonical node budget shared by insertion, layout and rendering, filled
    // exactly with valid single-root pages.
    func testStressFixtureFillsTheDocumentedNodeBudgetExactly() throws {
        XCTAssertEqual(InsertionPolicy.maximumNodeCount, ResolvedGraphPolicy.maximumNodes)
        XCTAssertEqual(InsertionPolicy.maximumNodeCount, LayoutPolicy.maximumNodeCount)
        let clock = ContinuousClock()
        var document = CanonicalDocument()
        let generation = clock.measure { document = WorkspaceFixtureScale.stress.document() }
        XCTAssertEqual(document.pages.count, WorkspaceFixtureScale.stress.pageCount)
        XCTAssertEqual(document.pages.reduce(0) { $0 + $1.nodes.count }, InsertionPolicy.maximumNodeCount)
        XCTAssertGreaterThan(WorkspaceFixtureScale.stress.pageCount, WorkspaceFixtureScale.large.pageCount)
        XCTAssertTrue(document.pages.allSatisfy { $0.nodes.count == 1 && $0.rootNodeIDs.count == 1 })
        XCTAssertNoThrow(try document.validate())
        XCTAssertLessThan(generation, .seconds(4), "Safety bound only; named-host timings belong in retained evidence")
        XCTAssertEqual(WorkspaceFixtureScale(rawValue: "stress"), .stress)
        XCTAssertEqual(WorkspaceFixtureScale.from(composition: DebugTestComposition(
            arguments: ["SiteForge", "-SiteForgeWorkspaceFixture", "stress"], enabled: true)), .stress)
        XCTAssertNil(WorkspaceFixtureScale.from(composition: DebugTestComposition(
            arguments: ["SiteForge", "-SiteForgeWorkspaceFixture", "stress"], enabled: false)))
    }

    // SF-0206-007: resolution is constant-time and one preference transaction
    // (prepare, execute, undo, redo) stays bounded on standard, large and
    // stress fixtures; workspace adoption and a Settings Apply stay bounded at
    // the stress limit.
    func testProjectPreferencesStayResponsiveOnStandardLargeAndStressFixtures() throws {
        let clock = ContinuousClock()
        for scale in [WorkspaceFixtureScale.standard, .large, .stress] {
            let session = DocumentSession(document: scale.document())
            XCTAssertEqual(session.document.pages.count, scale.pageCount)
            let transaction = try clock.measure {
                let command = try ProjectPreferencesCommandRegistry().prepare(.gridSpacing(24),
                    expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
                    document: session.document, isLifecycleAvailable: true)
                try session.execute(command)
                try session.undo()
                try session.redo()
            }
            XCTAssertEqual(session.document.projectPreferences?.gridSpacing, 24)
            XCTAssertEqual(session.document.pages.count, scale.pageCount)
            let bound: Duration = switch scale {
            case .standard: .seconds(2)
            case .large: .seconds(20)
            case .stress: .seconds(40)
            }
            XCTAssertLessThan(transaction, bound, "Safety bound only; named-host timings belong in retained evidence")
            let resolution = clock.measure {
                for _ in 0..<10_000 { _ = ProjectPreferenceResolver.gridSpacing(session.document.projectPreferences) }
            }
            XCTAssertLessThan(resolution, .seconds(1))
        }

        // At the stress limit: the workspace adopts preferences without
        // touching pages, and one Settings Apply is one transaction.
        let session = DocumentSession(document: WorkspaceFixtureScale.stress.document())
        let state = WorkspaceShellState(documentSession: session, initialWorldGridVisible: true)
        let name = "SiteForge.ProjectSettingsStressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ProjectSettingsStore(defaults: defaults, resolveTarget: { state })
        store.begin()
        store.chooseGridVisibility(false)
        store.chooseGridSpacing(32)
        var applied = false
        let apply = clock.measure { applied = store.apply() }
        XCTAssertTrue(applied)
        XCTAssertLessThan(apply, .seconds(20), "Safety bound only; named-host timings belong in retained evidence")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(session.document.pages.count, WorkspaceFixtureScale.stress.pageCount)
        let adoption = clock.measure {
            state.synchronizeProjectPreferences(session.document, applicationGridDefault: true)
        }
        XCTAssertFalse(state.isWorldGridVisible)
        XCTAssertEqual(state.worldGridSpacing, 32)
        XCTAssertLessThan(adoption, .milliseconds(100), "Adoption reads one record and never walks pages")
    }

    // SF-0206-003/006: Project sits beside the app-scoped panes, its drafts join
    // the shared pending-draft notice, and a valid authored value outside the
    // convenience list stays selectable.
    func testProjectSettingsDestinationChoicesAndPendingDraftNotice() {
        XCTAssertEqual(SettingsDestination.project.title, "Project")
        XCTAssertFalse(SettingsDestination.project.symbol.isEmpty)
        let order = SettingsDestination.allCases
        XCTAssertEqual(order.firstIndex(of: .project), order.firstIndex(of: .canvas).map { $0 + 1 })
        let notice = SettingsDraftNotice(appearanceDirty: false, canvasDirty: true, projectDirty: true)
        XCTAssertEqual(notice.destinations, [.canvas, .project])
        XCTAssertTrue(notice.message.contains("Canvas and Project"))
        XCTAssertTrue(SettingsDraftNotice(appearanceDirty: false, canvasDirty: false).destinations.isEmpty)
        XCTAssertEqual(ProjectGridVisibilityChoice(nil), .followMac)
        XCTAssertEqual(ProjectGridVisibilityChoice(true), .shown)
        XCTAssertEqual(ProjectGridVisibilityChoice(false).value, false)
        XCTAssertNil(ProjectGridVisibilityChoice.followMac.value)
        XCTAssertEqual(ProjectGridSpacingChoice.options(including: nil).map(\.points),
                       [nil] + ProjectPreferences.gridSpacingChoices.map { Optional($0) })
        XCTAssertTrue(ProjectGridSpacingChoice.options(including: 72).contains(ProjectGridSpacingChoice(72)))
        XCTAssertEqual(ProjectGridSpacingChoice(nil).title, "SiteForge default (16 pt)")
        XCTAssertEqual(ProjectGridSpacingChoice(16).title, "16 pt")
        XCTAssertNotEqual(ProjectGridSpacingChoice(nil), ProjectGridSpacingChoice(16))
    }

    // SF-1803-001/003/007 (OD-047): every flag has a valid identifier, an
    // owner, a requirement and a removal date that has not passed.
    func testFeatureFlagRegistryIdentifiersOwnersAndRemovalDatesAreValid() throws {
        XCTAssertEqual(FeatureFlagRegistry.issues(in: FeatureFlagRegistry.definitions, today: FeatureFlagDate(Date())), [])
        XCTAssertEqual(FeatureFlagRegistry.definition(.zipExport)?.id, FeatureFlagID("export.zip-archive"))
        XCTAssertTrue(FeatureFlagRegistry.definitions.allSatisfy { FeatureFlagID($0.id.rawValue) == $0.id })
        for invalid in ["Export.zip", "export", "export..zip", "export.zip-", ".export.zip", "export.zip archive",
                        "export.zip\n", "export." + String(repeating: "a", count: 64)] {
            XCTAssertNil(FeatureFlagID(invalid), invalid)
        }
        XCTAssertNil(FeatureFlagDate("2027-02-29")); XCTAssertNil(FeatureFlagDate("2027-2-03"))
        XCTAssertNil(FeatureFlagDate("2027-13-01")); XCTAssertNil(FeatureFlagDate("２０２７-01-01"))
        XCTAssertEqual(FeatureFlagDate("2028-02-29")?.description, "2028-02-29")

        let id = try XCTUnwrap(FeatureFlagID("test.sample"))
        let good = FeatureFlagDefinition(id: id, title: "Sample", summary: "Sample.", owner: "Owner",
            introduced: try flagDate("2026-01-01"), removeBy: try flagDate("2026-06-30"),
            defaultEnabled: false, requirementIDs: ["SF-1803"])
        XCTAssertEqual(FeatureFlagRegistry.issues(in: [good], today: try flagDate("2026-06-30")), [])
        XCTAssertEqual(FeatureFlagRegistry.issues(in: [good], today: try flagDate("2026-07-01")), [.expired(id)])
        let bad = FeatureFlagDefinition(id: id, title: " ", summary: "", owner: "", introduced: try flagDate("2026-06-30"),
            removeBy: try flagDate("2026-06-30"), defaultEnabled: false, requirementIDs: [])
        XCTAssertEqual(Set(FeatureFlagRegistry.issues(in: [good, bad], today: try flagDate("2026-01-02"))),
                       [.duplicate(id), .missingTitle(id), .missingOwner(id), .missingRequirement(id),
                        .removalNotAfterIntroduction(id)])
    }

    // SF-1803-002/004/005/006/008 (OD-047): draft → Apply/Cancel, explicit
    // versus omitted choices, reopen, launch-argument precedence, unknown
    // identifiers retained and corrupt records recovered without a crash.
    func testFeatureFlagStoreDraftApplyCancelPersistenceLaunchOverrideAndCorruptRecovery() throws {
        let suite = "SiteForgeFeatureFlagTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = try XCTUnwrap(FeatureFlagID("test.sample"))
        let definition = FeatureFlagDefinition(id: id, title: "Sample", summary: "Sample feature.", owner: "Owner",
            introduced: try flagDate("2026-01-01"), removeBy: try flagDate("2099-12-31"),
            defaultEnabled: true, requirementIDs: ["SF-1803"])
        let noLaunch = DebugTestComposition(arguments: [], enabled: true)
        func makeStore(_ launch: DebugTestComposition? = nil) -> FeatureFlagStore {
            FeatureFlagStore(defaults: defaults, definitions: [definition], launch: launch ?? noLaunch)
        }

        let store = makeStore()
        XCTAssertTrue(store.isEnabled(id)); XCTAssertEqual(store.resolution(id)?.source, .defaultValue)
        XCTAssertNil(defaults.object(forKey: FeatureFlagStore.defaultsKey))
        XCTAssertNil(store.storeFinding); XCTAssertEqual(store.lastDiagnostic.operation, "load")

        store.setDraft(id, enabled: false)
        XCTAssertTrue(store.isDirty); XCTAssertTrue(store.isEnabled(id)); XCTAssertFalse(store.draftValue(id))
        store.cancel()
        XCTAssertFalse(store.isDirty); XCTAssertTrue(store.isEnabled(id))
        XCTAssertNil(defaults.object(forKey: FeatureFlagStore.defaultsKey))

        store.setDraft(id, enabled: false)
        XCTAssertTrue(store.apply())
        XCTAssertFalse(store.isEnabled(id)); XCTAssertEqual(store.resolution(id)?.source, .thisMac)
        XCTAssertEqual(store.lastDiagnostic, .init(requirementID: "SF-1803-008", operation: "apply",
            flagIdentifiers: ["test.sample"], durationMilliseconds: store.lastDiagnostic.durationMilliseconds,
            failureCategory: "none"))

        let reopened = makeStore()
        XCTAssertFalse(reopened.isEnabled(id))
        reopened.setDraft(id, enabled: true); XCTAssertTrue(reopened.apply())
        XCTAssertEqual(reopened.resolution(id), FeatureFlagResolution(id: id, enabled: true, source: .thisMac))
        reopened.useDefault(id); XCTAssertTrue(reopened.apply())
        XCTAssertEqual(reopened.resolution(id), FeatureFlagResolution(id: id, enabled: true, source: .defaultValue))

        let stored = try JSONEncoder().encode(FeatureFlagOverrides(values: ["future.flag": true, "test.sample": false]))
        defaults.set(stored, forKey: FeatureFlagStore.defaultsKey)
        let withFuture = makeStore()
        XCTAssertFalse(withFuture.isEnabled(id)); XCTAssertTrue(withFuture.canRestoreDefaults)
        withFuture.restoreAllDefaults(); XCTAssertTrue(withFuture.apply())
        let retained = try JSONDecoder().decode(FeatureFlagOverrides.self,
                                                from: XCTUnwrap(defaults.data(forKey: FeatureFlagStore.defaultsKey)))
        XCTAssertEqual(retained.values, ["future.flag": true])
        XCTAssertFalse(withFuture.isEnabled(try XCTUnwrap(FeatureFlagID("future.flag"))))

        let launched = makeStore(DebugTestComposition(arguments: [FeatureFlagResolver.launchArgument(for: id), "NO"], enabled: true))
        XCTAssertFalse(launched.isEnabled(id)); XCTAssertTrue(launched.isLaunchControlled(id))
        XCTAssertEqual(launched.resolution(id)?.source, .launchArgument)
        launched.setDraft(id, enabled: true); XCTAssertFalse(launched.isDirty)
        XCTAssertTrue(launched.sourceDescription(id).contains("launch argument"))
        // Release builds ignore the launch argument even when it is present.
        let releaseLike = makeStore(DebugTestComposition(arguments: [FeatureFlagResolver.launchArgument(for: id), "NO"],
                                                         enabled: false))
        XCTAssertEqual(releaseLike.resolution(id)?.source, .defaultValue)
        XCTAssertFalse(releaseLike.isLaunchControlled(id))

        for bad in [Data("not json".utf8), Data(#"{"version":2,"values":{}}"#.utf8),
                    Data(#"{"version":1,"values":{"Bad ID":true}}"#.utf8),
                    Data(#"{"version":1,"values":{},"extra":1}"#.utf8)] {
            defaults.set(bad, forKey: FeatureFlagStore.defaultsKey)
            let recovered = makeStore()
            XCTAssertTrue(recovered.isEnabled(id)); XCTAssertNotNil(recovered.storeFinding)
            XCTAssertEqual(recovered.lastDiagnostic.failureCategory, "corrupt-data")
        }
        defaults.set("text", forKey: FeatureFlagStore.defaultsKey)
        let wrongType = makeStore()
        XCTAssertNotNil(wrongType.storeFinding)
        wrongType.setDraft(id, enabled: false); XCTAssertTrue(wrongType.apply())
        XCTAssertNil(wrongType.storeFinding); XCTAssertFalse(makeStore().isEnabled(id))
    }

    // SF-1803-001/002/003/004/005 (OD-047, ADR-0145): every shipped flag (zip
    // export, named snapshots, site languages, compare versions, component
    // libraries) defaults on, turns off and back on independently, persists on
    // this Mac, yields to a debug launch argument, and Restore Defaults stores
    // nothing for it. Unknown identifiers are off and cannot be drafted.
    func testFeatureFlagRegistryEveryShippedFlagDefaultsTogglesPersistsAndYieldsToLaunchArguments() throws {
        let shipped: [FeatureFlagID] = [.zipExport, .namedSnapshots, .siteLanguages, .versionComparison, .componentLibraries]
        XCTAssertEqual(FeatureFlagRegistry.definitions.map(\.id).sorted(), shipped.sorted(),
                       "Add a new flag here with its own coverage")
        let suite = "SiteForgeShippedFeatureFlagTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let noLaunch = DebugTestComposition(arguments: [], enabled: true)
        let store = FeatureFlagStore(defaults: defaults, launch: noLaunch)
        XCTAssertEqual(store.definitions.map(\.id), shipped.sorted())
        for id in shipped {
            let definition = try XCTUnwrap(FeatureFlagRegistry.definition(id), id.rawValue)
            XCTAssertTrue(definition.defaultEnabled, id.rawValue)
            XCTAssertFalse(definition.summary.isEmpty, id.rawValue)
            XCTAssertTrue(definition.requirementIDs.allSatisfy { $0.hasPrefix("SF-") }, id.rawValue)
            XCTAssertTrue(store.isEnabled(id), id.rawValue)
            XCTAssertEqual(store.resolution(id)?.source, .defaultValue, id.rawValue)
        }

        for id in shipped { store.setDraft(id, enabled: false) }
        XCTAssertTrue(shipped.allSatisfy { store.isEnabled($0) }, "Drafts never change behavior")
        XCTAssertTrue(store.apply())
        let reopened = FeatureFlagStore(defaults: defaults, launch: noLaunch)
        for id in shipped {
            XCTAssertFalse(reopened.isEnabled(id), id.rawValue)
            XCTAssertEqual(reopened.resolution(id)?.source, .thisMac, id.rawValue)
        }
        reopened.setDraft(.siteLanguages, enabled: true)
        XCTAssertTrue(reopened.apply())
        let again = FeatureFlagStore(defaults: defaults, launch: noLaunch)
        XCTAssertTrue(again.isEnabled(.siteLanguages))
        XCTAssertEqual(shipped.filter { again.isEnabled($0) }, [.siteLanguages], "The other flags stay off")

        let launched = FeatureFlagStore(defaults: defaults, launch: DebugTestComposition(
            arguments: [FeatureFlagResolver.launchArgument(for: .zipExport), "YES"], enabled: true))
        XCTAssertTrue(launched.isEnabled(.zipExport))
        XCTAssertEqual(launched.resolution(.zipExport)?.source, .launchArgument)
        XCTAssertFalse(launched.isEnabled(.versionComparison), "A launch argument affects its own flag only")

        again.restoreAllDefaults()
        XCTAssertTrue(again.apply())
        let record = try JSONDecoder().decode(FeatureFlagOverrides.self,
                                              from: XCTUnwrap(defaults.data(forKey: FeatureFlagStore.defaultsKey)))
        XCTAssertEqual(record.values, [:])
        let restored = FeatureFlagStore(defaults: defaults, launch: noLaunch)
        XCTAssertTrue(shipped.allSatisfy { restored.isEnabled($0) })

        let unknown = try XCTUnwrap(FeatureFlagID("test.not-registered"))
        XCTAssertFalse(restored.isEnabled(unknown))
        XCTAssertNil(restored.resolution(unknown))
        restored.setDraft(unknown, enabled: true)
        XCTAssertFalse(restored.isDirty)
    }

    private func flagDate(_ text: String) throws -> FeatureFlagDate { try XCTUnwrap(FeatureFlagDate(text)) }
}
