import XCTest
@testable import SiteForge

@MainActor
final class CanvasSettingsTests: XCTestCase {
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
        XCTAssertEqual(appearance.resolved, .system)
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
}
