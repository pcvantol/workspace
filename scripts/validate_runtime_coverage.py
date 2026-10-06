"""Offline, strict per-file executable-line gate using Python's trace module."""

from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PRODUCT = ROOT / "workspace_control"
HIT = re.compile(r"^\s*\d+: ")
TEST_RUNNER = """
import os
import sys
import trace
import unittest

sys.path[0] = os.getcwd()

def run_tests():
    suite = unittest.defaultTestLoader.discover(sys.argv[2], pattern="test_*.py")
    return unittest.TextTestRunner().run(suite)

tracer = trace.Trace(count=True, trace=False)
tracer.runctx("result = run_tests()", globals(), globals())
tracer.results().write_results(show_missing=True, summary=True, coverdir=sys.argv[1])
sys.exit(0 if result.wasSuccessful() else 1)
"""


def summarize(cover_dir, sources, product_root=PRODUCT):
    """Return per-file hit/total counts, failing closed on missing or low evidence."""
    results = {}
    for source in sources:
        relative = source.relative_to(product_root)
        dotted = ".".join(("workspace_control", *relative.with_suffix("").parts))
        cover = cover_dir / f"{dotted}.cover"
        if not cover.is_file():
            raise ValueError(f"missing executable-line evidence: {source.name}")
        lines = cover.read_text(encoding="utf-8").splitlines()
        hits = sum(bool(HIT.match(line)) for line in lines)
        misses = sum(line.startswith(">>>>>> ") for line in lines)
        total = hits + misses
        if total == 0 or hits * 1000 <= total * 802:
            raise ValueError(f"coverage does not strictly exceed 80.2%: {source.name} ({hits}/{total})")
        results[relative.as_posix()] = (hits, total)
    return results


def main():
    sources = sorted(PRODUCT.rglob("*.py"))
    if not sources:
        raise ValueError("no Workspace product modules found")
    with tempfile.TemporaryDirectory(prefix="workspace-coverage-") as directory:
        cover_dir = Path(directory)
        command = [sys.executable, "-c", TEST_RUNNER, str(cover_dir), "tests"]
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if run.returncode:
            print(run.stdout[-4000:], file=sys.stderr)
            print(run.stderr[-4000:], file=sys.stderr)
            raise SystemExit(run.returncode)
        results = summarize(cover_dir, sources)
        for name, (hits, total) in results.items():
            print(f"{name}: {hits}/{total} executable lines ({hits / total * 100:.2f}%)")
        print("Workspace runtime tests and strict per-file coverage passed.")


if __name__ == "__main__":
    main()
