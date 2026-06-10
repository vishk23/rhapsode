---
title: Whispr Free Me — overview
topics: [voice-pipeline, ui, decisions]
files:
  - Sources/AppState.swift
  - Sources/AudioRecorder.swift
  - Sources/TranscriptionService.swift
  - Sources/PostProcessingService.swift
  - Sources/DashboardView.swift
  - docs/superpowers/specs/2026-06-08-whispr-free-me-design.md
---

# Whispr Free Me

Whispr Free Me is a fork of [zachlatta/freeflow](https://github.com/zachlatta/freeflow) — a
native macOS menu-bar dictation app (Swift + SwiftUI + AVFoundation). The fork turns the
one-way **voice → text** dictation tool into a **two-way voice tool**: it banks your voice
while you dictate, clones it in the cloud, and adds **text → your voice, anywhere**. It also
adds a usage dashboard and content-aware cleanup modes. Bundle id `com.vishk23.whisprfreeme.dev`,
display name "Whispr Free Me Dev". The full design lives in
[[docs/superpowers/specs/2026-06-08-whispr-free-me-design.md]].

## The dictation pipeline
Hold `Fn` (or tap the toggle shortcut) → record → transcribe → clean up → paste. Driven by
[[Sources/AppState.swift]]:

1. **Capture** — [[Sources/AudioRecorder.swift]] records a normalized **16 kHz mono PCM16 WAV**
   to a temp file via `AVCaptureSession`. The realtime path also emits 24 kHz PCM16 chunks. The
   start cue ("Tink") fires the instant `startRecording` is called (not on first audio buffer —
   that lagged). `playAlertSound` events: start=Tink, stop=Pop, cancel=Funk, error=Sosumi.
2. **Transcribe** — [[Sources/TranscriptionService.swift]] uploads the WAV to an
   OpenAI-compatible endpoint (Groq by default, `whisper-large-v3-turbo`), `response_format=verbose_json`.
   `HallucinationFilter` (in [[Sources/Transcription/HallucinationFilter.swift]], a SwiftPM module)
   strips Whisper's trailing filler hallucinations — see [[gotchas-and-decisions]].
3. **Context + modes** — [[Sources/AppContextService.swift]] reads the frontmost app, window
   title, the **selected text** (`kAXSelectedTextAttribute`, Accessibility), and optionally a
   screenshot. Content-aware modes (`DictationModes`, now extracted toward a `DictationModeKit`
   SwiftPM module) map the frontmost app's bundle id → a cleanup style (Mail→formal, Xcode/
   Terminal→code, Messages/Slack→casual, else standard) injected into the cleanup prompt.
4. **Clean up** — [[Sources/PostProcessingService.swift]] sends raw transcript + context + custom
   vocabulary to a cleanup LLM (default `openai/gpt-oss-120b` on Groq) and returns polished text,
   which is pasted.

Per-dictation records (raw + cleaned transcript, timestamp, app/window, intent) persist in a
Core Data SQLite store ([[Sources/PipelineHistoryStore.swift]]) and are capped (trimmed).

## Voice Bank
The opt-in training dataset — see [[voice-bank]]. New in this fork; absent in upstream freeflow.

## Dashboard
A native SwiftUI `NSWindow` opened from the menu bar ([[Sources/DashboardView.swift]],
[[Sources/DashboardMetrics.swift]]), mirroring how `AppDelegate.handleShowSettings` builds the
settings window. Tabs: **Stats** (dictations, words, time saved, streak, WPM, minutes banked,
14-day activity chart via Swift Charts, top apps), **Dictionary** (edits `AppState.customVocabulary`),
**Snippets** (edits `AppState.voiceMacros`, reusing the existing macro editor), **Voice Clone**,
and **Speak**. Reads `appState.pipelineHistory` + `voiceBankStats()` + `voiceBankSamples()`.

## Voice clone + speak-as-me
ElevenLabs integration — see [[voice-cloning]].

## Build, signing, gotchas
See [[gotchas-and-decisions]] for code signing, the okay-hallucination fix, the ElevenLabs
free-tier wall, AirPods audio ducking, and the `make` staleness trap.
