import CoreText
import CryptoKit
import Darwin
import Foundation
import ImageIO
import os
import Vision
import UniformTypeIdentifiers

/// Immutable adapter over the existing package resource index, not another
/// store. Call on a worker: resourceData validates original bytes/hashes.
/// The package may contain an older saved revision, but never a foreign
/// document's resources. Missing individual blobs remain explicit absences.
struct ProjectImageResourceSnapshot: Sendable {
    let descriptors: [ResourceID: ProjectResourceDescriptor]
    let data: [ResourceID: Data]
    let images: [AssetID: Data]

    init(document: CanonicalDocument, package: ProjectPackage) throws {
        try Task.checkCancellation()
        guard document.id == package.document.id else { throw ProjectResourceError.corruptIndex }
        let index = try ProjectResourceIndex.decode(from: package)
        // SF-0805 / SF-0803: project font and media files travel with image resources.
        let referenced = Set(document.imageAssets.map(\.resourceID)).union(document.fontAssets.map(\.resourceID))
            .union(document.mediaAssets.map(\.resourceID))
        var descriptors: [ResourceID: ProjectResourceDescriptor] = [:], data: [ResourceID: Data] = [:]
        for descriptor in index?.resources ?? [] where referenced.contains(descriptor.id) {
            try Task.checkCancellation()
            descriptors[descriptor.id] = descriptor
            data[descriptor.id] = try? package.resourceData(for: descriptor)
        }
        var images: [AssetID: Data] = [:]
        for asset in document.imageAssets {
            try Task.checkCancellation()
            guard let descriptor = descriptors[asset.resourceID], descriptor.sha256 == asset.contentHash,
                  descriptor.byteCount == asset.byteCount, let bytes = data[asset.resourceID] else { continue }
            images[asset.id] = bytes
        }
        self.descriptors = descriptors; self.data = data; self.images = images
    }
}

/// Derived reference inventory shared by Assets, replacement disclosure and
/// Reveal Usage. It is not serialized and does not own resource lifetime.
struct ImageAssetReference: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case image = "Images", fill = "Image fills", definition = "Component defaults"
        case mediaOverride = "Component overrides", favicon = "Website favicon"
        case socialImage = "Social image"
        /// OD-038 (ADR-0087): an image one language shows instead of the element's own.
        case translation = "Translated images"
    }
    let kind: Kind
    let pageID: PageID?
    let nodeID: NodeID?
    static func references(to assetID: AssetID, in document: CanonicalDocument) -> [Self] {
        let raw = assetID.description
        var result: [Self] = []
        for page in document.pages {
            for node in page.canonicalDepthFirstNodes() {
                if node.insertionStringProperty(CanonicalImageStyle.namespace + "assetID") == raw {
                    result.append(.init(kind: page.role == .componentDefinition ? .definition : .image, pageID: page.id, nodeID: node.id))
                }
                if node.insertionStringProperty(CanonicalImageFill.assetKey) == raw {
                    result.append(.init(kind: .fill, pageID: page.id, nodeID: node.id))
                }
                for property in node.properties where CanonicalComponentMedia.overrideID(property.key.rawValue) != nil && property.value == .string(raw) {
                    result.append(.init(kind: .mediaOverride, pageID: page.id, nodeID: node.id))
                }
                // OD-038 (ADR-0087): Replace Everywhere retargets translated images and
                // delete is refused while one exists, so Reveal Usage lists them too
                // (translations of removed languages included: they are still stored).
                for entry in CanonicalTranslations.translations(on: node)
                where entry.key.field == .imageAssetID && entry.property.value == .string(raw) {
                    result.append(.init(kind: .translation, pageID: page.id, nodeID: node.id))
                }
            }
        }
        if document.websiteMetadata?.faviconAssetID == assetID { result.append(.init(kind: .favicon, pageID: nil, nodeID: nil)) }
        if document.websiteMetadata?.socialImageAssetID == assetID { result.append(.init(kind: .socialImage, pageID: nil, nodeID: nil)) }
        return result
    }
    static func summary(_ references: [Self]) -> String {
        Kind.allCases.compactMap { kind -> String? in
            let count = references.filter { $0.kind == kind }.count
            return count == 0 ? nil : "\(kind.rawValue): \(count)"
        }.joined(separator: " · ")
    }
}

/// SF-0807-001/003/004 (ADR-0144): what uses an asset and how to change that
/// in one undoable step. References are found with `ImageAssetReference` (the
/// same scan Reveal Usage, Replace Everywhere and delete use).
enum ImageAssetDependencies {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0807-%03d", $0) })

    /// The node properties that hold an asset use: exactly the ones
    /// `retarget` moves (Image, image fill, component value, translation).
    static func holdsAssetUse(_ key: String) -> Bool {
        key == CanonicalImageStyle.namespace + "assetID" || key == CanonicalImageFill.assetKey
            || CanonicalComponentMedia.overrideID(key) != nil
            || SiteTranslationKey(rawValue: key)?.field == .imageAssetID
    }

    /// Library assets something uses: a node property above, the favicon or
    /// social image, or a collection item (OD-035). One pass over the project
    /// instead of one per asset (SF-0807-007), so the Assets list, Remove
    /// Unused and export stay responsive with thousands of assets and objects.
    static func usedAssetIDs(in document: CanonicalDocument) -> Set<AssetID> {
        let library = Dictionary(document.imageAssets.map { ($0.id.description, $0.id) }, uniquingKeysWith: { first, _ in first })
        var used = Set<AssetID>()
        for page in document.pages {
            for node in page.nodes {
                for property in node.properties {
                    guard case .string(let raw) = property.value, let id = library[raw],
                          holdsAssetUse(property.key.rawValue) else { continue }
                    used.insert(id)
                }
            }
        }
        for id in [document.websiteMetadata?.faviconAssetID, document.websiteMetadata?.socialImageAssetID].compactMap({ $0 })
        where library[id.description] != nil {
            used.insert(id)
        }
        for collection in document.collections {
            for item in collection.items {
                for value in item.values {
                    if case .image(let id) = value.value, library[id.description] != nil { used.insert(id) }
                }
            }
        }
        return used
    }

    /// Library assets nothing uses (see `usedAssetIDs`), in library order.
    static func unusedAssetIDs(in document: CanonicalDocument) -> [AssetID] {
        let used = usedAssetIDs(in: document)
        return document.imageAssets.filter { !used.contains($0.id) }.map(\.id)
    }

    /// SF-0807-002: points every reference to `source` at `target` instead,
    /// keeping each use's fit, alt text, geometry and organization; `source`
    /// stays in the library (now unused) so Undo or reuse is possible.
    static func retarget(from source: AssetID, to target: AssetID, in document: CanonicalDocument,
                         expectedRevision: UInt64, isLifecycleAvailable: Bool) throws -> (command: DocumentCommand, count: Int) {
        guard isLifecycleAvailable else { throw CommandExecutionError.disabled("Assets can't be changed while the project is busy.") }
        guard document.revision == expectedRevision else {
            throw CommandExecutionError.disabled("The project changed. Nothing changed; choose the assets again.")
        }
        guard source != target else { throw CommandExecutionError.disabled("Choose a different asset to use instead.") }
        guard document.imageAssets.contains(where: { $0.id == source }), document.imageAssets.contains(where: { $0.id == target }) else {
            throw CommandExecutionError.disabled("One of the assets no longer exists. Nothing changed.")
        }
        let raw = source.description, replacement = PropertyValue.string(target.description)
        guard !document.pages.flatMap(\.nodes).contains(where: { CanonicalImageStyle.resolve($0)?.assetID == source && (try? CanonicalQRCode.resolve($0)) != nil }) else {
            throw CommandExecutionError.disabled("This asset is a generated QR code. Convert it to an Image first.")
        }
        var commands: [DocumentCommand] = []
        for page in document.pages {
            for node in page.nodes {
                for property in node.properties where property.value == .string(raw) {
                    guard holdsAssetUse(property.key.rawValue) else { continue }
                    commands.append(.setProperty(.init(pageID: page.id, nodeID: node.id,
                        property: .init(id: property.id, key: property.key, value: replacement, origin: property.origin))))
                }
            }
        }
        var count = commands.count
        // OD-035: collection items that show `source` show `target` instead,
        // in the same transaction, so the source really becomes unused.
        var collections = document.collections, collectionUses = 0
        for c in collections.indices {
            for i in collections[c].items.indices {
                for v in collections[c].items[i].values.indices where collections[c].items[i].values[v].value == .image(source) {
                    collections[c].items[i].values[v].value = .image(target)
                    collectionUses += 1
                }
            }
        }
        if collectionUses > 0 {
            commands.append(.setCollections(.init(documentID: document.id, collections: collections)))
            count += collectionUses
        }
        if var metadata = document.websiteMetadata, metadata.faviconAssetID == source || metadata.socialImageAssetID == source {
            if metadata.faviconAssetID == source { metadata.faviconAssetID = target; count += 1 }
            if metadata.socialImageAssetID == source { metadata.socialImageAssetID = target; count += 1 }
            commands.append(.setWebsiteMetadata(.init(documentID: document.id, metadata: metadata)))
        }
        guard !commands.isEmpty else { throw CommandExecutionError.disabled("Nothing uses this asset, so there is nothing to change.") }
        let command = DocumentCommand.batch(commands)
        let availability = CommandRegistry().availability(for: command, in: document)
        guard availability.isEnabled else {
            throw CommandExecutionError.disabled(availability.disabledReason ?? "These uses can't take the other asset.")
        }
        return (command, count)
    }

    /// SF-0807-004/005: removes every unused asset in one undoable step.
    static func removeUnused(in document: CanonicalDocument, expectedRevision: UInt64,
                             isLifecycleAvailable: Bool) throws -> (command: DocumentCommand, count: Int) {
        guard isLifecycleAvailable else { throw CommandExecutionError.disabled("Assets can't be changed while the project is busy.") }
        guard document.revision == expectedRevision else {
            throw CommandExecutionError.disabled("The project changed. Nothing changed; try again.")
        }
        let unused = unusedAssetIDs(in: document)
        guard !unused.isEmpty else { throw CommandExecutionError.disabled("Every asset is in use.") }
        let command = DocumentCommand.batch(unused.map { .removeImageAsset(.init(assetID: $0)) })
        let availability = CommandRegistry().availability(for: command, in: document)
        guard availability.isEnabled else {
            throw CommandExecutionError.disabled(availability.disabledReason ?? "The unused assets can't be removed.")
        }
        return (command, unused.count)
    }
}

