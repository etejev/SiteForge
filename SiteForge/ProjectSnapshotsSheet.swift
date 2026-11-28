import SwiftUI

struct ProjectSnapshotsSheet: View {
    @ObservedObject var state: WorkspaceShellState
    /// Observed so the Compare buttons follow a flag change while the sheet is open.
    @ObservedObject private var features = FeatureFlagStore.shared
    @State private var newName: String
    @State private var renamingID: ProjectSnapshotID?
    @State private var renameDraft = ""
    @State private var restoreTarget: ProjectSnapshotEntry?
    @State private var keepsCurrent = true
    @State private var keepName = ""
    @State private var deleteTarget: ProjectSnapshotEntry?
    @State private var isConfirmingDeleteAll = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(state: WorkspaceShellState) {
        self.state = state
        _newName = State(initialValue: state.suggestedSnapshotName())
    }

    private var palette: SiteForgeChromePalette { .init(scheme: scheme, contrast: contrast) }
    private var isAtLimit: Bool { state.snapshotEntries.count >= ProjectSnapshotIndex.maximumCount }

    var body: some View {
        VStack(spacing: 0) {
            Text("Snapshots")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(palette.bar)
                .accessibilityAddTraits(.isHeader)
            rule
            VStack(alignment: .leading, spacing: 12) {
                Text("Snapshots are kept inside this project file and become permanent when you save. Restoring one is a new change you can undo; the current version is never deleted.")
                    .font(.callout)
                    .foregroundStyle(palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure = state.snapshotStorageFailure {
                    storageFailure(failure)
                } else if let target = restoreTarget {
                    restorePanel(target)
                } else {
                    createRow
                    snapshotList
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            rule
            footer
        }
        .frame(width: min(720, max(560, (NSScreen.main?.visibleFrame.width ?? 736) - 16)),
               height: min(560, max(400, (NSScreen.main?.visibleFrame.height ?? 580) - 20)))
        .background(palette.base)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snapshots.sheet")
        .confirmationDialog("Delete this snapshot?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible, presenting: deleteTarget) { entry in
            Button("Delete \u{201C}\(entry.name)\u{201D}", role: .destructive) {
                _ = state.deleteSnapshot(entry.id)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("The kept version is removed from the project file when you save. The current document is not changed.")
        }
        .confirmationDialog("Delete all snapshots?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All Snapshots", role: .destructive) { _ = state.deleteAllSnapshots() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every kept version in this project is removed when you save. The current document is not changed.")
        }
    }

    private var rule: some View {
        Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
    }

    private var createRow: some View {
        let issue = newName.isEmpty ? nil : state.snapshotNameIssue(newName)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Snapshot name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { create() }
                    .accessibilityLabel("New snapshot name")
                    .accessibilityIdentifier("snapshots.name")
                Button("Create Snapshot") { create() }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette, primary: true))
                    .disabled(!state.canCreateSnapshot || state.snapshotNameIssue(newName) != nil)
                    .help("Keep the current document as a named snapshot in this project")
                    .accessibilityIdentifier("snapshots.create")
            }
            if let issue {
                Text(issue).font(.caption).foregroundStyle(palette.danger)
                    .accessibilityIdentifier("snapshots.name.issue")
            } else if isAtLimit {
                Text(ProjectSnapshotError.limitReached.localizedDescription).font(.caption).foregroundStyle(palette.quiet)
                    .accessibilityIdentifier("snapshots.limit")
            }
        }
    }

