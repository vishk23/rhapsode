# Phase 0 — Fork Rebrand + Opt-in Voice Bank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand the freeflow fork and add an opt-in, local "Voice Bank" that durably saves `(audio, raw transcript)` pairs while you dictate — the training dataset — decoupled from the capped run history, with a Settings UI to view and delete it.

**Architecture:** The app is a single-module macOS app built by a raw `swiftc` invocation in the `Makefile` that globs `Sources/**/*.swift` — there is no test target. We add the Voice Bank's logic as **AppKit-free files under `Sources/VoiceBank/`** that (a) compile into the app via the existing glob and (b) compile as an isolated SwiftPM module for `swift test`. The dictation pipeline already saves each recording's WAV durably (`AppState.saveAudioFile` → `~/Library/Application Support/<App>/audio/`) and funnels every run through one method, `AppState.recordPipelineHistoryEntry`. The Voice Bank hooks there: when enabled and the clip passes a quality gate, it **copies** that WAV into its own `VoiceBank/` directory and records metadata in its own Core Data store — so the 20-entry history cap never trims training data.

**Tech Stack:** Swift 6.3 toolchain (building in Swift 5 language mode, like the app), SwiftUI, AVFoundation, Core Data (programmatic model, as the existing `PipelineHistoryStore` does), SwiftPM + XCTest for the testable core.

---

## File Structure

**New (Voice Bank core — AppKit-free, under `Sources/VoiceBank/`):**
- `Sources/VoiceBank/VoiceSample.swift` — the `(audio, transcript)` record model.
- `Sources/VoiceBank/VoiceBankMetrics.swift` — `wordCount` + `wavDurationSeconds` helpers.
- `Sources/VoiceBank/VoiceBankQualityGate.swift` — `VoiceSampleCandidate` + `shouldBank`.
- `Sources/VoiceBank/VoiceBankStore.swift` — Core Data metadata CRUD + stats.
- `Sources/VoiceBank/VoiceBank.swift` — façade: copy WAV + insert, list, stats, delete.

**New (test harness):**
- `Package.swift` — SwiftPM manifest building the `VoiceBank` module + tests only.
- `Tests/VoiceBankTests/*.swift` — XCTest cases for the core.

**Modified:**
- `Makefile` — rebrand defaults (`APP_NAME`, `BUNDLE_ID`, `CODESIGN_IDENTITY`); add `test` target.
- `Info.plist` — `CFBundle*` names/identifier + usage strings.
- `Sources/AppName.swift` — fallback display-name string.
- `.gitignore` — ignore `.build/` and `.swiftpm/`.
- `Sources/AppState.swift` — `voiceBankEnabled` setting; `voiceBank` property; hook in `recordPipelineHistoryEntry`; UI accessor methods.
- `Sources/SettingsView.swift` — a "Voice Bank" settings card.
- `Sources/MenuBarView.swift` — a "banking on" indicator line.

**Why these boundaries:** the core is pure logic with no AppKit imports, so it is unit-testable in isolation and reused verbatim by the app. The app integration is thin glue (one hook + accessors + UI), verified by building and running because there is no UI test harness.

---

## Conventions used throughout

- **Local build/run command** (ad-hoc signing, so no dev cert is required):
  `make CODESIGN_IDENTITY=- ARCH=$(uname -m)` then `make run CODESIGN_IDENTITY=- ARCH=$(uname -m)`.
- **Test command:** `swift test`.
- The chosen identifier is `com.vishk23.whisprfreeme` (release) / `com.vishk23.whisprfreeme.dev` (dev). Adjust if you pick a different name; nothing else depends on the literal string.

---

## Task 1: Rebrand build configuration

**Files:**
- Modify: `Makefile` (top defaults, lines 1-5)
- Modify: `Info.plist`
- Modify: `Sources/AppName.swift`

- [ ] **Step 1: Rebrand the Makefile defaults**

In `Makefile`, replace the first five assignment lines:

```make
APP_NAME ?= FreeFlow Dev
BUNDLE_ID ?= com.zachlatta.freeflow.dev
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= FreeFlow Dev
```

with:

```make
APP_NAME ?= Whispr Free Me Dev
BUNDLE_ID ?= com.vishk23.whisprfreeme.dev
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= -
```

Also update the dev-icon guard a few lines below so the dev icon still selects:

```make
ifeq ($(APP_NAME),FreeFlow Dev)
```

becomes

```make
ifeq ($(APP_NAME),Whispr Free Me Dev)
```

- [ ] **Step 2: Rebrand Info.plist**

In `Info.plist`, set `CFBundleName`, `CFBundleDisplayName`, and `CFBundleExecutable` to `Whispr Free Me`, set `CFBundleIdentifier` to `com.vishk23.whisprfreeme`, and update the three usage-description strings to start with "Whispr Free Me" instead of "FreeFlow". (The Makefile overwrites `CFBundleName`/`Identifier`/`Executable` per build from `APP_NAME`/`BUNDLE_ID`, but the source plist should match so non-Makefile reads are correct.)