enum ImageImportError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, permissionDenied, unsupported, corrupt, tooLarge, invalidDimensions, ioFailure
    /// SF-0804: entity declarations, a non-SVG root, or an SVG that cannot be
    /// recolored as one icon.
    case unsupportedSVG
    var errorDescription: String? {
        switch self {
        case .cancelled: "Image import was cancelled."
        case .permissionDenied: "SiteForge cannot read the selected image. Choose an accessible local file."
        case .unsupported: "This image type is not supported. Choose PNG, JPEG, GIF, TIFF, HEIC, or SVG."
        case .unsupportedSVG: "This SVG uses features SiteForge can't import or recolor safely. Export it again as a plain SVG, or use PNG."
        case .corrupt: "The selected image is corrupt or cannot be decoded."
        case .tooLarge: "The selected image exceeds the 16 MB project-resource limit."
        case .invalidDimensions: "The selected image dimensions exceed the supported range."
        case .ioFailure: "The selected image could not be imported."
        }
    }
    var diagnosticCategory: String {
        switch self {
        case .cancelled: "cancelled"
        case .permissionDenied: "permission-denied"
        case .unsupported: "unsupported-format"
        case .unsupportedSVG: "unsupported-svg"
        case .corrupt: "decode-failed"
        case .tooLarge: "resource-limit"
        case .invalidDimensions: "dimension-limit"
        case .ioFailure: "io-failure"
        }
    }
}

struct PreparedImageImport: Sendable {
    let asset: ImageAsset
    let descriptor: ProjectResourceDescriptor
    let data: Data
    /// SF-0804: present only for SVG imports (what sanitizing removed).
    var svgReport: SVGSanitizationReport? = nil
}

/// Image byte loading and metadata decoding stay actor-isolated. Results are
/// immutable and identity-tagged before the main actor performs the canonical
/// transaction, so stale imports can be ignored without publishing drafts.
actor ImageImportWorker {
    func prepare(url: URL) throws -> PreparedImageImport {
        try Task.checkCancellation()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch CocoaError.fileReadNoPermission { throw ImageImportError.permissionDenied }
        catch { throw ImageImportError.ioFailure }
        guard !data.isEmpty else { throw ImageImportError.corrupt }
        guard data.count <= ProjectResourceIndex.maximumResourceBytes else { throw ImageImportError.tooLarge }
        try Task.checkCancellation()
        if url.pathExtension.lowercased() == "svg" || SVGAssetSanitizer.looksLikeSVG(data) {
            return try prepareSVG(data: data, url: url)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageImportError.corrupt
        }
        guard (1...ImageAsset.maximumPixelDimension).contains(width),
              (1...ImageAsset.maximumPixelDimension).contains(height) else {
            throw ImageImportError.invalidDimensions
        }
        let sourceType = CGImageSourceGetType(source) as String?
        let format: ImageAssetFormat = switch sourceType {
        case UTType.png.identifier: .png
        case UTType.jpeg.identifier: .jpeg
        case UTType.gif.identifier: .gif
        case UTType.tiff.identifier: .tiff
        case UTType.heic.identifier, UTType.heif.identifier: .heic
        default: throw ImageImportError.unsupported
        }
        guard CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) != nil else { throw ImageImportError.corrupt }
        let hash = ProjectResourceStore.digest(data)
        let resourceID = ResourceID()
        let filename = String(url.lastPathComponent.prefix(255))
        let stem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = stem.isEmpty ? "Imported Image" : String(stem.prefix(255))
        let descriptor = ProjectResourceDescriptor(
            id: resourceID, filename: filename, mediaType: format.mediaType,
            byteCount: data.count, sha256: hash
        )
        return PreparedImageImport(
            asset: ImageAsset(
                resourceID: resourceID, displayName: displayName,
                originalFilename: filename, format: format,
                pixelWidth: width, pixelHeight: height,
                byteCount: data.count, contentHash: hash
            ),
            descriptor: descriptor, data: data
        )
    }

    /// SF-0804 (OD-045): only the sanitized re-serialization is stored; the
    /// original bytes never enter the project.
    private func prepareSVG(data: Data, url: URL) throws -> PreparedImageImport {
        let sanitized = try SVGAssetSanitizer.sanitize(data)
        try Task.checkCancellation()
        let hash = ProjectResourceStore.digest(sanitized.data)
        let resourceID = ResourceID()
        let filename = String(url.lastPathComponent.prefix(255))
        let stem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = stem.isEmpty ? "Imported SVG" : String(stem.prefix(255))
        let descriptor = ProjectResourceDescriptor(
            id: resourceID, filename: filename, mediaType: ImageAssetFormat.svg.mediaType,
            byteCount: sanitized.data.count, sha256: hash
        )
        return PreparedImageImport(
            asset: ImageAsset(
                resourceID: resourceID, displayName: displayName,
                originalFilename: filename, format: .svg,
                pixelWidth: sanitized.report.pixelWidth, pixelHeight: sanitized.report.pixelHeight,
                byteCount: sanitized.data.count, contentHash: hash
            ),
            descriptor: descriptor, data: sanitized.data, svgReport: sanitized.report
        )
    }
}

/// Produces bounded preview data away from the main actor. The canonical
/// resource remains byte-for-byte unchanged; this derivative is scene-local
/// editor state and is never serialized or entered into document history.
actor ImageThumbnailWorker {
    func thumbnailPNG(from data: Data, maximumPixelSize: Int = 160) throws -> Data {
        // SF-0804: an SVG is vector data, so its sanitized bytes are their own
        // preview (AppKit scales them); no raster derivative is produced.
        if SVGAssetSanitizer.looksLikeSVG(data) { return data }
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            throw ImageImportError.corrupt
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw ImageImportError.ioFailure }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageImportError.ioFailure }
        return output as Data
    }
}

// MARK: - SF-0805 project fonts (OD-045, ADR-0051)

enum FontImportError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, permissionDenied, unsupported, corrupt, tooLarge, duplicateFile, duplicateFace, ioFailure
    /// SF-0805-004 (lane V08): an intact WOFF2 header whose tables Core Text
    /// can't read, told apart from a damaged file so the recovery is specific.
    case unreadableWOFF2
    var errorDescription: String? {
        switch self {
        case .cancelled: "Font import was cancelled."
        case .unreadableWOFF2: "SiteForge can't read this WOFF2 font on this Mac, so it can't check its family, weight and style. The file may be damaged or use a feature macOS can't open. Import the TrueType (.ttf) version of the font, or export the WOFF2 file again."
        case .permissionDenied: "SiteForge cannot read the selected font. Choose an accessible local file."
        case .unsupported: "This font type is not supported. Choose a WOFF2 or TrueType (.ttf) file."
        case .corrupt: "The selected font is damaged or cannot be read."
        case .tooLarge: "The selected font exceeds the 16 MB project-resource limit."
        case .duplicateFile: "This font file is already in the project."
        case .duplicateFace: "The project already has a face with this family, weight and style. Remove it first or change its weight or style."
        case .ioFailure: "The selected font could not be imported."
        }
    }
    var diagnosticCategory: String {
        switch self {
        case .cancelled: "cancelled"
        case .permissionDenied: "permission-denied"
        case .unsupported: "unsupported-format"
        case .corrupt: "decode-failed"
        case .tooLarge: "resource-limit"
        case .duplicateFile: "duplicate-resource"
        case .duplicateFace: "duplicate-face"
        case .unreadableWOFF2: "unreadable-woff2"
        case .ioFailure: "io-failure"
        }
    }
}

/// File signatures: `wOF2` (WOFF2) and `00 01 00 00` / `true` (TrueType).
/// OpenType-CFF (`OTTO`), WOFF 1 and collections are not accepted.
enum ProjectFontFormatSniffer {
    static func format(of data: Data) -> FontAssetFormat? {
        let tag = Array(data.prefix(4))
        guard tag.count == 4 else { return nil }
        if tag == [0x77, 0x4F, 0x46, 0x32] { return .woff2 }
        if tag == [0x00, 0x01, 0x00, 0x00] || tag == [0x74, 0x72, 0x75, 0x65] { return .ttf }
        return nil
    }

    /// The fixed 48-byte WOFF2 header (big-endian): `length` at 8 is the
    /// whole file, `numTables` at 12 is not 0 and `reserved` at 14 is 0. Core
    /// Text still reads the tables; this only tells a damaged file from one
    /// this Mac can't open.
    static func hasValidWOFF2Header(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(48))
        guard bytes.count == 48, Array(bytes[0..<4]) == [0x77, 0x4F, 0x46, 0x32] else { return false }
        func value(_ offset: Int, _ width: Int) -> Int {
            bytes[offset..<(offset + width)].reduce(0) { $0 << 8 | Int($1) }
        }
        return value(8, 4) == data.count && value(12, 2) > 0 && value(14, 2) == 0
    }
}

/// Facts read from a font's OS/2 table (big-endian): usWeightClass at 4,
/// fsType at 8, fsSelection at 62.
enum ProjectFontMetadata {
    struct OS2: Equatable, Sendable {
        let weight: Int
        let italic: Bool
        /// fsType embedding level 2: "Restricted License embedding".
        let restrictedEmbedding: Bool
    }

    static func os2(_ table: Data?) -> OS2? {
        guard let table, table.count >= 64 else { return nil }
        let bytes = [UInt8](table)
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
        let weight = min(900, max(100, Int((Double(u16(4)) / 100).rounded()) * 100))
        return OS2(weight: weight, italic: u16(62) & 0x0001 != 0, restrictedEmbedding: u16(8) & 0x000F == 0x0002)
    }
}

struct PreparedFontImport: Sendable {
    let font: FontAsset
    let descriptor: ProjectResourceDescriptor
    let data: Data
}

