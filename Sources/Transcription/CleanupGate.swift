import Foundation

/// Decides when a dictation is too short to be worth a cleanup-LLM round trip.
/// "Yes.", "Send it now." gain nothing from polishing but pay its full latency;
/// Whisper already capitalizes and punctuates short utterances acceptably.
public enum CleanupGate {
    static let maxSkippableWords = 3
    /// Unspaced scripts (CJK) count as one "word"; the character cap keeps real
    /// sentences in those languages flowing to cleanup.
    static let maxSkippableCharacters = 20

    public static func shouldSkipCleanup(transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxSkippableCharacters else { return false }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count <= maxSkippableWords
    }
}
