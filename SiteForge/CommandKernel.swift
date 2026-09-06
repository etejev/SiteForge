import Foundation

// SF-0303: authoring policy is stricter than historical decoding. Old page
// routes retain their intent; new edits use this one normalized static domain.
enum StaticPagePolicy {
    static func name(_ draft: String) throws -> String {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 256,
              value.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw PageAuthoringError.invalidName
        }
        return value
    }

    static func route(_ draft: String) throws -> PageRoute {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let segments = value.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        guard value.first == "/", value.utf8.count <= 1024, value != "/", value != "/404",
              !segments.isEmpty, segments.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            throw PageAuthoringError.invalidRoute
        }
        return PageRoute(rawValue: value)
    }

    static func uniqueRoute(stem: String, in document: CanonicalDocument) -> String {
        let existing = Set(document.pages.map { $0.route.rawValue.lowercased() })
        var suffix = 1
        var candidate = stem
        while existing.contains(candidate) {
            suffix += 1
            candidate = "\(stem)-\(suffix)"
        }
        return candidate
    }

    static func duplicateName(_ source: String) throws -> String {
        var prefix = ""
        for character in source {
            let next = prefix + String(character)
            guard next.utf8.count <= 251 else { break }
            prefix = next
        }
        return try name((prefix.isEmpty ? "Page" : prefix) + " Copy")
    }
}

enum PageAuthoringError: Error, LocalizedError {
    case invalidName, invalidRoute, collision, protectedPage, stale, unavailable, cancelled, unchanged
    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a page name of 1–256 UTF-8 bytes without control characters."
        case .invalidRoute: "Use /about or /about/team with letters, digits, hyphens or underscores. / and /404 are protected."
        case .collision: "Another page already uses this route. Choose a unique path."
        case .protectedPage: "Home and Not Found cannot be deleted or assigned another route."
        case .stale: "The page context changed. Reopen this action and try again."
        case .unavailable: "Page editing is unavailable while the document is read-only or being replaced."
        case .cancelled: "Page edit cancelled. The document is unchanged."
        case .unchanged: "The page already has this value."
        }
    }
}

struct PageEditIdentity: Equatable {
    let documentID: DocumentID
    let revision: UInt64
    let pageID: PageID
}

enum PageEdit {
    case create(name: String, route: String)
    case rename(String)
    case route(String)
    case duplicate
    case delete
    case move(Int)

    var commandName: CommandName {
        switch self {
        case .create, .duplicate: .insertPage
        case .rename: .renamePage
        case .route: .setPageRoute
        case .delete: .removePage
        case .move: .movePage
        }
    }
}

struct PreparedPageEdit {
    let command: DocumentCommand
    let selectedPageID: PageID
}

struct PageCommandRegistry {
    func prepare(_ edit: PageEdit, identity: PageEditIdentity, in document: CanonicalDocument,
                 isAvailable: Bool, cancelled: Bool = false) throws -> PreparedPageEdit {
        guard !cancelled else { throw PageAuthoringError.cancelled }
        guard isAvailable else { throw PageAuthoringError.unavailable }
        guard identity.documentID == document.id, identity.revision == document.revision,
              document.revision < UInt64.max,
              let index = document.pageIndex(for: identity.pageID) else { throw PageAuthoringError.stale }
        let page = document.pages[index]
        func validatedRoute(_ draft: String) throws -> PageRoute {
            let route = try StaticPagePolicy.route(draft)
            guard !document.pages.contains(where: { $0.id != page.id && $0.route.rawValue.lowercased() == route.rawValue }) else {
                throw PageAuthoringError.collision
            }
            return route
        }
        switch edit {
        case .create(let name, let rawRoute):
            let route = try StaticPagePolicy.route(rawRoute)
            guard !document.pages.contains(where: { $0.route.rawValue.lowercased() == route.rawValue }) else {
                throw PageAuthoringError.collision
            }
            let created = DocumentPage.minimum(name: try StaticPagePolicy.name(name), route: route.rawValue,
                                               role: .standard, provenance: .authored)
            return .init(command: .insertPage(.init(page: created, index: document.pages.count)), selectedPageID: created.id)
        case .rename(let draft):
            let name = try StaticPagePolicy.name(draft)
            guard name != page.name else { throw PageAuthoringError.unchanged }
            return .init(command: .renamePage(.init(pageID: page.id, name: name)), selectedPageID: page.id)
        case .route(let draft):
            guard page.role == .standard else { throw PageAuthoringError.protectedPage }
            let route = try validatedRoute(draft)
            guard route != page.route else { throw PageAuthoringError.unchanged }
            return .init(command: .setPageRoute(.init(pageID: page.id, route: route)), selectedPageID: page.id)
        case .move(let destination):
            guard document.pages.indices.contains(destination) else { throw PageAuthoringError.stale }
            guard destination != index else { throw PageAuthoringError.unchanged }
            return .init(command: .movePage(.init(pageID: page.id, index: destination)), selectedPageID: page.id)
        case .delete:
            guard page.role == .standard else { throw PageAuthoringError.protectedPage }
            // Guides are page-owned canonical data; remove them in the same
            // transaction so inverse insertion restores their exact ordering.
            let guides = document.guides.filter { $0.pageID == page.id }
            let commands = guides.map { DocumentCommand.removeGuide(.init(guideID: $0.id)) }
                + [.removePage(.init(pageID: page.id))]
            let destination = document.pages.first { $0.id != page.id }?.id
            guard let destination else { throw PageAuthoringError.protectedPage }
            return .init(command: .batch(commands), selectedPageID: destination)
        case .duplicate:
            let newID = PageID()
            let ids = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, NodeID()) })
            let nodes = page.nodes.map { node in
                let parent: NodeParent = switch node.parent {
                case .page: .page(newID)
                case .node(let id): .node(ids[id]!)
                }
                let properties = node.properties.map { property in
                    var value = property.value
                    if property.key.rawValue == CanonicalLinkTarget.namespace + "pageID",
                       value == .string(page.id.description) { value = .string(newID.description) }
                    if property.key.rawValue == CanonicalLinkTarget.namespace + "nodeID",
                       node.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == page.id.description,
                       case .string(let raw) = value, let old = NodeID(uuidString: raw), let replacement = ids[old] {
                        value = .string(replacement.description)
                    }
                    return NodeProperty(key: property.key, value: value, origin: property.origin)
                }
                return DocumentNode(id: ids[node.id]!, kind: node.kind, name: node.name,
                                    parent: parent, childIDs: node.childIDs.map { ids[$0]! }, properties: properties)
            }
            let copy = DocumentPage(id: newID, name: try StaticPagePolicy.duplicateName(page.name),
                route: .init(rawValue: StaticPagePolicy.uniqueRoute(stem: "/page-copy", in: document)),
                role: .standard, provenance: .authored,
                rootNodeIDs: page.rootNodeIDs.map { ids[$0]! }, nodes: nodes)
            let guides = document.guides.filter { $0.pageID == page.id }.enumerated().map { offset, guide in
                DocumentCommand.insertGuide(.init(guide: .init(pageID: newID, axis: guide.axis,
                    position: guide.position, provenance: guide.provenance), index: document.guides.count + offset))
            }
            return .init(command: .batch([.insertPage(.init(page: copy, index: index + 1))] + guides), selectedPageID: newID)
        }
    }

    func inboundLinkCount(to pageID: PageID, in document: CanonicalDocument) -> Int {
        document.pages.filter { $0.id != pageID }.flatMap(\.nodes).filter {
            $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == pageID.description
        }.count
    }
}

