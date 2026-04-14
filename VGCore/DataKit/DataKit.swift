//
//  DataKit.swift
//  VGCore
//
//  Created by Kalob Allen on 4/11/26.
//

import Foundation

// MARK: - Public Models

public enum NamespacedIDError: LocalizedError {
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidFormat(rawValue):
            return "Expected a namespaced id in the form namespace:name, got \(rawValue)."
        }
    }
}

public struct NamespacedID: Codable, Hashable, Sendable, ExpressibleByStringLiteral, Comparable {
    public let namespace: String
    public let name: String

    public var rawValue: String {
        "\(namespace):\(name)"
    }

    public init(namespace: String, name: String) {
        self.namespace = namespace
        self.name = name
    }

    public init(rawValue: String) throws {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw NamespacedIDError.invalidFormat(rawValue)
        }

        self.namespace = parts[0]
        self.name = parts[1]
    }

    public init(stringLiteral value: String) {
        do {
            try self.init(rawValue: value)
        } catch {
            preconditionFailure(error.localizedDescription)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        try self.init(rawValue: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: NamespacedID, rhs: NamespacedID) -> Bool {
        if lhs.namespace != rhs.namespace {
            return lhs.namespace.localizedStandardCompare(rhs.namespace) == .orderedAscending
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

public struct LoadedDataDefinition<Value: Sendable>: Sendable {
    fileprivate let definition: DataDefinition
    public let value: Value
}

public struct BlockDefinition: Codable, Hashable, Sendable, GameDataDefinition {
    fileprivate static let category: DataCategory = .blocks

    public let displayName: String
    public let voxel: BlockVoxelDefinition
    public let render: BlockRenderDefinition
    public let drops: [BlockDropDefinition]
    public let properties: [String: DefinitionPropertyValue]

    public init(
        displayName: String,
        voxel: BlockVoxelDefinition,
        render: BlockRenderDefinition,
        drops: [BlockDropDefinition] = [],
        properties: [String: DefinitionPropertyValue] = [:]
    ) {
        self.displayName = displayName
        self.voxel = voxel
        self.render = render
        self.drops = drops
        self.properties = properties
    }
}

public struct ItemDefinition: Codable, Hashable, Sendable, GameDataDefinition {
    fileprivate static let category: DataCategory = .items

    public let displayName: String
    public let stackSize: Int
    public let properties: [String: DefinitionPropertyValue]

    public init(
        displayName: String,
        stackSize: Int = 64,
        properties: [String: DefinitionPropertyValue] = [:]
    ) {
        self.displayName = displayName
        self.stackSize = stackSize
        self.properties = properties
    }
}

public struct BlockVoxelDefinition: Codable, Hashable, Sendable {
    public let solid: Bool
    public let material: String
    public let translucent: Bool

    public init(solid: Bool, material: String, translucent: Bool = false) {
        self.solid = solid
        self.material = material
        self.translucent = translucent
    }
}

public struct BlockRenderDefinition: Codable, Hashable, Sendable {
    public let opacity: Double
    public let tintKey: NamespacedID?
    public let antiAlias: Bool

    public init(opacity: Double, tintKey: NamespacedID? = nil, antiAlias: Bool = true) {
        self.opacity = opacity
        self.tintKey = tintKey
        self.antiAlias = antiAlias
    }
}

public struct BlockDropDefinition: Codable, Hashable, Sendable {
    public let itemID: NamespacedID
    public let count: Int

    public init(itemID: NamespacedID, count: Int = 1) {
        self.itemID = itemID
        self.count = count
    }
}

public enum DefinitionPropertyValue: Codable, Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                DefinitionPropertyValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported property value."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        }
    }
}

public enum DataValidationIssue: LocalizedError {
    case duplicateDefinition(id: NamespacedID, paths: [String])
    case missingReference(sourceID: NamespacedID, reference: NamespacedID, field: String)
    case invalidProperty(id: NamespacedID, property: String, value: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .duplicateDefinition(id, paths):
            return "Duplicate definition for \(id.rawValue) found at: \(paths.joined(separator: ", "))."
        case let .missingReference(sourceID, reference, field):
            return "Definition \(sourceID.rawValue) references missing \(field) \(reference.rawValue)."
        case let .invalidProperty(id, property, value, reason):
            return "Definition \(id.rawValue) has invalid \(property) '\(value)': \(reason)."
        }
    }
}

public struct DataRegistry: Sendable {
    fileprivate let blocksByID: [NamespacedID: LoadedDataDefinition<BlockDefinition>]
    fileprivate let itemsByID: [NamespacedID: LoadedDataDefinition<ItemDefinition>]

    public func block(for id: NamespacedID) -> LoadedDataDefinition<BlockDefinition>? {
        blocksByID[id]
    }

    public func item(for id: NamespacedID) -> LoadedDataDefinition<ItemDefinition>? {
        itemsByID[id]
    }
}

public struct DataReloadChanges: Sendable {
    public let blocks: ReloadDelta<NamespacedID>
    public let items: ReloadDelta<NamespacedID>
    public let impact: DataReloadImpact

    public var hasChanges: Bool {
        blocks.hasChanges || items.hasChanges
    }

    public init(
        blocks: ReloadDelta<NamespacedID>,
        items: ReloadDelta<NamespacedID>,
        impact: DataReloadImpact
    ) {
        self.blocks = blocks
        self.items = items
        self.impact = impact
    }
}

public struct DataReloadImpact: Sendable {
    public let affectedBlocks: [NamespacedID]
    public let affectedItems: [NamespacedID]

    public var hasAffectedContent: Bool {
        !affectedBlocks.isEmpty || !affectedItems.isEmpty
    }

    public init(affectedBlocks: [NamespacedID], affectedItems: [NamespacedID]) {
        self.affectedBlocks = affectedBlocks
        self.affectedItems = affectedItems
    }
}

// MARK: - Public Manager

public actor DataManager {
    private let packManager: PackManager
    private let store: DataStore
    private var cachedBlocks: [LoadedDataDefinition<BlockDefinition>]?
    private var cachedItems: [LoadedDataDefinition<ItemDefinition>]?
    private var cachedRegistry: DataRegistry?

    public init(packManager: PackManager) {
        self.packManager = packManager
        self.store = DataStore()
    }

    public func blocks() async throws -> [LoadedDataDefinition<BlockDefinition>] {
        if let cachedBlocks {
            return cachedBlocks
        }

        let definitions = try await definitions(in: .blocks)
        var blocks: [LoadedDataDefinition<BlockDefinition>] = []
        blocks.reserveCapacity(definitions.count)

        for definition in definitions {
            blocks.append(try await decode(BlockDefinition.self, for: definition))
        }

        cachedBlocks = blocks
        return blocks
    }

    public func items() async throws -> [LoadedDataDefinition<ItemDefinition>] {
        if let cachedItems {
            return cachedItems
        }

        let definitions = try await definitions(in: .items)
        var items: [LoadedDataDefinition<ItemDefinition>] = []
        items.reserveCapacity(definitions.count)

        for definition in definitions {
            items.append(try await decode(ItemDefinition.self, for: definition))
        }

        cachedItems = items
        return items
    }

    public func block(id: NamespacedID) async throws -> LoadedDataDefinition<BlockDefinition>? {
        try await registry().block(for: id)
    }

    public func item(id: NamespacedID) async throws -> LoadedDataDefinition<ItemDefinition>? {
        try await registry().item(for: id)
    }

    public func hasBlock(id: NamespacedID) async throws -> Bool {
        try await block(id: id) != nil
    }

    public func hasItem(id: NamespacedID) async throws -> Bool {
        try await item(id: id) != nil
    }

    public func registry() async throws -> DataRegistry {
        if let cachedRegistry {
            return cachedRegistry
        }

        let blocks = try await blocks()
        let items = try await items()

        let registry = DataRegistry(
            blocksByID: dictionaryByID(from: blocks),
            itemsByID: dictionaryByID(from: items)
        )
        cachedRegistry = registry
        return registry
    }

    public func validate() async throws -> [DataValidationIssue] {
        let blocks = try await blocks()
        let items = try await items()

        var issues: [DataValidationIssue] = []
        issues.append(contentsOf: duplicateIssues(in: blocks))
        issues.append(contentsOf: duplicateIssues(in: items))

        let itemIDs = Set(items.map(\.id))
        for block in blocks {
            for drop in block.value.drops where !itemIDs.contains(drop.itemID) {
                issues.append(
                    .missingReference(
                        sourceID: block.id,
                        reference: drop.itemID,
                        field: "item drop"
                    )
                )
            }
        }

        return issues
    }

    public func reload() async throws -> DataReloadChanges {
        let previousBlocks = cachedBlocks ?? []
        let previousItems = cachedItems ?? []

        _ = try await packManager.reload()

        cachedBlocks = nil
        cachedItems = nil
        cachedRegistry = nil

        let currentBlocks = try await blocks()
        let currentItems = try await items()
        _ = try await registry()

        let blockChanges = diffByID(
            old: dictionaryByID(from: previousBlocks),
            new: dictionaryByID(from: currentBlocks)
        )
        let itemChanges = diffByID(
            old: dictionaryByID(from: previousItems),
            new: dictionaryByID(from: currentItems)
        )

        return DataReloadChanges(
            blocks: blockChanges,
            items: itemChanges,
            impact: impactForReload(
                blockChanges: blockChanges,
                itemChanges: itemChanges,
                previousBlocks: previousBlocks,
                currentBlocks: currentBlocks
            )
        )
    }

    private func impactForReload(
        blockChanges: ReloadDelta<NamespacedID>,
        itemChanges: ReloadDelta<NamespacedID>,
        previousBlocks: [LoadedDataDefinition<BlockDefinition>],
        currentBlocks: [LoadedDataDefinition<BlockDefinition>]
    ) -> DataReloadImpact {
        let changedBlockIDs = Set(blockChanges.added + blockChanges.removed + blockChanges.updated)
        let changedItemIDs = Set(itemChanges.added + itemChanges.removed + itemChanges.updated)
        let relevantBlocks = previousBlocks + currentBlocks

        let blocksAffectedByItems = Set(relevantBlocks.compactMap { block in
            block.value.drops.contains { changedItemIDs.contains($0.itemID) } ? block.id : nil
        })

        return DataReloadImpact(
            affectedBlocks: Array(changedBlockIDs.union(blocksAffectedByItems)).sorted(),
            affectedItems: Array(changedItemIDs).sorted()
        )
    }

    private func availableDefinitions() async throws -> [DataDefinition] {
        let packs = try await packManager.activePacks()
        var definitions: [DataDefinition] = []

        for pack in packs {
            try definitions.append(contentsOf: store.discoverDefinitions(in: pack))
        }

        return definitions
    }

    private func definitions(in category: DataCategory) async throws -> [DataDefinition] {
        let definitions = try await availableDefinitions()
        return definitions.filter { $0.category == category }
    }

    private func decode<T: GameDataDefinition>(
        _ type: T.Type,
        for definition: DataDefinition
    ) async throws -> LoadedDataDefinition<T> {
        guard let pack = try await packManager.pack(id: definition.packID) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let value = try store.decode(type, for: definition, in: pack)
        return LoadedDataDefinition(definition: definition, value: value)
    }
}

// MARK: - Public Extensions

public extension LoadedDataDefinition {
    var resourcePath: String {
        let categoryDirectory = definition.category.relativeDirectoryPath + "/"
        guard definition.relativePath.hasPrefix(categoryDirectory) else {
            return definition.relativePath
        }

        let trimmedPath = String(definition.relativePath.dropFirst(categoryDirectory.count))
        let fileURL = URL(fileURLWithPath: trimmedPath)
        let basePath = fileURL.deletingPathExtension().path
        return basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var name: String {
        resourcePath
    }

    var id: NamespacedID {
        NamespacedID(namespace: definition.packID, name: name)
    }
}

// MARK: - Store

private enum DataCategory: String, CaseIterable, Codable {
    case blocks
    case items
    case entities
    case biomes
    case tags
    case recipes
    case lootTables = "loot_tables"
}

private protocol GameDataDefinition: Decodable {
    static var category: DataCategory { get }
}

private struct DataDefinition: Identifiable, Codable {
    let packID: String
    let category: DataCategory
    let relativePath: String

    var id: String {
        "\(packID):\(relativePath)"
    }
}

extension DataDefinition: Hashable {}

private enum DataStoreError: LocalizedError {
    case categoryMismatch(expected: DataCategory, actual: DataCategory, relativePath: String)

    var errorDescription: String? {
        switch self {
        case let .categoryMismatch(expected, actual, relativePath):
            return "Expected \(expected.rawValue) data but found \(actual.rawValue) at \(relativePath)."
        }
    }
}

private struct DataStore {
    let fileManager: FileManager
    let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.decoder = decoder
    }

    func discoverDefinitions(in pack: PackRecord) throws -> [DataDefinition] {
        try DataCategory.allCases.flatMap { category in
            try definitions(in: category, for: pack)
        }
    }

    func data(for definition: DataDefinition, in pack: PackRecord) throws -> Data {
        let fileURL = pack.location.appendingPathComponent(definition.relativePath)
        return try Data(contentsOf: fileURL)
    }

    func decode<T: GameDataDefinition>(
        _ type: T.Type,
        for definition: DataDefinition,
        in pack: PackRecord
    ) throws -> T {
        guard definition.category == type.category else {
            throw DataStoreError.categoryMismatch(
                expected: type.category,
                actual: definition.category,
                relativePath: definition.relativePath
            )
        }

        let fileData = try data(for: definition, in: pack)
        return try decoder.decode(type, from: fileData)
    }

    private func definitions(in category: DataCategory, for pack: PackRecord) throws -> [DataDefinition] {
        let relativeDirectory = category.relativeDirectoryPath
        let directoryURL = pack.location.appendingPathComponent(relativeDirectory, isDirectory: true)

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try jsonFiles(in: directoryURL).map { fileURL in
            DataDefinition(
                packID: pack.id,
                category: category,
                relativePath: relativePath(for: fileURL, in: pack.location)
            )
        }
    }

    private func jsonFiles(in directoryURL: URL) throws -> [URL] {
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [URL] = []

        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, url.pathExtension == "json" else {
                continue
            }

            files.append(url)
        }

        return files
    }

    private func relativePath(for fileURL: URL, in rootURL: URL) -> String {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        return String(fileURL.path.dropFirst(rootPath.count))
    }
}

