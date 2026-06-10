---
title: Voice cloning and speak-as-me
topics: [voice-cloning, gotchas]
files:
  - Sources/ElevenLabsClient.swift
  - Sources/SpeakSelectionHotkey.swift
  - Sources/AppState.swift
  - Sources/KeychainStorage.swift
---

# Voice cloning and speak-as-me

The cloud half of the two-way tool. Provider is **ElevenLabs** (configurable in spirit, hardcoded
in [[Sources/ElevenLabsClient.swift]]). Endpoints used:

- **Clone (instant)** — `POST https://api.elevenlabs.io/v1/voices/add`, header `xi-api-key`,
  multipart `name` + repeated `files` (the best banked WAVs, ~5 min) + `remove_background_noise=true`.
  Returns `{ "voice_id": ... }`. Driven from the dashboard "Voice Clone" tab; upload is gated behind
  an explicit per-action consent dialog (the only off-device egress of the user's voice).
- **Speak (TTS)** — `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}`, header
  `xi-api-key`, JSON `{ text, model_id: "eleven_multilingual_v2" }`, returns MP3 played via
  `AVAudioPlayer` (held as an `AppState` property + delegate so it isn't deallocated mid-play).

## Where the keys live
The ElevenLabs API key (`elevenlabs_api_key`) and created voice id (`elevenlabs_voice_id`), like
the Groq key (`groq_api_key`), are stored in a JSON file at
`~/Library/Application Support/Whispr Free Me Dev/.settings` (0600), via `AppSettingsStorage` in
[[Sources/KeychainStorage.swift]] — which **migrated off the macOS Keychain to that file** (see the
`migrateFromKeychainIfNeeded` path). Reading the key from the Keychain will not find it.

## Speak-as-me triggers
1. Dashboard "Speak" tab (type → button) and a menu-bar "Speak Clipboard in My Voice" action (v1).
2. **⌥⌘S global hotkey** (v2) — [[Sources/SpeakSelectionHotkey.swift]] is an `NSEvent` global+local
   keyDown monitor, **deliberately isolated** from the dictation shortcut system (`HotkeyManager`/
   `ShortcutCore`) so it cannot break Fn dictation. On ⌥⌘S it grabs the frontmost selection
   (`AppContextService.collectSelectionSnapshot().selectedText`) and calls `speakAsMe`. Caveat:
   the global monitor is **observe-only** — ⌥⌘S also reaches the focused app (a consuming
   `CGEventTap` would be the v3 upgrade).

## GOTCHA: ElevenLabs free tier blocks everything we need
A free-tier ElevenLabs key returns `402 payment_required` for **both** cloning
(`paid_plan_required`, "subscription does not include instant voice cloning") **and** TTS with
library voices ("Free users cannot use library voices via the API"). The integration is correct —
these are subscription gates, not code bugs. Testing the clone or speak paths requires a paid plan
(Starter+).
