import AppKit
import CryptoKit
import Foundation

enum FileAccessIntent: String, Codable, Equatable, Sendable {
    case open, save, revert, autosave, recovery, inspect

    var isWriting: Bool {
        switch self {
        case .save, .autosave: true
        case .open, .revert, .recovery, .inspect: false
        }
    }

    var isApplicationOwned: Bool { self == .autosave || self == .recovery }
}

enum FileAccessPolicy: String, Equatable, Sendable {
    case developmentUnrestricted
    case sandboxedUserSelectedReadWrite

    static var current: FileAccessPolicy {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
            ? .developmentUnrestricted
            : .sandboxedUserSelectedReadWrite
    }
}

enum FileAccessFailure: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case missingBookmark
    case corruptBookmarkStore
    case staleBookmarkRepairFailed
    case coordinationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "SiteForge could not obtain access to the selected project. Choose it again or review Files and Folders access in System Settings."
        case .missingBookmark: "Persistent access is unavailable. Locate the project again to restore access."
        case .corruptBookmarkStore: "Saved file access information is damaged. Locate the project again; the project itself is unchanged."
        case .staleBookmarkRepairFailed: "File access moved or expired and could not be refreshed. Locate the project again."
        case .coordinationFailed: "macOS could not coordinate access to this project. Close other editors or choose another copy."
        }
    }
}

struct SecurityScopedBookmarkResolution: Equatable, Sendable {
    let url: URL
    let isStale: Bool
}

protocol SecurityScopedBookmarkRuntime: Sendable {
    func makeBookmark(for url: URL) async throws -> Data
    func resolveBookmark(_ data: Data) async throws -> SecurityScopedBookmarkResolution
    func startAccessing(_ url: URL) async -> Bool
    func stopAccessing(_ url: URL) async
}

struct FoundationSecurityScopedBookmarkRuntime: SecurityScopedBookmarkRuntime {
    func makeBookmark(for url: URL) async throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.fileResourceIdentifierKey],
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) async throws -> SecurityScopedBookmarkResolution {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return SecurityScopedBookmarkResolution(url: url, isStale: stale)
    }

    func startAccessing(_ url: URL) async -> Bool { url.startAccessingSecurityScopedResource() }
    func stopAccessing(_ url: URL) async { url.stopAccessingSecurityScopedResource() }
}

struct PersistedFileBookmark: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let bookmark: Data
    let relativeMember: String?

    init(bookmark: Data, relativeMember: String? = nil) {
        schemaVersion = Self.currentSchemaVersion
        self.bookmark = bookmark
        self.relativeMember = relativeMember
    }
}

protocol FileBookmarkPersisting: Sendable {
    func bookmark(for key: String) async throws -> PersistedFileBookmark?
    func setBookmark(_ bookmark: PersistedFileBookmark, for key: String) async throws
}

actor FileBookmarkStore: FileBookmarkPersisting {
    private struct Envelope: Codable {
        let schemaVersion: Int
        var records: [String: PersistedFileBookmark]
    }

    static let currentSchemaVersion = 1
    private let url: URL

    init(url: URL = FileBookmarkStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SiteForge/FileAccess/bookmarks.json")
    }

    func bookmark(for key: String) throws -> PersistedFileBookmark? {
        try load().records[key]
    }

    func setBookmark(_ bookmark: PersistedFileBookmark, for key: String) throws {
        guard bookmark.schemaVersion == PersistedFileBookmark.currentSchemaVersion else {
            throw FileAccessFailure.corruptBookmarkStore
        }
        var envelope = try load()
        envelope.records[key] = bookmark
        try persist(envelope)
    }

    private func load() throws -> Envelope {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Envelope(schemaVersion: Self.currentSchemaVersion, records: [:])
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == Self.currentSchemaVersion,
                  envelope.records.values.allSatisfy({ $0.schemaVersion == PersistedFileBookmark.currentSchemaVersion }) else {
                throw FileAccessFailure.corruptBookmarkStore
            }
            return envelope
        } catch let error as FileAccessFailure {
            throw error
        } catch {
            throw FileAccessFailure.corruptBookmarkStore
        }
    }

    private func persist(_ envelope: Envelope) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

protocol ProjectFileCoordinating: Sendable {
    func coordinate<T: Sendable>(
        at url: URL,
        intent: FileAccessIntent,
        operation: @escaping @Sendable (URL) async throws -> T
    ) async throws -> T
}

private final class CoordinationResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, Error>?

    func set(_ value: Result<T, Error>) { lock.withLock { self.value = value } }
    func get() -> Result<T, Error>? { lock.withLock { value } }
}

