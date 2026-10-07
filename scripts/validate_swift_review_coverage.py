"""Require executable-line coverage strictly above 80.2% for native source."""

import json
from pathlib import Path
import sys


SOURCES = {
    "MissionReviewDecisionState.swift", "MissionReviewDiscovery.swift",
    "MissionReviewState.swift", "MissionReviewTransport.swift",
    "MissionReviewsView.swift", "WorkspaceApp.swift",
    "ApprovedWorklistPresentation.swift", "WorklistGraphLayout.swift", "WorklistDependencyGraph.swift",
    "ApprovedWorklistView.swift", "ConversationsView.swift",
    "WorklistTransport.swift", "WorklistProjection.swift",
    "WorklistState.swift", "LiveApprovedWorklistView.swift",
}


def main(path, sources=SOURCES):
    report = json.loads(Path(path).read_text(encoding="utf-8"))
    files = {}
    for unit in report["data"]:
        for entry in unit["files"]:
            source = Path(entry["filename"])
            if source.name in sources and source.parent.name == "WorkspaceClient":
                if source.name in files:
                    raise ValueError(f"duplicate Swift coverage: {source.name}")
                files[source.name] = entry["summary"]["lines"]
    if set(files) != sources:
        raise ValueError(f"missing Swift review coverage: {sorted(sources - set(files))}")
    for name, result in sorted(files.items()):
        covered, total = result["covered"], result["count"]
        if not isinstance(covered, int) or not isinstance(total, int) or total < 1 or covered * 1000 <= total * 802:
            raise ValueError(f"Swift coverage does not strictly exceed 80.2%: {name} ({covered}/{total})")
        print(f"{name}: {covered}/{total} executable lines ({covered / total * 100:.2f}%)")


if __name__ == "__main__":
    if sys.argv[2:] not in ([], ["--isolated"]):
        raise ValueError("unknown Swift coverage gate option")
    main(sys.argv[1], {"IsolatedTestCredentials.swift"} if sys.argv[2:] else SOURCES)
