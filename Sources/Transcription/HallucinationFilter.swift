import Foundation

public struct WhisperSegment: Equatable {
    public let text: String
    public let noSpeechProb: Double?
    public let start: Double?
    public let end: Double?
    public init(text: String, noSpeechProb: Double?, start: Double? = nil, end: Double? = nil) {
        self.text = text
        self.noSpeechProb = noSpeechProb
        self.start = start
        self.end = end
    }
    public var duration: Double? {
        guard let start, let end else { return nil }
        return max(0, end - start)
    }
}

public enum HallucinationFilter {
    /// Known phrases Whisper hallucinates on silence/pauses at the end of a clip.
    public static let phrases: Set<String> = [
        "thank you", "thank you for watching", "thank you very much", "thank you so much",
        "thanks for watching", "please subscribe", "like and subscribe",
        "subtitles by", "subtitles by the amara.org community", "you", "okay", "ok", "bye"
    ]
    /// Phrases that are commonly *intentional* (e.g. a message/email sign-off). These
    /// are stripped only when Whisper itself flags the segment as silence — never on
    /// the short-trailing-segment heuristic — so a deliberate "Thank you." survives.
    static let silenceOnlyPhrases: Set<String> = [
        "thank you", "thank you very much", "thank you so much"
    ]
    public static let noSpeechThreshold = 0.1
    /// A hallucinated trailing filler is a brief, isolated segment. Real sentences that
    /// merely *contain* a filler word are not their own short segment, so duration
    /// discriminates the artifact from genuine speech.
    static let maxFillerDuration = 1.5
    /// Window mean-RMS below this is silence: no voice was recorded during the segment,
    /// so a confident filler there is hallucinated. Raw samples normalized to [-1, 1];
    /// whispered speech measures >= ~0.01, ambient room noise <= ~0.005.
    public static let energySilenceFloor: Float = 0.006
    /// Shortest window that could physically hold a spoken filler phrase — "thank you"
    /// is two syllables and takes ~0.5s even rushed. A segment window holding less
    /// recorded audio than this cannot hold speech.
    static let minSpeakableSeconds = 0.45
    /// Below this share of real audio, a segment's window is mostly Whisper's own
    /// zero-padding rather than a tight claim about recorded speech.
    static let maxPaddingCoverageRatio = 0.5

    public static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// Removes trailing hallucinated segments. A trailing segment is dropped when it is a
    /// known filler phrase AND either Whisper flagged it as silence (`no_speech_prob` high)
    /// OR it is a short, isolated trailing segment — the signature of a confidently
    /// hallucinated "Okay."/"Bye." appended after the speaker stops. Real speech preceding
    /// the filler is preserved.
    public static func strip(
        text: String,
        segments: [WhisperSegment],
        windowRMS: ((_ start: Double, _ end: Double) -> Float)? = nil,
        audioSeconds: ((_ start: Double, _ end: Double) -> Double)? = nil
    ) -> String {
        guard !segments.isEmpty else { return text } // can't confirm without segment data
        var kept = segments

        // PHANTOM PADDING: Whisper pads its final 30s chunk with silence, and can
        // hallucinate an entire segment onto that padding — claiming a window that
        // lies past the end of the recording (observed: 30.32s of audio, segment
        // [30.00, 59.98]). Physics settles it: a window holding almost no recorded
        // audio cannot hold speech, whatever the model wrote there or however
        // confident it is. Only the sliver of real audio at such a chunk's start is
        // measurable, and it belongs to the PRECEDING utterance's tail — which is
        // why the energy check alone keeps the hallucination.
        //
        // Guards: a tight window (claimed span ≈ its audio) is real speech, not
        // padding; and the last remaining segment is never dropped this way, so a
        // short recording of only "Thank you." keeps the user's words.
        if let audioSeconds {
            while kept.count > 1, let last = kept.last,
                  let start = last.start, let end = last.end, end > start {
                let covered = audioSeconds(start, end)
                let claimed = end - start
                let ratio = claimed > 0 ? covered / claimed : 1
                guard covered < minSpeakableSeconds, ratio < maxPaddingCoverageRatio else { break }
                kept.removeLast()
            }
        }

        while let last = kept.last {
            let normalized = normalize(last.text)
            guard phrases.contains(normalized) else { break }
            let highSilence = (last.noSpeechProb ?? 0) >= noSpeechThreshold
            let shortTrailing = (last.duration ?? .greatestFiniteMagnitude) < maxFillerDuration
            // Audio evidence beats Whisper's own confidence: if the recorded audio during
            // this segment's window is silent, no one spoke it — a confident "Thank you."
            // there is hallucinated. A deliberately spoken sign-off has voice energy and
            // survives. Requires timestamps and a probe; otherwise falls back to the
            // metadata-only rules.
            let silentWindow: Bool
            if let windowRMS, let start = last.start, let end = last.end, end > start {
                silentWindow = windowRMS(start, end) < energySilenceFloor
            } else {
                silentWindow = false
            }
            let strippable = silenceOnlyPhrases.contains(normalized)
                ? (highSilence || silentWindow)
                : (highSilence || shortTrailing || silentWindow)
            guard strippable else { break }
            kept.removeLast()
        }
        if kept.count == segments.count { return text } // nothing stripped
        return kept.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
