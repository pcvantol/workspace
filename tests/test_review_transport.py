"""Real Workspace HTTP checks against the pinned Forge review wire contract."""

from datetime import datetime, timedelta, timezone
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from contextlib import redirect_stdout

from workspace_control.cli import main
from workspace_control.http import ThreadingHTTPServer, handler_for
from workspace_control.review_peer import ReviewError, _request_digest
from workspace_control.service import Service, initialize


MISSION = "mission-review-a"
FOREIGN = "mission-review-b"
FORGE_INSTANCE = "f" * 32
SUBJECT = "sha256:" + "a" * 64
EVIDENCE = "sha256:" + "b" * 64
POLICY_DIGEST = "sha256:" + "c" * 64
DECISION_DIGEST = "sha256:" + "d" * 64
STAMP = "2026-10-06T12:00:00Z"
EXPIRY = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()


def item(actor="reviewer-alice", *, mission=MISSION, recorded=None):
    requirement = {
        "requirement_id": "review-required-1", "subject_digest": SUBJECT,
        "subject_revision": "source-r1", "mission_state_revision": 3,
        "completed_action_id": "action-1", "evidence_digest": EVIDENCE,
        "policy_revision": "policy-r1", "policy_digest": POLICY_DIGEST,
        "required_role": "platform_architect", "required_role_actor": "primary_operator",
        "required_capability": "ARCHITECTURE_APPROVAL", "reason": "Completed Action waits",
        "blocking_scope": ["action-1"], "blocking_scope_redacted": False,
        "status": "AWAITING_APPROVAL",
    }
    return {
        "contract_version": "forge-workspace-review-inbox/v1", "instance_id": FORGE_INSTANCE,
        "mission_id": mission,
        "authority": {"principal_id": actor, "role": "platform_architect",
                      "role_actor": "primary_operator", "capability": "ARCHITECTURE_APPROVAL",
                      "expires_at": EXPIRY},
        "title": "Review exact Action", "lifecycle_state": "AWAITING_APPROVAL",
        "mission_state_revision": 4 if recorded else 3,
        "review_kind": "PROGRESSION",
        "decision": (None if recorded is None else
                     {"decision_id": recorded["operation_id"], "outcome": recorded["decision"],
                      "decision_digest": DECISION_DIGEST}),
        "requirement": requirement,
        "action_result": {"action_id": "action-1", "status": "COMPLETE", "outcome": "complete",
                          "evidence_reference": {"kind": "FORGE_EXECUTION_EVIDENCE",
                                                 "digest": EVIDENCE, "receipt_id": "receipt-1"}},
        "allowed_outcomes": [] if recorded else ["approve", "reject", "amend", "defer"],
        "observed_at": STAMP, "freshness": "CURRENT_FORGE_RUNTIME_READBACK",
    }


def decision(operation="decision-1", reason="Exact evidence accepted"):
    return {"contract_version": "forge-workspace-review-decision/v1",
            "operation_id": operation, "requirement_id": "review-required-1",
            "subject_digest": SUBJECT, "mission_state_revision": 3,
            "evidence_digest": EVIDENCE, "policy_revision": "policy-r1",
            "decision": "defer", "reason": reason}


