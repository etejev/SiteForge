import AppKit
import SwiftUI

@MainActor
final class SiteForgeApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windowPresentation: WorkspaceWindowLifecycleOwner?

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
    }
}
