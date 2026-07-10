#!/usr/bin/env python3
"""
Casual-mode before/after eval against your real saved Messages dictations.

It reads the saved pipeline history (the same SQLite DB the app writes), pulls
every dictation that ran in an iMessage/SMS window, and re-runs each raw
transcript through the NEW casual system prompt. It prints, side by side:

    RAW     – what the speech-to-text produced
    BEFORE  – the casual output the app actually saved (over-punctuated)
    AFTER   – the casual output with the new prompt

So you can judge the fix on your own data, not vibes. Re-run it after any future
prompt tweak — it's a standing regression check.

Usage:
    GROQ_API_KEY=sk-... python3 Tools/casual-eval/eval.py
    # optional overrides:
    MODEL=openai/gpt-oss-120b DB_PATH="/path/PipelineHistory.sqlite" python3 Tools/casual-eval/eval.py

No third-party deps (sqlite3 + urllib from the stdlib).
"""
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request

DEFAULT_DB = os.path.expanduser(
    "~/Library/Application Support/Rhapsode Dev/PipelineHistory.sqlite"
)
DB_PATH = os.environ.get("DB_PATH", DEFAULT_DB)
MODEL = os.environ.get("MODEL", "openai/gpt-oss-120b")
BASE_URL = os.environ.get("GROQ_BASE_URL", "https://api.groq.com/openai/v1")
API_KEY = os.environ.get("GROQ_API_KEY", "")

# Mirrors DictationMode.casual.promptSnippet in Sources/DictationModes/DictationModes.swift.
# Keep in sync if you edit the Swift source.
NEW_CASUAL_SNIPPET = "\n\n" + (
    "This is a casual text message (iMessage, SMS, or a chat app). Match how the speaker "
    "texts a friend: relaxed and informal, but still readable. Keep their normal "
    "capitalization, commas, question marks, exclamation points, names, and the word \"I\". "
    "The only casual touch is that you may drop the period at the very end of the message. "
    "Do not lowercase everything and do not strip out commas or other punctuation. "
    "No greeting and no sign-off."
)


def fetch_cases(db_path):
    if not os.path.exists(db_path):
        sys.exit(f"DB not found: {db_path}\nSet DB_PATH=... to point at PipelineHistory.sqlite")
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        """
        SELECT ZRAWTRANSCRIPT AS raw, ZPOSTPROCESSEDTRANSCRIPT AS before,
               ZSYSTEMPROMPT AS base, ZCONTEXTSUMMARY AS context
        FROM ZPIPELINEHISTORYENTRY
        WHERE ZCONTEXTBUNDLEIDENTIFIER = 'com.apple.MobileSMS'
          AND ZINTENT = 'dictation'
          AND ZRAWTRANSCRIPT IS NOT NULL AND ZRAWTRANSCRIPT <> ''
        ORDER BY ZTIMESTAMP
        """
    ).fetchall()
    con.close()
    return rows


def run_casual(base_prompt, context, raw):
    system_prompt = (base_prompt or "") + NEW_CASUAL_SNIPPET
    user_message = (
        "Instructions: Clean up RAW_TRANSCRIPTION and return only the cleaned transcript "
        "text without surrounding quotes. Return EMPTY if there should be no result.\n\n"
        f'CONTEXT: "{context or ""}"\n\n'
        f'RAW_TRANSCRIPTION: "{raw}"'
    )
    payload = {
        "model": MODEL,
        "temperature": 0.0,
        "max_completion_tokens": 4096,
        "reasoning_effort": "low",
        "include_reasoning": False,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
    }
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.load(resp)
    return body["choices"][0]["message"]["content"].strip().strip('"')


def main():
    if not API_KEY:
        sys.exit("Set GROQ_API_KEY=... (the eval makes one short Groq call per saved case).")
    cases = fetch_cases(DB_PATH)
    if not cases:
        sys.exit("No iMessage dictations found in history.")
    print(f"Model: {MODEL}   Cases: {len(cases)}\n" + "=" * 72)
    for i, c in enumerate(cases, 1):
        try:
            after = run_casual(c["base"], c["context"], c["raw"])
        except urllib.error.HTTPError as e:
            after = f"<HTTP {e.code}: {e.read().decode()[:200]}>"
        except Exception as e:  # noqa: BLE001
            after = f"<error: {e}>"
        print(f"\n#{i}")
        print(f"  RAW    : {c['raw']}")
        print(f"  BEFORE : {c['before']}")
        print(f"  AFTER  : {after}")
    print("\n" + "=" * 72)


if __name__ == "__main__":
    main()
