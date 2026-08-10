import Foundation

struct RepositoryTestFixture: Sendable {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".siteforge-test-fixtures", isDirectory: true)

    let url: URL

    static func reserve(_ scope: String) throws -> RepositoryTestFixture {
        let safeScope = scope.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !safeScope.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = root.appendingPathComponent("\(safeScope)-\(UUID().uuidString)", isDirectory: true)
        return RepositoryTestFixture(url: directory)
    }

    static func create(_ scope: String) throws -> RepositoryTestFixture {
        let fixture = try reserve(scope)
        let directory = fixture.url
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return fixture
    }

    func cleanup() throws {
        let rootPath = Self.root.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(rootPath) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try FileManager.default.removeItem(at: url)
    }
}

/// Descriptor-bound filesystem tests run inside the sandboxed application test
/// host. Their artifacts must live in that host's own temporary container,
/// rather than under the developer checkout, so no security-scoped user folder
/// access is implicitly assumed by the low-level filesystem layer.
struct ApplicationOwnedTestFixture: Sendable {
    static let root: URL = canonicalTemporaryDirectory()
        .appendingPathComponent("app.siteforge-test-fixtures", isDirectory: true)

    let url: URL

    static func create(_ scope: String) throws -> ApplicationOwnedTestFixture {
        let safeScope = scope.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !safeScope.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let directory = root.appendingPathComponent("\(safeScope)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return ApplicationOwnedTestFixture(url: directory)
    }

    func cleanup() throws {
        let rootPath = Self.root.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(rootPath) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try FileManager.default.removeItem(at: url)
    }

    private static func canonicalTemporaryDirectory() -> URL {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        // macOS exposes /var as a system symlink to /private/var. The
        // descriptor-bound tests intentionally reject arbitrary symlink hops,
        // so use the canonical spelling of that OS-owned alias instead.
        let path = temporary.path
        if path == "/var" || path.hasPrefix("/var/") {
            return URL(fileURLWithPath: "/private" + path, isDirectory: true)
        }
        return temporary
    }
}
