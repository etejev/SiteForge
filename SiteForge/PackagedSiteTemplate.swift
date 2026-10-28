import Foundation

// SF-0204-002/004/005/006: packaged examples use the normal document and
// content-addressed resource readers, not a sample-specific renderer/model.
enum BundledSiteTemplates {
    static let auroraID = TemplateID(UUID(uuidString: "02040000-0000-4000-8000-000000000201")!)
    static func auroraURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "Aurora", withExtension: "siteforge", subdirectory: "AuroraTemplate")
    }
}

actor PackagedSiteTemplateLoader {
    func load(from url: URL, templateID: TemplateID, bundle: Bundle = .main) async throws -> ProjectPackage {
        let source = try await ProjectPackageStore().read(from: url)
        try Task.checkCancellation()
        let index = try ProjectResourceIndex.decode(from: source)
        guard originalResourcesAreIndexed(source.document, index: index) else { throw ProjectResourceError.corruptIndex }
        let root = ProjectResourceStore.sidecarURL(for: url)
        let inBundle = bundle.resourceURL.map {
            root.resolvingSymlinksInPath().path.hasPrefix($0.resolvingSymlinksInPath().path + "/")
        } ?? false
        let store = inBundle ? ProjectResourceStore(bundledRoot: root, bundle: bundle) : ProjectResourceStore(root: root)
        var resources: [ResourceID: Data] = [:]
        for descriptor in index?.resources ?? [] {
            try Task.checkCancellation()
            resources[descriptor.id] = try await store.data(for: descriptor)
        }
        // A fresh document/project qualifies every scene/command identity.
        // Internal IDs stay stable together so links, assets, tokens and all
        // typed references remain exact; no opaque authored strings are remapped.
        let original = source.document
        let document = CanonicalDocument(creationKind: .template, templateID: templateID,
            pages: original.pages.map { page in var copy = page; copy.provenance = .template; return copy },
            guides: original.guides, imageAssets: original.imageAssets,
            colorTokens: original.colorTokens, websiteMetadata: original.websiteMetadata)
        try document.validate()
        let package = try ProjectPackage(document: document,
            optionalMembers: source.optionalMembers.filter { $0.path == ProjectResourceIndex.packageMemberPath })
            .attachingResourceData(resources)
        try ProjectCreationResources.validate(document: document, members: package.optionalMembers)
        try Task.checkCancellation()
        return package
    }

    private func originalResourcesAreIndexed(_ document: CanonicalDocument, index: ProjectResourceIndex?) -> Bool {
        let ids = Set(index?.resources.map(\.id) ?? [])
        return document.imageAssets.allSatisfy { ids.contains($0.resourceID) }
    }
}

enum ProjectCreationResources {
    /// Called on the loader/backend actor before a lifecycle boundary. History
    /// and unrelated optional members cannot enter a new creation baseline.
    static func validate(document: CanonicalDocument, members: [ProjectPackageMember]) throws {
        guard !members.isEmpty else { return }
        guard Set(members.map(\.path)).count == members.count,
              members.allSatisfy({ $0.role == .resource && ($0.path == ProjectResourceIndex.packageMemberPath
                || ProjectPackage.isTransientResourceBlobPath($0.path)) }) else { throw ProjectResourceError.corruptIndex }
        let package = ProjectPackage(document: document, optionalMembers: members)
        guard let index = try ProjectResourceIndex.decode(from: package) else { throw ProjectResourceError.corruptIndex }
        let ids = Set(index.resources.map(\.id))
        guard document.imageAssets.allSatisfy({ ids.contains($0.resourceID) }) else { throw ProjectResourceError.missingBlob }
        let expectedPaths = Set(index.resources.map { ProjectResourceIndex.blobMemberPath(for: $0.sha256) })
            .union([ProjectResourceIndex.packageMemberPath])
        guard Set(members.map(\.path)) == expectedPaths else { throw ProjectResourceError.corruptIndex }
        for asset in document.imageAssets {
            guard let descriptor = index.resources.first(where: { $0.id == asset.resourceID }),
                  descriptor.sha256 == asset.contentHash, descriptor.byteCount == asset.byteCount else {
                throw ProjectResourceError.corruptBlob
            }
        }
        for descriptor in index.resources { _ = try package.resourceData(for: descriptor) }
    }
}
