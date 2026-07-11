# Contributing

Rhapsode is a small, fast-moving project — contributions are welcome and the
bar is low-ceremony.

## Building

```bash
make CODESIGN_IDENTITY=- ARCH=$(uname -m)   # ad-hoc dev build
open "build/Rhapsode Dev.app"
swift test                                   # unit tests (SPM modules)
```

Ad-hoc signing means macOS re-asks for permissions after each rebuild; if you
have a Developer ID cert, pass its hash as `CODESIGN_IDENTITY` for grants that
stick (see the Makefile comment).

## Layout

- `Sources/` — the app, flat-compiled by the Makefile (no Xcode project).
- `Sources/Transcription`, `Sources/VoiceBank`, `Sources/DictationModes` —
  AppKit-free logic, also built as SwiftPM modules so `swift test` covers them.
  New pure logic should land in one of these (or a new module) with tests.
- `Tools/` — the replay harness (re-runs banked recordings through the
  pipeline), icon/banner generators, and eval scripts.
- `docs/evals/` — recorded benchmark methodology and results.

## Ground rules

- Test-first for pure logic; the existing suites show the style.
- The cleanup prompts are empirically tuned — see `docs/` and the CHANGELOG
  before "improving" them; several obvious-looking edits regress real usage.
- Upstream: Rhapsode began as a fork of
  [FreeFlow](https://github.com/zachlatta/freeflow) and still merges its fixes
  periodically. If your change is equally useful there, consider sending it
  upstream too.
