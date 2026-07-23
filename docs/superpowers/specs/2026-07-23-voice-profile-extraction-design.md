# Voice Profile Extraction — Design

**Date:** 2026-07-23
**Status:** Approved

## Goal

Turn the dictation history Rhapsode already banks (~493 entries, ~16k words in
`PipelineHistory.sqlite`) into two deliverables the user can hand to any AI
agent (immediately: Codex, writing their personal website) so it writes copy in
their authentic voice:

1. `corpus.md` — the full cleaned transcript dump, context-annotated.
2. `VOICE.md` — a distilled, comprehensive voice profile with verbatim
   exemplars, written by Claude after reading the corpus.

## Decisions made during brainstorming

- **One comprehensive document, not a pre-blended register.** Every pattern
  and exemplar is tagged with its source context (iMessage vs. Claude vs.
  Safari, etc.). The consuming agent sees the full range — casual and working
  voice — and calibrates itself; the profile notes that the user's casual
  voice already overlaps with professional.
- **Distillation over dumping.** The profile + ~30 verbatim exemplars is the
  handoff artifact, not the 16k-word corpus. Style signal drowns in content
  noise at full-corpus scale; models imitate exemplars better than adjectives.
- **Raw transcripts are the primary source.** They are truer to the spoken
  voice than the LLM-cleaned versions. Where raw and cleaned differ, the diff
  is itself signal (dictation tics vs. intended words) and is surfaced in the
  corpus.
- **Doc-now, skill-later.** The extraction script is the reusable core. A
  future `/write-as-me` skill or MCP that re-extracts fresh dictations and
  regenerates the profile is a small follow-up with no rework.

## Components

### 1. Extraction script — `Tools/voice-profile/extract.py`

Follows the `Tools/casual-eval/` precedent: standalone Python, stdlib only
(`sqlite3`, `argparse`, `shutil`).

- **Input:** `~/Library/Application Support/Rhapsode/PipelineHistory.sqlite`.
  Copies the DB (plus `-wal`/`-shm`) to a temp location and opens the copy
  read-only, so a live app writing WAL is never disturbed.
- **Columns:** `ZTIMESTAMP`, `ZCONTEXTAPPNAME`, `ZCONTEXTBUNDLEIDENTIFIER`,
  `ZRAWTRANSCRIPT`, `ZPOSTPROCESSEDTRANSCRIPT`, `ZINTENT`.
- **Filters:** drop entries with empty/failed raw transcripts, fragments under
  5 words, and exact-duplicate transcripts (keep first occurrence).
- **Output:** `corpus.md` (default `~/VoiceProfile/corpus.md`, `--out` to
  override). Grouped by app context, chronological within group. Each entry:
  date, raw transcript; when the cleaned transcript differs materially
  (normalized comparison), it is shown beneath as `cleaned:` for the
  tic-vs-intent contrast. Header includes corpus stats (entry count, word
  count, context breakdown).

### 2. Voice profile — `~/VoiceProfile/VOICE.md`

Written by Claude after reading `corpus.md` in full. Structure:

1. **Preamble to the consuming agent** — "you are writing as VK", how to use
   the document, how to weight registers for a given task (e.g. professional
   website copy).
2. **Register spectrum** — casual ↔ working voice, where they overlap, tagged
   observations per context.
3. **Vocabulary & recurring phrases.**
4. **Sentence rhythm & syntax habits** (e.g. stacked rhetorical questions,
   hedging chains).
5. **Emphasis & hedging patterns.**
6. **Anti-patterns** — constructions the user never uses.
7. **~30 verbatim exemplars**, each tagged `[Messages]`, `[Claude]`, etc.

## Privacy boundary

Rhapsode is a public repo. The **script and this spec are committable**; the
**outputs are personal speech and never touch git**. Outputs default to
`~/VoiceProfile/` (outside the repo), and `Tools/voice-profile/.gitignore`
excludes any locally generated output as a second fence.

## Error handling

- DB missing → clear message pointing at the expected path.
- Schema drift (missing column) → fail loudly with the column name.
- Zero surviving entries after filters → say so, don't write an empty corpus.

## Testing

Script is a one-shot personal tool: verified by running it against the real DB
and inspecting `corpus.md` (entry counts match a direct SQL count, no empty
bodies, groups present). No unit-test suite — matches the `casual-eval`
precedent for `Tools/`.

## Success criteria

- `corpus.md` contains every non-junk dictation, context-grouped, with stats.
- `VOICE.md` is self-contained: pasting it into a fresh Codex/Claude session
  with "write my website hero section" produces copy recognizably in the
  user's voice.
- Nothing personal is committed to the public repo.

## Future path (out of scope now)

- `/write-as-me` skill or MCP server: runs `extract.py` on demand, feeds the
  fresh corpus + profile to the agent, keeps the profile current as dictation
  history grows day to day.
