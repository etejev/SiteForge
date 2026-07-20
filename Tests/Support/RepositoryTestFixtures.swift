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
