import AppKit
import Foundation

@MainActor
final class ProgressApp: NSObject, NSApplicationDelegate {
    let run: URL
    private var window: NSPanel!
    private var labels: [String: NSTextField] = [:]
    private var bars: [String: NSProgressIndicator] = [:]
    private var heading: NSTextField!
    private var timer: Timer?
    private var isRunning = true

    init(run: URL) { self.run = run }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        // Ordinary level, no activation/frontmost request: the tested app stays key.
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 12, y: screen.visibleFrame.minY + 12))
        }
        // Show without becoming key. The next tested app activation naturally
        // orders its normal window above this ordinary-level panel.
        window.orderFront(nil)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // The collector is a detached sibling process, not this app's child. Closing
    // progress ends only its UI helper; testing and retained results continue.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func revealReport() { NSWorkspace.shared.activateFileViewerSelecting([run]) }

    @objc private func cancelRun() {
        guard isRunning else { return }
        let alert = NSAlert()
        alert.messageText = "Cancel this testing run?"
        alert.informativeText = "Only processes created by this collector are stopped. Completed results remain available."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Cancel Run")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        try? Data().write(to: run.appendingPathComponent("cancel.request"), options: .atomic)
    }

    private func refresh() {
        guard let data = try? Data(contentsOf: run.appendingPathComponent("state.json")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stages = state["stages"] as? [String: [String: Any]] else { return }
        let status = state["status"] as? String ?? "running"
        isRunning = status == "running"
        let active = stages.filter { $0.value["status"] as? String == "running" }.keys.sorted().joined(separator: ", ")
        heading.stringValue = isRunning ? "Running: \(active.isEmpty ? "preparing" : active)" : "Testing \(status). Report retained."
        for key in ["code", "ui"] {
            guard let stage = stages[key], let label = labels[key], let bar = bars[key] else { continue }
            let completed = (stage["completed"] as? NSNumber)?.intValue ?? 0
            let total = (stage["total"] as? NSNumber)?.intValue
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
        // Completion remains visible until explicitly closed; closing never cancels.
    }
}

guard CommandLine.arguments.count == 2 else { exit(2) }
// Swift's script entry is the native main thread but is not implicitly actor
// isolated under every supported toolchain. Keep the entire AppKit lifecycle
// in one explicit main-actor scope; the delegate lives until app.run returns.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = ProgressApp(run: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
