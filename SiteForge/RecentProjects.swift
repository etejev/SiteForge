import Foundation

struct RecentProjectID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct RecentProjectReference: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: RecentProjectID
    let bookmarkKey: String
    let displayName: String

    init(id: RecentProjectID, bookmarkKey: String, displayName: String) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.bookmarkKey = bookmarkKey
        self.displayName = displayName
    }
}

protocol RecentProjectPersisting: Sendable {
    func load() async throws -> [RecentProjectReference]
    func save(_ projects: [RecentProjectReference]) async throws
}

enum RecentProjectStoreFailure: Error, Equatable, Sendable {
    case malformed
}

actor RecentProjectStore: RecentProjectPersisting {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let projects: [RecentProjectReference]
    }

    static let currentSchemaVersion = 1
    static let capacity = 8
    private let url: URL

    init(url: URL = RecentProjectStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SiteForge/RecentProjects/recent-projects.json")
    }

    func load() throws -> [RecentProjectReference] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == Self.currentSchemaVersion,
                  RecentProjectPolicy.isValid(envelope.projects) else {
                throw RecentProjectStoreFailure.malformed
            }
            return Array(envelope.projects.prefix(Self.capacity))
        } catch let error as RecentProjectStoreFailure {
            throw error
        } catch {
            throw RecentProjectStoreFailure.malformed
        }
    }

    func save(_ projects: [RecentProjectReference]) throws {
        guard RecentProjectPolicy.isValid(projects) else {
            throw RecentProjectStoreFailure.malformed
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Envelope(
            schemaVersion: Self.currentSchemaVersion,
            projects: Array(projects.prefix(Self.capacity))
        ))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum RecentProjectPolicy {
    static func recording(_ url: URL, in current: [RecentProjectReference]) -> [RecentProjectReference] {
        let key = FileAccessService.key(for: url)
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBookmarkKey(key), isValidDisplayName(name) else { return current }
        let item = RecentProjectReference(
            id: RecentProjectID(rawValue: "recent-\(key.prefix(16))"),
            bookmarkKey: key,
            displayName: name
        )
        return Array(([item] + current.filter { $0.bookmarkKey != key }).prefix(RecentProjectStore.capacity))
    }

    static func removing(_ id: RecentProjectID, from current: [RecentProjectReference]) -> [RecentProjectReference] {
        current.filter { $0.id != id }
    }

    static func isValid(_ projects: [RecentProjectReference]) -> Bool {
        projects.count <= RecentProjectStore.capacity
            && Set(projects.map(\.id)).count == projects.count
            && Set(projects.map(\.bookmarkKey)).count == projects.count
            && projects.allSatisfy {
                $0.schemaVersion == RecentProjectReference.currentSchemaVersion
                    && $0.id.rawValue == "recent-\($0.bookmarkKey.prefix(16))"
                    && isValidBookmarkKey($0.bookmarkKey)
                    && isValidDisplayName($0.displayName)
            }
    }

    private static func isValidBookmarkKey(_ key: String) -> Bool {
        key.count == 64 && key == key.lowercased() && key.allSatisfy(\.isHexDigit)
    }

    private static func isValidDisplayName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 160 && !name.contains("/") && !name.contains(":")
            && name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}
