import AppKit
import Combine
import Foundation
import Network
import SwiftUI

enum WebsitePreviewError: Error, Equatable, Sendable {
    case invalidOutput, unavailable, cancelled
}

/// SF-1201/1206: HTTP reads only immutable compiler output, never a filesystem
/// path supplied by a client. The same plan is written by local export.
struct WebsitePreviewHTTPContent: Sendable {
    struct Response: Sendable {
        let status: Int
        let type: String
        let body: Data
        let headOnly: Bool

        var bytes: Data {
            let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 431: "Request Header Fields Too Large"][status] ?? "Error"
            let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n"
            return Data(header.utf8) + (headOnly ? Data() : body)
        }
    }

    let files: [String: Data]

    init(plan: LocalStaticBuildPlan) throws {
        var result: [String: Data] = [:]
        for (path, bytes) in plan.files.map({ ($0.path, Data($0.contents.utf8)) }) + plan.binaryFiles.map({ ($0.path, $0.contents) }) {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !path.contains("\\"), !path.contains("%"), !path.contains("\0"),
                  result.updateValue(bytes, forKey: path) == nil else { throw WebsitePreviewError.invalidOutput }
        }
        guard result["index.html"] != nil else { throw WebsitePreviewError.invalidOutput }
        files = result
    }

    func response(to request: Data, port: UInt16) -> Response {
        func reject(_ status: Int) -> Response {
            .init(status: status, type: "text/plain; charset=utf-8", body: Data("Website preview request unavailable.\n".utf8), headOnly: false)
        }
        guard request.count <= 16_384, let raw = String(data: request, encoding: .utf8),
              raw.contains("\r\n\r\n") else { return reject(request.count > 16_384 ? 431 : 400) }
        let lines = raw.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2] == "HTTP/1.1" || first[2] == "HTTP/1.0" else { return reject(400) }
        guard first[0] == "GET" || first[0] == "HEAD" else { return reject(405) }
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard hosts.count == 1,
              ["127.0.0.1:\(port)", "localhost:\(port)"].contains(String(hosts[0].dropFirst(5)).trimmingCharacters(in: .whitespaces).lowercased()) else { return reject(400) }
        let target = String(first[1]).split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard target.hasPrefix("/"), !target.hasPrefix("//"),
              let decoded = String(target).removingPercentEncoding,
              !decoded.contains("\\"), !decoded.contains("%"), !decoded.contains("\0"), !decoded.contains("#"),
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return reject(400) }
        let components = decoded.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains(".") else { return reject(400) }
        var path = String(decoded.dropFirst())
        if path.isEmpty || path.hasSuffix("/") { path += "index.html" }
        if files[path] == nil, !path.contains("."), files[path + ".html"] != nil { path += ".html" }
        let found = files[path]
        let body = found ?? files["404.html"] ?? Data("Page not found.\n".utf8)
        let suffix = found == nil && files["404.html"] != nil ? "html" : (path as NSString).pathExtension.lowercased()
        let types = ["html": "text/html; charset=utf-8", "css": "text/css; charset=utf-8", "js": "text/javascript; charset=utf-8", "json": "application/json", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "avif": "image/avif", "ico": "image/x-icon", "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf"]
        return .init(status: found == nil ? 404 : 200, type: types[suffix] ?? "application/octet-stream", body: body, headOnly: first[0] == "HEAD")
    }
}

