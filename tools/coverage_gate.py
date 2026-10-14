#!/usr/bin/env python3
"""Fail when actual logic/UX line coverage misses its threshold. Ported from FestivalNativeApps."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "contracts" / "coverage-rules.json"


def source_files(root: Path, patterns: list[str]) -> set[str]:
    """Find source files subject to coverage, independently of report contents.

    Args:
        root: Repository root.
        patterns: Repository-relative glob patterns for one coverage category.

    Returns:
        All matched repository-relative POSIX file paths.
    """
    return {
        path.relative_to(root).as_posix()
        for pattern in patterns
        for path in root.glob(pattern)
        if path.is_file()
    }


def llvm_file_totals(reports: list[Path], root: Path) -> dict[str, tuple[int, int]]:
    """Extract exact executable and covered line totals from LLVM JSON exports.

    Args:
        reports: One `llvm-cov export --format=text` result per test binary.
        root: Root against which tracked source paths are resolved.

    Returns:
        Mapping from repository-relative path to (covered, executable) lines.

    Raises:
        ValueError: On malformed, missing or duplicated per-file coverage.
    """
    totals: dict[str, tuple[int, int]] = {}
    for report in reports:
        try:
            payload = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"{report}: cannot read LLVM coverage JSON: {error}") from error
        if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
            raise ValueError(f"{report}: missing LLVM data array")
        for group in payload["data"]:
            if not isinstance(group, dict) or not isinstance(group.get("files"), list):
                raise ValueError(f"{report}: missing LLVM files array")
            for item in group["files"]:
                if not isinstance(item, dict) or not isinstance(item.get("filename"), str):
                    raise ValueError(f"{report}: invalid file entry")
                try:
                    name = Path(item["filename"]).resolve().relative_to(root.resolve()).as_posix()
                except ValueError:
                    continue  # Generated compiler or SDK sources are not product code.
                lines: Any = item.get("summary", {}).get("lines")
                if (
                    not isinstance(lines, dict)
                    or type(lines.get("covered")) is not int
                    or type(lines.get("count")) is not int
                    or not 0 <= lines["covered"] <= lines["count"]
                ):
                    raise ValueError(f"{report}: invalid line totals for {name}")
                if name in totals:
                    raise ValueError(f"{name}: duplicated in coverage exports; merge profiles first")
                totals[name] = (lines["covered"], lines["count"])
    return totals


def check_coverage(
    totals: dict[str, tuple[int, int]], root: Path, rules: dict[str, Any], language: str
) -> list[str]:
    """Check source-file completeness and separate threshold ratios.

    Args:
        totals: Actual per-file (covered, executable) line counts.
        root: Repository root.
        rules: Versioned coverage classification and numeric thresholds.
        language: Language section to validate.

    Returns:
        Errors for missing files, category overlap and low measured coverage.
    """
    if language not in rules or not isinstance(rules[language], dict):
        return [f"{language}: no configured coverage categories"]
    errors: list[str] = []
    exclude_patterns = rules[language].get("exclude", [])
    if not isinstance(exclude_patterns, list) or not all(
        isinstance(pattern, str) for pattern in exclude_patterns
    ):
        return [f"{language}: invalid coverage exclusion patterns"]
    excluded = source_files(root, exclude_patterns)
    for name in excluded:
        if name in totals and totals[name][1] > 0:
            errors.append(f"{language}: executable source cannot be excluded: {name}")
    classified: set[str] = set()
    for category in ("logic", "ux"):
        patterns = rules[language].get(category)
        threshold = rules.get("thresholds", {}).get(category)
        if (
            not isinstance(patterns, list)
            or not patterns
            or not all(isinstance(pattern, str) for pattern in patterns)
            or type(threshold) is not int
            or not 0 <= threshold <= 100
        ):
            errors.append(f"{language}.{category}: invalid patterns or threshold")
            continue
        files = source_files(root, patterns) - excluded
        if not files:
            errors.append(f"{language}.{category}: no matching source files")
            continue
        overlap = classified & files
        if overlap:
            errors.append(f"{language}.{category}: source classified twice: {sorted(overlap)}")
        classified.update(files)
        missing = files - totals.keys()
        if missing:
            errors.append(f"{language}.{category}: missing coverage for {sorted(missing)}")
            continue
        covered = sum(totals[name][0] for name in files)
        executable = sum(totals[name][1] for name in files)
        if executable == 0:
            errors.append(f"{language}.{category}: report has zero executable lines")
            continue
        percent = covered * 100 / executable
        print(f"{language}.{category}: {covered}/{executable} lines = {percent:.2f}% (need {threshold}%)")
        if covered * 100 < threshold * executable:
            errors.append(f"{language}.{category}: {percent:.2f}% is below {threshold}%")
    source_roots = rules[language].get("sourceRoots")
    if source_roots is not None:
        if (
            not isinstance(source_roots, list)
            or not source_roots
            or not all(isinstance(pattern, str) for pattern in source_roots)
        ):
            errors.append(f"{language}: invalid sourceRoots patterns")
        else:
            production = source_files(root, source_roots)
            if not production:
                errors.append(f"{language}: sourceRoots matched no production files")
            unclassified = production - classified - excluded
            if unclassified:
                errors.append(
                    f"{language}: unclassified production source: {sorted(unclassified)}"
                )
            outside_roots = classified - production
            if outside_roots:
                errors.append(
                    f"{language}: classified source outside sourceRoots: {sorted(outside_roots)}"
                )
    return errors


def main(argv: list[str] | None = None) -> int:
    """Parse LLVM reports and enforce the configured category coverage bars.

    Args:
        argv: Optional command-line arguments.

    Returns:
        Exit status zero only when all measured gates pass.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--language", required=True, choices=("swift",))
    parser.add_argument("--report", type=Path, action="append", required=True)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--rules", type=Path, default=RULES)
    args = parser.parse_args(argv)
    try:
        rules = json.loads(args.rules.read_text(encoding="utf-8"))
        totals = llvm_file_totals(args.report, args.root)
        errors = check_coverage(totals, args.root, rules, args.language)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"Coverage gate error: {error}", file=sys.stderr)
        return 2
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
