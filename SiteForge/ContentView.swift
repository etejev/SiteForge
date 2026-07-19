import SwiftUI

enum AppMetadata {
    static let productName = "SiteForge"
    static let localBundleIdentifier = "app.siteforge.SiteForge"
    static let foundationRequirementIDs: Set = [
        "SF-1501-008",
        "SF-1802-008",
        "SF-1902-006",
        "SF-1902-008",
    ]
}

struct ContentView: View {
    @ObservedObject var state: WorkspaceShellState
    @ObservedObject var launchExperience: LaunchExperienceController

    var body: some View {
        Group {
            if launchExperience.isWorkspaceVisible {
                WorkspaceShellView(state: state)
            } else {
                LaunchExperienceView(controller: launchExperience)
            }
        }
        .preferredColorScheme(WorkspaceMaterialPolicy.preferredColorScheme())
    }
}