- [ ] **Step 3: Rebrand the AppName fallback**

In `Sources/AppName.swift`, change the fallback string:

```swift
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FreeFlow"
```

to:

```swift
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Whispr Free Me"
```

- [ ] **Step 4: Build and run to verify the rebrand**

Run: `make run CODESIGN_IDENTITY=- ARCH=$(uname -m)`
Expected: compiles with no errors; a menu-bar app launches whose menu/app name reads "Whispr Free Me Dev". (Grant mic/accessibility if macOS prompts.)

- [ ] **Step 5: Commit**

```bash
git add Makefile Info.plist Sources/AppName.swift
git commit -m "chore: rebrand fork to Whispr Free Me"
```

---

## Task 2: SwiftPM test harness for the Voice Bank module

**Files:**
- Create: `Package.swift`
- Create: `Sources/VoiceBank/VoiceBankPlaceholder.swift` (temporary, removed in Task 3)
- Create: `Tests/VoiceBankTests/HarnessTests.swift`
- Modify: `.gitignore`
- Modify: `Makefile` (add `test` target)

- [ ] **Step 1: Write the SwiftPM manifest**

Create `Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceBank",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "VoiceBank", path: "Sources/VoiceBank"),
        .testTarget(
            name: "VoiceBankTests",
            dependencies: ["VoiceBank"],
            path: "Tests/VoiceBankTests"
        ),
    ]
)
```

This compiles **only** `Sources/VoiceBank/` and `Tests/VoiceBankTests/`. The rest of `Sources/` is invisible to SwiftPM, so the AppKit/SwiftUI app code is never pulled into `swift test`. The `Makefile` app build is unaffected (it does not read `Package.swift`).

- [ ] **Step 2: Add a placeholder source so the module is non-empty**

Create `Sources/VoiceBank/VoiceBankPlaceholder.swift`:

```swift
enum VoiceBankPlaceholder {
    static let ok = true
}
```

- [ ] **Step 3: Write a trivial failing test**

Create `Tests/VoiceBankTests/HarnessTests.swift`:

```swift
import XCTest
@testable import VoiceBank

final class HarnessTests: XCTestCase {
    func testHarnessRuns() {
        XCTAssertTrue(VoiceBankPlaceholder.ok)
    }
}
```

- [ ] **Step 4: Run the test to verify the harness works**

Run: `swift test`
Expected: builds the `VoiceBank` module + tests, runs `testHarnessRuns`, prints "Test Suite 'All tests' passed" with 1 test.

- [ ] **Step 5: Ignore SwiftPM build artifacts**

Append to `.gitignore`:

```
.build/
.swiftpm/
```

- [ ] **Step 6: Add a `make test` convenience target**

In `Makefile`, add to the `.PHONY` line (append `test`) and add this target at the end:

```make
test:
	swift test
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/VoiceBank/VoiceBankPlaceholder.swift Tests/VoiceBankTests/HarnessTests.swift .gitignore Makefile
git commit -m "test: add SwiftPM harness for the VoiceBank module"
```

---

## Task 3: Metrics helpers (`wordCount`, `wavDurationSeconds`)

**Files:**
- Create: `Sources/VoiceBank/VoiceBankMetrics.swift`
- Create: `Tests/VoiceBankTests/VoiceBankMetricsTests.swift`
- Delete: `Sources/VoiceBank/VoiceBankPlaceholder.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/VoiceBankTests/VoiceBankMetricsTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import VoiceBank

final class VoiceBankMetricsTests: XCTestCase {
    func testWordCountCountsWhitespaceSeparatedTokens() {
        XCTAssertEqual(VoiceBankMetrics.wordCount("hello there world"), 3)
        XCTAssertEqual(VoiceBankMetrics.wordCount("  spaced   out \n words "), 3)
        XCTAssertEqual(VoiceBankMetrics.wordCount(""), 0)
        XCTAssertEqual(VoiceBankMetrics.wordCount("   "), 0)
    }

    func testWavDurationMatchesWrittenFrames() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
        )!
        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(8_000) // 0.5s at 16 kHz
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file!.write(from: buffer)
        file = nil // flush + close before reading

        let duration = VoiceBankMetrics.wavDurationSeconds(at: url)
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 0.5, accuracy: 0.05)

        XCTAssertNil(VoiceBankMetrics.wavDurationSeconds(
            at: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).wav")
        ))
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VoiceBankMetricsTests`
Expected: FAIL — `cannot find 'VoiceBankMetrics' in scope`.

- [ ] **Step 3: Implement the helpers**

Delete the placeholder: `rm Sources/VoiceBank/VoiceBankPlaceholder.swift`

Create `Sources/VoiceBank/VoiceBankMetrics.swift`:

```swift
import AVFoundation
import Foundation

enum VoiceBankMetrics {
    /// Number of whitespace/newline-separated word tokens in a transcript.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Duration in seconds of a PCM/WAV file, or nil if it cannot be read.
    static func wavDurationSeconds(at url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return Double(file.length) / sampleRate
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter VoiceBankMetricsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceBank/VoiceBankMetrics.swift Tests/VoiceBankTests/VoiceBankMetricsTests.swift
git rm Sources/VoiceBank/VoiceBankPlaceholder.swift
git commit -m "feat: add VoiceBank metrics helpers (word count, wav duration)"
```

