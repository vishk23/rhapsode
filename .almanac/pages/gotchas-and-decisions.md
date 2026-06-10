---
title: Build, signing, and gotchas
topics: [build-and-signing, gotchas, decisions]
files:
  - Makefile
  - Sources/TranscriptionService.swift
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
user later added a separate silent-clip guard (`isSilentClipFiller` / `capturedAudioWasSilent`) for
cold-start dropped audio.

## GOTCHA: AirPods can't do mic + hi-fi audio at once
Bluetooth can't run A2DP (stereo music) and the microphone (HFP) simultaneously. When the app opens
the AirPods mic, macOS forces HFP and the user's music gets re-leveled *louder*. Mitigation:
[[Sources/SystemAudioStatus.swift]] + `AppState.applyAudioInterruptionIfNeeded` smoothly **duck**
the system output volume to ~20% while dictating (a ramped volume change), with a **mute fallback**
when the device's volume isn't settable. The cleanest fix for pristine music is to dictate with the
built-in mic instead.

## GOTCHA: the mode chip needs the pill widened
The recording overlay ([[Sources/RecordingOverlay.swift]]) is cramped. The content-aware mode chip
(Formal/Code/Casual/Standard, color-coded) truncated to "ST…" in the narrow side slot. Fix: when a
mode chip is visible the pill widens to a fixed **236pt** and the side slot grows to 80pt so the
full label fits beside a centered waveform. The chip uses `.fixedSize()` to never truncate.

## GOTCHA: OSLog subsystem is a rebrand leftover
`os_log` calls still use subsystem `"com.zachlatta.freeflow"` (hardcoded, not rebranded). To read
the app's logs: `log show --predicate 'subsystem == "com.zachlatta.freeflow"' --info`. Note info-level
logs are largely memory-only and often absent from `log show`.
