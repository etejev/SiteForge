import AppKit
import SwiftUI

@MainActor
final class SiteForgeApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windowPresentation: WorkspaceWindowLifecycleOwner?
    let appearanceSettings = AppearanceSettingsStore()
    let canvasSettings = CanvasSettingsStore()
    let supportSettings = SupportSettingsStore()
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
            TabView {
                AppearanceSettingsView(store: applicationDelegate.appearanceSettings)
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                CanvasSettingsView(store: applicationDelegate.canvasSettings)
                    .tabItem { Label("Canvas", systemImage: "circle.grid.2x2") }
                ApplicationSettingsGroupView(store: applicationDelegate.applicationSettingsGroup)
                    .tabItem { Label("Reset", systemImage: "arrow.uturn.backward") }
                SupportSettingsView(store: applicationDelegate.supportSettings)
                    .tabItem { Label("Support", systemImage: "lifepreserver") }
            }
            .accessibilityIdentifier("settings.tabs")
        }
    }
}