---

## Task 4: Sample model + quality gate

**Files:**
- Create: `Sources/VoiceBank/VoiceSample.swift`
- Create: `Sources/VoiceBank/VoiceBankQualityGate.swift`
- Create: `Tests/VoiceBankTests/VoiceBankQualityGateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/VoiceBankTests/VoiceBankQualityGateTests.swift`:

```swift
import XCTest
@testable import VoiceBank

final class VoiceBankQualityGateTests: XCTestCase {
    private func candidate(
        transcript: String = "this is a real sentence",
        intent: String = "dictation",
        duration: Double = 2.0
    ) -> VoiceSampleCandidate {
        VoiceSampleCandidate(transcript: transcript, intent: intent, durationSeconds: duration)
    }

    func testAcceptsGoodDictation() {
        XCTAssertTrue(VoiceBankQualityGate.shouldBank(candidate()))
    }

    func testRejectsNonDictationIntent() {
        XCTAssertFalse(VoiceBankQualityGate.shouldBank(candidate(intent: "command:automatic")))
        XCTAssertFalse(VoiceBankQualityGate.shouldBank(candidate(intent: "command:manual")))
    }

    func testRejectsEmptyOrWhitespaceTranscript() {
        XCTAssertFalse(VoiceBankQualityGate.shouldBank(candidate(transcript: "")))
        XCTAssertFalse(VoiceBankQualityGate.shouldBank(candidate(transcript: "   \n ")))
    }

    func testRejectsTooFewWords() {
        XCTAssertFalse(VoiceBankQualityGate.shouldBank(candidate(transcript: "hi")))
    }

    func testRejectsTooShortAudio() {
        XCTAssertFalse(VoiceBankQualityGate.shouldBank(candidate(duration: 0.3)))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VoiceBankQualityGateTests`
Expected: FAIL — `cannot find 'VoiceSampleCandidate' / 'VoiceBankQualityGate' in scope`.

- [ ] **Step 3: Implement the model and gate**

Create `Sources/VoiceBank/VoiceSample.swift`:

```swift
import Foundation

/// One durably-banked (audio, transcript) training pair.
struct VoiceSample: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let audioFileName: String
    let transcript: String
    let durationMs: Int
    let sampleRate: Int
    let wordCount: Int
    let appBundleId: String?

    init(
        id: UUID = UUID(),
        createdAt: Date,
        audioFileName: String,
        transcript: String,
        durationMs: Int,
        sampleRate: Int,
        wordCount: Int,
        appBundleId: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audioFileName = audioFileName
        self.transcript = transcript
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.wordCount = wordCount
        self.appBundleId = appBundleId
    }
}
```

Create `Sources/VoiceBank/VoiceBankQualityGate.swift`:

```swift
import Foundation

/// The minimal facts the gate needs to judge a clip, independent of storage.
struct VoiceSampleCandidate {
    let transcript: String
    let intent: String
    let durationSeconds: Double
}

/// Decides whether a finished dictation is worth banking for training.
enum VoiceBankQualityGate {
    static let minWords = 2
    static let minSeconds = 0.8

    static func shouldBank(_ candidate: VoiceSampleCandidate) -> Bool {
        guard candidate.intent == "dictation" else { return false }
        guard candidate.durationSeconds >= minSeconds else { return false }
        let trimmed = candidate.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard VoiceBankMetrics.wordCount(trimmed) >= minWords else { return false }
        return true
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter VoiceBankQualityGateTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceBank/VoiceSample.swift Sources/VoiceBank/VoiceBankQualityGate.swift Tests/VoiceBankTests/VoiceBankQualityGateTests.swift
git commit -m "feat: add VoiceSample model and banking quality gate"
```

---

## Task 5: Core Data metadata store

**Files:**
- Create: `Sources/VoiceBank/VoiceBankStore.swift`
- Create: `Tests/VoiceBankTests/VoiceBankStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/VoiceBankTests/VoiceBankStoreTests.swift`:

