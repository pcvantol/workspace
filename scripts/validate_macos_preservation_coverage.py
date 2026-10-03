"""Require strict executable-line coverage for the candidate handoff source."""

from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts/preserve_macos_app_candidate.py"
HIT = re.compile(r"^\s*\d+: ")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="workspace-preservation-coverage-") as directory:
        cover_dir = Path(directory)
        run = subprocess.run(
            [sys.executable, "-m", "trace", "--count", "--missing", "--coverdir",
             str(cover_dir), "--module", "unittest", "discover", "-s", "scripts",
             "-p", "test_macos_app_preservation.py"],
            cwd=ROOT, capture_output=True, text=True,
        )
        if run.returncode:
            print(run.stdout[-4000:], file=sys.stderr)
            print(run.stderr[-4000:], file=sys.stderr)
            raise SystemExit(run.returncode)
        report = cover_dir / "preserve_macos_app_candidate.cover"
        if not report.is_file():
            raise ValueError(f"missing executable-line evidence: {SOURCE.name}")
        lines = report.read_text(encoding="utf-8").splitlines()
        hits = sum(bool(HIT.match(line)) for line in lines)
        misses = sum(line.startswith(">>>>>> ") for line in lines)
        total = hits + misses
        if total == 0 or hits * 1000 <= total * 802:
            raise ValueError(f"coverage does not strictly exceed 80.2%: {SOURCE.name} ({hits}/{total})")
        print(f"{SOURCE.name}: {hits}/{total} executable lines ({hits / total * 100:.2f}%)")


if __name__ == "__main__":
    main()
