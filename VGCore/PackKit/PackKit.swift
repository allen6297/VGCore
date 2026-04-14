//
//  PackKit.swift
//  VGCore
//
//  Created by Kalob Allen on 4/11/26.
//

import Foundation

// MARK: - Public Models

public struct PackDefinition: Codable, Hashable, Sendable {
    fileprivate static let manifestFileName = "pack.json"

    public var minSupportedVersion: String?
    public var maxSupportedVersion: String?
    public var packVersion: String
    public var author: String?
    public var description: String?

    public init(
        minSupportedVersion: String? = nil,
        maxSupportedVersion: String? = nil,
        packVersion: String,
        author: String? = nil,
        description: String? = nil
    ) {
        self.minSupportedVersion = minSupportedVersion
        self.maxSupportedVersion = maxSupportedVersion
        self.packVersion = packVersion
        self.author = author
        self.description = description
    }

    public init(
        supportedVersion: String,
        packVersion: String,
        author: String? = nil,
        description: String? = nil
    ) {
        self.init(
            minSupportedVersion: supportedVersion,
            maxSupportedVersion: supportedVersion,
            packVersion: packVersion,
            author: author,
            description: description
        )
    }

    public func supports(coreVersion: String) -> Bool {
        guard minSupportedVersion != nil || maxSupportedVersion != nil else {
            return false
        }

        if let minSupportedVersion,
           VersionComparator.compare(coreVersion, minSupportedVersion) == .orderedAscending {
            return false
        }

        if let maxSupportedVersion,
           VersionComparator.compare(coreVersion, maxSupportedVersion) == .orderedDescending {
            return false
        }

        return true
    }

    private enum CodingKeys: String, CodingKey {
        case supportedVersion
        case minSupportedVersion
        case maxSupportedVersion
        case packVersion
        case author
        case description
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let legacySupportedVersion = try container.decodeIfPresent(String.self, forKey: .supportedVersion)
        minSupportedVersion = try container.decodeIfPresent(String.self, forKey: .minSupportedVersion) ?? legacySupportedVersion
        maxSupportedVersion = try container.decodeIfPresent(String.self, forKey: .maxSupportedVersion) ?? legacySupportedVersion
        packVersion = try container.decode(String.self, forKey: .packVersion)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(minSupportedVersion, forKey: .minSupportedVersion)
        try container.encodeIfPresent(maxSupportedVersion, forKey: .maxSupportedVersion)
        try container.encode(packVersion, forKey: .packVersion)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

public struct PackRecord: Identifiable, Hashable, Sendable {
    public var id: String
    public var location: URL
    public var definition: PackDefinition

    public var namespace: String {
        id
    }

    public var manifestURL: URL {
        location.appendingPathComponent(PackDefinition.manifestFileName)
    }

    public var assetsDirectory: URL {
        location.appendingPathComponent("assets", isDirectory: true)
    }

    public var dataDirectory: URL {
        location.appendingPathComponent("data", isDirectory: true)
    }

    public var scriptsDirectory: URL {
        location.appendingPathComponent("scripts", isDirectory: true)
    }
}

// MARK: - Public Manager

public struct ReloadDelta<ID: Hashable & Sendable>: Sendable {
    public let added: [ID]
    public let removed: [ID]
    public let updated: [ID]

    public var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty || !updated.isEmpty
    }

    public init(added: [ID], removed: [ID], updated: [ID]) {
        self.added = added
        self.removed = removed
        self.updated = updated
    }
}

public struct PackReloadChanges: Sendable {
    public let available: ReloadDelta<String>
    public let compatible: ReloadDelta<String>

    public var hasChanges: Bool {
        available.hasChanges || compatible.hasChanges
    }