```swift
import XCTest
@testable import VoiceBank

final class VoiceBankStoreTests: XCTestCase {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("VoiceBank.sqlite")
    }

    private func sample(
        transcript: String = "a banked sentence",
        durationMs: Int = 2000,
        words: Int = 3
    ) -> VoiceSample {
        VoiceSample(
            createdAt: Date(),
            audioFileName: UUID().uuidString + ".wav",
            transcript: transcript,
            durationMs: durationMs,
            sampleRate: 16_000,
            wordCount: words,
            appBundleId: "com.apple.TextEdit"
        )
    }

    func testInsertAndListRoundTrips() throws {
        let store = VoiceBankStore(storeURL: tempStoreURL())
        let s = sample()
        try store.insert(s)
        let all = store.allSamples()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, s.id)
        XCTAssertEqual(all.first?.transcript, "a banked sentence")
        XCTAssertEqual(all.first?.durationMs, 2000)
    }

    func testStatsSummarizesCountAndDuration() throws {
        let store = VoiceBankStore(storeURL: tempStoreURL())
        try store.insert(sample(durationMs: 1000))
        try store.insert(sample(durationMs: 2500))
        let stats = store.stats()
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.totalDurationMs, 3500)
    }

    func testDeleteReturnsAudioFileNameAndRemovesRow() throws {
        let store = VoiceBankStore(storeURL: tempStoreURL())
        let s = sample()
        try store.insert(s)
        let removed = try store.delete(id: s.id)
        XCTAssertEqual(removed, s.audioFileName)
        XCTAssertEqual(store.allSamples().count, 0)
    }

    func testDeleteAllReturnsEveryAudioFileName() throws {
        let store = VoiceBankStore(storeURL: tempStoreURL())
        let a = sample(), b = sample()
        try store.insert(a)
        try store.insert(b)
        let removed = try store.deleteAll()
        XCTAssertEqual(Set(removed), Set([a.audioFileName, b.audioFileName]))
        XCTAssertEqual(store.allSamples().count, 0)
    }

    func testDataPersistsAcrossStoreReopen() throws {
        let url = tempStoreURL()
        let s = sample()
        do {
            let store = VoiceBankStore(storeURL: url)
            try store.insert(s)
        }
        let reopened = VoiceBankStore(storeURL: url)
        XCTAssertEqual(reopened.allSamples().first?.id, s.id)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VoiceBankStoreTests`
Expected: FAIL — `cannot find 'VoiceBankStore' in scope`.

- [ ] **Step 3: Implement the store**

Create `Sources/VoiceBank/VoiceBankStore.swift` (mirrors the programmatic-model approach of `Sources/PipelineHistoryStore.swift`):

```swift
import CoreData
import Foundation

struct VoiceBankStats: Equatable {
    let count: Int
    let totalDurationMs: Int
}

/// Core Data metadata store for banked samples. Owns its own SQLite file,
/// fully independent of PipelineHistoryStore and its 20-entry trim.
final class VoiceBankStore {
    private let container: NSPersistentContainer
    private let isLoaded: Bool

    /// - Parameter storeURL: on-disk SQLite location, or nil for in-memory.
    init(storeURL: URL?) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "VoiceBank", managedObjectModel: model)

        let description: NSPersistentStoreDescription
        if let storeURL {
            try? FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            description = NSPersistentStoreDescription(url: storeURL)
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        } else {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        }
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        isLoaded = (loadError == nil)
    }

    func insert(_ sample: VoiceSample) throws {
        guard isLoaded else { return }
        var thrown: Error?
        container.viewContext.performAndWait {
            let entity = VoiceSampleEntry(context: container.viewContext)
            entity.id = sample.id
            entity.createdAt = sample.createdAt
            entity.audioFileName = sample.audioFileName
            entity.transcript = sample.transcript
            entity.durationMs = Int64(sample.durationMs)
            entity.sampleRate = Int64(sample.sampleRate)
            entity.wordCount = Int64(sample.wordCount)
            entity.appBundleId = sample.appBundleId
            do { try container.viewContext.save() }
            catch { thrown = error; container.viewContext.rollback() }
        }
        if let thrown { throw thrown }
    }

    func allSamples() -> [VoiceSample] {
        guard isLoaded else { return [] }
        var result: [VoiceSample] = []
        container.viewContext.performAndWait {
            let request = NSFetchRequest<VoiceSampleEntry>(entityName: "VoiceSampleEntry")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            guard let entities = try? container.viewContext.fetch(request) else { return }
            result = entities.map(Self.makeSample(from:))
        }
        return result
    }

    func stats() -> VoiceBankStats {
        let all = allSamples()
        return VoiceBankStats(
            count: all.count,
            totalDurationMs: all.reduce(0) { $0 + $1.durationMs }
        )
    }

    /// Deletes one sample, returning its audio file name so the caller can
    /// remove the WAV. Returns nil if no such row exists.
    func delete(id: UUID) throws -> String? {
        guard isLoaded else { return nil }
        var removed: String?
        var thrown: Error?
        container.viewContext.performAndWait {
            let request = NSFetchRequest<VoiceSampleEntry>(entityName: "VoiceSampleEntry")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            do {
                guard let entity = try container.viewContext.fetch(request).first else { return }
                removed = entity.audioFileName
                container.viewContext.delete(entity)
                try container.viewContext.save()
            } catch { thrown = error; container.viewContext.rollback() }
        }
        if let thrown { throw thrown }
        return removed
    }

    /// Deletes every sample, returning all audio file names to remove.
    func deleteAll() throws -> [String] {
        guard isLoaded else { return [] }
        var removed: [String] = []
        var thrown: Error?
        container.viewContext.performAndWait {
            let request = NSFetchRequest<VoiceSampleEntry>(entityName: "VoiceSampleEntry")
            do {
                let entities = try container.viewContext.fetch(request)
                removed = entities.compactMap(\.audioFileName)
                for entity in entities { container.viewContext.delete(entity) }
                try container.viewContext.save()
            } catch { thrown = error; container.viewContext.rollback() }
        }
        if let thrown { throw thrown }
        return removed
    }

    private static func makeSample(from entity: VoiceSampleEntry) -> VoiceSample {
        VoiceSample(
            id: entity.id,
            createdAt: entity.createdAt ?? Date(),
            audioFileName: entity.audioFileName ?? "",
            transcript: entity.transcript ?? "",
            durationMs: Int(entity.durationMs),
            sampleRate: Int(entity.sampleRate),
            wordCount: Int(entity.wordCount),
            appBundleId: entity.appBundleId
        )
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "VoiceSampleEntry"
        entity.managedObjectClassName = NSStringFromClass(VoiceSampleEntry.self)

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            return a
        }

        entity.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("createdAt", .dateAttributeType, optional: false),
            attribute("audioFileName", .stringAttributeType, optional: false),
            attribute("transcript", .stringAttributeType, optional: false),
            attribute("durationMs", .integer64AttributeType, optional: false),
            attribute("sampleRate", .integer64AttributeType, optional: false),
            attribute("wordCount", .integer64AttributeType, optional: false),
            attribute("appBundleId", .stringAttributeType, optional: true),
        ]
        model.entities = [entity]
        return model
    }
}

@objc(VoiceSampleEntry)
final class VoiceSampleEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var createdAt: Date?
    @NSManaged var audioFileName: String?
    @NSManaged var transcript: String?
    @NSManaged var durationMs: Int64
    @NSManaged var sampleRate: Int64
    @NSManaged var wordCount: Int64
    @NSManaged var appBundleId: String?
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter VoiceBankStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceBank/VoiceBankStore.swift Tests/VoiceBankTests/VoiceBankStoreTests.swift
git commit -m "feat: add VoiceBankStore (decoupled Core Data metadata store)"
```

