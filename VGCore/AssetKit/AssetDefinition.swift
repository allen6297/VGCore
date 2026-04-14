//
//  AssetDefinition.swift
//  VGCore
//
//  Created by Kalob Allen on 4/11/26.
//

import Foundation

enum AssetCategory: String, CaseIterable, Codable {
    case textures
    case models
    case states
}

protocol GameAssetDefinition: Decodable {
    static var category: AssetCategory { get }
}

struct AssetDefinition: Identifiable, Codable {
    var packID: String
    var category: AssetCategory
    var relativePath: String

    var id: String {
        "\(packID):\(relativePath)"
    }
}

struct TextureAsset: Identifiable, Codable {
    var packID: String
    var relativePath: String

    var id: String {
        "\(packID):\(relativePath)"
    }
}

struct ModelElementFaceDefinition: Codable {
    var texture: String
}

struct ModelElementDefinition: Codable {
    var from: [Double]
    var to: [Double]
    var faces: [String: ModelElementFaceDefinition]?
}

struct BlockModelDefinition: Identifiable, Codable, GameAssetDefinition {
    static let category: AssetCategory = .models

    var id: String
    var parent: String?
    var textures: [String: String]?
    var elements: [ModelElementDefinition]?
}

struct VariantStateDefinition: Codable {
    var model: String
    var x: Int?
    var y: Int?
    var uvlock: Bool?
}

struct BlockStateDefinition: Identifiable, Codable, GameAssetDefinition {
    static let category: AssetCategory = .states

    var id: String
    var variants: [String: VariantStateDefinition]
}
