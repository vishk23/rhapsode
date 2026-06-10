---
title: Voice Bank
topics: [voice-bank, decisions]
files:
  - Sources/VoiceBank/VoiceBankStore.swift
  - Sources/VoiceBank/VoiceSample.swift
  - Sources/VoiceBank/VoiceBankQualityGate.swift
  - Tools/replay/main.swift
---

# Voice Bank

The Voice Bank is the opt-in local dataset of `(audio, transcript)` pairs that feeds voice
cloning ([[voice-cloning]]). It is new in this fork — upstream freeflow recorded audio to a temp
file and **deleted** it after transcription, keeping only a capped run-log. None of
`Sources/VoiceBank/` exists upstream.

## Behavior
- Off by default. The toggle persists under UserDefaults key `voiceBankEnabled`. With it off,
  the app behaves exactly like upstream freeflow (nothing extra stored) — this default preserves
  freeflow's "no server, no retained data" promise and keeps the fork upstream-mergeable.
- When on, after a successful dictation the normalized 16 kHz WAV is copied (not deleted) into
  `~/Library/Application Support/Whispr Free Me Dev/VoiceBank/<uuid>.wav`, and a `VoiceSample`
  row (id, createdAt, audioFileName, transcript, durationMs, wordCount, appBundleId) is inserted
  via [[Sources/VoiceBank/VoiceBankStore.swift]] (its own Core Data SQLite store, decoupled from
  the capped pipeline history so banked data is never trimmed away).
- A quality gate ([[Sources/VoiceBank/VoiceBankQualityGate.swift]]) drops silent/too-short/failed
  clips and keeps only `dictation` intent.
- Settings → Voice Bank lists samples with a ▶ play button (reuses the run-log `AudioPlayerView`
  that already existed upstream), plus delete/clear.

## Decision: label with the RAW transcript
Samples are labelled with the **raw** transcript (what Whisper produced), not the
post-processed/cleaned text. Cleanup removes filler and applies edits, so the cleaned text does
not match the audio; voice/STT training needs transcript == audio.

## Replay harness — regression testing on real audio
[[Tools/replay/main.swift]] is a SwiftPM executable (`swift run replay <dir>`, needs
`GROQ_API_KEY`) that re-runs banked WAVs through the real transcription endpoint + the
`HallucinationFilter`, printing raw vs cleaned. It was built to verify the okay-hallucination fix
on the user's actual clips, and is the project's regression tester for transcription changes.
