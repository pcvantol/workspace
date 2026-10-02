"""Thin local Workspace management and Client entrypoints."""

import argparse
import json
import sys
from urllib.parse import urlsplit
import webbrowser

from .http import openapi_contract, operation_inventory, serve
from .service import Service, initialize


def main(argv=None):
    parser = argparse.ArgumentParser(prog="workspace-server")
    parser.add_argument("--root", required=True, help="existing private absolute data root")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init")
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
        elif args.command == "status":
            print(json.dumps(Service(args.root).status(), sort_keys=True))
        elif args.command == "projects":
            print(json.dumps(Service(args.root).projects(), sort_keys=True))
        elif args.command == "capabilities":
            print(json.dumps(operation_inventory(Service(args.root).instance_id), sort_keys=True))
        elif args.command == "openapi":
            Service(args.root)
            print(json.dumps(openapi_contract(), sort_keys=True))
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
    parsed = urlsplit(args.url)
    try:
        valid_port = parsed.port is not None and 1 <= parsed.port <= 65535
    except ValueError:
        valid_port = False
    if (parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost") or
            not valid_port or parsed.username or parsed.password or parsed.path not in ("", "/") or
            "?" in args.url or "#" in args.url):
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
