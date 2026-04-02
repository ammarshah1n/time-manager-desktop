# CoreData Schema Migration Strategy

> Status: Implementation-ready spec
> Last updated: 2026-04-02
> Applies to: Timed macOS intelligence layer

---

## Context

Timed does NOT currently use CoreData. Persistence is split between:
- **Local:** `DataStore` actor writing JSON files to `~/Library/Application Support/Timed/`
- **Remote:** Supabase Postgres (project ref `fpmjuufefhtlwbfinxlx`)

This spec covers the migration path FROM the current JSON + Supabase setup TO a CoreData-backed local store as the intelligence model evolves. CoreData is the right move because:

1. The memory system (episodic/semantic/procedural) will grow to tens of thousands of records per user
2. JSON file I/O does not support indexed queries, partial loads, or relationship traversal
3. CoreData's NSPersistentHistoryTracking enables diff-based sync with Supabase
4. Background context support is required for the Haiku swarm agents writing concurrently

Supabase remains the remote source of truth. CoreData replaces the local JSON layer only.

---

## Schema Design Principles

### Version Numbering

Format: `TimedModel_MAJOR.MINOR`

- **MAJOR** increments when a heavyweight migration is required (entity removal, relationship restructure, type change on existing attribute)
- **MINOR** increments for lightweight migrations (new optional attribute, new entity, new relationship with default)

Initial version: `TimedModel_1.0`

Examples:
- `TimedModel_1.0` -> `TimedModel_1.1`: Add optional `embedding: [Float]?` to `EpisodicMemoryEntity`
- `TimedModel_1.1` -> `TimedModel_1.2`: New entity `DriftDetectionEntity`
- `TimedModel_1.2` -> `TimedModel_2.0`: Change `importanceScore` from `Float` to composite `ImportanceVector` (requires mapping model)

### Entity Map (v1.0)

```
EpisodicMemoryEntity
  id: UUID (indexed)
  timestamp: Date (indexed)
  source: String (enum raw value)
  category: String (enum raw value)
  content: String
  rawDataJSON: Data (Binary, external storage)
  importanceScore: Double
  embeddingData: Data? (Binary, external storage, 1024 floats)
  isConsolidated: Bool (indexed, default false)
  promotedToSemanticID: UUID?

SemanticFactEntity
  id: UUID (indexed)
  createdAt: Date
  updatedAt: Date
  category: String
  fact: String
  confidence: Double (indexed)
  evidenceCount: Int32
  sourceMemoryIDsJSON: Data
  embeddingData: Data?

ProceduralRuleEntity
  id: UUID (indexed)
  createdAt: Date
  updatedAt: Date
  triggerJSON: Data
  actionJSON: Data
  reasoning: String
  confidence: Double (indexed)
  activationCount: Int32
  sourceInsightIDsJSON: Data
  isActive: Bool (indexed, default true)

CoreMemoryEntity (singleton — max 1 row)
  executiveName: String
  role: String
  prioritiesJSON: Data
  projectsJSON: Data
  relationshipsJSON: Data
  chronotypeJSON: Data
  stressIndicatorsJSON: Data
  lastReflectionDate: Date

SignalEventEntity
  id: UUID (indexed)
  timestamp: Date (indexed)
  source: String
  eventType: String
  payloadJSON: Data (Binary, external storage)
  processed: Bool (indexed, default false)

ReflectionResultEntity
  id: UUID
  runDate: Date (indexed)
  tier: String (haiku/sonnet/opus)
  patternsJSON: Data
  insightsJSON: Data
  rulesGeneratedJSON: Data
  memoriesProcessedCount: Int32
  durationSeconds: Double

TaskEntity (replaces JSON-persisted TimedTask)
  id: UUID (indexed)
  title: String
  sender: String?
  estimatedMinutes: Int16
  bucket: String (indexed)
  priority: Int16
  dueAt: Date?
  isDone: Bool (indexed)
  ... (all existing TimedTask fields)

CalendarBlockEntity
  id: UUID (indexed)
  title: String
  start: Date (indexed)
  end: Date
  category: String

CompletionRecordEntity
  id: UUID
  taskId: UUID (indexed)
  bucket: String
  estimatedMinutes: Int16
  actualMinutes: Int16?
  completedAt: Date (indexed)
```

