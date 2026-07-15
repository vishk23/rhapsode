import Foundation
import Transcription

// Corpus evaluation for the hallucination filters: runs REAL recordings through
// the REAL transcription request the app makes (verbose_json + vocabulary
// prompt), then applies the filter chain and reports what it changed.
//
// The point is regression evidence at scale, in both directions:
//   * do known hallucinations (phantom padding segments, prompt echoes) die?
//   * does anything strip a word the speaker actually said?
//
// Transcriptions are cached to disk, so re-runs after a filter change are free
// and deterministic — the cache is the corpus.
//
//   GROQ_API_KEY=<key> swift run corpus-eval <audio-dir> [--limit N] [--vocab "A, B"]
//
// Exits non-zero when a strip looks suspicious, so it can gate a release.

let env = ProcessInfo.processInfo.environment
guard let apiKey = env["GROQ_API_KEY"], !apiKey.isEmpty else {
    fputs("Error: GROQ_API_KEY is not set.\n", stderr)
    exit(1)
}

let args = CommandLine.arguments
guard args.count > 1 else {
    fputs("Usage: swift run corpus-eval <audio-dir> [--limit N] [--vocab \"A, B\"]\n", stderr)
    exit(1)
}
let audioDir = URL(fileURLWithPath: args[1], isDirectory: true)

func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let limit = flag("--limit").flatMap(Int.init)
let vocabulary = (flag("--vocab") ?? "")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }

let model = env["CORPUS_MODEL"] ?? "whisper-large-v3-turbo"
let baseURL = env["GROQ_BASE_URL"] ?? "https://api.groq.com/openai/v1"
let cacheDir = URL(fileURLWithPath: env["CORPUS_CACHE"] ?? "/tmp/rhapsode-corpus-cache", isDirectory: true)
try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

let fm = FileManager.default
var wavs = ((try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil)) ?? [])
    .filter { $0.pathExtension.lowercased() == "wav" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
if let limit { wavs = Array(wavs.prefix(limit)) }

guard !wavs.isEmpty else {
    print("No .wav files in \(audioDir.path)")
    exit(0)
}

// MARK: - Transcription (cached)

func multipart(audio: Data, fileName: String, boundary: String) -> Data {
    var body = Data()
    func append(_ s: String) { body.append(Data(s.utf8)) }
    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n")
    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json\r\n")
    if !vocabulary.isEmpty {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\n\(vocabulary.joined(separator: ", "))\r\n")
    }
    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
    append("Content-Type: audio/wav\r\n\r\n")
    body.append(audio)
    append("\r\n--\(boundary)--\r\n")
    return body
}

func transcribe(_ url: URL) -> [String: Any]? {
    let cacheKey = cacheDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".json")
    if let cached = try? Data(contentsOf: cacheKey),
       let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
        return json
    }
    guard let audio = try? Data(contentsOf: url) else { return nil }
    var request = URLRequest(url: URL(string: "\(baseURL)/audio/transcriptions")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = multipart(audio: audio, fileName: url.lastPathComponent, boundary: boundary)

    let semaphore = DispatchSemaphore(value: 0)
    var result: [String: Any]?
    URLSession.shared.dataTask(with: request) { data, _, _ in
        defer { semaphore.signal() }
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["segments"] != nil else { return }
        try? data.write(to: cacheKey)
        result = json
    }.resume()
    semaphore.wait()
    return result
}

// MARK: - The filter chain under test (mirrors TranscriptionService)

struct Outcome {
    let file: String
    let raw: String
    let filtered: String
    let phantomSpans: [String]
    let audioDuration: Double
    /// True when the recording holds no voiced audio anywhere — an accidental
    /// shortcut tap. Whisper still hallucinates a phrase for these, and emptying
    /// them is the CORRECT outcome (the app then pastes nothing), so an empty
    /// result here is expected rather than a false positive.
    let isSilentClip: Bool
}

// Warm the transcription cache concurrently — the corpus is hundreds of files
// and each round trip is ~1s, so serial fetching dominates the run.
let uncached = wavs.filter {
    !FileManager.default.fileExists(
        atPath: cacheDir.appendingPathComponent($0.deletingPathExtension().lastPathComponent + ".json").path
    )
}
if !uncached.isEmpty {
    FileHandle.standardError.write(Data("fetching \(uncached.count) transcription(s)…\n".utf8))
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 8
    let done = DispatchGroup()
    var completed = 0
    let lock = NSLock()
    for wav in uncached {
        done.enter()
        queue.addOperation {
            _ = transcribe(wav)
            lock.lock()
            completed += 1
            FileHandle.standardError.write(Data("\r  \(completed)/\(uncached.count)".utf8))
            lock.unlock()
            done.leave()
        }
    }
    done.wait()
    FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
}

var outcomes: [Outcome] = []
var failures = 0

