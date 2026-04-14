//
//  DataKit+Examples.swift
//  VGCore
//
//  Created by Kalob Allen on 4/12/26.
//
//  This file contains usage examples for DataKit.
//

import Foundation

/*

# DataKit Usage Examples

## Basic Setup

```swift
// Initialize the pack and data managers
let packsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("packs")

let packManager = PackManager(packsDirectory: packsURL, coreVersion: "1.0.0")
let dataManager = DataManager(packManager: packManager)
```

## Loading Data

Since DataManager is now an actor, all calls must be async:

```swift
// Load all blocks
let blocks = try await dataManager.blocks()
for block in blocks {
    print("Block: \(block.id.rawValue) - \(block.value.displayName)")
}

// Load all items
let items = try await dataManager.items()
for item in items {
    print("Item: \(item.id.rawValue) - \(item.value.displayName)")
}

// Get specific block or item
if let stone = try await dataManager.block(id: "minecraft:stone") {
    print("Found stone block with opacity: \(stone.value.render.opacity)")
}

// Check existence
let hasStone = try await dataManager.hasBlock(id: "minecraft:stone")
if hasStone {
    print("Stone block exists!")
}
```

## Using the Registry

```swift
// Get the registry for efficient repeated lookups
let registry = try await dataManager.registry()

// Look up blocks
if let grass = registry.block(for: "minecraft:grass") {
    print("Grass block drops: \(grass.value.drops)")
}

// Iterate all blocks
for blockID in registry.allBlockIDs {
    if let block = registry.block(for: blockID) {
        print("\(blockID.rawValue): \(block.value.displayName)")
    }
}

// Get counts
print("Total blocks: \(registry.blockCount)")
print("Total items: \(registry.itemCount)")
```

## Validation

```swift
// Validate all data
let issues = try await dataManager.validate()

if issues.isEmpty {
    print("✅ All data is valid!")
} else {
    print("❌ Found \(issues.count) validation issues:")
    for issue in issues {
        print("  - \(issue.localizedDescription)")
    }
}

// Handle specific validation issues
for issue in issues {
    switch issue {
    case let .duplicateDefinition(id, paths):
        print("Duplicate: \(id.rawValue) in \(paths)")
        
    case let .missingReference(sourceID, reference, field):
        print("Missing reference in \(sourceID.rawValue): \(field) -> \(reference.rawValue)")
        
    case let .invalidProperty(id, property, value, reason):
        print("Invalid property in \(id.rawValue): \(property) = \(value) (\(reason))")
    }
}
```

## Hot Reloading

```swift
// Reload all data (useful for development)
let changes = try await dataManager.reload()

if changes.hasChanges {
    print("Data changed!")
    
    // Check block changes
    if changes.blocks.hasChanges {
        print("Blocks added: \(changes.blocks.added)")
        print("Blocks removed: \(changes.blocks.removed)")
        print("Blocks updated: \(changes.blocks.updated)")
    }
    
    // Check item changes
    if changes.items.hasChanges {
        print("Items added: \(changes.items.added)")
        print("Items removed: \(changes.items.removed)")
        print("Items updated: \(changes.items.updated)")
    }
    
    // Check impact
    if changes.impact.hasAffectedContent {
        print("Affected blocks: \(changes.impact.affectedBlocks)")
        print("Affected items: \(changes.impact.affectedItems)")
    }
} else {
    print("No changes detected")
}
```

## Creating Custom Definitions

```swift
// Create a custom block definition
let customBlock = BlockDefinition(
    displayName: "My Custom Stone",
    voxel: BlockVoxelDefinition(
        solid: true,
        material: "stone",
        translucent: false
    ),
    render: BlockRenderDefinition(
        opacity: 1.0,
        tintKey: nil,
        antiAlias: true
    ),
    drops: [
        BlockDropDefinition(itemID: "mypack:stone_item", count: 1)
    ],
    properties: [
        "hardness": .double(2.0),
        "blast_resistance": .double(6.0),
        "requires_tool": .bool(true),
        "tool_type": .string("pickaxe"),
        "harvest_level": .int(0)
    ]
)

// Create a custom item definition
let customItem = ItemDefinition(
    displayName: "My Custom Tool",
    stackSize: 1,  // Non-stackable tool
    properties: [
        "durability": .int(250),
        "attack_damage": .double(5.0),
        "enchantable": .bool(true),
        "category": .string("tools")
    ]
)
```

## Working with Namespaced IDs

```swift
// Create namespaced IDs
let id1: NamespacedID = "minecraft:stone"  // String literal
let id2 = try NamespacedID(rawValue: "mypack:custom_block")
let id3 = NamespacedID(namespace: "vgcore", name: "grass")

// Use namespaced IDs
print(id1.namespace)  // "minecraft"
print(id1.name)       // "stone"
print(id1.rawValue)   // "minecraft:stone"

// Namespaced IDs are Hashable
let idSet: Set<NamespacedID> = [id1, id2, id3]
let idDict: [NamespacedID: String] = [
    id1: "A stone block",
    id2: "My custom block"
]
```

## Error Handling

```swift
// Handle namespaced ID parsing errors
do {
    let id = try NamespacedID(rawValue: "invalid_format")
} catch let error as NamespacedIDError {
    print("ID Error: \(error.localizedDescription)")
}

// Handle data loading errors
do {
    let blocks = try await dataManager.blocks()
} catch {
    print("Failed to load blocks: \(error)")
}

// Handle validation gracefully
let issues = try await dataManager.validate()
let criticalIssues = issues.filter { issue in
    if case .duplicateDefinition = issue {
        return true
    }
    return false
}

if !criticalIssues.isEmpty {
    print("Critical validation errors found!")
}
```

## Accessing Definition Metadata

```swift
let blocks = try await dataManager.blocks()

for block in blocks {
    // Access the definition metadata
    print("ID: \(block.id.rawValue)")
    print("Name: \(block.name)")
    print("Resource Path: \(block.resourcePath)")
    
    // Access the actual block data
    print("Display Name: \(block.value.displayName)")
    print("Solid: \(block.value.voxel.solid)")
    print("Material: \(block.value.voxel.material)")
    
    // Access properties
    if let hardness = block.value.properties["hardness"] {
        if case let .double(value) = hardness {
            print("Hardness: \(value)")
        }
    }
}
```

## Thread-Safe Concurrent Access

Since DataManager is an actor, it's automatically thread-safe:

```swift
// Multiple concurrent accesses are safe
Task {
    let blocks = try await dataManager.blocks()
    print("Task 1: \(blocks.count) blocks")
}

Task {
    let items = try await dataManager.items()
    print("Task 2: \(items.count) items")
}

Task {
    let registry = try await dataManager.registry()
    print("Task 3: \(registry.blockCount) blocks in registry")
}
```

## SwiftUI Integration

```swift
import SwiftUI

@MainActor
class GameDataModel: ObservableObject {
    let dataManager: DataManager
    
    @Published var blocks: [LoadedDataDefinition<BlockDefinition>] = []
    @Published var items: [LoadedDataDefinition<ItemDefinition>] = []
    @Published var validationIssues: [DataValidationIssue] = []
    @Published var isLoading = false
    
    init(dataManager: DataManager) {
        self.dataManager = dataManager
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            blocks = try await dataManager.blocks()
            items = try await dataManager.items()
            validationIssues = try await dataManager.validate()
        } catch {
            print("Failed to load data: \(error)")
        }
    }
    
    func reload() async {
        do {
            let changes = try await dataManager.reload()
            
            if changes.hasChanges {
                await loadData()
            }
        } catch {
            print("Failed to reload: \(error)")
        }
    }
}

struct ContentView: View {
    @StateObject var gameData: GameDataModel
    
    var body: some View {
        List {
            Section("Blocks") {
                ForEach(gameData.blocks, id: \.id) { block in
                    HStack {
                        Text(block.value.displayName)
                        Spacer()
                        Text(block.id.rawValue)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            
            Section("Validation") {
                if gameData.validationIssues.isEmpty {
                    Label("All data is valid", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(Array(gameData.validationIssues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .task {
            await gameData.loadData()
        }
        .refreshable {
            await gameData.reload()
        }
    }
}
```

*/
