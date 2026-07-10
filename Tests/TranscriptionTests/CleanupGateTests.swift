import XCTest
@testable import Transcription

final class CleanupGateTests: XCTestCase {

    func testShortAcknowledgementsSkipCleanup() {
        XCTAssertTrue(CleanupGate.shouldSkipCleanup(transcript: "yes"))
        XCTAssertTrue(CleanupGate.shouldSkipCleanup(transcript: "Send it now."))
        XCTAssertTrue(CleanupGate.shouldSkipCleanup(transcript: "  okay  "))
    }

    func testFourWordsGetCleanedUp() {
        XCTAssertFalse(CleanupGate.shouldSkipCleanup(transcript: "send it right now"))
    }

    func testLongUnspacedTextGetsCleanedUp() {
        // CJK has no word-splitting spaces; a character cap keeps real sentences
        // from slipping past the word count.
        XCTAssertFalse(CleanupGate.shouldSkipCleanup(transcript: "这是一个很长的句子需要清理和正确的标点符号处理"))
    }

    func testShortUnspacedTextSkips() {
        XCTAssertTrue(CleanupGate.shouldSkipCleanup(transcript: "好的"))
    }
}
