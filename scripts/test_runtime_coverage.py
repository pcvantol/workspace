"""Ensure runtime coverage evidence cannot hide a failing test run."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from validate_runtime_coverage import TEST_RUNNER


class RuntimeCoverageRunnerTests(unittest.TestCase):
    def run_fixture(self, assertion):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "tests"
            tests.mkdir()
            (tests / "test_fixture.py").write_text(
                "import unittest\n"
                "from threading import Thread\n"
                "def worker():\n"
                "    executed_only_in_worker = True\n"
                "class Fixture(unittest.TestCase):\n"
                "    def test_result(self):\n"
                f"        {assertion}\n", encoding="utf-8")
            coverage = root / "coverage"
            run = subprocess.run(
                [sys.executable, "-c", TEST_RUNNER, str(coverage), str(tests)],
                capture_output=True, text=True)
            self.assertTrue((coverage / "test_fixture.cover").is_file())
            return run, (coverage / "test_fixture.cover").read_text()

    def test_failed_tests_return_failure_with_coverage_evidence(self):
        run, _ = self.run_fixture("self.fail('deliberate failure')")
        self.assertEqual(run.returncode, 1)
        self.assertIn("FAILED (failures=1)", run.stderr)

    def test_successful_tests_return_success_with_coverage_evidence(self):
        run, _ = self.run_fixture("self.assertEqual(2 + 2, 4)")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("OK", run.stderr)

    def test_server_worker_threads_are_included_in_coverage(self):
        run, evidence = self.run_fixture(
            "thread = Thread(target=worker); thread.start(); thread.join()")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertRegex(evidence, r"\d+:     executed_only_in_worker = True")


if __name__ == "__main__":
    unittest.main()