class FakeForge:
    def __init__(self):
        self.token = "F" * 43
        self.actor = "reviewer-alice"
        self.revoked = False
        self.recorded = None
        self.posts = 0
        self.tamper = None

    def start(self):
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def reply(self, code, value):
                if owner.tamper == "actor" and code == 200 and isinstance(value, dict):
                    value = json.loads(json.dumps(value))
                    if "scope" in value:
                        value["scope"]["principal_id"] = "foreign-actor"
                    elif "authority" in value:
                        value["authority"]["principal_id"] = "foreign-actor"
                if owner.tamper == "digest" and code == 200 and "operation" in value:
                    value = json.loads(json.dumps(value))
                    value["operation"]["request_digest"] = "sha256:" + "0" * 64
                encoded = json.dumps(value).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def authorized(self):
                if owner.revoked or self.headers.get("Authorization") != "Bearer " + owner.token:
                    self.reply(401, {"error": "denied"})
                    return False
                return True

            def do_GET(self):
                if not self.authorized():
                    return
                if self.path == "/v1/reviews":
                    return self.reply(200, {
                        "contract_version": "forge-workspace-review-inbox/v1",
                        "instance_id": FORGE_INSTANCE,
                        "scope": {"kind": "EXPLICIT_MISSION_SET", "principal_id": owner.actor,
                                  "mission_ids": [MISSION], "complete_within_scope": True},
                        "items": [item(owner.actor, recorded=owner.recorded)], "read_only": True})
                if self.path == f"/v1/reviews/missions/{MISSION}":
                    return self.reply(200, item(owner.actor, recorded=owner.recorded))
                if self.path.startswith(f"/v1/reviews/missions/{MISSION}/decisions/"):
                    operation_id = self.path.rsplit("/", 1)[-1]
                    if owner.recorded is None or owner.recorded["operation_id"] != operation_id:
                        return self.reply(404, {"error": "not_found"})
                    return self.reply(200, owner.receipt(read_only=True))
                return self.reply(403, {"error": "denied"})

            def do_POST(self):
                if not self.authorized():
                    return
                if self.path != f"/v1/reviews/missions/{MISSION}/decisions":
                    return self.reply(403, {"error": "denied"})
                raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                try:
                    request = json.loads(raw)
                except ValueError:
                    return self.reply(409, {"error": "invalid"})
                owner.posts += 1
                if owner.recorded is not None:
                    if request != owner.recorded:
                        return self.reply(409, {"error": "conflict"})
                    return self.reply(200, owner.receipt(read_only=False, recorded=False))
                owner.recorded = request
                return self.reply(201, owner.receipt(read_only=False, recorded=True))

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_port}"

    def receipt(self, *, read_only, recorded=False):
        request = self.recorded
        operation = {"operation_id": request["operation_id"], "mission_id": MISSION,
                     "requirement_id": request["requirement_id"],
                     "subject_digest": request["subject_digest"], "decision": request["decision"],
                     "decision_digest": DECISION_DIGEST,
                     "request_digest": _request_digest(MISSION, request), "recorded_at": STAMP}
        result = {"contract_version": "forge-workspace-review-operation/v1",
                  "operation": operation, "current": item(self.actor, recorded=request)}
        return result | ({"read_only": True} if read_only else
                         {"runtime_status": "AWAITING_APPROVAL", "recorded": recorded})

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)


class ReviewTransportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "workspace"
        self.root.mkdir(mode=0o700)
        self.instance = initialize(self.root)
        self.forge = FakeForge()
        self.forge_endpoint = self.forge.start()
        self.addCleanup(self.forge.close)
        self.service = Service(self.root)
        self.addCleanup(self.service.close)
        self.start_workspace()
        self.forge_file = self.root / "forge-review-token"
        self.forge_file.write_text(self.forge.token + "\n")
        self.forge_file.chmod(0o600)
        self.client_file = self.root / "workspace-review-token"

    def start_workspace(self):
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.service))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close_workspace(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)

    def tearDown(self):
        self.close_workspace()

    def provision(self):
        receipt = self.service.provision_review("reviewer-alice", self.forge_endpoint,
                                                FORGE_INSTANCE, str(self.forge_file),
                                                str(self.client_file))
        self.assertEqual(receipt["mission_ids"], [MISSION])
        self.assertNotIn(self.forge.token, json.dumps(receipt))
        return self.client_file.read_text().strip(), receipt

    def request(self, path, *, method="GET", client_token=None, workspace_token=None,
                instance=None, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        request_headers = {"Authorization": "Bearer " + (workspace_token or self.service.token),
                           "X-Workspace-Instance": instance or self.instance}
        if client_token is not None:
            request_headers["X-Workspace-Review-Grant"] = client_token
        if body is not None:
            request_headers["Content-Type"] = "application/json"
        request_headers.update(headers or {})
        try:
            connection.request(method, path, body=None if body is None else json.dumps(body),
                               headers=request_headers)
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_owner_provision_and_scoped_reads_do_not_mutate(self):
        client_token, receipt = self.provision()
        self.assertEqual((self.root / "review-bindings.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.client_file.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(client_token, (self.root / "review-bindings.json").read_text())
        self.assertNotIn(self.forge.token, json.dumps(receipt))
        self.assertFalse((self.root / "review-intents.sqlite3").exists())
        status, inbox = self.request("/v1/reviews", client_token=client_token)
        self.assertEqual(status, 200, inbox)
        self.assertEqual(inbox["scope"]["principal_id"], "reviewer-alice")
        self.assertEqual(inbox["scope"]["mission_ids"], [MISSION])
        self.assertEqual(inbox["items"][0]["allowed_outcomes"], ["approve", "reject", "amend", "defer"])
        self.assertEqual(self.request(f"/v1/reviews/missions/{MISSION}", client_token=client_token)[0], 200)
        self.assertEqual(self.request("/v1/reviews/openapi.json")[0], 200)
        self.assertEqual(self.forge.posts, 0)
        self.assertFalse((self.root / "review-intents.sqlite3").exists())

    def test_credential_scope_and_revocation(self):
        token, receipt = self.provision()
        self.assertEqual(self.request("/v1/reviews")[0], 403)
        self.assertEqual(self.request("/v1/reviews", client_token="wrong")[0], 403)
        self.assertEqual(self.request("/v1/reviews", client_token=token, workspace_token="bad")[0], 401)
        self.assertEqual(self.request("/v1/reviews", client_token=token, instance="wrong")[0], 409)
        self.assertEqual(self.request(f"/v1/reviews/missions/{FOREIGN}", client_token=token)[0], 403)
        self.assertEqual(self.request(f"/v1/reviews/missions/{FOREIGN}/decisions", method="POST",
                                      client_token=token, body=decision())[0], 403)
        self.assertEqual(self.forge.posts, 0)
        self.forge.revoked = True
        self.assertEqual(self.request("/v1/reviews", client_token=token)[0], 401)
        self.forge.revoked = False
        self.service.revoke_review(receipt["binding_id"])
        self.assertEqual(self.request("/v1/reviews", client_token=token)[0], 403)

    def test_decision_receipt_restart_replay_and_conflict(self):
        token, _ = self.provision()
        command = decision(reason="Controleer résumé en bewijs")
        path = f"/v1/reviews/missions/{MISSION}/decisions"
        self.assertEqual(self.request(path + "/" + command["operation_id"], client_token=token)[0], 404)
        self.assertFalse((self.root / "review-intents.sqlite3").exists())
        status, response = self.request(path, method="POST", client_token=token, body=command)
        self.assertEqual(status, 201, response)
        self.assertTrue(response["recorded"])
        self.assertEqual(response["operation"]["request_digest"], _request_digest(MISSION, command))
        self.assertEqual(self.forge.posts, 1)
        self.close_workspace()
        self.service.close()
        self.service = Service(self.root)
        self.start_workspace()
        status, readback = self.request(path + "/" + command["operation_id"], client_token=token)
        self.assertEqual(status, 200, readback)
        self.assertEqual(readback["operation"], response["operation"])
        self.assertEqual(readback["current"]["allowed_outcomes"], [])
        self.assertEqual(self.forge.posts, 1)
        replay_status, replay = self.request(path, method="POST", client_token=token, body=command)
        self.assertEqual(replay_status, 200, replay)
        self.assertFalse(replay["recorded"])
        self.assertEqual(self.request(path, method="POST", client_token=token,
                                      body=decision(reason="Different reason"))[0], 409)
        self.assertEqual(self.forge.posts, 2)

    def test_client_fields_and_tampered_producer_fail_closed(self):
        token, _ = self.provision()
        path = f"/v1/reviews/missions/{MISSION}/decisions"
        self.assertEqual(self.request(path, method="POST", client_token=token,
                                      body=decision() | {"actor": "reviewer-alice"})[0], 400)
        self.assertEqual(self.request(path, method="POST", client_token=token,
                                      body=decision() | {"mission_state_revision": True})[0], 400)
        self.assertEqual(self.forge.posts, 0)
        self.forge.tamper = "actor"
        self.assertEqual(self.request("/v1/reviews", client_token=token)[0], 503)
        self.assertEqual(self.request(f"/v1/reviews/missions/{MISSION}", client_token=token)[0], 503)
        self.forge.tamper = None
        self.assertEqual(self.request(path, method="POST", client_token=token, body=decision())[0], 201)
        self.forge.tamper = "digest"
        self.assertEqual(self.request(path + "/decision-1", client_token=token)[0], 503)

    def test_owner_cli_never_prints_bearers_and_rejects_duplicate_binding(self):
        output = io.StringIO()
        with redirect_stdout(output):
            code = main(["--root", str(self.root), "review-bind-issue",
                         "--actor", "reviewer-alice", "--forge-endpoint", self.forge_endpoint,
                         "--forge-instance-id", FORGE_INSTANCE,
                         "--forge-token-file", str(self.forge_file),
                         "--client-token-file", str(self.client_file)])
        self.assertEqual(code, 0)
        receipt = json.loads(output.getvalue())
        self.assertNotIn(self.forge.token, output.getvalue())
        self.assertNotIn(self.client_file.read_text().strip(), output.getvalue())
        second = self.root / "second-client-token"
        with self.assertRaises(ValueError):
            self.service.provision_review("reviewer-alice", self.forge_endpoint, FORGE_INSTANCE,
                                          str(self.forge_file), str(second))
        self.assertFalse(second.exists())
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--root", str(self.root), "review-bind-revoke",
                                   "--binding-id", receipt["binding_id"]]), 0)
        self.assertEqual(json.loads(output.getvalue())["state"], "REVOKED")


if __name__ == "__main__":
    unittest.main()