struct FoundationProjectFileCoordinator: ProjectFileCoordinating {
    func coordinate<T: Sendable>(
        at url: URL,
        intent: FileAccessIntent,
        operation: @escaping @Sendable (URL) async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                let result = CoordinationResultBox<T>()
                let accessor: (URL) -> Void = { coordinatedURL in
                    let semaphore = DispatchSemaphore(value: 0)
                    Task {
                        do { result.set(.success(try await operation(coordinatedURL))) }
                        catch { result.set(.failure(error)) }
                        semaphore.signal()
                    }
                    semaphore.wait()
                }
                if intent.isWriting {
                    coordinator.coordinate(
                        writingItemAt: url,
                        options: [],
                        error: &coordinationError,
                        byAccessor: accessor
                    )
                } else {
                    coordinator.coordinate(
                        readingItemAt: url,
                        options: .withoutChanges,
                        error: &coordinationError,
                        byAccessor: accessor
                    )
                }
                if let coordinationError {
                    continuation.resume(throwing: coordinationError)
                } else if let result = result.get() {
                    continuation.resume(with: result)
                } else {
                    continuation.resume(throwing: FileAccessFailure.coordinationFailed)
                }
            }
        }
    }
}

enum FileAccessDiagnosticResult: String, Equatable, Sendable { case success, failure }

struct FileAccessDiagnostic: Equatable, Sendable {
    let requirementIDs: [String]
    let intent: FileAccessIntent
    let sanitizedResourceID: String
    let usedPersistedBookmark: Bool
    let repairedStaleBookmark: Bool
    let durationNanoseconds: UInt64
    let result: FileAccessDiagnosticResult
    let failureCategory: String?
}

actor FileAccessDiagnostics {
    private(set) var records: [FileAccessDiagnostic] = []
    func append(_ record: FileAccessDiagnostic) { records.append(record) }
}

