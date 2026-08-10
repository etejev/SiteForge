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
        // This bridge deliberately belongs to the scene root rather than the
        // editor shell: welcome, loading, recovery and the workspace are one
        // native document window with one restoration policy.
        .background {
            // UI-test edge/minimum placement is deliberately attached by the
            // workspace shell after its accessibility hierarchy exists. It
            // avoids a launch-time geometry race without leaking into Release.
            if DebugTestComposition.current().boolValue(after: "-SiteForgeUITestMode") != true {
                WorkspaceWindowConfigurator()
                    .frame(width: 0, height: 0)
            }
        }
        .preferredColorScheme(WorkspaceMaterialPolicy.preferredColorScheme())
        .alert(
            launchExperience.lifecycle.pendingUnsavedChangesPrompt?.transition.title ?? "Save changes?",
            isPresented: Binding(
                get: { launchExperience.lifecycle.pendingUnsavedChangesPrompt != nil },
                set: { presented in
                    guard !presented,
                          let prompt = launchExperience.lifecycle.pendingUnsavedChangesPrompt else { return }
                    launchExperience.lifecycle.resolveUnsavedChanges(.cancel, promptID: prompt.id)
                }
            )
        ) {
            if let prompt = launchExperience.lifecycle.pendingUnsavedChangesPrompt {
                Button("Save") {
                    launchExperience.lifecycle.resolveUnsavedChanges(.save, promptID: prompt.id)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("documentTransition.save")
                Button("Discard Changes", role: .destructive) {
                    launchExperience.lifecycle.resolveUnsavedChanges(.discard, promptID: prompt.id)
                }
                .accessibilityIdentifier("documentTransition.discard")
                Button("Cancel", role: .cancel) {
                    launchExperience.lifecycle.resolveUnsavedChanges(.cancel, promptID: prompt.id)
                }
                .accessibilityIdentifier("documentTransition.cancel")
            }
        } message: {
            Text(launchExperience.lifecycle.pendingUnsavedChangesPrompt?.message ?? "The current project is unchanged.")
        }
    }
}
