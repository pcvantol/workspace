#!/usr/bin/env python3
"""Exercise installed Forge and Workspace wheels through both real HTTP servers.

Forge source supplies only its exact-source synthetic OS/provider/EP fixtures;
both product packages are imported from the selected noneditable installation.
"""

from argparse import ArgumentParser
from hashlib import sha256
from http.client import HTTPConnection
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from threading import Thread
from unittest.mock import patch
from zipfile import ZipFile

import forge
from forge.runtime.dynamic_mission import InstalledDynamicMissionRuntime
from forge.server_runtime import existing_instance
import workspace_control
from workspace_control.http import ThreadingHTTPServer, handler_for
from workspace_control.review_peer import _request_digest
from workspace_control.service import Service, initialize


WORKSPACE_SOURCE = Path(__file__).resolve().parents[1]


def _http(port, method, path, *, read_token, instance, review_token=None, body=None):
    connection = HTTPConnection("127.0.0.1", port, timeout=8)
    headers = {"Authorization": "Bearer " + read_token,
               "X-Workspace-Instance": instance}
    if review_token is not None:
        headers["X-Workspace-Review-Grant"] = review_token
    if body is not None:
        headers["Content-Type"] = "application/json"
    try:
        connection.request(method, path, body=None if body is None else json.dumps(body),
                           headers=headers)
        response = connection.getresponse()
        return response.status, json.loads(response.read())
    finally:
        connection.close()


def _server(service):
    listener = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(service))
    worker = Thread(target=listener.serve_forever, daemon=True)
    worker.start()
    return listener, worker


def _close(listener, worker):
    listener.shutdown()
    listener.server_close()
    worker.join(timeout=3)


def _installed(package, source):
    target = Path(package.__file__).resolve()
    if (not target.is_relative_to(Path(sys.prefix).resolve()) or
            "site-packages" not in target.parts or target.is_relative_to(source)):
        raise AssertionError(f"{package.__name__} is not installed noneditably")
    return target


def _wheel_check(wheel_path, source, product):
    wheel_bytes = wheel_path.read_bytes()
    with ZipFile(wheel_path) as wheel:
        members = [name for name in wheel.namelist() if name.startswith(product + "/")
                   and not name.endswith("/")]
        if not members:
            raise AssertionError("wheel product package is absent")
        for name in members:
            if (source / name).read_bytes() != wheel.read(name):
                raise AssertionError("wheel differs from selected source: " + name)
            installed = Path(sys.prefix) / "lib" / "python3.14" / "site-packages" / name
            if installed.read_bytes() != wheel.read(name):
                raise AssertionError("installed bytes differ from selected wheel: " + name)
    return sha256(wheel_bytes).hexdigest(), len(members)


