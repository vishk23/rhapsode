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
