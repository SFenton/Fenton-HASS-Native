"""Log digests (``tools/test_digest.py``) and the background runner (``tools/bg_run.py``).

The samples are trimmed copies of real xcodebuild, Swift Testing and devcap output.
"""

import io
import subprocess
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bg_run  # noqa: E402
import test_digest  # noqa: E402

XCTEST_FAIL = """\
Test Case '-[FentonHomeUITests.HomeJourneyTests testLightsSheetToggles]' started.
Test Case '-[FentonHomeUITests.HomeJourneyTests testLightsSheetToggles]' passed (22.108 seconds).
Test Case '-[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit]' started.
/Users/me/repos/Fenton/apple/Apps/iOSUITests/BedroomJourneyTests.swift:262: error: -[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit] : failed - Accessibility audit:
Contrast failed: 48 'Snooze' (rendered 2.4:1)
Test Case '-[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit]' failed (82.815 seconds).
\t Executed 2 tests, with 1 failure (0 unexpected) in 104.9 (105.0) seconds
** TEST FAILED **
"""

SWIFT_TESTING_FAIL = """\
✔ Test failedCallRevertsThePower() passed after 0.153 seconds.
✘ Test readsAlarmAndPhaseStates() recorded an issue at BedroomContractTests.swift:352:9: Expectation failed: metric == "91.3°F"
✘ Test readsAlarmAndPhaseStates() failed after 0.057 seconds with 1 issue.
✘ Test run with 154 tests in 28 suites failed after 0.482 seconds with 1 issue.
"""

SWIFT_TESTING_PASS = "✔ Test run with 154 tests in 28 suites passed after 3.1 seconds.\n"

BUILD_ERROR = """\
Building for debugging...
/Users/me/Fenton/apple/Sources/HassCore/Bedroom/WakeLightController.swift:250:15: \x1b[1;31merror: \x1b[1;39mpattern the checker does not understand\x1b[0;0m
/Users/me/Fenton/apple/Sources/HassCore/Bedroom/WakeLightController.swift:250:15: error: pattern the checker does not understand
** BUILD FAILED **
"""


