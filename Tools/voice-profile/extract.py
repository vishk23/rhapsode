#!/usr/bin/env python3
"""Extract dictation transcripts from Rhapsode's history into a voice corpus.

Reads PipelineHistory.sqlite (Core Data store), filters junk, and writes a
context-grouped markdown corpus suitable for voice/style distillation.

Outputs are personal speech — never commit them. Default output dir is
~/VoiceProfile, outside the repo.
"""

import argparse
import datetime
import re
import shutil
import sqlite3
import sys
import tempfile
from collections import Counter
from pathlib import Path

DEFAULT_DB = Path.home() / "Library/Application Support/Rhapsode/PipelineHistory.sqlite"
DEFAULT_OUT = Path.home() / "VoiceProfile/corpus.md"
APPLE_EPOCH_OFFSET = 978307200  # Core Data timestamps count from 2001-01-01
MIN_WORDS = 5

REQUIRED_COLUMNS = [
    "ZTIMESTAMP",
    "ZCONTEXTAPPNAME",
    "ZCONTEXTBUNDLEIDENTIFIER",
    "ZRAWTRANSCRIPT",
    "ZPOSTPROCESSEDTRANSCRIPT",
    "ZINTENT",
]


def normalize(text):
    """Lowercase, strip punctuation/whitespace — for dedup and diff checks."""
    return re.sub(r"[^\w\s]", "", (text or "").lower()).split()


def copy_db(db_path):
    """Copy the store (plus WAL/SHM sidecars) so a live app is never disturbed."""
    tmpdir = Path(tempfile.mkdtemp(prefix="voice-profile-"))
    for suffix in ("", "-wal", "-shm"):
        src = Path(str(db_path) + suffix)
        if src.exists():
            shutil.copy2(src, tmpdir / src.name)
    return tmpdir / db_path.name


def load_entries(db_path):
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cols = {r[1] for r in conn.execute("PRAGMA table_info(ZPIPELINEHISTORYENTRY)")}
    missing = [c for c in REQUIRED_COLUMNS if c not in cols]
    if missing:
        sys.exit(f"error: schema drift — missing column(s): {', '.join(missing)}")
    rows = conn.execute(
        f"SELECT {', '.join(REQUIRED_COLUMNS)} FROM ZPIPELINEHISTORYENTRY ORDER BY ZTIMESTAMP"
    ).fetchall()
    conn.close()
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="path to PipelineHistory.sqlite")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output corpus path")
    parser.add_argument("--min-words", type=int, default=MIN_WORDS, help="drop shorter entries")
    args = parser.parse_args()

    if not args.db.exists():
        sys.exit(f"error: history database not found at {args.db}\n"
                 "expected Rhapsode's store in ~/Library/Application Support/Rhapsode/")

    rows = load_entries(copy_db(args.db))

    entries, seen = [], set()
    dropped = Counter()
    for row in rows:
        raw = (row["ZRAWTRANSCRIPT"] or "").strip()
        words = normalize(raw)
        if not raw:
            dropped["empty"] += 1
            continue
        if len(words) < args.min_words:
            dropped["short"] += 1
            continue
        key = " ".join(words)
        if key in seen:
            dropped["duplicate"] += 1
            continue
        seen.add(key)
        entries.append(row)

    if not entries:
        sys.exit("error: no entries survived filtering — nothing to write")

    by_app = {}
    for row in entries:
        app = row["ZCONTEXTAPPNAME"] or "Unknown"
        by_app.setdefault(app, []).append(row)

    total_words = sum(len(normalize(r["ZRAWTRANSCRIPT"])) for r in entries)
    lines = [
        "# Rhapsode dictation corpus",
        "",
        f"Extracted {datetime.date.today().isoformat()}. "
        f"{len(entries)} entries, ~{total_words} words "
        f"(dropped: {dropped['empty']} empty, {dropped['short']} short, {dropped['duplicate']} duplicate).",
        "",
        "Context breakdown: "
        + ", ".join(f"{app} {len(rs)}" for app, rs in sorted(by_app.items(), key=lambda kv: -len(kv[1]))),
        "",
        "Raw transcripts are the spoken voice; `cleaned:` lines show the LLM-cleaned",
        "version only where it differs materially (dictation tics vs. intended words).",
        "",
    ]

    for app, rs in sorted(by_app.items(), key=lambda kv: -len(kv[1])):
        lines += [f"## {app} ({len(rs)} entries)", ""]
        for row in rs:
            ts = datetime.datetime.fromtimestamp(row["ZTIMESTAMP"] + APPLE_EPOCH_OFFSET)
            intent = row["ZINTENT"]
            tag = f" · {intent}" if intent else ""
            lines.append(f"**{ts:%Y-%m-%d %H:%M}{tag}**  ")
            lines.append(row["ZRAWTRANSCRIPT"].strip())
            cleaned = (row["ZPOSTPROCESSEDTRANSCRIPT"] or "").strip()
            if cleaned and normalize(cleaned) != normalize(row["ZRAWTRANSCRIPT"]):
                lines.append(f"cleaned: {cleaned}")
            lines.append("")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines))
    print(f"wrote {args.out}: {len(entries)} entries, ~{total_words} words, {len(by_app)} contexts")


if __name__ == "__main__":
    main()