enum CommandName: String, CaseIterable, Codable, Sendable {
    case insertPage = "document.page.insert"
    case removePage = "document.page.remove"
    case renamePage = "document.page.rename"
    case setPageRoute = "document.page.route.set"
    case movePage = "document.page.move"
    case insertNode = "document.node.insert"
    case removeNode = "document.node.remove"
    case moveNode = "document.node.move"
    case setProperty = "document.property.set"
    case removeProperty = "document.property.remove"
    case insertGuide = "document.guide.insert"
    case setGuidePosition = "document.guide.position.set"
    case removeGuide = "document.guide.remove"
    case insertImageAsset = "document.asset.image.insert"
    case updateImageAsset = "document.asset.image.update"
    case removeImageAsset = "document.asset.image.remove"
    case batch = "document.batch"
    case undo = "history.undo"
    case redo = "history.redo"
}

struct CommandDescriptor: Equatable {
    let name: CommandName
    let title: String
    let mutatesDocument: Bool
}

enum CommandAvailability: Equatable {
    case enabled
    case disabled(reason: String)

    var isEnabled: Bool {
        self == .enabled
    }

    var disabledReason: String? {
        guard case .disabled(let reason) = self else { return nil }
        return reason
    }
}

struct InsertPageCommand: Codable, Equatable, Sendable {
    let page: DocumentPage
    let index: Int
}

struct RemovePageCommand: Codable, Equatable, Sendable {
    let pageID: PageID
}

struct RenamePageCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let name: String
}

struct SetPageRouteCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let route: PageRoute
}

/// The destination is the final index, after removal of the source page.
struct MovePageCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let index: Int
}

struct InsertNodeCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let node: DocumentNode
    let index: Int
}

struct RemoveNodeCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let nodeID: NodeID
}

/// Moves an existing node without duplicating its identity or subtree. `index` is
/// interpreted against the destination collection before same-parent removal.
struct MoveNodeCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let nodeID: NodeID
    let destination: NodeParent
    let index: Int
}

struct SetPropertyCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let nodeID: NodeID
    let property: NodeProperty
    let insertionIndex: Int?

    init(
        pageID: PageID,
        nodeID: NodeID,
        property: NodeProperty,
        insertionIndex: Int? = nil
    ) {
        self.pageID = pageID
        self.nodeID = nodeID
        self.property = property
        self.insertionIndex = insertionIndex
    }
}

struct RemovePropertyCommand: Codable, Equatable, Sendable {
    let pageID: PageID
    let nodeID: NodeID
    let propertyID: PropertyID
}

struct InsertGuideCommand: Codable, Equatable, Sendable {
    let guide: AuthoredGuide
    let index: Int
}

struct SetGuidePositionCommand: Codable, Equatable, Sendable {
    let guideID: GuideID
    let position: Double
}

struct RemoveGuideCommand: Codable, Equatable, Sendable {
    let guideID: GuideID
}

struct InsertImageAssetCommand: Codable, Equatable, Sendable {
    let asset: ImageAsset
    let index: Int
}

struct UpdateImageAssetCommand: Codable, Equatable, Sendable {
    let asset: ImageAsset
}

struct RemoveImageAssetCommand: Codable, Equatable, Sendable {
    let assetID: AssetID
}