---

## Task 6: VoiceBank façade (copy + insert + manage)

**Files:**
- Create: `Sources/VoiceBank/VoiceBank.swift`
- Create: `Tests/VoiceBankTests/VoiceBankTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/VoiceBankTests/VoiceBankTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import VoiceBank

final class VoiceBankTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a mono 16 kHz PCM16 WAV of the given duration and returns its URL.
    private func makeWav(seconds: Double, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(UUID().uuidString + ".wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
        )!
        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file!.write(from: buffer)
        file = nil
        return url
    }

    func testBanksEligibleClipCopyingAudioAndRecordingMetadata() throws {
        let base = tempDir()
        let source = try makeWav(seconds: 1.5, in: tempDir())
        let bank = VoiceBank(baseDirectory: base)

        let sample = bank.bankIfEligible(
            sourceWavURL: source,
            transcript: "this is a banked sentence",
            intent: "dictation",
            appBundleId: "com.apple.TextEdit"
        )

        let saved = try XCTUnwrap(sample)
        XCTAssertEqual(bank.allSamples().count, 1)
        XCTAssertEqual(saved.wordCount, 5)
        XCTAssertEqual(saved.appBundleId, "com.apple.TextEdit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bank.audioURL(for: saved).path))
        // The bank keeps its own copy, separate from the source.
        XCTAssertNotEqual(bank.audioURL(for: saved).path, source.path)
    }

    func testIneligibleClipBanksNothing() throws {
        let base = tempDir()
        let bank = VoiceBank(baseDirectory: base)

        // wrong intent
        XCTAssertNil(bank.bankIfEligible(
            sourceWavURL: try makeWav(seconds: 1.5, in: tempDir()),
            transcript: "hello there friend", intent: "command:automatic", appBundleId: nil
        ))
        // empty transcript
        XCTAssertNil(bank.bankIfEligible(
            sourceWavURL: try makeWav(seconds: 1.5, in: tempDir()),
            transcript: "   ", intent: "dictation", appBundleId: nil
        ))
        // too short
        XCTAssertNil(bank.bankIfEligible(
            sourceWavURL: try makeWav(seconds: 0.3, in: tempDir()),
            transcript: "hello there friend", intent: "dictation", appBundleId: nil
        ))

        XCTAssertEqual(bank.allSamples().count, 0)
        let contents = try FileManager.default.contentsOfDirectory(
            atPath: bank.audioDirectory.path
        ).filter { $0.hasSuffix(".wav") }
        XCTAssertEqual(contents, [])
    }

    func testDeleteRemovesRowAndFile() throws {
        let base = tempDir()
        let bank = VoiceBank(baseDirectory: base)
        let saved = try XCTUnwrap(bank.bankIfEligible(
            sourceWavURL: try makeWav(seconds: 1.5, in: tempDir()),
            transcript: "delete me please now", intent: "dictation", appBundleId: nil
        ))
        let url = bank.audioURL(for: saved)
        bank.delete(id: saved.id)
        XCTAssertEqual(bank.allSamples().count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteAllEmptiesStoreAndDirectory() throws {
        let base = tempDir()
        let bank = VoiceBank(baseDirectory: base)
        _ = bank.bankIfEligible(
            sourceWavURL: try makeWav(seconds: 1.5, in: tempDir()),
            transcript: "first banked sentence", intent: "dictation", appBundleId: nil
        )
        _ = bank.bankIfEligible(
            sourceWavURL: try makeWav(seconds: 1.5, in: tempDir()),
            transcript: "second banked sentence", intent: "dictation", appBundleId: nil
        )
        XCTAssertEqual(bank.stats().count, 2)
        bank.deleteAll()
        XCTAssertEqual(bank.stats().count, 0)
        let wavs = try FileManager.default.contentsOfDirectory(atPath: bank.audioDirectory.path)
            .filter { $0.hasSuffix(".wav") }
        XCTAssertEqual(wavs, [])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VoiceBankTests`