def _require(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected}, got {actual}")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--forge-source", type=Path, required=True)
    parser.add_argument("--forge-revision", required=True)
    parser.add_argument("--forge-wheel", type=Path, required=True)
    parser.add_argument("--workspace-wheel", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--hold-for-gui", action="store_true")
    parser.add_argument("--gui-credentials", type=Path)
    parser.add_argument("--outcome", choices=("approve", "reject", "amend", "defer"),
                        default="defer")
    args = parser.parse_args()
    if args.hold_for_gui and args.gui_credentials is None:
        parser.error("--hold-for-gui needs --gui-credentials")
    forge_source = args.forge_source.resolve()
    revision = subprocess.check_output(["git", "-C", str(forge_source), "rev-parse", "HEAD"],
                                       text=True).strip()
    _require(revision, args.forge_revision, "Forge source revision")
    if subprocess.check_output(["git", "-C", str(forge_source), "status", "--porcelain"],
                               text=True).strip():
        raise AssertionError("Forge source checkout is dirty")
    forge_install = _installed(forge, forge_source)
    workspace_install = _installed(workspace_control, WORKSPACE_SOURCE)
    forge_digest, forge_members = _wheel_check(args.forge_wheel, forge_source, "forge")
    workspace_digest, workspace_members = _wheel_check(args.workspace_wheel, WORKSPACE_SOURCE,
                                                       "workspace_control")

    # Import test adapters only after the product modules above are installed and pinned.
    sys.path.append(str(forge_source))
    from tests.test_workspace_review_inbox import WorkspaceReviewInboxTests

    qualifier = WorkspaceReviewInboxTests(
        methodName="test_two_principals_real_http_scope_decision_replay_and_readback")
    qualifier.setUp()
    workspace_root = Path(tempfile.mkdtemp(prefix="workspace-review-pair-"))
    workspace_root.chmod(0o700)
    forge_listener = workspace_listener = None
    forge_worker = workspace_worker = None
    service = None
    count = 0
    gui_operation = None
    try:
        # The installed Solo Runtime permits only one selected nonterminal
        # Mission. Each invocation therefore qualifies one outcome in isolation.
        mission = qualifier._mission("-workspace-" + args.outcome, paused=True)
        foreign = (None if args.outcome == "approve" and not args.hold_for_gui else
                   qualifier._mission("-workspace-foreign"))
        alice_missions = [mission]
        bob_missions = [] if foreign is None else [foreign]
        forge_alice, _ = qualifier._issue("reviewer-alice", tuple(alice_missions))
        forge_bob, bob_grant = ((None, None) if foreign is None else
                                qualifier._issue("reviewer-bob", tuple(bob_missions)))
        forge_listener, forge_worker = qualifier._server()
        forge_endpoint = f"http://127.0.0.1:{forge_listener.server.server_port}"
        forge_instance = existing_instance(qualifier.root).instance_id
        workspace_instance = initialize(workspace_root)
        service = Service(workspace_root)

        with patch.object(InstalledDynamicMissionRuntime, "open",
                          side_effect=qualifier._open_adapted_runtime):
            actor_bindings = [("reviewer-alice", forge_alice, alice_missions)]
            if bob_missions:
                actor_bindings.append(("reviewer-bob", forge_bob, bob_missions))
            for actor, forge_token, missions in actor_bindings:
                token_path = qualifier.root / f"{actor}-review-token"
                _require(token_path.read_text().strip(), forge_token, "Forge private grant")
                result = service.provision_review(actor, forge_endpoint, forge_instance,
                                                  str(token_path),
                                                  str(workspace_root / f"{actor}-workspace-token"))
                _require(set(result["mission_ids"]), set(missions), "Workspace actor scope")
            alice = (workspace_root / "reviewer-alice-workspace-token").read_text().strip()
            bob = ((workspace_root / "reviewer-bob-workspace-token").read_text().strip()
                   if bob_missions else None)
            workspace_listener, workspace_worker = _server(service)
            port = workspace_listener.server_port
            def request(method, path, token=None, body=None, read_token=None):
                return _http(port, method, path,
                             read_token=read_token if read_token is not None else service.token,
                             instance=workspace_instance, review_token=token, body=body)

            if (workspace_root / "review-intents.sqlite3").exists():
                raise AssertionError("review read-side intent store appeared before reads")
            scoped_actors = [(alice, "reviewer-alice", alice_missions)]
            if bob_missions:
                scoped_actors.append((bob, "reviewer-bob", bob_missions))
            for token, actor, missions in scoped_actors:
                status, inbox = request("GET", "/v1/reviews", token)
                _require(status, 200, "authorized inbox")
                _require(inbox["scope"]["principal_id"], actor, "inbox actor")
                _require(set(inbox["scope"]["mission_ids"]), set(missions), "inbox Missions")
                count += 1
            if (workspace_root / "review-intents.sqlite3").exists():
                raise AssertionError("review reads mutated Workspace intent storage")
            if bob_missions:
                for actor_token, other_mission in ((alice, bob_missions[0]),
                                                   (bob, alice_missions[0])):
                    _require(request("GET", f"/v1/reviews/missions/{other_mission}", actor_token)[0],
                             403, "cross-actor Mission")
                    count += 1
            _require(request("GET", "/v1/reviews")[0], 403, "missing review grant")
            _require(request("GET", "/v1/reviews", alice, read_token="bad")[0],
                     401, "missing Server authority")
            count += 2

            if not args.hold_for_gui:
                outcome, token = args.outcome, alice
                route = f"/v1/reviews/missions/{mission}"
                status, detail = request("GET", route, token)
                _require(status, 200, "current requirement")
                requirement = detail["requirement"]
                command = {"contract_version": "forge-workspace-review-decision/v1",
                           "operation_id": f"workspace-pair-{outcome}-001",
                           "requirement_id": requirement["requirement_id"],
                           "subject_digest": requirement["subject_digest"],
                           "mission_state_revision": requirement["mission_state_revision"],
                           "evidence_digest": requirement["evidence_digest"],
                           "policy_revision": requirement["policy_revision"],
                           "decision": outcome, "reason": f"Exact {outcome} evidence reviewed."}
                status, submitted = request("POST", route + "/decisions", token, command)
                _require(status, 201, "Forge canonical decision")
                _require(submitted["operation"]["request_digest"],
                         _request_digest(mission, command), "exact request digest")
                operation_path = route + "/decisions/" + command["operation_id"]
                status, readback = request("GET", operation_path, token)
                _require(status, 200, "same operation readback")
                _require(readback["operation"], submitted["operation"], "same receipt")
                _require(readback["current"]["allowed_outcomes"], [], "current fence")
                status, replay = request("POST", route + "/decisions", token, command)
                _require(status, 200, "same operation replay")
                _require(replay["recorded"], False, "idempotent replay")
                _require(request("POST", route + "/decisions", token,
                                 command | {"reason": "Conflicting reason"})[0],
                         409, "conflicting same-ID payload")
                count += 5

                _close(workspace_listener, workspace_worker)
                service.close()
                service = Service(workspace_root)
                workspace_listener, workspace_worker = _server(service)
                port = workspace_listener.server_port
                operation = (f"/v1/reviews/missions/{mission}/decisions/"
                             f"workspace-pair-{outcome}-001")
                _require(request("GET", operation, alice)[0], 200, "restart readback")
                count += 1
            if bob_missions:
                qualifier.grant.revoke(bob_grant)
                _require(request("GET", "/v1/reviews", bob)[0], 401, "Forge grant revocation")
                _require(request("GET", "/v1/reviews", alice)[0], 200, "independent actor")
                count += 2

            receipt = {
                "forge_source_revision": revision,
                "workspace_source_head": subprocess.check_output(
                    ["git", "-C", str(WORKSPACE_SOURCE), "rev-parse", "HEAD"], text=True).strip(),
                "workspace_source_clean": not bool(subprocess.check_output(
                    ["git", "-C", str(WORKSPACE_SOURCE), "status", "--porcelain"], text=True).strip()),
                "forge_wheel_sha256": forge_digest,
                "workspace_wheel_sha256": workspace_digest,
                "forge_product_files_checked": forge_members,
                "workspace_product_files_checked": workspace_members,
                "installed_forge": str(forge_install),
                "installed_workspace": str(workspace_install),
                "http_assertions": count, "status": "PASS",
                "outcome": args.outcome if not args.hold_for_gui else "GUI_PENDING",
                "gui_mission_id": mission if args.hold_for_gui else None,
                "gui_result": "NOT_RUN",
            }
            args.receipt.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
            print(json.dumps({"status": "PASS", "http_assertions": count,
                              "workspace_source_clean": receipt["workspace_source_clean"],
                              "gui_mission_id": receipt["gui_mission_id"]}), flush=True)

            if args.hold_for_gui:
                credentials = {
                    "endpoint": f"http://127.0.0.1:{port}/", "instance_id": workspace_instance,
                    "read_token": service.token,
                    "project_id": "isolated-review-qualification",
                    "draft_grant": "D" * 43,
                    "local_root": str(workspace_root / "native-local"),
                    "review_grant": alice, "review_actor": "reviewer-alice",
                    "review_forge_instance": forge_instance,
                    "review_mission_ids": alice_missions,
                }
                with args.gui_credentials.open("x", encoding="utf-8") as stream:
                    os.fchmod(stream.fileno(), 0o600)
                    json.dump(credentials, stream)
                    stream.write("\n")
                print("GUI_FIXTURE_READY=" + str(args.gui_credentials), flush=True)
                input("Press Return after the packaged GUI click: ")
                connection = sqlite3.connect(workspace_root / "review-intents.sqlite3")
                try:
                    rows = connection.execute(
                        "SELECT operation_id FROM intents WHERE actor_id=? AND mission_id=?",
                        ("reviewer-alice", mission)).fetchall()
                finally:
                    connection.close()
                if len(rows) == 1:
                    gui_operation = rows[0][0]
                    operation_path = f"/v1/reviews/missions/{mission}/decisions/{gui_operation}"
                    gui_status, gui_readback = request("GET", operation_path, alice)
                    if gui_status == 200 and gui_readback["operation"]["operation_id"] == gui_operation:
                        receipt["gui_result"] = "FORGE_RECEIPT_AND_CURRENT_READBACK"
                        receipt["gui_operation_id"] = gui_operation
                        receipt["gui_decision"] = gui_readback["operation"]["decision"]
                    else:
                        receipt["gui_result"] = f"READBACK_{gui_status}"
                else:
                    receipt["gui_result"] = "NO_SINGLE_GUI_OPERATION"
                args.receipt.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
                print(json.dumps({"gui_result": receipt["gui_result"]}), flush=True)
    finally:
        if workspace_listener is not None:
            _close(workspace_listener, workspace_worker)
        if service is not None:
            service.close()
        qualifier.doCleanups()


if __name__ == "__main__":
    main()