### Relationships (v1.0)

No CoreData relationships in v1.0. Cross-references use UUID foreign keys stored as attributes. Rationale:

1. The Supabase schema uses foreign keys, not CoreData-style relationships
2. UUID references are simpler to sync bidirectionally
3. Avoids cascade-delete complexity during early development
4. Relationships can be added in v2.0 as a heavyweight migration once the schema stabilises

### Indexes

Every entity has `id` indexed. Additional indexes:
- `EpisodicMemoryEntity`: `timestamp`, `isConsolidated`, `source`
- `SemanticFactEntity`: `confidence`, `category`
- `ProceduralRuleEntity`: `confidence`, `isActive`
- `SignalEventEntity`: `timestamp`, `processed`
- `CompletionRecordEntity`: `taskId`, `completedAt`
- `TaskEntity`: `bucket`, `isDone`
- `CalendarBlockEntity`: `start`

Compound indexes where CoreData supports them:
- `(source, timestamp)` on `EpisodicMemoryEntity`
- `(processed, timestamp)` on `SignalEventEntity`

---

## Migration Strategy

### When Lightweight Migration Applies

CoreData lightweight migration handles these changes automatically with zero code:

- Adding a new optional attribute (e.g., `voiceProsodyJSON: Data?` on `EpisodicMemoryEntity`)
- Adding a new entity (e.g., `ChronotypeProfileEntity`)
- Adding a relationship with a default value
- Making a required attribute optional
- Renaming an entity or attribute (with renaming identifier set in model editor)
- Widening a numeric type (Int16 -> Int32)

**Implementation:** Set `NSMigratePersistentStoresAutomaticallyOption` and `NSInferMappingModelAutomaticallyOption` to `true` on the persistent store description.

```swift
let description = NSPersistentStoreDescription()
description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
```

### When Heavyweight Migration Applies

Heavyweight (custom) migration is required when:

- Changing an attribute's type (e.g., `importanceScore: Float` -> `importanceVector: Data`)
- Splitting one entity into two (e.g., extracting `CoreMemoryEntity.relationshipsJSON` into a `RelationshipEntity`)
- Merging two entities into one
- Computing derived values during migration (e.g., backfilling embeddings)
- Removing an entity and redistributing its data

**Implementation:** Write an `NSMappingModel` with custom `NSEntityMigrationPolicy` subclasses.

### Migration Decision Matrix

| Change | Migration Type | Risk | Test Coverage Required |
|--------|---------------|------|----------------------|
| New optional attribute | Lightweight | None | Smoke test |
| New entity | Lightweight | None | Smoke test |
| Rename (with identifier) | Lightweight | Low | Verify data survives |
| Remove unused attribute | Lightweight | Low | Verify no code references |
| Change attribute type | Heavyweight | Medium | Full data preservation test |
| Split entity | Heavyweight | High | Row-count + data integrity |
| Merge entities | Heavyweight | High | Row-count + data integrity |
| Add relationship | Heavyweight (usually) | Medium | Relationship traversal test |
| Remove entity | Heavyweight | Critical | Full backup + restore test |

---

## Heavyweight Migration Implementation

### Mapping Model Structure

For each heavyweight migration, create:

1. **Source model:** `TimedModel_N.xcdatamodel` (the version being migrated FROM)
2. **Destination model:** `TimedModel_N+1.xcdatamodel` (the version being migrated TO)
3. **Mapping model:** `TimedModel_N_to_N+1.xcmappingmodel`
4. **Migration policy:** `TimedMigrationPolicy_N_to_N+1.swift` (subclass of `NSEntityMigrationPolicy`)

### Example: importanceScore Float -> ImportanceVector

