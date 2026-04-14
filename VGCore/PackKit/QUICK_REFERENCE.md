# Quick Reference: Updated DataKit API

## All Methods Are Now Async

Since `DataManager` is an actor, all methods require `await`.

---

## Core Methods

### Loading Data

```swift
// Get all blocks
let blocks = try await dataManager.blocks()

// Get all items  
let items = try await dataManager.items()

// Get registry for fast lookups
let registry = try await dataManager.registry()
```

### Looking Up Specific Items

```swift
// Get specific block
if let stone = try await dataManager.block(id: "minecraft:stone") {
    print(stone.value.displayName)
}

// Get specific item
if let pickaxe = try await dataManager.item(id: "minecraft:pickaxe") {
    print(pickaxe.value.stackSize)
}

// Check existence
let hasBlock = try await dataManager.hasBlock(id: "minecraft:stone")
let hasItem = try await dataManager.hasItem(id: "minecraft:diamond")
```

### Validation

```swift
// Validate all data
let issues = try await dataManager.validate()

if issues.isEmpty {
    print("✅ All data valid")
} else {
    for issue in issues {
        print("❌ \(issue.localizedDescription)")
    }
}
```

### Reloading

```swift
// Hot reload from disk
let changes = try await dataManager.reload()

if changes.hasChanges {
    print("Added blocks: \(changes.blocks.added)")
    print("Removed blocks: \(changes.blocks.removed)")
    print("Updated blocks: \(changes.blocks.updated)")
}
```

---

## Registry Methods

Once you have a registry, lookups are fast and don't require `await`:

```swift
let registry = try await dataManager.registry()

// Look up by ID (no await needed)
let block = registry.block(for: "minecraft:stone")
let item = registry.item(for: "minecraft:diamond")

// Get all blocks/items
let allBlocks = registry.allBlocks
let allItems = registry.allItems

// Get sorted IDs
let blockIDs = registry.allBlockIDs  // sorted
let itemIDs = registry.allItemIDs    // sorted

// Get counts
print("Blocks: \(registry.blockCount)")
print("Items: \(registry.itemCount)")
```

---

## Common Patterns

### In a Task

```swift
Task {
    do {
        let blocks = try await dataManager.blocks()
        // Use blocks...
    } catch {
        print("Error: \(error)")
    }
}
```

### In an Async Function

```swift
func loadGameData() async throws {
    let blocks = try await dataManager.blocks()
    let items = try await dataManager.items()
    // Process...
}
```

### In SwiftUI

```swift
struct GameDataView: View {
    let dataManager: DataManager
    @State private var blocks: [LoadedDataDefinition<BlockDefinition>] = []
    
    var body: some View {
        List(blocks, id: \.id) { block in
            Text(block.value.displayName)
        }
        .task {
            do {
                blocks = try await dataManager.blocks()
            } catch {
                print("Failed to load: \(error)")
            }
        }
        .refreshable {
            _ = try? await dataManager.reload()
            blocks = try await dataManager.blocks()
        }
    }
}
```

### Concurrent Loading

```swift
// Load blocks and items concurrently
async let blocksTask = dataManager.blocks()
async let itemsTask = dataManager.items()

let (blocks, items) = try await (blocksTask, itemsTask)
```

### With Continuation (for callbacks)

```swift
func loadBlocks(completion: @escaping ([LoadedDataDefinition<BlockDefinition>]) -> Void) {
    Task {
        let blocks = try await dataManager.blocks()
        completion(blocks)
    }
}
```

---

## Error Handling

```swift
do {
    let blocks = try await dataManager.blocks()
    print("Loaded \(blocks.count) blocks")
} catch let error as NamespacedIDError {
    print("ID error: \(error.localizedDescription)")
} catch {
    print("Unknown error: \(error)")
}
```

---

## Testing

```swift
import XCTest
@testable import VGCore

final class MyTests: XCTestCase {
    func testLoadingBlocks() async throws {
        let packManager = PackManager(packsDirectory: testURL, coreVersion: "1.0")
        let dataManager = DataManager(packManager: packManager)
        
        let blocks = try await dataManager.blocks()
        XCTAssertFalse(blocks.isEmpty)
    }
}
```

---

## Migration Quick Tips

### Find & Replace Patterns

1. Find: `try dataManager.`  
   Replace: `try await dataManager.`

2. Find: `func.*DataManager.*throws`  
   Replace: Add `async` before `throws`

3. Find test methods using DataManager  
   Add: `async` to method signature

### Common Errors After Update

**Error:** "Expression is 'async' but is not marked with 'await'"  
**Fix:** Add `await` before the call

**Error:** "'async' call in a function that does not support concurrency"  
**Fix:** Make the containing function `async`

**Error:** "Cannot use instance member within property initializer"  
**Fix:** Move to `.task` or `.onAppear` in SwiftUI

---

## Performance Tips

1. **Cache the registry** for repeated lookups:
   ```swift
   let registry = try await dataManager.registry()
   // Now do many lookups without await
   let stone = registry.block(for: "minecraft:stone")
   let dirt = registry.block(for: "minecraft:dirt")
   ```

2. **Load concurrently** when possible:
   ```swift
   async let blocks = dataManager.blocks()
   async let items = dataManager.items()
   let (b, i) = try await (blocks, items)
   ```

3. **Validate once** at startup, not on every access:
   ```swift
   let issues = try await dataManager.validate()
   guard issues.isEmpty else {
       throw ValidationError(issues)
   }
   ```

---

## See Also

- `FIXES_APPLIED.md` - Details on what was fixed
- `IMPROVEMENTS.md` - Complete list of improvements
- `DataKit+Examples.swift` - Extensive code examples
- `MIGRATION_CHECKLIST.md` - Step-by-step migration guide
