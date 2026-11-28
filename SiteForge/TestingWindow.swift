import AppKit
import SwiftUI
import CoreImage

// SF-0206-002/003/004/006/008, SF-1607-002/004/008, SF-1902-007/008.
// These snapshots describe a collector receipt; they never own project content.
struct TestingRunSnapshot: Decodable, Equatable, Sendable {
    struct Stage: Decodable, Equatable, Sendable {
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
        let inventory: [String]?
        let inventoryMismatch: Bool?
        let timedCases: Int?
        let timedSeconds: Double?
    }
    struct Scope: Decodable, Equatable, Sendable {
        let mode: String
        let selectors: [String]
    }
    let status: String
    let mode: String?
    let runID: String?
    let startedAt: String?
    let finishedAt: String?
    let pauseStartedAt: String?
    let pausedSeconds: Double?
    let sourceFingerprint: String?
    let installedHarnessFingerprint: String?
    let scope: Scope?
    let stages: [String: Stage]?
    let activity: String?
    let pauseAvailable: Bool?

    var resolvedMode: String {
        if let scope { return scope.mode }
        if mode == "full", stages?["ui"]?.status == "skipped" { return "code" }
        if mode == "full", stages?["code"]?.status == "skipped" { return "ui" }
        return mode ?? "unknown"
    }
    var isOngoing: Bool { ["running", "pausing", "paused", "resuming", "cancelling"].contains(status) }
    var selectedStages: [Stage] {
        let names = resolvedMode == "ui" ? ["ui"] : resolvedMode == "code" ? ["code"] : ["code", "ui"]
        return names.compactMap { stages?[$0] }.filter { $0.status != "skipped" }
    }
    var activeStage: String? {
        ["preflight", "repository", "build", "code", "ui"].first { stages?[$0]?.status == "running" }
    }
    var isPreparing: Bool {
        guard let activeStage else { return isOngoing }
        return ["preflight", "repository", "build"].contains(activeStage) || stages?[activeStage]?.phase == "discovering"
    }
    var preparationDetail: String? {
        guard isOngoing, status != "paused", currentSelector == nil else { return nil }
        return activity ?? activeStage.flatMap { stages?[$0]?.phaseDetail }
            ?? (activeStage == "build" ? "Waiting for compiler activity" : "Checking source and test environment")
    }
    var hasPreparationEstimate: Bool { activeStage.flatMap { stages?[$0]?.estimatedSeconds } != nil }
    func preparationRemaining(at now: Date) -> Double? {
        guard status == "running", isPreparing, let activeStage, let stage = stages?[activeStage],
              let estimate = stage.estimatedSeconds, let start = Self.date(stage.startedAt) else { return nil }
        let elapsed = max(0, now.timeIntervalSince(start) - max(0, (pausedSeconds ?? 0) - (stage.pausedSecondsAtStart ?? 0)))
        return estimate > elapsed ? estimate - elapsed : nil
    }
    var currentEventIdentifier: String? { selectedStages.compactMap(\.currentTest).first }
    var currentSelector: String? {
        for (name, target) in [("code", "SiteForgeTests"), ("ui", "SiteForgeUITests")] {
            guard let stage = stages?[name], let raw = stage.currentTest, selectedStages.contains(stage) else { continue }
            let parts = raw.split(separator: "/")
            guard parts.count >= 2 else { return raw }
            let suite = String(parts[parts.count - 2].split(separator: ".").last ?? "")
            let method = String(parts.last!).replacingOccurrences(of: "()", with: "")
            return stage.inventory?.first { $0.hasSuffix("/" + suite + "/" + method) }
                ?? target + "/" + suite + "/" + method
        }
        return nil
    }
    var title: String {
        if status == "paused" { return "Testing paused" }
        if !isOngoing { return "Testing \(status)" }
        if let currentSelector { return Self.describe(currentSelector) }
        if let active = ["preflight", "repository", "build", "code", "ui"].first(where: { stages?[$0]?.status == "running" }) {
            if stages?[active]?.phase == "discovering" { return "Discovering prepared test methods" }
            return ["preflight": "Checking test environment", "repository": "Checking the repository",
                    "build": "Preparing test applications", "code": "Regular testing", "ui": "UI testing"][active] ?? "Preparing testing"
        }
        return "Preparing testing"
    }
    var modeLabel: String {
        resolvedMode == "code" ? "Regular testing" : resolvedMode == "ui" ? "UI testing"
            : resolvedMode == "full" ? (scope?.selectors.isEmpty == false ? "Combined testing" : "Full verification") : "Recorded testing"
    }
    var scopeSummary: String {
        guard let selectors = scope?.selectors, !selectors.isEmpty else { return modeLabel }
        return "\(selectors.count) requested selector\(selectors.count == 1 ? "" : "s") · \(modeLabel)"
    }
    var scopeLabel: String {
        if let selectors = scope?.selectors, !selectors.isEmpty { return selectors.joined(separator: "\n") }
        if scope == nil { return "Recorded \(resolvedMode) inventory; see exact methods below" }
        return resolvedMode == "code" ? "All regular tests" : resolvedMode == "ui" ? "All UI journeys" : "Full verification"
    }
    var completed: Int { selectedStages.reduce(0) { $0 + $1.completed } }
    var total: Int? {
        guard !selectedStages.isEmpty, selectedStages.allSatisfy({
            $0.total != nil && $0.inventoryMismatch != true && $0.completed <= ($0.total ?? 0)
        }) else { return nil }
        let count = selectedStages.reduce(0) { $0 + ($1.total ?? 0) }
        return count > 0 ? count : nil
    }
    func elapsed(at now: Date) -> TimeInterval? {
        guard let start = Self.date(startedAt) else { return nil }
        return max(0, (Self.date(finishedAt) ?? Self.date(pauseStartedAt) ?? now).timeIntervalSince(start) - (pausedSeconds ?? 0))
    }
    func remaining(at now: Date) -> TimeInterval? {
        if let estimate = preparationRemaining(at: now) { return estimate }
        guard status == "running", let total, completed < total else { return nil }
        var result = 0.0
        for stage in selectedStages {
            let remaining = (stage.total ?? 0) - stage.completed
            if remaining <= 0 { continue }
            let spent = Self.date(stage.currentTestStartedAt).map { max(0, now.timeIntervalSince($0)) } ?? 0
            if let estimate = stage.estimatedRemainingSeconds {
                result += max(0, estimate - min(spent, (stage.estimatedCurrentCaseSeconds ?? 0) * 0.75))
                continue
            }
            guard let samples = stage.timedCases, samples >= 2, let duration = stage.timedSeconds, duration > 0 else { return nil }
            let average = duration / Double(samples)
            result += average * Double(remaining) - min(spent, average * 0.75)
        }
        return result
    }
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
    static func describe(_ selector: String) -> String {
        let method = String(selector.split(separator: "/").last ?? "")
        let name = method.hasPrefix("test") ? String(method.dropFirst(4)) : method
        return name.replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
    }
    static func clock(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        let seconds = Int(max(0, value))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct TestingRunRecord: Identifiable, Equatable, Sendable {
    let url: URL
    let status: String
    let mode: String
    var id: String { url.path }
    var startedAt: String? = nil
    var title: String {
        guard let date = TestingRunSnapshot.date(startedAt) else { return "Undated run" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    var subtitle: String { "\(mode == "code" ? "Regular testing" : mode == "ui" ? "UI testing" : mode == "focused" ? "Combined testing" : mode == "full" ? "Full verification" : "Recorded testing") · \(status.capitalized)" }
    var label: String { title + " · " + subtitle }

}

enum TestingScopePolicy: String, CaseIterable, Identifiable {
    case all = "All tests in the selected target"
    case focused = "Exact selectors"
    case affected = "Affected features"
    var id: String { rawValue }
}

private struct TestingNativeProgress: NSViewRepresentable {
    let completed: Int
    let total: Int?
    let running: Bool
    func makeNSView(context: Context) -> NSProgressIndicator {
        let bar = NSProgressIndicator()
        bar.style = .bar; bar.controlSize = .small; bar.minValue = 0; bar.maxValue = 1
        bar.wantsLayer = true
        if let tint = CIFilter(name: "CIColorPolynomial") {
            tint.setValue(CIVector(x: 0, y: 1, z: -4, w: 0), forKey: "inputRedCoefficients")
            tint.setValue(CIVector(x: 0, y: 1.7, z: -2.5, w: 0), forKey: "inputGreenCoefficients")
            tint.setValue(CIVector(x: 0, y: 1, z: 3.5, w: 0), forKey: "inputBlueCoefficients")
            bar.contentFilters = [tint]
        }
        bar.setAccessibilityLabel("Testing progress")
        return bar
    }
    func updateNSView(_ bar: NSProgressIndicator, context: Context) {
        bar.isIndeterminate = total == nil
        if let total, total > 0 { bar.stopAnimation(nil); bar.doubleValue = Double(completed) / Double(total) }
        else if running { bar.startAnimation(nil) }
        else { bar.stopAnimation(nil) }
    }
}

struct SiteForgeTestingWindow: View {
    @ObservedObject var store: ExperimentalTestingStore
    @State private var confirmingCancel = false
    @State private var showingDetails = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Retained runs").font(.headline)
                Button("Current / Latest Run") { store.showRun(nil) }.accessibilityIdentifier("testing.history.latest")
                List(selection: Binding<URL?>(get: { store.displayedReport }, set: { if let url = $0 { store.showRun(url) } })) {
                    ForEach(store.history) { run in
                        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                            Text(run.title).font(.caption).lineLimit(2)
                            Text(run.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.tag(run.url).help(run.url.lastPathComponent)
                            .accessibilityIdentifier("testing.history." + run.url.lastPathComponent)
                            .accessibilityLabel(run.label).accessibilityValue(run.url.lastPathComponent)
                    }
                }
            }.padding(16).frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("SiteForge Testing").font(.title2.weight(.semibold))
                    if let request = store.requestDescription {
                        Text(request).font(.callout).accessibilityIdentifier("testing.request")
                    }
                    if let notice = store.presentationNotice {
                        Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .accessibilityIdentifier("testing.status")
                    }
                    if !store.harnessAvailable {
                        Text("Starting tests requires a current owner-local installation with its provisioned source and harness.")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("testing.unavailable")
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Scope", selection: $store.scopePolicy) {
                                ForEach(TestingScopePolicy.allCases) { Text($0.rawValue).tag($0) }
                            }.accessibilityIdentifier("testing.scope")
                            if store.scopePolicy == .focused {
                                TextField("Target/Class/testMethod, separated by spaces", text: $store.selectorText)
                                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("testing.selectors")
                            }
                            Text(store.scopeDescription).font(.caption).textSelection(.enabled)
                                .accessibilityIdentifier("testing.scope.description")
                            HStack {
                                Button { store.startPrepared(mode: "code") } label: {
                                    Text("Start Regular Testing").frame(width: SiteForgeVisualSystem.testingStartLabelWidth)
                                }
                                    .disabled(!store.canStart(mode: "code")).accessibilityIdentifier("testing.start.code")
                                Button { store.startPrepared(mode: "ui") } label: {
                                    Text("Start UI Testing").frame(width: SiteForgeVisualSystem.testingStartLabelWidth)
                                }
                                    .disabled(!store.canStart(mode: "ui")).accessibilityIdentifier("testing.start.ui")
                            }
                            Text("Regular: unit and integration tests. UI: native macOS journeys. Exact methods are discovered from the prepared build.")
                                .font(.caption).foregroundStyle(.secondary)
                            Divider()
                            HStack {
                                Button { store.startUISmoke() } label: {
                                    Text("Start UI Smoke Test").frame(width: SiteForgeVisualSystem.testingStartLabelWidth)
                                }
                                .accessibilityIdentifier("testing.start.smoke")
                                Button { store.run(mode: "full") } label: {
                                    Text("Start Full Verification").frame(width: SiteForgeVisualSystem.testingStartLabelWidth)
                                }
                                .accessibilityIdentifier("testing.start.full")
                            }
                            .disabled(store.running || !store.harnessAvailable)
                            Text("UI Smoke checks launch, editor layout and canvas input.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Explicit repository checks and both complete targets for major changes and pre-commit verification.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                    if let snapshot = store.snapshot {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(snapshot.title).font(.headline).lineLimit(2)
                                .frame(height: 34, alignment: .topLeading).accessibilityIdentifier("testing.current.title")
                            Text("Run scope: " + snapshot.scopeSummary).font(.caption).textSelection(.enabled)
                                .accessibilityIdentifier("testing.current.scope")
                            if snapshot.isOngoing {
                                // Reserve the live status slots so pausing, discovery and
                                // case-name changes never move the controls under the pointer.
                                Text(snapshot.status == "paused" ? "Desktop released. Resume continues unresolved methods from the same prepared build." : snapshot.preparationDetail ?? "").font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2).frame(height: 28, alignment: .topLeading)
                                    .accessibilityHidden(snapshot.status != "paused" && snapshot.preparationDetail == nil).accessibilityIdentifier("testing.activity")
                                Text(store.displayedPhase == "paused" ? "Results retained" : store.displayedPhase.capitalized)
                                    .font(.caption).frame(height: 14, alignment: .topLeading)
                                    .accessibilityIdentifier("testing.phase")
                            }
                            TestingNativeProgress(completed: snapshot.completed, total: snapshot.total, running: snapshot.status == "running").frame(height: 14)
                            Text(snapshot.total.map { "\(snapshot.completed)/\($0) complete · \($0 - snapshot.completed) remaining" }
                                 ?? (snapshot.isPreparing && snapshot.completed == 0 ? "Preparation activity · exact inventory pending" : "\(snapshot.completed) complete · total unknown")).font(.caption.monospacedDigit())
                            TimelineView(.periodic(from: .now, by: 1)) { clock in
                                HStack {
                                    Text("Elapsed \(TestingRunSnapshot.clock(snapshot.elapsed(at: clock.date)))")
                                    Spacer()
                                    Text(snapshot.status == "paused" ? "Paused · estimate resumes with testing"
                                         : snapshot.isOngoing && snapshot.status != "running" ? snapshot.status.capitalized + "…"
                                         : snapshot.isOngoing && snapshot.activity != nil ? "Retaining results…"
                                         : snapshot.remaining(at: clock.date).map {
                                        "\(snapshot.isPreparing ? "Phase estimate" : "Estimated remaining") \(TestingRunSnapshot.clock($0))"
                                    } ?? (snapshot.isPreparing && snapshot.hasPreparationEstimate ? "Estimate exceeded · still preparing" : snapshot.isOngoing ? "Estimate unavailable · no matching timing evidence" : "Run complete"))
                                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.frame(height: snapshot.isOngoing ? 28 : 14, alignment: .top)
                            if store.running && store.viewedRun == nil {
                                HStack(spacing: 8) {
                                    Button(action: { store.pauseOrResume() }) {
                                        Text(snapshot.status == "paused" ? "Resume" : "Pause").frame(maxWidth: .infinity)
                                    }
                                        .frame(width: 94, height: 24)
                                        .disabled(store.controlPending || snapshot.pauseAvailable == false || !["running", "paused"].contains(snapshot.status))
                                        .accessibilityIdentifier("testing.pause")
                                    Button {
                                        if confirmingCancel { store.cancel(); confirmingCancel = false }
                                        else {
                                            confirmingCancel = true
                                            Task { try? await Task.sleep(for: .seconds(6)); confirmingCancel = false }
                                        }
                                    } label: {
                                        Text(confirmingCancel ? "Confirm Cancel" : "Cancel").frame(maxWidth: .infinity)
                                    }.frame(width: 94, height: 24).disabled(store.cancellationRequested).accessibilityIdentifier("testing.cancel")
                                }.buttonStyle(.bordered).controlSize(.small)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Button { showingDetails.toggle() } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: showingDetails ? "chevron.down" : "chevron.right")
                                            .font(.caption).accessibilityHidden(true)
                                        Text("Run Details")
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("testing.details")
                                    .accessibilityValue(showingDetails ? "Expanded" : "Collapsed")
                                if showingDetails {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(snapshot.currentSelector ?? "No active case").accessibilityIdentifier("testing.current.selector")
                                    Text("Run: \(snapshot.runID ?? store.displayedReport?.lastPathComponent ?? "unknown")")
                                    Text("Scope: \(snapshot.scopeLabel)")
                                    Text("Started: \(snapshot.startedAt ?? "unknown")\nFinished: \(snapshot.finishedAt ?? "not finished")")
                                    Text("Source: \(snapshot.sourceFingerprint ?? "unavailable")")
                                    Text("Installed harness: \(snapshot.installedHarnessFingerprint ?? "developer launch")")
                                    ForEach(snapshot.selectedStages.flatMap { $0.inventory ?? [] }, id: \.self) { Text($0) }
                                }.font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    } else { Text(store.running ? "Preparing the selected test scope…" : "Choose a scope and start testing. Completed and interrupted runs remain available here.") }
                    HStack {
                        Button("Open Report") { store.openReport() }.disabled(store.displayedReport == nil)
                        Button("Reveal Logs") { store.revealReport() }.disabled(store.displayedReport == nil)
                        Button("Open Progress Details") { store.openProgress() }.disabled(store.report == nil)
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minWidth: 490)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.scopePolicy) { _,_ in Task { await store.prepareScope() } }
        .onChange(of: store.affectedBase) { _,_ in Task { await store.prepareScope() } }
        .onChange(of: store.selectorText) { _,_ in Task { await store.prepareScope() } }
        .task { await store.prepareScope(); await store.reloadHistory() }
        .onChange(of: store.snapshot?.status) { _, _ in Task { await store.reloadHistory() } }
        .onChange(of: store.running) { _, active in
            if !active { confirmingCancel = false; Task { await store.reloadHistory() } }
        }
        .onChange(of: store.report) { _,_ in confirmingCancel = false }
    }
}