Expected: FAIL — `cannot find 'VoiceBank' in scope`.

- [ ] **Step 3: Implement the façade**

Create `Sources/VoiceBank/VoiceBank.swift`:

```swift
import Foundation

/// Single entry point the app uses to bank dictations and manage the dataset.
/// Owns a `VoiceBank/` directory (audio copies + its own SQLite store) under
/// the given base directory.
final class VoiceBank {
    let audioDirectory: URL
    private let store: VoiceBankStore
    private let fileManager = FileManager.default

    init(baseDirectory: URL) {
        let bankDir = baseDirectory.appendingPathComponent("VoiceBank", isDirectory: true)
        try? FileManager.default.createDirectory(at: bankDir, withIntermediateDirectories: true)
        audioDirectory = bankDir
        store = VoiceBankStore(storeURL: bankDir.appendingPathComponent("VoiceBank.sqlite"))
    }

    /// Copies the WAV and records metadata when the clip passes the quality
    /// gate. Returns the banked sample, or nil if skipped or on I/O failure.
    @discardableResult
    func bankIfEligible(
        sourceWavURL: URL,
        transcript: String,
        intent: String,
        appBundleId: String?,
        sampleRate: Int = 16_000
    ) -> VoiceSample? {
        let duration = VoiceBankMetrics.wavDurationSeconds(at: sourceWavURL) ?? 0
        let candidate = VoiceSampleCandidate(
            transcript: transcript, intent: intent, durationSeconds: duration
        )
        guard VoiceBankQualityGate.shouldBank(candidate) else { return nil }

        let fileName = UUID().uuidString + ".wav"
        let destination = audioDirectory.appendingPathComponent(fileName)
        do {
            try fileManager.copyItem(at: sourceWavURL, to: destination)
        } catch {
            return nil
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = VoiceSample(
            createdAt: Date(),
            audioFileName: fileName,
            transcript: trimmed,
            durationMs: Int(duration * 1000),
            sampleRate: sampleRate,
            wordCount: VoiceBankMetrics.wordCount(trimmed),
            appBundleId: appBundleId
        )
        do {
            try store.insert(sample)
        } catch {
            try? fileManager.removeItem(at: destination)
            return nil
        }
        return sample
    }

    func allSamples() -> [VoiceSample] { store.allSamples() }

    func stats() -> VoiceBankStats { store.stats() }

    func audioURL(for sample: VoiceSample) -> URL {
        audioDirectory.appendingPathComponent(sample.audioFileName)
    }

    func delete(id: UUID) {
        do {
            if let fileName = try store.delete(id: id) {
                try? fileManager.removeItem(at: audioDirectory.appendingPathComponent(fileName))
            }
        } catch { }
    }

    func deleteAll() {
        let names = (try? store.deleteAll()) ?? []
        for name in names {
            try? fileManager.removeItem(at: audioDirectory.appendingPathComponent(name))
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test`
Expected: PASS — the full suite (harness + metrics + gate + store + façade), all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceBank/VoiceBank.swift Tests/VoiceBankTests/VoiceBankTests.swift
git commit -m "feat: add VoiceBank façade (copy audio + record metadata + manage)"
```

---

## Task 7: Wire the Voice Bank into AppState

**Files:**
- Modify: `Sources/AppState.swift`

No new unit tests (this is MainActor app glue with no test harness); verified by `swift test` still passing, a clean `make` build, and a manual dictation check.

- [ ] **Step 1: Add the opt-in setting**

In `Sources/AppState.swift`, near the other `@Published` settings (around line 491 where `preserveClipboard` is declared), add the storage key and property:

```swift
    private let voiceBankEnabledStorageKey = "voiceBankEnabled"

    @Published var voiceBankEnabled: Bool {
        didSet {
            UserDefaults.standard.set(voiceBankEnabled, forKey: voiceBankEnabledStorageKey)
        }
    }
```

- [ ] **Step 2: Initialize the setting in `init`**

In the `AppState` initializer, alongside the other setting assignments (near line 728 where `self.preserveClipboard = preserveClipboard`), add:

```swift
        self.voiceBankEnabled = UserDefaults.standard.bool(forKey: voiceBankEnabledStorageKey)