indirect enum DocumentCommand: Codable, Equatable, Sendable {
    case insertPage(InsertPageCommand)
    case removePage(RemovePageCommand)
    case renamePage(RenamePageCommand)
    case setPageRoute(SetPageRouteCommand)
    case movePage(MovePageCommand)
    case insertNode(InsertNodeCommand)
    case removeNode(RemoveNodeCommand)
    case moveNode(MoveNodeCommand)
    case setProperty(SetPropertyCommand)
    case removeProperty(RemovePropertyCommand)
    case insertGuide(InsertGuideCommand)
    case setGuidePosition(SetGuidePositionCommand)
    case removeGuide(RemoveGuideCommand)
    case insertImageAsset(InsertImageAssetCommand)
    case updateImageAsset(UpdateImageAssetCommand)
    case removeImageAsset(RemoveImageAssetCommand)
    case batch([DocumentCommand])

    var name: CommandName {
        switch self {
        case .insertPage: .insertPage
        case .removePage: .removePage
        case .renamePage: .renamePage
        case .setPageRoute: .setPageRoute
        case .movePage: .movePage
        case .insertNode: .insertNode
        case .removeNode: .removeNode
        case .moveNode: .moveNode
        case .setProperty: .setProperty
        case .removeProperty: .removeProperty
        case .insertGuide: .insertGuide
        case .setGuidePosition: .setGuidePosition
        case .removeGuide: .removeGuide
        case .insertImageAsset: .insertImageAsset
        case .updateImageAsset: .updateImageAsset
        case .removeImageAsset: .removeImageAsset
        case .batch: .batch
        }
    }

    var targets: [CommandTarget] {
        return switch self {
        case .insertPage(let command):
            [command.page.id.commandTarget]
        case .removePage(let command):
            [command.pageID.commandTarget]
        case .renamePage(let command):
            [command.pageID.commandTarget]
        case .setPageRoute(let command):
            [command.pageID.commandTarget]
        case .movePage(let command):
            [command.pageID.commandTarget]
        case .insertNode(let command):
            [command.pageID.commandTarget, command.node.id.commandTarget]
        case .removeNode(let command):
            [command.pageID.commandTarget, command.nodeID.commandTarget]
        case .moveNode(let command):
            switch command.destination {
            case .page: [command.pageID.commandTarget, command.nodeID.commandTarget]
            case .node(let parentID): [command.pageID.commandTarget, command.nodeID.commandTarget, parentID.commandTarget]
            }
        case .setProperty(let command):
            [
                command.pageID.commandTarget,
                command.nodeID.commandTarget,
                command.property.id.commandTarget,
            ]
        case .removeProperty(let command):
            [
                command.pageID.commandTarget,
                command.nodeID.commandTarget,
                command.propertyID.commandTarget,
            ]
        case .insertGuide(let command):
            [command.guide.pageID.commandTarget, command.guide.id.commandTarget]
        case .setGuidePosition(let command):
            [command.guideID.commandTarget]
        case .removeGuide(let command):
            [command.guideID.commandTarget]
        case .insertImageAsset(let command):
            [command.asset.id.commandTarget]
        case .updateImageAsset(let command):
            [command.asset.id.commandTarget]
        case .removeImageAsset(let command):
            [command.assetID.commandTarget]
        case .batch(let commands):
            commands.flatMap(\.targets)
        }
    }
}

struct CommandTarget: Codable, Hashable, Sendable {
    let namespace: String
    let rawValue: UUID
}

private extension StableIdentifier {
    var commandTarget: CommandTarget {
        CommandTarget(namespace: Domain.diagnosticNamespace, rawValue: rawValue)
    }
}

struct CommandCancellation: Sendable {
    let isCancelled: @Sendable () -> Bool

    static let never = CommandCancellation(isCancelled: { false })
}

enum CommandExecutionError: Error, Equatable, LocalizedError {
    case disabled(String)
    case cancelled
    case revisionExhausted
    case invalidResult(ModelValidationError)

    var errorDescription: String? {
        switch self {
        case .disabled(let reason): reason
        case .cancelled: "The command was cancelled before it committed."
        case .revisionExhausted: "The document revision cannot accept another transaction. Keep this file unchanged and open a compatible earlier project version."
        case .invalidResult(let error): "The command produced an invalid document: \(error.localizedDescription)"
        }
    }
}

struct CommandMutation: Equatable {
    let inverse: DocumentCommand
}

struct CommandRegistry {
    let descriptors: [CommandName: CommandDescriptor]

    init() {
        let values = [
            CommandDescriptor(name: .insertPage, title: "Insert Page", mutatesDocument: true),
            CommandDescriptor(name: .removePage, title: "Remove Page", mutatesDocument: true),
            CommandDescriptor(name: .renamePage, title: "Rename Page", mutatesDocument: true),
            CommandDescriptor(name: .setPageRoute, title: "Edit Page Route", mutatesDocument: true),
            CommandDescriptor(name: .movePage, title: "Move Page", mutatesDocument: true),
            CommandDescriptor(name: .insertNode, title: "Insert Node", mutatesDocument: true),
            CommandDescriptor(name: .removeNode, title: "Remove Node", mutatesDocument: true),
            CommandDescriptor(name: .moveNode, title: "Move Node", mutatesDocument: true),
            CommandDescriptor(name: .setProperty, title: "Set Property", mutatesDocument: true),
            CommandDescriptor(name: .removeProperty, title: "Remove Property", mutatesDocument: true),
            CommandDescriptor(name: .insertGuide, title: "Add Guide", mutatesDocument: true),
            CommandDescriptor(name: .setGuidePosition, title: "Move Guide", mutatesDocument: true),
            CommandDescriptor(name: .removeGuide, title: "Remove Guide", mutatesDocument: true),
            CommandDescriptor(name: .insertImageAsset, title: "Import Image", mutatesDocument: true),
            CommandDescriptor(name: .updateImageAsset, title: "Edit Image Asset", mutatesDocument: true),
            CommandDescriptor(name: .removeImageAsset, title: "Delete Image Asset", mutatesDocument: true),
            CommandDescriptor(name: .batch, title: "Grouped Edit", mutatesDocument: true),
            CommandDescriptor(name: .undo, title: "Undo", mutatesDocument: true),
            CommandDescriptor(name: .redo, title: "Redo", mutatesDocument: true),
        ]
        descriptors = Dictionary(uniqueKeysWithValues: values.map { ($0.name, $0) })
    }

    func descriptor(for name: CommandName) -> CommandDescriptor {
        // The exhaustive registry is constructed from every CommandName case.
        descriptors[name]!
    }

