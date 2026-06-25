---
title: Dictation modes (DictationModeKit)
summary: How content-aware cleanup modes work — routing, prompt snippets, the casual register decision, and the eval harness.
topics: [voice-pipeline, decisions, dictation-modes]
sources:
  - id: dictation-modes-swift
    type: file
    path: Sources/DictationModes/DictationModes.swift
    note: Defines DictationMode enum, promptSnippet, and DictationModes routing.
  - id: dictation-mode-kit-tests
    type: file
    path: Tests/DictationModeKitTests/DictationModeKitTests.swift
    note: TDD contract tests for casual snippet + characterization tests for routing (on ios-voice-keyboard branch).
  - id: package-swift
    type: file
    path: Package.swift
    note: DictationModeKit and DictationModeKitTests targets (on ios-voice-keyboard branch).
  - id: casual-eval
    type: file
    path: Tools/casual-eval/eval.py
    note: Before/after eval tool; on wip-casual-eval branch.
  - id: casual-mode-memory
    type: file
    path: /Users/vk/.claude/projects/-Users-vk-whispr-free-me/memory/casual-mode-register.md
    note: User preference for the casual register, including the two-iteration rejection history.
status: active
verified: 2026-06-09
---

# Dictation modes (DictationModeKit)

Content-aware cleanup modes map the frontmost app's bundle ID to a `DictationMode` enum, which
adds a mode-specific prompt snippet to the cleanup system prompt. The logic lives in
[[Sources/DictationModes/DictationModes.swift]], extracted from `Sources/` root into the
`DictationModeKit` SwiftPM module on the `ios-voice-keyboard` branch.

## The four modes

| Mode | Trigger apps (bundle ID contains) | Behavior |
|---|---|---|
| `.standard` | (everything else) | No snippet; base prompt rules only. |
| `.formal` | mail, outlook, spark, airmail | Complete sentences, correct capitalization, professional tone. |
| `.code` | xcode, terminal, iterm, vscode, cursor, ghostty, warp, sublime, jetbrains, nova | Preserve code/commands/paths exactly; no prose capitalization. |
| `.casual` | messages, mobilesms, ichat, slack, discord, whatsapp, telegram, signal | Natural texting register (see below). |

Routing is done by `DictationModes.mode(forBundleId:)` — a `lowercased().contains(…)` match
chain, with `standard` as the default. Mode detection is default-on (UserDefaults key
`contentAwareModesEnabled`; defaults to `true` when never set).

The recording overlay shows a color-coded badge (the pill widened to 236pt when the chip is
visible — see [[gotchas-and-decisions]] "mode chip needs the pill widened").

## DictationModeKit SwiftPM module

`DictationModes.swift` was moved from `Sources/` root to `Sources/DictationModes/` and added as
a SwiftPM `DictationModeKit` target in [[Package.swift]] (on the `ios-voice-keyboard` branch).
The app's Makefile still globs `Sources/**/*.swift` and picks it up unchanged — the module split
only enables `swift test` to cover it. Tests live in `Tests/DictationModeKitTests/`.

Before this change, the mode and routing logic had **zero test coverage**.

The `ios-voice-keyboard` branch (as of `367c54a`) has 9 tests: 3 casual-snippet contract tests
+ 6 routing characterization tests. `swift test` runs 46 total (including prior Transcription +
VoiceBank tests), all green.

## Casual register: what the user wants

The casual register was calibrated empirically in one session (2026-06-09) by rejecting both
extremes back-to-back [@casual-mode-memory]:

- **Round 1 (bug):** Output identical to Standard — full sentence-case and punctuation — because the
  old one-liner snippet ("lowercase is fine, minimal punctuation") was a soft hint the base prompt
  overruled. User: "too many punctuations."
- **Round 2 (overcorrection):** Rewrite said "lowercase the start of sentences" explicitly; model
  produced all-lowercase, no formatting. User: "you ruined it."
- **Round 3 (committed):** Conservative middle. Keep everyday punctuation (commas, `?`, `!`, names,
  `I`); only drop the message-final period. Snippet explicitly says "Do not lowercase everything and
  do not strip out commas or other punctuation."

**Current snippet (committed `367c54a` on `ios-voice-keyboard`):**
> This is a casual text message (iMessage, SMS, or a chat app). Match how the speaker texts a
> friend: relaxed and informal, but still readable. Keep their normal capitalization, commas,
> question marks, exclamation points, names, and the word "I". The only casual touch is that you
> may drop the period at the very end of the message. Do not lowercase everything and do not strip
> out commas or other punctuation. No greeting and no sign-off.

**Open idea:** The user floated a future **slider/spectrum from casual → formal** rather than four
discrete modes. Keep prompt policy parameterizable so it can become a continuum.

## GOTCHA: soft prompt suffixes lose to explicit base rules

The root cause of the original casual-mode failure — and a general pattern to watch for.

The base `defaultSystemPrompt` in `PostProcessingService.swift` contains imperative rules: "Fix
punctuation and capitalization", "use normal sentence punctuation for complete sentences." The old
casual snippet was a soft, vague appended paragraph. The model followed the explicit base rules and
ignored the hint.

**Diagnosis was data-driven, not guesswork.** Querying the pipeline history DB confirmed the
snippet was present in `ZPOSTPROCESSINGPROMPT` for all 7 Messages dictations, yet 5 of 7 came out
with full sentence-case and punctuation. The model (`openai/gpt-oss-120b`) couldn't reconcile
conflicting instructions — it's a prompt design problem, not a model-size problem.

**Fix principle:** When a mode snippet must override base rules, it must say so explicitly ("This
OVERRIDES the capitalization and normal-sentence-punctuation rules above") and be imperative, not
permissive. Alternatively, restructure the base prompt to not pre-empt mode overrides.

## Eval harness

`Tools/casual-eval/eval.py` (on `wip-casual-eval` branch) re-runs saved iMessage dictations from
the pipeline history SQLite DB through the casual system prompt and prints RAW / BEFORE (saved
output) / AFTER (new prompt). Use before judging any snippet change.

Run: `GROQ_API_KEY=... python3 Tools/casual-eval/eval.py`. Stdlib only; queries
`~/Library/Application Support/Whispr Free Me Dev/PipelineHistory.sqlite` for
`com.apple.MobileSMS` entries. The `NEW_CASUAL_SNIPPET` constant in the script must mirror
`DictationMode.casual.promptSnippet`.

## Related pages

- [[whispr-free-me]] — the pipeline that calls the mode routing and injects the snippet
- [[gotchas-and-decisions]] — recording overlay chip width gotcha; the `PipelineHistoryStore` section
- [[ios-voice-keyboard]] — branch map including `wip-casual-eval`