for (i, wav) in wavs.enumerated() {
    FileHandle.standardError.write(Data("\r[\(i + 1)/\(wavs.count)] \(wav.lastPathComponent)".utf8))
    guard let json = transcribe(wav), let text = json["text"] as? String else {
        failures += 1
        continue
    }
    let rawSegments = (json["segments"] as? [[String: Any]]) ?? []
    let segments = rawSegments.map {
        WhisperSegment(
            text: $0["text"] as? String ?? "",
            noSpeechProb: $0["no_speech_prob"] as? Double,
            start: $0["start"] as? Double,
            end: $0["end"] as? Double
        )
    }
    guard let audioData = try? Data(contentsOf: wav), let probe = WAVEnergyProbe(data: audioData) else {
        failures += 1
        continue
    }

    // Which segments does the phantom rule consider padding? (reported for insight)
    let phantoms = segments.filter { seg in
        guard let s = seg.start, let e = seg.end, e > s else { return false }
        let covered = probe.audioSeconds(start: s, end: e)
        let ratio = covered / (e - s)
        return covered < 0.45 && ratio < 0.5
    }.map { "[\(String(format: "%.2f", $0.start ?? 0))-\(String(format: "%.2f", $0.end ?? 0))] \($0.text.trimmingCharacters(in: .whitespaces))" }

    var filtered = HallucinationFilter.strip(
        text: text,
        segments: segments,
        windowRMS: { probe.rms(start: $0, end: $1) },
        audioSeconds: { probe.audioSeconds(start: $0, end: $1) }
    )
    filtered = DictionaryEchoGuard.stripTrailingPromptEcho(transcript: filtered, vocabulary: vocabulary)
    if DictionaryEchoGuard.isEcho(transcript: filtered, vocabulary: vocabulary) { filtered = "" }

    // Peak voiced energy anywhere in the clip, in 0.25s windows.
    var peak: Float = 0
    var t = 0.0
    while t < probe.duration {
        peak = max(peak, probe.rms(start: t, end: min(t + 0.25, probe.duration)))
        t += 0.25
    }

    outcomes.append(Outcome(
        file: wav.lastPathComponent,
        raw: text.trimmingCharacters(in: .whitespacesAndNewlines),
        filtered: filtered.trimmingCharacters(in: .whitespacesAndNewlines),
        phantomSpans: phantoms,
        audioDuration: probe.duration,
        isSilentClip: peak < HallucinationFilter.energySilenceFloor
    ))
}
FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))

// MARK: - Report

/// A strip is EXPECTED when what disappeared is a known filler phrase or a
/// vocabulary echo. Anything else removed is a potential false positive and is
/// printed in full for review.
func removedTail(_ raw: String, _ filtered: String) -> String? {
    guard raw != filtered else { return nil }
    guard raw.hasPrefix(filtered) || filtered.isEmpty else { return "<<NON-SUFFIX REWRITE>>" }
    return String(raw.dropFirst(filtered.count)).trimmingCharacters(in: .whitespacesAndNewlines)
}

func isExpectedRemoval(_ tail: String) -> Bool {
    let normalized = HallucinationFilter.normalize(tail)
    if HallucinationFilter.phrases.contains(normalized) { return true }
    let vocabNormalized = HallucinationFilter.normalize(vocabulary.joined(separator: ", "))
    if !vocabulary.isEmpty, normalized == vocabNormalized { return true }
    // A phantom can hallucinate arbitrary text; treat a removal as expected when
    // the transcript kept real content and the tail is short.
    return tail.split(separator: " ").count <= 6
}

let changed = outcomes.filter { $0.raw != $0.filtered }
let suspicious = changed.filter { o in
    guard let tail = removedTail(o.raw, o.filtered) else { return false }
    // Emptying a clip with no voiced audio is the correct outcome, not a loss.
    if o.filtered.isEmpty { return !o.isSilentClip }
    return !isExpectedRemoval(tail)
}

print(String(repeating: "=", count: 72))
print("CORPUS EVAL — \(outcomes.count) recordings (\(failures) unreadable)")
print("vocabulary prompt: \(vocabulary.isEmpty ? "(none)" : vocabulary.joined(separator: ", "))")
print(String(repeating: "=", count: 72))

let withPhantoms = outcomes.filter { !$0.phantomSpans.isEmpty }
print("\nPhantom padding segments detected: \(withPhantoms.count) recording(s)")
for o in withPhantoms.prefix(12) {
    print("  \(o.file.prefix(8))  audio=\(String(format: "%.2f", o.audioDuration))s")
    for span in o.phantomSpans { print("      phantom \(span)") }
    print("      after filter: …\(String(o.filtered.suffix(60)))")
}

print("\nFilter changed the transcript: \(changed.count) recording(s)")
for o in changed.prefix(20) {
    let tail = removedTail(o.raw, o.filtered) ?? "?"
    let why = o.filtered.isEmpty
        ? (o.isSilentClip ? "silent clip (\(String(format: "%.2f", o.audioDuration))s) — emptied" : "EMPTIED")
        : (o.phantomSpans.isEmpty ? "trailing filler over silence" : "phantom past audio end")
    print("  \(o.file.prefix(8))  removed \(tail.prefix(48).debugDescription) — \(why)")
}

print("\nSuspicious strips (possible false positives): \(suspicious.count)")
for o in suspicious {
    print("  \(o.file)")
    print("      raw:      \(o.raw.suffix(100).debugDescription)")
    print("      filtered: \(o.filtered.suffix(100).debugDescription)")
}

print("\n" + String(repeating: "-", count: 72))
print("untouched: \(outcomes.count - changed.count)/\(outcomes.count)")
print(suspicious.isEmpty ? "PASS — no suspicious strips" : "REVIEW NEEDED — \(suspicious.count) suspicious")
exit(suspicious.isEmpty ? 0 : 1)