/// Reads and checks font bytes off the main actor. Original bytes are kept
/// unchanged (no subsetting or conversion).
actor FontImportWorker {
    func prepare(url: URL) throws -> PreparedFontImport {
        try Task.checkCancellation()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch CocoaError.fileReadNoPermission { throw FontImportError.permissionDenied }
        catch { throw FontImportError.ioFailure }
        guard !data.isEmpty else { throw FontImportError.corrupt }
        guard data.count <= ProjectResourceIndex.maximumResourceBytes else { throw FontImportError.tooLarge }
        guard let format = ProjectFontFormatSniffer.format(of: data) else { throw FontImportError.unsupported }
        try Task.checkCancellation()
        guard let fontDescriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) else {
            throw format == .woff2 && ProjectFontFormatSniffer.hasValidWOFF2Header(data)
                ? FontImportError.unreadableWOFF2 : FontImportError.corrupt
        }
        let font = CTFontCreateWithFontDescriptor(fontDescriptor, 12, nil)
        let os2 = ProjectFontMetadata.os2(CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []).map { $0 as Data })
        let filename = String(url.lastPathComponent.prefix(255))
        let stem = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        var family = (CTFontCopyFamilyName(font) as String).trimmingCharacters(in: .whitespacesAndNewlines)
        if !FontAsset.isValidFamily(family) { family = String(stem.prefix(FontAsset.maximumFamilyBytes)).trimmingCharacters(in: .whitespaces) }
        if !FontAsset.isValidFamily(family) { family = "Project Font" }
        let hash = ProjectResourceStore.digest(data)
        let resourceID = ResourceID()
        let asset = FontAsset(
            resourceID: resourceID, family: family, weight: os2?.weight ?? 400,
            style: (os2?.italic ?? CTFontGetSymbolicTraits(font).contains(.traitItalic)) ? .italic : .normal,
            format: format, originalFilename: filename, byteCount: data.count, contentHash: hash,
            rights: os2?.restrictedEmbedding == true ? .editorOnly : .unconfirmed
        )
        guard asset.isValid else { throw FontImportError.corrupt }
        return PreparedFontImport(
            font: asset,
            descriptor: ProjectResourceDescriptor(id: resourceID, filename: filename, mediaType: format.mediaType,
                                                  byteCount: data.count, sha256: hash),
            data: data
        )
    }
}

/// Website output for project fonts: `@font-face` only for faces whose
/// declared rights allow web embedding and whose bytes were verified, and the
/// family's fallback stack after every use of the family.
enum ProjectFontOutput {
    static func cssFamilyName(_ family: String) -> String {
        family.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" { return String(scalar) }
            return "\\" + String(scalar.value, radix: 16) + " "
        }.joined()
    }

    static func isUsed(_ family: String, in document: CanonicalDocument) -> Bool {
        ProjectFontResolver.usageCount(family: family, in: document) > 0
    }

    /// Faces to package: declared web rights and used by at least one text.
    static func exportCandidates(in document: CanonicalDocument) -> [FontAsset] {
        document.fontAssets.filter { $0.rights.allowsWebExport && isUsed($0.family, in: document) }
            .sorted { $0.id.description < $1.id.description }
    }

    static func exportedPaths(fonts: [FontAsset], entries: [StaticAssetExportEntry]) -> [AssetID: String] {
        var result: [AssetID: String] = [:]
        for font in fonts where font.rights.allowsWebExport {
            if let entry = entries.first(where: { $0.resourceID == font.resourceID && $0.sha256 == font.contentHash }) {
                result[font.id] = entry.outputPath
            }
        }
        return result
    }

    static func fontFaceCSS(fonts: [FontAsset], paths: [AssetID: String]) -> String {
        fonts.sorted { ($0.family.lowercased(), $0.weight, $0.style.rawValue, $0.id.description)
            < ($1.family.lowercased(), $1.weight, $1.style.rawValue, $1.id.description) }
            .compactMap { font -> String? in
                guard font.rights.allowsWebExport, let path = paths[font.id],
                      path.range(of: "^assets/[a-f0-9]{64}\\.(woff2|ttf)$", options: .regularExpression) != nil else { return nil }
                return "@font-face { font-family: \"\(cssFamilyName(font.family))\"; src: url(\"\(path)\") format(\"\(font.format.cssFormat)\"); "
                    + "font-weight: \(font.weight); font-style: \(font.style.rawValue); font-display: swap; }"
            }
            .joined(separator: "\n")
    }

    /// Lowercased family → fallback CSS (ProjectFontResolver.fallback rule).
    static func fallbackStacks(fonts: [FontAsset]) -> [String: String] {
        var result: [String: String] = [:]
        for family in ProjectFontResolver.families(in: fonts) {
            if let stack = ProjectFontResolver.fallback(family: family, in: fonts) { result[family.lowercased()] = stack.css }
        }
        return result
    }

    static func usesProjectFont(_ page: DocumentPage, fonts: [FontAsset]) -> Bool {
        guard !fonts.isEmpty else { return false }
        return page.nodes.contains { node in
            guard let family = CanonicalTypography.resolved(for: node)?.family else { return false }
            return !ProjectFontResolver.faces(family: family, in: fonts).isEmpty
        }
    }

    /// SF-0805-003/004 findings; no family names or text in the messages.
    static func findings(document: CanonicalDocument) -> [StaticBuildFinding] {
        var result: [StaticBuildFinding] = []
        let nodes = document.pages.flatMap(\.nodes)
        for family in ProjectFontResolver.families(in: document.fontAssets) {
            let users = nodes.filter { CanonicalTypography.resolved(for: $0)?.family.caseInsensitiveCompare(family) == .orderedSame }
            guard let first = users.first else { continue }
            let faces = ProjectFontResolver.faces(family: family, in: document.fontAssets)
            let exported = faces.filter(\.rights.allowsWebExport)
            if exported.isEmpty {
                let unconfirmed = faces.contains { $0.rights == .unconfirmed }
                result.append(.init(severity: .warning, code: unconfirmed ? "font-rights-unconfirmed" : "font-not-licensed-for-web",
                    requirementID: "SF-0805-004", affectedNodeID: first.id,
                    explanation: unconfirmed
                        ? "A project font is used, but its web embedding rights are not confirmed, so it is not exported and visitors see its fallback fonts."
                        : "A project font is used, but it is marked for editing only, so it is not exported and visitors see its fallback fonts.",
                    repair: "Confirm in Project Fonts that the license allows web embedding, or choose another font."))
                continue
            }
            func weight(_ node: DocumentNode) -> Int? {
                CanonicalTypography.resolved(for: node).map { ProjectFontResolver.cssWeight($0.weight) }
            }
            for wanted in Set(users.compactMap(weight)).sorted()
            where ProjectFontResolver.resolve(family: family, weight: wanted, in: exported).rule != .exactFace {
                result.append(.init(severity: .warning, code: "font-face-missing", requirementID: "SF-0805-003",
                    affectedNodeID: users.first { weight($0) == wanted }?.id,
                    explanation: "Text uses a weight that no exported face of its project font provides; browsers use the nearest face and may synthesize the rest.",
                    repair: "Import the missing face in Project Fonts, or choose a weight the font provides."))
            }
        }
        return result
    }
}

// MARK: - SF-0803 video and audio (OD-045, ADR-0100)

enum MediaImportError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, permissionDenied, unsupported, corrupt, tooLarge, duplicateFile, wrongKind, ioFailure
    var errorDescription: String? {
        switch self {
        case .cancelled: "Video and audio import was cancelled."
        case .permissionDenied: "SiteForge cannot read the selected file. Choose an accessible local file."
        case .unsupported: "This file type is not supported. Choose MP4 or WebM video, MP3, M4A, OGG or WAV audio, or WebVTT (.vtt) captions."
        case .corrupt: "The selected file is damaged or is not the type its name says."
        case .tooLarge: "The selected file exceeds the 16 MB project-resource limit. SiteForge never re-encodes media; export a smaller file and import it again."
        case .duplicateFile: "This file is already in the project."
        case .wrongKind: "The replacement must be the same kind of file (video, audio or captions)."
        case .ioFailure: "The selected file could not be imported."
        }
    }
    var diagnosticCategory: String {
        switch self {
        case .cancelled: "cancelled"
        case .permissionDenied: "permission-denied"
        case .unsupported: "unsupported-format"
        case .corrupt: "decode-failed"
        case .tooLarge: "resource-limit"
        case .duplicateFile: "duplicate-resource"
        case .wrongKind: "wrong-kind"
        case .ioFailure: "io-failure"
        }
    }
}

/// File signatures only (no decoding, no transcoding): ISO BMFF `ftyp` (MP4;
/// M4A by brand or `.m4a`; QuickTime `qt` brands refused), EBML with DocType
/// `webm`, `OggS`, `RIFF`…`WAVE`, `ID3` or an MPEG audio frame sync in an
/// `.mp3`, and `WEBVTT` UTF-8 text (optional byte-order mark).
enum ProjectMediaFormatSniffer {
    static let knownExtensions: Set<String> = ["mp4", "m4v", "webm", "mp3", "m4a", "ogg", "oga", "wav", "vtt"]

    static func format(of data: Data, fileExtension: String) -> MediaAssetFormat? {
        let head = [UInt8](data.prefix(64))
        let ext = fileExtension.lowercased()
        func matches(_ text: String, at offset: Int) -> Bool {
            let bytes = Array(text.utf8)
            return head.count >= offset + bytes.count && Array(head[offset..<(offset + bytes.count)]) == bytes
        }
        if matches("ftyp", at: 4) {
            guard head.count >= 12 else { return nil }
            let brand = String(decoding: head[8..<12], as: UTF8.self)
            if brand.hasPrefix("qt") { return nil }
            if brand == "M4A " || brand == "M4B " || ext == "m4a" { return MediaAssetFormat.m4a }
            return MediaAssetFormat.mp4
        }
        if head.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) {
            let webm = Array("webm".utf8)
            let found = head.indices.contains { start in
                start + webm.count <= head.count && Array(head[start..<(start + webm.count)]) == webm
            }
            return found ? MediaAssetFormat.webm : nil
        }
        if matches("OggS", at: 0) { return .ogg }
        if matches("RIFF", at: 0), matches("WAVE", at: 8) { return .wav }
        if matches("ID3", at: 0) { return .mp3 }
        if ext == "mp3", head.count >= 2, head[0] == 0xFF, head[1] & 0xE0 == 0xE0, head[1] & 0x06 != 0 { return .mp3 }
        var text = head
        if text.starts(with: [0xEF, 0xBB, 0xBF]) { text.removeFirst(3) }
        let separators: [UInt8] = [0x20, 0x09, 0x0A, 0x0D]
        if text.starts(with: Array("WEBVTT".utf8)), text.count == 6 || separators.contains(text[6]) {
            return String(data: data, encoding: .utf8) != nil && !data.contains(0) ? MediaAssetFormat.vtt : nil
        }
        return nil
    }
}

struct PreparedMediaImport: Sendable {
    let media: MediaAsset
    let descriptor: ProjectResourceDescriptor
    let data: Data
}

