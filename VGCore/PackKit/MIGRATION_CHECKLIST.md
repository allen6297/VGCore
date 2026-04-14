# DataKit Migration Checklist

Use this checklist to migrate your code to the improved DataKit.

## ☑️ Pre-Migration

- [ ] Ensure you're on Swift 5.9+ (for actor support)
- [ ] Back up your current code
- [ ] Note all places where DataManager is used
- [ ] Note all places where PackManager is used

## ☑️ Code Updates

### DataManager Calls

- [ ] Add `async` to functions that call DataManager
- [ ] Add `await` to all DataManager method calls
  - [ ] `dataManager.blocks()`
  - [ ] `dataManager.items()`
  - [ ] `dataManager.block(id:)`
  - [ ] `dataManager.item(id:)`
  - [ ] `dataManager.hasBlock(id:)`
  - [ ] `dataManager.hasItem(id:)`
  - [ ] `dataManager.registry()`
  - [ ] `dataManager.validate()`
  - [ ] `dataManager.reload()`

### PackManager Calls

- [ ] Add `async` to functions that call PackManager
- [ ] Add `await` to all PackManager method calls
  - [ ] `packManager.availablePacks()`
  - [ ] `packManager.compatiblePacks()`
  - [ ] `packManager.pack(id:)`
  - [ ] `packManager.activePacks()`
  - [ ] `packManager.reload()`

### Validation Error Handling

- [ ] Update `switch` statements on `DataValidationIssue` to handle `.invalidProperty`

```swift
switch issue {
case .duplicateDefinition(let id, let paths):
    // existing code
case .missingReference(let sourceID, let reference, let field):
    // existing code
case .invalidProperty(let id, let property, let value, let reason):
    // NEW: handle invalid property
}
```

## ☑️ Testing

- [ ] Run existing unit tests
- [ ] Test concurrent access scenarios
- [ ] Test data loading
- [ ] Test validation
- [ ] Test hot reloading
- [ ] Verify no race conditions

## ☑️ New Features (Optional)

Consider using these new features:

- [ ] Use `registry.allBlocks` to iterate all blocks
- [ ] Use `registry.allItems` to iterate all items
- [ ] Use `registry.blockCount`/`itemCount` for UI
- [ ] Use `registry.allBlockIDs`/`allItemIDs` for sorted iteration

## ☑️ Common Patterns

### Before & After Examples

#### Loading Data

**Before:**
```swift
func loadBlocks() throws {
    let blocks = try dataManager.blocks()
    self.blocks = blocks
}
```

**After:**
```swift
func loadBlocks() async throws {
    let blocks = try await dataManager.blocks()
    self.blocks = blocks
}
```

#### Button Action

**Before:**
```swift
Button("Load") {
    do {
        try loadData()
    } catch {
        print(error)
    }
}
```

**After:**
```swift
Button("Load") {
    Task {
        do {
            try await loadData()
        } catch {
            print(error)
        }
    }
}
```

#### SwiftUI View

**Before:**
```swift
struct MyView: View {
    @State private var blocks: [BlockDefinition] = []
    
    var body: some View {
        List(blocks, id: \.self) { block in
            Text(block.displayName)
        }
        .onAppear {
            blocks = try? dataManager.blocks()
        }
    }
}
```

**After:**
```swift
struct MyView: View {
    @State private var blocks: [BlockDefinition] = []
    
    var body: some View {
        List(blocks, id: \.self) { block in
            Text(block.displayName)
        }
        .task {
            blocks = try await dataManager.blocks()
        }
    }
}
```

## ☑️ Verification

- [ ] All compiler errors resolved
- [ ] All compiler warnings addressed
- [ ] Tests pass
- [ ] App runs without crashes
- [ ] No race condition warnings in Thread Sanitizer
- [ ] Documentation builds (if using DocC)

## ☑️ Cleanup

- [ ] Remove any temporary workarounds
- [ ] Update internal documentation
- [ ] Update team members
- [ ] Celebrate! 🎉

## Common Issues & Solutions

### Issue: "Expression is 'async' but is not marked with 'await'"

**Solution:** Add `await` before the call:
```swift
let blocks = try await dataManager.blocks()
```

### Issue: "'async' call in a function that does not support concurrency"

**Solution:** Make the containing function `async`:
```swift
func myFunction() async throws {
    // Now you can use await
}
```

### Issue: "Cannot use instance member within property initializer"

**Solution:** Move DataManager calls to `.task` or `.onAppear`:
```swift
struct MyView: View {
    @State private var blocks: [BlockDefinition] = []
    
    var body: some View {
        // ...
        .task {
            blocks = try? await dataManager.blocks()
        }
    }
}
```

### Issue: "Actor-isolated property 'blocks' cannot be referenced from a non-isolated context"

**Solution:** Use `await` to access actor-isolated members:
```swift
let blocks = await dataManager.blocks()
```

## Need Help?

- Check `DataKit+Examples.swift` for usage examples
- Review `IMPROVEMENTS.md` for detailed explanations
- Run tests in `DataKitTests.swift` to see working examples

---

**Estimated Migration Time:** 30 minutes - 2 hours depending on codebase size
