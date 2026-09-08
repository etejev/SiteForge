import AppKit
import XCTest
@testable import SiteForge

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    private func withStore(_ body: (UserDefaults, AppearanceSettingsStore) throws -> Void) rethrows {
        let name = "SiteForge.AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, AppearanceSettingsStore(defaults: defaults, present: { _ in }))
    }

    // SF-0206-003/004/008: versioned intent and safe future-data handling.
    func testAppearanceStrictRecordsAndUpgradeFallbackPreserveIntent() throws {
        for choice in ApplicationAppearance.allCases {
            let record = ApplicationAppearanceRecord(choice)
            XCTAssertEqual(ApplicationAppearanceRecord.decode(try JSONEncoder().encode(record)), record)
        }
        for json in ["{}", "{\"version\":2,\"preferenceID\":\"application.appearance\",\"origin\":\"authored\",\"appearance\":\"dark\"}", "{\"version\":1,\"preferenceID\":\"wrong\",\"origin\":\"authored\",\"appearance\":\"light\"}", "{\"version\":1,\"preferenceID\":\"application.appearance\",\"origin\":\"authored\",\"appearance\":\"unknown\"}"] {
            let data = Data(json.utf8)
            XCTAssertNil(ApplicationAppearanceRecord.decode(data))
            withStore { defaults, _ in
                defaults.set(data, forKey: AppearanceSettingsStore.storageKey)
                let store = AppearanceSettingsStore(defaults: defaults, present: { _ in })
                XCTAssertEqual(store.resolved, .system)
                XCTAssertTrue(store.status.contains("unavailable"))
                store.begin(); store.preview(.light); store.cancel(); store.close()
                XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), data)
                store.begin(); store.reset(); XCTAssertTrue(store.apply())
                XCTAssertNil(defaults.object(forKey: AppearanceSettingsStore.storageKey))
                store.restorePrevious()
                XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), data)
            }
        }
    }

    // SF-0206-002/003/004: preview never persists; Escape/close restore.
    func testAppearancePreviewCancelCloseAndNoOpAreNeutral() {
        withStore { defaults, store in
            XCTAssertEqual(store.resolved, .system)
            XCTAssertTrue(store.provenance.contains("Default"))
            store.begin(); store.preview(.dark)
            XCTAssertEqual(store.choice, .dark)
            XCTAssertEqual(store.resolved, .system)
            XCTAssertNil(defaults.object(forKey: AppearanceSettingsStore.storageKey))
            store.cancel()
            XCTAssertEqual(store.choice, .system)
            XCTAssertTrue(store.apply())
            XCTAssertTrue(store.transactions.isEmpty)
            store.preview(.light); store.close()
            XCTAssertEqual(store.choice, .system)
            XCTAssertFalse(store.apply())
            XCTAssertTrue(store.transactions.isEmpty)
        }
    }

    // SF-0206-002/003/008: exact app preference restoration, not document Undo.
    func testAppearanceApplyResetRestorationAndRelaunchPersistence() {
        withStore { defaults, store in
            defaults.set("unrelated", forKey: "other.preference")
            store.begin(); store.preview(.dark); XCTAssertTrue(store.apply())
            let authored = defaults.data(forKey: AppearanceSettingsStore.storageKey)
            XCTAssertNotNil(authored)
            XCTAssertEqual(store.transactions.count, 1)
            XCTAssertNil(store.transactions[0].before)
            XCTAssertEqual(store.transactions[0].after, authored)
            XCTAssertEqual(store.transactions[0].preferenceID, "application.appearance")
            XCTAssertEqual(AppearanceSettingsStore(defaults: defaults, present: { _ in }).resolved, .dark)
            store.reset(); XCTAssertEqual(store.resolved, .dark)
            XCTAssertTrue(store.apply())
            XCTAssertNil(defaults.object(forKey: AppearanceSettingsStore.storageKey))
            store.restorePrevious()
            XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), authored)
            XCTAssertEqual(store.resolved, .dark)
            XCTAssertEqual(defaults.string(forKey: "other.preference"), "unrelated")
        }
    }

    func testAppearanceNativeResolutionAndBoundedRestorationHistory() {
        XCTAssertNil(ApplicationAppearance.system.nativeAppearance)
        XCTAssertEqual(ApplicationAppearance.light.nativeAppearance?.name, .aqua)
        XCTAssertEqual(ApplicationAppearance.dark.nativeAppearance?.name, .darkAqua)
        withStore { _, store in
            store.begin()
            for index in 0..<100 {
                store.preview(index.isMultiple(of: 2) ? .dark : .light)
                XCTAssertTrue(store.apply())
            }
            XCTAssertEqual(store.transactions.count, 32)
            XCTAssertEqual(store.revision, 100)
            XCTAssertFalse(store.status.contains("/"))
            XCTAssertEqual(store.lastDiagnostic.requirementID, "SF-0206-008")
            XCTAssertEqual(store.lastDiagnostic.operation, "set-appearance")
            XCTAssertEqual(store.lastDiagnostic.failureCategory, "none")
            XCTAssertTrue(store.lastDiagnostic.durationSeconds.isFinite)
            XCTAssertGreaterThanOrEqual(store.lastDiagnostic.durationSeconds, 0)
        }
    }

    func testAppearanceStaleExternalChangeRejectsDraftWithoutOverwriting() throws {
        try withStore { defaults, store in
            store.begin(); store.preview(.light)
            let external = try JSONEncoder().encode(ApplicationAppearanceRecord(.dark))
            defaults.set(external, forKey: AppearanceSettingsStore.storageKey)
            XCTAssertFalse(store.apply())
            XCTAssertEqual(store.lastDiagnostic.failureCategory, "stale-context")
            XCTAssertTrue(store.transactions.isEmpty)
            XCTAssertEqual(defaults.data(forKey: AppearanceSettingsStore.storageKey), external)
            store.close(); store.begin()
            XCTAssertEqual(store.choice, .dark)
            XCTAssertEqual(store.resolved, .dark)
        }
    }

    func testAppearanceNativeWindowReattachmentPreservesPreviewButCloseCancels() {
        withStore { _, store in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            store.attach(to: window)
            store.preview(.dark)
            store.attach(to: window)
            XCTAssertEqual(store.choice, .dark)
            XCTAssertTrue(store.isDirty)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            XCTAssertEqual(store.choice, .system)
            XCTAssertFalse(store.isDirty)
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            store.preview(.light)
            XCTAssertEqual(store.choice, .light)
        }
    }
}
