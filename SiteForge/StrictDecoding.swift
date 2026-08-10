import Foundation

/// Closed current-schema records must not silently discard future semantics.
/// Legacy migration decoders opt out explicitly through `strictCurrentSchema`.
struct AnySiteForgeCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum SiteForgeDecodingPolicy {
    static let strictCurrentSchema = CodingUserInfoKey(rawValue: "app.siteforge.strict-current-schema")!

    static func requiresExactKeys(_ decoder: Decoder) -> Bool {
        decoder.userInfo[strictCurrentSchema] as? Bool == true
    }
}

func requireExactKeys<Key: CodingKey & CaseIterable>(
    _ type: Key.Type,
    in decoder: Decoder,
    when enabled: Bool = true
) throws {
    guard enabled else { return }
    let container = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    let expected = Set(Key.allCases.map(\.stringValue))
    guard actual == expected else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Current SiteForge schema requires an exact closed key set."
            )
        )
    }
}

/// Historical migrations may intentionally omit fields that did not exist in
/// their source schema, but they must never silently accept a field introduced
/// by a newer schema. This keeps a relabeled newer payload from being decoded
/// as an older shape and losing semantics during migration.
func requireKnownKeys<Key: CodingKey & CaseIterable>(
    _ type: Key.Type,
    in decoder: Decoder
) throws {
    let container = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    let allowed = Set(Key.allCases.map(\.stringValue))
    guard actual.isSubset(of: allowed) else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Historical SiteForge schema contains an unknown key."
            )
        )
    }
}

func requireExactlyOneCase<Key: CodingKey & CaseIterable>(
    _ type: Key.Type,
    in decoder: Decoder
) throws {
    let container = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    let allowed = Set(Key.allCases.map(\.stringValue))
    guard actual.count == 1, actual.isSubset(of: allowed) else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Current SiteForge schema requires exactly one known enum case."
            )
        )
    }
}
