"""Real HTTP and state qualification for the own read-only slice."""

import json
import hashlib
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import http.client
from http.server import BaseHTTPRequestHandler
import importlib
import io
import os
from pathlib import Path
import re
import socket
import sqlite3
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from unittest.mock import Mock, patch
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from workspace_control.cli import main, client_main
from workspace_control.http import ThreadingHTTPServer, handler_for, listener_config, serve, ROUTES, OPERATIONS
from workspace_control.service import Service, _regular_private, initialize, inspect
from workspace_control.conversations import ConversationConflict, ConversationStore
from workspace_control.forge_peer import _binding, _endpoint
import workspace_control.forge_peer as forge_peer


class ReadOnlyTests(unittest.TestCase):
    def test_version_projection_uses_package_and_source(self):
        import workspace_control
        root = Path(__file__).resolve().parents[1]
        expected = json.loads((root / "product-version.json").read_text())["version"]
        self.assertEqual(importlib.reload(workspace_control).__version__, expected)
        with patch("pathlib.Path.read_text", side_effect=FileNotFoundError), patch("importlib.metadata.version", return_value=expected):
            self.assertEqual(importlib.reload(workspace_control).__version__, expected)
        self.assertEqual(importlib.reload(workspace_control).__version__, expected)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "one"
        self.root.mkdir(mode=0o700)
        self.instance = initialize(self.root)
        self.service = Service(self.root)
        self.addCleanup(self.service.close)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.service))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def request(self, path, *, method="GET", token=None, instance=None, origin=None):
        headers = {}
        if token is not None:
            headers["Authorization"] = "Bearer " + token
        if instance is not None:
            headers["X-Workspace-Instance"] = instance
        if origin is not None:
            headers["Origin"] = origin
        request = Request(self.url + path, method=method, headers=headers)
        try:
            with urlopen(request, timeout=2) as response:
                return response.status, response.read(), response.headers
        except HTTPError as error:
            try:
                return error.code, error.read(), error.headers
            finally:
                error.close()

    def authorized(self, path):
        return self.request(path, token=self.service.token, instance=self.instance)

    def raw_request(self, path, *, method="GET", hosts=(), origins=(),
                    authorizations=None, pins=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        try:
            connection.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
            for host in hosts:
                connection.putheader("Host", host)
            for origin in origins:
                connection.putheader("Origin", origin)
            if authorizations is None:
                authorizations = ("Bearer " + self.service.token,)
            if pins is None:
                pins = (self.instance,)
            for authorization in authorizations:
                connection.putheader("Authorization", authorization)
            for pin in pins:
                connection.putheader("X-Workspace-Instance", pin)
            connection.endheaders()
            response = connection.getresponse()
            body = response.read()
            return (response.status, json.loads(body) if body and response.headers.get_content_type() == "application/json" else None,
                    response.headers, body)
        finally:
            connection.close()

    def test_loopback_host_and_origin_are_bound_before_assets_and_api(self):
        port = self.server.server_port
        for host in (f"127.0.0.1:{port}", f"localhost:{port}"):
            for path in ("/v1/identity", "/v1/status", "/"):
                with self.subTest(host=host, path=path):
                    self.assertEqual(self.raw_request(path, hosts=(host,),
                                                      origins=(f"http://{host}",))[0], 200)
            for method in ("POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE", "CONNECT"):
                self.assertEqual(self.raw_request("/v1/status", method=method, hosts=(host,))[0], 405)
            get = self.raw_request("/v1/status", hosts=(host,))
            head = self.raw_request("/v1/status", method="HEAD", hosts=(host,))
            self.assertEqual(head[0], get[0])
            self.assertEqual(head[2]["Content-Length"], get[2]["Content-Length"])
            self.assertEqual(head[3], b"")
        for hosts in ((), (f"evil.example:{port}",),
                      (f"127.0.0.1:{port}", f"evil.example:{port}"),
                      (f"127.0.0.1:{port}", f"127.0.0.1:{port}")):
            for path in ("/v1/identity", "/v1/status", "/"):
                with self.subTest(hosts=hosts, path=path):
                    self.assertEqual(self.raw_request(path, hosts=hosts)[0], 403)
            for method in ("POST", "HEAD", "OPTIONS", "TRACE", "CONNECT"):
                self.assertEqual(self.raw_request("/v1/status", method=method, hosts=hosts)[0], 403)
        host = f"127.0.0.1:{port}"
        for target in ("http://evil.example/v1/identity",
                       "http://[bad/v1/identity", "//[bad/v1/identity",
                       f"http://{host}/v1/status", "//evil.example/v1/identity",
                       "/v1/identity?", "/v1/identity#", "/v1/status?", "/v1/status#"):
            for method in ("GET", "HEAD"):
                with self.subTest(target=target, method=method):
                    response = self.raw_request(target, method=method, hosts=(host,))
                    self.assertEqual(response[0], 400)
                    if method == "GET":
                        self.assertEqual(response[1]["error"], "INVALID_PATH")
        for origins in (("http://evil.example",), (f"http://{host}", f"http://{host}"),
                        ("null",)):
            for path in ("/v1/identity", "/v1/status", "/"):
                with self.subTest(origins=origins, path=path):
                    self.assertEqual(self.raw_request(path, hosts=(host,), origins=origins)[0], 403)
        self.assertEqual(self.authorized("/v1/status")[0], 200)

    def test_rejected_request_targets_are_not_logged(self):
        host = f"127.0.0.1:{self.server.server_port}"
        secret = "private-token-value-do-not-log"
        output = io.StringIO()
        with redirect_stderr(output):
            self.assertEqual(self.raw_request(f"/v1/identity?token={secret}", hosts=(host,))[0], 400)
            self.assertEqual(self.raw_request(f"/v1/identity?token={secret}",
                                              method="POST", hosts=(host,))[0], 405)
        self.assertNotIn(secret, output.getvalue())
        self.assertEqual(output.getvalue(), "")

    def test_parser_errors_do_not_echo_request_targets(self):
        secret = b"private-token-value-do-not-echo"
        for request_line, status, body_expected in (
            (b"GET /v1/identity?token=" + secret + b" HTTP/1.1 EXTRA\r\n", b"400", True),
            (b"UNKNOWN /v1/identity?token=" + secret + b" HTTP/1.1\r\n", b"501", True),
            (b"HEAD /v1/identity?token=" + secret + b" HTTP/1.1 EXTRA\r\n", b"400", False),
            (b"HEAD\t/v1/identity?token=" + secret + b" HTTP/1.1 EXTRA\r\n", b"400", False),
        ):
            with self.subTest(status=status), socket.create_connection(
                ("127.0.0.1", self.server.server_port), timeout=2
            ) as connection:
                connection.sendall(request_line + b"Host: 127.0.0.1\r\n\r\n")
                chunks = []
                while chunk := connection.recv(4096):
                    chunks.append(chunk)
                response = b"".join(chunks)
                headers, body = response.split(b"\r\n\r\n", 1)
                self.assertIn(b" " + status + b" ", headers.split(b"\r\n", 1)[0])
                self.assertIn(b"Content-Type: application/json; charset=utf-8", headers)
                self.assertIn(b"Cache-Control: no-store", headers)
                self.assertIn(b"X-Content-Type-Options: nosniff", headers)
                self.assertIn(b"frame-ancestors 'none'", headers)
                self.assertIn(b"X-Frame-Options: DENY", headers)
                if body_expected:
                    self.assertEqual(json.loads(body), {"error": "REQUEST_REJECTED"})
                else:
                    self.assertEqual(body, b"")
                self.assertNotIn(secret, response)

    def test_ambiguous_auth_and_pin_headers_are_rejected(self):
        host = f"127.0.0.1:{self.server.server_port}"
        valid_auth = "Bearer " + self.service.token
        for values in ((valid_auth, valid_auth), (valid_auth, "Bearer wrong"),
                       ("Bearer wrong", valid_auth)):
            with self.subTest(authorizations=values):
                response = self.raw_request("/v1/status", hosts=(host,), authorizations=values)
                self.assertEqual((response[0], response[1]["error"]), (400, "AMBIGUOUS_CREDENTIALS"))
        for values in ((self.instance, self.instance), (self.instance, "wrong"),
                       ("wrong", self.instance)):
            with self.subTest(pins=values):
                response = self.raw_request("/v1/status", hosts=(host,), pins=values)
                self.assertEqual((response[0], response[1]["error"]), (400, "AMBIGUOUS_CREDENTIALS"))
        self.assertEqual(self.raw_request("/v1/status", hosts=(host,), authorizations=())[0], 401)
        self.assertEqual(self.raw_request("/v1/status", hosts=(host,), pins=())[0], 409)
        self.assertEqual(self.raw_request("/v1/status", hosts=(host,))[0], 200)
        self.assertEqual(self.raw_request("/v1/identity", hosts=(host,),
                                          authorizations=(valid_auth, valid_auth))[0], 200)

    def test_identity_auth_routes_and_read_only(self):
        code, data, _ = self.request("/v1/identity")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(data)["instance_id"], self.instance)
        self.assertEqual(self.request("/v1/status")[0], 401)
        self.assertEqual(self.request("/v1/status", token="bad", instance=self.instance)[0], 401)
        self.assertEqual(self.request("/v1/status", token=self.service.token, instance="wrong")[0], 409)
        self.assertEqual(self.request("/v1/status", token=self.service.token, instance=self.instance, origin="https://evil.test")[0], 403)
        self.assertEqual(self.authorized("/v1/status?x=1")[0], 400)
        self.assertEqual(self.authorized("/v1/%73tatus")[0], 400)
        self.assertEqual(self.authorized("/v1/absent")[0], 404)
        self.assertEqual(self.authorized("/v1/projects")[0], 200)
        self.assertEqual(json.loads(self.authorized("/v1/projects")[1])["state"], "UNCONFIGURED")
        self.assertIn(b"openapi", self.authorized("/v1/openapi.json")[1])
        self.assertEqual(self.request("/v1/capabilities")[0], 401)
        self.assertEqual(self.request("/v1/capabilities", token=self.service.token, instance="wrong")[0], 409)
        self.assertEqual(self.authorized("/v1/capabilities")[0], 200)
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            self.assertEqual(self.request("/v1/projects", method=method)[0], 405)
            self.assertEqual(self.request("/v1/capabilities", method=method)[0], 405)
        self.assertFalse((self.root / "projects.json").exists())

    def test_browser_is_real_client_asset(self):
        code, html, headers = self.request("/")
        self.assertEqual(code, 200)
        self.assertIn(b"/client.js", html)
        self.assertIn(b"/client.css", html)
        self.assertNotIn(b"<style", html)
        self.assertIn(b"Read-only", html)
        self.assertIn("no-store", headers["Cache-Control"])
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
        self.assertIn("style-src 'self'", headers["Content-Security-Policy"])
        self.assertNotIn("'unsafe-inline'", headers["Content-Security-Policy"])
        self.assertEqual(headers["X-Frame-Options"], "DENY")
        code, script, _ = self.request("/client.js")
        self.assertEqual(code, 200)
        self.assertIn(b"fetch('/v1/projects'", script)
        self.assertIn(b"fetch('/v1/capabilities'", script)
        self.assertIn(b"'conversations.archive'", script)
        self.assertIn(b"'conversations.restore'", script)
        self.assertIn(b'id="capabilities"', html)
        self.assertIn(b'id="project-observed"', html)
        self.assertIn(b'catalogue.observed_at', script)
        code, style, style_headers = self.request("/client.css")
        self.assertEqual(code, 200)
        self.assertIn(b"background:#f6f8fa", style)
        self.assertEqual(style_headers["Content-Type"], "text/css; charset=utf-8")
        self.assertEqual(style_headers["Cache-Control"], "no-store")
        self.assertEqual(style_headers["X-Frame-Options"], "DENY")

    def test_openapi_postman_route_parity(self):
        api = json.loads(self.authorized("/v1/openapi.json")[1])
        collection = json.loads((Path(__file__).resolve().parents[1] / "docs" /
                                 "WORKSPACE_SERVER_READONLY_V1.postman.json").read_text())
        routes = {item["request"]["url"].removeprefix("{{baseUrl}}") for item in collection["item"]}
        self.assertEqual(set(ROUTES), set(api["paths"]))
        self.assertEqual(set(ROUTES), routes)
        expected_reads = {"/v1/identity": "Identity", "/v1/status": "Status",
                          "/v1/projects": "Projects", "/v1/openapi.json": "OpenAPIContract",
                          "/v1/capabilities": "Capabilities"}
        schemas = api["components"]["schemas"]
        for path, name in expected_reads.items():
            responses = api["paths"][path]["get"]["responses"]
            for code, response in responses.items():
                expected = name if code == "200" else "Error"
                self.assertEqual(response["content"]["application/json"]["schema"]["$ref"],
                                 f"#/components/schemas/{expected}")
                self.assertIn(expected, schemas)
            body = json.loads((self.request(path) if path == "/v1/identity" else
                               self.authorized(path))[1])
            schema = schemas[name]
            self.assertTrue(set(schema["required"]) <= set(body))
            if schema.get("additionalProperties") is False:
                self.assertTrue(set(body) <= set(schema["properties"]))
        self.assertEqual(schemas["Projects"]["properties"]["projects"]["items"]["$ref"],
                         "#/components/schemas/Project")
        self.assertEqual(schemas["Projects"]["properties"]["projects"]["maxItems"], 100)
        for field in ("id", "name"):
            self.assertEqual(schemas["Project"]["properties"][field]["minLength"], 1)
            self.assertEqual(schemas["Project"]["properties"][field]["maxLength"], 120)
        status_version = schemas["Status"]["properties"]["version"]["pattern"]
        inventory_version = schemas["Capabilities"]["properties"]["product_version"]["pattern"]
        self.assertEqual(status_version, inventory_version)
        self.assertIsNotNone(re.fullmatch(status_version, self.service.status()["version"]))
        for invalid_version in ("2.4", "02.4.50", "2.4.50-rc1", "2.4.50.1"):
            self.assertIsNone(re.fullmatch(status_version, invalid_version))
        self.assertTrue(all(api["paths"][path]["get"]["responses"]["403"]["description"] ==
                            "Host or Origin denied" for path in ROUTES))
        public = api["paths"]["/v1/identity"]["get"]
        self.assertEqual(set(public["responses"]), {"200", "400", "403"})
        self.assertNotIn("security", public)
        self.assertNotIn("parameters", public)
        self.assertEqual(self.request("/v1/identity", token="bad", instance="wrong")[0], 200)
        self.assertEqual(self.request("/v1/identity?x=1")[0], 400)
        self.assertEqual(self.request("/v1/identity", origin="https://evil.test")[0], 403)
        for path in set(ROUTES) - {"/v1/identity"}:
            protected = api["paths"][path]["get"]
            self.assertEqual(set(protected["responses"]), {"200", "400", "401", "403", "409", "503"})
            self.assertEqual(protected["security"], [{"bearerAuth": []}])
        inventory = json.loads(self.authorized("/v1/capabilities")[1])
        self.assertEqual((inventory["schema_version"], inventory["instance_id"]), (1, self.instance))
        self.assertFalse(inventory["peer_operations_qualified"])
        operations = {operation["id"]: operation for operation in inventory["operations"]}
        self.assertEqual(set(operations), set(OPERATIONS))
        http_routes = {operation["path"] for operation in operations.values()
                       if operation["exposure"] == "HTTP_EXPOSED" and
                       not operation["id"].startswith(("conversations.", "reviews.", "worksets.", "workset-controls.", "advisory."))}
        self.assertEqual(http_routes, set(ROUTES))
        self.assertEqual(operations["projects.read"]["local_cli"], "projects")
        self.assertEqual(operations["capabilities.read"]["local_cli"], "capabilities")
        self.assertEqual(operations["openapi.read"]["local_cli"], "openapi")
        self.assertEqual({api["paths"][path]["get"]["operationId"] for path in http_routes},
                         {operation["id"] for operation in operations.values()
                          if operation["exposure"] == "HTTP_EXPOSED" and
                          not operation["id"].startswith(("conversations.", "reviews.", "worksets.", "workset-controls.", "advisory."))})
        self.assertEqual({operation["id"] for operation in operations.values()
                          if operation["exposure"] == "LOCAL_ONLY_ADMIN"},
                         {"instance.init", "instance.inspect", "forge.read.configure", "server.serve",
                          "conversations.grant.issue", "conversations.grant.revoke",
                          "reviews.bind.issue", "reviews.bind.revoke", "worksets.bind.issue", "worksets.bind.revoke", "workset-controls.bind.issue", "workset-controls.bind.revoke", "advisory.bind.issue", "advisory.bind.revoke"})
        self.assertTrue(all("path" not in operation for operation in operations.values()
                            if operation["exposure"] == "LOCAL_ONLY_ADMIN"))
        self.assertTrue(all(operation["auth"] in {"BEARER_PINNED", "BEARER_PINNED_AND_DRAFT_GRANT",
                                                  "BEARER_PINNED_AND_REVIEW_GRANT", "BEARER_PINNED_AND_WORKLIST_GRANT", "BEARER_PINNED_AND_WORKLIST_CONTROL_GRANT", "BEARER_PINNED_AND_DRAFT_AND_ADVISORY_GRANT"}
                            for operation in operations.values()
                            if operation.get("path") not in (None, "/v1/identity")))
        for item in collection["item"]:
            self.assertEqual(item["request"]["method"], "GET")
            if item["name"] != "identity":
                self.assertEqual({header["key"] for header in item["request"]["header"]},
                                 {"Authorization", "X-Workspace-Instance"})

    def test_cli_capabilities_matches_http_and_requires_private_instance(self):
        def cli_read():
            stdout, stderr = io.StringIO(), io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                code = main(["--root", str(self.root), "capabilities"])
            return code, stdout.getvalue(), stderr.getvalue()
        code, output, error = cli_read()
        self.assertEqual((code, error), (0, ""))
        inventory = json.loads(output)
        self.assertEqual(inventory, json.loads(self.authorized("/v1/capabilities")[1]))
        self.assertEqual(inventory["instance_id"], self.instance)
        self.assertFalse(inventory["peer_operations_qualified"])
        self.assertNotIn(self.service.token, output)
        identity = self.root / "instance.json"
        identity.chmod(0o644)
        try:
            code, output, error = cli_read()
            self.assertEqual((code, output), (2, ""))
            self.assertNotIn(self.service.token, error)
        finally:
            identity.chmod(0o600)
        self.assertEqual(json.loads(cli_read()[1]), inventory)

    def test_cli_openapi_matches_http_and_requires_private_instance(self):
        def cli_read():
            stdout, stderr = io.StringIO(), io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                code = main(["--root", str(self.root), "openapi"])
            return code, stdout.getvalue(), stderr.getvalue()
        code, output, error = cli_read()
        self.assertEqual((code, error), (0, ""))
        self.assertEqual(json.loads(output), json.loads(self.authorized("/v1/openapi.json")[1]))
        self.assertNotIn(self.service.token, output)
        identity = self.root / "instance.json"
        identity.chmod(0o644)
        try:
            code, output, error = cli_read()
            self.assertEqual((code, output), (2, ""))
            self.assertNotIn(self.service.token, error)
        finally:
            identity.chmod(0o600)

    def test_catalogue_states_and_failure(self):
        target = self.root / "projects.json"
        def write(items, stamp, source="LOCAL"):
            target.write_text(json.dumps({"source": source, "projects": items, "observed_at": stamp}))
            target.chmod(0o600)
        now = time.time()
        from datetime import datetime, timezone
        stamp = lambda seconds: datetime.fromtimestamp(seconds, timezone.utc).isoformat()
        write([], stamp(now))
        self.assertEqual({key: json.loads(self.authorized("/v1/projects")[1])[key]
                          for key in ("state", "partial", "stale")},
                         {"state": "EMPTY", "partial": False, "stale": False})
        write([{"id": "sample", "name": "Sample"}], stamp(now), "DEMO")
        result = json.loads(self.authorized("/v1/projects")[1])
        self.assertEqual((result["state"], result["source"]), ("AVAILABLE", "DEMO"))
        write([{"id": "one", "name": "Shared name"}, {"id": "two", "name": "Shared name"}], stamp(now))
        self.assertEqual([item["id"] for item in json.loads(self.authorized("/v1/projects")[1])["projects"]],
                         ["one", "two"])
        write([{"id": "same", "name": "First"}, {"id": "same", "name": "Second"}], stamp(now))
        self.assertEqual(self.authorized("/v1/projects")[0], 503)

        self.assertEqual(json.loads(self.authorized("/v1/status")[1])["project_source"],
                         "SOURCE_UNAVAILABLE")
        write([{"id": "sample", "name": "Sample"}], stamp(now - 600))
        result = json.loads(self.authorized("/v1/projects")[1])
        self.assertEqual((result["state"], result["partial"], result["stale"]),
                         ("STALE", False, True))
        target.write_text(json.dumps({"source": "LOCAL", "projects": [], "partial": True, "observed_at": stamp(now)}))
        result = json.loads(self.authorized("/v1/projects")[1])
        self.assertEqual((result["state"], result["partial"], result["stale"]),
                         ("PARTIAL", True, False))
        target.write_text(json.dumps({"source": "LOCAL", "projects": [], "partial": True,
                                      "observed_at": stamp(now - 600)}))
        result = json.loads(self.authorized("/v1/projects")[1])
        self.assertEqual((result["state"], result["partial"], result["stale"], result["projects"]),
                         ("STALE", True, True, []))
        self.assertEqual(json.loads(self.authorized("/v1/status")[1])["project_source"], "STALE")
        target.write_text("bad")
        self.assertEqual(self.authorized("/v1/projects")[0], 503)
        code, status, _ = self.authorized("/v1/status")
        self.assertEqual(code, 200)
        self.assertEqual((json.loads(status)["state"], json.loads(status)["project_source"]),
                         ("READY", "SOURCE_UNAVAILABLE"))
        self.assertEqual(self.request("/v1/status")[0], 401)
        self.assertEqual(self.request("/v1/status", token=self.service.token, instance="wrong")[0], 409)
        target.write_bytes(b"\xff")
        self.assertEqual(self.authorized("/v1/projects")[0], 503)
        self.assertEqual(json.loads(self.authorized("/v1/status")[1])["project_source"],
                         "SOURCE_UNAVAILABLE")
        write([{"id": "restored", "name": "Restored"}], stamp(now))
        self.assertEqual(json.loads(self.authorized("/v1/status")[1])["project_source"], "AVAILABLE")
        self.assertEqual(json.loads(self.authorized("/v1/projects")[1])["projects"][0]["id"], "restored")
        raw = target.read_text()
        target.write_text(raw.replace('"source": "LOCAL"', '"source": "DEMO", "source": "LOCAL"', 1))
        self.assertEqual(self.authorized("/v1/projects")[0], 503)
        self.assertEqual(json.loads(self.authorized("/v1/status")[1])["project_source"],
                         "SOURCE_UNAVAILABLE")
        target.write_text(raw.replace('"id": "restored"', '"id": "hidden", "id": "restored"', 1))
        self.assertEqual(self.authorized("/v1/projects")[0], 503)
        target.write_text(raw)
        self.assertEqual(json.loads(self.authorized("/v1/projects")[1])["projects"][0]["id"], "restored")
        target.unlink()
        target.symlink_to(self.root / "token")
        self.assertEqual(self.authorized("/v1/projects")[0], 503)

    def test_running_instance_does_not_follow_replaced_root_path(self):
        from datetime import datetime, timezone
        stamp = datetime.now(timezone.utc).isoformat()
        def catalogue(root, project_id):
            target = root / "projects.json"
            target.write_text(json.dumps({"source": "LOCAL", "observed_at": stamp,
                                          "projects": [{"id": project_id, "name": project_id}]}))
            target.chmod(0o600)
        catalogue(self.root, "one")
        other = Path(self.temp.name) / "two"
        other.mkdir(mode=0o700)
        other_id = initialize(other)
        catalogue(other, "two")
        moved = Path(self.temp.name) / "one-moved"
        self.root.rename(moved)
        self.root.symlink_to(other, target_is_directory=True)
        self.assertEqual(Service(other).instance_id, other_id)
        self.assertEqual(json.loads(self.authorized("/v1/status")[1])["instance_id"], self.instance)
        self.assertEqual(json.loads(self.authorized("/v1/projects")[1])["projects"][0]["id"], "one")

    def test_startup_rejects_root_replaced_between_inspection_and_open(self):
        other = Path(self.temp.name) / "other"
        other.mkdir(mode=0o700)
        initialize(other)
        moved = Path(self.temp.name) / "one-moved"
        actual_open = os.open
        def swap_on_root(path, flags, mode=0o777, *, dir_fd=None):
            if Path(path) == self.root and flags & os.O_DIRECTORY:
                self.root.rename(moved)
                other.rename(self.root)
            return actual_open(path, flags, mode, dir_fd=dir_fd)
        try:
            with patch("workspace_control.service.os.open", side_effect=swap_on_root):
                with self.assertRaisesRegex(ValueError, "changed during open"):
                    Service(self.root)
        finally:
            self.root.rename(other)
            moved.rename(self.root)
        self.assertEqual(Service(self.root).instance_id, self.instance)

    def test_init_rejects_root_replaced_between_inspection_and_open(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir(mode=0o700)
        other = Path(self.temp.name) / "other"
        other.mkdir(mode=0o700)
        moved = Path(self.temp.name) / "fresh-moved"
        actual_open = os.open
        def swap_on_root(path, flags, mode=0o777, *, dir_fd=None):
            if Path(path) == fresh and flags & os.O_DIRECTORY:
                fresh.rename(moved)
                other.rename(fresh)
            return actual_open(path, flags, mode, dir_fd=dir_fd)
        with patch("workspace_control.service.os.open", side_effect=swap_on_root):
            with self.assertRaisesRegex(ValueError, "changed during open"):
                initialize(fresh)
        self.assertFalse((fresh / "instance.json").exists())
        self.assertFalse((moved / "instance.json").exists())
        self.assertFalse((fresh / "initialized").exists())

    def test_remote_listener_requires_exact_interface_and_complete_tls(self):
        for bind in ("0.0.0.0", "::", "localhost", "127.0.0.2", "224.0.0.1"):
            with self.subTest(bind=bind), self.assertRaises(ValueError):
                listener_config(bind)
        with self.assertRaisesRegex(ValueError, "requires TLS"):
            listener_config("192.168.1.134")
        for supplied in ({"server_name": "server.example"},
                         {"cert_file": "/tmp/cert.pem", "key_file": "/tmp/key.pem"}):
            with self.subTest(supplied=supplied), self.assertRaisesRegex(ValueError, "together"):
                listener_config("127.0.0.1", **supplied)
        self.assertIsNone(listener_config("127.0.0.1"))

    def test_https_verified_certificate_host_origin_and_pinned_auth(self):
        cert = Path(self.temp.name) / "tls-cert.pem"
        key = Path(self.temp.name) / "tls-key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", str(key), "-out", str(cert), "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        key.chmod(0o600)
        context = listener_config("127.0.0.1", "localhost", str(cert), str(key))
        for bad_name in ("bad/name", "bad..name", "https://localhost"):
            with self.subTest(bad_name=bad_name), self.assertRaises(ValueError):
                listener_config("127.0.0.1", bad_name, str(cert), str(key))
        key.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "private key"):
            listener_config("127.0.0.1", "localhost", str(cert), str(key))
        key.chmod(0o600)
        trusted = ssl.create_default_context(cafile=str(cert))
        secure = ThreadingHTTPServer(("127.0.0.1", 0),
                                     handler_for(self.service, public_host="localhost", scheme="https"))
        secure.socket = context.wrap_socket(secure.socket, server_side=True,
                                            do_handshake_on_connect=False)
        thread = threading.Thread(target=secure.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(secure.server_close)
        self.addCleanup(secure.shutdown)

        def request(host, origin=None, token=None, pin=None, client_context=trusted):
            connection = http.client.HTTPSConnection("localhost", secure.server_port,
                                                     timeout=2, context=client_context)
            try:
                connection.putrequest("GET", "/v1/status", skip_host=True)
                connection.putheader("Host", host)
                if origin is not None:
                    connection.putheader("Origin", origin)
                if token is not None:
                    connection.putheader("Authorization", "Bearer " + token)
                if pin is not None:
                    connection.putheader("X-Workspace-Instance", pin)
                connection.endheaders()
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        host = f"localhost:{secure.server_port}"
        self.assertEqual(request(host, f"https://{host}", self.service.token, self.instance)[0], 200)
        connection = http.client.HTTPSConnection("localhost", secure.server_port,
                                                 timeout=2, context=trusted)
        try:
            connection.request("GET", "/v1/openapi.json", headers={
                "Authorization": "Bearer " + self.service.token,
                "X-Workspace-Instance": self.instance,
            })
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(json.loads(response.read())["servers"],
                             [{"url": f"https://{host}"}])
        finally:
            connection.close()
        self.assertEqual(request("evil.example:" + str(secure.server_port),
                                 token=self.service.token, pin=self.instance),
                         (403, {"error": "HOST_DENIED"}))
        self.assertEqual(request(host, f"http://{host}", self.service.token, self.instance),
                         (403, {"error": "ORIGIN_DENIED"}))
        self.assertEqual(request(host, token="wrong", pin=self.instance),
                         (401, {"error": "UNAUTHORIZED"}))
        self.assertEqual(request(host, token=self.service.token, pin="wrong"),
                         (409, {"error": "WRONG_INSTANCE"}))
        with self.assertRaises(ssl.SSLCertVerificationError):
            request(host, client_context=ssl.create_default_context())
        with socket.create_connection(("127.0.0.1", secure.server_port), timeout=2) as raw:
            with self.assertRaises(ssl.SSLCertVerificationError):
                trusted.wrap_socket(raw, server_hostname="other.example")

    def test_serve_wraps_explicit_tls_listener(self):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        with patch("workspace_control.http.listener_config", return_value=context), \
             patch("workspace_control.http.ThreadingHTTPServer") as server_class, \
             patch.object(context, "wrap_socket", return_value=object()) as wrap:
            original_socket = object()
            server_class.return_value.socket = original_socket
            serve(self.root, 0, bind="192.0.2.10", server_name="server.example",
                  cert_file="/absolute/cert", key_file="/absolute/key")
            server_class.assert_called_once()
            self.assertEqual(server_class.call_args.args[0], ("192.0.2.10", 0))
            wrap.assert_called_once_with(original_socket, server_side=True,
                                         do_handshake_on_connect=False)
            server_class.return_value.serve_forever.assert_called_once_with(poll_interval=0.1)

    def test_serve_lock_uses_opened_root_when_path_changes_before_lock(self):
        other = Path(self.temp.name) / "two"
        other.mkdir(mode=0o700)
        initialize(other)
        moved = Path(self.temp.name) / "one-moved"
        actual_service = Service
        def swap_after_open(root):
            service = actual_service(root)
            self.root.rename(moved)
            self.root.symlink_to(other, target_is_directory=True)
            return service
        with patch("workspace_control.http.Service", side_effect=swap_after_open), \
             patch("workspace_control.http.ThreadingHTTPServer") as server_class:
            serve(self.root, 0)
            server_class.return_value.serve_forever.assert_called_once_with(poll_interval=0.1)
            self.assertIs(server_class.return_value.daemon_threads, False)
        self.assertTrue((moved / "server.lock").is_file())
        self.assertFalse((other / "server.lock").exists())

    def test_closed_instance_never_reads_relative_catalogue(self):
        from datetime import datetime, timezone
        with tempfile.TemporaryDirectory() as cwd:
            target = Path(cwd) / "projects.json"
            target.write_text(json.dumps({"source": "LOCAL",
                                          "observed_at": datetime.now(timezone.utc).isoformat(),
                                          "projects": [{"id": "wrong", "name": "Wrong"}]}))
            target.chmod(0o600)
            service = Service(self.root)
            service.close()
            before = Path.cwd()
            try:
                os.chdir(cwd)
                with self.assertRaisesRegex(ValueError, "closed"):
                    service.projects()
            finally:
                os.chdir(before)

    def test_close_waits_for_in_flight_catalogue_open(self):
        from workspace_control.service import _private_json
        service = Service(self.root)
        entered, release, closed = threading.Event(), threading.Event(), threading.Event()
        outcomes = []
        def delayed_read(path, *, dir_fd=None):
            if path == "projects.json":
                entered.set()
                release.wait(timeout=2)
            return _private_json(path, dir_fd=dir_fd)
        def read():
            outcomes.append(service.projects()["state"])
        def close():
            service.close()
            closed.set()
        with patch("workspace_control.service._private_json", side_effect=delayed_read):
            reader = threading.Thread(target=read)
            closer = threading.Thread(target=close)
            reader.start()
            try:
                self.assertTrue(entered.wait(timeout=2))
                closer.start()
                self.assertFalse(closed.wait(timeout=0.05))
            finally:
                release.set()
                reader.join(timeout=2)
                if closer.ident is not None:
                    closer.join(timeout=2)
        self.assertEqual(outcomes, ["UNCONFIGURED"])
        self.assertTrue(closed.is_set())

    def test_catalogue_observed_at_schema_preserves_accepted_iso_week_spelling(self):
        from datetime import datetime, timezone
        from workspace_control.service import _observed_datetime
        now = datetime.now(timezone.utc)
        week = now.isocalendar()
        target = self.root / "projects.json"
        spellings = (f"{week.year}-W{week.week:02d}-{week.weekday}T{now:%H:%M:%S}+00:00",
                     f"{week.year}-W{week.week:02d}-{week.weekday}T{now:%H:%M}+00:00",
                     f"{week.year}-W{week.week:02d}-{week.weekday}T{now:%H:%M}+0000",
                     now.strftime("%Y%m%dT%H%M%S+0000"),
                     now.strftime("%Y%m%dT%H%M+0000"),
                     now.strftime("%Y%m%dT%H:%M+00:00"),
                     now.strftime("%Y-%m-%dT%H:%M:%S+00"))
        for observed_at in spellings:
            with self.subTest(observed_at=observed_at):
                target.write_text(json.dumps({"source": "LOCAL", "observed_at": observed_at,
                                              "projects": []}))
                target.chmod(0o600)
                code, body, _ = self.authorized("/v1/projects")
                self.assertEqual(code, 200)
                self.assertEqual(json.loads(body)["observed_at"], observed_at)
                expected = now.replace(second=0, microsecond=0) if observed_at in (
                    spellings[1], spellings[2], spellings[4], spellings[5]) else now.replace(microsecond=0)
                self.assertEqual(_observed_datetime(observed_at), expected)
        for observed_at in (f"{week.year}-W54-1T{now:%H:%M:%S}+00:00",
                            now.strftime("%Y-%m-%dT%H:%M:%S+25"),
                            now.strftime("%Y%m%dT%H%M%S+0000")[0:7] +
                            now.strftime("T%H%M%S+0000")):
            with self.subTest(invalid=observed_at):
                target.write_text(json.dumps({"source": "LOCAL", "observed_at": observed_at,
                                              "projects": []}))
                target.chmod(0o600)
                self.assertEqual(self.authorized("/v1/projects")[0], 503)
        api = json.loads(self.authorized("/v1/openapi.json")[1])
        schema = api["components"]["schemas"]["Projects"]["properties"]["observed_at"]
        self.assertEqual(schema["type"], "string")
        self.assertNotIn("format", schema)

    def test_cli_projects_matches_service_and_fails_closed(self):
        from datetime import datetime, timedelta, timezone
        target = self.root / "projects.json"
        def cli_read():
            stdout, stderr = io.StringIO(), io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                code = main(["--root", str(self.root), "projects"])
            return code, stdout.getvalue(), stderr.getvalue()
        code, output, error = cli_read()
        self.assertEqual((code, error), (0, ""))
        self.assertEqual(json.loads(output), json.loads(self.authorized("/v1/projects")[1]))
        now = datetime.now(timezone.utc)
        for value, expected in (({"source": "LOCAL", "observed_at": now.isoformat(),
                                 "projects": []}, "EMPTY"),
                                ({"source": "DEMO", "observed_at": now.isoformat(),
                                  "projects": [{"id": "one", "name": "Sample"}]}, "AVAILABLE"),
                                ({"source": "LOCAL", "observed_at": now.isoformat(),
                                  "projects": [], "partial": True}, "PARTIAL"),
                                ({"source": "LOCAL", "observed_at":
                                  (now - timedelta(minutes=10)).isoformat(),
                                  "projects": [], "partial": True}, "STALE")):
            with self.subTest(state=expected):
                target.write_text(json.dumps(value))
                target.chmod(0o600)
                code, output, error = cli_read()
                self.assertEqual((code, error), (0, ""))
                self.assertEqual(json.loads(output)["state"], expected)
                self.assertEqual(json.loads(output), json.loads(self.authorized("/v1/projects")[1]))
        invalid = {"source": "LOCAL", "observed_at": now.isoformat(),
                   "projects": [], "peer_status": "QUALIFIED"}
        target.write_text(json.dumps(invalid))
        before = target.read_bytes()
        code, output, error = cli_read()
        self.assertEqual((code, output), (2, ""))
        self.assertIn("workspace-server:", error)
        self.assertNotIn(self.service.token, error)
        self.assertEqual(target.read_bytes(), before)
        self.assertEqual(self.authorized("/v1/projects")[0], 503)
        target.write_bytes(b"\xff")
        code, output, error = cli_read()
        self.assertEqual((code, output), (2, ""))
        self.assertTrue(error.startswith("workspace-server:"))
        self.assertNotIn("Traceback", error)
        self.assertNotIn(self.service.token, error)
        self.assertEqual(target.read_bytes(), b"\xff")
        self.assertEqual(self.authorized("/v1/projects")[0], 503)

    def test_restart_isolation_and_cli(self):
        self.assertEqual(main(["--root", str(self.root), "status"]), 0)
        self.assertEqual(Service(self.root).instance_id, self.instance)
        second = Path(self.temp.name) / "two"
        second.mkdir(mode=0o700)
        other = initialize(second)
        self.assertNotEqual(other, self.instance)
        self.assertNotEqual(Service(second).token, self.service.token)
        self.assertEqual(self.request("/v1/status", token=Service(second).token, instance=self.instance)[0], 401)
        self.assertEqual(main(["--root", str(second), "init"]), 2)

    def test_init_keeps_identity_and_token_in_opened_root_after_path_swap(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir(mode=0o700)
        other = Path(self.temp.name) / "other"
        other.mkdir(mode=0o700)
        other_id = initialize(other)
        other_token = (other / "token").read_bytes()
        moved = Path(self.temp.name) / "fresh-moved"
        actual_open = os.open
        def swap_on_token(path, flags, mode=0o777, *, dir_fd=None):
            if path == "token" and flags & os.O_CREAT:
                fresh.rename(moved)
                fresh.symlink_to(other, target_is_directory=True)
            return actual_open(path, flags, mode, dir_fd=dir_fd)
        with patch("workspace_control.service.os.open", side_effect=swap_on_token):
            created = initialize(fresh)
        self.assertEqual(Service(moved).instance_id, created)
        self.assertTrue((moved / "token").is_file())
        self.assertEqual((moved / "initialized").read_text(), created + "\n")
        self.assertEqual((moved / "initialized").stat().st_mode & 0o777, 0o600)
        self.assertEqual(Service(other).instance_id, other_id)
        self.assertEqual((other / "token").read_bytes(), other_token)

    def test_init_failure_preserves_concurrent_replacement_in_opened_root(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir(mode=0o700)
        other = Path(self.temp.name) / "other"
        other.mkdir(mode=0o700)
        other_id = initialize(other)
        other_token = (other / "token").read_bytes()
        moved = Path(self.temp.name) / "fresh-moved"
        actual_fsync = os.fsync
        calls = 0
        def fail_second_sync(descriptor):
            nonlocal calls
            calls += 1
            if calls == 4:
                fresh.rename(moved)
                fresh.symlink_to(other, target_is_directory=True)
                (moved / "instance.json").rename(moved / "original-instance.json")
                (moved / "instance.json").write_bytes(b"replacement")
                raise OSError("sync failure")
            return actual_fsync(descriptor)
        with patch("workspace_control.service.os.fsync", side_effect=fail_second_sync):
            with self.assertRaisesRegex(OSError, "sync failure"):
                initialize(fresh)
        self.assertEqual((moved / "instance.json").read_bytes(), b"replacement")
        self.assertTrue((moved / "token").is_file())
        self.assertEqual((moved / "initialized").stat().st_mode & 0o777, 0)
        self.assertRaises(ValueError, initialize, moved)
        self.assertRaises(ValueError, Service, moved)
        self.assertEqual(Service(other).instance_id, other_id)
        self.assertEqual((other / "token").read_bytes(), other_token)

    def test_final_sync_failure_cannot_publish_new_instance(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir(mode=0o700)
        actual_fsync = os.fsync
        calls = 0
        def fail_token_sync(descriptor):
            nonlocal calls
            calls += 1
            if calls == 4:
                raise OSError("token sync failure")
            return actual_fsync(descriptor)
        with patch("workspace_control.service.os.fsync", side_effect=fail_token_sync):
            with self.assertRaisesRegex(OSError, "token sync failure"):
                initialize(fresh)
        self.assertTrue((fresh / "instance.json").is_file())
        self.assertTrue((fresh / "token").is_file())
        self.assertEqual((fresh / "initialized").stat().st_mode & 0o777, 0)
        self.assertRaisesRegex(ValueError, "incomplete", Service, fresh)
        (fresh / "initialized").unlink()
        self.assertRaisesRegex(ValueError, "incomplete", Service, fresh)
        self.assertRaises(ValueError, initialize, fresh)

    def test_completed_new_identity_requires_marker_but_legacy_identity_loads(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir(mode=0o700)
        created = initialize(fresh)
        (fresh / "initialized").unlink()
        self.assertRaisesRegex(ValueError, "incomplete", Service, fresh)
        identity = fresh / "instance.json"
        legacy = json.loads(identity.read_text())
        legacy.pop("init_protocol")
        identity.write_text(json.dumps(legacy))
        self.assertEqual(Service(fresh).instance_id, created)

    def test_inspect_reports_private_init_state_without_secret_or_writes(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir(mode=0o700)
        empty = {"identity": False, "token": False, "marker": False}
        complete = {"identity": True, "token": True, "marker": True}
        legacy_files = {"identity": True, "token": True, "marker": False}
        self.assertEqual(inspect(fresh), {"state": "UNINITIALIZED", "files": empty})
        self.assertEqual(inspect(self.root), {"state": "READY", "files": complete,
                                              "instance_id": self.instance})
        token = (self.root / "token").read_text().strip()
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--root", str(self.root), "inspect"]), 0)
        self.assertEqual(json.loads(output.getvalue()), {"state": "READY", "files": complete,
                                                         "instance_id": self.instance})
        self.assertNotIn(token, output.getvalue())
        (fresh / "initialized").write_text(self.instance + "\n")
        (fresh / "initialized").chmod(0)
        self.assertEqual(inspect(fresh), {"state": "INCOMPLETE",
                                          "files": {"identity": False, "token": False, "marker": True}})
        self.assertEqual((fresh / "initialized").stat().st_mode & 0o777, 0)
        self.assertRaises(ValueError, initialize, fresh)
        (fresh / "initialized").unlink()
        created = initialize(fresh)
        self.assertEqual(inspect(fresh), {"state": "READY", "files": complete, "instance_id": created})
        (fresh / "initialized").unlink()
        self.assertEqual(inspect(fresh), {"state": "INCOMPLETE", "files": legacy_files})
        identity = fresh / "instance.json"
        legacy = json.loads(identity.read_text())
        legacy.pop("init_protocol")
        identity.write_text(json.dumps(legacy))
        self.assertEqual(inspect(fresh), {"state": "READY", "files": legacy_files,
                                          "instance_id": created})
        (fresh / "token").chmod(0o644)
        self.assertEqual(inspect(fresh), {"state": "INCOMPLETE", "files": legacy_files})
        fresh.chmod(0o755)
        self.assertRaises(ValueError, inspect, fresh)

    def test_inspect_ready_flags_follow_validated_state_after_stale_presence_scan(self):
        real_stat = os.stat
        missed = {"instance.json", "token"}

        def stale_first_scan(path, *args, **kwargs):
            if path in missed and kwargs.get("dir_fd") is not None:
                missed.remove(path)
                raise FileNotFoundError(path)
            return real_stat(path, *args, **kwargs)

        with patch("workspace_control.service.os.stat", side_effect=stale_first_scan):
            result = inspect(self.root)
        self.assertEqual(result, {"state": "READY", "instance_id": self.instance,
                                  "files": {"identity": True, "token": True, "marker": True}})
        self.assertFalse(missed)

    def test_marker_publication_failure_cannot_start_instance(self):
        fresh = Path(self.temp.name) / "fresh"
        fresh.mkdir(mode=0o700)
        with patch("workspace_control.service.os.fchmod", side_effect=OSError("publish failure")):
            with self.assertRaisesRegex(OSError, "publish failure"):
                initialize(fresh)
        self.assertEqual((fresh / "initialized").stat().st_mode & 0o777, 0)
        self.assertRaisesRegex(ValueError, "incomplete", Service, fresh)

    def test_bad_roots_and_private_files(self):
        self.assertEqual(main(["--root", "relative", "init"]), 2)
        self.root.chmod(0o755)
        self.assertRaises(ValueError, Service, self.root)
        self.root.chmod(0o700)
        token = self.root / "token"
        token.chmod(0o644)
        self.assertRaises(ValueError, Service, self.root)

    def test_private_file_read_is_bound_to_one_descriptor(self):
        source = self.root / "source"
        other = self.root / "other"
        source.write_text("original")
        other.write_text("replacement")
        source.chmod(0o600)
        other.chmod(0o600)
        real_open = os.open

        def replace_after_open(path, flags, mode=0o777, *, dir_fd=None):
            descriptor = real_open(path, flags, mode, dir_fd=dir_fd)
            source.unlink()
            source.symlink_to(other)
            return descriptor

        with patch("workspace_control.service.os.open", side_effect=replace_after_open):
            self.assertEqual(_regular_private(source), "original")
        self.assertRaises(OSError, _regular_private, source)

    def test_nonregular_private_file_does_not_block(self):
        fifo = self.root / "fifo"
        os.mkfifo(fifo, 0o600)
        self.assertRaises(ValueError, _regular_private, fifo)

    def test_invalid_instance_state_fails_closed_without_reset(self):
        identity = self.root / "instance.json"
        original = identity.read_text()
        secret = (self.root / "token").read_text()
        valid = json.loads(original)
        duplicate_id = original.replace('"instance_id":', '"instance_id": "' + "0" * 32 + '", "instance_id":', 1)
        cases = ["[]", "null", "{not-json", json.dumps({"instance_id": self.instance}),
                 json.dumps(dict(valid, unexpected="accepted")),
                 json.dumps(dict(valid, instance_id="z" * 32)),
                 json.dumps(dict(valid, instance_id="A" * 32)),
                 json.dumps(dict(valid, created_at="not-a-date")),
                 json.dumps(dict(valid, created_at="2026-10-01T00:00:00")), duplicate_id]
        for raw in cases:
            with self.subTest(raw=raw):
                identity.write_text(raw)
                self.assertRaises(ValueError, Service, self.root)
                self.assertEqual(main(["--root", str(self.root), "status"]), 2)
        identity.write_text(original)
        restored = Service(self.root)
        self.assertEqual(restored.instance_id, self.instance)
        self.assertEqual((self.root / "token").read_text(), secret)

    def test_deep_private_json_fails_as_invalid_source(self):
        deep = "[" * 200_000 + "0" + "]" * 200_000
        identity = self.root / "instance.json"
        original = identity.read_text()
        identity.write_text(deep)
        with redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(main(["--root", str(self.root), "status"]), 2)
        self.assertIn("invalid private JSON nesting", errors.getvalue())
        identity.write_text(original)
        catalogue = self.root / "projects.json"
        catalogue.write_text(deep)
        catalogue.chmod(0o600)
        self.assertEqual(json.loads(self.authorized("/v1/status")[1])["project_source"], "SOURCE_UNAVAILABLE")
        self.assertEqual(self.authorized("/v1/projects")[0], 503)

    def test_invalid_token_state_fails_closed_without_disclosure(self):
        token_file = self.root / "token"
        original = token_file.read_text()
        cases = [original.rstrip("\n"), original + "\n", " " + original,
                 original[:-1] + " \n", original[:-2] + "!\n",
                 original[:-2] + "B\n", "\u00e9" * 43 + "\n"]
        for raw in cases:
            with self.subTest(length=len(raw)):
                token_file.write_text(raw)
                self.assertRaises(ValueError, Service, self.root)
                stderr = io.StringIO()
                with redirect_stderr(stderr):
                    self.assertEqual(main(["--root", str(self.root), "status"]), 2)
                self.assertNotIn(original.strip(), stderr.getvalue())
        token_file.write_text(original)
        restored = Service(self.root)
        self.assertEqual(restored.instance_id, self.instance)
        self.assertEqual(restored.token + "\n", original)

    def test_init_race_preserves_other_initializer_files(self):
        fresh = Path(self.temp.name) / "racing"
        fresh.mkdir(mode=0o700)
        real_open = os.open
        def race_at_identity(path, flags, mode=0o777, *, dir_fd=None):
            if path == "instance.json":
                fd = real_open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=dir_fd)
                with os.fdopen(fd, "w") as stream:
                    stream.write("winner")
                raise FileExistsError("other initializer won")
            return real_open(path, flags, mode, dir_fd=dir_fd)
        with patch("workspace_control.service.os.open", side_effect=race_at_identity):
            self.assertRaises(FileExistsError, initialize, fresh)
        self.assertEqual((fresh / "instance.json").read_text(), "winner")
        self.assertEqual((fresh / "initialized").stat().st_mode & 0o777, 0)
        second = Path(self.temp.name) / "racing-two"
        second.mkdir(mode=0o700)
        def race_at_token(path, flags, mode=0o777, *, dir_fd=None):
            if path == "token":
                fd = real_open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=dir_fd)
                with os.fdopen(fd, "w") as stream:
                    stream.write("winner token")
                raise FileExistsError("other initializer won")
            return real_open(path, flags, mode, dir_fd=dir_fd)
        with patch("workspace_control.service.os.open", side_effect=race_at_token):
            self.assertRaises(FileExistsError, initialize, second)
        self.assertTrue((second / "instance.json").is_file())
        self.assertEqual((second / "token").read_text(), "winner token")
        self.assertEqual((second / "initialized").stat().st_mode & 0o777, 0)

    def test_cli_read_commands_close_private_root_on_success_and_error(self):
        real_close = Service.close
        for command in ("status", "projects", "capabilities", "openapi"):
            with self.subTest(command=command), patch.object(
                    Service, "close", autospec=True, side_effect=real_close) as closed:
                with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                    self.assertEqual(main(["--root", str(self.root), command]), 0)
                self.assertEqual(closed.call_count, 1)
        catalogue = self.root / "projects.json"
        catalogue.write_text("{invalid")
        catalogue.chmod(0o600)
        with patch.object(Service, "close", autospec=True, side_effect=real_close) as closed:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(main(["--root", str(self.root), "projects"]), 2)
            self.assertEqual(closed.call_count, 1)

    def test_cli_invalid_utf8_instance_secret_exits_without_traceback(self):
        fresh = Path(self.temp.name) / "invalid-secret"
        fresh.mkdir(mode=0o700)
        initialize(fresh)
        (fresh / "token").write_bytes(b"\xff")
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = main(["--root", str(fresh), "status"])
        self.assertEqual((code, stdout.getvalue()), (2, ""))
        self.assertTrue(stderr.getvalue().startswith("workspace-server:"))
        self.assertNotIn("Traceback", stderr.getvalue())
        self.assertEqual((fresh / "token").read_bytes(), b"\xff")

    def test_cli_modes_and_server_lock(self):
        self.assertEqual(main(["--root", str(self.root), "serve", "--port", "0"]), 2)
        with patch("workspace_control.cli.serve") as mock_serve:
            self.assertEqual(main(["--root", str(self.root), "serve", "--port", "8767"]), 0)
            mock_serve.assert_called_once_with(str(self.root), 8767)
        with patch("workspace_control.cli.serve") as mock_serve:
            self.assertEqual(main(["--root", str(self.root), "serve", "--port", "8767",
                                   "--bind", "192.0.2.10", "--tls-server-name", "server.example",
                                   "--tls-cert", "/absolute/cert", "--tls-key", "/absolute/key"]), 0)
            mock_serve.assert_called_once_with(str(self.root), 8767, bind="192.0.2.10",
                                               server_name="server.example",
                                               cert_file="/absolute/cert", key_file="/absolute/key")
        with patch("workspace_control.cli.webbrowser.open", return_value=True) as open_browser:
            self.assertEqual(client_main(["--url", "http://127.0.0.1:8767"]), 0)
            open_browser.assert_called_once_with("http://127.0.0.1:8767/")
        with patch("workspace_control.cli.webbrowser.open", return_value=True) as open_browser:
            self.assertEqual(client_main(["--url", "http://localhost:8767/"]), 0)
            open_browser.assert_called_once_with("http://localhost:8767/")
        with patch("workspace_control.cli.webbrowser.open", return_value=False):
            self.assertEqual(client_main(["--url", "http://127.0.0.1:8767"]), 2)
        with patch("workspace_control.cli.webbrowser.open", side_effect=OSError("unavailable")):
            self.assertEqual(client_main(["--url", "http://127.0.0.1:8767"]), 2)
        for url in ("https://127.0.0.1:8767", "http://127.0.0.1:8767@evil.example",
                    "http://127.0.0.1:bad", "http://localhost:8767/v1/status",
                    "http://127.0.0.1:8767?", "http://127.0.0.1:8767#",
                    "http://localhost:8767/?", "http://localhost:8767/#",
                    "http://[::1:8767", "http://[x]:8767", "http://LOCALHOST:8767",
                    "http://127.0.0.1:08767", "http://127.0.0.1:0",
                    "http://localhost:65536"):
            with self.subTest(url=url), patch("workspace_control.cli.webbrowser.open") as open_browser:
                with self.assertRaises(SystemExit):
                    client_main(["--url", url])
                open_browser.assert_not_called()
        lock = self.root / "server.lock"
        lock.symlink_to(self.root / "token")
        self.assertRaises(OSError, serve, self.root, 0)
        lock.unlink()

    def test_rejected_catalogues(self):
        target = self.root / "projects.json"
        cases = [[], {"source": "PEER", "projects": [], "observed_at": "2026-10-01T00:00:00Z"},
                 {"source": "LOCAL", "projects": [], "observed_at": "2026-10-01T00:00:00Z",
                  "peer_status": "QUALIFIED"},
                 {"source": "LOCAL", "projects": [], "observed_at": "2026-10-01T00:00:00Z",
                  "parital": True},
                 {"source": "LOCAL", "projects": []},
                 {"source": "LOCAL", "projects": "wrong", "observed_at": "2026-10-01T00:00:00Z"},
                 {"source": "LOCAL", "projects": [{"id": "x"}], "observed_at": "2026-10-01T00:00:00Z"},
                 {"source": "LOCAL", "projects": [{"id": "", "name": "x"}], "observed_at": "2026-10-01T00:00:00Z"},
                 {"source": "LOCAL", "projects": [], "observed_at": "bad"},
                 {"source": "LOCAL", "projects": [], "observed_at": "2026-10-01T00:00:00"},
                 {"source": "LOCAL", "projects": [], "observed_at": "2999-01-01T00:00:00Z"}]
        cases.append({"source": "LOCAL", "projects": [], "partial": "yes", "observed_at": "2026-10-01T00:00:00Z"})
        cases.extend(({"source": "LOCAL", "observed_at": "2026-10-01T00:00:00Z",
                       "projects": [{"id": "x" * 121, "name": "Name"}]},
                      {"source": "LOCAL", "observed_at": "2026-10-01T00:00:00Z",
                       "projects": [{"id": "id", "name": "N" * 121}]},
                      {"source": "LOCAL", "observed_at": "2026-10-01T00:00:00Z",
                       "projects": [{"id": str(i), "name": "Name"} for i in range(101)]}))
        for value in cases:
            target.write_text(json.dumps(value))
            target.chmod(0o600)
            self.assertEqual(self.authorized("/v1/projects")[0], 503)


class ForgeReadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "instance"
        self.root.mkdir(mode=0o700)
        self.instance = initialize(self.root)
        self.service = Service(self.root)
        self.addCleanup(self.service.close)
        self.own = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.service))
        self.own_thread = threading.Thread(target=self.own.serve_forever, daemon=True)
        self.own_thread.start()
        self.addCleanup(self.own.server_close)
        self.addCleanup(self.own.shutdown)
        self.forge_instance = "forge-instance-1234567890"
        self.forge_token = "f" * 40
        self.scope = {"contract_version": "forge-workspace-status-read/v1",
                      "instance_id": self.forge_instance, "repository_id": "forge"}
        self.forge_calls = []
        self.forge_status = 200
        self.forge_document = {
            "api_version": "1", "contract_version": "1.0", "read_only": True,
            "instance": {"instance_id": self.forge_instance, "product_version": "2.7.58"},
            "workspace_read_scope": self.scope,
        }
        self.status_document = {
            "api_version": "1", "read_only": True, "availability": "AVAILABLE",
            "freshness": "CURRENT", "source_observed_at": "2026-10-02T12:00:00Z",
            "runtime": {"instance_id": self.forge_instance, "product_version": "2.7.58"},
            "workspace_read_scope": self.scope,
        }
        test = self

        class FakeForge(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                return

            def do_GET(self):
                test.forge_calls.append((self.path, self.headers.get("Authorization")))
                if self.headers.get("Authorization") != "Bearer " + test.forge_token:
                    self.send_response(401)
                    self.end_headers()
                    return
                document = test.forge_document if self.path == "/v1/instance" else test.status_document
                payload = json.dumps(document).encode()
                self.send_response(test.forge_status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        self.forge = ThreadingHTTPServer(("127.0.0.1", 0), FakeForge)
        self.forge_thread = threading.Thread(target=self.forge.serve_forever, daemon=True)
        self.forge_thread.start()
        self.addCleanup(self.forge.server_close)
        self.addCleanup(self.forge.shutdown)

    def configure(self, **changes):
        binding = {"schema_version": 1, "revision": 1,
                   "endpoint": f"http://127.0.0.1:{self.forge.server_port}/",
                   "instance_id": self.forge_instance, "repository_id": "forge",
                   "token": self.forge_token}
        binding.update(changes)
        path = self.root / "forge-read-binding.json"
        path.write_text(json.dumps(binding))
        path.chmod(0o600)

    def read(self):
        request = Request(f"http://127.0.0.1:{self.own.server_port}/v1/forge/status",
                          headers={"Authorization": "Bearer " + self.service.token,
                                   "X-Workspace-Instance": self.instance})
        with urlopen(request, timeout=4) as response:
            self.assertEqual(response.status, 200)
            return json.loads(response.read())

    def test_unconfigured_partial_and_private_binding(self):
        self.assertEqual(self.read()["state"], "UNCONFIGURED")
        self.assertEqual(self.forge_calls, [])
        self.configure()
        self.assertEqual(self.read()["state"], "OBSERVED")
        self.configure(token="short")
        self.assertEqual(self.read()["state"], "INVALID_CONFIGURATION")
        self.configure()
        (self.root / "forge-read-binding.json").chmod(0o644)
        self.assertEqual(self.read()["state"], "INVALID_CONFIGURATION")
        self.configure(schema_version=True)
        self.assertEqual(self.read()["state"], "INVALID_CONFIGURATION")

    def test_selected_reads_and_honest_freshness(self):
        self.configure()
        first = self.read()
        self.assertEqual(first["state"], "OBSERVED")
        self.assertEqual((first["availability"], first["freshness"]), ("AVAILABLE", "CURRENT"))
        self.assertEqual((first["instance_id"], first["repository_id"]), (self.forge_instance, "forge"))
        self.assertEqual(first["source_observed_at"], "2026-10-02T12:00:00Z")
        self.assertIsNotNone(first["retrieved_at"])
        self.assertEqual(self.forge_calls, [("/v1/instance", "Bearer " + self.forge_token),
                                            ("/v1/status", "Bearer " + self.forge_token)])
        self.status_document["freshness"] = "STALE"
        self.assertEqual(self.read()["freshness"], "STALE")
        self.status_document["freshness"] = "UNKNOWN"
        self.status_document["source_observed_at"] = None
        self.assertEqual(self.read()["freshness"], "UNKNOWN")
        self.status_document["availability"] = "UNAVAILABLE"
        self.status_document["freshness"] = "UNAVAILABLE"
        self.assertEqual(self.read()["availability"], "UNAVAILABLE")

    def test_fail_closed_on_identity_auth_and_schema(self):
        self.configure()
        scope = self.forge_document.pop("workspace_read_scope")
        self.assertEqual(self.read()["state"], "READ_SCOPE_UNVERIFIED")
        self.forge_document["workspace_read_scope"] = scope
        self.status_document["workspace_read_scope"] = {**self.scope, "repository_id": "foreign"}
        self.assertEqual(self.read()["state"], "READ_SCOPE_UNVERIFIED")
        self.status_document["workspace_read_scope"] = self.scope
        self.forge_document["instance"]["instance_id"] = "foreign-instance"
        self.assertEqual(self.read()["state"], "WRONG_INSTANCE")
        self.forge_document["instance"]["instance_id"] = self.forge_instance
        self.status_document["runtime"]["instance_id"] = "foreign-instance"
        self.assertEqual(self.read()["state"], "WRONG_INSTANCE")
        self.status_document["runtime"]["instance_id"] = self.forge_instance
        self.status_document["runtime"]["product_version"] = "2.7.59"
        self.assertEqual(self.read()["state"], "INVALID_RESPONSE")
        self.status_document["runtime"]["product_version"] = "2.7.58"
        self.forge_token = "g" * 40
        self.assertEqual(self.read()["state"], "UNAUTHORIZED")
        self.forge_token = "f" * 40
        self.forge_status = 503
        self.assertEqual(self.read()["state"], "UNAVAILABLE")
        self.forge_status = 200
        self.status_document["freshness"] = "BOGUS"
        self.assertEqual(self.read()["state"], "INVALID_RESPONSE")

    def test_remote_plaintext_and_invalid_endpoint_rejected(self):
        for value in ("http://example.test:8765/", "https://user:pass@example.test/",
                      "https://example.test/path", "https://example.test:0/",
                      "https://example.test/?x=1", "https://0.0.0.0/"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                _endpoint(value)
        self.configure(endpoint="http://example.test:8765/")
        self.assertEqual(self.read()["state"], "INVALID_CONFIGURATION")
        self.assertEqual(self.forge_calls, [])

    def test_redirect_timeout_and_tls_trust_remain_non_observed(self):
        self.configure()
        self.forge_status = 302
        self.assertEqual(self.read()["state"], "INVALID_RESPONSE")
        self.forge_status = 200

        connection = Mock()
        connection.request.side_effect = TimeoutError
        with patch.object(forge_peer.http.client, "HTTPConnection", return_value=connection):
            with self.assertRaises(forge_peer.PeerReadError) as failure:
                forge_peer._read("http", "127.0.0.1", self.forge.server_port,
                                 "/v1/instance", self.forge_token)
        self.assertEqual(failure.exception.state, "UNAVAILABLE")
        self.assertTrue(connection.close.called)

        self.configure(endpoint="https://forge.example.test/")
        connection = Mock()
        connection.request.side_effect = ssl.SSLCertVerificationError("untrusted test certificate")
        with patch.object(forge_peer.http.client, "HTTPSConnection", return_value=connection):
            with self.assertRaises(forge_peer.PeerReadError) as failure:
                forge_peer._read("https", "forge.example.test", 443,
                                 "/v1/instance", self.forge_token)
        self.assertEqual(failure.exception.state, "TLS_UNTRUSTED")
        self.assertTrue(connection.close.called)

    def test_local_admin_provisions_and_rotates_private_scoped_credential(self):
        source = Path(self.temp.name) / "issued-token"
        source.write_text(self.forge_token + "\n")
        source.chmod(0o600)
        arguments = ["--root", str(self.root), "forge-read-configure", "--endpoint",
                     f"http://127.0.0.1:{self.forge.server_port}/", "--instance-id",
                     self.forge_instance, "--repository-id", "forge", "--token-file", str(source)]

        def administer(extra=()):
            output, error = io.StringIO(), io.StringIO()
            with redirect_stdout(output), redirect_stderr(error):
                code = main(arguments + list(extra))
            return code, output.getvalue(), error.getvalue()

        code, output, error = administer()
        self.assertEqual((code, error), (0, ""))
        self.assertNotIn(self.forge_token, output)
        for name in ("forge-read-binding.json", ".forge-read-config.lock"):
            self.assertEqual((self.root / name).stat().st_mode & 0o777, 0o600)
        self.assertFalse((self.root / "forge-read-token").exists())
        self.assertEqual(self.read()["state"], "OBSERVED")
        self.assertEqual(administer()[0], 2)
        self.assertEqual(administer(("--expected-current-instance", self.forge_instance,
                                     "--expected-current-repository", "foreign",
                                     "--expected-current-revision", "1"))[0], 2)
        self.forge_token = "g" * 40
        source.write_text(self.forge_token + "\n")
        self.assertEqual(administer(("--expected-current-instance", self.forge_instance,
                                     "--expected-current-repository", "forge",
                                     "--expected-current-revision", "1"))[0], 0)
        self.assertEqual(self.read()["state"], "OBSERVED")
        self.assertEqual(administer(("--expected-current-instance", self.forge_instance,
                                     "--expected-current-repository", "forge",
                                     "--expected-current-revision", "1"))[0], 2)
        source.chmod(0o644)
        self.assertEqual(administer(("--expected-current-instance", self.forge_instance,
                                     "--expected-current-repository", "forge",
                                     "--expected-current-revision", "2"))[0], 2)

    def test_replacement_publishes_endpoint_and_token_as_one_generation(self):
        self.configure()
        old, *_ = _binding(self.service._root_fd)
        next_token = "h" * 40
        next_endpoint = "http://127.0.0.1:8764/"
        source = Path(self.temp.name) / "next-token"
        source.write_text(next_token + "\n")
        source.chmod(0o600)
        entered, release = threading.Event(), threading.Event()
        errors = []
        original_publish = forge_peer._publish

        def delayed_publish(temporary, descriptor):
            entered.set()
            if not release.wait(5):
                raise RuntimeError("test publication pause timed out")
            original_publish(temporary, descriptor)

        def replace_binding():
            try:
                self.service.configure_forge_read(
                    next_endpoint, self.forge_instance, "forge", str(source),
                    expected_instance_id=self.forge_instance,
                    expected_repository_id="forge", expected_revision=1)
            except Exception as error:
                errors.append(error)

        with patch("workspace_control.forge_peer._publish", side_effect=delayed_publish):
            worker = threading.Thread(target=replace_binding)
            worker.start()
            try:
                self.assertTrue(entered.wait(5))
                during, *_ = _binding(self.service._root_fd)
                self.assertEqual((during["endpoint"], during["token"], during["revision"]),
                                 (old["endpoint"], old["token"], 1))
            finally:
                release.set()
                worker.join(timeout=5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(errors, [])
        after, *_ = _binding(self.service._root_fd)
        self.assertEqual((after["endpoint"], after["token"], after["revision"]),
                         (next_endpoint, next_token, 2))


class ConversationDraftTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "server"
        self.root.mkdir(mode=0o700)
        self.instance = initialize(self.root)
        self._catalogue()
        self.service = Service(self.root)
        self.addCleanup(self.service.close)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.service))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        self.grant = self.service.issue_conversation_grant("alice", "project-a")

    def _catalogue(self, *, age=0, projects=None):
        document = {"source": "LOCAL", "observed_at":
                    (datetime.now(timezone.utc) - timedelta(seconds=age)).isoformat(),
                    "projects": projects if projects is not None else
                    [{"id": "project-a", "name": "Project A"}, {"id": "project-b", "name": "Project B"}]}
        path = self.root / "projects.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        path.chmod(0o600)

    def request(self, path, *, method="GET", grant=None, token=None, pin=None, body=None, origin=None):
        headers = {"Authorization": "Bearer " + (self.service.token if token is None else token),
                   "X-Workspace-Instance": self.instance if pin is None else pin}
        if grant is not False:
            headers["X-Workspace-Draft-Grant"] = self.grant if grant is None else grant
        if origin is not None:
            headers["Origin"] = origin
        if body is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(body).encode()
        request = Request(self.url + path, method=method, headers=headers, data=body)
        try:
            with urlopen(request, timeout=2) as response:
                return response.status, json.loads(response.read())
        except HTTPError as error:
            try:
                return error.code, json.loads(error.read())
            finally:
                error.close()

    @staticmethod
    def fields(**overrides):
        return {"title": "Discuss the outcome", "focus": "Vision", "mode": "BUSINESS",
                "draft": "What would help users?", "request_id": "a" * 32, **overrides}

    @classmethod
    def update_fields(cls, **overrides):
        fields = cls.fields(**overrides)
        fields.pop("request_id")
        return fields

    @staticmethod
    def operation_id(identity, archived, revision, suffix="0" * 16):
        action = "ARCHIVE" if archived else "RESTORE"
        binding = hashlib.sha256(f"{identity}:{action}:{revision}".encode()).hexdigest()[:16]
        return binding + suffix[:16]

    def test_explicit_grant_durable_drafts_and_revision_conflict(self):
        self.assertEqual(self.request("/v1/conversations")[1]["conversations"], [])
        self.assertFalse((self.root / "conversations.sqlite3").exists())
        status, created = self.request("/v1/conversations", method="POST", body=self.fields())
        self.assertEqual(status, 201)
        self.assertEqual(created["state"], "DRAFT_ONLY")
        self.assertEqual(created["history"], [])
        self.assertEqual(created["history_availability"], "UNQUALIFIED_FORGE")
        self.assertEqual((created["actor_id"], created["project_id"], created["revision"]),
                         ("alice", "project-a", 1))
        self.assertFalse(created["archived"])
        identity = created["id"]
        self.assertEqual(self.request("/v1/conversations", method="POST", body=self.fields()),
                         (201, created))
        self.assertEqual(self.request("/v1/conversations", method="POST",
                                      body=self.fields(title="Changed request")),
                         (409, {"error": "DRAFT_CONFLICT"}))
        self.assertEqual(self.request("/v1/conversations")[1]["conversations"][0]["id"], identity)
        self.assertEqual(self.request("/v1/conversations/" + identity)[1]["draft"],
                         "What would help users?")
        changed = {**self.update_fields(mode="ARCHITECTURE", draft="Check the current boundary"),
                   "expected_revision": 1}
        self.assertEqual(self.request("/v1/conversations/" + identity,
                                      method="PATCH", body=changed)[1]["revision"], 2)
        replay = self.request("/v1/conversations", method="POST", body=self.fields())
        self.assertEqual((replay[0], replay[1]["id"], replay[1]["revision"]), (201, identity, 2))
        self.assertEqual(self.request("/v1/conversations/" + identity,
                                      method="PATCH", body=changed),
                         (409, {"error": "DRAFT_CONFLICT"}))
        with Service(self.root) as reopened:
            record = reopened.conversations.get(("alice", "project-a"), identity)
        self.assertEqual((record["draft"], record["mode"], record["revision"]),
                         ("Check the current boundary", "ARCHITECTURE", 2))
        self.assertEqual((self.root / "conversation-grants.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.root / "conversations.sqlite3").stat().st_mode & 0o777, 0o600)

    def test_draft_contract_and_revision_preserve_navigation(self):
        status, contract = self.request("/v1/conversations/openapi.json", grant=False)
        self.assertEqual(status, 200)
        self.assertEqual(set(contract["paths"]["/v1/conversations"]), {"get", "post"})
        self.assertEqual(set(contract["paths"]["/v1/conversations/{id}"]), {"get", "patch"})
        self.assertEqual(set(contract["paths"]["/v1/conversations/{id}/archive"]), {"post"})
        self.assertEqual(set(contract["paths"]["/v1/conversations/{id}/restore"]), {"post"})
        self.assertIn("archived", contract["components"]["schemas"]["Conversation"]["required"])
        self.assertNotIn("send", json.dumps(contract).lower())
        self.assertEqual(self.request("/v1/conversations/openapi.json", token="wrong")[0], 401)
        _, created = self.request("/v1/conversations", method="POST", body=self.fields())
        changed = {**self.update_fields(title="Renamed", mode="ARCHITECTURE"),
                   "expected_revision": 1}
        status, updated = self.request("/v1/conversations/" + created["id"], method="PATCH", body=changed)
        self.assertEqual(status, 200)
        self.assertEqual((updated["title"], updated["mode"], updated["history"]),
                         ("Renamed", "ARCHITECTURE", []))
        self.assertEqual(self.request("/v1/conversations")[1]["conversations"][0]["title"], "Renamed")

    def test_archive_restore_is_durable_idempotent_and_preserves_draft(self):
        _, created = self.request("/v1/conversations", method="POST", body=self.fields())
        identity = created["id"]
        archive = {"expected_revision": 1,
                   "operation_id": self.operation_id(identity, True, 1, "b" * 16)}
        status, archived = self.request(f"/v1/conversations/{identity}/archive",
                                        method="POST", body=archive)
        self.assertEqual(status, 200)
        self.assertEqual((archived["id"], archived["archived"], archived["revision"],
                          archived["draft"], archived["mode"]),
                         (identity, True, 2, "What would help users?", "BUSINESS"))
        self.assertEqual(self.request(f"/v1/conversations/{identity}/archive",
                                      method="POST", body=archive), (200, archived))
        restore = {"expected_revision": 2,
                   "operation_id": self.operation_id(identity, False, 2, "c" * 16)}
        status, restored = self.request(f"/v1/conversations/{identity}/restore",
                                        method="POST", body=restore)
        self.assertEqual(status, 200)
        self.assertEqual((restored["id"], restored["archived"], restored["revision"],
                          restored["draft"]), (identity, False, 3, "What would help users?"))
        replay_status, old_replay = self.request(f"/v1/conversations/{identity}/archive",
                                                 method="POST", body=archive)
        self.assertEqual((replay_status, old_replay["archived"], old_replay["revision"]),
                         (200, False, 3))
        with Service(self.root) as reopened:
            record = reopened.conversations.get(("alice", "project-a"), identity)
        self.assertEqual((record["archived"], record["revision"], record["draft"]),
                         (False, 3, "What would help users?"))

    def test_archive_conflicts_scope_and_old_client_patch_preserves_state(self):
        _, created = self.request("/v1/conversations", method="POST", body=self.fields())
        identity = created["id"]
        path = f"/v1/conversations/{identity}/archive"
        command = {"expected_revision": 1,
                   "operation_id": self.operation_id(identity, True, 1, "d" * 16)}
        bob = self.service.issue_conversation_grant("bob", "project-a")
        other = self.service.issue_conversation_grant("alice", "project-b")
        for grant in (bob, other):
            self.assertEqual(self.request(path, method="POST", grant=grant, body=command),
                             (404, {"error": "NOT_FOUND"}))
        self.assertEqual(self.request(path, method="POST", body=command)[1]["revision"], 2)
        stale_patch = {**self.update_fields(title="Old client rename"), "expected_revision": 1}
        self.assertEqual(self.request(f"/v1/conversations/{identity}", method="PATCH",
                                      body=stale_patch), (409, {"error": "DRAFT_CONFLICT"}))
        current_patch = {**self.update_fields(title="Archived rename"), "expected_revision": 2}
        renamed = self.request(f"/v1/conversations/{identity}", method="PATCH",
                               body=current_patch)[1]
        self.assertEqual((renamed["title"], renamed["archived"], renamed["revision"]),
                         ("Archived rename", True, 3))
        self.assertEqual(self.request(path, method="POST",
                                      body={"expected_revision": 3,
                                            "operation_id": command["operation_id"]}),
                         (409, {"error": "DRAFT_CONFLICT"}))
        self.service.revoke_conversation_grants("alice", "project-a")
        self.assertEqual(self.request(f"/v1/conversations/{identity}/restore", method="POST",
                                      body={"expected_revision": 3,
                                            "operation_id": self.operation_id(
                                                identity, False, 3, "e" * 16)}),
                         (403, {"error": "DRAFT_GRANT_DENIED"}))

    def test_existing_store_migrates_records_to_active(self):
        database = self.root / "conversations.sqlite3"
        connection = sqlite3.connect(database)
        try:
            connection.execute("""CREATE TABLE conversations (
                id TEXT PRIMARY KEY, actor_id TEXT NOT NULL, project_id TEXT NOT NULL,
                request_id TEXT NOT NULL, request_digest TEXT NOT NULL,
                title TEXT NOT NULL, focus TEXT NOT NULL, mode TEXT NOT NULL,
                draft TEXT NOT NULL, revision INTEGER NOT NULL,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
            connection.execute("""INSERT INTO conversations VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                ("f" * 32, "alice", "project-a", "1" * 32, "2" * 64,
                 "Existing", "Vision", "UX", "Keep this", 4,
                 "2026-10-05T00:00:00+00:00", "2026-10-05T00:00:00+00:00"))
            connection.commit()
        finally:
            connection.close()
        database.chmod(0o600)
        status, listing = self.request("/v1/conversations")
        self.assertEqual(status, 200)
        self.assertEqual((listing["conversations"][0]["id"],
                          listing["conversations"][0]["archived"]), ("f" * 32, False))
        restored = self.request(f"/v1/conversations/{'f' * 32}/restore", method="POST",
                                body={"expected_revision": 4,
                                      "operation_id": self.operation_id(
                                          "f" * 32, False, 4, "3" * 16)})[1]
        self.assertEqual((restored["archived"], restored["revision"]), (False, 4))

    def test_archive_operation_receipts_are_bounded_without_reapplying_old_command(self):
        _, created = self.request("/v1/conversations", method="POST", body=self.fields())
        identity = created["id"]
        self.service.conversations.OPERATION_RECEIPT_LIMIT = 3
        commands = []
        for digit in "12345":
            command = {"expected_revision": 1,
                       "operation_id": self.operation_id(identity, False, 1, digit * 16)}
            commands.append(command)
            status, restored = self.request(
                f"/v1/conversations/{identity}/restore", method="POST",
                body=command)
            self.assertEqual((status, restored["archived"], restored["revision"]),
                             (200, False, 1))
        status, replay = self.request(
            f"/v1/conversations/{identity}/restore", method="POST", body=commands[0])
        self.assertEqual((status, replay["archived"], replay["revision"]), (200, False, 1))
        self.assertEqual(self.request(
            f"/v1/conversations/{identity}/archive", method="POST",
            body=commands[0]),
            (409, {"error": "DRAFT_CONFLICT"}))
        status, archived = self.request(
            f"/v1/conversations/{identity}/archive", method="POST",
            body={"expected_revision": 1,
                  "operation_id": self.operation_id(identity, True, 1, "a" * 16)})
        self.assertEqual((status, archived["archived"], archived["revision"]), (200, True, 2))
        connection = sqlite3.connect(self.root / "conversations.sqlite3")
        try:
            count = connection.execute("SELECT COUNT(*) FROM conversation_operations").fetchone()[0]
        finally:
            connection.close()
        self.assertLessEqual(count, 3)

    def test_read_token_alone_cannot_write_or_read_actor_drafts(self):
        path = "/v1/conversations"
        self.assertEqual(self.request(path, grant=False), (403, {"error": "DRAFT_GRANT_REQUIRED"}))
        self.assertEqual(self.request(path, method="POST", grant=False, body=self.fields()),
                         (403, {"error": "DRAFT_GRANT_REQUIRED"}))
        self.assertEqual(self.request(path, grant="invalid"), (403, {"error": "DRAFT_GRANT_DENIED"}))
        self.assertEqual(self.request(path, token="wrong"), (401, {"error": "UNAUTHORIZED"}))
        self.assertEqual(self.request(path, pin="wrong"), (409, {"error": "WRONG_INSTANCE"}))
        self.assertEqual(self.request(path, method="POST", body=self.fields(),
                                      origin="https://other.example"), (403, {"error": "ORIGIN_DENIED"}))
        self.assertEqual(self.request(path, method="PUT", body=self.fields())[0], 405)
        self.assertEqual(self.request(path, method="DELETE", body=self.fields())[0], 405)
        _, created = self.request(path, method="POST", body=self.fields())
        bob_grant = self.service.issue_conversation_grant("bob", "project-a")
        other_project = self.service.issue_conversation_grant("alice", "project-b")
        for grant in (bob_grant, other_project):
            self.assertEqual(self.request(path, grant=grant)[1]["conversations"], [])
            self.assertEqual(self.request(path + "/" + created["id"], grant=grant),
                             (404, {"error": "NOT_FOUND"}))
            self.assertEqual(self.request(path + "/" + created["id"], method="PATCH",
                                          grant=grant, body={**self.update_fields(), "expected_revision": 1}),
                             (404, {"error": "NOT_FOUND"}))

    def test_invalid_requests_and_project_freshness_fail_closed(self):
        path = "/v1/conversations"
        for fields in (self.fields(mode="UNKNOWN"), self.fields(title=" "),
                       self.fields(draft="a" * 10001), self.fields(extra="value")):
            self.assertEqual(self.request(path, method="POST", body=fields),
                             (400, {"error": "INVALID_BODY"}))
        _, created = self.request(path, method="POST", body=self.fields())
        for revision in (True, 0, "1"):
            self.assertEqual(self.request(path + "/" + created["id"], method="PATCH",
                                          body={**self.update_fields(), "expected_revision": revision}),
                             (400, {"error": "INVALID_BODY"}))
        self._catalogue(age=301)
        self.assertEqual(self.request(path), (503, {"error": "PROJECT_SOURCE_UNAVAILABLE"}))
        self._catalogue(projects=[{"id": "project-b", "name": "Project B"}])
        self.assertEqual(self.request(path), (403, {"error": "DRAFT_GRANT_DENIED"}))
        with self.assertRaises(ValueError):
            self.service.issue_conversation_grant("bob", "project-a")
        with self.assertRaises(ValueError):
            self.service.issue_conversation_grant("bad actor", "project-b")

    def test_duplicate_json_keys_and_oversized_body_fail_closed(self):
        port = self.server.server_port
        headers = {"Authorization": "Bearer " + self.service.token,
                   "X-Workspace-Instance": self.instance,
                   "X-Workspace-Draft-Grant": self.grant,
                   "Content-Type": "application/json"}
        for body in (b'{"title":"one","title":"two"}', b"x" * 48_001):
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
            try:
                connection.request("POST", "/v1/conversations", body=body, headers=headers)
                response = connection.getresponse()
                self.assertEqual(response.status, 400)
                self.assertEqual(json.loads(response.read()), {"error": "INVALID_BODY"})
            finally:
                connection.close()
        self.assertEqual(self.request("/v1/conversations")[1]["conversations"], [])

    def test_grant_store_validation_and_direct_conflict(self):
        scope = self.service.conversation_scope(self.grant)
        record = self.service.conversations.create(scope, self.fields())
        with self.assertRaises(ConversationConflict):
            self.service.conversations.update(scope, record["id"],
                                              {**self.update_fields(), "expected_revision": 9})
        with self.assertRaises(FileNotFoundError):
            self.service.conversations.get(scope, "missing")
        grant_path = self.root / "conversation-grants.json"
        grant_path.write_text('{"grants": [{"digest": "bad"}]}', encoding="utf-8")
        with self.assertRaises(ValueError):
            self.service.conversations.scope(self.grant)

    def test_grant_revocation_removes_only_exact_actor_project(self):
        other = self.service.issue_conversation_grant("alice", "project-b")
        self.assertEqual(self.service.revoke_conversation_grants("alice", "project-a"), 1)
        self.assertEqual(self.request("/v1/conversations"), (403, {"error": "DRAFT_GRANT_DENIED"}))
        self.assertEqual(self.request("/v1/conversations", grant=other)[0], 200)
        self.assertEqual(self.service.revoke_conversation_grants("alice", "project-a"), 0)

    def test_concurrent_grant_issue_cannot_restore_revoked_scope(self):
        issuer = ConversationStore(self.root, self.service._root_fd)
        revoker = ConversationStore(self.root, self.service._root_fd)
        read_complete = threading.Event()
        allow_issue = threading.Event()
        revoke_started = threading.Event()
        original_read = issuer._grants
        original_lock = revoker._grant_write_lock

        def paused_read():
            grants = original_read()
            read_complete.set()
            self.assertTrue(allow_issue.wait(5))
            return grants

        issuer._grants = paused_read

        @contextmanager
        def announced_lock():
            revoke_started.set()
            with original_lock():
                yield

        revoker._grant_write_lock = announced_lock
        with ThreadPoolExecutor(max_workers=2) as pool:
            issued = pool.submit(issuer.issue_grant, "bob", "project-a")
            self.assertTrue(read_complete.wait(5))
            revoked = pool.submit(revoker.revoke_grants, "alice", "project-a")
            self.assertTrue(revoke_started.wait(5))
            with self.assertRaises(TimeoutError):
                revoked.result(timeout=0.1)
            allow_issue.set()
            bob = issued.result(timeout=5)
            self.assertEqual(revoked.result(timeout=5), 1)
        with self.assertRaises(PermissionError):
            issuer.scope(self.grant)
        self.assertEqual(revoker.scope(bob), ("bob", "project-a"))

    def test_local_admin_grant_cli_and_revoke(self):
        issued = io.StringIO()
        with redirect_stdout(issued):
            self.assertEqual(main(["--root", str(self.root), "conversation-grant-issue",
                                   "--actor", "carol", "--project", "project-b"]), 0)
        token = json.loads(issued.getvalue())["draft_grant_token"]
        self.assertEqual(self.request("/v1/conversations", grant=token)[1]["actor_id"], "carol")
        revoked = io.StringIO()
        with redirect_stdout(revoked):
            self.assertEqual(main(["--root", str(self.root), "conversation-grant-revoke",
                                   "--actor", "carol", "--project", "project-b"]), 0)
        self.assertEqual(json.loads(revoked.getvalue())["revoked"], 1)
        self.assertEqual(self.request("/v1/conversations", grant=token)[0], 403)

    def test_concurrent_duplicate_create_and_stale_update(self):
        barrier = threading.Barrier(2)
        def create():
            with Service(self.root) as client:
                barrier.wait(timeout=3)
                return client.conversations.create(client.conversation_scope(self.grant), self.fields())
        with ThreadPoolExecutor(max_workers=2) as pool:
            first, second = list(pool.map(lambda _: create(), range(2)))
        self.assertEqual(first["id"], second["id"])
        self.assertEqual(len(self.request("/v1/conversations")[1]["conversations"]), 1)
        barrier = threading.Barrier(2)
        def update(title):
            with Service(self.root) as client:
                barrier.wait(timeout=3)
                try:
                    return client.conversations.update(client.conversation_scope(self.grant), first["id"],
                        {**self.update_fields(title=title), "expected_revision": 1})["revision"]
                except ConversationConflict:
                    return "CONFLICT"
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(update, ("One", "Two")))
        self.assertEqual(sorted(map(str, results)), ["2", "CONFLICT"])

    def test_draft_navigation_has_no_forge_provider_call(self):
        with patch.object(forge_peer, "projection", side_effect=AssertionError("unexpected Forge call")):
            _, created = self.request("/v1/conversations", method="POST", body=self.fields())
            self.assertEqual(self.request("/v1/conversations")[0], 200)
            self.assertEqual(self.request("/v1/conversations/" + created["id"])[0], 200)
            self.assertEqual(self.request("/v1/conversations/" + created["id"], method="PATCH",
                body={**self.update_fields(mode="UX"), "expected_revision": 1})[0], 200)
