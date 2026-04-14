//
//  AssetKit.swift
//  VGCore
//
//  Created by Kalob Allen on 4/11/26.
//

import Foundation

// MARK: - Public Models

public struct TextureAsset: Identifiable, Codable, Hashable, Sendable {
    public var packID: String
    public var relativePath: String

    public var id: String {
        "\(packID):\(relativePath)"
    }
}

public extension TextureAsset {
    var resourceID: NamespacedID {
        let prefix = "assets/textures/"
        let trimmedPath = relativePath.hasPrefix(prefix) ? String(relativePath.dropFirst(prefix.count)) : relativePath
        let basePath = URL(fileURLWithPath: trimmedPath).deletingPathExtension().path
        return NamespacedID(
            namespace: packID,
            name: basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
    }
}

public struct ModelElementFaceDefinition: Codable, Hashable, Sendable {
    public var texture: String
}

public struct ModelElementDefinition: Codable, Hashable, Sendable {
    public var from: [Double]
    public var to: [Double]
    public var faces: [String: ModelElementFaceDefinition]?
}

public struct BlockModelDefinition: Identifiable, Codable, Hashable, Sendable, GameAssetDefinition {
    fileprivate static let category: AssetCategory = .models

    public var id: String
    public var parent: String?
    public var textures: [String: String]?
    public var elements: [ModelElementDefinition]?
}

public struct VariantStateDefinition: Codable, Hashable, Sendable {
    public var model: String
    public var x: Int?
    public var y: Int?
    public var uvlock: Bool?
}

public struct BlockStateDefinition: Identifiable, Codable, Hashable, Sendable, GameAssetDefinition {
    fileprivate static let category: AssetCategory = .states

    public var id: String
    public var variants: [String: VariantStateDefinition]
}

// MARK: - Public Manager

public struct AssetReloadChanges: Sendable {
    public let textures: ReloadDelta<String>
    public let models: ReloadDelta<String>
    public let states: ReloadDelta<String>
    public let impact: AssetReloadImpact

    public var hasChanges: Bool {
        textures.hasChanges || models.hasChanges || states.hasChanges
    }

    public init(
        textures: ReloadDelta<String>,
        models: ReloadDelta<String>,
        states: ReloadDelta<String>,
        impact: AssetReloadImpact
    ) {
        self.textures = textures
        self.models = models
        self.states = states
        self.impact = impact
    }
}

public struct AssetReloadImpact: Sendable {
    public let affectedTextures: [String]
    public let affectedModels: [String]
    public let affectedStates: [String]

    public var hasAffectedContent: Bool {
        !affectedTextures.isEmpty || !affectedModels.isEmpty || !affectedStates.isEmpty
    }