// MARK: - Helpers

private func duplicateIssues<Value>(
    in definitions: [LoadedDataDefinition<Value>]
) -> [DataValidationIssue] {
    let grouped = Dictionary(grouping: definitions, by: \.id)

    return grouped.compactMap { id, matches in
        guard matches.count > 1 else {
            return nil
        }

        return .duplicateDefinition(
            id: id,
            paths: matches.map(\.definition.relativePath).sorted()
        )
    }
}

private func dictionaryByID<Value>(
    from definitions: [LoadedDataDefinition<Value>]
) -> [NamespacedID: LoadedDataDefinition<Value>] {
    definitions.reduce(into: [:]) { result, definition in
        result[definition.id] = definition
    }
}

extension LoadedDataDefinition: Equatable where Value: Equatable {
    public static func == (lhs: LoadedDataDefinition<Value>, rhs: LoadedDataDefinition<Value>) -> Bool {
        lhs.definition == rhs.definition && lhs.value == rhs.value
    }
}

private extension DataCategory {
    var relativeDirectoryPath: String {
        switch self {
        case .blocks:
            return "data/blocks"
        case .items:
            return "data/items"
        case .entities:
            return "data/entities"
        case .biomes:
            return "data/worldgen/biomes"
        case .tags:
            return "data/tags"
        case .recipes:
            return "data/recipes"
        case .lootTables:
            return "data/loot_tables"
        }
    }
}
