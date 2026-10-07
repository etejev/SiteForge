import AppKit

final class ProgressApp: NSObject, NSApplicationDelegate {
    private let stateURL: URL
    private let logURL: URL
    private var window: NSWindow!
    private var indicator: NSProgressIndicator!
    private var phaseLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var elapsedLabel: NSTextField!
    private var progressLabel: NSTextField!
    private var timer: Timer?
    private let startedAt = Date()

    init(statePath: String, logPath: String) {
        stateURL = URL(fileURLWithPath: statePath)
        logURL = URL(fileURLWithPath: logPath)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 176))

        phaseLabel = NSTextField(labelWithString: "Preparing full verification…")
        phaseLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        phaseLabel.frame = NSRect(x: 24, y: 126, width: 412, height: 24)

        detailLabel = NSTextField(wrappingLabelWithString: "SiteForge will continue testing without Codex interaction.")
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 24, y: 88, width: 412, height: 34)

        indicator = NSProgressIndicator(frame: NSRect(x: 24, y: 64, width: 412, height: 12))
        indicator.style = .bar
        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = 100
        indicator.doubleValue = 0

        progressLabel = NSTextField(labelWithString: "0%")
        progressLabel.alignment = .right
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.frame = NSRect(x: 276, y: 43, width: 160, height: 18)

        elapsedLabel = NSTextField(labelWithString: "Elapsed: 0m")
        elapsedLabel.textColor = .secondaryLabelColor
        elapsedLabel.frame = NSRect(x: 24, y: 24, width: 210, height: 22)

        let revealButton = NSButton(title: "Reveal Log", target: self, action: #selector(revealLog))
        revealButton.bezelStyle = .rounded
        revealButton.frame = NSRect(x: 332, y: 18, width: 104, height: 30)

        [phaseLabel, detailLabel, indicator, progressLabel, elapsedLabel, revealButton].forEach(content.addSubview)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 176),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SiteForge Verification"
        window.contentView = content
        window.center()
        window.isReleasedWhenClosed = false
        // Stay visible without becoming key or active. UI verification must
        // retain ownership of the frontmost SiteForge window and first
        // responder throughout native menu, pointer, and keyboard journeys.
        window.orderFrontRegardless()

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    private func refresh() {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        elapsedLabel.stringValue = "Elapsed: \(elapsed / 60)m \(elapsed % 60)s"

        guard let data = try? Data(contentsOf: stateURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 4 else { return }

        let status = lines[0]
        phaseLabel.stringValue = lines[1]
        detailLabel.stringValue = lines[2]
        let progress = min(100, max(0, Double(lines[3]) ?? indicator.doubleValue))
        indicator.doubleValue = progress
        progressLabel.stringValue = "\(Int(progress.rounded()))%"

        if status != "RUNNING" {
            switch status {
            case "PASSED":
                indicator.doubleValue = 100
                progressLabel.stringValue = "100% • Passed"
                elapsedLabel.stringValue += " • Passed"
            case "ISSUES":
                indicator.doubleValue = 100
                progressLabel.stringValue = "100% • Completed with Issues"
                elapsedLabel.stringValue += " • Completed with Issues"
            default:
                indicator.doubleValue = 0
                elapsedLabel.stringValue += " • Stopped"
            }
            timer?.invalidate()
            NSApp.requestUserAttention(.informationalRequest)
            Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
                NSApp.terminate(nil)
            }
        }
    }
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: full-verification-progress.swift <state-file> <log-file>\n", stderr)
    exit(2)
}

let app = NSApplication.shared
let delegate = ProgressApp(statePath: CommandLine.arguments[1], logPath: CommandLine.arguments[2])
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
