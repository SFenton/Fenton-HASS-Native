"""Coverage classification and measurement (``tools/coverage_gate.py``).

Each test builds a small source tree and LLVM export in a temporary directory, so nothing here runs a
build or reads the real ``.build``.
"""

import contextlib
import io
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools import coverage_gate

RULES = {
    "thresholds": {"logic": 95, "ux": 95},
    "swift": {
        "sourceRoots": ["apple/Sources/**/*.swift"],
        "logic": ["apple/Sources/Core/**/*.swift"],
        "ux": ["apple/Sources/UI/**/*.swift"],
        "exclude": [],
    },
}


class CoverageGateTests(unittest.TestCase):
    """The gate names unclassified files and measures declaration-only files as zero lines."""

    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write_sources(self, *names: str) -> None:
        for name in names:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// source\n", encoding="utf-8")

    def report(self, lines: dict[str, tuple[int, int]]) -> Path:
        files = [
            {"filename": str(self.root / name), "summary": {"lines": {"covered": covered, "count": count}}}
            for name, (covered, count) in lines.items()
        ]
        path = self.root / "report.json"
        path.write_text(json.dumps({"data": [{"files": files}]}), encoding="utf-8")
        return path

    def run_gate(self, *args: str) -> tuple[int, str, str]:
        rules = self.root / "rules.json"
        rules.write_text(json.dumps(RULES), encoding="utf-8")
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = coverage_gate.main(
                ["--language", "swift", "--root", str(self.root), "--rules", str(rules), *args]
            )
        return status, out.getvalue(), err.getvalue()

    def test_classify_only_names_each_unclassified_file_and_module(self) -> None:
        self.write_sources(
            "apple/Sources/Core/A.swift",
            "apple/Sources/UI/B.swift",
            "apple/Sources/Telemetry/Log.swift",
            "apple/Sources/Telemetry/Sub/Record.swift",
        )
        status, _, err = self.run_gate("--classify-only")
        self.assertEqual(status, 1)
        self.assertIn("2 production source file(s) are not classified", err)
        self.assertIn("apple/Sources/Telemetry", err)
        self.assertIn("\n  apple/Sources/Telemetry/Log.swift", err)
        self.assertIn("\n  apple/Sources/Telemetry/Sub/Record.swift", err)

    def test_classify_only_needs_no_report_and_passes_when_complete(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        status, out, err = self.run_gate("--classify-only")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("swift.logic: 1 source files classified", out)

    def test_report_is_required_without_classify_only(self) -> None:
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.run_gate()

    def test_declaration_only_file_counts_as_zero_lines_and_is_listed(self) -> None:
        self.write_sources(
            "apple/Sources/Core/A.swift",
            "apple/Sources/Core/Protocol.swift",
            "apple/Sources/UI/B.swift",
        )
        report = self.report({"apple/Sources/Core/A.swift": (96, 100), "apple/Sources/UI/B.swift": (19, 20)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual((status, err), (0, ""))
        self.assertIn("1 file(s) have no LLVM record", out)
        self.assertIn("\n  apple/Sources/Core/Protocol.swift", out)
        self.assertIn("swift.logic: 96/100 lines = 96.00% across 2 files", out)

    def test_module_with_no_records_is_an_error(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (96, 100)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual(status, 1)
        self.assertIn("no coverage records for module(s) apple/Sources/UI", err)
        self.assertIn("swift.logic: 96/100", out)

    def test_low_coverage_fails_with_the_number(self) -> None:
        self.write_sources("apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift")
        report = self.report({"apple/Sources/Core/A.swift": (90, 100), "apple/Sources/UI/B.swift": (9, 10)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual(status, 1)
        self.assertIn("swift.logic: 90.00% is below 95%", err)
        self.assertIn("swift.ux: 9/10 lines = 90.00%", out)

    def test_unclassified_file_fails_but_still_reports_numbers(self) -> None:
        self.write_sources(
            "apple/Sources/Core/A.swift", "apple/Sources/UI/B.swift", "apple/Sources/Extra/C.swift"
        )
        report = self.report({"apple/Sources/Core/A.swift": (96, 100), "apple/Sources/UI/B.swift": (9, 10)})
        status, out, err = self.run_gate("--report", str(report))
        self.assertEqual(status, 1)
        self.assertIn("\n  apple/Sources/Extra/C.swift", err)
        self.assertIn("swift.logic: 96/100", out)

    def test_module_of_uses_the_directory_under_sources(self) -> None:
        self.assertEqual(
            coverage_gate.module_of("apple/Sources/HassUI/Features/Feedback/Sheet.swift"),
            "apple/Sources/HassUI",
        )
        self.assertEqual(coverage_gate.module_of("tools/x.swift"), "tools")


if __name__ == "__main__":
    unittest.main()
