"""Thin local Workspace management and Client entrypoints."""

import argparse
import json
import re
import sys
import webbrowser

from .http import openapi_contract, operation_inventory, serve
from .service import Service, initialize, inspect


def main(argv=None):
    parser = argparse.ArgumentParser(prog="workspace-server")
    parser.add_argument("--root", required=True, help="existing private absolute data root")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init")
    commands.add_parser("inspect")
    commands.add_parser("status")
    commands.add_parser("projects")
    commands.add_parser("capabilities")
    commands.add_parser("openapi")
    start = commands.add_parser("serve")
    start.add_argument("--port", type=int, default=8765)
    args = parser.parse_args(argv)
    try:
        if args.command == "init":
            print(json.dumps({"instance_id": initialize(args.root)}))
        elif args.command == "inspect":
            print(json.dumps(inspect(args.root), sort_keys=True))
        elif args.command in ("status", "projects", "capabilities", "openapi"):
            with Service(args.root) as service:
                if args.command == "status":
                    result = service.status()
                elif args.command == "projects":
                    result = service.projects()
                elif args.command == "capabilities":
                    result = operation_inventory(service.instance_id)
                else:
                    result = openapi_contract()
            print(json.dumps(result, sort_keys=True))
        else:
            if not 1 <= args.port <= 65535:
                raise ValueError("port out of range")
            serve(args.root, args.port)
    except (OSError, ValueError) as exc:
        print(f"workspace-server: {exc}", file=sys.stderr)
        return 2
    return 0


def client_main(argv=None):
    parser = argparse.ArgumentParser(prog="workspace-client")
    parser.add_argument("--url", required=True)
    args = parser.parse_args(argv)
    url = re.fullmatch(r"http://(?:127\.0\.0\.1|localhost):([1-9][0-9]{0,4})/?", args.url)
    if url is None or int(url.group(1)) > 65535:
        parser.error("this first Client supports only a loopback Workspace Server")
    try:
        opened = webbrowser.open(args.url.rstrip("/") + "/")
    except (OSError, webbrowser.Error) as exc:
        print(f"workspace-client: browser launch failed: {exc}", file=sys.stderr)
        return 2
    if not opened:
        print("workspace-client: browser launch failed", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