```

(`UserDefaults.bool(forKey:)` defaults to `false` when unset — banking is off by default, preserving the privacy invariant.)

- [ ] **Step 3: Add the base-directory helper and the VoiceBank property**

Near `audioStorageDirectory()` (line 1001), add a sibling helper:

```swift
    static func appSupportBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppName.displayName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
```

Near the `pipelineHistoryStore` property (line 583), add:

```swift
    private let voiceBank = VoiceBank(baseDirectory: AppState.appSupportBaseDirectory())
```

- [ ] **Step 4: Hook banking into `recordPipelineHistoryEntry`**

In `recordPipelineHistoryEntry` (line 2711), inside the `do` block, immediately after `pipelineHistory = pipelineHistoryStore.loadAllHistory()` (line 2749) and before the closing `}` of the `do`, add:

```swift
            if voiceBankEnabled,
               intent.persistedIntent == .dictation,
               let audioFileName {
                let sourceURL = Self.audioStorageDirectory().appendingPathComponent(audioFileName)
                let transcript = rawTranscript
                let bundleId = context.bundleIdentifier
                let bank = voiceBank
                DispatchQueue.global(qos: .utility).async {
                    bank.bankIfEligible(
                        sourceWavURL: sourceURL,
                        transcript: transcript,
                        intent: PipelineHistoryItemIntent.dictation.rawValue,
                        appBundleId: bundleId
                    )
                }
            }
```

This runs off the main thread so it never adds latency to paste. It copies from the already-saved `audio/` WAV into the decoupled `VoiceBank/` directory; the quality gate inside `bankIfEligible` rejects empty/short/non-dictation clips (so the error path, which passes an empty `rawTranscript`, banks nothing).

- [ ] **Step 5: Add UI accessor methods**

So `SettingsView` can read/manage the bank without exposing the private property, add these methods to `AppState` (anywhere among its instance methods, e.g. after `clearPipelineHistory`):

```swift
    func voiceBankStats() -> VoiceBankStats { voiceBank.stats() }

    func voiceBankSamples() -> [VoiceSample] { voiceBank.allSamples() }

    func voiceBankAudioURL(for sample: VoiceSample) -> URL { voiceBank.audioURL(for: sample) }

    var voiceBankDirectory: URL { voiceBank.audioDirectory }

    func deleteVoiceSample(id: UUID) { voiceBank.delete(id: id) }

    func deleteAllVoiceBank() { voiceBank.deleteAll() }
