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
    forge_binding = commands.add_parser("forge-read-configure")
    forge_binding.add_argument("--endpoint", required=True)
    forge_binding.add_argument("--instance-id", required=True)
    forge_binding.add_argument("--repository-id", required=True)
    forge_binding.add_argument("--token-file", required=True,
                               help="absolute owner-held file containing the scoped Forge read token")
    forge_binding.add_argument("--expected-current-instance")
    forge_binding.add_argument("--expected-current-repository")
    forge_binding.add_argument("--expected-current-revision", type=int)
    start = commands.add_parser("serve")
    start.add_argument("--port", type=int, default=8765)
    start.add_argument("--bind", default="127.0.0.1", help="explicit IPv4 listener interface")
    start.add_argument("--tls-server-name", help="exact HTTPS Host and certificate name")
    start.add_argument("--tls-cert", help="absolute owner-held TLS certificate path")
    start.add_argument("--tls-key", help="absolute private TLS key path (mode 0600)")
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
        elif args.command == "forge-read-configure":
            with Service(args.root) as service:
                result = service.configure_forge_read(
                    args.endpoint, args.instance_id, args.repository_id, args.token_file,
                    expected_instance_id=args.expected_current_instance,
                    expected_repository_id=args.expected_current_repository,
                    expected_revision=args.expected_current_revision)
            print(json.dumps(result, sort_keys=True))
        else:
            if not 1 <= args.port <= 65535:
                raise ValueError("port out of range")
            if (args.bind, args.tls_server_name, args.tls_cert, args.tls_key) == (
                    "127.0.0.1", None, None, None):
                serve(args.root, args.port)
            else:
                serve(args.root, args.port, bind=args.bind, server_name=args.tls_server_name,
                      cert_file=args.tls_cert, key_file=args.tls_key)
    except (OSError, ValueError, UnicodeError) as exc:
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
