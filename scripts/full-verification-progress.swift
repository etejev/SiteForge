import AppKit
import Foundation
import CoreImage

private struct TestingProgressState: Decodable {
    struct Stage: Decodable {
        let status: String
        let completed: Int
        let total: Int?
        let phase: String?
        let phaseDetail: String?
        let startedAt: String?
        let pausedSecondsAtStart: Double?
        let estimatedSeconds: Double?
        let estimatedRemainingSeconds: Double?
        let estimatedCurrentCaseSeconds: Double?
        let currentTest: String?
        let currentTestStartedAt: String?
        let inventoryMismatch: Bool?
        let timedCases: Int?
        let timedSeconds: Double?
    }

    let mode: String
    let status: String
    let startedAt: String?
    let finishedAt: String?
    let pauseAvailable: Bool?
    let pauseStartedAt: String?
    let pausedSeconds: Double?
    let stages: [String: Stage]
    let activity: String?

    var isOngoing: Bool { ["running", "pausing", "paused", "resuming", "cancelling"].contains(status) }

    var activeStage: String? {
        ["preflight", "repository", "build", "code", "ui"].first { stages[$0]?.status == "running" }
    }

    var stageTitle: String {
        switch activeStage {
        case "preflight": "Checking test environment"
        case "repository": "Repository checks"
        case "build": "Building test apps"
        case "code" where stages["code"]?.phase == "discovering": "Finding code tests"
        case "ui" where stages["ui"]?.phase == "discovering": "Finding UI tests"
        case "code": "Code tests"
        case "ui": "UI automation"
        default: "Preparing tests"
        }
    }

    var isPreparing: Bool {
        guard let activeStage else { return isOngoing }
        return ["preflight", "repository", "build"].contains(activeStage) || stages[activeStage]?.phase == "discovering"
    }
    var preparationDetail: String {
        activity ?? activeStage.flatMap { stages[$0]?.phaseDetail }
            ?? (activeStage == "build" ? "Waiting for compiler activity" : "Checking source and test environment")
    }
    func preparationRemaining(at time: Date) -> Double? {
        guard status == "running", isPreparing, let activeStage, let stage = stages[activeStage],
              let estimate = stage.estimatedSeconds, let start = Self.timestamp(stage.startedAt) else { return nil }
        let active = max(0, time.timeIntervalSince(start) - max(0, (pausedSeconds ?? 0) - (stage.pausedSecondsAtStart ?? 0)))
        return estimate > active ? estimate - active : nil
    }
    var hasPreparationEstimate: Bool {
        activeStage.flatMap { stages[$0]?.estimatedSeconds } != nil
    }

    var currentTest: String? { activeStage.flatMap { stages[$0]?.currentTest } }

    private var selectedStages: [Stage] {
        let targets = mode == "ui" ? ["ui"] : mode == "code" ? ["code"] : ["code", "ui"]
        return targets.compactMap { stages[$0] }
    }

    var counts: (completed: Int, total: Int?) {
        let selected = selectedStages
        let completed = selected.reduce(0) { $0 + $1.completed }
        let totals = selected.compactMap(\.total)
        guard totals.count == (mode == "full" ? 2 : 1), selected.allSatisfy({
            $0.inventoryMismatch != true && $0.completed >= 0 && $0.completed <= ($0.total ?? 0)
        }) else { return (completed, nil) }
        let total = totals.reduce(0, +)
        return (completed, total > 0 ? total : nil)
    }

    func elapsed(at time: Date) -> Double? {
        guard let start = Self.timestamp(startedAt) else { return nil }
        let end = Self.timestamp(finishedAt) ?? Self.timestamp(pauseStartedAt) ?? time
        return max(0, end.timeIntervalSince(start) - (pausedSeconds ?? 0))
    }