```swift
class MigrationPolicy_1_2_to_2_0: NSEntityMigrationPolicy {
    override func createDestinationInstances(
        forSource sInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        let destination = NSEntityDescription.insertNewObject(
            forEntityName: mapping.destinationEntityName!,
            into: manager.destinationContext
        )

        // Carry forward all unchanged attributes
        for (key, _) in sInstance.entity.attributesByName where key != "importanceScore" {
            destination.setValue(sInstance.value(forKey: key), forKey: key)
        }

        // Transform importanceScore -> importanceVectorData
        let oldScore = sInstance.value(forKey: "importanceScore") as? Double ?? 0.5
        let vector = ImportanceVector(base: oldScore, contextual: oldScore, temporal: oldScore)
        let data = try JSONEncoder().encode(vector)
        destination.setValue(data, forKey: "importanceVectorData")

        manager.associate(sourceInstance: sInstance, withDestinationInstance: destination, for: mapping)
    }
}
```

### Multi-Step Migration

If a user skips multiple versions (e.g., app auto-updates from v1.0 to v2.0), CoreData needs to chain migrations: v1.0 -> v1.1 -> v1.2 -> v2.0.

**Implementation:** A `MigrationCoordinator` that:

1. Reads the store metadata to determine the current model version
2. Finds the chain of model versions from current to latest
3. Executes each migration step sequentially
4. Reports progress to the UI (important for large episodic memory stores)

```swift
actor MigrationCoordinator {
    enum MigrationStep {
        case lightweight(from: String, to: String)
        case heavyweight(from: String, to: String, mappingModel: NSMappingModel)
    }

    func requiredSteps(from currentVersion: String, to targetVersion: String) -> [MigrationStep] {
        // Walk the version graph from current to target
        // Return ordered list of steps
    }

    func execute(steps: [MigrationStep], storeURL: URL, onProgress: (Double) -> Void) async throws {
        for (index, step) in steps.enumerated() {
            onProgress(Double(index) / Double(steps.count))
            switch step {
            case .lightweight:
                // Automatic — CoreData handles it
                break
            case .heavyweight(_, _, let mappingModel):
                let manager = NSMigrationManager(
                    sourceModel: /* source */,
                    destinationModel: /* destination */
                )
                try manager.migrateStore(
                    from: storeURL,
                    type: .sqlite,
                    mapping: mappingModel,
                    to: tempURL,
                    type: .sqlite
                )
                // Swap files atomically
                try FileManager.default.replaceItem(at: storeURL, withItemAt: tempURL)
            }
        }
        onProgress(1.0)
    }
}
```

---

## Data Preservation Guarantee

**Absolute rule: no user intelligence is ever lost during migration.**

### Backup Before Migration

Before any migration executes:

1. Copy the entire `~/Library/Application Support/Timed/` directory to `~/Library/Application Support/Timed/Backups/pre-migration-{version}-{timestamp}/`
2. Verify the backup is complete (file count + total size match)
3. Only then begin migration
4. Keep the last 3 migration backups. Delete older ones.

```swift
func backupBeforeMigration(currentVersion: String) throws -> URL {
    let backupDir = timedSupportDir
        .appendingPathComponent("Backups")
        .appendingPathComponent("pre-migration-\(currentVersion)-\(ISO8601DateFormatter().string(from: Date()))")
    try FileManager.default.copyItem(at: timedSupportDir, to: backupDir)
    return backupDir
}
```

### Rollback Strategy

If migration fails at any step:

1. Log the failure with full error context via `TimedLogger`
2. Restore from the pre-migration backup
3. Present the user with a clear message: "Timed encountered an issue during an update. Your data is safe. Please restart."
4. On next launch, retry the migration
5. After 3 failed attempts, launch in read-only mode and surface a support contact

```swift
func attemptMigrationWithRollback() async throws {
    let backupURL = try backupBeforeMigration(currentVersion: currentModelVersion)

    do {
        let steps = requiredSteps(from: currentModelVersion, to: latestModelVersion)
        try await execute(steps: steps, storeURL: storeURL, onProgress: { _ in })
    } catch {
        TimedLogger.migration.error("Migration failed: \(error.localizedDescription)")
        try FileManager.default.removeItem(at: timedSupportDir)
        try FileManager.default.copyItem(at: backupURL, to: timedSupportDir)
        throw MigrationError.rolledBack(underlyingError: error)
    }
}
```

### Data Integrity Verification

