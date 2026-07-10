# Local transcription eval — whisper.cpp on M4 vs Groq cloud

**Date:** 2026-07-10 · **Hardware:** Apple M4 · **Local model:** ggml-large-v3-turbo-q5_0
(547 MB, Metal) via Homebrew whisper-cli · **Cloud baseline:** whisper-large-v3-turbo on Groq
· **Corpus:** 12 most recent voice-bank clips > 3s (412 reference words, real dictations)

## Results

| Metric | Local (M4, Metal) | Groq cloud |
|---|---|---|
| Word agreement | 96.6% vs Groq output (7/12 clips byte-identical) | — |
| Inference latency (avg/clip) | 1,390 ms (model resident; +172 ms load if cold) | 580–850 ms total incl. network |
| First-run cost | ~9 s one-time Metal shader compile | none |
| Cost / privacy / offline | free, on-device, works offline | paid API, audio leaves device |

On the largest-divergence clip (8.8% WER) the local output was *better* — it correctly
dropped a stutter ("I feel like the like for some reason" → "I feel like for some reason").
No local hallucinations observed on this corpus. Quality is at parity for dictation use.

## Conclusion

**Keep Groq as the default: it is ~2x faster** (0.6–0.9 s vs 1.4 s per dictation), and the
connection prewarm added in Phase 6 widens that gap. **Local is viable as an offline/privacy
fallback**, not as a speed upgrade.

If/when local integration happens, the eval points at:
- large-v3-turbo q5_0 quality is sufficient; no need for the full-precision model.
- The 1.4 s is Metal-only. VoiceInk pairs whisper.cpp with a **CoreML ANE encoder**
  (downloaded alongside the GGML model) and reports large speedups on Apple Silicon —
  that is the path to test before concluding local can't reach sub-second.
- Keep the model resident (172 ms load is fine to pay once; VoiceInk prewarms on wake).
- The `TranscriptionModel`-protocol pattern (VoiceInk) lets Groq and local coexist behind
  the provider dropdown rather than special-casing.

Artifacts (per-clip transcripts, timings) were produced in the session scratchpad;
methodology: WER of local output against the banked Groq raw transcripts (agreement
measure, not ground truth), wall-clock per whisper-cli invocation, internal
whisper_print_timings for the load/inference split, and 3 timed Groq uploads of the same
WAVs for the cloud baseline.
