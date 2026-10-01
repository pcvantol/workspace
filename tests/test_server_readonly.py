"""Real HTTP and state qualification for the own read-only slice."""

import json
import http.client
import importlib
import io
import os
from pathlib import Path
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
from workspace_control.service import Service, initialize


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
            return (response.status, json.loads(body) if body and path.startswith("/v1/") else None,
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
        for origins in (("http://evil.example",), (f"http://{host}", f"http://{host}"),
                        ("null",)):
            for path in ("/v1/identity", "/v1/status", "/"):
                with self.subTest(origins=origins, path=path):
                    self.assertEqual(self.raw_request(path, hosts=(host,), origins=origins)[0], 403)
        self.assertEqual(self.authorized("/v1/status")[0], 200)

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
        self.assertIn(b"Read-only", html)
        self.assertIn("no-store", headers["Cache-Control"])
        code, script, _ = self.request("/client.js")
        self.assertEqual(code, 200)
        self.assertIn(b"fetch('/v1/projects'", script)

    def test_openapi_postman_route_parity(self):
        api = json.loads(self.authorized("/v1/openapi.json")[1])
        collection = json.loads((Path(__file__).resolve().parents[1] / "docs" /
                                 "WORKSPACE_SERVER_READONLY_V1.postman.json").read_text())
        routes = {item["request"]["url"].removeprefix("{{baseUrl}}") for item in collection["item"]}
        self.assertEqual(set(ROUTES), set(api["paths"]))
        self.assertEqual(set(ROUTES), routes)
        inventory = json.loads(self.authorized("/v1/capabilities")[1])
        self.assertEqual((inventory["schema_version"], inventory["instance_id"]), (1, self.instance))
        self.assertFalse(inventory["peer_operations_qualified"])
        operations = {operation["id"]: operation for operation in inventory["operations"]}
        self.assertEqual(set(operations), set(OPERATIONS))
        http_routes = {operation["path"] for operation in operations.values()
                       if operation["exposure"] == "HTTP_EXPOSED"}
        self.assertEqual(http_routes, set(ROUTES))
        self.assertEqual(operations["projects.read"]["local_cli"], "projects")
        self.assertEqual({api["paths"][path]["get"]["operationId"] for path in http_routes},
                         {operation["id"] for operation in operations.values()
                          if operation["exposure"] == "HTTP_EXPOSED"})
        self.assertEqual({operation["id"] for operation in operations.values()
                          if operation["exposure"] == "LOCAL_ONLY_ADMIN"},
                         {"instance.init", "server.serve"})
        self.assertTrue(all("path" not in operation for operation in operations.values()
                            if operation["exposure"] == "LOCAL_ONLY_ADMIN"))
        self.assertTrue(all(operation["auth"] == "BEARER_PINNED" for operation in operations.values()
                            if operation.get("path") not in (None, "/v1/identity")))
        for item in collection["item"]:
            self.assertEqual(item["request"]["method"], "GET")
            if item["name"] != "identity":
                self.assertEqual({header["key"] for header in item["request"]["header"]},
                                 {"Authorization", "X-Workspace-Instance"})

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

    def test_bad_roots_and_private_files(self):
        self.assertEqual(main(["--root", "relative", "init"]), 2)
        self.root.chmod(0o755)
        self.assertRaises(ValueError, Service, self.root)
        self.root.chmod(0o700)
        token = self.root / "token"
        token.chmod(0o644)
        self.assertRaises(ValueError, Service, self.root)

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
        def race_at_identity(path, flags, mode):
            if Path(path).name == "instance.json":
                Path(path).write_text("winner")
                raise FileExistsError("other initializer won")
            return real_open(path, flags, mode)
        with patch("workspace_control.service.os.open", side_effect=race_at_identity):
            self.assertRaises(FileExistsError, initialize, fresh)
        self.assertEqual((fresh / "instance.json").read_text(), "winner")
        (fresh / "instance.json").unlink()
        def race_at_token(path, flags, mode):
            if Path(path).name == "token":
                Path(path).write_text("winner token")
                raise FileExistsError("other initializer won")
            return real_open(path, flags, mode)
        with patch("workspace_control.service.os.open", side_effect=race_at_token):
            self.assertRaises(FileExistsError, initialize, fresh)
        self.assertFalse((fresh / "instance.json").exists())
        self.assertEqual((fresh / "token").read_text(), "winner token")

    def test_cli_modes_and_server_lock(self):
        self.assertEqual(main(["--root", str(self.root), "serve", "--port", "0"]), 2)
        with patch("workspace_control.cli.serve") as mock_serve:
            self.assertEqual(main(["--root", str(self.root), "serve", "--port", "8767"]), 0)
            mock_serve.assert_called_once_with(str(self.root), 8767)
        with patch("workspace_control.cli.webbrowser.open") as open_browser:
            self.assertEqual(client_main(["--url", "http://127.0.0.1:8767"]), 0)
            open_browser.assert_called_once_with("http://127.0.0.1:8767/")
        for url in ("https://127.0.0.1:8767", "http://127.0.0.1:8767@evil.example",
                    "http://127.0.0.1:bad", "http://localhost:8767/v1/status"):
            with self.assertRaises(SystemExit):
                client_main(["--url", url])
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
        for value in cases:
            target.write_text(json.dumps(value))
            target.chmod(0o600)
            self.assertEqual(self.authorized("/v1/projects")[0], 503)
