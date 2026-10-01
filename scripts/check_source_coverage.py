"""Require strict per-module coverage for the selected product source."""

import json
from pathlib import Path
import sys


def main(path):
    report = json.loads(Path(path).read_text())
    source_files = {name: data for name, data in report["files"].items()
                    if name.startswith("workspace_control/") and name.endswith(".py")}
    if set(source_files) != {"workspace_control/__init__.py", "workspace_control/service.py",
                             "workspace_control/http.py", "workspace_control/cli.py"}:
        raise SystemExit("incomplete Workspace product coverage report")
    for name, data in sorted(source_files.items()):
        summary = data["summary"]
        covered = summary["covered_lines"]
        count = summary["num_statements"]
        percent = covered * 100 / count
        print(f"{name}: {covered}/{count} = {percent:.2f}%")
        if percent <= 80.2:
            raise SystemExit(f"coverage below strict >80.2% gate: {name}")


if __name__ == "__main__":
    main(sys.argv[1])