/// Reads and checks media bytes off the main actor. Original bytes are kept
/// unchanged (OD-045: no transcoding).
actor MediaImportWorker {
    func prepare(url: URL) throws -> PreparedMediaImport {
        try Task.checkCancellation()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > ProjectResourceIndex.maximumResourceBytes {
            throw MediaImportError.tooLarge
        }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch CocoaError.fileReadNoPermission { throw MediaImportError.permissionDenied }
        catch { throw MediaImportError.ioFailure }
        guard !data.isEmpty else { throw MediaImportError.corrupt }
        guard data.count <= ProjectResourceIndex.maximumResourceBytes else { throw MediaImportError.tooLarge }
        guard let format = ProjectMediaFormatSniffer.format(of: data, fileExtension: url.pathExtension) else {
            throw ProjectMediaFormatSniffer.knownExtensions.contains(url.pathExtension.lowercased())
                ? MediaImportError.corrupt : MediaImportError.unsupported
        }
        try Task.checkCancellation()
        let filename = String(url.lastPathComponent.prefix(255))
        let stem = String(String.UnicodeScalarView(url.deletingPathExtension().lastPathComponent.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = ProjectResourceStore.digest(data)
        let resourceID = ResourceID()
        let media = MediaAsset(resourceID: resourceID, displayName: stem.isEmpty ? format.kind.title : String(stem.prefix(200)),
                               originalFilename: filename, format: format, byteCount: data.count, contentHash: hash)
        guard media.isValid else { throw MediaImportError.corrupt }
        return PreparedMediaImport(
            media: media,
            descriptor: ProjectResourceDescriptor(id: resourceID, filename: filename, mediaType: format.mediaType,
                                                  byteCount: data.count, sha256: hash),
            data: data
        )
    }
}

/// Website output for project media: only files an output page plays (or
/// captions with) are copied, each once, under a content-addressed name.
enum ProjectMediaOutput {
    static func references(_ id: AssetID, _ node: DocumentNode) -> Bool {
        guard let playback = CanonicalMediaPlayback.resolve(node) else { return false }
        return playback.assetID == id || playback.captionsAssetID == id
    }

    /// Files used by the given output nodes, in stable identity order.
    static func exportCandidates(nodes: [DocumentNode], document: CanonicalDocument) -> [MediaAsset] {
        document.mediaAssets.filter { asset in nodes.contains { references(asset.id, $0) } }
            .sorted { $0.id.description < $1.id.description }
    }

    static func exportedPaths(media: [MediaAsset], entries: [StaticAssetExportEntry]) -> [AssetID: String] {
        var result: [AssetID: String] = [:]
        for asset in media {
            if let entry = entries.first(where: { $0.resourceID == asset.resourceID && $0.sha256 == asset.contentHash }) {
                result[asset.id] = entry.outputPath
            }
        }
        return result
    }

    /// SF-0803-006: a video without captions is named (content-free).
    static func findings(nodes: [DocumentNode], document: CanonicalDocument) -> [StaticBuildFinding] {
        let media = Dictionary(uniqueKeysWithValues: document.mediaAssets.map { ($0.id, $0) })
        var result: [StaticBuildFinding] = []
        var reported = Set<NodeID>()
        for node in nodes {
            guard let playback = CanonicalMediaPlayback.resolve(node), media[playback.assetID]?.kind == .video,
                  playback.captionsAssetID == nil, reported.insert(node.id).inserted else { continue }
            result.append(.init(severity: .warning, code: "media-video-no-captions", requirementID: "SF-0803-006",
                affectedNodeID: node.id,
                explanation: "A video has no captions, so visitors who can't hear it may miss its content.",
                repair: "Import a WebVTT captions file in Video & Audio and choose it for the video in the Inspector."))
        }
        return result
    }
}

/// SF-0803-008 / SF-0804-008 / SF-0805-008: one content-free record per
/// media-asset operation (no names, bytes, colors or paths; identities are
/// hashed).
enum MediaAssetOperation: String, Equatable, Sendable {
    case svgImport = "svg-import", svgRecolor = "svg-recolor"
    case fontImport = "font-import", fontUpdate = "font-update", fontRemove = "font-remove"
    case mediaImport = "media-import", mediaReplace = "media-replace", mediaUpdate = "media-update"
    case mediaRemove = "media-remove", mediaPlayback = "media-playback"

    var requirementID: String {
        switch self {
        case .svgImport: "SF-0804-004"
        case .svgRecolor: "SF-0804-002"
        case .fontImport: "SF-0805-004"
        case .fontUpdate: "SF-0805-002"
        case .fontRemove: "SF-0805-005"
        case .mediaImport, .mediaReplace: "SF-0803-004"
        case .mediaUpdate, .mediaPlayback: "SF-0803-002"
        case .mediaRemove: "SF-0803-005"
        }
    }
}

struct MediaAssetDiagnosticRecord: Equatable, Sendable {
    let requirementID: String
    let operation: MediaAssetOperation
    let sanitizedAssetID: String?
    let durationNanoseconds: UInt64
    let succeeded: Bool
    let failureCategory: String?
    /// Counts only, for example "removed-parts=3".
    let detail: String?

    init(operation: MediaAssetOperation, assetID: AssetID?, startedAt: UInt64, now: UInt64 = DispatchTime.now().uptimeNanoseconds,
         failureCategory: String?, detail: String? = nil) {
        requirementID = operation.requirementID
        self.operation = operation
        sanitizedAssetID = assetID.map { DiagnosticStableIdentifier.sanitize($0.description, domain: .document, kind: "asset") }
        durationNanoseconds = now >= startedAt ? now - startedAt : 0
        succeeded = failureCategory == nil
        self.failureCategory = failureCategory
        self.detail = detail
    }
}

/// SF-0805: project faces are registered for this app process only, so the
/// canvas (which resolves families through Core Text) shows them. Bytes are
/// verified first and written once to an app-owned temporary folder named by
/// content hash; nothing is installed for other apps or kept after quit.
/// Each window that shows a face counts as one user; when the last user
/// stops using it, the face is unregistered so its text shows the fallback.
enum ProjectFontCanvasRegistration {
    /// Content hash → windows using the registered face. Registering,
    /// counting and unregistering happen under one lock, so one window's
    /// release never races another window's registration of the same file.
    private static let users = OSAllocatedUnfairLock(initialState: [String: Int]())

    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SiteForgeProjectFonts", isDirectory: true)
    }

    static func fileURL(format: FontAssetFormat, contentHash: String) -> URL {
        folder.appendingPathComponent(contentHash + "." + format.rawValue)
    }

    /// Registers verified bytes (once per process) and counts one more user.
    static func retain(_ data: Data, format: FontAssetFormat, contentHash: String) -> Bool {
        users.withLock { counts in
            guard register(data, format: format, contentHash: contentHash) else { return false }
            counts[contentHash, default: 0] += 1
            return true
        }
    }

    /// Counts one user less; the last one unregisters the face. Returns
    /// whether the face was unregistered.
    @discardableResult
    static func release(format: FontAssetFormat, contentHash: String) -> Bool {
        users.withLock { counts in
            guard let count = counts[contentHash] else { return false }
            guard count == 1 else {
                counts[contentHash] = count - 1
                return false
            }
            counts[contentHash] = nil
            return CTFontManagerUnregisterFontsForURL(fileURL(format: format, contentHash: contentHash) as CFURL, .process, nil)
        }
    }

    static func userCount(contentHash: String) -> Int {
        users.withLock { $0[contentHash] ?? 0 }
    }

    static func register(_ data: Data, format: FontAssetFormat, contentHash: String) -> Bool {
        guard ProjectFontFormatSniffer.format(of: data) == format,
              ProjectResourceStore.digest(data) == contentHash else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = fileURL(format: format, contentHash: contentHash)
            if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
            guard let failure = error?.takeRetainedValue() else { return false }
            return CFErrorGetCode(failure) == CTFontManagerError.alreadyRegistered.rawValue
        } catch {
            return false
        }
    }
}

/// SF-0805-003/007 (lane V08): the project faces one window shows on its
/// canvas. Reading and verifying bytes, writing the file and the Core Text
/// calls run on this actor, never on the main actor. Faces that leave the
/// document are released; bytes Core Text refuses are not retried.
actor ProjectFontCanvasSession {
    private var retained: [String: FontAssetFormat] = [:]
    private var refused = Set<String>()

    /// Brings the registered faces in line with `fonts`. Returns true when
    /// the canvas must be prepared again.
    func update(fonts: [FontAsset], package: ProjectPackage) -> Bool {
        let wanted = Set(fonts.map(\.contentHash))
        var changed = false
        for (hash, format) in retained where !wanted.contains(hash) {
            retained[hash] = nil
            if ProjectFontCanvasRegistration.release(format: format, contentHash: hash) { changed = true }
        }
        let index = try? ProjectResourceIndex.decode(from: package)
        for font in fonts where retained[font.contentHash] == nil && !refused.contains(font.contentHash) {
            // A file that is missing now is looked for again on the next change.
            guard let descriptor = index?.resources.first(where: { $0.id == font.resourceID }),
                  let bytes = try? package.resourceData(for: descriptor) else { continue }
            if ProjectFontCanvasRegistration.retain(bytes, format: font.format, contentHash: font.contentHash) {
                retained[font.contentHash] = font.format
                changed = true
            } else {
                refused.insert(font.contentHash)
            }
        }
        return changed
    }

    /// A closed window stops using its faces.
    deinit {
        for (hash, format) in retained { ProjectFontCanvasRegistration.release(format: format, contentHash: hash) }
    }
}

struct ProjectResourceDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: ResourceID
    let filename: String
    let mediaType: String
    let byteCount: Int
    let sha256: String
}

extension ProjectResourceDescriptor {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, filename, mediaType, byteCount, sha256
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ResourceID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
    }
}

