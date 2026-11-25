import SwiftUI

/// Website configuration is edited with native controls. Animation runs only
/// in explicit website preview/output, never in the ordinary edit canvas.
struct DecorativeEffectsInspector: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var showsLivePreview = false
    private var node: DocumentNode? { state.selectedCanonicalNodes.count == 1 ? state.selectedCanonicalNodes.first : nil }
    private var flow: CanonicalFlowGradient? { node.flatMap { try? CanonicalFlowGradient.resolve($0) } }
    private var glass: CanonicalGlassSurface? { node.flatMap { try? CanonicalGlassSurface.resolve($0) } }
    private var flowSupported: Bool { node.map { [.frame, .section].contains($0.kind) } ?? false }
    private var glassSupported: Bool { node.map { [.frame, .section, .stack, .grid, .button].contains($0.kind) } ?? false }
    var body: some View {
        if flowSupported || glassSupported {
            GroupBox("Website Effects") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    if flowSupported {
                        Toggle("Flowing gradient", isOn: Binding(get: { flow?.enabled == true }, set: { enabled in
                            var next = flow ?? .defaults; next.enabled = enabled
                            commit(.flow(next))
                        })).accessibilityIdentifier("inspector.effects.flow.enabled")
                        if let flow, flow.enabled {
                            if let node, CanonicalFlowGradient.gradient(on: node) == nil {
                                Text(CanonicalFlowGradient.unavailableReason).font(.caption).foregroundStyle(.secondary)
                            }
                            effectNumber("Pull radius", value: flow.radius, range: 24...1_200, unit: "px", key: "radius") { var next = flow; next.radius = $0; return .flow(next) }
                            effectNumber("Pull strength", value: flow.strength * 100, range: 0...100, unit: "%", key: "strength") { var next = flow; next.strength = $0 / 100; return .flow(next) }
                            effectNumber("Follow response", value: flow.response, range: 0.5...30, unit: "/s", key: "response") { var next = flow; next.response = $0; return .flow(next) }
                            effectNumber("Return smoothing", value: flow.returnSeconds, range: 0.1...5, unit: "s", key: "return") { var next = flow; next.returnSeconds = $0; return .flow(next) }
                            Text("Higher response follows motion faster. Return smoothing is the time for displacement to decay to 37%. Preview the website to move the gradient.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(showsLivePreview ? "Close Live Effect Preview" : "Live Effect Preview") { showsLivePreview.toggle() }
                                .accessibilityIdentifier("inspector.effects.flow.preview")
                            if showsLivePreview, let previewNode = state.previewedDesignStyleNode,
                               let configuration = try? DecorativeEffectOutput.configuration(previewNode) {
                                FlowEffectPreview(configuration: configuration).frame(height: 180)
                                Text("Move the pointer over this preview. The edit canvas stays still. Reduced Motion and touch-only input use the static gradient.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Button("Reset Flow") { commit(.flow(.defaults)) }.accessibilityIdentifier("inspector.effects.flow.reset")
                        }
                    }
                    if glassSupported {
                        Toggle("Glass surface", isOn: Binding(get: { glass != nil }, set: { enabled in
                            commit(.glass(enabled ? .init(blur: 16, fallback: .legacySurface) : nil))
                        })).accessibilityIdentifier("inspector.effects.glass.enabled")
                        if let glass {
                            EffectNumberControl(state: state, label: "Backdrop blur", value: glass.blur, range: 0...60, unit: "px", identifier: "inspector.effects.glass.blur") { var next = glass; next.blur = $0; return .glass(next) }
                            DesignColorEditor(state: state, color: glass.fallback, isEnabled: true,
                                label: "Opaque glass fallback", identifier: "inspector.effects.glass.fallback", allowsAlpha: false,
                                edit: { color in var next = glass; next.fallback = color; return .effect(.glass(next)) })
                            Toggle("Dark opaque fallback", isOn: Binding(get: { glass.darkFallback != nil }, set: { enabled in
                                var next = glass; next.darkFallback = enabled ? glass.fallback : nil; commit(.glass(next))
                            })).accessibilityIdentifier("inspector.effects.glass.dark.enabled")
                            if let color = glass.darkFallback {
                                DesignColorEditor(state: state, color: color, isEnabled: true,
                                    label: "Dark opaque glass fallback", identifier: "inspector.effects.glass.dark.color", allowsAlpha: false,
                                    edit: { color in var next = glass; next.darkFallback = color; return .effect(.glass(next)) })
                            }
                            Text("The opaque fallback is used without backdrop support or when reduced transparency is requested.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } else if state.selectedCanonicalNodes.count > 1 {
            Text("Select one object to edit website effects. Mixed effects are preserved.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func effectNumber(_ label: String, value: Double, range: ClosedRange<Double>, unit: String, key: String,
                              edit: @escaping (Double) -> DecorativeEffectEdit) -> some View {
        EffectNumberControl(state: state, label: label, value: value, range: range, unit: unit,
                            identifier: "inspector.effects.flow." + key, edit: edit)
    }
    private func commit(_ edit: DecorativeEffectEdit) {
        guard state.prepareForWorkspaceAction(.context) else { return }
        let owner = UUID()
        if state.previewDesignStyle(.effect(edit), owner: owner) { _ = state.finishDesignStylePreview(owner: owner) }
    }
}

private struct EffectNumberControl: View {
    @ObservedObject var state: WorkspaceShellState
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let unit: String
    let identifier: String
    let edit: (Double) -> DecorativeEffectEdit
    @State private var owner = UUID()
    @State private var draft: String?
    @State private var displayed: Double?
    @State private var context: ResponsiveInspectorEditContext?
    @State private var validation: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption)
            HStack(spacing: 6) {
                DesignStyleSlider(minimum: range.lowerBound, value: displayed ?? value,
                    maximum: range.upperBound, isEnabled: true, label: label + " " + unit,
                    identifier: identifier + ".slider", context: state.responsiveInspectorEditContext,
                    begin: { validation == nil }, preview: { update($0) }, finish: { _ = finish() }, cancel: { cancel() })
                TextField(label, text: Binding(get: { draft ?? DesignStyleNumberText.string(displayed ?? value) }, set: { text in
                    guard text != (draft ?? DesignStyleNumberText.string(displayed ?? value)) else { return }
                    if context == nil { context = state.responsiveInspectorEditContext }
                    draft = text
                    guard let next = Double(text), next.isFinite, range.contains(next) else {
                        validation = "Enter \(DesignStyleNumberText.string(range.lowerBound))–\(DesignStyleNumberText.string(range.upperBound)) \(unit)."; return
                    }
                    update(next)
                })).textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 65)
                    .focused($focused).onSubmit { _ = finish() }
                    .onChange(of: focused) { old, new in if old && !new { _ = finish() } }
                    .accessibilityLabel(label + " " + unit).accessibilityIdentifier(identifier + ".value")
                Text(unit).font(.caption).foregroundStyle(.secondary).frame(minWidth: 18)
            }
            if let validation { Text(validation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger) }
        }
        .onExitCommand { cancel() }
        .onDisappear { cancel() }
        .onChange(of: state.responsiveInspectorEditContext) { _, _ in cancel() }
        .onReceive(state.designStyleCancellation) { cancel() }
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted, draft != nil || displayed != nil else { return }
            if request.requiresCleanEditors || !finish() { request.reject() }
        }
    }
    private func update(_ next: Double) {
        if context == nil { context = state.responsiveInspectorEditContext }
        guard state.previewDesignStyle(.effect(edit(next)), owner: owner, expectedContext: context) else {
            validation = state.lastDesignInspectorAnnouncement; return
        }
        displayed = next; validation = nil
    }
    @discardableResult private func finish() -> Bool {
        guard validation == nil else { return false }
        guard state.finishDesignStylePreview(owner: owner) else { validation = state.lastDesignInspectorAnnouncement; return false }
        draft = nil; displayed = nil; context = nil; return true
    }
    private func cancel() {
        state.cancelDesignStylePreview(owner: owner); draft = nil; displayed = nil; context = nil; validation = nil
    }
}


import WebKit

/// A deliberately opened, isolated website effect preview. There are no app
/// message handlers, filesystem access or remote requests in this WebKit view.
struct FlowEffectPreview: NSViewRepresentable {
    let configuration: FlowOutputConfiguration
    func makeCoordinator() -> Coordinator { Coordinator(configuration: configuration) }
    func makeNSView(context: Context) -> WKWebView {
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .nonPersistent()
        settings.setURLSchemeHandler(context.coordinator, forURLScheme: "siteforge-effect")
        let view = WKWebView(frame: .zero, configuration: settings)
        view.navigationDelegate = context.coordinator
        view.setAccessibilityLabel("Live flowing gradient preview")
        view.load(URLRequest(url: URL(string: "siteforge-effect://preview/index.html")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.configuration != configuration else { return }
        context.coordinator.configuration = configuration
        context.coordinator.update(view)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }
    @MainActor final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
        var configuration: FlowOutputConfiguration
        private var ready = false
        init(configuration: FlowOutputConfiguration) { self.configuration = configuration }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; update(webView) }
        func update(_ webView: WKWebView) {
            guard ready else { return }
            // Only validated numeric configuration is serialized. The program
            // itself is fixed SiteForge-owned code and has no author text.
            webView.evaluateJavaScript("""
                (()=>{const c=\(configuration.json),e=document.getElementById('preview');
                e.style.backgroundImage='linear-gradient('+(c.angle+90)+'deg,'+c.stops.map(s=>'rgba('+s.red*255+','+s.green*255+','+s.blue*255+','+s.alpha+') '+s.position*100+'%').join(',')+')';
                window.SiteForgeDecorativeEffects.update(e,c);})();
                """)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.scheme == "siteforge-effect" ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url, url.host == "preview" else {
                urlSchemeTask.didFailWithError(URLError(.resourceUnavailable)); return
            }
            let content: String, type: String
            switch url.path {
            case "/index.html":
                content = Self.html(configuration); type = "text/html"
            case "/effect.js": content = DecorativeEffectRuntime.javascript; type = "text/javascript"
            case "/preview.css": content = Self.css; type = "text/css"
            default: urlSchemeTask.didFailWithError(URLError(.resourceUnavailable)); return
            }
            let data = Data(content.utf8)
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: "utf-8"))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
        static let css = """
        html,body { margin:0;width:100%;height:100%;overflow:hidden; }
        #preview { width:100%;height:100%;position:relative; }
        """ + DecorativeEffectRuntime.css
        static func html(_ config: FlowOutputConfiguration) -> String {
            let escaped = config.json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none';script-src siteforge-effect:;style-src siteforge-effect:;connect-src 'none';img-src 'none';base-uri 'none';form-action 'none'"><link rel="stylesheet" href="preview.css"></head><body><div id="preview" data-siteforge-flow="\(escaped)"></div><script src="effect.js"></script></body></html>
            """
        }
    }
}