class DigestTests(unittest.TestCase):
    def test_xctest_failure_names_the_test_and_first_message(self):
        out = test_digest.digest_text(XCTEST_FAIL, exit_code=65, elapsed=125)
        self.assertIn("RESULT: FAIL (exit 65)", out)
        self.assertIn("2m05s", out)
        self.assertIn("BedroomJourneyTests.testBedTemperaturePassesAudit: failed - Accessibility audit:", out)
        self.assertIn("(BedroomJourneyTests.swift:262)", out)
        self.assertIn("named: 1 passed, 1 failed", out)
        self.assertNotIn("HomeJourneyTests.testLightsSheetToggles:", out)

    def test_swift_testing_failure(self):
        out = test_digest.digest_text(SWIFT_TESTING_FAIL, exit_code=1)
        self.assertIn("RESULT: FAIL", out)
        self.assertIn("readsAlarmAndPhaseStates:", out)
        self.assertIn("swift-testing: 154 tests failed", out)

    def test_clean_pass(self):
        out = test_digest.digest_text(SWIFT_TESTING_PASS, exit_code=0)
        self.assertIn("RESULT: PASS (exit 0)", out)
        self.assertNotIn("FAILED", out)

    def test_retried_test_that_passes_is_not_a_failure(self):
        log = XCTEST_FAIL.replace("failed (82.815", "failed (82.815").replace("** TEST FAILED **", "** TEST SUCCEEDED **")
        log += ("Test Case '-[FentonHomeUITests.BedroomJourneyTests testBedTemperaturePassesAudit]' passed (40.0 seconds).\n")
        out = test_digest.digest_text(log.replace(": error: -[", ": note: -["), exit_code=0)
        self.assertIn("RESULT: PASS", out)

    def test_build_errors_are_listed_once_without_colour_codes(self):
        out = test_digest.digest_text(BUILD_ERROR, exit_code=65)
        self.assertIn("BUILD ERRORS (1):", out)
        self.assertIn("WakeLightController.swift:250: pattern the checker does not understand", out)
        self.assertNotIn("\x1b", out)

    def test_device_hub_failure_is_infra_not_a_test_failure(self):
        log = "ios_sim.DeviceHubError: Pressed the unfolded control but the Duo reads folded\n"
        out = test_digest.digest_text(log, exit_code=1)
        self.assertIn("RESULT: INFRA", out)
        self.assertIn("INFRA (not a test failure): Device Hub pose", out)

    def test_gap_and_hold_timeout_are_infra(self):
        self.assertIn("RESULT: INFRA", test_digest.digest_text("GAP: no available simulator named 'iPhone Duo'\n", exit_code=1))
        self.assertIn("hold timeout", test_digest.digest_text("devcap: hold timeout after 3600s\n", exit_code=124))

    def test_unknown_failure_shows_the_last_lines(self):
        out = test_digest.digest_text("one\ntwo\nthree\n", exit_code=2)
        self.assertIn("RESULT: FAIL (exit 2)", out)
        self.assertIn("last lines:", out)
        self.assertIn("  three", out)

    def test_no_exit_code_reads_the_log(self):
        self.assertIn("RESULT: PASS", test_digest.digest_text("** TEST SUCCEEDED **\n"))
        self.assertIn("RESULT: UNKNOWN", test_digest.digest_text("hello\n"))

    def test_many_failures_are_capped(self):
        log = "".join(f"Test Case '-[A.B test{i}]' failed (1.0 seconds).\n" for i in range(80))
        out = test_digest.digest_text(log, exit_code=1, max_lines=30)
        self.assertLessEqual(len(out.splitlines()), 32)
        self.assertIn("and ", out)

    def test_duration_formats(self):
        self.assertEqual(test_digest.describe(45), "45s")
        self.assertEqual(test_digest.describe(3725), "1h02m")

    def test_cli_reads_a_file_and_stdin(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "run.log"
            path.write_text(SWIFT_TESTING_PASS)
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                self.assertEqual(test_digest.main([str(path), "--exit-code", "0", "--label", "x"]), 0)
            self.assertIn("RESULT: PASS (exit 0)  x", buffer.getvalue())
            self.assertIn(str(path), buffer.getvalue())
            stdin, sys.stdin = sys.stdin, io.StringIO(SWIFT_TESTING_FAIL)
            try:
                buffer = io.StringIO()
                with redirect_stdout(buffer):
                    test_digest.main(["-"])
            finally:
                sys.stdin = stdin
            self.assertIn("RESULT: FAIL", buffer.getvalue())


class BackgroundRunTests(unittest.TestCase):
    def test_prints_only_the_digest_and_keeps_the_log(self):
        with TemporaryDirectory() as tmp:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                status = bg_run.main(["unit", "--dir", tmp, "--", sys.executable, "-c",
                                      "print('noise ' * 1000); print('** TEST SUCCEEDED **')"])
            self.assertEqual(status, 0)
            self.assertIn("RESULT: PASS (exit 0)  unit", buffer.getvalue())
            self.assertNotIn("noise noise", buffer.getvalue())
            self.assertIn("noise noise", (Path(tmp) / "unit.log").read_text())
            self.assertEqual((Path(tmp) / "unit.digest").read_text().strip(), buffer.getvalue().strip())

    def test_failure_status_passes_through(self):
        with TemporaryDirectory() as tmp:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                status = bg_run.main(["bad", "--dir", tmp, "--", sys.executable, "-c",
                                      "import sys; print('Test Case \\'-[A.B testX]\\' failed (1.0 seconds).'); sys.exit(3)"])
            self.assertEqual(status, 3)
            self.assertIn("B.testX: failed", buffer.getvalue())
            self.assertIn("RESULT: FAIL (exit 3)", buffer.getvalue())

    def test_timeout_kills_the_process_group(self):
        with TemporaryDirectory() as tmp:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                status = bg_run.main(["hang", "--dir", tmp, "--timeout", "1", "--", "sh", "-c", "sleep 30 & sleep 30"])
            self.assertEqual(status, 124)
            self.assertIn("hold timeout", buffer.getvalue())

    def test_usage_errors(self):
        self.assertEqual(bg_run.main(["only-a-label"]), 2)
        self.assertEqual(bg_run.main(["label", "--"]), 2)

    def test_cli_script_runs(self):
        with TemporaryDirectory() as tmp:
            done = subprocess.run([sys.executable, str(Path(bg_run.__file__)), "cli", "--dir", tmp, "--", "true"],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 0)
            self.assertIn("RESULT: PASS", done.stdout)


if __name__ == "__main__":
    unittest.main()
