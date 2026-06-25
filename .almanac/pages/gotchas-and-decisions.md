---
title: Build, signing, and gotchas
topics: [build-and-signing, gotchas, decisions]
files:
  - Makefile
  - Sources/AudioRecorder.swift
  - Sources/AppState.swift
  - Sources/Pipeline/TranscriptionService.swift
  - Sources/Transcription/HallucinationFilter.swift
  - Sources/SystemAudioStatus.swift
  - Sources/RecordingOverlay.swift
  - Package.swift
---

# Build, signing, and gotchas

## Build
No Xcode project. [[Makefile]] globs `Sources/**/*.swift` and builds with a raw `swiftc`
invocation (`-target arm64-apple-macosx13.0`). A separate [[Package.swift]] defines SwiftPM
targets for the AppKit-free, unit-testable logic: `VoiceBank`, `Transcription`
(the `HallucinationFilter`), and the in-progress `DictationModeKit`. Run logic tests with
`swift test`; build the app with `make ARCH=$(uname -m)`.

## DECISION: sign with a stable Developer ID so TCC grants survive rebuilds
Fn dictation uses a `CGEvent.tapCreate` event tap, which needs **Accessibility** permission.
Ad-hoc signing (`CODESIGN_IDENTITY=-`) changes the code hash on every build, so macOS treats each
rebuild as a different app and **drops the Accessibility/Mic/Input-Monitoring grants** — Fn then
silently stops working. Fix: [[Makefile]] pins `CODESIGN_IDENTITY` to the **SHA-1 of the Developer
ID Application cert** (`DFA91A6910C03A08E484BEB0C53AC107C461C800`, team R78VP2V5AQ) — by hash, not
name, because two Developer ID certs share the same name and `codesign` would otherwise be
ambiguous. With a stable Designated Requirement, TCC grants persist across rebuilds. `--options
runtime` (hardened runtime) is already in the codesign step; the only entitlement is mic.

## GOTCHA: `make` has no per-file dependency tracking
`make` only rebuilds if the `.app` is missing — it prints "Nothing to be done for `all'" even after
source edits. To force a rebuild that picks up changes, run `make clean && make`.

## GOTCHA / DECISION: the trailing-"okay" Whisper hallucination
Whisper appends a spurious filler (" Okay.", " Thank you.", " Bye.") on the trailing silence after
you stop talking. The first fix gated on `no_speech_prob >= 0.1`, but the replay harness ([[voice-bank]])
proved that on real audio the trailing "Okay." is its **own short segment with `no_speech_prob = 0.0`**
(Whisper is *confident*). So [[Sources/Transcription/HallucinationFilter.swift]] strips a trailing
filler segment when it is a known phrase AND (high `no_speech_prob` OR a short, isolated trailing
segment — duration < ~1.5s). A silence-only carve-out keeps deliberate "Thank you." sign-offs. The
project later added a separate silent-clip guard (`isSilentClipFiller` / `capturedAudioWasSilent`) for
cold-start dropped audio (see below).

## GOTCHA / DECISION: cold-start drops the front of the first utterance → a lone "A"
[[Sources/AudioRecorder.swift]] rebuilds the entire `AVCaptureSession` (teardown → `startRunning`)
on **every** dictation — there is no warm or persistent session. The mic is not live for the first
hundreds of ms (up to ~1–2s on AirPods, whose A2DP→HFP route switch is slow), so a short utterance
spoken into that gap is partially or fully dropped. Near-silent audio makes Whisper emit a single
low-information token ("A", "you") that the trailing-filler strip does not catch.

Two independent guards prevent this garbage from pasting:
- **Energy guard** (`capturedAudioWasSilent(peakRMS:)` in [[Sources/Transcription/HallucinationFilter.swift]]) — [[Sources/AudioRecorder.swift]] tracks peak raw RMS while capturing (not the high-pass-filtered display meter); [[Sources/AppState.swift]] skips the upload and shows "Didn't catch that" when peak < `silenceRMSFloor` (0.006). Stops dropped recordings before any network call.
- **Transcript guard** (`isSilentClipFiller(text:segments:)`) — drops a whole-clip single-token filler only when Whisper's own metadata flags the clip as silence (`no_speech_prob >= 0.1`). A deliberate one-word "Okay" reply carries a confident, low-`no_speech_prob` segment and is not dropped. Routes to the existing "Nothing to transcribe" path (no paste, no LLM call). Wired in [[Sources/Pipeline/TranscriptionService.swift]].

Both guards are TDD'd (9 tests in [[Tests/TranscriptionTests/HallucinationFilterTests.swift]]).

DECISION: the mic is deliberately **not** pre-warmed — the user accepted the first-press lag rather than an always-on mic indicator. Instead the start cue was made honest: the "talk now" Tink fires from `AudioRecorder.onCaptureLive` (the first captured audio buffer — mic genuinely live), not on key-press, so the user is never prompted to speak into a not-yet-live mic.

## GOTCHA: AirPods can't do mic + hi-fi audio at once
Bluetooth can't run A2DP (stereo music) and the microphone (HFP) simultaneously. When the app opens
the AirPods mic, macOS forces HFP and the user's music gets re-leveled *louder*. Mitigation:
[[Sources/SystemAudioStatus.swift]] + `AppState.applyAudioInterruptionIfNeeded` smoothly **duck**
the system output volume to ~20% while dictating (a ramped volume change), with a **mute fallback**
when the device's volume isn't settable. The cleanest fix for pristine music is to dictate with the
built-in mic instead.

**Cue-before-duck:** `applyAudioInterruptionIfNeeded` used to run synchronously inside `startRecording`, immediately after `playAlertSound` fired the Tink. On AirPods the mute fallback swallowed the cue — the user heard the *close* cue (the duck is restored before it plays) but never the *start* cue. `NSSound` plays through the same default output device the duck controls, so the cue cannot be exempted from the mute; sequencing is the only fix. `applyAudioInterruptionIfNeeded` is now deferred into `AudioRecorder.onCaptureLive` and fires only *after* `playAlertSound`'s duration elapses (`playAlertSound` returns the cue duration to enable this), mirroring the close path (restore-then-cue). A guard prevents a tap shorter than the cue's duration from leaving the output stuck ducked after the session ends.

## GOTCHA: the mode chip needs the pill widened
The recording overlay ([[Sources/RecordingOverlay.swift]]) is cramped. The content-aware mode chip
(Formal/Code/Casual/Standard, color-coded) truncated to "ST…" in the narrow side slot. Fix: when a
mode chip is visible the pill widens to a fixed **236pt** and the side slot grows to 80pt so the
full label fits beside a centered waveform. The chip uses `.fixedSize()` to never truncate.

## GOTCHA: OSLog subsystem is a rebrand leftover
`os_log` calls still use subsystem `"com.zachlatta.freeflow"` (hardcoded, not rebranded). To read
the app's logs: `log show --predicate 'subsystem == "com.zachlatta.freeflow"' --info`. Note info-level
logs are largely memory-only and often absent from `log show`.
