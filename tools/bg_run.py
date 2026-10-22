#!/usr/bin/env python3
"""Run a long command and print only its digest when it exits.

Launch it with the Bash tool's ``run_in_background: true`` and end the turn: the harness notifies you when it
exits, and the notification carries the digest, not the log. Never poll the log with ``until … sleep``.

    tools/bg_run.py LABEL [--timeout SECONDS] [--dir DIR] -- COMMAND [ARG …]

The full output goes to ``build/runs/LABEL.log`` (``--dir`` to change it) and the digest, from
``tools/test_digest.py``, to ``LABEL.digest`` next to it. The exit status is the command's, or 124 after
``--timeout`` (the process group is killed).
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_digest  # noqa: E402


def run(label: str, command: List[str], directory: Path, timeout: Optional[float]) -> int:
    """Run ``command`` with output to ``directory/label.log``, print its digest and return its status."""
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / f"{label}.log"
    started = time.monotonic()
    status = 0
    with open(log, "wb") as handle:
        process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                   start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            status = 124
            handle.write(f"\nbg_run: hold timeout, killed after {int(timeout or 0)}s\n".encode())
    elapsed = time.monotonic() - started
    text = log.read_text(encoding="utf-8", errors="replace")
    digest = test_digest.digest_text(text, exit_code=status, elapsed=elapsed, label=label, log=str(log))
    (directory / f"{label}.digest").write_text(digest + "\n", encoding="utf-8")
    print(digest)
    return status


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--" not in argv:
        print(__doc__, file=sys.stderr)
        return 2
    split = argv.index("--")
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("label")
    parser.add_argument("--timeout", type=float)
    parser.add_argument("--dir", type=Path, default=ROOT / "build" / "runs")
    args = parser.parse_args(argv[:split])
    command = argv[split + 1:]
    if not command:
        print("bg_run: no command after --", file=sys.stderr)
        return 2
    return run(args.label, command, args.dir, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
