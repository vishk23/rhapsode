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