After every migration, run integrity checks:

1. **Row count preservation:** Count rows per entity before and after. Must match (or exceed, if new entities were added).
2. **UUID continuity:** Sample 100 random UUIDs from the pre-migration backup, verify they exist post-migration.
3. **Semantic fact integrity:** Load all `SemanticFactEntity` records, verify `confidence` is in valid range [0.0, 1.0].
4. **Procedural rule integrity:** Load all `ProceduralRuleEntity` records, verify `triggerJSON` and `actionJSON` decode without error.
5. **Embedding preservation:** Sample 10 `EpisodicMemoryEntity` records with embeddings, verify embedding dimensionality is 1024.

```swift
func verifyMigrationIntegrity(preBackup: URL, postStore: NSPersistentContainer) throws {
    let preContext = loadContextFromBackup(preBackup)
    let postContext = postStore.viewContext

    // Row counts
    for entityName in postStore.managedObjectModel.entities.map(\.name!) {
        let preFetch = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let postFetch = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let preCount = try preContext.count(for: preFetch)
        let postCount = try postContext.count(for: postFetch)
        guard postCount >= preCount else {
            throw MigrationError.dataLoss(entity: entityName, expected: preCount, actual: postCount)
        }
    }

    // UUID sampling
    let sampleFetch = NSFetchRequest<NSManagedObject>(entityName: "EpisodicMemoryEntity")
    sampleFetch.fetchLimit = 100
    let preSamples = try preContext.fetch(sampleFetch)
    for sample in preSamples {
        let uuid = sample.value(forKey: "id") as! UUID
        let postFetch = NSFetchRequest<NSManagedObject>(entityName: "EpisodicMemoryEntity")
        postFetch.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        let count = try postContext.count(for: postFetch)
        guard count == 1 else {
            throw MigrationError.missingRecord(entity: "EpisodicMemoryEntity", id: uuid)
        }
    }
}
```

---

## JSON-to-CoreData Initial Migration

The first migration is special: moving from the current `DataStore` JSON files to CoreData.

### Strategy: Parallel Operation, Then Cutover

1. **Phase 1 (1 release):** CoreData stack initialised alongside DataStore. All writes go to both. Reads come from DataStore. This validates CoreData is storing correctly without user impact.

2. **Phase 2 (next release):** Reads switch to CoreData. DataStore becomes write-only backup. If CoreData reads fail, fall back to DataStore transparently.

3. **Phase 3 (release after):** DataStore writes removed. JSON files archived to backup directory. CoreData is the sole local store.

### Import Procedure

```swift
func importFromDataStore() async throws {
    let store = DataStore.shared

    let context = persistentContainer.newBackgroundContext()
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

    try await context.perform {
        // Tasks
        let tasks = try await store.loadTasks()
        for task in tasks {
            let entity = TaskEntity(context: context)
            entity.id = task.id
            entity.title = task.title
            // ... map all fields
        }

        // Completion records
        let records = try await store.loadCompletionRecords()
        for record in records {
            let entity = CompletionRecordEntity(context: context)
            entity.id = record.id
            // ... map all fields
        }

        // Calendar blocks, triage items, captures, etc.
        // Same pattern for each JSON file

        try context.save()
    }
}
```

---

## Supabase Sync Integration

CoreData's `NSPersistentHistoryTracking` provides change tokens that map cleanly to Supabase sync:

1. Enable persistent history tracking on the store description
2. After each local save, read the history transactions since last sync token
3. Batch changed objects into Supabase upserts
4. After successful remote write, advance the sync token

```swift
let description = NSPersistentStoreDescription()
description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
```

This replaces the current pattern where `SupabaseClient.swift` makes direct CRUD calls. Instead, local CoreData is always written first, then synced asynchronously.

---

## CI Migration Testing

### Test Matrix

Every model version change triggers these automated tests:

1. **Fresh install test:** Create store with latest model version. Verify all entities are accessible.
2. **Sequential migration test:** Start from v1.0, apply every migration step to latest. Verify integrity at each step.
3. **Skip migration test:** Start from v1.0, migrate directly to latest. Verify the chained migration works.
4. **Large dataset migration test:** Seed v1.0 store with 50,000 episodic memories, 500 semantic facts, 100 procedural rules. Migrate. Verify:
   - All records preserved
   - Migration completes in < 60 seconds
   - Memory usage stays under 500MB during migration