struct ProjectResourceIndex: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let packageMemberPath = "resources/index-v1.json"
    static let maximumResourceCount = ImageAsset.maximumAssetCount
    static let maximumResourceBytes = ImageAsset.maximumResourceBytes
    static let maximumTotalBytes = 2 * 1_024 * 1_024 * 1_024

    static func blobMemberPath(for sha256: String) -> String {
        "resources/blobs/\(sha256).blob"
    }

    let version: Int
    let resources: [ProjectResourceDescriptor]

    init(version: Int = currentVersion, resources: [ProjectResourceDescriptor]) {
        self.version = version
        self.resources = resources.sorted { $0.id.description < $1.id.description }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, resources
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let decoded = try container.decode([ProjectResourceDescriptor].self, forKey: .resources)
        let canonical = decoded.sorted { $0.id.description < $1.id.description }
        guard decoded == canonical else {
            throw DecodingError.dataCorruptedError(
                forKey: .resources,
                in: container,
                debugDescription: "Resource descriptors must use stable-identity order."
            )
        }
        resources = decoded
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw ProjectResourceError.unsupportedIndexVersion(version) }
        guard resources.count <= Self.maximumResourceCount else { throw ProjectResourceError.capacityExceeded }
        var identities = Set<ResourceID>()
        var total = 0
        for resource in resources {
            guard identities.insert(resource.id).inserted else { throw ProjectResourceError.duplicateResource }
            guard !resource.filename.isEmpty,
                  !resource.filename.contains("/"),
                  !resource.filename.contains("\\"),
                  resource.filename != ".",
                  resource.filename != "..",
                  !resource.mediaType.isEmpty,
                  resource.byteCount > 0,
                  resource.byteCount <= Self.maximumResourceBytes,
                  resource.sha256.count == 64,
                  resource.sha256 == resource.sha256.lowercased(),
                  resource.sha256.allSatisfy({ $0.isHexDigit }) else {
                throw ProjectResourceError.malformedMetadata
            }
            let (next, overflow) = total.addingReportingOverflow(resource.byteCount)
            guard !overflow, next <= Self.maximumTotalBytes else { throw ProjectResourceError.capacityExceeded }
            total = next
        }
    }

    func encodedMember() throws -> ProjectPackageMember {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ProjectPackageMember(
            path: Self.packageMemberPath,
            role: .resource,
            data: try encoder.encode(self)
        )
    }

    static func decode(from package: ProjectPackage) throws -> ProjectResourceIndex? {
        guard let member = package.optionalMembers.first(where: { $0.path == packageMemberPath }) else {
            return nil
        }
        guard member.role == .resource else { throw ProjectResourceError.corruptIndex }
        do {
            let value = try JSONDecoder().decode(Self.self, from: member.data)
            try value.validate()
            return value
        } catch let error as ProjectResourceError {
            throw error
        } catch {
            throw ProjectResourceError.corruptIndex
        }
    }
}

// MARK: - SF-0804 SVG assets (OD-045, ADR-0050)

/// Content-free facts about one sanitized SVG. Derived on demand and never
/// serialized: canonical state stores only the sanitized bytes' metadata.
struct SVGSanitizationReport: Equatable, Sendable {
    /// Where the asset's pixel size came from (SF-0804-001: explicit root
    /// width/height, the viewBox, or the HTML replaced-element default).
    enum DimensionSource: String, Equatable, Sendable { case attributes, viewBox, defaulted }

    let removedElementCount: Int
    let removedAttributeCount: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let dimensionSource: DimensionSource
    /// The root `<title>`, trimmed and whitespace-collapsed; nil when absent.
    let title: String?
    /// Distinct concrete paint values (lowercased, sorted).
    let paintColors: [String]
    /// Gradients, patterns, embedded rasters or `url(#…)` paint.
    let hasComplexPaint: Bool

    /// SF-0804-002: one concrete paint (or none) and no paint servers.
    var isRecolorCompatible: Bool { !hasComplexPaint && paintColors.count <= 1 }
    var removedPartCount: Int { removedElementCount + removedAttributeCount }
}

struct SanitizedSVG: Equatable, Sendable {
    let data: Data
    let report: SVGSanitizationReport
}

/// SF-0804 (OD-045): SVG is imported as a sanitized image asset and rendered
/// as an image. Scripts, `foreignObject`, animation, external references,
/// event attributes, entity declarations, comments and processing
/// instructions are removed or rejected. The output is a canonical
/// re-serialization (sorted attributes, fixed namespaces), so
/// `sanitize(sanitize(x).data).data == sanitize(x).data` and export can verify
/// stored bytes exactly instead of trusting a hand-edited package.
enum SVGAssetSanitizer {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0804-%03d", $0) })
    static let maximumDepth = 128
    static let maximumElementCount = 50_000
    static let maximumTitleCharacters = 256
    static let defaultPixelWidth = 300
    static let defaultPixelHeight = 150
    static let svgNamespace = "http://www.w3.org/2000/svg"
    static let xlinkNamespace = "http://www.w3.org/1999/xlink"

    /// Kept with their safe attributes and children. Anything else is removed
    /// together with its subtree (script, foreignObject, animate, set, feImage,
    /// iframe, metadata, editor namespaces…).
    static let allowedElements: Set<String> = [
        "svg", "g", "defs", "symbol", "use", "switch", "title", "desc", "style",
        "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
        "text", "tspan", "textPath", "image",
        "linearGradient", "radialGradient", "stop", "pattern", "clipPath", "mask", "marker",
        "filter", "feBlend", "feColorMatrix", "feComponentTransfer", "feComposite",
        "feConvolveMatrix", "feDiffuseLighting", "feDisplacementMap", "feDistantLight",
        "feDropShadow", "feFlood", "feFuncA", "feFuncB", "feFuncG", "feFuncR",
        "feGaussianBlur", "feMerge", "feMergeNode", "feMorphology", "feOffset",
        "fePointLight", "feSpecularLighting", "feSpotLight", "feTile", "feTurbulence",
    ]
    /// Removed, but their safe children are kept (a link loses its target).
    static let unwrappedElements: Set<String> = ["a"]
    /// Elements whose character data is kept.
    static let textElements: Set<String> = ["title", "desc", "style", "text", "tspan", "textPath"]
    static let paintProperties: Set<String> = ["fill", "stroke", "color", "stop-color", "flood-color", "lighting-color"]
    static let neutralPaints: Set<String> = [
        "none", "transparent", "currentcolor", "inherit", "initial", "unset", "context-fill", "context-stroke",
    ]
    private static let allowedPrefixedAttributes: Set<String> = ["xlink:href", "xlink:title", "xml:space", "xml:lang"]
    private static let blockedAttributes: Set<String> = [
        "src", "srcset", "action", "formaction", "ping", "background", "dynsrc", "lowsrc", "xml:base",
    ]
    private static let unsafeMarkers = ["javascript:", "vbscript:", "expression(", "@import", "-moz-binding", "behavior:"]
    private static let embeddedRasterPrefixes = [
        "data:image/png;base64,", "data:image/jpeg;base64,", "data:image/gif;base64,", "data:image/webp;base64,",
    ]
    private static let paintDeclarationPattern =
        #"(?i)(?:^|[;{\s])((?:fill|stroke|color|stop-color|flood-color|lighting-color)\s*:\s*)([^;{}!]+)"#