```

- [ ] **Step 6: Verify build + tests**

Run: `swift test`
Expected: full suite still PASS (no core regressions).

Run: `make CODESIGN_IDENTITY=- ARCH=$(uname -m)`
Expected: app compiles cleanly.

- [ ] **Step 7: Manual functional check**

```bash
defaults write com.vishk23.whisprfreeme.dev voiceBankEnabled -bool YES
make run CODESIGN_IDENTITY=- ARCH=$(uname -m)
```

Dictate a full sentence into any text field, then:

```bash
ls "$HOME/Library/Application Support/Whispr Free Me Dev/VoiceBank/"
```

Expected: a `.wav` file plus `VoiceBank.sqlite`. Then set the default back to `NO`, dictate again, and confirm no new `.wav` appears (the privacy invariant).

- [ ] **Step 8: Commit**

```bash
git add Sources/AppState.swift
git commit -m "feat: bank dictations to the Voice Bank when enabled"
```

---

## Task 8: Voice Bank settings UI

**Files:**
- Modify: `Sources/SettingsView.swift`

Build-verified (SwiftUI, no UI test harness). Follow the existing `SettingsCard` pattern (see the card at `SettingsView.swift:672`) and the existing history list that already plays audio via `AudioPlayerView` (`SettingsView.swift:2081-2111`, component defined at `:2416`).

- [ ] **Step 1: Add a "Voice Bank" card**

Add a new `SettingsCard` in the settings layout (place it near the run-history/audio section so related controls are together). Bind to the existing settings `appState` object. Use this content:

```swift
SettingsCard("Voice Bank", icon: "waveform.badge.mic") {
    Toggle(isOn: $appState.voiceBankEnabled) {
        Text("Save my voice locally to build a training dataset")
    }

    Text("""
    When on, Whispr Free Me keeps a local copy of the audio and the exact words \
    of each dictation in Application Support. Nothing is uploaded. Turn it off \
    any time, and delete what you've collected below.
    """)
    .font(.caption)
    .foregroundStyle(.secondary)

    let stats = appState.voiceBankStats()
    HStack {
        Text("\(stats.count) samples")
        Spacer()
        Text(String(format: "%.1f min banked", Double(stats.totalDurationMs) / 60_000.0))
    }
    .font(.caption.monospacedDigit())

    HStack {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([appState.voiceBankDirectory])
        }
        Spacer()
        Button("Delete All", role: .destructive) {
            appState.deleteAllVoiceBank()
        }
        .disabled(stats.count == 0)
    }
}
```

If `SettingsView` does not already `import AppKit`, add it (needed for `NSWorkspace`); it is almost certainly imported transitively via SwiftUI, but verify.

- [ ] **Step 2: Add a basic sample list (browse + play + delete per item)**

Below the card (or inside it under a `Divider()`), add a simple list reusing the existing `AudioPlayerView`:

```swift
ForEach(appState.voiceBankSamples()) { sample in
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(sample.transcript)
                .lineLimit(2)
                .font(.callout)
            Spacer()
            Button(role: .destructive) {
                appState.deleteVoiceSample(id: sample.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        HStack(spacing: 8) {
            Text(String(format: "%.1fs", Double(sample.durationMs) / 1000.0))
            Text("\(sample.wordCount) words")
            if let app = sample.appBundleId { Text(app) }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)

        AudioPlayerView(audioURL: appState.voiceBankAudioURL(for: sample))
    }
    .padding(.vertical, 4)
}
```

Note: this list reads `voiceBankSamples()` once per render. That is fine for Phase 0; a future phase can make it observe changes reactively.

- [ ] **Step 3: Verify build + run**

Run: `make run CODESIGN_IDENTITY=- ARCH=$(uname -m)`
Expected: Settings shows a "Voice Bank" card. Toggle it on, dictate a sentence, reopen Settings — the count increments and the sample appears with a working play button. "Delete All" empties it.

- [ ] **Step 4: Commit**

```bash
git add Sources/SettingsView.swift
git commit -m "feat: add Voice Bank settings card (toggle, stats, browse, delete)"
```

---

## Task 9: Menu-bar "banking on" indicator

**Files:**
- Modify: `Sources/MenuBarView.swift`

A small visible indicator that banking is active — a privacy affordance, so it is never silently recording your dataset.

- [ ] **Step 1: Add an indicator row**

In `Sources/MenuBarView.swift`, within the menu content and using the existing `appState` reference, add a conditional row (place it near other status rows; match the surrounding style):

```swift
if appState.voiceBankEnabled {
    Label("Voice Bank: on (\(appState.voiceBankStats().count))", systemImage: "waveform.badge.mic")
        .font(.caption)
}
```

If the surrounding menu uses AppKit `NSMenuItem`s rather than SwiftUI, instead add a disabled `NSMenuItem` titled `"Voice Bank: on"` when `appState.voiceBankEnabled`, mirroring how existing status items are built in that file.

- [ ] **Step 2: Verify build + run**

Run: `make run CODESIGN_IDENTITY=- ARCH=$(uname -m)`
Expected: with banking on, the menu shows the indicator; with it off, the row is absent.

- [ ] **Step 3: Commit**

```bash
git add Sources/MenuBarView.swift
git commit -m "feat: show a menu-bar indicator when Voice Bank is active"
```

---

## Task 10: Docs + privacy note

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the README**

In `README.md`, add a "Voice Bank" subsection under Features describing: it is **off by default**, opt-in; audio + transcript are stored **locally only** in Application Support; nothing is uploaded; how to delete (Settings → Voice Bank → Delete All). Update the "Privacy" section to note the default-off, local-only Voice Bank exists. Update the top-of-file project name/description from FreeFlow to Whispr Free Me.

- [ ] **Step 2: Update the changelog**

In `CHANGELOG.md`, add an `## [Unreleased]` section:

```markdown
## [Unreleased]

### Added
- Voice Bank: opt-in, local-only capture of (audio, transcript) pairs from your
  dictations to build a voice-training dataset. Off by default; browse and delete
  in Settings → Voice Bank. Nothing is uploaded.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: document the opt-in Voice Bank"
```

---

## Definition of done

- `swift test` is green (metrics, gate, store, façade).
- `make CODESIGN_IDENTITY=- ARCH=$(uname -m)` builds the rebranded app.
- With Voice Bank **on**, dictating a full sentence creates a WAV + row under
  `Application Support/<App>/VoiceBank/`, browsable and deletable in Settings.
- With Voice Bank **off** (the default), no audio is retained and behavior matches
  upstream freeflow (the privacy invariant).
- Banked data survives the 20-entry history cap (separate store + copied audio).

## Notes / deliberate scope decisions

- **`durationMs` / `wordCount` on the history record (for the dashboard) are deferred
  to Phase 1.** Adding them means a `PipelineHistory` Core Data migration plus threading
  through `PipelineHistoryItem` and `recordPipelineHistoryEntry`; the dashboard is the
  natural place to do that. Phase 0 captures duration/word count on banked `VoiceSample`s,
  which is what the cloning pipeline needs. (This narrows spec §8.2 intentionally.)
- **Audio is double-stored when banking is on** (once in `audio/` for history, once in
  `VoiceBank/`). This buys clean decoupling from the history trim. A future optimization
  could reference-count instead.
- **WAV size:** ~1.9 MB/min. The stats row surfaces minutes banked; "Delete All" is the
  release valve. FLAC compression is a future enhancement.
- **`CODESIGN_IDENTITY=-`** (ad-hoc) is for local dev. Release/CI keeps a real identity.
