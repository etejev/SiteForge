import Foundation
@preconcurrency import WebKit

private struct BrowserFrame: Decodable {
    let id: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

@MainActor
private final class BrowserOracle: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var webView: WKWebView?

    func frames(html: String, viewport: LayoutSize) async throws -> [NodeID: LayoutRect] {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: viewport.width, height: viewport.height),
            configuration: configuration
        )
        view.navigationDelegate = self
        webView = view
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard view.loadHTMLString(html, baseURL: nil) != nil else {
                self.continuation = nil
                continuation.resume(throwing: EvidenceError.browserFailure)
                return
            }
        }
        let script = """
        JSON.stringify(Array.from(document.querySelectorAll('[data-layout-id]')).map(element => {
          const frame = element.getBoundingClientRect();
          return {id: element.dataset.layoutId, x: frame.x, y: frame.y, width: frame.width, height: frame.height};
        }))
        """
        guard let json = try await view.evaluateJavaScript(script) as? String,
              let data = json.data(using: .utf8) else { throw EvidenceError.browserFailure }
        let decoded = try JSONDecoder().decode([BrowserFrame].self, from: data)
        view.stopLoading()
        webView = nil
        return try Dictionary(uniqueKeysWithValues: decoded.map { item in
            guard let id = NodeID(uuidString: item.id) else { throw EvidenceError.browserFailure }
            return (id, LayoutRect(
                origin: LayoutPoint(x: item.x, y: item.y),
                size: LayoutSize(width: item.width, height: item.height)
            ))
        })
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private struct LayoutHTMLOracleAdapter {
    func document(snapshot: LayoutSnapshot, viewport: LayoutSize) throws -> String {
        let nodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        guard let root = nodes[snapshot.rootID] else { throw EvidenceError.invalidFixture }
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden}
        *{box-sizing:border-box}.node{position:relative;border:0;background:transparent}
        </style></head><body>\(try element(
            root, parentAxis: nil, isRoot: true, nodes: nodes,
            catalog: snapshot.intrinsicCatalog, viewport: viewport
        ))</body></html>
        """
    }

    private func element(
        _ node: LayoutNodeSnapshot,
        parentAxis: LayoutAxis?,
        isRoot: Bool,
        nodes: [NodeID: LayoutNodeSnapshot],
        catalog: LayoutIntrinsicCatalog,
        viewport: LayoutSize
    ) throws -> String {
        var declarations = ["position:relative"]
        let intrinsic = node.intrinsicKey.flatMap { catalog.measurement(for: $0) } ?? LayoutSize(width: 0, height: 0)
        if isRoot {
            declarations += ["width:\(px(viewport.width))", "height:\(px(viewport.height))"]
        } else {
            declarations += try dimension("width", node.width, intrinsic: intrinsic.width, isMain: parentAxis == .horizontal)
            declarations += try dimension("height", node.height, intrinsic: intrinsic.height, isMain: parentAxis == .vertical)
            let main = parentAxis == .horizontal ? node.width : node.height
            declarations.append(main == .fill ? "flex:1 1 0" : "flex:0 0 auto")
        }
        declarations += [
            "min-width:\(px(node.constraints.minWidth))",
            "min-height:\(px(node.constraints.minHeight))",
        ]
        if node.constraints.maxWidth < LayoutPolicy.maximumDimension {
            declarations.append("max-width:\(px(node.constraints.maxWidth))")
        }
        if node.constraints.maxHeight < LayoutPolicy.maximumDimension {
            declarations.append("max-height:\(px(node.constraints.maxHeight))")
        }
        if let axis = node.axis {
            declarations += [
                "display:flex",
                "flex-direction:\(axis == .horizontal ? "row" : "column")",
                "align-items:\(alignment(node.alignment))",
                "gap:\(px(node.gap))",
                "padding:\(px(node.padding.top)) \(px(node.padding.trailing)) \(px(node.padding.bottom)) \(px(node.padding.leading))",
                "overflow:\(node.overflow == .clip ? "hidden" : "visible")",
            ]
        }
        let children = try node.childIDs.map { childID -> String in
            guard let child = nodes[childID] else { throw EvidenceError.invalidFixture }
            return try element(
                child, parentAxis: node.axis, isRoot: false,
                nodes: nodes, catalog: catalog, viewport: viewport
            )
        }.joined()
        return "<div class=\"node\" data-layout-id=\"\(node.id.description)\" style=\"\(declarations.joined(separator: ";"))\">\(children)</div>"
    }

    private func dimension(_ name: String, _ length: LayoutLength, intrinsic: Double, isMain: Bool) throws -> [String] {
        switch length {
        case .fixed(let value): ["\(name):\(px(value))"]
        case .intrinsic: ["\(name):\(px(intrinsic))"]
        case .fill: isMain ? [] : ["\(name):100%"]
        case .percentage, .automatic: throw EvidenceError.invalidFixture
        }
    }

    private func alignment(_ value: LayoutAlignment) -> String {
        switch value {
        case .start: "flex-start"
        case .center: "center"
        case .end: "flex-end"
        case .stretch: "stretch"
        case .baseline: "baseline"
        }
    }

    private func px(_ value: Double) -> String { String(format: "%.6fpx", value) }
}

private struct LayoutEvidenceCorrectness: Codable {
    let repeatedDigestsStable: Bool
    let cancellationObserved: Bool
    let staleResultRejected: Bool
    let browserParityWidths: [Double]
    let browserParityMaximumPointError: Double
    let largeFixtureBrowserParityMaximumPointError: [String: Double]
    let webKitExcludedFromProductionCore: Bool
}

private struct LayoutEvidenceReport: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let sourceBaseRevision: String
    let environment: RunwayEnvironment
    let configuration: [String: String]
    let correctness: LayoutEvidenceCorrectness
    let measurements: [RunwayMeasurement]
    let limitations: [String]
}

@main
@MainActor
private struct LayoutFoundationEvidenceMain {
    static func main() async throws {
        guard let outputIndex = CommandLine.arguments.firstIndex(of: "--output"),
              CommandLine.arguments.indices.contains(outputIndex + 1) else { throw EvidenceError.usage }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[outputIndex + 1])
        let engine = DeterministicLayoutEngine()
        var measurements: [RunwayMeasurement] = []
        var stable = true
        var largeErrors: [String: Double] = [:]
        let oracle = BrowserOracle()
        let adapter = LayoutHTMLOracleAdapter()

        for count in [100, 10_000] {
            let request = LayoutEvidenceFixtures.large(count: count)
            let reference = try engine.layout(request)
            let repeated = try engine.layout(request)
            stable = stable && reference.deterministicDigest == repeated.deterministicDigest
            measurements.append(try RunwayBenchmark.measure(
                domain: "layout",
                alternative: "Production deterministic layout core",
                operation: "validate graph and compute immutable frames",
                fixtureCount: count,
                warmups: 5,
                repetitions: 30,
                digest: reference.deterministicDigest,
                notes: [
                    "Optimized Foundation-only production source; fixture construction excluded.",
                    "Timing and memory describe the named host and do not establish a release hardware budget.",
                ]
            ) { _ = try engine.layout(request) })

            let html = try adapter.document(snapshot: request.snapshot, viewport: request.containingBlock)
            measurements.append(try await RunwayBenchmark.measureAsync(
                domain: "layout-oracle",
                alternative: "Ephemeral WebKit HTML/CSS geometry oracle",
                operation: "load exported adapter document and read frames",
                fixtureCount: count,
                warmups: 1,
                repetitions: count == 100 ? 5 : 3,
                notes: ["WebKit is benchmark/evidence-only and never canonical authoring state."]
            ) { _ = try await oracle.frames(html: html, viewport: request.containingBlock) })
            largeErrors[String(count)] = try await parityError(
                request: request, engine: engine, adapter: adapter, oracle: oracle
            )
        }

        let widths = [320.0, 768.0, 1_440.0]
        var responsiveMaximum = 0.0
        for width in widths {
            responsiveMaximum = max(
                responsiveMaximum,
                try await parityError(
                    request: LayoutEvidenceFixtures.parity(width: width),
                    engine: engine,
                    adapter: adapter,
                    oracle: oracle
                )
            )
        }

        var cancellationObserved = false
        do {
            _ = try engine.layout(
                LayoutEvidenceFixtures.large(count: 10_000),
                cancellation: LayoutCancellation(isCancelled: { $0 >= 128 })
            )
        } catch LayoutEngineError.cancelled {
            cancellationObserved = true
        }
        let valid = try engine.layout(LayoutEvidenceFixtures.large(count: 100))
        var staleRejected = false
        do {
            let stale = LayoutRequestIdentity(
                documentID: valid.identity.documentID,
                revision: valid.identity.revision + 1,
                generation: valid.identity.generation + 1,
                viewportWidth: valid.identity.viewportWidth
            )
            try LayoutResultAdoptionGate().validate(valid, expected: stale)
        } catch LayoutEngineError.staleResult {
            staleRejected = true
        }

        guard stable, cancellationObserved, staleRejected,
              responsiveMaximum <= 0.51,
              largeErrors.values.allSatisfy({ $0 <= 0.51 }) else {
            throw EvidenceError.correctnessFailure
        }
        let report = LayoutEvidenceReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            sourceBaseRevision: "f98316456a8b491dec277c5cecd865ab004a8eb9",
            environment: RunwayBenchmark.environment(),
            configuration: [
                "productionWarmups": "5",
                "productionRepetitions": "30",
                "browser100Repetitions": "5",
                "browser10000Repetitions": "3",
                "browserParityTolerancePoints": "0.51",
                "layoutPolicyMaximumNodes": String(LayoutPolicy.maximumNodeCount),
                "layoutPolicyMaximumDepth": String(LayoutPolicy.maximumDepth),
            ],
            correctness: LayoutEvidenceCorrectness(
                repeatedDigestsStable: stable,
                cancellationObserved: cancellationObserved,
                staleResultRejected: staleRejected,
                browserParityWidths: widths,
                browserParityMaximumPointError: responsiveMaximum,
                largeFixtureBrowserParityMaximumPointError: largeErrors,
                webKitExcludedFromProductionCore: true
            ),
            measurements: measurements,
            limitations: [
                "Measurements describe one named machine and toolchain; OD-001 still blocks release budgets.",
                "Resident-memory values are process samples and the process peak is shared across sequential scenarios.",
                "WebKit measurements include process launch, navigation, style/layout, IPC, and geometry extraction.",
                "Browser parity covers geometry for the declared deterministic subset, not typography, pixels, colors, or unsupported CSS.",
                "Intrinsic text sizes are immutable adapter inputs; production text shaping and fallback remain later work.",
                "The engine is not yet wired to canonical layout-property mutations, inspector UI, rendering, preview, or export UI.",
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try encoder.encode(report).write(to: outputURL, options: .atomic)
        print("Deterministic layout foundation evidence passed: \(measurements.count) measurements written.")
    }

    private static func parityError(
        request: LayoutRequest,
        engine: DeterministicLayoutEngine,
        adapter: LayoutHTMLOracleAdapter,
        oracle: BrowserOracle
    ) async throws -> Double {
        let expected = try engine.layout(request).fragmentsByID.mapValues(\.frame)
        let actual = try await oracle.frames(
            html: adapter.document(snapshot: request.snapshot, viewport: request.containingBlock),
            viewport: request.containingBlock
        )
        guard expected.keys == actual.keys else { throw EvidenceError.browserFailure }
        var maximum = 0.0
        for id in expected.keys {
            guard let lhs = expected[id], let rhs = actual[id] else { throw EvidenceError.browserFailure }
            maximum = max(
                maximum,
                abs(lhs.origin.x - rhs.origin.x), abs(lhs.origin.y - rhs.origin.y),
                abs(lhs.size.width - rhs.size.width), abs(lhs.size.height - rhs.size.height)
            )
        }
        return maximum
    }
}

private enum LayoutEvidenceFixtures {
    static func parity(width: Double) -> LayoutRequest {
        let root = id(1), fixed = id(2), intrinsic = id(3), fill = id(4)
        let text = LayoutIntrinsicKey(rawValue: "text.system-17.en-US.headline")
        return request(
            root: root,
            nodes: [
                LayoutNodeSnapshot(
                    id: root, axis: .horizontal, width: .fill, height: .fill,
                    padding: LayoutInsets(top: 10, leading: 20, bottom: 10, trailing: 20),
                    gap: 10, alignment: .center, childIDs: [fixed, intrinsic, fill]
                ),
                LayoutNodeSnapshot(id: fixed, width: .fixed(100), height: .fixed(50)),
                LayoutNodeSnapshot(id: intrinsic, width: .intrinsic, height: .intrinsic, intrinsicKey: text),
                LayoutNodeSnapshot(id: fill, width: .fill, height: .fill),
            ],
            catalog: LayoutIntrinsicCatalog(entries: [text: LayoutSize(width: 80, height: 30)]),
            width: width,
            height: 400
        )
    }

    static func large(count: Int) -> LayoutRequest {
        let root = id(10_000)
        let children = (1..<count).map { id(10_000 + $0) }
        let nodes = [LayoutNodeSnapshot(
            id: root, axis: .vertical, width: .fill, height: .fill,
            padding: LayoutInsets(all: 12), gap: 1, overflow: .clip, childIDs: children
        )] + children.enumerated().map { offset, id in
            LayoutNodeSnapshot(id: id, width: .fill, height: .fixed(Double(8 + offset % 24)))
        }
        return request(root: root, nodes: nodes, width: 1_200, height: 800)
    }

    private static func request(
        root: NodeID,
        nodes: [LayoutNodeSnapshot],
        catalog: LayoutIntrinsicCatalog = LayoutIntrinsicCatalog(),
        width: Double,
        height: Double
    ) -> LayoutRequest {
        LayoutRequest(
            identity: LayoutRequestIdentity(
                documentID: DocumentID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                revision: 7,
                generation: 3,
                viewportWidth: width
            ),
            snapshot: LayoutSnapshot(rootID: root, nodes: nodes, intrinsicCatalog: catalog),
            containingBlock: LayoutSize(width: width, height: height)
        )
    }

    private static func id(_ value: Int) -> NodeID {
        NodeID(uuidString: String(format: "40000000-0000-0000-0000-%012d", value))!
    }
}

private enum EvidenceError: Error {
    case usage
    case invalidFixture
    case browserFailure
    case correctnessFailure
}
