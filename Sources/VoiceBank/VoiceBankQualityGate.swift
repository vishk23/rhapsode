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
