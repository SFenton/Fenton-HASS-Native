"""Agent hooks: ``tools/hooks/no_poll.py`` and ``tools/hooks/context_guard.py``."""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import context_guard  # noqa: E402
import no_poll  # noqa: E402

#: Commands lifted from the transcripts that cost a turn per ten minutes.
POLLS = [
    'until grep -q "exited with code" /private/tmp/x/tasks/bl0h.output 2>/dev/null; do sleep 15; done; cat /private/tmp/x/tasks/bl0h.output',
    "for i in $(seq 1 58); do [ -f $D/r.done ] && break; sleep 10; done; cat $D/r.log",
    "L=build1.log; until grep -qE '^rc=' $L; do sleep 5; done; tail -3 $L",
    "i=0; until grep -q done $L || [ $i -ge 38 ]; do sleep 3; i=$((i+1)); done",
    "while kill -0 34497 2>/dev/null; do sleep 5; done; echo done",
    "xcodebuild test ... ; sleep 120; cat out.log",
    "sleep 2m && cat out.log",
    "tail -f build/runs/x.log",
]
#: Ordinary commands, including ones that mention sleeping.
FINE = [
    "sleep 2; ps aux | grep -c '[s]wift-build'",
    "git status --short",
    "tools/bg_run.py uitest-iphone -- tools/ios_uitest.sh --only iphone",
    "python3 - <<'EOF'\nimport time\nwhile True:\n    do = 1\n    sleep 60\nEOF\necho ok",
    "grep -n 'Task.sleep' apple/Sources/HassCore/*.swift | head",
    "until grep -q ready log; do sleep 5; done  # poll-ok: sim boot, 20 s at most",
]


def run_hook(payload):
    err = io.StringIO()
    with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), redirect_stderr(err):
        status = no_poll.main()
    return status, err.getvalue()


class NoPollTests(unittest.TestCase):
    def test_blocks_polls_seen_in_the_transcripts(self):
        for command in POLLS:
            with self.subTest(command=command[:50]):
                status, message = run_hook({"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertEqual(status, 2)
                self.assertIn("run_in_background", message)

    def test_allows_ordinary_commands(self):
        for command in FINE:
            with self.subTest(command=command[:50]):
                self.assertEqual(run_hook({"tool_name": "Bash", "tool_input": {"command": command}})[0], 0)

    def test_ignores_other_tools_and_bad_input(self):
        self.assertEqual(run_hook({"tool_name": "Read", "tool_input": {"file_path": "x"}})[0], 0)
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(no_poll.main(), 0)


def write_transcript(path, usages):
    lines = [json.dumps({"type": "user", "message": {"content": "hi"}})]
    for usage in usages:
        lines.append(json.dumps({"type": "assistant", "message": {"usage": usage}}))
        lines.append(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "content": "x" * 50}]}}))
    Path(path).write_text("\n".join(lines) + "\n")


class ContextGuardTests(unittest.TestCase):
    def run_guard(self, transcript, state_dir):
        out = io.StringIO()
        payload = {"transcript_path": str(transcript)}
        with mock.patch.dict(os.environ, {"CONTEXT_GUARD_DIR": str(state_dir)}), \
                mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), redirect_stdout(out):
            self.assertEqual(context_guard.main(), 0)
        return json.loads(out.getvalue()) if out.getvalue() else None

    def test_counts_input_cache_read_and_cache_write(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "t.jsonl"
            write_transcript(path, [{"input_tokens": 2, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 50}])
            self.assertEqual(context_guard.context_tokens(path), 152)
            self.assertIsNone(context_guard.context_tokens(Path(tmp) / "missing.jsonl"))

    def test_silent_below_the_first_threshold(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "t.jsonl"
            write_transcript(path, [{"input_tokens": 2, "cache_read_input_tokens": 100_000, "cache_creation_input_tokens": 0}])
            self.assertIsNone(self.run_guard(path, Path(tmp) / "state"))

    def test_fires_once_per_threshold(self):
        with TemporaryDirectory() as tmp:
            path, state = Path(tmp) / "t.jsonl", Path(tmp) / "state"
            write_transcript(path, [{"input_tokens": 2, "cache_read_input_tokens": 160_000, "cache_creation_input_tokens": 0}])
            first = self.run_guard(path, state)
            self.assertIn("handoff", first["hookSpecificOutput"]["additionalContext"])
            self.assertEqual(first["hookSpecificOutput"]["hookEventName"], "PostToolUse")
            self.assertIsNone(self.run_guard(path, state))
            write_transcript(path, [{"input_tokens": 2, "cache_read_input_tokens": 260_000, "cache_creation_input_tokens": 0}])
            second = self.run_guard(path, state)
            self.assertIn("Stop starting new work", second["hookSpecificOutput"]["additionalContext"])

    def test_subagents_are_told_to_finish_not_to_hand_off(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "subagents" / "agent-a1.jsonl"
            path.parent.mkdir()
            write_transcript(path, [{"input_tokens": 2, "cache_read_input_tokens": 200_000, "cache_creation_input_tokens": 0}])
            text = self.run_guard(path, Path(tmp) / "state")["hookSpecificOutput"]["additionalContext"]
            self.assertIn("report back", text)

    def test_bad_payloads_are_ignored(self):
        for stdin in ("not json", "{}"):
            with mock.patch.object(sys, "stdin", io.StringIO(stdin)):
                self.assertEqual(context_guard.main(), 0)


if __name__ == "__main__":
    unittest.main()
