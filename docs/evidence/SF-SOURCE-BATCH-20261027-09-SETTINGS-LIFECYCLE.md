# SF-SOURCE-BATCH-20261027-09 — Native Settings and lifecycle usability

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

Queue remains IN PROGRESS; modules remain Partial. Static source/diff inspection
and ordinary editing only. No tests/builds/check scripts, UI/runtime/visual
inspection, readiness/authentication, collectors, app/browser launches,
installation, signing, cleanup, commits or GitHub mutation. Advanced testing was
not invoked. No new screenshots; future attachment names below are instructions.
Deleted schedule and all owner projects/resources/recovery/evidence are preserved.
Historical cancelled verification does not cover these changes.

## Bounded requirements and inspected baseline

- SF-0204-003/004/006: truthful Welcome/recent/recovery presentation and native
  recovery/error/cancellation controls.
- SF-0206-002/003/005/006: global preference draft/commit/cancel/restore and
  accessible operation, explicitly separate from document metadata.
- SF-0301-003/004, SF-0306-003/004: identity-safe lifecycle presentation and
  recovery failure/cancellation without losing committed content or intent.

Settings already provides the seven global pages, shared reference-12 geometry,
fixed native Settings role, manual owner-local testing, inherited accessibility,
Dark defaults and fail-closed update installation. Welcome already distinguishes
first/clean/live sessions from crash-qualified automatic recovery and supports
manual history inspection. These are preserved, not reconstructed or certified.
Website metadata from batch 01 remains authored document content, not an app
preference scope. SF-1505 canvas accessibility is not newly claimed here.

## Concrete gaps and source changes

`SiteForge/AppearanceSettings.swift` and `SiteForge/CanvasSettings.swift`:
Cancel/close now reload the latest persisted bytes before restoring the visible
choice/appearance. Previously a stale draft replayed the cached old choice even
though a different value had been saved externally. Restore Previous requires
clean drafts and a matching latest transaction/current stored value; it cannot
overwrite a foreign change. Unsupported records remain byte-identical until an
explicit Apply/Reset, with truthful fallback guidance. Existing versioned app
transactions remain the only preference write path; project history is separate.
Application Defaults now correctly describes omitted appearance as Dark, not
Follow macOS. No new preference keys or policy override.

`SiteForge/SupportSettings.swift`: one observed SettingsNavigationModel owns the
destination instead of an unobserved model plus an independent view selection.
Native List callbacks publish at the next event boundary with a latest-request
guard; explicit Review supersedes older queued row changes.
A native bottom notice exposes existing Appearance/Canvas drafts across pages,
with Review and Cancel Drafts actions. It consumes normal scroll layout rather
than resizing the Settings window. Sidebar, consistent cards/form padding,
970×740 preferred fixed geometry and screen-fit fallback remain authoritative.
There is no scope selector, release-channel picker or experimental app split.
The existing Advanced run methods are unchanged and remain explicit buttons;
opening or selecting Settings does not invoke them. No open project is required.
Existing update verification/install trust and OD-026/027 restrictions are intact.

`SiteForge/LaunchExperience.swift`:

- Serialize load/forget/remember through the controller's existing recent store,
  computing each mutation after the prior one completes. Late failures preserve
  the last valid list; native progress explains pending metadata updates. Forget
  changes the list only, never a project package or retained authorization.
- Guard old Open/New and cancellation publication before work and after awaits,
  including the wait for recent metadata persistence. An expired completion can
  no longer publish Workspace/Welcome over a newer failure or operation.
- Preserve the actual return origin across retries/replacement work. An untitled
  workspace remains a real current project, so failed Open offers Return to
  Current Project even without a file URL. No replacement document is fabricated.
- Cancelled manual recovery review returns from loading and preserves snapshots.
  Restore/discard is single-flight, pinned to launch/candidate identity, and shows
  progress/result feedback. Failed discard retains the recovery surface/candidate
  instead of always entering Workspace. Restore cancellation/failure remains
  inspectable; Later still retains bytes. Existing preview fixtures are preserved.

No recovery trust, ownership lease, fingerprint deletion, security bookmark,
project package, migration, document command, renderer or compiler mechanism was
replaced. Existing lifecycle operations remain the canonical mutation boundary;
these changes correct the native workflow and publication around them. App
preferences never become authored website styles. Feedback does not add paths,
recovery bytes or preference payloads to diagnostics.

## Seven new acceptance methods — all UNRUN

- `SiteForgeTests/AppearanceSettingsTests/testAppearanceCancelReloadsLatestSavedValueAndRejectsForeignRestore`
  — external change, stale Apply, latest Cancel, blocked foreign Restore and
  unsupported-record preservation.
- `SiteForgeTests/CanvasSettingsTests/testCanvasCancelReloadsExternalDefaultWithoutReplayingOldHistory`
  — global new-workspace default, external change/cancel/restore guards and no
  project-history mutation.
- `SiteForgeTests/SupportSettingsTests/testGlobalSettingsNavigationAndDraftNoticeHaveNoProjectScope`
  — published destination ownership, explicit draft summary, seven global pages
  and unchanged fixed geometry, guarded native-selection ordering, without
  launching testing.
- `SiteForgeTests/LaunchExperienceTests/testRecentProjectMutationsSerializeAndFailedRefreshRetainsLastValidList`
  — controlled suspended persistence proves ordered removals and retained valid
  presentation on refresh failure.
- `SiteForgeTests/LaunchExperienceTests/testOpenCompletionAfterRecentPersistenceCannotReplaceNewerLaunchState`
  — late metadata completion, superseded queued creation, unchanged document and
  Return to an untitled workspace after failure.
- `SiteForgeTests/LaunchExperienceTests/testRecoveryReviewCancellationAndFailedDiscardKeepTruthfulStateAndBytes`
  — production fixture autosave, no fake crash for a live session, existing
  backend checkpoint cancellation, changed fixture artifact/failed conditional
  discard, retained UI/candidate/bytes and Later.
- `SiteForgeUITests/SiteForgeLaunchTests/testWelcomeGlobalSettingsDraftReviewCancelAndFixedGeometryJourney`
  — real Welcome→Settings, native draft editing, cross-page Review/Cancel,
  unchanged fixed window, Advanced presence without pressing testing actions,
  and return to Welcome. `SF-SOURCE-09` attachments are planned, not captured.

Existing future regressions include clean/crash session qualification,
`testInitialRecoveryOffersAbandonedSessionButKeepsCleanExitManual`,
`testWelcomeRecoveryReviewAndLaterPreserveBytesAndDoNotLoop`,
`testNewerRecoveryCandidatePresentsRestoreAndDiscardPaths`, native Settings
close/reopen/fixed geometry, group reset/restore, and manual testing availability
without a project. Historical results are not current-source acceptance.

## Limits and future approval boundary

All compilation, focused/native execution, original-resolution reference-12
visual review, VoiceOver/focus/IME, storage-error behavior and integrated
verification remain pending separate owner approval. Recent-operation ordering
is per controller; cross-process/multi-controller concurrent list merging is not
newly proven or claimed. No project durability/recovery format has changed.
No updater trust/install waiver, remote services, distribution signing, release,
slot ownership or conflict-retarget decision is made. OD-018/019 remain untouched;
resolved OD-026/027 are not reopened. No requirement or mandatory gate is waived.
