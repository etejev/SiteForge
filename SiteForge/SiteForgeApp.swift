import SwiftUI

@main
struct SiteForgeApp: App {
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