    func availability(for command: DocumentCommand, in document: CanonicalDocument) -> CommandAvailability {
        switch command {
        case .insertPage(let value):
            guard (0...document.pages.count).contains(value.index) else {
                return .disabled(reason: "The page insertion position is no longer valid.")
            }
            guard !document.pages.contains(where: { $0.id == value.page.id }) else {
                return .disabled(reason: "A page with this stable identifier already exists.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .removePage(let value):
            guard document.pageIndex(for: value.pageID) != nil else {
                return .disabled(reason: "The page no longer exists.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .renamePage(let value):
            guard document.pageIndex(for: value.pageID) != nil else {
                return .disabled(reason: "The page no longer exists.")
            }
            guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .disabled(reason: "Page names cannot be empty.")
            }
            return .enabled

        case .setPageRoute(let value):
            guard let page = document.pages.first(where: { $0.id == value.pageID }),
                  page.role == .standard else {
                return .disabled(reason: "Home and Not Found routes are protected.")
            }
            // Authoring normalization belongs to PageCommandRegistry. The
            // inverse must also restore valid historical route spellings.
            return validationAvailability(afterApplying: command, to: document)

        case .movePage(let value):
            guard document.pageIndex(for: value.pageID) != nil,
                  document.pages.indices.contains(value.index) else {
                return .disabled(reason: "The page or destination no longer exists.")
            }
            return .enabled

        case .insertNode(let value):
            guard let pageIndex = document.pageIndex(for: value.pageID) else {
                return .disabled(reason: "The owning page no longer exists.")
            }
            let page = document.pages[pageIndex]
            guard !document.pages.flatMap(\.nodes).contains(where: { $0.id == value.node.id }) else {
                return .disabled(reason: "A node with this stable identifier already exists.")
            }
            let childCount: Int
            switch value.node.parent {
            case .page(let pageID):
                guard pageID == value.pageID else {
                    return .disabled(reason: "The node must be owned by its target page.")
                }
                childCount = page.rootNodeIDs.count
            case .node(let parentID):
                guard let parent = page.nodes.first(where: { $0.id == parentID }) else {
                    return .disabled(reason: "The parent node no longer exists on this page.")
                }
                childCount = parent.childIDs.count
            }
            guard (0...childCount).contains(value.index) else {
                return .disabled(reason: "The node insertion position is no longer valid.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .removeNode(let value):
            guard let node = document.node(pageID: value.pageID, nodeID: value.nodeID) else {
                return .disabled(reason: "The node no longer exists on this page.")
            }
            guard node.childIDs.isEmpty else {
                return .disabled(reason: "Remove child nodes before removing their parent.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .moveNode(let value):
            guard let pageIndex = document.pageIndex(for: value.pageID),
                  let source = document.node(pageID: value.pageID, nodeID: value.nodeID) else {
                return .disabled(reason: "The moved node no longer exists on this page.")
            }
            let page = document.pages[pageIndex]
            let count: Int
            switch value.destination {
            case .page(let pageID):
                guard pageID == value.pageID else { return .disabled(reason: "A node cannot move across pages.") }
                count = page.rootNodeIDs.count
            case .node(let parentID):
                guard let parent = page.nodes.first(where: { $0.id == parentID }) else {
                    return .disabled(reason: "The destination container no longer exists on this page.")
                }
                guard parent.kind.acceptsAuthoredChildren else { return .disabled(reason: "Only authored containers accept nested nodes.") }
                guard parentID != source.id, !isDescendant(parentID, of: source.id, in: page) else {
                    return .disabled(reason: "A node cannot be moved into itself or its descendant.")
                }
                count = parent.childIDs.count
            }
            guard (0...count).contains(value.index) else { return .disabled(reason: "The destination insertion position is no longer valid.") }
            return validationAvailability(afterApplying: command, to: document)

        case .setProperty(let value):
            guard let node = document.node(pageID: value.pageID, nodeID: value.nodeID) else {
                return .disabled(reason: "The property owner no longer exists on this page.")
            }
            if let conflicting = node.properties.first(where: {
                $0.key == value.property.key && $0.id != value.property.id
            }) {
                _ = conflicting
                return .disabled(reason: "This node already owns a different property with that key.")
            }
            guard !value.property.key.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .disabled(reason: "Property keys cannot be empty.")
            }
            if let insertionIndex = value.insertionIndex,
               !(0...node.properties.count).contains(insertionIndex) {
                return .disabled(reason: "The property insertion position is no longer valid.")
            }
            return .enabled

        case .removeProperty(let value):
            guard let node = document.node(pageID: value.pageID, nodeID: value.nodeID) else {
                return .disabled(reason: "The property owner no longer exists on this page.")
            }
            guard node.properties.contains(where: { $0.id == value.propertyID }) else {
                return .disabled(reason: "The property no longer exists.")
            }
            return .enabled

        case .insertGuide(let value):
            guard document.pages.contains(where: { $0.id == value.guide.pageID }) else {
                return .disabled(reason: "The guide's owning page no longer exists.")
            }
            guard !document.guides.contains(where: { $0.id == value.guide.id }) else {
                return .disabled(reason: "A guide with this stable identifier already exists.")
            }
            guard (0...document.guides.count).contains(value.index) else {
                return .disabled(reason: "The guide insertion position is no longer valid.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .setGuidePosition(let value):
            guard document.guides.contains(where: { $0.id == value.guideID }) else {
                return .disabled(reason: "The guide no longer exists.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .removeGuide(let value):
            guard document.guides.contains(where: { $0.id == value.guideID }) else {
                return .disabled(reason: "The guide no longer exists.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .insertImageAsset(let value):
            guard (0...document.imageAssets.count).contains(value.index) else {
                return .disabled(reason: "The asset insertion position is no longer valid.")
            }
            guard !document.imageAssets.contains(where: { $0.id == value.asset.id }) else {
                return .disabled(reason: "An image asset with this stable identity already exists.")
            }
            guard !document.imageAssets.contains(where: { $0.contentHash == value.asset.contentHash }) else {
                return .disabled(reason: "These image bytes are already imported.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .updateImageAsset(let value):
            guard document.imageAssets.contains(where: { $0.id == value.asset.id }) else {
                return .disabled(reason: "The image asset no longer exists.")
            }
            guard !document.imageAssets.contains(where: {
                $0.id != value.asset.id && $0.contentHash == value.asset.contentHash
            }) else {
                return .disabled(reason: "These image bytes already belong to another asset.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .removeImageAsset(let value):
            guard document.imageAssets.contains(where: { $0.id == value.assetID }) else {
                return .disabled(reason: "The image asset no longer exists.")
            }
            let reference = value.assetID.description
            guard !document.pages.flatMap(\.nodes).contains(where: {
                $0.insertionStringProperty(CanonicalImageStyle.namespace + "assetID") == reference
            }) else {
                return .disabled(reason: "Detach or remove every Image using this asset before deleting it.")
            }
            return validationAvailability(afterApplying: command, to: document)

        case .batch(let commands):
            guard !commands.isEmpty else {
                return .disabled(reason: "A grouped edit must contain at least one command.")
            }
            var draft = document
            do {
                for nestedCommand in commands {
                    _ = try mutate(nestedCommand, document: &draft, cancellation: .never)
                }
                try draft.validate()
            } catch let error as ModelValidationError {
                return .disabled(reason: error.localizedDescription)
            } catch let error as CommandExecutionError {
                return .disabled(reason: error.localizedDescription)
            } catch {
                return .disabled(reason: "The grouped edit could not be validated.")
            }
            return .enabled
        }
    }

    func historyAvailability(for name: CommandName, canUndo: Bool, canRedo: Bool) -> CommandAvailability {
        switch name {
        case .undo:
            canUndo ? .enabled : .disabled(reason: "There are no document changes to undo.")
        case .redo:
            canRedo ? .enabled : .disabled(reason: "There are no document changes to redo.")
        default:
            .disabled(reason: "This is not a history command.")
        }
    }

    func apply(
        _ command: DocumentCommand,
        to document: inout CanonicalDocument,
        cancellation: CommandCancellation = .never
    ) throws -> CommandMutation {
        let availability = availability(for: command, in: document)
        guard availability.isEnabled else {
            throw CommandExecutionError.disabled(
                availability.disabledReason ?? "The command is unavailable."
            )
        }
        return try mutate(command, document: &document, cancellation: cancellation)
    }

    private func validationAvailability(
        afterApplying command: DocumentCommand,
        to document: CanonicalDocument
    ) -> CommandAvailability {
        var draft = document
        do {
            _ = try mutate(command, document: &draft, cancellation: .never)
            try draft.validate()
            return .enabled
        } catch let error as ModelValidationError {
            return .disabled(reason: error.localizedDescription)
        } catch {
            return .disabled(reason: "The command would produce an invalid document.")
        }
    }

    private func mutate(
        _ command: DocumentCommand,
        document: inout CanonicalDocument,
        cancellation: CommandCancellation
    ) throws -> CommandMutation {
        guard !cancellation.isCancelled() else { throw CommandExecutionError.cancelled }

        switch command {
        case .insertPage(let value):
            document.pages.insert(value.page, at: value.index)
            return CommandMutation(inverse: .removePage(RemovePageCommand(pageID: value.page.id)))

        case .removePage(let value):
            guard let index = document.pageIndex(for: value.pageID) else {
                throw CommandExecutionError.disabled("The page no longer exists.")
            }
            let page = document.pages.remove(at: index)
            return CommandMutation(inverse: .insertPage(InsertPageCommand(page: page, index: index)))

        case .renamePage(let value):
            guard let index = document.pageIndex(for: value.pageID) else {
                throw CommandExecutionError.disabled("The page no longer exists.")
            }
            let previousName = document.pages[index].name
            document.pages[index].name = value.name
            return CommandMutation(
                inverse: .renamePage(RenamePageCommand(pageID: value.pageID, name: previousName))
            )

        case .setPageRoute(let value):
            guard let index = document.pageIndex(for: value.pageID) else {
                throw CommandExecutionError.disabled("The page no longer exists.")
            }
            let previous = document.pages[index].route
            document.pages[index].route = value.route
            return CommandMutation(inverse: .setPageRoute(.init(pageID: value.pageID, route: previous)))

        case .movePage(let value):
            guard let index = document.pageIndex(for: value.pageID) else {
                throw CommandExecutionError.disabled("The page no longer exists.")
            }
            let page = document.pages.remove(at: index)
            document.pages.insert(page, at: value.index)
            return CommandMutation(inverse: .movePage(.init(pageID: value.pageID, index: index)))

        case .insertNode(let value):
            guard let pageIndex = document.pageIndex(for: value.pageID) else {
                throw CommandExecutionError.disabled("The owning page no longer exists.")
            }
            document.pages[pageIndex].nodes.append(value.node)
            switch value.node.parent {
            case .page:
                document.pages[pageIndex].rootNodeIDs.insert(value.node.id, at: value.index)
            case .node(let parentID):
                guard let parentIndex = document.pages[pageIndex].nodes.firstIndex(where: {
                    $0.id == parentID
                }) else {
                    throw CommandExecutionError.disabled("The parent node no longer exists.")
                }
                document.pages[pageIndex].nodes[parentIndex].childIDs.insert(value.node.id, at: value.index)
            }
            return CommandMutation(
                inverse: .removeNode(RemoveNodeCommand(pageID: value.pageID, nodeID: value.node.id))
            )

        case .removeNode(let value):
            guard let location = document.nodeLocation(pageID: value.pageID, nodeID: value.nodeID) else {
                throw CommandExecutionError.disabled("The node no longer exists.")
            }
            let node = document.pages[location.page].nodes[location.node]
            guard node.childIDs.isEmpty else {
                throw CommandExecutionError.disabled("Remove child nodes before removing their parent.")
            }
            let index: Int
            switch node.parent {
            case .page:
                guard let value = document.pages[location.page].rootNodeIDs.firstIndex(of: node.id) else {
                    throw CommandExecutionError.disabled("The page no longer owns this node.")
                }
                index = value
                document.pages[location.page].rootNodeIDs.remove(at: value)
            case .node(let parentID):
                guard let parentIndex = document.pages[location.page].nodes.firstIndex(where: { $0.id == parentID }),
                      let value = document.pages[location.page].nodes[parentIndex].childIDs.firstIndex(of: node.id) else {
                    throw CommandExecutionError.disabled("The parent no longer owns this node.")
                }
                index = value
                document.pages[location.page].nodes[parentIndex].childIDs.remove(at: value)
            }
            document.pages[location.page].nodes.remove(at: location.node)
            return CommandMutation(
                inverse: .insertNode(InsertNodeCommand(pageID: value.pageID, node: node, index: index))
            )

        case .moveNode(let value):
            guard let location = document.nodeLocation(pageID: value.pageID, nodeID: value.nodeID) else {
                throw CommandExecutionError.disabled("The moved node no longer exists.")
            }
            let sourceParent = document.pages[location.page].nodes[location.node].parent
            let sourceIndex = try removeNodeReference(value.nodeID, parent: sourceParent, from: &document.pages[location.page])
            var adjustedIndex = value.index
            if sourceParent == value.destination, sourceIndex < adjustedIndex { adjustedIndex -= 1 }
            try insertNodeReference(value.nodeID, parent: value.destination, at: adjustedIndex, into: &document.pages[location.page])
            document.pages[location.page].nodes[location.node].parent = value.destination
            // `MoveNodeCommand.index` is interpreted before removal. When the node
            // moved backwards within one collection, undo must compensate for its
            // current earlier position before restoring the original later index.
            let inverseIndex = sourceParent == value.destination && sourceIndex > value.index
                ? sourceIndex + 1
                : sourceIndex
            return CommandMutation(inverse: .moveNode(MoveNodeCommand(
                pageID: value.pageID, nodeID: value.nodeID, destination: sourceParent, index: inverseIndex
            )))

        case .setProperty(let value):
            guard let location = document.nodeLocation(pageID: value.pageID, nodeID: value.nodeID) else {
                throw CommandExecutionError.disabled("The property owner no longer exists.")
            }
            let properties = document.pages[location.page].nodes[location.node].properties
            if let propertyIndex = properties.firstIndex(where: { $0.id == value.property.id }) {
                let previous = properties[propertyIndex]
                document.pages[location.page].nodes[location.node].properties[propertyIndex] = value.property
                return CommandMutation(
                    inverse: .setProperty(
                        SetPropertyCommand(
                            pageID: value.pageID,
                            nodeID: value.nodeID,
                            property: previous
                        )
                    )
                )
            }
            let insertionIndex = value.insertionIndex ?? properties.count
            document.pages[location.page].nodes[location.node].properties.insert(
                value.property,
                at: insertionIndex
            )
            return CommandMutation(
                inverse: .removeProperty(
                    RemovePropertyCommand(
                        pageID: value.pageID,
                        nodeID: value.nodeID,
                        propertyID: value.property.id
                    )
                )
            )

        case .removeProperty(let value):
            guard let location = document.nodeLocation(pageID: value.pageID, nodeID: value.nodeID),
                  let propertyIndex = document.pages[location.page].nodes[location.node].properties.firstIndex(
                    where: { $0.id == value.propertyID }
                  ) else {
                throw CommandExecutionError.disabled("The property no longer exists.")
            }
            let property = document.pages[location.page].nodes[location.node].properties.remove(
                at: propertyIndex
            )
            return CommandMutation(
                inverse: .setProperty(
                    SetPropertyCommand(
                        pageID: value.pageID,
                        nodeID: value.nodeID,
                        property: property,
                        insertionIndex: propertyIndex
                    )
                )
            )

        case .insertGuide(let value):
            document.guides.insert(value.guide, at: value.index)
            return CommandMutation(
                inverse: .removeGuide(RemoveGuideCommand(guideID: value.guide.id))
            )

        case .setGuidePosition(let value):
            guard let index = document.guides.firstIndex(where: { $0.id == value.guideID }) else {
                throw CommandExecutionError.disabled("The guide no longer exists.")
            }
            let previous = document.guides[index].position
            document.guides[index].position = value.position
            return CommandMutation(
                inverse: .setGuidePosition(
                    SetGuidePositionCommand(guideID: value.guideID, position: previous)
                )
            )

        case .removeGuide(let value):
            guard let index = document.guides.firstIndex(where: { $0.id == value.guideID }) else {
                throw CommandExecutionError.disabled("The guide no longer exists.")
            }
            let guide = document.guides.remove(at: index)
            return CommandMutation(
                inverse: .insertGuide(InsertGuideCommand(guide: guide, index: index))
            )

        case .insertImageAsset(let value):
            document.imageAssets.insert(value.asset, at: value.index)
            return CommandMutation(inverse: .removeImageAsset(.init(assetID: value.asset.id)))

        case .updateImageAsset(let value):
            guard let index = document.imageAssets.firstIndex(where: { $0.id == value.asset.id }) else {
                throw CommandExecutionError.disabled("The image asset no longer exists.")
            }
            let previous = document.imageAssets[index]
            document.imageAssets[index] = value.asset
            return CommandMutation(inverse: .updateImageAsset(.init(asset: previous)))

        case .removeImageAsset(let value):
            guard let index = document.imageAssets.firstIndex(where: { $0.id == value.assetID }) else {
                throw CommandExecutionError.disabled("The image asset no longer exists.")
            }
            let asset = document.imageAssets.remove(at: index)
            return CommandMutation(inverse: .insertImageAsset(.init(asset: asset, index: index)))

        case .batch(let commands):
            var inverses: [DocumentCommand] = []
            for nestedCommand in commands {
                guard !cancellation.isCancelled() else { throw CommandExecutionError.cancelled }
                let mutation = try mutate(
                    nestedCommand,
                    document: &document,
                    cancellation: cancellation
                )
                inverses.append(mutation.inverse)
            }
            return CommandMutation(inverse: .batch(inverses.reversed()))
        }
    }

    private func isDescendant(_ candidate: NodeID, of ancestor: NodeID, in page: DocumentPage) -> Bool {
        guard let root = page.nodes.first(where: { $0.id == ancestor }) else { return false }
        var pending = root.childIDs
        var visited = Set<NodeID>()
        while let id = pending.popLast() {
            guard visited.insert(id).inserted else { return true }
            if id == candidate { return true }
            pending.append(contentsOf: page.nodes.first(where: { $0.id == id })?.childIDs ?? [])
        }
        return false
    }

    private func removeNodeReference(_ nodeID: NodeID, parent: NodeParent, from page: inout DocumentPage) throws -> Int {
        switch parent {
        case .page:
            guard let index = page.rootNodeIDs.firstIndex(of: nodeID) else { throw CommandExecutionError.disabled("The page no longer owns this node.") }
            page.rootNodeIDs.remove(at: index); return index
        case .node(let parentID):
            guard let parentIndex = page.nodes.firstIndex(where: { $0.id == parentID }),
                  let index = page.nodes[parentIndex].childIDs.firstIndex(of: nodeID) else { throw CommandExecutionError.disabled("The parent no longer owns this node.") }
            page.nodes[parentIndex].childIDs.remove(at: index); return index
        }
    }

    private func insertNodeReference(_ nodeID: NodeID, parent: NodeParent, at index: Int, into page: inout DocumentPage) throws {
        switch parent {
        case .page:
            guard (0...page.rootNodeIDs.count).contains(index) else { throw CommandExecutionError.disabled("The destination insertion position is no longer valid.") }
            page.rootNodeIDs.insert(nodeID, at: index)
        case .node(let parentID):
            guard let parentIndex = page.nodes.firstIndex(where: { $0.id == parentID }),
                  (0...page.nodes[parentIndex].childIDs.count).contains(index) else { throw CommandExecutionError.disabled("The destination insertion position is no longer valid.") }
            page.nodes[parentIndex].childIDs.insert(nodeID, at: index)
        }
    }
}

private extension CanonicalDocument {
    func pageIndex(for pageID: PageID) -> Int? {
        pages.firstIndex(where: { $0.id == pageID })
    }

    func node(pageID: PageID, nodeID: NodeID) -> DocumentNode? {
        guard let pageIndex = pageIndex(for: pageID) else { return nil }
        return pages[pageIndex].nodes.first(where: { $0.id == nodeID })
    }

    func nodeLocation(pageID: PageID, nodeID: NodeID) -> (page: Int, node: Int)? {
        guard let pageIndex = pageIndex(for: pageID),
              let nodeIndex = pages[pageIndex].nodes.firstIndex(where: { $0.id == nodeID }) else {
            return nil
        }
        return (pageIndex, nodeIndex)
    }
}

enum DiagnosticResult: String, Equatable {
    case success
    case failure
    case cancelled
}

enum DiagnosticFailureCategory: String, Equatable, Sendable {
    case validation
    case cancellation
    case modelInvariant
}

struct CommandDiagnosticRecord: Equatable, Sendable {
    let requirementIDs: [String]
    let commandName: CommandName
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let result: DiagnosticResult
    let failureCategory: DiagnosticFailureCategory?
}

final class CommandDiagnostics {
    private var buffer: BoundedDiagnosticBuffer<CommandDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    var records: [CommandDiagnosticRecord] { buffer.snapshot() }
    var droppedRecordCount: UInt64 { buffer.droppedRecordCount }

    func recordPagePreparationFailure(_ edit: PageEdit, pageID: PageID, durationMilliseconds: Double) {
        record(commandName: edit.commandName, targets: [pageID.commandTarget],
               durationMilliseconds: durationMilliseconds, result: .failure, failureCategory: .validation)
    }

    fileprivate func record(
        commandName: CommandName,
        targets: [CommandTarget],
        durationMilliseconds: Double,
        result: DiagnosticResult,
        failureCategory: DiagnosticFailureCategory?
    ) {
        buffer.append(
            CommandDiagnosticRecord(
                requirementIDs: ["SF-0203-008", "SF-0306-008", "SF-1607-008"]
                    + ([CommandName.insertPage, .removePage, .renamePage, .setPageRoute, .movePage].contains(commandName)
                        ? ["SF-0303-008"] : []),
                commandName: commandName,
                sanitizedIdentifiers: targets.map(sanitize),
                durationMilliseconds: max(0, durationMilliseconds),
                result: result,
                failureCategory: failureCategory
            )
        )
    }

    private func sanitize(_ target: CommandTarget) -> String {
        DiagnosticStableIdentifier.sanitize(
            "\(target.namespace):\(target.rawValue)",
            domain: .command,
            kind: target.namespace
        )
    }
}

struct HistoryEntry: Codable, Equatable, Sendable {
    let id: TransactionID
    let parentRevision: UInt64
    let resultRevision: UInt64
    let commandName: CommandName
    let label: String
    let timestamp: ProjectTimestamp
    let affectedIdentifiers: [CommandTarget]
    let forward: DocumentCommand
    let inverse: DocumentCommand
}

@MainActor
final class DocumentSession: ObservableObject {
    static let requirementIDs: Set<String> = [
        "SF-0203-001", "SF-0203-004", "SF-0203-005", "SF-0203-006", "SF-0203-008",
        "SF-0302-001", "SF-0302-004", "SF-0302-005", "SF-0302-008",
        "SF-0303-001", "SF-0304-001", "SF-0304-004", "SF-0305-001",
        "SF-0306-001", "SF-0306-004", "SF-0306-005", "SF-0306-008",
        "SF-0307-001", "SF-0307-004", "SF-0307-005", "SF-0307-006", "SF-0307-008",
        "SF-1607-008", "SF-1702-001", "SF-1702-004", "SF-1702-008",
        "SF-1902-001", "SF-1902-004", "SF-1902-005", "SF-1902-006", "SF-1902-008",
    ]

    @Published private(set) var document: CanonicalDocument
    @Published private(set) var lastError: CommandExecutionError?
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private(set) var historyBoundaryRevision: UInt64

    let registry: CommandRegistry
    let diagnostics: CommandDiagnostics

    init(
        document: CanonicalDocument = CanonicalDocument(),
        registry: CommandRegistry = CommandRegistry(),
        diagnostics: CommandDiagnostics = CommandDiagnostics()
    ) {
        self.document = document
        self.registry = registry
        self.diagnostics = diagnostics
        historyBoundaryRevision = document.revision
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var nextUndoLabel: String? { undoStack.last?.label }
    var nextRedoLabel: String? { redoStack.last?.label }

    var undoAvailability: CommandAvailability {
        registry.historyAvailability(for: .undo, canUndo: canUndo, canRedo: canRedo)
    }

    var redoAvailability: CommandAvailability {
        registry.historyAvailability(for: .redo, canUndo: canUndo, canRedo: canRedo)
    }

    /// Establishes a validated lifecycle boundary. Persisted history is intentionally
    /// not imported until SF-FOUNDATION-006 defines its package representation.
    func establishBaseline(_ baseline: CanonicalDocument, boundaryRevision: UInt64? = nil) throws {
        try baseline.validate()
        document = baseline
        undoStack.removeAll()
        redoStack.removeAll()
        historyBoundaryRevision = boundaryRevision ?? baseline.revision
        lastError = nil
    }

    @discardableResult
    func execute(
        _ command: DocumentCommand,
        cancellation: CommandCancellation = .never
    ) throws -> CanonicalDocument {
        let parentRevision = document.revision
        let mutation = try commit(command, diagnosticName: command.name, cancellation: cancellation)
        undoStack.append(HistoryEntry(
            id: TransactionID(), parentRevision: parentRevision, resultRevision: document.revision,
            commandName: command.name, label: registry.descriptor(for: command.name).title,
            timestamp: ProjectTimestamp(date: Date()), affectedIdentifiers: command.targets,
            forward: command, inverse: mutation.inverse
        ))
        redoStack.removeAll()
        return document
    }

    func undo() throws {
        guard let entry = undoStack.last else {
            throw CommandExecutionError.disabled(
                undoAvailability.disabledReason ?? "Undo is unavailable."
            )
        }
        _ = try commit(entry.inverse, diagnosticName: .undo, cancellation: .never)
        undoStack.removeLast()
        redoStack.append(entry)
    }

    func redo() throws {
        guard let entry = redoStack.last else {
            throw CommandExecutionError.disabled(
                redoAvailability.disabledReason ?? "Redo is unavailable."
            )
        }
        _ = try commit(entry.forward, diagnosticName: .redo, cancellation: .never)
        redoStack.removeLast()
        undoStack.append(entry)
    }

    func historySnapshot() -> PersistedHistorySnapshot {
        PersistedHistorySnapshot(
            documentID: document.id,
            documentRevision: document.revision,
            boundaryRevision: historyBoundaryRevision,
            undoEntries: undoStack,
            redoEntries: redoStack
        )
    }

    func installValidatedHistory(_ snapshot: PersistedHistorySnapshot) throws {
        guard snapshot.documentID == document.id,
              snapshot.documentRevision == document.revision,
              snapshot.boundaryRevision <= document.revision else {
            throw PersistedHistoryError.documentMismatch
        }
        undoStack = snapshot.undoEntries
        redoStack = snapshot.redoEntries
        historyBoundaryRevision = snapshot.boundaryRevision
        lastError = nil
        objectWillChange.send()
    }

    private func commit(
        _ command: DocumentCommand,
        diagnosticName: CommandName,
        cancellation: CommandCancellation
    ) throws -> CommandMutation {
        let start = DispatchTime.now().uptimeNanoseconds
        let committedDocument = document
        do {
            guard !cancellation.isCancelled() else { throw CommandExecutionError.cancelled }
            guard committedDocument.revision < UInt64.max - 1 else {
                throw CommandExecutionError.revisionExhausted
            }
            var draft = committedDocument
            let mutation = try registry.apply(command, to: &draft, cancellation: cancellation)
            guard !cancellation.isCancelled() else { throw CommandExecutionError.cancelled }
            let (nextRevision, overflow) = committedDocument.revision.addingReportingOverflow(1)
            guard !overflow, nextRevision < UInt64.max else {
                throw CommandExecutionError.revisionExhausted
            }
            draft.revision = nextRevision
            do {
                try draft.validate()
            } catch let error as ModelValidationError {
                throw CommandExecutionError.invalidResult(error)
            }
            document = draft
            lastError = nil
            recordDiagnostic(
                name: diagnosticName,
                command: command,
                start: start,
                result: .success,
                failureCategory: nil
            )
            return mutation
        } catch let error as CommandExecutionError {
            document = committedDocument
            lastError = error
            let result: DiagnosticResult = error == .cancelled ? .cancelled : .failure
            let category: DiagnosticFailureCategory
            switch error {
            case .cancelled: category = .cancellation
            case .disabled, .revisionExhausted: category = .validation
            case .invalidResult: category = .modelInvariant
            }
            recordDiagnostic(
                name: diagnosticName,
                command: command,
                start: start,
                result: result,
                failureCategory: category
            )
            throw error
        }
    }

    private func recordDiagnostic(
        name: CommandName,
        command: DocumentCommand,
        start: UInt64,
        result: DiagnosticResult,
        failureCategory: DiagnosticFailureCategory?
    ) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        diagnostics.record(
            commandName: name,
            targets: command.targets,
            durationMilliseconds: Double(elapsed) / 1_000_000,
            result: result,
            failureCategory: failureCategory
        )
    }
}
