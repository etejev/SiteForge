import SwiftUI

@main
struct SiteForgeApp: App {
    @StateObject private var shellState: WorkspaceShellState
    @StateObject private var launchExperience: LaunchExperienceController

    init() {
        let fixture = WorkspaceFixtureScale.from(arguments: ProcessInfo.processInfo.arguments)
        let session = fixture.map { DocumentSession(document: $0.document()) } ?? DocumentSession()
        let shellState = WorkspaceShellState(documentSession: session)
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SiteForgeStartModified"),
           let homeID = session.document.pages.first?.id {
            _ = try? session.execute(.renamePage(RenamePageCommand(pageID: homeID, name: "Unsaved Home")))
        }
#endif
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