    @ViewBuilder
    private var snapshotList: some View {
        if state.snapshotRows.isEmpty {
            Text("No snapshots yet. Name the current version above and choose Create Snapshot.")
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.quiet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("snapshots.empty")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(state.snapshotRows) { entry in
                        snapshotRow(entry)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Snapshots, newest first")
            .accessibilityIdentifier("snapshots.list")
        }
    }

    private func snapshotRow(_ entry: ProjectSnapshotEntry) -> some View {
        let key = entry.id.description
        return HStack(spacing: 8) {
            if renamingID == entry.id {
                TextField("Snapshot name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(entry) }
                    .accessibilityLabel("New name for \(entry.name)")
                    .accessibilityIdentifier("snapshots.\(key).renameField")
                Button("Cancel") { renamingID = nil }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("snapshots.\(key).renameCancel")
                Button("Rename") { commitRename(entry) }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette, primary: true))
                    .disabled(state.snapshotNameIssue(renameDraft, renaming: entry.id) != nil
                        || (try? ProjectSnapshots.validatedName(renameDraft)) == entry.name)
                    .accessibilityIdentifier("snapshots.\(key).renameApply")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).lineLimit(1)
                    Text(WorkspaceShellState.snapshotDetail(entry)).font(.caption).foregroundStyle(palette.quiet)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Restore…") { beginRestore(entry) }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .disabled(!state.canReplaceProjectContent)
                    .help(state.canReplaceProjectContent
                        ? "Make the document match this snapshot as one undoable change"
                        : WorkspaceShellState.variantOpenReplacementMessage)
                    .accessibilityLabel("Restore \(entry.name)")
                    .accessibilityIdentifier("snapshots.\(key).restore")
                if features.isEnabled(.versionComparison) {
                    Button("Compare") { state.compareSnapshotWithCurrent(entry.id) }
                        .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                        .help("Compare this snapshot with the current document")
                        .accessibilityLabel("Compare \(entry.name) with the current document")
                        .accessibilityIdentifier("snapshots.\(key).compare")
                }
                Button("Rename…") {
                    renameDraft = entry.name
                    renamingID = entry.id
                }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .disabled(!state.canManageSnapshots)
                    .accessibilityLabel("Rename \(entry.name)")
                    .accessibilityIdentifier("snapshots.\(key).rename")
                Button("Delete…") { deleteTarget = entry }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .disabled(!state.canManageSnapshots)
                    .accessibilityLabel("Delete \(entry.name)")
                    .accessibilityIdentifier("snapshots.\(key).delete")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.panel))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snapshots.row.\(key)")
    }

    private func restorePanel(_ entry: ProjectSnapshotEntry) -> some View {
        let keepIssue = keepsCurrent ? state.snapshotNameIssue(keepName) : nil
        let blocked = keepIssue != nil || (keepsCurrent && isAtLimit)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Restore \u{201C}\(entry.name)\u{201D}?")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("The document will match this snapshot as one new change; choose Undo to go back. Its creation settings stay with the current document.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Keep the current version as a snapshot first", isOn: $keepsCurrent)
                .accessibilityIdentifier("snapshots.restore.keep")
            if keepsCurrent {
                TextField("Name for the current version", text: $keepName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Name for the current version")
                    .accessibilityIdentifier("snapshots.restore.keepName")
                if let keepIssue {
                    Text(keepIssue).font(.caption).foregroundStyle(palette.danger)
                        .accessibilityIdentifier("snapshots.restore.keepIssue")
                } else if isAtLimit {
                    Text(ProjectSnapshotError.limitReached.localizedDescription).font(.caption).foregroundStyle(palette.danger)
                        .accessibilityIdentifier("snapshots.restore.limit")
                }
            }
            if !state.canReplaceProjectContent {
                Text(WorkspaceShellState.variantOpenReplacementMessage).font(.caption).foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("snapshots.restore.variantOpen")
            }
            HStack(spacing: 8) {
                // SF-1301-003: see exactly what the restore would change first.
                if features.isEnabled(.versionComparison) {
                    Button("Review Changes…") {
                        restoreTarget = nil
                        state.previewSnapshotRestore(entry.id)
                    }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .help("Compare the current document with this snapshot; nothing is restored")
                    .accessibilityLabel("Review what restoring \(entry.name) would change")
                    .accessibilityIdentifier("snapshots.restore.review")
                }
                Spacer()
                Button("Cancel") { restoreTarget = nil }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("snapshots.restore.cancel")
                Button("Restore") {
                    if state.restoreSnapshot(entry.id, keepingCurrentAs: keepsCurrent ? keepName : nil) {
                        restoreTarget = nil
                        newName = state.suggestedSnapshotName()
                    }
                }
                .buttonStyle(SiteForgeChromeButtonStyle(palette: palette, primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(blocked || !state.canReplaceProjectContent)
                .accessibilityIdentifier("snapshots.restore.confirm")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.panel))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snapshots.restore")
    }

    private func storageFailure(_ failure: ProjectSnapshotError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(failure.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(palette.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("snapshots.failure")
            Text("Deleting all snapshots removes only the kept versions. The current document is not changed.")
                .font(.callout)
                .foregroundStyle(palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Try Again") { state.reloadSnapshots() }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .accessibilityIdentifier("snapshots.retry")
                Button("Delete All Snapshots…", role: .destructive) { isConfirmingDeleteAll = true }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .disabled(!state.canManageSnapshots)
                    .accessibilityIdentifier("snapshots.recover.deleteAll")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !state.snapshotsStatus.isEmpty {
                Text(state.snapshotsStatus).font(.callout)
                    .foregroundStyle(palette.quiet)
                    .lineLimit(2)
                    .accessibilityIdentifier("snapshots.status")
            }
            Spacer()
            if state.snapshotStorageFailure == nil, !state.snapshotEntries.isEmpty, restoreTarget == nil {
                Button("Delete All…") { isConfirmingDeleteAll = true }
                    .buttonStyle(SiteForgeChromeButtonStyle(palette: palette))
                    .disabled(!state.canManageSnapshots)
                    .accessibilityIdentifier("snapshots.deleteAll")
            }
            Button("Done") { state.isSnapshotsPresented = false }
                .buttonStyle(SiteForgeChromeButtonStyle(palette: palette, primary: restoreTarget == nil))
                .keyboardShortcut(restoreTarget == nil && renamingID == nil ? KeyboardShortcut.cancelAction : nil)
                .accessibilityIdentifier("snapshots.done")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 51)
        .background(palette.bar)
    }

    private func create() {
        guard state.canCreateSnapshot, state.snapshotNameIssue(newName) == nil else { return }
        if state.createSnapshot(named: newName) { newName = state.suggestedSnapshotName() }
    }

    private func commitRename(_ entry: ProjectSnapshotEntry) {
        guard state.snapshotNameIssue(renameDraft, renaming: entry.id) == nil else { return }
        if state.renameSnapshot(entry.id, to: renameDraft) { renamingID = nil }
    }

    private func beginRestore(_ entry: ProjectSnapshotEntry) {
        renamingID = nil
        keepsCurrent = !isAtLimit
        keepName = state.suggestedSnapshotName(base: "Before restoring \(entry.name)")
        restoreTarget = entry
    }
}