    public init(
        affectedTextures: [String],
        affectedModels: [String],
        affectedStates: [String]
    ) {
        self.affectedTextures = affectedTextures
        self.affectedModels = affectedModels
        self.affectedStates = affectedStates
    }
}

public actor AssetManager {
    private let packManager: PackManager
    private let store: AssetStore
    private var cachedTextures: [TextureAsset]?
    private var cachedModels: [BlockModelDefinition]?
    private var cachedStates: [BlockStateDefinition]?

    public init(packManager: PackManager) {
        self.packManager = packManager
        self.store = AssetStore()
    }

    public func textures() async throws -> [TextureAsset] {
        if let cachedTextures {
            return cachedTextures
        }

        let packs = try await packManager.activePacks()
        var textures: [TextureAsset] = []

        for pack in packs {
            try textures.append(contentsOf: store.textureAssets(in: pack))
        }

        cachedTextures = textures
        return textures
    }

    public func textureURL(for texture: TextureAsset) async throws -> URL {
        guard let pack = try await packManager.pack(id: texture.packID) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return store.textureURL(for: texture, in: pack)
    }

    public func models() async throws -> [BlockModelDefinition] {
        if let cachedModels {
            return cachedModels
        }

        let definitions = try await definitions(in: .models)
        var models: [BlockModelDefinition] = []
        models.reserveCapacity(definitions.count)

        for definition in definitions {
            models.append(try await decode(BlockModelDefinition.self, for: definition))
        }

        cachedModels = models
        return models
    }

    public func states() async throws -> [BlockStateDefinition] {
        if let cachedStates {
            return cachedStates
        }

        let definitions = try await definitions(in: .states)
        var states: [BlockStateDefinition] = []
        states.reserveCapacity(definitions.count)

        for definition in definitions {
            states.append(try await decode(BlockStateDefinition.self, for: definition))
        }

        cachedStates = states
        return states
    }

    public func model(id: NamespacedID) async throws -> BlockModelDefinition? {
        let relativePath = "assets/models/\(id.name).json"
        guard let definition = try await definition(
            in: .models,
            packID: id.namespace,
            relativePath: relativePath
        ) else {
            return nil
        }

        return try await decode(BlockModelDefinition.self, for: definition)
    }

    public func state(id: NamespacedID) async throws -> BlockStateDefinition? {
        let relativePath = "assets/states/\(id.name).json"
        guard let definition = try await definition(
            in: .states,
            packID: id.namespace,
            relativePath: relativePath
        ) else {
            return nil
        }

        return try await decode(BlockStateDefinition.self, for: definition)
    }

    public func textureURL(id: NamespacedID, fileExtension: String = "png") async throws -> URL? {
        let relativePath = "assets/textures/\(id.name).\(fileExtension)"
        guard let texture = try await textures().first(where: { texture in
            texture.packID == id.namespace && texture.relativePath == relativePath
        }) else {
            return nil
        }

        return try await textureURL(for: texture)
    }

    public func reload() async throws -> AssetReloadChanges {
        let previousTextures = cachedTextures ?? []
        let previousModels = cachedModels ?? []
        let previousStates = cachedStates ?? []

        _ = try await packManager.reload()

        cachedTextures = nil
        cachedModels = nil
        cachedStates = nil

        let currentTextures = try await textures()
        let currentModels = try await models()
        let currentStates = try await states()

        let textureChanges = diffByID(
            old: Dictionary(uniqueKeysWithValues: previousTextures.map { ($0.id, $0) }),
            new: Dictionary(uniqueKeysWithValues: currentTextures.map { ($0.id, $0) })
        )
        let modelChanges = diffByID(
            old: Dictionary(uniqueKeysWithValues: previousModels.map { ($0.id, $0) }),
            new: Dictionary(uniqueKeysWithValues: currentModels.map { ($0.id, $0) })
        )
        let stateChanges = diffByID(
            old: Dictionary(uniqueKeysWithValues: previousStates.map { ($0.id, $0) }),
            new: Dictionary(uniqueKeysWithValues: currentStates.map { ($0.id, $0) })
        )

        return AssetReloadChanges(
            textures: textureChanges,
            models: modelChanges,
            states: stateChanges,
            impact: impactForReload(
                textureChanges: textureChanges,
                modelChanges: modelChanges,
                stateChanges: stateChanges,
                previousTextures: previousTextures,
                currentTextures: currentTextures,
                previousModels: previousModels,
                currentModels: currentModels,
                previousStates: previousStates,
                currentStates: currentStates
            )
        )
    }

    private func impactForReload(
        textureChanges: ReloadDelta<String>,
        modelChanges: ReloadDelta<String>,
        stateChanges: ReloadDelta<String>,
        previousTextures: [TextureAsset],
        currentTextures: [TextureAsset],
        previousModels: [BlockModelDefinition],
        currentModels: [BlockModelDefinition],
        previousStates: [BlockStateDefinition],
        currentStates: [BlockStateDefinition]
    ) -> AssetReloadImpact {
        let changedTextureIDs = Set(textureChanges.added + textureChanges.removed + textureChanges.updated)
        let changedModelIDs = Set(modelChanges.added + modelChanges.removed + modelChanges.updated)
        let changedStateIDs = Set(stateChanges.added + stateChanges.removed + stateChanges.updated)

        let changedTextureReferences = Set((previousTextures + currentTextures).compactMap { texture in
            changedTextureIDs.contains(texture.id) ? texture.resourceID.rawValue : nil
        })

        let relevantModels = previousModels + currentModels
        let modelsAffectedByTextures: Set<String> = Set(relevantModels.compactMap { model in
            guard let textures = model.textures?.values else {
                return nil
            }

            return textures.contains { textureReference in
                changedTextureReferences.contains(textureReference)
            } ? model.id : nil
        })

        let effectiveChangedModelIDs = changedModelIDs.union(modelsAffectedByTextures)
        let relevantStates = previousStates + currentStates
        let statesAffectedByModels: Set<String> = Set(relevantStates.compactMap { state in
            state.variants.values.contains { effectiveChangedModelIDs.contains($0.model) } ? state.id : nil
        })

        return AssetReloadImpact(
            affectedTextures: Array(changedTextureIDs).sorted(),
            affectedModels: Array(effectiveChangedModelIDs).sorted(),
            affectedStates: Array(changedStateIDs.union(statesAffectedByModels)).sorted()
        )
    }

    private func availableDefinitions() async throws -> [AssetDefinition] {
        let packs = try await packManager.activePacks()
        var definitions: [AssetDefinition] = []

        for pack in packs {
            try definitions.append(contentsOf: store.discoverDefinitions(in: pack))
        }

        return definitions
    }

    private func definitions(in category: AssetCategory) async throws -> [AssetDefinition] {
        let definitions = try await availableDefinitions()
        return definitions.filter { $0.category == category }
    }

    private func definition(
        in category: AssetCategory,
        packID: String,
        relativePath: String
    ) async throws -> AssetDefinition? {
        let definitions = try await definitions(in: category)
        return definitions.first { definition in
            definition.packID == packID && definition.relativePath == relativePath
        }
    }

    private func decode<T: GameAssetDefinition>(
        _ type: T.Type,
        for definition: AssetDefinition
    ) async throws -> T {
        guard let pack = try await packManager.pack(id: definition.packID) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return try store.decode(type, for: definition, in: pack)
    }
}

// MARK: - Store

private enum AssetCategory: String, CaseIterable, Codable {
    case textures
    case models
    case states
}

private protocol GameAssetDefinition: Decodable {
    static var category: AssetCategory { get }
}

private struct AssetDefinition: Identifiable, Codable {
    let packID: String
    let category: AssetCategory
    let relativePath: String

