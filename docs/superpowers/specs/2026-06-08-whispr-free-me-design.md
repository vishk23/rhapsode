# Whispr Free Me — Design

- **Date:** 2026-06-08
- **Status:** Approved (overall vision + Phase 0); later phases get their own specs
- **Fork of:** [zachlatta/freeflow](https://github.com/zachlatta/freeflow) (MIT)
- **Working name:** "Whispr Free Me" (rename is cheap; not final)

## 1. Summary

freeflow is a native macOS menu-bar dictation app (**voice → text**). This fork makes it a
**two-way voice tool**: it learns your voice while you dictate, clones it in the cloud, and
adds **text → voice in your own voice, anywhere** — plus a dashboard to see your usage and
your voice data.

Three features on a shared foundation:

- **F — Voice Bank** (foundation): opt-in, local, durable capture of `(audio, transcript)`
  pairs while you dictate. The training dataset.
- **A — Dashboard:** a native window of usage stats ("see your voice and related stuff").
- **B — Voice clone pipeline:** bank audio → "Create My Voice" → ElevenLabs clone.
- **C — Speak as me anywhere:** global hotkey → selected/typed text → cloud TTS in your
  voice → played into any app. The mirror image of dictation.

## 2. Background: what freeflow actually is

Native macOS app, Swift + SwiftUI + AVFoundation, menu-bar resident. Key facts established by
reading the source:

- **Audio** is captured by `Sources/AudioRecorder.swift` as normalized **16 kHz mono PCM16
  WAV**, written to a **temp file**, uploaded for transcription, then **deleted**
  (`cleanup()` / `finishAudioFileLocked(discard:)`). The realtime path also emits 24 kHz
  PCM16 chunks.
- **Per-dictation history** is logged to a local **Core Data SQLite** store
  (`Sources/PipelineHistoryStore.swift`, `Sources/PipelineHistoryItem.swift`) in
  `~/Library/Application Support/<AppName>/PipelineHistory.sqlite`. Each row already has:
  `rawTranscript`, `postProcessedTranscript`, `timestamp`, `intent`,
  `contextAppName` / `contextBundleIdentifier` / `contextWindowTitle`, and — notably — an
  **`audioFileName`** field plus cleanup logic that deletes referenced audio on
  trim/delete/clearAll. History is **capped** (`trim(to: maxCount)`).
- **Selection capture already exists** for "Edit Mode" (highlight text + speak an
  instruction): `selectedText` / `capturedSelection`.
- **Global hotkeys**: `HotkeyManager.swift`, `GlobalShortcutBackend.swift`,
  `ShortcutBinding.swift`, `Sources/ShortcutCore/`.
- **Audio ducking** (mute/pause other audio while dictating) already exists.
- **Providers are configurable** (OpenAI-compatible base URLs + model IDs) and API keys live
  in `KeychainStorage.swift`.
- **Privacy promise** (README): *"There is no FreeFlow server, so FreeFlow does not store or
  retain your data."*

Implication: the dashboard is mostly aggregation over data already captured; voice capture is
a matter of *not deleting* the WAV and storing it durably; speak-as-me reuses hotkeys,
selection capture, and ducking.

## 3. Goals / non-goals

**Goals**
- Bank a high-quality local voice dataset passively, starting as early as possible.
- A native dashboard of usage + voice-data stats.
- One-click cloud voice clone from banked audio (ElevenLabs).
- System-wide "speak in my voice" on selected/typed text.
- Keep the app cleanly **upstream-contributable**: default-off, local-first, opt-in.

**Non-goals**
- Training/hosting a TTS model locally (we use a cloud provider).
- A web dashboard or any server component.
- Multi-user / accounts / cloud sync of the dataset.

## 4. Key decisions (each was a fork in the road)

1. **Dashboard = native SwiftUI window, not web.** No server, ships in-binary, consistent
   with the app. Uses Swift Charts (built-in, macOS 13+).
2. **Provider = ElevenLabs, but configurable.** Best instant + professional cloning API and
   low-latency streaming TTS. Mirror freeflow's configurable-provider pattern so it is
   swappable; key in `KeychainStorage`.
3. **Everything that stores audio or sends it off-device is default-OFF, opt-in.** If you
   never opt in, behavior is identical to today's freeflow. This preserves the upstream
   privacy promise and keeps the fork mergeable.
4. **Label samples with `rawTranscript`, not `postProcessedTranscript`.** The cleaned text
   (filler removed, edits applied, Edit-Mode transforms) does not match the audio; training
   needs transcript == audio. Realtime-only transcriptions that never produced a stable raw
   transcript are excluded.
5. **Voice Bank is decoupled from the capped history.** Banked samples live in their own
   store and are never trimmed by the rolling history cap.

## 5. Privacy & consent model (cross-cutting)

Layered, escalating consent — passive local storage is the lowest tier; off-device egress is
always an explicit, per-action click.

- **Tier 0 — default:** nothing stored, nothing extra sent. Identical to upstream freeflow.
- **Tier 1 — Voice Bank (opt-in toggle):** local audio + transcript saved to Application
  Support. Disclosed plainly: what's saved, where, that nothing is uploaded yet, how to
  delete. A visible "banking on" indicator and an easy pause.
- **Tier 2 — Create My Voice (per-action):** uploading to ElevenLabs is a deliberate button
  with an explicit summary ("uploads N clips / M minutes to ElevenLabs"). Never passive.
- **Tier 3 — Speak as me (per-action):** sends only the specific text you trigger to the TTS
  API.

Sensitive-content risk (you might dictate passwords/PII while banking is on) is mitigated by:
opt-in, visible active indicator, easy pause, and easy per-sample + bulk delete. Per-app
exclude lists are a future enhancement.

## 6. Architecture

### F — Voice Bank
- **New `VoiceBankStore`** (modeled on `PipelineHistoryStore`, own SQLite file) so it is
  isolated from history trimming and migrations.
- **`VoiceSample`** record: `id`, `createdAt`, `audioFileName` (relative path),
  `transcript` (raw), `durationMs`, `sampleRate`, `rms`/quality, `appBundleId?`, `intent`.
  (Phase B adds `providerVoiceId?` / `uploadedAt?` to track what was used.)
- **WAV files** in `~/Library/Application Support/<App>/VoiceBank/<uuid>.wav` (16 kHz mono
  PCM16, the format already produced).
- **Capture hook:** at the post-transcription success point in the dictation orchestration
  (`AppState`), when banking is enabled and the clip passes the quality gate, copy the WAV
  (instead of deleting) and insert a `VoiceSample`.
- **Quality gate:** drop clips that are silent / too short / had empty or failed
  transcription; keep only `dictation` intent (not command/edit).
- **Management:** Settings section with stats (count, minutes, disk size), a basic sample
  list (date, duration, transcript preview, play, delete), "open folder", and "delete all".

### A — Dashboard
- Native window opened from the menu bar; reads `PipelineHistoryStore` + `VoiceBankStore`.
- Cards: total dictations & words, speaking **WPM**, **time saved vs typing**
  (`words/40wpm − speaking time`), daily **streak**, 30/90-day activity chart (Swift Charts),
  **top apps** (from `contextBundleIdentifier`), cleanup impact (raw vs cleaned diff), and
  **Voice Bank readiness** (minutes banked vs thresholds for instant/professional cloning).
- **Gap to fill:** per-dictation duration is not stored today. Start capturing `durationMs` +
  `wordCount` on every dictation (added in Phase 0 since we touch that path for the Bank);
  estimate for pre-existing rows.

### B — Voice clone pipeline
- "Create My Voice" screen: banked minutes, readiness meter, tier choice, the Tier-2 upload
  consent, post-create status. Stores the returned `voice_id`.
- **Instant Voice Cloning** (~1–5 min, near-instant) for an immediate first voice.
- **Professional Voice Cloning** (~30 min–3 hr, trains over hours, higher fidelity) once
  enough audio is banked; create → upload samples → start training → poll status.
- Picks best clips (longest, cleanest, highest quality, successful transcript) within
  provider limits. ElevenLabs ToS: you are cloning your own voice (consent satisfied).

### C — Speak as me anywhere
- New global hotkey (reuse `HotkeyManager` / `ShortcutBinding`).
- Text source: current selection (reuse Edit-Mode selection capture) with a typed/clipboard
  fallback.
- Synthesis: ElevenLabs streaming TTS (`/v1/text-to-speech/{voice_id}/stream`) with the
  stored `voice_id`.
- Playback: play through the output device, **duck other audio** (reuse existing ducking),
  show a "speaking…" overlay with cancel (reuse `RecordingOverlay`).
- Requires a `voice_id` from B, or a manually pasted one for early dev/testing.

## 7. Build sequence

Dependencies run **F → B → C**; **A** is independent. Voice Bank is pulled into Phase 0 so
data collection starts ASAP.

| Phase | Scope | Rationale |
|-------|-------|-----------|
| **0** | Fork + minimal rebrand; **Voice Bank (F)**: opt-in capture, consent, basic browse/delete; capture `durationMs`/`wordCount` | Start banking immediately; establish the repo |
| **1** | **Dashboard (A)** | Independent, low-risk, shows real banked minutes |
| **2** | **Voice clone (B)** — instant then professional | Needs banked audio |
| **3** | **Speak as me (C)** | Consumes the clone (dev-testable early with a pasted voice_id) |

Each phase = its own spec → plan → build → PR. Phase 1 is cleanly upstream-contributable;
Phases 0/2/3 are opt-in modules that can also be proposed upstream given default-off design.

## 8. Phase 0 — detailed spec (first implementation target)

**Outcome:** the app builds and runs under the new identity and, when you flip one opt-in
toggle, durably banks `(audio, raw transcript)` pairs locally that you can review and delete.

### 8.1 Fork + minimal rebrand
- Create the GitHub fork (`gh repo fork zachlatta/freeflow --fork-name whispr-free-me`),
  set `origin` to the fork, keep `upstream`.
- Rebrand to build/run under a new identity: `AppName.swift` display name; `Info.plist`
  `CFBundleName` + `CFBundleIdentifier` (`com.zachlatta.freeflow` → e.g.
  `com.vishk23.whisprfreeme`); `FreeFlow.entitlements`; enough of `Makefile` to build locally.
  Changing the bundle id changes the `defaults` domain and the Application Support folder name
  (`AppName.displayName`) — a **fresh data home**, which is expected and acceptable for a fork.
- **Trailing (not blocking):** app icons, README, `website/`, release workflows.

### 8.2 Voice Bank
- Add `VoiceBankStore` + `VoiceSample` (section 6/F).
- Add the capture hook + quality gate in the dictation orchestration, gated by the opt-in.
- Capture `durationMs` + `wordCount` on every dictation (for A later).
- Settings "Voice Bank" section: master toggle (default OFF), disclosure text, stats, basic
  sample list (play/delete), "open folder", "delete all".
- Menu-bar / overlay indicator when banking is active.

### 8.3 Out of scope for Phase 0
Dashboard visuals (Phase 1), any ElevenLabs/network code (Phase 2), speak-as-me (Phase 3),
audio compression, per-app exclusions.

### 8.4 Testing
- `VoiceBankStore` CRUD + decoupling from history trim (banked samples survive a trim).
- Quality gate (silent/short/empty-transcript rejected; good clips accepted).
- Opt-in OFF ⇒ zero files written, behavior identical to upstream (the privacy invariant).
- Capture hook pairs the WAV with the **raw** transcript and correct duration.

## 9. Risks & open questions

- **Storage growth:** 16 kHz mono PCM16 ≈ ~1.9 MB/min (~115 MB/hr). Show disk usage; offer
  delete. Future: FLAC (lossless) to cut size without hurting training.
- **Sensitive content** banked while enabled — mitigations in §5; revisit per-app excludes.
- **Transcript fidelity** for the realtime path; confirm a stable raw transcript exists
  before banking.
- **ElevenLabs API specifics** (IVC vs PVC limits, minutes, endpoints, streaming) to be
  pinned down in the Phase 2 spec.
- **Naming** not final.

## 10. Contributing upstream

Default-off, local-first design means each module can be proposed to upstream freeflow
independently. The dashboard (Phase 1) is the most obviously mergeable. The voice features are
opt-in and self-contained, so they are candidates too if upstream wants them.
