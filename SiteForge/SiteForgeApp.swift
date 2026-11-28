import AppKit
import SwiftUI

@MainActor
final class SiteForgeApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windowPresentation: WorkspaceWindowLifecycleOwner?
    let appearanceSettings = AppearanceSettingsStore()
    let canvasSettings = CanvasSettingsStore()
    let projectSettings = ProjectSettingsStore()
    let supportSettings = SupportSettingsStore()
    let updateSettings = UpdateSettingsStore()
    let settingsNavigation = SettingsNavigationModel()
    lazy var applicationSettingsGroup = ApplicationSettingsGroupStore(
        appearance: appearanceSettings, canvas: canvasSettings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let owner = WorkspaceWindowLifecycleOwner()
        windowPresentation = owner
        owner.install()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openTestingRequest(_:)),
            name: NSNotification.Name("app.siteforge.openTesting"), object: nil)
    }

    @objc private func openTestingRequest(_ notification: Notification) {
        guard let mode = notification.userInfo?["mode"] as? String, ["code", "ui", "full"].contains(mode),
              let selectors = notification.userInfo?["selectors"] as? [String],
              let nonce = notification.userInfo?["nonce"] as? String else { return }
        let store = ExperimentalTestingStore.shared
        let exact = selectors.filter { $0.contains("/") }
        let affected = notification.userInfo?["policy"] as? String == "affected"
        if affected {
            guard let base = notification.userInfo?["base"] as? String, !base.isEmpty, base.count <= 1024 else { return }
            store.affectedBase = base
            store.scopePolicy = .affected
        } else if !exact.isEmpty {
            guard ExperimentalTestingStore.selectors(in: exact.joined(separator: " ")) != nil else { return }
            store.selectorText = exact.joined(separator: " ")
            store.scopePolicy = .focused
        } else { store.scopePolicy = .all }
        store.openTestingWindow()
        store.requestDescription = affected ? "CLI requested affected features. Review the resolved scope; unresolved changes require your explicit choice." : "CLI requested \(mode == "full" ? "Full Verification" : mode == "ui" ? "UI Testing" : "Regular Testing"). Review the scope and choose Start."
        DistributedNotificationCenter.default().postNotificationName(.init("app.siteforge.testingWindowOpened"),
            object: nonce, userInfo: nil, deliverImmediately: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        RecoverySessionEvidence.shared.markCleanShutdown()
    }
}

@main
struct SiteForgeApp: App {
    @NSApplicationDelegateAdaptor(SiteForgeApplicationDelegate.self) private var applicationDelegate
    private let composition: WorkspaceSceneComposition

    init() {
        composition = .current()
    }

    private var workspaceDefaultSize: CGSize {
        if DebugTestComposition.current().boolValue(after: "-SiteForgeUITestMode") == true,
           let size = NSScreen.main?.visibleFrame.size {
            return size
        }
        return WorkspaceMetrics.defaultWindowSize
    }

    var body: some Scene {
        WindowGroup("SiteForge", id: "workspace") {
            WorkspaceSceneRoot(composition: composition)
        }
        .defaultSize(
            width: workspaceDefaultSize.width,
            height: workspaceDefaultSize.height
        )
        .windowResizability(.contentMinSize)
        .commands {
            SiteForgeCommands()
        }
        Settings {
            SiteForgeSettingsRootView(
                navigation: applicationDelegate.settingsNavigation,
                appearance: applicationDelegate.appearanceSettings,
                canvas: applicationDelegate.canvasSettings,
                project: applicationDelegate.projectSettings,
                defaults: applicationDelegate.applicationSettingsGroup,
                updates: applicationDelegate.updateSettings,
                support: applicationDelegate.supportSettings
            )
            .modifier(UITestTextSizeOverride())
        }
        .defaultSize(width: SiteForgeVisualSystem.settingsIdealWidth, height: SiteForgeVisualSystem.settingsIdealHeight)
        .windowResizability(.contentSize)
    }
}