    var id: String {
        "\(packID):\(relativePath)"
    }
}

private enum AssetStoreError: LocalizedError {
    case categoryMismatch(expected: AssetCategory, actual: AssetCategory, relativePath: String)

    var errorDescription: String? {
        switch self {
        case let .categoryMismatch(expected, actual, relativePath):
            return "Expected \(expected.rawValue) asset but found \(actual.rawValue) at \(relativePath)."
        }
    }
}

private struct AssetStore {
    let fileManager: FileManager
    let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.decoder = decoder
    }

    func discoverDefinitions(in pack: PackRecord) throws -> [AssetDefinition] {
        try AssetCategory.allCases.flatMap { category in
            try definitions(in: category, for: pack)
        }
    }

    func textureAssets(in pack: PackRecord) throws -> [TextureAsset] {
        let directoryURL = pack.assetsDirectory.appendingPathComponent("textures", isDirectory: true)

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try assetFiles(
            in: directoryURL,
            allowedExtensions: ["png", "jpg", "jpeg", "webp"]
        ).map { fileURL in
            TextureAsset(
                packID: pack.id,
                relativePath: relativePath(for: fileURL, in: pack.location)
            )
        }
    }

    func data(for definition: AssetDefinition, in pack: PackRecord) throws -> Data {
        let fileURL = pack.location.appendingPathComponent(definition.relativePath)
        return try Data(contentsOf: fileURL)
    }

    func textureURL(for texture: TextureAsset, in pack: PackRecord) -> URL {
        pack.location.appendingPathComponent(texture.relativePath)
    }

    func decode<T: GameAssetDefinition>(
        _ type: T.Type,
        for definition: AssetDefinition,
        in pack: PackRecord
    ) throws -> T {
        guard definition.category == type.category else {
            throw AssetStoreError.categoryMismatch(
                expected: type.category,
                actual: definition.category,
                relativePath: definition.relativePath
            )
        }

        let fileData = try data(for: definition, in: pack)
        return try decoder.decode(type, from: fileData)
    }

    private func definitions(in category: AssetCategory, for pack: PackRecord) throws -> [AssetDefinition] {
        let relativeDirectory = relativeDirectoryPath(for: category)
        let directoryURL = pack.location.appendingPathComponent(relativeDirectory, isDirectory: true)

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let allowedExtensions: [String]
        switch category {
        case .textures:
            allowedExtensions = ["png", "jpg", "jpeg", "webp"]
        case .models, .states:
            allowedExtensions = ["json"]
        }

        return try assetFiles(in: directoryURL, allowedExtensions: allowedExtensions).map { fileURL in
            AssetDefinition(
                packID: pack.id,
                category: category,
                relativePath: relativePath(for: fileURL, in: pack.location)
            )
        }
    }

    private func relativeDirectoryPath(for category: AssetCategory) -> String {
        switch category {
        case .textures:
            return "assets/textures"
        case .models:
            return "assets/models"
        case .states:
            return "assets/states"
        }
    }

    private func assetFiles(in directoryURL: URL, allowedExtensions: [String]) throws -> [URL] {
        let allowed = Set(allowedExtensions.map { $0.lowercased() })
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [URL] = []

        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            let pathExtension = url.pathExtension.lowercased()
            guard allowed.contains(pathExtension) else {
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