    /// Routing only (import and preview): the first non-whitespace byte is
    /// `<` and an `<svg` tag appears in the first kilobyte. `sanitize`
    /// decides validity.
    static func looksLikeSVG(_ data: Data) -> Bool {
        var prefix = data.prefix(1_024)
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) { prefix = prefix.dropFirst(3) }
        guard let first = prefix.first(where: { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }),
              first == UInt8(ascii: "<") else { return false }
        return String(decoding: prefix, as: UTF8.self).lowercased().contains("<svg")
    }

    static func sanitize(_ data: Data) throws -> SanitizedSVG {
        let parsed = try parse(data)
        let output = Data(serialize(parsed.root).utf8)
        guard output.count <= ProjectResourceIndex.maximumResourceBytes else { throw ImageImportError.tooLarge }
        return SanitizedSVG(data: output, report: try report(for: parsed))
    }

    /// Export gate: stored SVG bytes must already be the canonical sanitized
    /// form. Anything else (for example a hand-edited package) fails closed.
    static func isCanonicalSanitized(_ data: Data) -> Bool {
        (try? sanitize(data))?.data == data
    }

    /// `#RGB`, `#RRGGBB`, with or without `#`, case-insensitive → `#rrggbb`.
    static func normalizedHexColor(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 3 || text.count == 6, text.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        return "#" + text
    }

    /// SF-0804-002: rewrites every concrete paint and `currentColor` to one
    /// color and gives the root a fill when it has none. Incompatible icons
    /// (gradients, patterns, embedded rasters, several colors) are refused.
    static func recolor(_ data: Data, to rawColor: String) throws -> SanitizedSVG {
        guard let color = normalizedHexColor(rawColor) else { throw ImageImportError.unsupportedSVG }
        let parsed = try parse(data)
        guard try report(for: parsed).isRecolorCompatible else { throw ImageImportError.unsupportedSVG }
        recolor(parsed.root, color: color)
        if !parsed.root.attributes.contains(where: { $0.name == "fill" }) {
            parsed.root.attributes.append((name: "fill", value: color))
        }
        return try sanitize(Data(serialize(parsed.root).utf8))
    }

    enum AccessibleNameSource: String, Equatable, Sendable { case decorative, imageAltText, svgTitle, missing }

    /// SF-0804-003: an Image's own alternative text always wins; the SVG's
    /// root title is only a fallback suggestion; decorative Images expose no
    /// name at all.
    static func accessibleName(altText: String, isDecorative: Bool,
                               svgTitle: String?) -> (name: String, source: AccessibleNameSource) {
        if isDecorative { return ("", .decorative) }
        let authored = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authored.isEmpty { return (authored, .imageAltText) }
        if let svgTitle, !svgTitle.isEmpty { return (svgTitle, .svgTitle) }
        return ("", .missing)
    }

    /// SF-0804-003 (lane V08): the Image Inspector's sentence for the rule
    /// `accessibleName` picks. Names no text, so it is safe in diagnostics.
    static func accessibleNameExplanation(altText: String, isDecorative: Bool, svgTitle: String?) -> String {
        switch accessibleName(altText: altText, isDecorative: isDecorative, svgTitle: svgTitle).source {
        case .decorative:
            "Decorative: assistive technology skips this Image, so the SVG's title is not used."
        case .imageAltText:
            "Named by this Image's alternative text, which always wins over the SVG's title."
        case .svgTitle:
            "No alternative text yet. The SVG's title is only a suggestion and is not written to the website; add alternative text or mark the Image decorative."
        case .missing:
            "No alternative text, and the SVG has no title. Add alternative text or mark the Image decorative."
        }
    }

    /// SF-0804-008: content-free evidence (no bytes, names or paths).
    static func diagnosticSummary(_ report: SVGSanitizationReport, assetID: AssetID) -> String {
        let token = DiagnosticStableIdentifier.sanitize(assetID.description, domain: .document, kind: "asset")
        return "SF-0804-004 svg-sanitize \(token) removed-elements=\(report.removedElementCount) "
            + "removed-attributes=\(report.removedAttributeCount) dimensions=\(report.dimensionSource.rawValue) "
            + "recolor=\(report.isRecolorCompatible ? "compatible" : "incompatible")"
    }

    /// Returns the value to keep, or nil to remove the attribute.
    static func safeAttributeValue(name: String, value: String, element: String) -> String? {
        let lower = name.lowercased()
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_.:-]*$", options: .regularExpression) != nil,
              !lower.hasPrefix("on"), !blockedAttributes.contains(lower) else { return nil }
        if name.contains(":"), !allowedPrefixedAttributes.contains(name) { return nil }
        let compact = compacted(value)
        for marker in unsafeMarkers where compact.contains(marker) { return nil }
        if lower == "href" || lower == "xlink:href" {
            if value.hasPrefix("#") { return value }
            if element == "image", embeddedRasterPrefixes.contains(where: { compact.hasPrefix($0) }) { return value }
            return nil
        }
        if lower == "style" { return safeStyleAttribute(value) }
        return hasOnlyFragmentURLs(compact) ? value : nil
    }

    /// Keeps only safe declarations; nil when none remain.
    static func safeStyleAttribute(_ value: String) -> String? {
        let declarations = value.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isSafeStyleSheet($0) }
        return declarations.isEmpty ? nil : declarations.joined(separator: "; ")
    }

    static func isSafeStyleSheet(_ css: String) -> Bool {
        let compact = compacted(css)
        return !(unsafeMarkers + ["\\", "</"]).contains(where: { compact.contains($0) }) && hasOnlyFragmentURLs(compact)
    }

    /// Every `url(` must point inside the document (`url(#id)`).
    static func hasOnlyFragmentURLs(_ compact: String) -> Bool {
        var rest = Substring(compact)
        while let range = rest.range(of: "url(") {
            var after = rest[range.upperBound...]
            if after.first == "\"" || after.first == "'" { after = after.dropFirst() }
            guard after.first == "#" else { return false }
            rest = after
        }
        return true
    }

    /// Lowercased, without whitespace or control characters, so `java script:`
    /// style obfuscation is caught.
    static func compacted(_ value: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in value.lowercased().unicodeScalars
        where !CharacterSet.whitespacesAndNewlines.contains(scalar) && !CharacterSet.controlCharacters.contains(scalar) {
            result.append(scalar)
        }
        return String(result)
    }

    fileprivate static func textContent(_ element: SVGSanitizerElement) -> String {
        var result = ""
        for case .text(let value) in element.children { result += value }
        return result
    }

    private static func parse(_ data: Data) throws -> SVGSanitizerParseResult {
        guard !data.isEmpty else { throw ImageImportError.corrupt }
        guard data.count <= ProjectResourceIndex.maximumResourceBytes else { throw ImageImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ImageImportError.corrupt }
        guard text.range(of: "<!entity", options: .caseInsensitive) == nil else { throw ImageImportError.unsupportedSVG }
        let delegate = SVGSanitizerParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let succeeded = parser.parse()
        if let failure = delegate.failure { throw failure }
        guard succeeded, let root = delegate.root else { throw ImageImportError.corrupt }
        return SVGSanitizerParseResult(root: root, removedElements: delegate.removedElements,
                                       removedAttributes: delegate.removedAttributes)
    }

    private static func report(for parsed: SVGSanitizerParseResult) throws -> SVGSanitizationReport {
        let root = parsed.root
        func attribute(_ name: String) -> String? { root.attributes.first { $0.name == name }?.value }
        let width = length(attribute("width")), height = length(attribute("height"))
        let viewBox = viewBoxSize(attribute("viewBox"))
        let resolved: (width: Double, height: Double, source: SVGSanitizationReport.DimensionSource)
        if let width, let height {
            resolved = (width, height, .attributes)
        } else if let viewBox {
            if let width {
                resolved = (width, width * viewBox.height / viewBox.width, .viewBox)
            } else if let height {
                resolved = (height * viewBox.width / viewBox.height, height, .viewBox)
            } else {
                resolved = (viewBox.width, viewBox.height, .viewBox)
            }
        } else {
            resolved = (width ?? Double(defaultPixelWidth), height ?? Double(defaultPixelHeight), .defaulted)
        }
        var colors = Set<String>()
        var complex = false
        collectPaint(root, colors: &colors, complex: &complex)
        return SVGSanitizationReport(
            removedElementCount: parsed.removedElements, removedAttributeCount: parsed.removedAttributes,
            pixelWidth: try pixels(resolved.width), pixelHeight: try pixels(resolved.height),
            dimensionSource: resolved.source, title: title(of: root),
            paintColors: colors.sorted(), hasComplexPaint: complex
        )
    }

    private static func length(_ value: String?) -> Double? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        if text.hasSuffix("px") { text.removeLast(2) }
        guard let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite, number > 0 else { return nil }
        return number
    }

    private static func viewBoxSize(_ value: String?) -> (width: Double, height: Double)? {
        guard let value else { return nil }
        let parts = value.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Double($0) }
        guard parts.count == 4, parts[2].isFinite, parts[3].isFinite, parts[2] > 0, parts[3] > 0 else { return nil }
        return (parts[2], parts[3])
    }

    private static func pixels(_ value: Double) throws -> Int {
        let rounded = value.rounded(.up)
        guard rounded.isFinite, rounded >= 1, rounded <= Double(ImageAsset.maximumPixelDimension) else {
            throw ImageImportError.invalidDimensions
        }
        return Int(rounded)
    }

    private static func title(of root: SVGSanitizerElement) -> String? {
        for case .element(let child) in root.children where child.name == "title" {
            let collapsed = textContent(child).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return collapsed.isEmpty ? nil : String(collapsed.prefix(maximumTitleCharacters))
        }
        return nil
    }

    private static func isConcretePaint(_ value: String) -> Bool {
        !value.isEmpty && !neutralPaints.contains(value) && !value.hasPrefix("url(")
    }

    private static func isRecolorablePaint(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "currentcolor" || isConcretePaint(value)
    }

    private static func classify(_ raw: String, colors: inout Set<String>, complex: inout Bool) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("url(") { complex = true } else if isConcretePaint(value) { colors.insert(value) }
    }

    private static func paintDeclarationValues(_ css: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: paintDeclarationPattern) else { return [] }
        let text = css as NSString
        return expression.matches(in: css, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range(at: 2)) }
    }

    private static func rewritePaintDeclarations(_ css: String, color: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: paintDeclarationPattern) else { return css }
        var text = css as NSString
        for match in expression.matches(in: css, range: NSRange(location: 0, length: text.length)).reversed() {
            let range = match.range(at: 2)
            guard isRecolorablePaint(text.substring(with: range)) else { continue }
            text = text.replacingCharacters(in: range, with: color) as NSString
        }
        return text as String
    }

    private static func collectPaint(_ element: SVGSanitizerElement, colors: inout Set<String>, complex: inout Bool) {
        if ["linearGradient", "radialGradient", "pattern", "image"].contains(element.name) { complex = true }
        for attribute in element.attributes {
            if paintProperties.contains(attribute.name) { classify(attribute.value, colors: &colors, complex: &complex) }
            if attribute.name == "style" {
                for value in paintDeclarationValues(attribute.value) { classify(value, colors: &colors, complex: &complex) }
            }
        }
        for child in element.children {
            switch child {
            case .element(let nested):
                collectPaint(nested, colors: &colors, complex: &complex)
            case .text(let text):
                guard element.name == "style" else { continue }
                for value in paintDeclarationValues(text) { classify(value, colors: &colors, complex: &complex) }
            }
        }
    }

    private static func recolor(_ element: SVGSanitizerElement, color: String) {
        element.attributes = element.attributes.map { attribute -> (name: String, value: String) in
            if paintProperties.contains(attribute.name), isRecolorablePaint(attribute.value) {
                return (name: attribute.name, value: color)
            }
            if attribute.name == "style" { return (name: "style", value: rewritePaintDeclarations(attribute.value, color: color)) }
            return attribute
        }
        element.children = element.children.map { child -> SVGSanitizerContent in
            switch child {
            case .element(let nested):
                recolor(nested, color: color)
                return child
            case .text(let text):
                return element.name == "style" ? .text(rewritePaintDeclarations(text, color: color)) : child
            }
        }
    }

    private static func serialize(_ root: SVGSanitizerElement) -> String {
        var output = ""
        append(root, isRoot: true, declaresXLink: usesXLink(root), to: &output)
        return output
    }

    private static func usesXLink(_ element: SVGSanitizerElement) -> Bool {
        if element.attributes.contains(where: { $0.name.hasPrefix("xlink:") }) { return true }
        for case .element(let nested) in element.children where usesXLink(nested) { return true }
        return false
    }

    private static func append(_ element: SVGSanitizerElement, isRoot: Bool, declaresXLink: Bool, to output: inout String) {
        output += "<" + element.name
        if isRoot {
            output += " xmlns=\"" + svgNamespace + "\""
            if declaresXLink { output += " xmlns:xlink=\"" + xlinkNamespace + "\"" }
        }
        for attribute in element.attributes {
            output += " " + attribute.name + "=\"" + escape(attribute.value, inAttribute: true) + "\""
        }
        guard !element.children.isEmpty else {
            output += "/>"
            return
        }
        output += ">"
        for child in element.children {
            switch child {
            case .element(let nested): append(nested, isRoot: false, declaresXLink: false, to: &output)
            case .text(let text): output += escape(text, inAttribute: false)
            }
        }
        output += "</" + element.name + ">"
    }

    private static func escape(_ value: String, inAttribute: Bool) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\r": result += "&#13;"
            case "\"" where inAttribute: result += "&quot;"
            case "\n" where inAttribute: result += "&#10;"
            case "\t" where inAttribute: result += "&#9;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

private final class SVGSanitizerElement {
    let name: String
    var attributes: [(name: String, value: String)]
    var children: [SVGSanitizerContent] = []

    init(name: String, attributes: [(name: String, value: String)]) {
        self.name = name
        self.attributes = attributes
    }
}

private enum SVGSanitizerContent {
    case element(SVGSanitizerElement)
    case text(String)
}

private struct SVGSanitizerParseResult {
    let root: SVGSanitizerElement
    let removedElements: Int
    let removedAttributes: Int
}

/// Builds the filtered tree while parsing; removed subtrees are never built.
private final class SVGSanitizerParserDelegate: NSObject, XMLParserDelegate {
    private enum Frame {
        case kept(SVGSanitizerElement)
        case unwrapped
        case skipped
    }

    private(set) var root: SVGSanitizerElement?
    private(set) var failure: ImageImportError?
    private(set) var removedElements = 0
    private(set) var removedAttributes = 0
    private var stack: [Frame] = []
    private var elementCount = 0

    private var isSkipping: Bool {
        if case .skipped? = stack.last { return true }
        return false
    }

