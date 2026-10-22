#!/usr/bin/env python3
"""PreToolUse hook for Agent: delegated work must not inherit Opus by accident.

Opus plans and does the final review; lanes run on `coder` (Sonnet) and chores on `menial` (Haiku). A spawn
passes when it names `coder`, `menial`, `Explore`, `Plan` or a docs/web helper, or sets `model` to Sonnet or
Haiku. A `general-purpose` spawn with no model, or any spawn asking for Opus, is refused with the fix. A spawn
that really needs Opus (the final reviewer) says `opus-ok: reason` in its prompt. Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import sys
from typing import Dict, List, Optional

LANE_TYPES = {"coder", "menial", "Explore", "Plan", "claude-code-guide", "statusline-setup", "web-fetch"}
CHEAP = ("sonnet", "haiku")

MESSAGE = (
    "Blocked: this subagent would run on Opus. Delegate with subagent_type \"coder\" (Sonnet, implementation, "
    "tests, builds) or \"menial\" (Haiku: re-runs, logs, git chores), or pass model \"sonnet\"/\"haiku\". Opus is "
    "for planning and the final review; if this spawn is that review, put `opus-ok: reason` in its prompt. "
    "See .agents/workflow/token-economy.md."
)


def reason(tool_input: Dict) -> Optional[str]:
    """Why the spawn is refused, or ``None``."""
    if "opus-ok" in str(tool_input.get("prompt", "")):
        return None
    model = str(tool_input.get("model") or "").lower()
    kind = tool_input.get("subagent_type")
    if "opus" in model:
        return "model is Opus"
    if any(name in model for name in CHEAP):
        return None
    if kind in LANE_TYPES:
        return None
    return f"subagent_type {kind or 'general-purpose'} with no model inherits Opus"


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") not in ("Agent", "Task"):
        return 0
    why = reason(payload.get("tool_input") or {})
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
