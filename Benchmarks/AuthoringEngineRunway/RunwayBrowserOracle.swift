import Foundation
@preconcurrency import WebKit

private struct RunwayBrowserFrame: Decodable {
    let id: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

@MainActor
final class RunwayBrowserOracle: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var webView: WKWebView?

    func frames(html: String, viewport: RunwaySize) async throws -> [RunwayStableID: RunwayRect] {
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
                continuation.resume(throwing: RunwayError.oracleFailure)
                return
            }
        }
        let script = """
        JSON.stringify(Array.from(document.querySelectorAll('[data-runway-id]')).map(element => {
          const frame = element.getBoundingClientRect();
          return {id: element.dataset.runwayId, x: frame.x, y: frame.y, width: frame.width, height: frame.height};
        }))
        """
        guard let json = try await view.evaluateJavaScript(script) as? String,
              let data = json.data(using: .utf8) else { throw RunwayError.oracleFailure }
        let decoded = try JSONDecoder().decode([RunwayBrowserFrame].self, from: data)
        view.stopLoading()
        webView = nil
        return Dictionary(uniqueKeysWithValues: decoded.map {
            (
                RunwayStableID($0.id),
                RunwayRect(
                    origin: RunwayPoint(x: $0.x, y: $0.y),
                    size: RunwaySize(width: $0.width, height: $0.height)
                )
            )
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

@MainActor
struct RunwayBrowserBenchmarks {
    let oracle = RunwayBrowserOracle()
    let exporter = RunwayHTMLExport()
    let engine = RunwayLayoutEngine()

    func parity(root: RunwayLayoutNode, widths: [Double]) async throws -> Double {
        var maximumError = 0.0
        for width in widths {
            let viewport = RunwaySize(width: width, height: 360)
            let expected = try engine.layout(root: root, viewport: viewport, revision: 1).frames
            let actual = try await oracle.frames(html: exporter.document(root: root, viewport: viewport), viewport: viewport)
            maximumError = max(maximumError, try frameError(expected: expected, actual: actual))
        }
        return maximumError
    }

    func parity(root: RunwayLayoutNode, viewport: RunwaySize) async throws -> Double {
        let expected = try engine.layout(root: root, viewport: viewport, revision: 1).frames
        let actual = try await oracle.frames(
            html: exporter.document(root: root, viewport: viewport), viewport: viewport
        )
        return try frameError(expected: expected, actual: actual)
    }

    func measurement(
        root: RunwayLayoutNode,
        nodeCount: Int,
        viewport: RunwaySize,
        warmups: Int,
        repetitions: Int
    ) async throws -> RunwayMeasurement {
        let html = try exporter.document(root: root, viewport: viewport)
        return try await RunwayBenchmark.measureAsync(
            domain: "layout", alternative: "WebKit HTML/CSS oracle", operation: "load DOM and read all frames",
            fixtureCount: nodeCount, warmups: warmups, repetitions: repetitions,
            notes: [
                "Uses an ephemeral WKWebView as an oracle/export adapter only.",
                "Includes web-process navigation, style/layout, IPC, and geometry extraction; it is not canonical authoring state.",
            ]
        ) {
            _ = try await oracle.frames(html: html, viewport: viewport)
        }
    }

    private func frameError(
        expected: [RunwayStableID: RunwayRect],
        actual: [RunwayStableID: RunwayRect]
    ) throws -> Double {
        guard expected.keys == actual.keys else { throw RunwayError.oracleFailure }
        var maximumError = 0.0
        for id in expected.keys {
            guard let lhs = expected[id], let rhs = actual[id] else { throw RunwayError.oracleFailure }
            maximumError = max(
                maximumError,
                abs(lhs.origin.x - rhs.origin.x), abs(lhs.origin.y - rhs.origin.y),
                abs(lhs.size.width - rhs.size.width), abs(lhs.size.height - rhs.size.height)
            )
        }
        return maximumError
    }
}