    func estimatedRemaining(at time: Date) -> Double? {
        if let estimate = preparationRemaining(at: time) { return estimate }
        guard status == "running", let total = counts.total, counts.completed < total else { return nil }
        var seconds = 0.0
        for stage in selectedStages {
            let remaining = (stage.total ?? 0) - stage.completed
            guard remaining > 0 else { continue }
            let spent = Self.timestamp(stage.currentTestStartedAt).map { max(0, time.timeIntervalSince($0)) } ?? 0
            if let estimate = stage.estimatedRemainingSeconds {
                seconds += max(0, estimate - min(spent, (stage.estimatedCurrentCaseSeconds ?? 0) * 0.75))
                continue
            }
            guard let samples = stage.timedCases, samples >= 2,
                  let sampleSeconds = stage.timedSeconds, sampleSeconds > 0 else { return nil }
            let average = sampleSeconds / Double(samples)
            seconds += average * Double(remaining) - min(spent, average * 0.75)
        }
        return seconds.isFinite ? seconds : nil
    }

    private static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }
}

private final class TestingMonitorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TestingMonitorButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// Dynamic semantic fill redraws when the app appearance changes; a captured
// CGColor would freeze the initial palette in this independent helper process.
@MainActor
final class TestingProgressSurface: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setStroke()
        let boundary = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        boundary.lineWidth = 1
        boundary.stroke()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class ProgressApp: NSObject, NSApplicationDelegate {
    private static let monitorButtonSize = NSSize(width: 94, height: 24)
    private static let monitorButtonSpacing: CGFloat = 8
    private static let monitorButtonMargin: CGFloat = 14

    let run: URL
    private let monitor: Bool
    private var window: NSPanel!
    private var labels: [String: NSTextField] = [:]
    private var bars: [String: NSProgressIndicator] = [:]
    private var heading: NSTextField!
    private var monitorStage: NSTextField?
    private var monitorCounts: NSTextField?
    private var monitorBar: NSProgressIndicator?
    private var monitorElapsed: NSTextField?
    private var monitorETA: NSTextField?
    private var monitorClose: NSButton?
    private var monitorCancel: NSButton?
    private var cancelPanel: NSPanel?
    private var monitorPause: NSButton?
    private var pausePanel: NSPanel?
    private var displayStatus = "running"
    private var pauseActionFailed = false
    private var confirmCancelUntil: Date?
    private var cancelRequestFailed = false
    private var timer: Timer?
    private var isRunning = true

    init(run: URL, monitor: Bool) {
        self.run = run
        self.monitor = monitor
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearancePresentation(ProcessInfo.processInfo.environment["SITEFORGE_TESTING_APPEARANCE"] ?? "system")
        if let source = ProcessInfo.processInfo.environment["SITEFORGE_TESTING_APPEARANCE_SOURCE"] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(appearancePresentationChanged(_:)),
                name: .init("app.siteforge.testingAppearanceChanged"), object: source, suspensionBehavior: .deliverImmediately)
        }
        if monitor {
            makeMonitor()
            positionMonitor()
            window.orderFrontRegardless()
            if let cancelPanel { window.addChildWindow(cancelPanel, ordered: .above) }
        }
        else { makeDetails() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func appearancePresentationChanged(_ notification: Notification) {
        guard let value = notification.userInfo?["appearance"] as? String else { return }
        applyAppearancePresentation(value)
    }
    private func applyAppearancePresentation(_ value: String) {
        guard ["system", "light", "dark"].contains(value) else { return }
        NSApplication.shared.appearance = value == "system" ? nil
            : NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
        window?.contentView?.needsDisplay = true
    }

    private func makeMonitor() {
        let frame = NSRect(x: 0, y: 0, width: 428, height: 140)
        let panel = makeFloatingPanel(frame: frame, titled: true)
        panel.title = "SiteForge Testing"
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.isMovable = false

        let background = TestingProgressSurface(frame: frame)
        panel.contentView = background
        background.wantsLayer = true

        let stage = NSTextField(labelWithString: "Preparing tests")
        stage.frame = NSRect(x: 14, y: panel.contentLayoutRect.maxY - 22, width: 400, height: 16)
        stage.font = .systemFont(ofSize: 11)
        stage.textColor = .secondaryLabelColor
        background.addSubview(stage)
        monitorStage = stage

        heading = NSTextField(labelWithString: "Waiting for the first test…")
        heading.frame = NSRect(x: 14, y: stage.frame.minY - 24, width: 400, height: 21)
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.lineBreakMode = .byTruncatingMiddle
        background.addSubview(heading)

        let bar = NSProgressIndicator(frame: NSRect(x: 14, y: 43, width: 253, height: 14))
        bar.style = .bar
        bar.controlSize = .small
        bar.minValue = 0
        bar.maxValue = 1
        bar.setAccessibilityLabel("SiteForge test progress")
        bar.wantsLayer = true
        if let color = CIFilter(name: "CIColorPolynomial") {
            // AppKit dims background-window progress bars to gray. Map the
            // neutral fill to blue without changing the native bar's geometry.
            color.setValue(CIVector(x: 0, y: 1, z: -4, w: 0), forKey: "inputRedCoefficients")
            color.setValue(CIVector(x: 0, y: 1.7, z: -2.5, w: 0), forKey: "inputGreenCoefficients")
            color.setValue(CIVector(x: 0, y: 1, z: 3.5, w: 0), forKey: "inputBlueCoefficients")
            bar.contentFilters = [color]
        }
        background.addSubview(bar)
        monitorBar = bar

        let counts = NSTextField(labelWithString: "Counting tests…")
        counts.frame = NSRect(x: 275, y: 41, width: 139, height: 18)
        counts.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        counts.alignment = .right
        counts.lineBreakMode = .byTruncatingTail
        background.addSubview(counts)
        monitorCounts = counts

        let elapsed = NSTextField(labelWithString: "Elapsed 0:00")
        elapsed.frame = NSRect(x: 14, y: 15, width: 194, height: 17)
        elapsed.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        elapsed.textColor = .secondaryLabelColor
        background.addSubview(elapsed)
        monitorElapsed = elapsed

        let eta = NSTextField(labelWithString: "ETA calculating…")
        eta.frame = NSRect(x: 146, y: 15, width: 156, height: 17)
        eta.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        eta.textColor = .secondaryLabelColor
        eta.alignment = .right
        background.addSubview(eta)
        monitorETA = eta

        monitorClose = panel.standardWindowButton(.closeButton)
        monitorClose?.target = self
        monitorClose?.action = #selector(closeMonitor)
        monitorClose?.isEnabled = false
        // Keep the body click-through. The child window contains only Cancel.
        panel.ignoresMouseEvents = true
        window = panel

        (monitorCancel, cancelPanel) = makeMonitorButton("Cancel", action: #selector(cancelFromMonitor))
        (monitorPause, pausePanel) = makeMonitorButton("Pause", action: #selector(pauseFromMonitor))
    }

    private func makeMonitorButton(_ title: String, action: Selector) -> (NSButton, NSPanel) {
        let button = TestingMonitorButton(title: title, target: self, action: action)
        button.frame = NSRect(origin: .zero, size: Self.monitorButtonSize)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.setAccessibilityLabel("\(title) testing")
        let panel = makeFloatingPanel(frame: button.frame)
        panel.contentView = button
        return (button, panel)
    }

    private func monitorButtonFrame(in bounds: NSRect, trailingIndex: Int) -> NSRect {
        let width = Self.monitorButtonSize.width
        let offset = CGFloat(trailingIndex) * (width + Self.monitorButtonSpacing)
        let origin = NSPoint(x: bounds.maxX - Self.monitorButtonMargin - width - offset, y: bounds.minY + 11)
        return NSRect(origin: origin, size: Self.monitorButtonSize)
    }

    private func makeFloatingPanel(frame: NSRect, titled: Bool = false) -> NSPanel {
        let style: NSWindow.StyleMask = titled
            ? [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
            : [.borderless, .nonactivatingPanel]
        let panel = TestingMonitorPanel(contentRect: frame, styleMask: style,
                                        backing: .buffered, defer: false)
        panel.appearance = nil
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionMonitor() {
        guard monitor, let window, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: max(visible.minX, visible.maxX - window.frame.width - 12),
                                      y: max(visible.minY, visible.maxY - window.frame.height - 12)))
        cancelPanel?.setFrame(monitorButtonFrame(in: window.frame, trailingIndex: 0), display: false)
        pausePanel?.setFrame(monitorButtonFrame(in: window.frame, trailingIndex: 1), display: false)
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) { positionMonitor() }

    private func makeDetails() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 250))
        heading = NSTextField(wrappingLabelWithString: "Preparing local testing…")
        heading.frame = NSRect(x: 20, y: 204, width: 380, height: 34)
        content.addSubview(heading)
        for (index, key) in ["code", "ui"].enumerated() {
            let y = CGFloat(160 - index * 66)
            let label = NSTextField(labelWithString: key == "code" ? "Code testing — waiting" : "UI automation — waiting")
            label.frame = NSRect(x: 20, y: y, width: 380, height: 24)
            label.font = .systemFont(ofSize: 13)
            let bar = NSProgressIndicator(frame: NSRect(x: 20, y: y - 22, width: 380, height: 14))
            bar.style = .bar
            bar.minValue = 0
            bar.maxValue = 1
            bar.isIndeterminate = true
            labels[key] = label
            bars[key] = bar
            content.addSubview(label)
            content.addSubview(bar)
        }
        let reveal = NSButton(title: "Reveal Report", target: self, action: #selector(revealReport))
        reveal.frame = NSRect(x: 20, y: 16, width: 130, height: 32)
        let cancel = NSButton(title: "Cancel Run…", target: self, action: #selector(cancelRun))
        cancel.frame = NSRect(x: 260, y: 16, width: 140, height: 32)
        content.addSubview(reveal)
        content.addSubview(cancel)
        window = NSPanel(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.title = "SiteForge Testing Progress"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = true
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 12, y: screen.visibleFrame.minY + 12))
        }
        window.orderFront(nil)
    }

    // The collector is a detached sibling process, not this app's child. Closing
    // progress ends only its UI helper; testing and retained results continue.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !monitor }

    @objc private func revealReport() { NSWorkspace.shared.activateFileViewerSelecting([run]) }

    @objc private func closeMonitor() { NSApp.terminate(nil) }

    private var cancelRequest: URL { run.appendingPathComponent("cancel.request") }
    private var pauseRequest: URL { run.appendingPathComponent("pause.request") }
    private var resumeRequest: URL { run.appendingPathComponent("resume.request") }

    @objc private func pauseFromMonitor() {
        guard displayStatus == "running" || displayStatus == "paused" else { return }
        let request = displayStatus == "paused" ? resumeRequest : pauseRequest
        guard !FileManager.default.fileExists(atPath: request.path) else { return }
        do {
            try Data().write(to: request, options: .atomic)
            pauseActionFailed = false
        } catch {
            pauseActionFailed = true
        }
        refresh()
    }

    @objc private func cancelFromMonitor() {
        guard isRunning, !FileManager.default.fileExists(atPath: cancelRequest.path) else { return }
        if let event = NSApp.currentEvent, event.type == .leftMouseUp, event.clickCount > 1 { return }
        let time = Date()
        if let deadline = confirmCancelUntil, time < deadline {
            do {
                try Data().write(to: cancelRequest, options: .atomic)
                cancelRequestFailed = false
            } catch {
                cancelRequestFailed = true
            }
            confirmCancelUntil = nil
        } else {
            confirmCancelUntil = time.addingTimeInterval(5)
            cancelRequestFailed = false
        }
        refresh()
    }

    @objc private func cancelRun() {
        guard isRunning else { return }
        let alert = NSAlert()
        alert.messageText = "Cancel this testing run?"
        alert.informativeText = "Only processes created by this collector are stopped. Completed results remain available."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Cancel Run")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        try? Data().write(to: cancelRequest, options: .atomic)
    }

    private func refresh() {
        if monitor, !isRunning {
            retireIfSuperseded()
            return
        }
        guard let data = try? Data(contentsOf: run.appendingPathComponent("state.json")) else { return }
        if monitor {
            guard let state = try? JSONDecoder().decode(TestingProgressState.self, from: data) else { return }
            refreshMonitor(state)
            return
        }
        guard let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stages = state["stages"] as? [String: [String: Any]] else { return }
        let status = state["status"] as? String ?? "running"
        isRunning = status == "running"
        let active = stages.filter { $0.value["status"] as? String == "running" }.keys.sorted().joined(separator: ", ")
        let currentTest = stages.values.compactMap { $0["currentTest"] as? String }.first
        heading.stringValue = isRunning
            ? (currentTest.map { String($0.split(separator: "/").last ?? "") }
                ?? "Running: \(active.isEmpty ? "preparing" : active)")
            : "Testing \(status). Report retained."
        for key in ["code", "ui"] {
            guard let stage = stages[key], let label = labels[key], let bar = bars[key] else { continue }
            let completed = (stage["completed"] as? NSNumber)?.intValue ?? 0
            let reportedTotal = (stage["total"] as? NSNumber)?.intValue
            let total = stage["inventoryMismatch"] as? Bool == true ? nil : reportedTotal
            let outcome = stage["status"] as? String ?? "waiting"
            let title = key == "code" ? "Code testing" : "UI automation"
            let count = total.map { "\(completed)/\($0)" } ?? "\(completed) completed · total unknown"
            let failed = (stage["failed"] as? NSNumber)?.intValue ?? 0
            label.stringValue = "\(title): \(count) · \(outcome) · \(failed) failed"
            bar.isIndeterminate = total == nil
            if let total, total > 0 {
                bar.maxValue = Double(total)
                bar.doubleValue = Double(min(completed, total))
            } else if outcome == "running" { bar.startAnimation(nil) }
            else { bar.stopAnimation(nil) }
        }
    }

    private func refreshMonitor(_ state: TestingProgressState, at time: Date = Date()) {
        guard let stage = monitorStage, let counts = monitorCounts, let bar = monitorBar else { return }
        isRunning = state.isOngoing
        displayStatus = state.status
        let test = state.currentTest
        let name = test.map(Self.readableCaseName)
        let files = FileManager.default
        let cancelling = isRunning && files.fileExists(atPath: cancelRequest.path)
        let pausePending = state.status == "pausing" || files.fileExists(atPath: pauseRequest.path)
        let resumePending = state.status == "resuming" || files.fileExists(atPath: resumeRequest.path)
        stage.stringValue = state.status == "running" ? (state.activity == nil ? state.stageTitle : "Retaining diagnostics") : state.status.capitalized
        if state.status == "paused" {
            heading.stringValue = "Resume when you’re ready."
        } else {
            heading.stringValue = isRunning ? (name ?? state.preparationDetail) : "Results and logs are retained in Testing."
        }
        heading.setAccessibilityLabel(state.status == "paused" ? heading.stringValue : test ?? heading.stringValue)
        heading.toolTip = test ?? state.preparationDetail
        let (completed, total) = state.counts
        counts.stringValue = total.map { "\($0 - completed) left · \(completed)/\($0)" }
            ?? (state.isPreparing && completed == 0 ? "Activity · pending" : "\(completed) done · total unknown")
        bar.setAccessibilityLabel(state.isPreparing ? "Preparation activity, not measured completion" : "SiteForge test progress")
        counts.setAccessibilityLabel(total.map { "\(completed) of \($0) tests complete, \($0 - completed) remaining" }
                                     ?? "\(completed) tests complete. Total unknown.")
        if let total {
            if bar.isIndeterminate {
                bar.stopAnimation(nil)
                bar.isIndeterminate = false
            }
            bar.doubleValue = Double(completed) / Double(total)
        } else {
            bar.isIndeterminate = true
            if state.status == "running" { bar.startAnimation(nil) }
            else { bar.stopAnimation(nil) }
        }
        let elapsed = state.elapsed(at: time).map(Self.elapsedLabel) ?? "—"
        monitorElapsed?.stringValue = "Elapsed \(elapsed)"
        if isRunning {
            let pauseSupported = state.pauseAvailable == true
            if let bounds = window.contentView?.bounds {
                let firstButton = monitorButtonFrame(in: bounds, trailingIndex: pauseSupported ? 1 : 0)
                let etaWidth = firstButton.minX - Self.monitorButtonMargin - 114
                monitorETA?.frame = NSRect(x: 114, y: 15, width: etaWidth, height: 17)
            }
            if pauseSupported, window.isVisible, let pausePanel, pausePanel.parent == nil {
                window.addChildWindow(pausePanel, ordered: .above)
            }
            monitorPause?.title = state.status == "paused" ? "Resume" : "Pause"
            monitorPause?.setAccessibilityLabel(state.status == "paused" ? "Resume testing" : "Pause testing")
            monitorPause?.isEnabled = pauseSupported && !cancelling && !pausePending && !resumePending
            if cancelling {
                monitorETA?.stringValue = "Cancelling…"
            } else if cancelRequestFailed {
                monitorETA?.stringValue = "Cancel request failed"
            } else if pauseActionFailed {
                monitorETA?.stringValue = "Request failed"
            } else if resumePending {
                monitorETA?.stringValue = "Resuming…"
            } else if pausePending {
                monitorETA?.stringValue = "Pausing…"
            } else if state.status == "paused" {
                monitorETA?.stringValue = ""
            } else {
                if let remaining = state.estimatedRemaining(at: time) {
                    monitorETA?.stringValue = "Est. \(Self.etaLabel(remaining))"
                } else if state.isPreparing && state.hasPreparationEstimate {
                    monitorETA?.stringValue = "Still preparing"
                } else {
                    monitorETA?.stringValue = state.activity != nil ? "Retaining…" : "ETA unavailable"
                }
                monitorETA?.toolTip = state.isPreparing
                    ? "Estimated remaining time for this preparation phase, based on matching local timing history. Activity animation is not measured completion."
                    : "Estimated remaining testing time from matched cases and fresh measurements. New methods need timing evidence."
            }
            let confirming = confirmCancelUntil.map { time < $0 } ?? false
            monitorCancel?.title = confirming ? "Confirm Cancel" : "Cancel"
            monitorCancel?.setAccessibilityLabel(confirming ? "Confirm cancellation of testing" : "Cancel testing")
            monitorCancel?.isEnabled = !cancelling
        } else {
            monitorETA?.stringValue = "Run complete"
            monitorETA?.frame = NSRect(x: 208, y: 15, width: 206, height: 17)
            monitorClose?.isEnabled = true
            if let cancelPanel {
                window.removeChildWindow(cancelPanel)
                cancelPanel.orderOut(nil)
            }
            if let pausePanel, pausePanel.parent != nil {
                window.removeChildWindow(pausePanel)
                pausePanel.orderOut(nil)
            }
            window.ignoresMouseEvents = false
            retireIfSuperseded()
        }
    }

    private func retireIfSuperseded() {
        let latest = run.deletingLastPathComponent().appendingPathComponent("current.json")
        if let data = try? Data(contentsOf: latest),
           let record = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let current = record["run"],
           URL(fileURLWithPath: current).standardizedFileURL.path != run.standardizedFileURL.path {
            closeMonitor()
        }
    }

    private static func elapsedLabel(_ seconds: Double) -> String {
        let value = Int(seconds)
        if value >= 3_600 {
            return String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60)
        }
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private static func readableCaseName(_ identity: String) -> String {
        let method = String(identity.split(separator: "/").last ?? "")
        let name = method.hasPrefix("test") ? String(method.dropFirst(4)) : method
        return name.replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    private static func etaLabel(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes > 60 {
            return "~\(minutes / 60)h \(minutes % 60)m"
        }
        return minutes <= 1 ? "<1m" : "~\(minutes)m"
    }
}

let arguments = CommandLine.arguments
let monitor = arguments.count == 3 && arguments[2] == "--monitor"
guard arguments.count == 2 || monitor else { exit(2) }
// Swift's script entry is the native main thread but is not implicitly actor
// isolated under every supported toolchain. Keep the entire AppKit lifecycle
// in one explicit main-actor scope; the delegate lives until app.run returns.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = ProgressApp(run: URL(fileURLWithPath: arguments[1], isDirectory: true), monitor: monitor)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
