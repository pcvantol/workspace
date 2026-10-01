"""Project metadata reads the canonical Workspace product-version source."""

import json
from pathlib import Path
from setuptools import setup

setup(version=json.loads((Path(__file__).parent / "product-version.json").read_text())["version"])
