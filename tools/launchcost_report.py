#!/usr/bin/env python3
"""Summarises the launch cost probe's lines and checks them against the budgets.

Reads `LAUNCHCOST<TAB>case<TAB>key=value ...` lines (tools/ios_launchperf.sh writes them; the app's `LaunchCostProbe` makes them)
and prints one row per case: main-thread turn cost (p95, worst, turns over 8 and 16 ms) and the signpost intervals.

Budgets (simulator, main-thread CPU per run-loop turn; hitch ratios from a simulator mean nothing, see
.agents/testing/apple/performance.md): p95 turn <= 8 ms and no turn over 16 ms in every case; warm launch to the snapshot
(SnapshotShown) <= 400 ms; the arrival (Arrival) <= 1000 ms; the intro (Intro) <= 1500 ms.

Usage: launchcost_report.py FILE.tsv [--no-budget]   (exit 1 when a budget is missed)
"""
import sys

P95 = 8.0
WORST = 16.0
INTERVAL_BUDGETS = {"SnapshotShown_ms": 400.0, "Arrival_ms": 1000.0, "Intro_ms": 1500.0}
COLUMNS = ["p95_ms", "worst_ms", "over8", "over16", "main_ms", "turns", "Launch_ms", "SnapshotShown_ms", "SignIn_ms", "Intro_ms", "Arrival_ms"]


def parse(path):
    rows = []
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 3 or parts[0] != "LAUNCHCOST":
            continue
        values = {}
        for pair in parts[2].split():
            key, _, value = pair.partition("=")
            try:
                values[key] = float(value)
            except ValueError:
                pass
        rows.append((parts[1], values))
    return rows


def failures(case, values):
    problems = []
    if values.get("p95_ms", 0) > P95:
        problems.append(f"{case}: p95 turn {values['p95_ms']:.2f} ms > {P95} ms")
    if values.get("over16", 0) > 0 or values.get("worst_ms", 0) > WORST:
        problems.append(f"{case}: a turn over {WORST:.0f} ms (worst {values.get('worst_ms', 0):.2f} ms, {values.get('over16', 0):.0f} over)")
    for key, limit in INTERVAL_BUDGETS.items():
        if key in values and values[key] > limit:
            problems.append(f"{case}: {key[:-3]} {values[key]:.0f} ms > {limit:.0f} ms")
    return problems


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    rows = parse(argv[1])
    check = "--no-budget" not in argv
    if not rows:
        print("no LAUNCHCOST lines in", argv[1])
        return 1
    width = max(len(case) for case, _ in rows)
    print(f"{'case'.ljust(width)}  " + "  ".join(c.replace("_ms", "").rjust(9) for c in COLUMNS))
    problems = []
    for case, values in rows:
        cells = [(f"{values[c]:.1f}" if c in values else "-").rjust(9) for c in COLUMNS]
        print(f"{case.ljust(width)}  " + "  ".join(cells))
        problems += failures(case, values)
    if check:
        print()
        print("budgets: " + ("all met" if not problems else "MISSED"))
        for problem in problems:
            print("  " + problem)
    return 1 if problems and check else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