5. **Rollback test:** Force a migration failure mid-way. Verify backup restore works and app launches cleanly.
6. **Concurrent access test:** Start migration while a background context is writing. Verify no corruption.

### Test Implementation

```swift
import Testing

@Suite("CoreData Migration")
struct MigrationTests {

    @Test("Lightweight migration preserves all episodic memories")
    func lightweightPreservesEpisodic() async throws {
        let storeURL = createTempStoreWith(modelVersion: "1.0", episodicCount: 1000)
        let container = loadContainer(storeURL: storeURL, modelVersion: "1.1")
        let count = try container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "EpisodicMemoryEntity"))
        #expect(count == 1000)
    }

    @Test("Heavyweight migration transforms importanceScore to vector")
    func heavyweightTransformsImportance() async throws {
        let storeURL = createTempStoreWith(modelVersion: "1.2", episodicCount: 100)
        // Seed known importanceScore values
        seedImportanceScores(storeURL: storeURL, scores: [0.1, 0.5, 0.9])

        let container = loadContainer(storeURL: storeURL, modelVersion: "2.0")
        let memories = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "EpisodicMemoryEntity"))

        for memory in memories {
            let vectorData = memory.value(forKey: "importanceVectorData") as! Data
            let vector = try JSONDecoder().decode(ImportanceVector.self, from: vectorData)
            #expect(vector.base >= 0.0 && vector.base <= 1.0)
        }
    }

    @Test("Rollback restores previous state on failure")
    func rollbackWorks() async throws {
        let storeURL = createTempStoreWith(modelVersion: "1.0", episodicCount: 500)
        let coordinator = MigrationCoordinator()

        // Inject a failing migration step
        coordinator.injectFailure(atStep: 2)

        do {
            try await coordinator.attemptMigrationWithRollback()
            Issue.record("Should have thrown")
        } catch {
            // Verify original data is intact
            let container = loadContainer(storeURL: storeURL, modelVersion: "1.0")
            let count = try container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "EpisodicMemoryEntity"))
            #expect(count == 500)
        }
    }

    @Test("Migration performance: 50K records in under 60s", .timeLimit(.seconds(60)))
    func performanceTest() async throws {
        let storeURL = createTempStoreWith(modelVersion: "1.0", episodicCount: 50_000)
        let container = loadContainer(storeURL: storeURL, modelVersion: "2.0")
        let count = try container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "EpisodicMemoryEntity"))
        #expect(count == 50_000)
    }
}
```

### CI Pipeline

```yaml
# .github/workflows/migration-test.yml
name: CoreData Migration Tests
on:
  pull_request:
    paths:
      - '*.xcdatamodeld/**'
      - '**/Migration*.swift'
      - '**/MappingModel*'
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Run migration tests
        run: swift test --filter MigrationTests
```

---

## Version History (to be maintained)

| Version | Date | Type | Change | Migration |
|---------|------|------|--------|-----------|
| 1.0 | TBD | Initial | All entities, JSON import | N/A |

---

## Decision Log

| Decision | Rationale |
|----------|-----------|
| CoreData over SwiftData | SwiftData (macOS 14+) is too young. CoreData has battle-tested migration tooling, NSPersistentHistoryTracking, and reliable heavyweight migration support. SwiftData migration is not mature enough for a system where data loss is unacceptable. |
| UUID references over CoreData relationships | Simpler Supabase sync. Avoids cascade-delete foot guns. Can add relationships later as heavyweight migration. |
| External storage for embeddings and raw data | 1024-float embeddings are 4KB each. 50K memories = 200MB of embeddings. External storage keeps the SQLite file lean and query-fast. |
| Phased JSON-to-CoreData cutover | Zero-risk migration. If CoreData has bugs, the JSON fallback keeps the app working. |
| Backup before every migration | The data is the product's intelligence. Losing it is losing months of compounding. No acceptable risk tolerance. |