/// All mutable Network state is confined to `queue`, including callbacks,
/// startup completion, connection budgets and teardown. No main-thread wait.
final class LoopbackWebsiteServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.siteforge.website-preview", qos: .userInitiated)
    private var listener: NWListener?
    private var startup: CheckedContinuation<URL, Error>?
    private var content: WebsitePreviewHTTPContent?
    private var port: UInt16 = 0
    private var stopped = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func start(plan: LocalStaticBuildPlan) async throws -> URL {
        try Task.checkCancellation()
        let content = try WebsitePreviewHTTPContent(plan: plan)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !stopped, listener == nil else { continuation.resume(throwing: WebsitePreviewError.cancelled); return }
                    do {
                        let parameters = NWParameters.tcp
                        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                        let value = try NWListener(using: parameters)
                        self.content = content
                        startup = continuation
                        listener = value
                        value.stateUpdateHandler = { [weak self] state in
                            guard let self else { return }
                            switch state {
                            case .ready:
                                guard let number = value.port?.rawValue else { self.finishStart(.failure(WebsitePreviewError.unavailable)); self.stopOnQueue(); return }
                                self.port = number
                                self.finishStart(.success(URL(string: "http://127.0.0.1:\(number)/")!))
                            case .failed: self.finishStart(.failure(WebsitePreviewError.unavailable)); self.stopOnQueue()
                            case .cancelled: self.finishStart(.failure(WebsitePreviewError.cancelled))
                            default: break
                            }
                        }
                        value.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                        value.start(queue: queue)
                    } catch { continuation.resume(throwing: WebsitePreviewError.unavailable) }
                }
            }
        } onCancel: { [self] in queue.async { self.stopOnQueue() } }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { self.stopOnQueue(); continuation.resume() }
        }
    }

    private func finishStart(_ result: Result<URL, Error>) {
        let continuation = startup; startup = nil
        continuation?.resume(with: result)
    }

    private func stopOnQueue() {
        stopped = true
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        content = nil
        finishStart(.failure(WebsitePreviewError.cancelled))
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in
            guard let self, let connection, self.connections[id] === connection else { return }
            connection.cancel(); self.connections.removeValue(forKey: id)
        }
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_385 - min(accumulated.count, 16_384)) { [weak self] bytes, _, complete, error in
            guard let self else { connection.cancel(); return }
            let request = accumulated + (bytes ?? Data())
            if request.count > 16_384 || request.range(of: Data("\r\n\r\n".utf8)) != nil || complete || error != nil {
                guard let content = self.content else { connection.cancel(); return }
                let response = content.response(to: request, port: self.port)
                connection.send(content: response.bytes, completion: .contentProcessed { [weak self] _ in
                    connection.cancel(); self?.connections.removeValue(forKey: ObjectIdentifier(connection))
                })
            } else { self.receive(connection, accumulated: request) }
        }
    }
}

actor BrowserWebsiteBuilder {
    func prepare(document: CanonicalDocument, package: ProjectPackage) throws -> (StaticBuildCompilation, URL?) {
        try Task.checkCancellation()
        return try writePrepared(StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .development), package: package), revision: document.revision)
    }

    func prepare(document: CanonicalDocument, descriptors: [ResourceID: ProjectResourceDescriptor], data: [ResourceID: Data]) throws -> (StaticBuildCompilation, URL?) {
        try Task.checkCancellation()
        let result = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development), resourceDescriptors: descriptors, resourceData: data)
        return try writePrepared(result, revision: document.revision)
    }

    private func writePrepared(_ result: StaticBuildCompilation, revision: UInt64) throws -> (StaticBuildCompilation, URL?) {
        guard let plan = result.plan, result.canWrite else { return (result, nil) }
        try Task.checkCancellation()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("siteforge-website-" + UUID().uuidString, isDirectory: true)
        do {
            // The writer's staging directory must itself be beneath a private
            // parent, not exposed in the shared temporary directory until a
            // post-write chmod. HTTP still serves only the immutable plan.
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try LocalStaticBuildWriter.write(plan, to: root.appendingPathComponent("website", isDirectory: true),
                                            expectedRevision: revision)
            try Task.checkCancellation()
        } catch {
            removeOwnedOutput(root)
            throw error
        }
        return (result, root)
    }

    func removeOwnedOutput(_ root: URL) {
        guard root.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL,
              root.lastPathComponent.hasPrefix("siteforge-website-") else { return }
        try? FileManager.default.removeItem(at: root)
    }

    func export(_ plan: LocalStaticBuildPlan, to destination: URL, replacing: Bool) throws {
        try Task.checkCancellation()
        try LocalStaticBuildWriter.write(plan, to: destination, expectedRevision: plan.revision, replacingExisting: replacing)
    }
}

