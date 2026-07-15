# Hallucination filter — corpus evaluation

**Date:** 2026-07-15 · **Corpus:** 490 real dictation recordings (the retained
history audio) · **Request:** the app's exact call — `whisper-large-v3-turbo`,
`verbose_json`, vocabulary prompt `Cava, Dunkin', wellness` · **Harness:**
`swift run corpus-eval <dir> --vocab "…"` (transcriptions cached to disk, so
re-runs after a filter change are free and deterministic; exits non-zero on a
suspicious strip, so it can gate a release).

## Result

| | count |
|---|---|
| Recordings evaluated | 490 |
| **Untouched by the filter** | **476 (97.1%)** |
| Changed (all verified correct) | 14 |
| **Suspicious strips / false positives** | **0** |

### What the 14 changes were

| Class | n | Behavior |
|---|---|---|
| **Phantom past audio end** (new rule) | 3 | Real speech kept, hallucinated tail dropped |
| Trailing filler over silence (energy rule) | 3 | Real speech kept, filler dropped |
| Silent clip, whole transcript hallucinated | 8 | Emptied → app pastes nothing |

## The phantom class — why the earlier fixes missed it

Whisper transcribes in 30-second chunks and zero-pads the final one. Every
phantom in the corpus is a dictation that **crossed 30 seconds**, with the
hallucination in a segment starting at exactly 30.00:

| recording | audio | phantom segment | real audio inside it |
|---|---|---|---|
| `0D3B7E85` | 30.05s | `[30.00, 32.00]` "Thank you" | 0.05s |
| `3231E36E` | 30.07s | `[30.00, 59.98]` "Thank you" | 0.07s |
| `6B698570` | 30.32s | `[30.00, 59.98]` "Thank you" | 0.32s |

These clips are voiced to their last sample (the speaker is mid-word at key
release), so there is no trailing silence to trim; `no_speech_prob` is 0.0000;
and the claimed durations (2s, 30s) defeat a short-filler heuristic. The energy
probe clamped the impossible window to the sliver of audio that exists, measured
the *previous word's* tail, and kept the hallucination.

The rule that fixes it is physical rather than statistical: a trailing segment
whose window holds **less recorded audio than the phrase takes to say**
(`minSpeakableSeconds` = 0.45s) while covering **under half its claimed span** is
describing padding, not speech — whatever its text, however confident the model.

## Negative controls (the fix must not eat real words)

- `24C17A98` — "Hi Tom, thanks for connecting" → **untouched**. Genuine
  gratitude inside speech survives.
- 476/490 recordings pass through byte-identical.
- A tight trailing window (a genuinely spoken final word claims the span it
  covers) is never treated as padding; the last remaining segment is never
  dropped by the phantom rule, so a short clip of only "Thank you." still
  pastes.

## Notes

- The vocabulary prompt is what provokes the phantom: the same file transcribes
  clean without it. That is the price of correct rare-word spelling; the filters
  neutralize the side effect.
- One recording (`589F1F52`) had the vocabulary list itself echoed as its tail —
  caught by `DictionaryEchoGuard` (0.5.1).
- 8 of 490 recordings are accidental shortcut taps with no voiced audio at all
  (0.01s–5.9s of silence). Whisper hallucinates a phrase for each; emptying them
  is correct and routes to the app's "Nothing to transcribe" path.
- ~79 files in the directory failed to transcribe or parse (empty/truncated
  captures) and are excluded from the counts above.

## Re-running

```bash
GROQ_API_KEY=<key> swift run corpus-eval \
  ~/Library/Application\ Support/Rhapsode/audio --vocab "Cava, Dunkin', wellness"
```

Any filter change should be re-validated here before release: it is the only
check that covers real-world audio at scale, and it fails loudly on a strip that
removes something other than a known hallucination.
