import Foundation
import SwiftUI

struct DebugTestComposition: Equatable {
    let arguments: [String]
    let enabled: Bool

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
#if DEBUG
        Self(arguments: arguments, enabled: true)
#else
        Self(arguments: [], enabled: false)
#endif
    }

    func value(after flag: String) -> String? {
        guard enabled,
              let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    func contains(_ flag: String) -> Bool { enabled && arguments.contains(flag) }

    func boolValue(after flag: String) -> Bool? {
        guard let value = value(after: flag)?.lowercased() else { return nil }
        if ["yes", "true", "1"].contains(value) { return true }
        if ["no", "false", "0"].contains(value) { return false }
        return nil
    }
}

@MainActor
final class WorkspaceDocumentContext: ObservableObject {
    let shellState: WorkspaceShellState
    let launchExperience: LaunchExperienceController

    init(
        session: DocumentSession = DocumentSession(),
        recoveryDirectory: URL = DocumentLifecycleController.defaultRecoveryDirectory,
        previewScenario: LaunchPreviewScenario? = nil,
        autosaveDebouncer: any LifecycleAutosaveDebouncing = ContinuousLifecycleAutosaveDebouncer()
    ) {
        let lifecycle = DocumentLifecycleController(
            session: session,
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: autosaveDebouncer
        )
        shellState = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        launchExperience = LaunchExperienceController(
            lifecycle: lifecycle,
            previewScenario: previewScenario
        )
    }
}

struct WorkspaceSceneComposition {
    let makeContext: @MainActor () -> WorkspaceDocumentContext

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> WorkspaceSceneComposition {
        let overrides = DebugTestComposition.current(arguments: arguments)
        return WorkspaceSceneComposition {
            let fixture = WorkspaceFixtureScale.from(composition: overrides)
            let selectionFixture = WorkspaceSelectionFixture.from(composition: overrides)
            let fixtureDocument = selectionFixture?.document() ?? fixture?.document()
            let session = fixtureDocument.map { DocumentSession(document: $0) } ?? DocumentSession()
            let recoveryDirectory = overrides.value(after: "-SiteForgeRecoveryDirectory")
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? DocumentLifecycleController.productionRecoveryDirectory
            let context = WorkspaceDocumentContext(
                session: session,
                recoveryDirectory: recoveryDirectory,
                previewScenario: LaunchPreviewScenario.from(composition: overrides)
            )
            if overrides.contains("-SiteForgeStartModified"),
               let homeID = session.document.pages.first?.id {
                _ = try? session.execute(.renamePage(RenamePageCommand(pageID: homeID, name: "Unsaved Home")))
            }
            return context
        }
    }
}

struct WorkspaceSceneRoot: View {
    @StateObject private var context: WorkspaceDocumentContext

    init(composition: WorkspaceSceneComposition) {
        _context = StateObject(wrappedValue: composition.makeContext())
    }

    var body: some View {
        ContentView(
            state: context.shellState,
            launchExperience: context.launchExperience
        )
        .background {
            // The scene-root bridge both identifies the real document window
            // and applies its presentation. Keeping those responsibilities on
            // the same AppKit view prevents launch-order races where the
            // lifecycle observer sees an unmarked window and permanently
            // skips an explicit minimum-size request.
            WorkspaceWindowConfigurator()
                .frame(width: 0, height: 0)
        }
        .focusedSceneObject(context.shellState)
        .focusedSceneObject(context.launchExperience)
    }
}