/// Ephemeral panel intent: never retarget a destination chosen for an older build.
struct WebsitePreviewExportRequest: Sendable {
    fileprivate let buildID: UUID
    let documentID: DocumentID
    let plan: LocalStaticBuildPlan
}

@MainActor final class BrowserPreviewController: ObservableObject {
    @Published private(set) var status = "Preview your website in Safari."
    @Published private(set) var isBuilding = false
    @Published private(set) var isExporting = false
    @Published private(set) var isOpeningBrowser = false
    @Published private(set) var exportFailure: LocalStaticBuildWriteError?
    @Published private(set) var url: URL?
    @Published private(set) var revision: UInt64?
    @Published private(set) var documentID: DocumentID?
    @Published private(set) var findings: [StaticBuildFinding] = []
    private var task: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var requestID = UUID()
    private var exportRequestID = UUID()
    private var browserOpenRequestID = UUID()
    private var pendingBuildIdentity: (documentID: DocumentID, revision: UInt64)?
    enum BrowserOpenResult { case opened, unavailable, failed }
    private let browserOpener: @MainActor (URL) async -> BrowserOpenResult
    private var server: LoopbackWebsiteServer?
    private var outputRoot: URL?
    private(set) var plan: LocalStaticBuildPlan?
    private let builder = BrowserWebsiteBuilder()

    init(browserOpener: @escaping @MainActor (URL) async -> BrowserOpenResult = BrowserPreviewController.openInSafari) {
        self.browserOpener = browserOpener
    }

