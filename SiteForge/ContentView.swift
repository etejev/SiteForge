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
        .modifier(RecoveryDetailsPresentation(controller: launchExperience.lifecycle))
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


private struct RecoveryDetailsPresentation: ViewModifier {
    @ObservedObject var controller: DocumentLifecycleController

    func body(content: Content) -> some View {
        content.sheet(isPresented: $controller.isRecoveryDetailsPresented) {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.toolbarGroupSpacing) {
                Text("Recovery Details").font(.title2)
                Text(controller.recoveryCandidate?.summary ?? "No valid recovery candidate is available.")
                Text("Project content and complete file paths are excluded from these details.")
                    .foregroundStyle(.secondary)
                Button("Done") { controller.isRecoveryDetailsPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("recovery.details.done")
            }
            .padding(SiteForgeVisualSystem.settingsFormPadding).frame(minWidth: 420)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recovery.details")
        }
    }
}
