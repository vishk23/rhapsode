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