    public init(available: ReloadDelta<String>, compatible: ReloadDelta<String>) {
        self.available = available
        self.compatible = compatible
    }
}

/// Manages data packs for the game.
///
/// PackManager discovers, validates, and tracks packs from the packs directory.
/// All methods are thread-safe through actor isolation.
public actor PackManager {
    private let store: PackStore
    private let coreVersion: String
    private var cachedAvailablePacks: [PackRecord]?
    private var cachedCompatiblePacks: [PackRecord]?

    public init(packsDirectory: URL) {
        self.init(packsDirectory: packsDirectory, coreVersion: VGCoreInfo.coreVersion)
    }

    public init(packsDirectory: URL, coreVersion: String) {
        self.store = PackStore(packsDirectory: packsDirectory)
        self.coreVersion = coreVersion
    }

    public func availablePacks() throws -> [PackRecord] {
        if let cachedAvailablePacks {
            return cachedAvailablePacks
        }

        let availablePacks = try store.discoverPacks()
        cachedAvailablePacks = availablePacks
        return availablePacks
    }

    public func compatiblePacks() throws -> [PackRecord] {
        if let cachedCompatiblePacks {
            return cachedCompatiblePacks
        }

        let compatiblePacks = try availablePacks().filter { pack in
            pack.definition.supports(coreVersion: coreVersion)
        }
        cachedCompatiblePacks = compatiblePacks
        return compatiblePacks
    }

    public func pack(id: String) throws -> PackRecord? {
        try availablePacks().first { $0.id == id }
    }

    public func activePacks() throws -> [PackRecord] {
        try compatiblePacks()
    }

    public func reload() throws -> PackReloadChanges {
        let previousAvailable = cachedAvailablePacks ?? []
        let previousCompatible = cachedCompatiblePacks ?? []

        cachedAvailablePacks = nil
        cachedCompatiblePacks = nil

        let currentAvailable = try availablePacks()
        let currentCompatible = try compatiblePacks()

        return PackReloadChanges(
            available: diffByID(
                old: Dictionary(uniqueKeysWithValues: previousAvailable.map { ($0.id, $0) }),
                new: Dictionary(uniqueKeysWithValues: currentAvailable.map { ($0.id, $0) })
            ),
            compatible: diffByID(
                old: Dictionary(uniqueKeysWithValues: previousCompatible.map { ($0.id, $0) }),
                new: Dictionary(uniqueKeysWithValues: currentCompatible.map { ($0.id, $0) })
            )
        )
    }
}

// MARK: - STORE

private struct PackStore {
    let packsDirectory: URL
    let fileManager: FileManager
    let decoder: JSONDecoder

    init(
        packsDirectory: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.packsDirectory = packsDirectory
        self.fileManager = fileManager
        self.decoder = decoder
    }

    func discoverPacks() throws -> [PackRecord] {
        guard fileManager.fileExists(atPath: packsDirectory.path) else {
            return []
        }

        let packDirectories = try fileManager.contentsOfDirectory(
            at: packsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try packDirectories.compactMap { directoryURL in
            guard try isDirectory(at: directoryURL) else {
                return nil
            }

            let definition = try loadDefinition(in: directoryURL)
            return PackRecord(
                id: directoryURL.lastPathComponent,
                location: directoryURL,
                definition: definition
            )
        }
    }

    func loadDefinition(in packDirectory: URL) throws -> PackDefinition {
        let definitionURL = packDirectory.appendingPathComponent(PackDefinition.manifestFileName)
        let data = try Data(contentsOf: definitionURL)
        return try decoder.decode(PackDefinition.self, from: data)
    }

    private func isDirectory(at url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }
}

private enum VersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftComponents = parse(lhs)
        let rightComponents = parse(rhs)
        let count = max(leftComponents.count, rightComponents.count)
        for index in 0..<count {
            let left = index < leftComponents.count ? leftComponents[index] : .zero
            let right = index < rightComponents.count ? rightComponents[index] : .zero

            if left.number != right.number {
                return left.number < right.number ? .orderedAscending : .orderedDescending
            }

            if left.suffix != right.suffix {
                switch (left.suffix.isEmpty, right.suffix.isEmpty) {
                case (true, false):
                    return .orderedDescending
                case (false, true):
                    return .orderedAscending
                default:
                    return left.suffix.localizedStandardCompare(right.suffix)
                }
            }
        }

        return .orderedSame
    }

    private static func parse(_ version: String) -> [Component] {
        version.split(separator: ".", omittingEmptySubsequences: false).map(Component.init)
    }

    private struct Component: Comparable {
        let number: Int
        let suffix: String

        static let zero = Component(number: 0, suffix: "")

        init(number: Int, suffix: String) {
            self.number = number
            self.suffix = suffix
        }

        init(_ rawValue: some StringProtocol) {
            let scalarView = String(rawValue)
            let digits = scalarView.prefix { $0.isNumber }
            number = Int(digits) ?? 0
            suffix = String(scalarView.dropFirst(digits.count))
        }

        static func < (lhs: Component, rhs: Component) -> Bool {
            if lhs.number != rhs.number {
                return lhs.number < rhs.number
            }

            return lhs.suffix < rhs.suffix
        }
    }
}
