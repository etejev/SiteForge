import SwiftUI

@main
struct SiteForgeApp: App {
    @StateObject private var shellState: WorkspaceShellState
    @StateObject private var launchExperience: LaunchExperienceController

    init() {
        let shellState = WorkspaceShellState()
        _shellState = StateObject(wrappedValue: shellState)
        _launchExperience = StateObject(wrappedValue: LaunchExperienceController(lifecycle: shellState.lifecycle))
    }

    var body: some Scene {
        WindowGroup("SiteForge", id: "workspace") {
            ContentView(state: shellState, launchExperience: launchExperience)
        }
        .defaultSize(
            width: WorkspaceMetrics.defaultWindowSize.width,
            height: WorkspaceMetrics.defaultWindowSize.height
        )
        .windowResizability(.contentMinSize)
        .commands {
            SiteForgeCommands(state: shellState, launchExperience: launchExperience)
        }
    }
}