    private var current: SVGSanitizerElement? {
        for frame in stack.reversed() {
            if case .kept(let element) = frame { return element }
        }
        return nil
    }

    private func fail(_ error: ImageImportError, _ parser: XMLParser) {
        if failure == nil { failure = error }
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard failure == nil else { return }
        elementCount += 1
        guard elementCount <= SVGAssetSanitizer.maximumElementCount,
              stack.count < SVGAssetSanitizer.maximumDepth else {
            fail(.corrupt, parser)
            return
        }
        if isSkipping {
            stack.append(.skipped)
            return
        }
        if stack.isEmpty, root != nil || elementName != "svg" {
            fail(.unsupportedSVG, parser)
            return
        }
        if !stack.isEmpty, SVGAssetSanitizer.unwrappedElements.contains(elementName) {
            removedElements += 1
            stack.append(.unwrapped)
            return
        }
        guard SVGAssetSanitizer.allowedElements.contains(elementName) else {
            removedElements += 1
            stack.append(.skipped)
            return
        }
        var attributes: [(name: String, value: String)] = []
        for name in attributeDict.keys.sorted() {
            // Namespace declarations are rewritten by the serializer.
            if name == "xmlns" || name.hasPrefix("xmlns:") { continue }
            if let value = SVGAssetSanitizer.safeAttributeValue(name: name, value: attributeDict[name] ?? "", element: elementName) {
                attributes.append((name: name, value: value))
            } else {
                removedAttributes += 1
            }
        }
        if elementName == "image", !attributes.contains(where: { $0.name == "href" || $0.name == "xlink:href" }) {
            removedElements += 1
            stack.append(.skipped)
            return
        }
        let element = SVGSanitizerElement(name: elementName, attributes: attributes)
        if let parent = current { parent.children.append(.element(element)) } else { root = element }
        stack.append(.kept(element))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard failure == nil, let frame = stack.popLast() else { return }
        // A style sheet is judged once its whole text is known.
        guard case .kept(let element) = frame, element.name == "style",
              !SVGAssetSanitizer.isSafeStyleSheet(SVGAssetSanitizer.textContent(element)) else { return }
        if let parent = current, case .element(let last)? = parent.children.last, last === element {
            parent.children.removeLast()
            removedElements += 1
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        fail(.unsupportedSVG, parser)
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        fail(.unsupportedSVG, parser)
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        nil
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = .corrupt }
    }

    private func appendText(_ string: String) {
        guard failure == nil, !isSkipping, let element = current,
              SVGAssetSanitizer.textElements.contains(element.name) else { return }
        if case .text(let previous)? = element.children.last {
            element.children[element.children.count - 1] = .text(previous + string)
        } else {
            element.children.append(.text(string))
        }
    }
}

// SF-1206 v1: portable output names derive from verified content, never a
// Finder path or user-provided filename. Callers supply package-owned bytes.
enum StaticAssetExportError: Error, Equatable, Sendable { case unsupported, corrupt, oversized }

struct StaticAssetExportEntry: Equatable, Sendable {
    let resourceID: ResourceID
    let outputPath: String
    let sha256: String
}

enum StaticAssetExportPlanner {
    static func plan(index: ProjectResourceIndex, blobs: [String: Data]) throws -> [StaticAssetExportEntry] {
        try index.resources.map { resource in
            let svgType = ImageAssetFormat.svg.mediaType
            let fontTypes = Set(FontAssetFormat.allCases.map(\.mediaType))
            let mediaTypes = Set(MediaAssetFormat.allCases.map(\.mediaType))
            guard resource.mediaType == "image/png" || resource.mediaType == "image/jpeg" || resource.mediaType == svgType
                    || fontTypes.contains(resource.mediaType) || mediaTypes.contains(resource.mediaType) else { throw StaticAssetExportError.unsupported }
            // SF-1206-004 (ADR-0121): over the per-file limit is oversized, not unsupported.
            guard resource.byteCount >= 0 else { throw StaticAssetExportError.corrupt }
            guard resource.byteCount <= ProjectResourceIndex.maximumResourceBytes else { throw StaticAssetExportError.oversized }
            guard let bytes = blobs[resource.sha256], bytes.count == resource.byteCount,
                  ProjectResourceStore.digest(bytes) == resource.sha256 else { throw StaticAssetExportError.corrupt }
            // SF-0804: SVG output must be the canonical sanitized form, so a
            // hand-edited package cannot smuggle script into the website.
            if resource.mediaType == svgType, !SVGAssetSanitizer.isCanonicalSanitized(bytes) {
                throw StaticAssetExportError.corrupt
            }
            // SF-0805: font output must carry its declared format's signature.
            if fontTypes.contains(resource.mediaType),
               ProjectFontFormatSniffer.format(of: bytes)?.mediaType != resource.mediaType {
                throw StaticAssetExportError.corrupt
            }
            // SF-0803: media output must carry its declared format's signature.
            if mediaTypes.contains(resource.mediaType),
               ProjectMediaFormatSniffer.format(of: bytes, fileExtension: (resource.filename as NSString).pathExtension)?.mediaType
                != resource.mediaType {
                throw StaticAssetExportError.corrupt
            }
            let ext = switch resource.mediaType {
            case "image/png": "png"
            case "image/jpeg": "jpg"
            case "font/woff2": "woff2"
            case "font/ttf": "ttf"
            case "video/mp4": "mp4"
            case "video/webm": "webm"
            case "audio/mpeg": "mp3"
            case "audio/mp4": "m4a"
            case "audio/ogg": "ogg"
            case "audio/wav": "wav"
            case "text/vtt": "vtt"
            default: "svg"
            }
            return .init(resourceID: resource.id, outputPath: "assets/\(resource.sha256).\(ext)", sha256: resource.sha256)
        }.sorted { $0.outputPath < $1.outputPath }
    }
}

// SF-0801/SF-0802 static-output v1: canonical assets resolve only through a
// verified content-addressed export plan; filenames and local paths are never
// output identifiers.
enum StaticImageOutputReferencePlanner {
    static func path(for asset: ImageAsset, entries: [StaticAssetExportEntry]) throws -> String {
        try asset.validate()
        guard let entry = entries.first(where: { $0.resourceID == asset.resourceID }),
              entry.sha256 == asset.contentHash else { throw StaticAssetExportError.corrupt }
        return entry.outputPath
    }
}

/// SF-1206 static-output v1: an immutable, content-free manifest makes the
/// verified resource references in a build plan inspectable without carrying
/// bytes, filenames, Finder paths, or an output write operation.
/// SF-1206-001 (ADR-0124): one line per exported asset of every type, in
/// asset-identity order: `<asset id>\t<output path>\t<detail>`, where the detail
/// is the pixel size for images (SVG and video posters included) and the media
/// type for fonts, video, audio and captions. Names never appear.
enum StaticAssetManifestEmitter {
    static func emit(assets: [ImageAsset], entries: [StaticAssetExportEntry],
                     fonts: [FontAsset] = [], fontPaths: [AssetID: String] = [:],
                     media: [MediaAsset] = [], mediaPaths: [AssetID: String] = [:]) -> String {
        let images = assets.compactMap { asset -> (id: String, line: String)? in
            guard let path = try? StaticImageOutputReferencePlanner.path(for: asset, entries: entries),
                  (1...ImageAsset.maximumPixelDimension).contains(asset.pixelWidth),
                  (1...ImageAsset.maximumPixelDimension).contains(asset.pixelHeight) else {
                return nil
            }
            return (id: asset.id.description, line: "\(asset.id.description)\t\(path)\t\(asset.pixelWidth)x\(asset.pixelHeight)")
        }
        // Only exported files have a path: faces with declared web rights
        // (`ProjectFontOutput.exportedPaths`) and media an output page plays.
        let faces = fonts.compactMap { font -> (id: String, line: String)? in
            guard let path = fontPaths[font.id] else { return nil }
            return (id: font.id.description, line: "\(font.id.description)\t\(path)\t\(font.format.mediaType)")
        }
        let files = media.compactMap { asset -> (id: String, line: String)? in
            guard let path = mediaPaths[asset.id] else { return nil }
            return (id: asset.id.description, line: "\(asset.id.description)\t\(path)\t\(asset.format.mediaType)")
        }
        return (images + faces + files).sorted { ($0.id, $0.line) < ($1.id, $1.line) }
            .map { $0.line }
            .joined(separator: "\n")
    }
}

enum ProjectResourceError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedIndexVersion(Int)
    case duplicateResource
    case malformedMetadata
    case capacityExceeded
    case corruptIndex
    case missingBlob
    case corruptBlob
    case unsafeStore
    case ioFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedIndexVersion: "This project uses an unsupported resource-index version."
        case .duplicateResource: "The project resource index contains a duplicate stable identity."
        case .malformedMetadata: "The project resource metadata is malformed."
        case .capacityExceeded: "The project resources exceed the versioned capacity policy."
        case .corruptIndex: "The project resource index is corrupt."
        case .missingBlob: "A declared project resource is missing. Locate a complete project copy."
        case .corruptBlob: "A project resource failed its integrity check. Restore a valid copy."
        case .unsafeStore: "The resource store has unsafe ownership or link metadata."
        case .ioFailure: "A project resource could not be read or written."
        }
    }
}

enum ProjectResourceIOPhase: Sendable {
    case storeDescriptorBound
}

struct ProjectResourceIOObserver: Sendable {
    let didReach: @Sendable (ProjectResourceIOPhase) -> Void

    init(didReach: @escaping @Sendable (ProjectResourceIOPhase) -> Void = { _ in }) {
        self.didReach = didReach
    }
}

