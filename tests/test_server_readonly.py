"""Real HTTP and state qualification for the own read-only slice."""

import json
import http.client
import importlib
import io
import os
from pathlib import Path
import re
import socket
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from workspace_control.cli import main, client_main
from workspace_control.http import ThreadingHTTPServer, handler_for, serve, ROUTES, OPERATIONS
from workspace_control.service import Service, _regular_private, initialize, inspect


class ReadOnlyTests(unittest.TestCase):
    def test_version_projection_uses_package_and_source(self):
        import workspace_control
        expected = json.loads((Path(__file__).resolve().parents[1] / "product-version.json").read_text())["version"]
        self.assertEqual(importlib.reload(workspace_control).__version__, expected)
        with patch("pathlib.Path.read_text", side_effect=FileNotFoundError), patch("importlib.metadata.version", return_value=expected):
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
        for request_line, status in (
            (b"GET /v1/identity?token=" + secret + b" HTTP/1.1 EXTRA\r\n", b"400"),
            (b"UNKNOWN /v1/identity?token=" + secret + b" HTTP/1.1\r\n", b"501"),
        ):
            with self.subTest(status=status), socket.create_connection(
                ("127.0.0.1", self.server.server_port), timeout=2
            ) as connection:
                connection.sendall(request_line + b"Host: 127.0.0.1\r\n\r\n")
                chunks = []
                while chunk := connection.recv(4096):
                    chunks.append(chunk)
                response = b"".join(chunks)
                self.assertIn(b" " + status + b" ", response.split(b"\r\n", 1)[0])
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
                       if operation["exposure"] == "HTTP_EXPOSED"}
        self.assertEqual(http_routes, set(ROUTES))
        self.assertEqual(operations["projects.read"]["local_cli"], "projects")
        self.assertEqual(operations["capabilities.read"]["local_cli"], "capabilities")
        self.assertEqual(operations["openapi.read"]["local_cli"], "openapi")
        self.assertEqual({api["paths"][path]["get"]["operationId"] for path in http_routes},
                         {operation["id"] for operation in operations.values()
                          if operation["exposure"] == "HTTP_EXPOSED"})
        self.assertEqual({operation["id"] for operation in operations.values()
                          if operation["exposure"] == "LOCAL_ONLY_ADMIN"},
                         {"instance.init", "instance.inspect", "server.serve"})
        self.assertTrue(all("path" not in operation for operation in operations.values()
                            if operation["exposure"] == "LOCAL_ONLY_ADMIN"))
        self.assertTrue(all(operation["auth"] == "BEARER_PINNED" for operation in operations.values()
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
        now = datetime.now(timezone.utc)
        week = now.isocalendar()
        observed_at = f"{week.year}-W{week.week:02d}-{week.weekday}T{now:%H:%M:%S}+00:00"
        target = self.root / "projects.json"
        target.write_text(json.dumps({"source": "LOCAL", "observed_at": observed_at,
                                      "projects": []}))
        target.chmod(0o600)
        result = json.loads(self.authorized("/v1/projects")[1])
        self.assertEqual(result["observed_at"], observed_at)
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

        def replace_after_open(path, flags):
            descriptor = real_open(path, flags)
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

    def test_cli_modes_and_server_lock(self):
        self.assertEqual(main(["--root", str(self.root), "serve", "--port", "0"]), 2)
        with patch("workspace_control.cli.serve") as mock_serve:
            self.assertEqual(main(["--root", str(self.root), "serve", "--port", "8767"]), 0)
            mock_serve.assert_called_once_with(str(self.root), 8767)
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