    private static func openInSafari(_ url: URL) async -> BrowserOpenResult {
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return .unavailable }
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: .init()) { _, error in
                continuation.resume(returning: error == nil ? .opened : .failed)
            }
        }
    }

    deinit {
        task?.cancel()
        exportTask?.cancel()
        let oldServer = server, oldRoot = outputRoot, worker = builder
        Task { await oldServer?.stop(); if let oldRoot { await worker.removeOwnedOutput(oldRoot) } }
    }

    @discardableResult
    func build(document: CanonicalDocument, pageID: PageID?, package: ProjectPackage, isCurrent: @escaping @MainActor (DocumentID, UInt64) -> Bool) -> Task<Void, Never> {
        task?.cancel()
        exportTask?.cancel(); exportTask = nil
        let request = UUID(); requestID = request
        pendingBuildIdentity = (document.id, document.revision)
        exportRequestID = UUID(); isExporting = false
        browserOpenRequestID = UUID(); isOpeningBrowser = false
        isBuilding = true; status = "Building website…"; findings = []
        let work = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == request { pendingBuildIdentity = nil; isBuilding = false } }
            var preparedRoot: URL?
            var newServer: LoopbackWebsiteServer?
            do {
                let (result, root) = try await builder.prepare(document: document, package: package)
                preparedRoot = root
                guard !Task.isCancelled, requestID == request, isCurrent(document.id, document.revision) else { throw WebsitePreviewError.cancelled }
                findings = result.findings
                guard let nextPlan = result.plan, result.canWrite else {
                    if let root { await builder.removeOwnedOutput(root); preparedRoot = nil }
                    guard requestID == request else { return }
                    status = "Build needs attention. Fix the listed issues and Retry. Last successful preview is unchanged."
                    isBuilding = false; return
                }
                let nextServer = LoopbackWebsiteServer(); newServer = nextServer
                let base = try await nextServer.start(plan: nextPlan)
                guard !Task.isCancelled, requestID == request, isCurrent(document.id, document.revision) else { throw WebsitePreviewError.cancelled }
                let page = document.websitePages.first { $0.id == pageID } ?? document.websitePages.first { $0.role == .home }
                let path = try page.map { try MultiPageStaticBuildPlanner.outputPath(for: $0) } ?? "index.html"
                let oldServer = server, oldRoot = outputRoot
                server = nextServer; outputRoot = root; plan = nextPlan
                documentID = document.id; revision = document.revision
                url = base.appendingPathComponent(path)
                isBuilding = false; status = "Website revision \(document.revision) is ready."
                await oldServer?.stop()
                if let oldRoot { await builder.removeOwnedOutput(oldRoot) }
                guard requestID == request else { return }
                openAgain()
            } catch {
                await newServer?.stop()
                if let preparedRoot { await builder.removeOwnedOutput(preparedRoot) }
                guard requestID == request else { return }
                isBuilding = false
                status = Task.isCancelled || error is CancellationError || error as? WebsitePreviewError == .cancelled
                    ? "Build cancelled or superseded. Last successful preview is unchanged."
                    : "Preview could not start. Retry, or export the website locally."
            }
        }
        task = work
        return work
    }

    func noteRevision(documentID: DocumentID, revision: UInt64) {
        if let pending = pendingBuildIdentity {
            if pending.documentID != documentID { stop(); return }
            if pending.revision != revision {
                cancel()
                status = "Edits changed while building. Refresh to include them; the last successful preview is unchanged."
                return
            }
        }
        if let active = self.documentID, active != documentID { stop(); return }
        if let built = self.revision, built != revision, !isBuilding {
            browserOpenRequestID = UUID(); isOpeningBrowser = false
            status = "Safari is showing revision \(built). Refresh to build your latest edits."
        }
    }

    func cancel() {
        task?.cancel(); requestID = UUID(); pendingBuildIdentity = nil
        exportTask?.cancel(); exportTask = nil
        isBuilding = false
        exportRequestID = UUID(); isExporting = false
        browserOpenRequestID = UUID(); isOpeningBrowser = false
        status = "Build cancelled. Last successful preview is unchanged."
    }

    func stop() {
        task?.cancel(); requestID = UUID()
        exportTask?.cancel(); exportTask = nil
        pendingBuildIdentity = nil; exportRequestID = UUID(); isExporting = false
        browserOpenRequestID = UUID(); isOpeningBrowser = false
        let oldServer = server, oldRoot = outputRoot
        server = nil; outputRoot = nil; plan = nil; url = nil; revision = nil; documentID = nil
        isBuilding = false; status = "Website preview stopped."
        Task { await oldServer?.stop(); if let oldRoot { await builder.removeOwnedOutput(oldRoot) } }
    }

    func openAgain() {
        guard let url, !isOpeningBrowser, !isExporting else { return }
        let request = requestID
        let openRequest = UUID(); browserOpenRequestID = openRequest
        isOpeningBrowser = true; status = "Opening Safari…"
        Task { [weak self] in
            guard let self else { return }
            let result = await browserOpener(url)
            guard requestID == request, browserOpenRequestID == openRequest, self.url == url else { return }
            isOpeningBrowser = false
            switch result {
            case .opened: status = "Website opened in Safari."
            case .unavailable: status = "Safari is unavailable. Install Safari or export the website for another browser."
            case .failed: status = "Safari could not open. Retry Open Again or export the website."
            }
        }
    }

    func makeExportRequest() -> WebsitePreviewExportRequest? {
        guard !isBuilding, !isExporting, let plan, let documentID else { return nil }
        return .init(buildID: requestID, documentID: documentID, plan: plan)
    }

    func cancelExport() {
        guard isExporting else { return }
        exportTask?.cancel()
        status = "Cancelling export. Any already committed output is retained."
    }

    @discardableResult
    func export(to destination: URL, request captured: WebsitePreviewExportRequest? = nil,
                replacingExisting: Bool = false) -> Task<Void, Never>? {
        guard let intent = captured ?? makeExportRequest(), !isBuilding, !isExporting,
              intent.buildID == requestID, intent.documentID == documentID,
              intent.plan == plan else { return nil }
        let plan = intent.plan
        let request = requestID
        let exportRequest = UUID(); exportRequestID = exportRequest
        browserOpenRequestID = UUID(); isOpeningBrowser = false
        isExporting = true; exportFailure = nil; status = "Exporting website revision \(plan.revision)…"
        let work = Task {
            defer { if exportRequestID == exportRequest { isExporting = false; exportTask = nil } }
            do {
                try Task.checkCancellation()
                try await builder.export(plan, to: destination, replacing: replacingExisting)
                guard requestID == request, exportRequestID == exportRequest else { return }
                status = "Exported the same website revision \(plan.revision) used by Safari."
            } catch {
                guard requestID == request, exportRequestID == exportRequest else { return }
                let category = error as? LocalStaticBuildWriteError ?? (error is CancellationError ? .cancelled : .writeFailed)
                exportFailure = category
                switch category {
                case .permissionDenied: status = "Export needs access. Choose a writable destination and retry."
                case .insufficientSpace: status = "Export needs more disk space. Free space or choose another destination."
                case .unsafeDestination: status = "Export destination is unsafe. Choose another folder."
                case .destinationExists: status = "Export destination already exists. Confirm replacement or choose another folder."
                case .stale, .cancelled: status = "Export was cancelled or superseded. Retry the current website revision."
                case .writeFailed: status = "Export did not finish. Choose a writable destination and retry."
                }
            }
        }
        exportTask = work
        return work
    }
}

