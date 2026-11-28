// SF-0206-006/008, SF-1607-004/008, SF-1902-007/008.
// Compiled with the real helper by test_testing_progress.py.
func verify(_ data: String, stage: String, test: String?, completed: Int, total: Int?) throws {
    let state = try JSONDecoder().decode(TestingProgressState.self, from: Data(data.utf8))
    precondition(state.stageTitle == stage)
    precondition(state.currentTest == test)
    precondition(state.counts.completed == completed && state.counts.total == total)
}

try verify(
    #"{"mode":"full","status":"running","stages":{"code":{"status":"running","completed":12,"total":32,"currentTest":"SiteForgeTests.Sample/testCode"},"ui":{"status":"waiting","completed":0,"total":14}}}"#,
    stage: "Code tests", test: "SiteForgeTests.Sample/testCode", completed: 12, total: 46
)
try verify(
    #"{"mode":"full","status":"running","stages":{"code":{"status":"passed","completed":32,"total":32},"ui":{"status":"running","completed":4,"total":14,"currentTest":"SiteForgeUITests.Sample/testSafari"}}}"#,
    stage: "UI automation", test: "SiteForgeUITests.Sample/testSafari", completed: 36, total: 46
)
try verify(
    #"{"mode":"ui","status":"running","stages":{"code":{"status":"skipped","completed":0},"ui":{"status":"running","completed":4,"total":14}}}"#,
    stage: "UI automation", test: nil, completed: 4, total: 14
)
try verify(
    #"{"mode":"full","status":"running","stages":{"code":{"status":"waiting","completed":0,"total":32},"ui":{"status":"running","completed":0,"phase":"discovering"}}}"#,
    stage: "Finding UI tests", test: nil, completed: 0, total: nil
)
try verify(
    #"{"mode":"ui","status":"cancelled","stages":{"ui":{"status":"cancelled","completed":4,"total":14}}}"#,
    stage: "Preparing tests", test: nil, completed: 4, total: 14
)

try verify(
    #"{"mode":"ui","status":"running","stages":{"ui":{"status":"running","completed":4,"total":14,"currentTest":"SiteForgeUITests.Sample/testRenamed","inventoryMismatch":true}}}"#,
    stage: "UI automation", test: "SiteForgeUITests.Sample/testRenamed", completed: 4, total: nil
)

