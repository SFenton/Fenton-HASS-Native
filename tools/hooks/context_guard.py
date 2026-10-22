#!/usr/bin/env python3
"""PostToolUse hook: remind the model to hand off when its context is large.

Every turn re-reads the whole conversation, and sessions here grew to 500 to 900 k tokens. The reminder fires
once per threshold per transcript (state in the temp directory) and goes to the model as additional context.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional

THRESHOLDS = (150_000, 250_000, 400_000)
TAIL_BYTES = 2_000_000


def context_tokens(transcript: Path) -> Optional[int]:
    """Tokens the last assistant turn read (input + cache read + cache write), from the transcript tail."""
    try:
        size = transcript.stat().st_size
        with open(transcript, "rb") as handle:
            handle.seek(max(0, size - TAIL_BYTES))
            chunk = handle.read()
    except OSError:
        return None
    for raw in reversed(chunk.splitlines()):
        if b'"usage"' not in raw:
            continue
        try:
            record = json.loads(raw)
        except ValueError:
            continue
        usage = (record.get("message") or {}).get("usage") if record.get("type") == "assistant" else None
        if usage:
            return sum(int(usage.get(key) or 0) for key in
                       ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    return None


def reminder(tokens: int, level: int, subagent: bool) -> str:
    """The text for the highest threshold crossed."""
    k = tokens // 1000
    if subagent:
        return (f"Context is about {k}k tokens and every turn re-reads it. Do not start new items: finish "
                "the current one, then report back with the result and what is left.")
    if level == 0:
        return (f"Context is about {k}k tokens and every turn re-reads it. At the next natural stop (a commit, "
                "a PR, a green run) write build/handoff/<topic>.md (branch, state, next step, open failures; "
                "40 lines at most) and tell the user to continue in a fresh session from it.")
    return (f"Context is about {k}k tokens: each turn now costs several times a fresh session. Stop starting "
            "new work. Commit, write build/handoff/<topic>.md and tell the user to continue in a fresh session.")


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin and print additional context when a threshold is newly crossed."""
    try:
        payload: Dict = json.load(sys.stdin)
    except ValueError:
        return 0
    path = payload.get("transcript_path")
    if not path:
        return 0
    tokens = context_tokens(Path(path))
    if tokens is None:
        return 0
    level = max((i for i, limit in enumerate(THRESHOLDS) if tokens >= limit), default=-1)
    if level < 0:
        return 0
    state_dir = Path(os.environ.get("CONTEXT_GUARD_DIR") or Path(tempfile.gettempdir()) / "hass-context-guard")
    state = state_dir / hashlib.sha1(path.encode()).hexdigest()
    try:
        seen = int(state.read_text())
    except (OSError, ValueError):
        seen = -1
    if level <= seen:
        return 0
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        state.write_text(str(level))
    except OSError:
        pass
    text = reminder(tokens, level, "/subagents/" in path)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
