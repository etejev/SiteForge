import AppKit
import SwiftUI

@MainActor
final class SiteForgeApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windowPresentation: WorkspaceWindowLifecycleOwner?
    let appearanceSettings = AppearanceSettingsStore()
    let canvasSettings = CanvasSettingsStore()
    let supportSettings = SupportSettingsStore()
    let updateSettings = UpdateSettingsStore()
    let settingsNavigation = SettingsNavigationModel()
    lazy var applicationSettingsGroup = ApplicationSettingsGroupStore(
        appearance: appearanceSettings, canvas: canvasSettings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let owner = WorkspaceWindowLifecycleOwner()
        windowPresentation = owner
        owner.install()
    }
}

@main
struct SiteForgeApp: App {
    @NSApplicationDelegateAdaptor(SiteForgeApplicationDelegate.self) private var applicationDelegate
    private let composition: WorkspaceSceneComposition

    init() {
        composition = .current()
    }

    var body: some Scene {
        WindowGroup("SiteForge", id: "workspace") {
            WorkspaceSceneRoot(composition: composition)
        }
        .defaultSize(
            width: WorkspaceMetrics.defaultWindowSize.width,
            height: WorkspaceMetrics.defaultWindowSize.height
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
                defaults: applicationDelegate.applicationSettingsGroup,
                updates: applicationDelegate.updateSettings,
                support: applicationDelegate.supportSettings
            )
        }
        .defaultSize(width: SiteForgeVisualSystem.settingsIdealWidth, height: SiteForgeVisualSystem.settingsIdealHeight)
        .windowResizability(.contentSize)
    }
}
