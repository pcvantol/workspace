"""Own worklist credentials and GET-only transport; producer fixtures are source tests."""

import hashlib
import http.client
import io
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler
import json
import os
from pathlib import Path
import ssl
import tempfile
from threading import Thread
import unittest
from unittest.mock import Mock, patch

from tests.test_worklist_contract import projection, seal
from workspace_control.cli import main
from workspace_control.http import ThreadingHTTPServer, handler_for, operation_inventory
from workspace_control.schemas import OPENAPI_SCHEMAS as SCHEMAS
from workspace_control.service import Service, initialize
from workspace_control.worklist_peer import WorklistError, WorklistReadTransport, _get


class WorklistPeerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="workspace-worklist-peer-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.root.chmod(0o700)
        initialize(self.root)
        self.service = Service(self.root)
        self.addCleanup(self.service.close)
        self.reader = WorklistReadTransport(self.root, self.service._root_fd)
        self.forge_instance = "f" * 32
        self.tokens = {"F" * 43: ("actor-a", ["workset-a"]), "B" * 43: ("actor-b", ["workset-b"])}
        self.revoked = set()
        self.status = 200
        self.tamper = None
        self.calls = []
        self.projection_tamper = None
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args): pass

            def do_GET(self):
                owner.calls.append(("GET", self.path))
                token = self.headers.get("Authorization", "").removeprefix("Bearer ")
                code = owner.status
                if token not in owner.tokens or token in owner.revoked:
                    code = 401
                if code == 200:
                    actor, worksets = owner.tokens[token]
                    body = {"contract_version": "forge-workspace-worklist-scopes/v1",
                            "instance_id": owner.forge_instance, "principal_id": actor,
                            "workset_ids": worksets, "read_only": True}
                    if owner.tamper == "actor": body["principal_id"] = "foreign"
                    if owner.tamper == "instance": body["instance_id"] = "foreign"
                    if owner.tamper == "empty": body["workset_ids"] = []
                    if owner.tamper == "duplicate": body["workset_ids"] = worksets * 2
                    if owner.tamper == "widened": body["workset_ids"] = worksets + ["unexpected"]
                    if owner.tamper == "extra": body["admin"] = True
                    if owner.tamper == "read_flag": body["read_only"] = 1
                    if owner.tamper == "invalid_id": body["workset_ids"] = ["../foreign"]
                    if owner.tamper == "too_many": body["workset_ids"] = [f"workset-{i}" for i in range(17)]
                else:
                    body = {"error": "private-peer-error-not-for-consumer"}
                if code == 200 and self.path != "/v1/worksets":
                    body = projection(allocated=True)
                    body["instance_id"] = owner.forge_instance
                    body["scope"]["principal_id"] = actor
                    body["scope"]["workset_id"] = worksets[0]
                    if owner.projection_tamper == "partial": body["completeness"] = "PARTIAL"
                    if owner.projection_tamper == "scope": body["scope"]["principal_id"] = "foreign"
                    seal(body)
                    if owner.projection_tamper == "digest": body["snapshot_revision"] = "sha256:" + "0" * 64
                encoded = json.dumps(body).encode()
                if owner.tamper == "bad_json": encoded = b"{"
                if owner.tamper == "duplicate_json": encoded = b'{"principal_id":"a","principal_id":"b"}'
                if owner.tamper == "invalid_utf8": encoded = b"\xff"
                self.send_response(code)
                self.send_header("Content-Type", "text/plain" if owner.tamper == "content_type" else "application/json")
                length = "invalid" if owner.tamper == "length" else str(len(encoded))
                if owner.tamper == "oversize": length = "1000001"
                self.send_header("Content-Length", length)
                self.end_headers()
                self.wfile.write(encoded)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.worker = Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()
        self.addCleanup(self.worker.join, 3)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.endpoint = f"http://127.0.0.1:{self.server.server_port}"
        self.forge_file = self.root / "forge-token"
        self.forge_file.write_text("F" * 43)
        self.forge_file.chmod(0o600)
        self.client_file = self.root / "client-token"

    def provision(self):
        receipt = self.reader.provision("actor-a", self.endpoint, self.forge_instance,
                                        str(self.forge_file), str(self.client_file))
        return self.client_file.read_text().strip(), receipt

    def start_workspace(self):
        listener = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.service))
        worker = Thread(target=listener.serve_forever, daemon=True)
        worker.start()
        self.addCleanup(worker.join, 3)
        self.addCleanup(listener.server_close)
        self.addCleanup(listener.shutdown)
        return listener.server_port

    def request(self, port, path, *, grant=None, method="GET", read_token=None, instance=None, extra=None):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        headers = {"Authorization": "Bearer " + (read_token or self.service.token),
                   "X-Workspace-Instance": instance or self.service.instance_id}
        if grant is not None: headers["X-Workspace-Worklist-Grant"] = grant
        headers.update(extra or {})
        try:
            connection.request(method, path, headers=headers)
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally: connection.close()

    def test_projection_reads_exact_scoped_snapshot_and_does_not_mutate_product_files(self):
        token, _ = self.provision()
        port = self.start_workspace()
        before = {path.name: path.read_bytes() for path in self.root.iterdir() if path.is_file()}
        code, observed = self.request(port, "/v1/worksets/workset-a", grant=token)
        self.assertEqual(code, 200)
        self.assertEqual(observed["scope"]["principal_id"], "actor-a")
        self.assertEqual(observed["items"][0]["mission_id"], "mission-a")
        self.assertEqual(observed["items"][0]["evidence_references"][1]["subject_id"], "business-decision-a")
        count = len(self.calls)
        self.assertEqual(self.request(port, "/v1/worksets/workset-b", grant=token)[0], 403)
        self.assertEqual(len(self.calls), count)
        self.assertEqual(self.request(port, "/v1/worksets/workset-a", grant="unknown")[0], 403)
        self.projection_tamper = "partial"
        code, observed = self.request(port, "/v1/worksets/workset-a", grant=token)
        self.assertEqual((code, observed["completeness"]), (200, "PARTIAL"))
        for tamper in ("digest", "scope"):
            self.projection_tamper = tamper
            code, observed = self.request(port, "/v1/worksets/workset-a", grant=token)
            self.assertEqual(code, 503)
            self.assertNotIn("items", observed)
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            self.assertEqual(self.request(port, "/v1/worksets/workset-a", grant=token, method=method)[0], 405)
        self.assertEqual({path.name: path.read_bytes() for path in self.root.iterdir() if path.is_file()}, before)
        self.assertTrue(all(method == "GET" for method, _ in self.calls))

    def test_owner_cli_and_authenticated_http_do_not_print_or_borrow_credentials(self):
        output = io.StringIO()
        with redirect_stdout(output):
            code = main(["--root", str(self.root), "worklist-bind-issue", "--actor", "actor-a",
                         "--forge-endpoint", self.endpoint, "--forge-instance-id", self.forge_instance,
                         "--forge-token-file", str(self.forge_file), "--client-token-file", str(self.client_file)])
        self.assertEqual(code, 0)
        token = self.client_file.read_text().strip()
        self.assertNotIn(token, output.getvalue())
        self.assertNotIn("F" * 43, output.getvalue())
        receipt = json.loads(output.getvalue())
        port = self.start_workspace()
        status, scopes = self.request(port, "/v1/worksets", grant=token, extra={"X-Workspace-Actor": "actor-b"})
        self.assertEqual(status, 200)
        self.assertEqual(scopes["principal_id"], "actor-a")
        self.assertEqual(self.request(port, "/v1/worksets")[0], 403)
        self.assertEqual(self.request(port, "/v1/worksets", grant="F" * 43)[0], 403)
        self.assertEqual(self.request(port, "/v1/worksets", grant=token, read_token="bad")[0], 401)
        self.assertEqual(self.request(port, "/v1/worksets", grant=token, instance="foreign")[0], 409)
        self.assertEqual(self.request(port, "/v1/worksets?actor=actor-b", grant=token)[0], 400)
        contract_status, contract = self.request(port, "/v1/worksets/openapi.json")
        self.assertEqual(contract_status, 200)
        self.assertEqual(set(contract["paths"]["/v1/worksets"]), {"get"})
        self.assertEqual(contract["components"]["securitySchemes"]["worklistGrant"]["name"], "X-Workspace-Worklist-Grant")
        inventory = operation_inventory(self.service.instance_id)
        auth_values = SCHEMAS["Operation"]["properties"]["auth"]["enum"]
        self.assertTrue(all(operation["auth"] in auth_values for operation in inventory["operations"]))
        with redirect_stdout(io.StringIO()):
            self.assertEqual(main(["--root", str(self.root), "worklist-bind-revoke", "--binding-id", receipt["binding_id"]]), 0)
        self.assertEqual(self.request(port, "/v1/worksets", grant=token)[0], 403)

    def test_http_worklist_is_read_only_and_maps_only_sanitized_errors(self):
        token, _ = self.provision()
        port = self.start_workspace()
        for status, expected in [(401, 401), (403, 403), (404, 404), (409, 409), (503, 503), (201, 503)]:
            self.status = status
            code, body = self.request(port, "/v1/worksets", grant=token)
            self.assertEqual(code, expected)
            self.assertNotIn("private-peer-error", json.dumps(body))
        self.status = 200
        before = list(self.calls)
        for method in ["POST", "PATCH", "PUT", "DELETE"]:
            self.assertEqual(self.request(port, "/v1/worksets", method=method, grant=token)[0], 405)
        self.assertEqual(before, self.calls)
        draft = self.service.conversations.issue_grant("actor-a", "project-a")
        self.assertEqual(self.request(port, "/v1/worksets", grant=draft)[0], 403)
        self.assertEqual(self.request(port, "/v1/worksets", extra={"X-Workspace-Review-Grant": token})[0], 403)
        with patch.object(self.service.worklists, "scopes", side_effect=OSError("private file path")):
            code, body = self.request(port, "/v1/worksets", grant=token)
        self.assertEqual(code, 503)
        self.assertEqual(body, {"error": "WORKLIST_UNAVAILABLE"})
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        try:
            connection.putrequest("GET", "/v1/worksets")
            connection.putheader("Authorization", "Bearer " + self.service.token)
            connection.putheader("X-Workspace-Instance", self.service.instance_id)
            connection.putheader("X-Workspace-Worklist-Grant", token)
            connection.putheader("X-Workspace-Worklist-Grant", token)
            connection.endheaders()
            response = connection.getresponse()
            self.assertEqual(response.status, 403)
            response.read()
        finally: connection.close()

    def test_private_separate_binding_scoped_reads_revocation_and_no_read_mutation(self):
        token, receipt = self.provision()
        self.assertNotIn(token, json.dumps(receipt))
        self.assertNotIn("F" * 43, json.dumps(receipt))
        path = self.root / "worklist-bindings.json"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.client_file.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(token, path.read_text())
        before = (path.read_bytes(), path.stat().st_mtime_ns)
        binding = self.reader.access(token)
        result = self.reader.scopes(binding)
        self.assertEqual(result["workset_ids"], ["workset-a"])
        self.assertEqual(before, (path.read_bytes(), path.stat().st_mtime_ns))
        self.assertFalse((self.root / "review-bindings.json").exists())
        self.assertFalse((self.root / "review-intents.sqlite3").exists())
        self.assertTrue(all(method == "GET" and route == "/v1/worksets" for method, route in self.calls))
        self.revoked.add("F" * 43)
        with self.assertRaisesRegex(WorklistError, "UNAUTHORIZED"):
            self.reader.scopes(binding)
        self.reader.revoke(receipt["binding_id"])
        with self.assertRaisesRegex(WorklistError, "DENIED"): self.reader.access(token)
        with self.assertRaises(FileNotFoundError): self.reader.revoke(receipt["binding_id"])
        with self.assertRaises(ValueError): self.reader.revoke("../id")

    def test_actor_scope_and_malformed_producer_cannot_issue_or_widen_binding(self):
        for tamper in ["actor", "instance", "empty", "duplicate", "extra", "read_flag", "invalid_id", "too_many"]:
            with self.subTest(tamper=tamper):
                self.tamper = tamper
                with self.assertRaisesRegex(WorklistError, "INVALID_RESPONSE"): self.provision()
                self.assertFalse(self.client_file.exists())
                self.assertFalse((self.root / "worklist-bindings.json").exists())
        self.tamper = None
        token, _ = self.provision()
        self.tamper = "widened"
        with self.assertRaisesRegex(WorklistError, "INVALID_RESPONSE"):
            self.reader.scopes(self.reader.access(token))

    def test_two_actors_have_separate_exact_credentials_and_no_old_grant_file(self):
        alice, _ = self.provision()
        self.forge_file.write_text("B" * 43)
        bob_file = self.root / "bob-token"
        self.reader.provision("actor-b", self.endpoint, self.forge_instance,
                              str(self.forge_file), str(bob_file))
        bob = bob_file.read_text().strip()
        self.assertEqual(self.reader.scopes(self.reader.access(alice))["principal_id"], "actor-a")
        self.assertEqual(self.reader.scopes(self.reader.access(bob))["workset_ids"], ["workset-b"])
        for bad in [None, "bad", self.service.token, "F" * 43]:
            with self.assertRaisesRegex(WorklistError, "DENIED"): self.reader.access(bad)

    def test_peer_failures_redirects_malformed_and_oversized_bodies_are_sanitized(self):
        token, _ = self.provision()
        binding = self.reader.access(token)
        for status, expected in [(401, "UNAUTHORIZED"), (403, "DENIED"), (404, "NOT_FOUND"),
                                 (409, "CONFLICT"), (503, "UNAVAILABLE"), (301, "INVALID_RESPONSE"), (201, "INVALID_RESPONSE")]:
            with self.subTest(status=status):
                self.status = status
                with self.assertRaisesRegex(WorklistError, expected): self.reader.scopes(binding)
        self.status = 200
        for tamper in ["bad_json", "duplicate_json", "invalid_utf8", "content_type", "length", "oversize"]:
            self.tamper = tamper
            with self.assertRaisesRegex(WorklistError, "INVALID_RESPONSE"): self.reader.scopes(binding)
        fake = Mock()
        fake.getresponse.return_value.status = 200
        fake.getresponse.return_value.getheader.side_effect = lambda name, default=None: "application/json" if name == "Content-Type" else None
        fake.getresponse.return_value.read.return_value = b"x" * 1_000_001
        with patch("workspace_control.worklist_peer.http.client.HTTPConnection", return_value=fake):
            with self.assertRaisesRegex(WorklistError, "INVALID_RESPONSE"): _get(binding, "/v1/worksets")
        fake.request.side_effect = http.client.HTTPException()
        with patch("workspace_control.worklist_peer.http.client.HTTPConnection", return_value=fake):
            with self.assertRaisesRegex(WorklistError, "UNAVAILABLE"): _get(binding, "/v1/worksets")
        secure = dict(binding, endpoint="https://localhost:443")
        fake.request.side_effect = ssl.SSLCertVerificationError()
        with patch("workspace_control.worklist_peer.http.client.HTTPSConnection", return_value=fake):
            with self.assertRaisesRegex(WorklistError, "TLS_UNTRUSTED"): _get(secure, "/v1/worksets")

    def test_owner_paths_permissions_duplicate_issue_and_failed_write_fail_closed(self):
        for actor, instance, source, output in [("../actor", self.forge_instance, str(self.forge_file), str(self.client_file)),
            ("actor-a", "", str(self.forge_file), str(self.client_file)),
            ("actor-a", self.forge_instance, "relative", str(self.client_file))]:
            with self.assertRaises(ValueError): self.reader.provision(actor, self.endpoint, instance, source, output)
        self.forge_file.write_text("bad")
        with self.assertRaises(ValueError): self.provision()
        self.forge_file.write_text("F" * 43)
        public = self.root / "public"
        public.mkdir(mode=0o755)
        with self.assertRaises(ValueError):
            self.reader.provision("actor-a", self.endpoint, self.forge_instance, str(self.forge_file), str(public / "token"))
        with patch.object(self.reader, "_write_bindings", side_effect=OSError("controlled failure")):
            with self.assertRaises(OSError): self.provision()
        self.assertFalse(self.client_file.exists())
        self.provision()
        second = self.root / "second"
        with self.assertRaises(ValueError):
            self.reader.provision("actor-a", self.endpoint, self.forge_instance, str(self.forge_file), str(second))
        self.assertFalse(second.exists())
        lock = self.root / ".worklist-bindings.lock"
        lock.chmod(0o666)
        with self.assertRaisesRegex(WorklistError, "INVALID_CONFIGURATION"): self.reader.revoke("id")

    def test_corrupt_private_binding_and_duplicate_identity_never_authorize(self):
        token, _ = self.provision()
        path = self.root / "worklist-bindings.json"
        valid = json.loads(path.read_text())
        corrupt = [{"bindings": "bad"}, {"bindings": [None]}, {"bindings": valid["bindings"] * 2}]
        for key, value in [("client_digest", "bad"), ("actor_id", "../foreign"), ("forge_token", "bad"),
                           ("workset_ids", []), ("endpoint", "http://example.com")]:
            record = dict(valid["bindings"][0], **{key: value})
            corrupt.append({"bindings": [record]})
        for document in corrupt:
            path.write_text(json.dumps(document))
            with self.assertRaisesRegex(WorklistError, "INVALID_CONFIGURATION"): self.reader.access(token)
        path.write_text("{")
        with self.assertRaisesRegex(WorklistError, "INVALID_CONFIGURATION"): self.reader.access(token)


if __name__ == "__main__": unittest.main()