actor ProjectResourceStore {
    static let requirementIDs: Set<String> = [
        "SF-0303-001", "SF-0303-008", "SF-1702-008", "SF-2002-008",
    ]

    let root: URL
    private let cancellation: CooperativeCancellationCheckpoint
    private let ioObserver: ProjectResourceIOObserver
    private let bundledResourceRoot: URL?
    private let isBundledReadOnly: Bool

    init(
        root: URL,
        cancellation: CooperativeCancellationCheckpoint = CooperativeCancellationCheckpoint(),
        ioObserver: ProjectResourceIOObserver = ProjectResourceIOObserver()
    ) {
        self.root = root
        self.cancellation = cancellation
        self.ioObserver = ioObserver
        bundledResourceRoot = nil
        isBundledReadOnly = false
    }

    /// Bundled examples are public readable assets, not a writable private
    /// store. Descriptor binding/hash checks remain shared; this mode cannot
    /// create a directory, add a blob, or read outside its supplied bundle.
    init(bundledRoot root: URL, bundle: Bundle) {
        self.root = root
        cancellation = CooperativeCancellationCheckpoint()
        ioObserver = ProjectResourceIOObserver()
        bundledResourceRoot = bundle.resourceURL?.resolvingSymlinksInPath()
        isBundledReadOnly = true
    }

    static func sidecarURL(for packageURL: URL) -> URL {
        packageURL.appendingPathExtension("resources-v1")
    }

    func put(
        id: ResourceID = ResourceID(),
        filename: String,
        mediaType: String,
        data: Data
    ) throws -> ProjectResourceDescriptor {
        guard !isBundledReadOnly else { throw ProjectResourceError.unsafeStore }
        let digest = Self.digest(data)
        let descriptor = ProjectResourceDescriptor(
            id: id,
            filename: filename,
            mediaType: mediaType,
            byteCount: data.count,
            sha256: digest
        )
        try ProjectResourceIndex(resources: [descriptor]).validate()
        let storeDescriptor = try openStore()
        defer { Darwin.close(storeDescriptor) }
        try cancellation.check()
        let destinationName = blobName(for: digest)
        var destinationInformation = stat()
        if Darwin.fstatat(
            storeDescriptor,
            destinationName,
            &destinationInformation,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            try validateBlob(descriptor, storeDescriptor: storeDescriptor)
            return descriptor
        }
        guard errno == ENOENT else { throw ProjectResourceError.unsafeStore }

        let temporaryName = ".stage-\(UUID().uuidString.lowercased())"
        let temporaryDescriptor = Darwin.openat(
            storeDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard temporaryDescriptor >= 0 else { throw ProjectResourceError.ioFailure }
        var temporaryIsOpen = true
        defer {
            if temporaryIsOpen { Darwin.close(temporaryDescriptor) }
            _ = Darwin.unlinkat(storeDescriptor, temporaryName, 0)
        }
        do {
            guard Darwin.fchmod(temporaryDescriptor, mode_t(0o600)) == 0,
                  try !Self.hasExtendedACL(temporaryDescriptor) else {
                throw ProjectResourceError.unsafeStore
            }
            try Self.writeAll(data, to: temporaryDescriptor)
            guard Darwin.fsync(temporaryDescriptor) == 0 else { throw ProjectResourceError.ioFailure }
            try cancellation.check()
            if Darwin.linkat(storeDescriptor, temporaryName, storeDescriptor, destinationName, 0) != 0 {
                if errno == EEXIST {
                    try validateBlob(descriptor, storeDescriptor: storeDescriptor)
                } else {
                    throw ProjectResourceError.ioFailure
                }
            } else {
                guard Darwin.fsync(storeDescriptor) == 0 else { throw ProjectResourceError.ioFailure }
            }
            Darwin.close(temporaryDescriptor)
            temporaryIsOpen = false
            return descriptor
        } catch let error as ProjectResourceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectResourceError.ioFailure
        }
    }

    func validate(_ index: ProjectResourceIndex) throws {
        try index.validate()
        let storeDescriptor = try openStore()
        defer { Darwin.close(storeDescriptor) }
        for resource in index.resources {
            try cancellation.check()
            try validateBlob(resource, storeDescriptor: storeDescriptor)
        }
    }

    func data(for resource: ProjectResourceDescriptor) throws -> Data {
        let storeDescriptor = try openStore()
        defer { Darwin.close(storeDescriptor) }
        let descriptor = try openBlob(resource, storeDescriptor: storeDescriptor)
        defer { Darwin.close(descriptor) }
        var result = Data()
        result.reserveCapacity(resource.byteCount)
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            try cancellation.check()
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw ProjectResourceError.ioFailure }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        guard result.count == resource.byteCount, Self.digest(result) == resource.sha256 else {
            throw ProjectResourceError.corruptBlob
        }
        return result
    }

    private func openStore() throws -> Int32 {
        if isBundledReadOnly {
            guard let bundledResourceRoot,
                  root.resolvingSymlinksInPath().path.hasPrefix(bundledResourceRoot.path + "/") else {
                throw ProjectResourceError.unsafeStore
            }
        }
        var info = stat()
        if lstat(root.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR,
                  safeResourcePermissions(info) else {
                throw ProjectResourceError.unsafeStore
            }
        } else {
            guard !isBundledReadOnly else { throw ProjectResourceError.missingBlob }
            guard errno == ENOENT else { throw ProjectResourceError.ioFailure }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            } catch {
                throw ProjectResourceError.ioFailure
            }
        }
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProjectResourceError.unsafeStore }
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              safeResourcePermissions(info),
              try !Self.hasExtendedACL(descriptor) else {
            Darwin.close(descriptor)
            throw ProjectResourceError.unsafeStore
        }
        ioObserver.didReach(.storeDescriptorBound)
        return descriptor
    }

    private func safeResourcePermissions(_ info: stat, blob: Bool = false) -> Bool {
        if isBundledReadOnly {
            return (info.st_uid == geteuid() || info.st_uid == 0) && (info.st_mode & 0o022) == 0
        }
        return info.st_uid == (blob ? getuid() : geteuid()) && (info.st_mode & 0o077) == 0
    }

    private func blobName(for digest: String) -> String {
        "\(digest).blob"
    }

    private func validateBlob(
        _ resource: ProjectResourceDescriptor,
        storeDescriptor: Int32
    ) throws {
        let descriptor = try openBlob(resource, storeDescriptor: storeDescriptor)
        defer { Darwin.close(descriptor) }
        var hasher = SHA256()
        var remaining = resource.byteCount
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while remaining > 0 {
            try cancellation.check()
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, remaining))
            guard count > 0 else { throw ProjectResourceError.corruptBlob }
            hasher.update(data: Data(buffer[0..<count]))
            remaining -= count
        }
        var extra: UInt8 = 0
        guard Darwin.read(descriptor, &extra, 1) == 0,
              hasher.finalize().map({ String(format: "%02x", $0) }).joined() == resource.sha256 else {
            throw ProjectResourceError.corruptBlob
        }
    }

    private func openBlob(
        _ resource: ProjectResourceDescriptor,
        storeDescriptor: Int32
    ) throws -> Int32 {
        let descriptor = Darwin.openat(
            storeDescriptor,
            blobName(for: resource.sha256),
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw errno == ENOENT ? ProjectResourceError.missingBlob : ProjectResourceError.unsafeStore
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              safeResourcePermissions(info, blob: true),
              info.st_nlink == 1,
              info.st_size == resource.byteCount,
              info.st_size <= ProjectResourceIndex.maximumResourceBytes,
              try !Self.hasExtendedACL(descriptor) else {
            Darwin.close(descriptor)
            throw ProjectResourceError.unsafeStore
        }
        return descriptor
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ProjectResourceError.ioFailure }
                offset += count
            }
        }
    }

    private static func hasExtendedACL(_ descriptor: Int32) throws -> Bool {
        errno = 0
        guard let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT || errno == ENOTSUP || errno == EOPNOTSUPP { return false }
            throw ProjectResourceError.unsafeStore
        }
        Darwin.acl_free(UnsafeMutableRawPointer(acl))
        return true
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension ProjectPackage {
    static func isTransientResourceBlobPath(_ path: String) -> Bool {
        path.hasPrefix("resources/blobs/") && path.hasSuffix(".blob")
    }

    var archiveOptionalMembers: [ProjectPackageMember] {
        optionalMembers.filter { !Self.isTransientResourceBlobPath($0.path) }
    }

    func withResourceIndex(_ index: ProjectResourceIndex) throws -> ProjectPackage {
        let member = try index.encodedMember()
        return ProjectPackage(
            projectID: projectID,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            document: document,
            optionalMembers: optionalMembers.filter { $0.path != ProjectResourceIndex.packageMemberPath } + [member],
            compatibility: compatibility
        )
    }

    func withResource(_ descriptor: ProjectResourceDescriptor, data: Data) throws -> ProjectPackage {
        guard descriptor.byteCount == data.count,
              descriptor.sha256 == ProjectResourceStore.digest(data) else {
            throw ProjectResourceError.corruptBlob
        }
        var resources = try ProjectResourceIndex.decode(from: self)?.resources ?? []
        resources.removeAll { $0.id == descriptor.id }
        resources.append(descriptor)
        let index = ProjectResourceIndex(resources: resources)
        let indexed = try withResourceIndex(index)
        let path = ProjectResourceIndex.blobMemberPath(for: descriptor.sha256)
        let blob = ProjectPackageMember(path: path, role: .resource, data: data)
        return ProjectPackage(
            projectID: indexed.projectID,
            createdAt: indexed.createdAt,
            modifiedAt: indexed.modifiedAt,
            document: indexed.document,
            optionalMembers: indexed.optionalMembers.filter { $0.path != path } + [blob],
            compatibility: indexed.compatibility
        )
    }

    func resourceData(for descriptor: ProjectResourceDescriptor) throws -> Data {
        let path = ProjectResourceIndex.blobMemberPath(for: descriptor.sha256)
        guard let member = optionalMembers.first(where: { $0.path == path }) else {
            throw ProjectResourceError.missingBlob
        }
        guard member.role == .resource,
              member.data.count == descriptor.byteCount,
              ProjectResourceStore.digest(member.data) == descriptor.sha256 else {
            throw ProjectResourceError.corruptBlob
        }
        return member.data
    }

    func attachingResourceData(_ resources: [ResourceID: Data]) throws -> ProjectPackage {
        guard let index = try ProjectResourceIndex.decode(from: self) else { return self }
        var members = archiveOptionalMembers
        for descriptor in index.resources {
            guard let data = resources[descriptor.id] else { continue }
            guard data.count == descriptor.byteCount,
                  ProjectResourceStore.digest(data) == descriptor.sha256 else {
                throw ProjectResourceError.corruptBlob
            }
            members.append(.init(
                path: ProjectResourceIndex.blobMemberPath(for: descriptor.sha256),
                role: .resource,
                data: data
            ))
        }
        return ProjectPackage(
            projectID: projectID, createdAt: createdAt, modifiedAt: modifiedAt,
            document: document, optionalMembers: members, compatibility: compatibility
        )
    }
}

/// SF-0802-004/008: both generation and output verify the actual local bytes.
/// Production callers perform this bounded decode on their build/resource actor.
enum ProjectQRCodeVerifier {
    enum Failure: Error { case payloadMismatch }
    static func verify(_ bytes: Data, payload: String) throws {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        try VNImageRequestHandler(data: bytes).perform([request])
        guard request.results?.contains(where: { $0.payloadStringValue == payload }) == true else { throw Failure.payloadMismatch }
    }
}
