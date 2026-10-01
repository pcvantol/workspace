#!/usr/bin/env python3
"""Project the own OpenAPI reads into the checked-in Postman collection."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from workspace_control.http import openapi_contract


TARGET = ROOT / "docs" / "WORKSPACE_SERVER_READONLY_V1.postman.json"


def collection():
    contract = openapi_contract()
    server = contract["servers"][0]
    base_url = server["url"].replace("{port}", server["variables"]["port"]["default"])
    items = []
    for path, methods in contract["paths"].items():
        if set(methods) != {"get"}:
            raise ValueError(f"unsupported Postman methods for {path}")
        operation = methods["get"]
        request = {"method": "GET", "url": "{{baseUrl}}" + path}
        security = operation.get("security", [])
        parameters = operation.get("parameters", [])
        if security or parameters:
            if security != [{"bearerAuth": []}] or parameters != [
                {"name": "X-Workspace-Instance", "in": "header", "required": True,
                 "schema": {"type": "string"}}
            ]:
                raise ValueError(f"unsupported Postman authentication for {path}")
            request["header"] = [
                {"key": "Authorization", "value": "Bearer {{token}}"},
                {"key": "X-Workspace-Instance", "value": "{{instanceId}}"},
            ]
        items.append({"name": operation["operationId"].split(".", 1)[0], "request": request})
    return {
        "info": {"name": contract["info"]["title"],
                 "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "variable": [{"key": "baseUrl", "value": base_url},
                     {"key": "token", "value": ""},
                     {"key": "instanceId", "value": ""}],
        "item": items,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    expected = json.dumps(collection(), indent=2, ensure_ascii=False) + "\n"
    if args.write:
        TARGET.write_text(expected, encoding="utf-8")
    elif TARGET.read_text(encoding="utf-8") != expected:
        parser.exit(1, "Postman projection is stale; run scripts/project_postman.py --write\n")


if __name__ == "__main__":
    main()