let decoder = JSONDecoder()
let clock = try Date.ISO8601FormatStyle().parse("2026-11-15T17:41:28Z")
private let live = try decoder.decode(TestingProgressState.self, from: Data(
    #"{"mode":"ui","status":"running","startedAt":"2026-11-15T17:00:00.000000+00:00","stages":{"ui":{"status":"running","completed":36,"total":129,"timedCases":36,"timedSeconds":2370,"currentTestStartedAt":"2026-11-15T17:41:10.000000+00:00"}}}"#.utf8))
precondition(live.elapsed(at: clock) == 2488)
precondition(live.estimatedRemaining(at: clock) == 6104.5)
private let preparing = try decoder.decode(TestingProgressState.self, from: Data(
    #"{"mode":"full","status":"running","stages":{"code":{"status":"running","completed":30,"total":40,"timedCases":30,"timedSeconds":15},"ui":{"status":"waiting","completed":0,"total":14}}}"#.utf8))
precondition(preparing.estimatedRemaining(at: clock) == nil)
private let finished = try decoder.decode(TestingProgressState.self, from: Data(
    #"{"mode":"ui","status":"passed","startedAt":"2026-11-15T17:00:00Z","finishedAt":"2026-11-15T17:01:02Z","stages":{"ui":{"status":"passed","completed":2,"total":2}}}"#.utf8))
precondition(finished.elapsed(at: clock) == 62)
precondition(finished.estimatedRemaining(at: clock) == nil)
print("Passed 9 monitor state and timing fixtures")

extension ProgressApp {
    func verifyPauseControl() throws {
        let files = FileManager.default
        try files.createDirectory(at: run, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: run) }
        let stateFile = run.appendingPathComponent("state.json")
        let live = #"{"mode":"ui","status":"running","pauseAvailable":true,"stages":{"ui":{"status":"running","completed":4,"total":12}}}"#
        try Data(live.utf8).write(to: stateFile, options: .atomic)
        makeMonitor()
        precondition(!applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        refresh()
        precondition(monitorCancel?.frame.size == monitorPause?.frame.size)
        precondition(monitorPause?.frame.size == NSSize(width: 94, height: 24))
        let left = monitorButtonFrame(in: window.contentView!.bounds, trailingIndex: 1)
        let right = monitorButtonFrame(in: window.contentView!.bounds, trailingIndex: 0)
        precondition(left.minY == right.minY && right.minX - left.maxX == 8)
        precondition(monitorETA!.frame.maxX <= left.minX - 14)
        precondition(monitorPause?.title == "Pause")
        precondition(monitorPause?.isEnabled == true)
        precondition(monitorBar?.style == .bar && monitorBar?.controlSize == .small)
        precondition(monitorBar?.contentFilters.first?.name == "CIColorPolynomial")
        let originalAppearance = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = originalAppearance }
        for (choice, expected) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            applyAppearancePresentation(choice)
            precondition(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
            precondition(cancelPanel?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
            precondition(pausePanel?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
            precondition(window.backgroundColor == NSColor.windowBackgroundColor)
            precondition(window.contentView is TestingProgressSurface)
            precondition(monitorCancel?.frame.size == monitorPause?.frame.size)
        }
        for appearance in [NSAppearance.Name.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            // AppKit normalizes accessibility names to Aqua/Dark Aqua when
            // Increase Contrast is off. Verify the appearance it actually
            // returns; this fixture never changes the owner's system setting.
            let resolved = NSAppearance(named: appearance)!
            NSApplication.shared.appearance = resolved
            precondition(window.effectiveAppearance.name == resolved.name)
            precondition(window.isOpaque && window.contentView!.isOpaque)
            precondition(monitorCancel?.frame.size == monitorPause?.frame.size)
        }
        applyAppearancePresentation("system")
        precondition(NSApplication.shared.appearance == nil)
        applyAppearancePresentation("invalid")
        precondition(NSApplication.shared.appearance == nil)
        print("Passed semantic system-gray surfaces and scoped appearance presentation assertions")
        pauseFromMonitor()
        precondition(files.fileExists(atPath: pauseRequest.path))
        precondition(monitorETA?.stringValue == "Pausing…")
        precondition(monitorPause?.isEnabled == false)
        try files.removeItem(at: pauseRequest)
        let paused = #"{"mode":"ui","status":"paused","pauseAvailable":true,"startedAt":"2026-11-15T17:00:00Z","pauseStartedAt":"2026-11-15T17:00:16Z","stages":{"ui":{"status":"paused","completed":4,"total":12}}}"#
        try Data(paused.utf8).write(to: stateFile, options: .atomic)
        refresh()
        precondition(monitorElapsed?.stringValue == "Elapsed 0:16")
        precondition(monitorCancel?.frame.size == monitorPause?.frame.size)
        precondition(monitorPause?.frame.size == NSSize(width: 94, height: 24))
        precondition(monitorPause?.title == "Resume")
        precondition(monitorPause?.isEnabled == true)
        precondition(monitorCancel?.isEnabled == true)
        pauseFromMonitor()
        precondition(files.fileExists(atPath: resumeRequest.path))
        precondition(monitorETA?.stringValue == "Resuming…")
        print("Passed native rounded bar with blue tint, pause and resume request, and frozen elapsed time assertions")
    }
}
try MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("siteforge-monitor-pause-" + UUID().uuidString)
    try ProgressApp(run: path, monitor: true).verifyPauseControl()
}

extension ProgressApp {
    func verifyCancellation() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: run, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: run) }
        let stateFile = run.appendingPathComponent("state.json")
        let live = #"{"mode":"ui","status":"running","stages":{"ui":{"status":"running","completed":4,"total":12}}}"#
        try Data(live.utf8).write(to: stateFile, options: .atomic)
        makeMonitor()
        precondition(!applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        refresh()
        precondition(monitorCancel?.frame.size == monitorPause?.frame.size)
        precondition(monitorPause?.frame.size == NSSize(width: 94, height: 24))
        precondition(window.ignoresMouseEvents)
        precondition(cancelPanel?.ignoresMouseEvents == false)
        precondition(monitorCancel?.title == "Cancel")
        cancelFromMonitor()
        precondition(!fileManager.fileExists(atPath: cancelRequest.path))
        precondition(monitorCancel?.frame.size == monitorPause?.frame.size)
        precondition(monitorPause?.frame.size == NSSize(width: 94, height: 24))
        precondition(monitorCancel?.title == "Confirm Cancel")
        confirmCancelUntil = .distantPast
        refresh()
        precondition(monitorCancel?.title == "Cancel")
        cancelFromMonitor()
        cancelFromMonitor()
        precondition(fileManager.fileExists(atPath: cancelRequest.path))
        precondition(monitorETA?.stringValue == "Cancelling…")
        precondition(monitorCancel?.isEnabled == false)
        let cancelled = #"{"mode":"ui","status":"cancelled","stages":{"ui":{"status":"cancelled","completed":4,"total":12}}}"#
        try Data(cancelled.utf8).write(to: stateFile, options: .atomic)
        refresh()
        precondition(monitorStage?.stringValue == "Cancelled")
        precondition(monitorCounts?.stringValue == "8 left · 4/12")
        precondition(monitorClose?.isEnabled == true)
        print("Passed click-through, confirmation, expiration, cancellation request, and terminal result assertions")
    }
}
try MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("siteforge-monitor-cancel-" + UUID().uuidString)
    try ProgressApp(run: path, monitor: true).verifyCancellation()
}