actor FileAccessService {
    static let requirementIDs: Set<String> = [
        "SF-1504-001", "SF-1504-002", "SF-1504-003", "SF-1504-004",
        "SF-1504-005", "SF-1504-006", "SF-1504-007", "SF-1504-008", "SF-1603-004",
    ]

    private let policy: FileAccessPolicy
    private let runtime: any SecurityScopedBookmarkRuntime
    private let bookmarks: any FileBookmarkPersisting
    private let coordinator: any ProjectFileCoordinating
    private let diagnostics: FileAccessDiagnostics
    private var userSelections: Set<String> = []

    init(
        policy: FileAccessPolicy = .current,
        runtime: any SecurityScopedBookmarkRuntime = FoundationSecurityScopedBookmarkRuntime(),
        bookmarks: any FileBookmarkPersisting = FileBookmarkStore(),
        coordinator: any ProjectFileCoordinating = FoundationProjectFileCoordinator(),
        diagnostics: FileAccessDiagnostics = FileAccessDiagnostics()
    ) {
        self.policy = policy
        self.runtime = runtime
        self.bookmarks = bookmarks
        self.coordinator = coordinator
        self.diagnostics = diagnostics
    }

    func authorizeUserSelection(_ url: URL) async throws {
        let key = Self.key(for: url)
        if FileManager.default.fileExists(atPath: url.path) {
            try await retainBookmark(for: url, aliases: [key])
        } else {
            let member = url.lastPathComponent
            guard !member.isEmpty, member != ".", member != "..", !member.contains("/") else {
                throw FileAccessFailure.permissionDenied
            }
            let parent = url.deletingLastPathComponent()
            let data = try await runtime.makeBookmark(for: parent)
            try await bookmarks.setBookmark(
                PersistedFileBookmark(bookmark: data, relativeMember: member),
                for: key
            )
        }
        userSelections.insert(key)
    }

    func recordRelocation(from oldURL: URL, to newURL: URL) async throws {
        let oldKey = Self.key(for: oldURL)
        guard try await bookmarks.bookmark(for: oldKey) != nil else {
            if policy == .sandboxedUserSelectedReadWrite { throw FileAccessFailure.missingBookmark }
            return
        }
        try await retainBookmark(for: newURL, aliases: [Self.key(for: newURL)])
    }

    func withAccess<T: Sendable>(
        to requestedURL: URL,
        intent: FileAccessIntent,
        operation: @escaping @Sendable (URL) async throws -> T
    ) async throws -> T {
        let start = ContinuousClock.now
        let key = Self.key(for: requestedURL)
        var usedBookmark = false
        var repaired = false
        var scopeCandidateURL: URL?
        var scopedURL: URL?
        do {
            let resolvedURL: URL
            if intent.isApplicationOwned {
                resolvedURL = requestedURL
            } else if let record = try await bookmarks.bookmark(for: key) {
                guard record.schemaVersion == PersistedFileBookmark.currentSchemaVersion else {
                    throw FileAccessFailure.corruptBookmarkStore
                }
                let resolution = try await runtime.resolveBookmark(record.bookmark)
                usedBookmark = true
                if let member = record.relativeMember {
                    guard !member.isEmpty, member != ".", member != "..", !member.contains("/") else {
                        throw FileAccessFailure.corruptBookmarkStore
                    }
                    resolvedURL = resolution.url.appendingPathComponent(member)
                    scopeCandidateURL = resolution.url
                } else {
                    resolvedURL = resolution.url
                    scopeCandidateURL = resolution.url
                }
                if resolution.isStale {
                    do {
                        let data = try await runtime.makeBookmark(for: resolution.url)
                        let refreshed = PersistedFileBookmark(bookmark: data, relativeMember: record.relativeMember)
                        try await bookmarks.setBookmark(refreshed, for: key)
                        if record.relativeMember == nil {
                            try await bookmarks.setBookmark(refreshed, for: Self.key(for: resolution.url))
                        }
                        repaired = true
                    } catch {
                        throw FileAccessFailure.staleBookmarkRepairFailed
                    }
                }
            } else if userSelections.contains(key) || policy == .developmentUnrestricted {
                resolvedURL = requestedURL
            } else {
                throw FileAccessFailure.missingBookmark
            }

            if !intent.isApplicationOwned, usedBookmark || policy == .sandboxedUserSelectedReadWrite {
                let accessURL = scopeCandidateURL ?? resolvedURL
                guard await runtime.startAccessing(accessURL) else {
                    throw FileAccessFailure.permissionDenied
                }
                scopedURL = accessURL
            }
            let value = try await coordinator.coordinate(at: resolvedURL, intent: intent, operation: operation)
            if let scopedURL {
                await runtime.stopAccessing(scopedURL)
            }
            scopedURL = nil
            await record(
                key: key, intent: intent, usedBookmark: usedBookmark, repaired: repaired,
                start: start, result: .success, failure: nil
            )
            return value
        } catch {
            if let scopedURL {
                await runtime.stopAccessing(scopedURL)
            }
            await record(
                key: key, intent: intent, usedBookmark: usedBookmark, repaired: repaired,
                start: start, result: .failure, failure: error
            )
            throw error
        }
    }

    func diagnosticRecords() async -> [FileAccessDiagnostic] { await diagnostics.records }

    private func retainBookmark(for url: URL, aliases: [String]) async throws {
        let data = try await runtime.makeBookmark(for: url)
        let record = PersistedFileBookmark(bookmark: data)
        for alias in Set(aliases) { try await bookmarks.setBookmark(record, for: alias) }
    }

    private func record(
        key: String,
        intent: FileAccessIntent,
        usedBookmark: Bool,
        repaired: Bool,
        start: ContinuousClock.Instant,
        result: FileAccessDiagnosticResult,
        failure: Error?
    ) async {
        let duration = start.duration(to: .now).components
        let nanos = UInt64(max(0, duration.seconds)) * 1_000_000_000
            + UInt64(max(0, duration.attoseconds / 1_000_000_000))
        await diagnostics.append(FileAccessDiagnostic(
            requirementIDs: Self.requirementIDs.sorted(),
            intent: intent,
            sanitizedResourceID: "resource-\(key.prefix(12))",
            usedPersistedBookmark: usedBookmark,
            repairedStaleBookmark: repaired,
            durationNanoseconds: nanos,
            result: result,
            failureCategory: failure.map { String(describing: type(of: $0)) }
        ))
    }

    nonisolated static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

enum ProjectFilePresentationEvent: Equatable, Sendable {
    case changed
    case moved(URL)
    case deleted
}

final class ProjectFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var itemURL: URL?
    private let handler: @Sendable (ProjectFilePresentationEvent) -> Void
    let presentedItemOperationQueue: OperationQueue

    init(url: URL, handler: @escaping @Sendable (ProjectFilePresentationEvent) -> Void) {
        itemURL = url
        self.handler = handler
        let queue = OperationQueue()
        queue.name = "app.siteforge.file-presenter"
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue
        super.init()
    }

    var presentedItemURL: URL? { lock.withLock { itemURL } }

    func presentedItemDidChange() { handler(.changed) }

    func presentedItemDidMove(to newURL: URL) {
        lock.withLock { itemURL = newURL }
        handler(.moved(newURL))
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        handler(.deleted)
        completionHandler(nil)
    }
}
