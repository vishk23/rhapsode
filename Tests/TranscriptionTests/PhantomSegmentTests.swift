import XCTest
@testable import Transcription

/// Whisper pads its final 30s chunk with silence and can hallucinate an entire
/// segment onto that padding, claiming a window that lies past the end of the
/// recording. Real incident (2026-07-13): a 30.32s dictation produced a phantom
/// segment [30.00, 59.98] whose text ("Thank you") pasted into the user's message.
final class PhantomSegmentTests: XCTestCase {

    /// 30.32s of audio: voiced to the last sample (the tail of a real word).
    private func probe(audioSeconds: Double) -> (Double, Double) -> Double {
        { start, end in
            let lo = Swift.max(0, start)
            let hi = Swift.min(audioSeconds, end)
            return Swift.max(0, hi - lo)
        }
    }

    private let voiced: (Double, Double) -> Float = { _, _ in 0.07 }

    func testPhantomPaddingSegmentIsStripped() {
        let segments = [
            WhisperSegment(text: " So I would like to make it feel more exciting, but that's a future pass.",
                           noSpeechProb: 0.0, start: 0.0, end: 29.98),
            WhisperSegment(text: " Thank you", noSpeechProb: 0.0, start: 30.00, end: 59.98)
        ]
        let result = HallucinationFilter.strip(
            text: segments.map(\.text).joined(),
            segments: segments,
            windowRMS: voiced,
            audioSeconds: probe(audioSeconds: 30.32)
        )
        XCTAssertEqual(
            result,
            "So I would like to make it feel more exciting, but that's a future pass."
        )
    }

    /// The same phantom mechanism can hallucinate arbitrary text (a vocabulary
    /// echo, a caption credit) — no audio means nothing was said, whatever it says.
    func testPhantomPaddingStripsNonFillerText() {
        let segments = [
            WhisperSegment(text: " Real speech here.", noSpeechProb: 0.0, start: 0.0, end: 29.98),
            WhisperSegment(text: " Cava, Dunkin'", noSpeechProb: 0.0, start: 30.00, end: 59.98)
        ]
        let result = HallucinationFilter.strip(
            text: segments.map(\.text).joined(),
            segments: segments,
            windowRMS: voiced,
            audioSeconds: probe(audioSeconds: 30.32)
        )
        XCTAssertEqual(result, "Real speech here.")
    }

    /// A genuine short word at the very end has a TIGHT window — its claimed span
    /// matches the audio it covers, so it is not padding and must survive.
    func testGenuineShortTrailingWordSurvives() {
        let segments = [
            WhisperSegment(text: " Alright, sending it now.", noSpeechProb: 0.0, start: 0.0, end: 29.5),
            WhisperSegment(text: " Thank you.", noSpeechProb: 0.0, start: 29.5, end: 30.3)
        ]
        let result = HallucinationFilter.strip(
            text: segments.map(\.text).joined(),
            segments: segments,
            windowRMS: voiced,
            audioSeconds: probe(audioSeconds: 30.32)
        )
        // Nothing stripped — the filter returns the transcript untouched.
        XCTAssertEqual(result, " Alright, sending it now. Thank you.")
    }

    /// A whole-clip segment on a short recording is not padding — a user who
    /// records only "Thank you." must still get their words.
    func testSingleSegmentIsNeverTreatedAsPhantom() {
        let segments = [
            WhisperSegment(text: " Thank you.", noSpeechProb: 0.0, start: 0.0, end: 29.98)
        ]
        let result = HallucinationFilter.strip(
            text: " Thank you.",
            segments: segments,
            windowRMS: voiced,
            audioSeconds: probe(audioSeconds: 1.4)
        )
        XCTAssertEqual(result, " Thank you.")
    }

    /// Without a coverage probe (no audio available) behavior is unchanged.
    func testNoProbeKeepsExistingBehavior() {
        let segments = [
            WhisperSegment(text: " Real speech.", noSpeechProb: 0.0, start: 0.0, end: 29.98),
            WhisperSegment(text: " Thank you", noSpeechProb: 0.0, start: 30.00, end: 59.98)
        ]
        let result = HallucinationFilter.strip(text: segments.map(\.text).joined(), segments: segments)
        XCTAssertEqual(result, " Real speech. Thank you")
    }
}