struct BrowserPreviewPanel: View {
    @ObservedObject var controller: BrowserPreviewController
    let refresh: () -> Void
    let dismiss: () -> Void

    private var actionableFindings: [StaticBuildFinding] {
        controller.findings.filter { $0.severity != .information }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Website Preview", systemImage: "safari").font(.title2.weight(.semibold))
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("preview.website.done")
            }
            Text("Build your website locally and open it in Safari. Export uses the same HTML, CSS and assets. Nothing is published.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if controller.isBuilding || controller.isExporting || controller.isOpeningBrowser { ProgressView().controlSize(.small) }
                Text(controller.status).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityValue(controller.status)
                    .accessibilityIdentifier("preview.website.status")
            }
            if let url = controller.url {
                Text(url.absoluteString).font(.callout.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("preview.website.url")
            }
            if !actionableFindings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(actionableFindings) { finding in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(finding.explanation)
                                Text(finding.repair).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
            }
            HStack {
                Button("Refresh", action: refresh).disabled(controller.isBuilding)
                    .accessibilityIdentifier("preview.website.refresh")
                Button("Open Again", action: controller.openAgain).disabled(controller.url == nil || controller.isOpeningBrowser || controller.isExporting || controller.isBuilding)
                    .accessibilityIdentifier("preview.website.open")
                Button("Cancel Build", action: controller.cancel).disabled(!controller.isBuilding)
                if controller.isExporting {
                    Button("Cancel Export", action: controller.cancelExport)
                        .accessibilityIdentifier("preview.website.export.cancel")
                }
                Button("Stop", action: controller.stop).disabled(controller.url == nil && !controller.isBuilding)
                Spacer()
                Button("Export…", action: export).disabled(controller.plan == nil || controller.isExporting || controller.isBuilding)
                    .accessibilityIdentifier("preview.website.export")
            }
        }
        .padding(24)
        .frame(minWidth: 660, idealWidth: 740)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview.website")
    }

    private func export() {
        guard let request = controller.makeExportRequest() else { return }
        let panel = NSSavePanel()
        panel.title = "Export Website"
        panel.nameFieldStringValue = "Website"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            controller.export(to: url, request: request,
                              replacingExisting: FileManager.default.fileExists(atPath: url.path))
        }
    }
}
