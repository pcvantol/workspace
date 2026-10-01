"""Workspace-owned, read-only Server foundation."""

import json
from importlib.metadata import version
from pathlib import Path

try:
    __version__ = json.loads((Path(__file__).resolve().parent.parent / "product-version.json").read_text())["version"]
except FileNotFoundError:
    __version__ = version("pcvantol-workspace-control")
