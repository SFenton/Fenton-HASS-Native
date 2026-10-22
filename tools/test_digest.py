#!/usr/bin/env python3
"""Reduce an xcodebuild, ``swift test`` or script log to a digest of at most ~30 lines.

Agents read the digest, never the log: a result, the failing tests with their first assertion, the first
compile errors, and whether the run died of infrastructure (Device Hub, hung hold, unavailable simulator)
rather than a test. Run through ``tools/bg_run.py`` it is printed when the command exits.

Usage: tools/test_digest.py LOG [--exit-code N] [--elapsed SECONDS] [--label NAME] [--max-lines N]
       some-command 2>&1 | tools/test_digest.py -
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import OrderedDict
from typing import Dict, Iterable, List, Optional, Tuple

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

XC_RESULT = re.compile(r"Test Case '-\[(?P<cls>[\w.]+) (?P<name>\w+)\]' (?P<state>passed|failed) \(")
XC_FAIL_MESSAGE = re.compile(r"(?P<where>[^\s:]+\.swift:\d+): error: -\[(?P<cls>[\w.]+) (?P<name>\w+)\] : (?P<msg>.*)")
XC_EXECUTED = re.compile(r"Executed (?P<n>\d+) tests?, with (?P<f>\d+) failures?")
ST_ISSUE = re.compile(r"✘ Test (?P<name>[\w`' ]+?)\(?\)? recorded an issue at (?P<where>[^\s:]+\.swift:\d+)(?::\d+)?: (?P<msg>.*)")
ST_FAILED = re.compile(r"✘ Test (?P<name>[\w`' ]+?)\(?\)? failed after")
ST_PASSED = re.compile(r"✔ Test (?P<name>[\w`' ]+?)\(?\)? passed after")
ST_RUN = re.compile(r"[✔✘] Test run with (?P<n>\d+) tests?.*?(?P<state>passed|failed)")
COMPILE_ERROR = re.compile(r"(?P<where>/?[^\s:]+\.swift:\d+):\d+: error: (?P<msg>.*)")

#: (label, pattern, advice). The first match wins, so list the most specific first.
INFRA: List[Tuple[str, "re.Pattern[str]", str]] = [
    ("hold timeout", re.compile(r"hold timeout|gave up waiting"), "devcap killed a hung run; check `devcap.py status`, rerun once"),
    ("Device Hub pose", re.compile(r"DeviceHubError|Pressed the unfolded control"), "the Duo pose control did not take; rerun once, then `devcap.py pose`"),
    ("simulator unavailable", re.compile(r"^GAP:", re.M), "a gap, not a pass; create the simulator"),
    ("simulator boot/launch", re.compile(r"Unable to boot|Invalid device state|Failed to launch|Early unexpected exit"), "simulator did not come up; rerun once"),
    ("test host crash", re.compile(r"crashed with signal|Test crashed"), "the app or test host crashed; read the crash log named in the full log"),
    ("SwiftPM lock", re.compile(r"Another instance of SwiftPM|waiting for lock"), "another build holds the package; wait for it"),
]


def clean(text: str) -> str:
    """Strip ANSI colour codes."""
    return ANSI.sub("", text)


def short(text: str, width: int = 170) -> str:
    """Collapse whitespace and cut to ``width`` characters."""
    text = " ".join(text.split())
    return text if len(text) <= width else text[: width - 1] + "…"


class Digest:
    """What one log said."""

    def __init__(self) -> None:
        self.passed: "OrderedDict[str, None]" = OrderedDict()
        self.failed: "OrderedDict[str, str]" = OrderedDict()  # test -> first message
        self.build_errors: "OrderedDict[str, None]" = OrderedDict()
        self.suite_status: Optional[str] = None  # "succeeded" / "failed" from ** TEST ** / ** BUILD **
        self.build_status: Optional[str] = None
        self.executed = 0
        self.executed_failures = 0
        self.st_run: Optional[Tuple[int, str]] = None
        self.infra: "OrderedDict[str, int]" = OrderedDict()
        self.tail: List[str] = []

    def feed(self, lines: Iterable[str]) -> None:
        """Read every line of a log."""
        recent: List[str] = []
        for raw in lines:
            line = clean(raw.rstrip("\n"))
            if line.strip():
                recent.append(line)
                if len(recent) > 12:
                    recent.pop(0)
            self._line(line)
        self.tail = recent

    def _line(self, line: str) -> None:
        if match := ST_RUN.search(line):
            self.st_run = (int(match["n"]), match["state"])
        elif match := XC_FAIL_MESSAGE.search(line):
            test = f"{match['cls'].split('.')[-1]}.{match['name']}"
            self.failed.setdefault(test, f"{short(match['msg'], 140)} ({match['where'].split('/')[-1]})")
            self.passed.pop(test, None)
        elif match := XC_RESULT.search(line):
            test = f"{match['cls'].split('.')[-1]}.{match['name']}"
            if match["state"] == "passed":
                self.passed[test] = None
                # A retried test that finally passes is not a failure of the run.
                self.failed.pop(test, None)
            else:
                self.failed.setdefault(test, "failed")
                self.passed.pop(test, None)
        elif match := ST_ISSUE.search(line):
            name = match["name"].strip()
            self.failed[name] = f"{short(match['msg'], 140)} ({match['where'].split('/')[-1]})"
        elif match := ST_FAILED.search(line):
            self.failed.setdefault(match["name"].strip(), "failed")
        elif match := ST_PASSED.search(line):
            self.passed[match["name"].strip()] = None
        elif match := XC_EXECUTED.search(line):
            if int(match["n"]) > 0:
                self.executed = max(self.executed, int(match["n"]))
                self.executed_failures = max(self.executed_failures, int(match["f"]))
        elif match := COMPILE_ERROR.search(line):
            self.build_errors.setdefault(f"{match['where'].split('/')[-1]}: {short(match['msg'], 130)}", None)
        if "** TEST SUCCEEDED **" in line:
            self.suite_status = "succeeded"
        elif "** TEST FAILED **" in line:
            self.suite_status = "failed"
        elif "** BUILD FAILED **" in line:
            self.build_status = "failed"
        elif "** BUILD SUCCEEDED **" in line:
            self.build_status = "succeeded"
        for label, pattern, _ in INFRA:
            if pattern.search(line):
                self.infra[label] = self.infra.get(label, 0) + 1

    def verdict(self, exit_code: Optional[int]) -> str:
        """``PASS``, ``FAIL`` (tests or build), ``INFRA`` (died of the machine) or ``UNKNOWN``."""
        failed_tests = bool(self.failed) or self.suite_status == "failed" or (self.st_run and self.st_run[1] == "failed")
        build_failed = self.build_status == "failed" or bool(self.build_errors and not self.passed)
        if exit_code == 0 and not failed_tests and not build_failed:
            return "PASS"
        if failed_tests or build_failed:
            return "FAIL"
        if self.infra:
            return "INFRA"
        if exit_code is None:
            ok = self.suite_status == "succeeded" or (self.st_run and self.st_run[1] == "passed")
            return "PASS" if ok else "UNKNOWN"
        return "FAIL" if exit_code else "PASS"

    def render(self, exit_code: Optional[int], elapsed: Optional[float], label: str, log: str, max_lines: int) -> str:
        """Format the digest."""
        verdict = self.verdict(exit_code)
        head = f"RESULT: {verdict}"
        if exit_code is not None:
            head += f" (exit {exit_code})"
        if label:
            head += f"  {label}"
        if elapsed is not None:
            head += f"  {describe(elapsed)}"
        out = [head]

        counts = []
        if self.st_run:
            counts.append(f"swift-testing: {self.st_run[0]} tests {self.st_run[1]}")
        if self.executed:
            counts.append(f"xctest executed {self.executed}, {self.executed_failures} failures")
        if self.passed or self.failed:
            counts.append(f"named: {len(self.passed)} passed, {len(self.failed)} failed")
        if counts:
            out.append("tests: " + "; ".join(counts))

        budget = max(4, max_lines - len(out) - 6)
        if self.failed:
            out.append(f"FAILED ({len(self.failed)}):")
            for test, message in list(self.failed.items())[: max(3, budget // 2)]:
                out.append(f"  {test}: {message}")
            if len(self.failed) > max(3, budget // 2):
                out.append(f"  … and {len(self.failed) - max(3, budget // 2)} more (grep 'failed (' in the log)")
        if self.build_errors:
            out.append(f"BUILD ERRORS ({len(self.build_errors)}):")
            for error in list(self.build_errors)[: max(3, budget // 2)]:
                out.append(f"  {error}")
        if self.infra:
            for label_, pattern, advice in INFRA:
                if label_ in self.infra:
                    kind = "INFRA (not a test failure)" if verdict in ("INFRA", "UNKNOWN") else "infra noise seen"
                    out.append(f"{kind}: {label_} x{self.infra[label_]}: {advice}")
        if verdict in ("UNKNOWN", "FAIL") and not (self.failed or self.build_errors or self.infra):
            out.append("last lines:")
            out.extend(f"  {short(line, 150)}" for line in self.tail[-8:])
        out.append(f"log: {log}" if log else "log: (stdin)")
        return "\n".join(out[: max_lines + 2])


def describe(seconds: float) -> str:
    """Format a duration as ``45s``, ``3m05s`` or ``2h05m``."""
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m{seconds % 60:02d}s"
    return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"


def digest_text(text: str, exit_code: Optional[int] = None, elapsed: Optional[float] = None, label: str = "",
                log: str = "", max_lines: int = 30) -> str:
    """Digest a log held in memory."""
    digest = Digest()
    digest.feed(text.splitlines())
    return digest.render(exit_code, elapsed, label, log, max_lines)


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point; exits 0 whatever the verdict, so a digest never hides behind a status."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", help="log file, or - for stdin")
    parser.add_argument("--exit-code", type=int)
    parser.add_argument("--elapsed", type=float)
    parser.add_argument("--label", default="")
    parser.add_argument("--max-lines", type=int, default=30)
    args = parser.parse_args(argv)
    digest = Digest()
    if args.log == "-":
        digest.feed(sys.stdin)
    else:
        with open(args.log, encoding="utf-8", errors="replace") as handle:
            digest.feed(handle)
    print(digest.render(args.exit_code, args.elapsed, args.label, "" if args.log == "-" else args.log, args.max_lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
