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
    conversation_grant = commands.add_parser("conversation-grant-issue")
    conversation_grant.add_argument("--actor", required=True)
    conversation_grant.add_argument("--project", required=True)
    conversation_revoke = commands.add_parser("conversation-grant-revoke")
    conversation_revoke.add_argument("--actor", required=True)
    conversation_revoke.add_argument("--project", required=True)
    review_issue = commands.add_parser("review-bind-issue")
    review_issue.add_argument("--actor", required=True)
    review_issue.add_argument("--forge-endpoint", required=True)
    review_issue.add_argument("--forge-instance-id", required=True)
    review_issue.add_argument("--forge-token-file", required=True)
    review_issue.add_argument("--client-token-file", required=True)
    review_revoke = commands.add_parser("review-bind-revoke")
    review_revoke.add_argument("--binding-id", required=True)
    worklist_issue = commands.add_parser("worklist-bind-issue")
    worklist_issue.add_argument("--actor", required=True)
    worklist_issue.add_argument("--forge-endpoint", required=True)
    worklist_issue.add_argument("--forge-instance-id", required=True)
    worklist_issue.add_argument("--forge-token-file", required=True)
    worklist_issue.add_argument("--client-token-file", required=True)
    worklist_revoke = commands.add_parser("worklist-bind-revoke")
    worklist_revoke.add_argument("--binding-id", required=True)
    control_issue = commands.add_parser("worklist-control-bind-issue")
    control_issue.add_argument("--actor", required=True)
    control_issue.add_argument("--forge-endpoint", required=True)
    control_issue.add_argument("--forge-instance-id", required=True)
    control_issue.add_argument("--workset-id", action="append", required=True)
    control_issue.add_argument("--forge-token-file", required=True)
    control_issue.add_argument("--client-token-file", required=True)
    control_revoke = commands.add_parser("worklist-control-bind-revoke")
    control_revoke.add_argument("--binding-id", required=True)
    advisory_issue = commands.add_parser("advisory-bind-issue")
    for flag in ["actor", "project", "forge-endpoint", "forge-grant-receipt-file", "forge-token-file", "client-token-file"]:
        advisory_issue.add_argument("--" + flag, required=True)
    advisory_revoke = commands.add_parser("advisory-bind-revoke")
    advisory_revoke.add_argument("--binding-id", required=True)
    candidate_issue = commands.add_parser("candidate-bind-issue")
    for flag in ["actor", "project", "forge-endpoint", "forge-grant-receipt-file", "forge-token-file", "client-token-file"]:
        candidate_issue.add_argument("--" + flag, required=True)
    candidate_revoke = commands.add_parser("candidate-bind-revoke")
    candidate_revoke.add_argument("--binding-id", required=True)
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
        elif args.command == "conversation-grant-issue":
            with Service(args.root) as service:
                token = service.issue_conversation_grant(args.actor, args.project)
            print(json.dumps({"actor_id": args.actor, "project_id": args.project,
                              "draft_grant_token": token}, sort_keys=True))
        elif args.command == "conversation-grant-revoke":
            with Service(args.root) as service:
                revoked = service.revoke_conversation_grants(args.actor, args.project)
            print(json.dumps({"actor_id": args.actor, "project_id": args.project,
                              "revoked": revoked}, sort_keys=True))
        elif args.command == "worklist-bind-issue":
            with Service(args.root) as service:
                result = service.provision_worklist(args.actor, args.forge_endpoint,
                                                    args.forge_instance_id,
                                                    args.forge_token_file, args.client_token_file)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "worklist-bind-revoke":
            with Service(args.root) as service:
                result = service.revoke_worklist(args.binding_id)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "worklist-control-bind-issue":
            with Service(args.root) as service:
                result = service.provision_worklist_control(args.actor, args.forge_endpoint,
                    args.forge_instance_id, args.workset_id, args.forge_token_file, args.client_token_file)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "worklist-control-bind-revoke":
            with Service(args.root) as service:
                result = service.revoke_worklist_control(args.binding_id)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "candidate-bind-issue":
            with Service(args.root) as service:
                result = service.provision_candidate(args.actor, args.project, args.forge_endpoint,
                    args.forge_grant_receipt_file, args.forge_token_file, args.client_token_file)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "candidate-bind-revoke":
            with Service(args.root) as service:
                result = service.revoke_candidate(args.binding_id)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "advisory-bind-issue":
            with Service(args.root) as service:
                result = service.provision_advisory(args.actor, args.project, args.forge_endpoint,
                    args.forge_grant_receipt_file, args.forge_token_file, args.client_token_file)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "advisory-bind-revoke":
            with Service(args.root) as service:
                result = service.revoke_advisory(args.binding_id)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "review-bind-issue":
            with Service(args.root) as service:
                result = service.provision_review(args.actor, args.forge_endpoint,
                                                  args.forge_instance_id,
                                                  args.forge_token_file,
                                                  args.client_token_file)
            print(json.dumps(result, sort_keys=True))
        elif args.command == "review-bind-revoke":
            with Service(args.root) as service:
                result = service.revoke_review(args.binding_id)
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
