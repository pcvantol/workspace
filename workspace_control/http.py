"""Loopback-only, authenticated and versioned Workspace HTTP ingress."""

import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.resources
import json
import os
import secrets
import stat
from urllib.parse import urlsplit

from . import __version__
from .service import Service


OPERATIONS = {
    "identity.read": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/identity",
                      "auth": "PUBLIC", "summary": "public identity"},
    "status.read": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/status",
                    "auth": "BEARER_PINNED", "local_cli": "status", "summary": "authenticated status"},
    "projects.read": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/projects",
                      "auth": "BEARER_PINNED", "local_cli": "projects",
                      "summary": "authenticated catalogue"},
    "openapi.read": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/openapi.json",
                     "auth": "BEARER_PINNED", "local_cli": "openapi",
                     "summary": "authenticated API contract"},
    "capabilities.read": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/capabilities",
                         "auth": "BEARER_PINNED", "local_cli": "capabilities",
                         "summary": "own operation inventory"},
    "instance.init": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "init",
                      "auth": "PRIVATE_ROOT_OWNER", "summary": "initialize private instance"},
    "server.serve": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "serve",
                     "auth": "PRIVATE_ROOT_OWNER", "summary": "serve private instance"},
}
ROUTES = {details["path"]: details["summary"] for details in OPERATIONS.values()
          if details["exposure"] == "HTTP_EXPOSED"}


def operation_inventory(instance_id):
    operations = []
    for operation_id, details in sorted(OPERATIONS.items()):
        operation = {"id": operation_id, "exposure": details["exposure"], "auth": details["auth"]}
        for key in ("method", "path", "local_cli"):
            if key in details:
                operation[key] = details[key]
        operations.append(operation)
    return {"schema_version": 1, "product_version": __version__,
            "instance_id": instance_id, "operations": operations,
            "peer_operations_qualified": False}


def openapi_contract():
    paths = {}
    for operation_id, details in OPERATIONS.items():
        if details["exposure"] != "HTTP_EXPOSED":
            continue
        route = details["path"]
        responses = {"200": {"description": "Read result"},
                     "400": {"description": "Invalid path"},
                     "403": {"description": "Host or Origin denied"}}
        operation = {"operationId": operation_id, "summary": details["summary"],
                     "responses": responses}
        if details["auth"] == "BEARER_PINNED":
            responses["400"] = {"description": "Invalid path or ambiguous credentials"}
            responses.update({"401": {"description": "Unauthorized"},
                              "409": {"description": "Wrong instance"},
                              "503": {"description": "Source unavailable"}})
            operation["security"] = [{"bearerAuth": []}]
            operation["parameters"] = [{"name": "X-Workspace-Instance", "in": "header", "required": True,
                                        "schema": {"type": "string"}}]
        paths[route] = {"get": operation}
    return {"openapi": "3.0.3", "info": {"title": "Workspace read-only V1", "version": "1"},
            "servers": [{"url": "http://127.0.0.1:{port}", "variables": {"port": {"default": "8765"}}}],
            "components": {"securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"}}},
            "paths": paths}


def handler_for(service):
    class Handler(BaseHTTPRequestHandler):
        def _reply(self, code, value, content_type="application/json; charset=utf-8"):
            payload = value if isinstance(value, bytes) else json.dumps(value, sort_keys=True).encode()
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'unsafe-inline'")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)

        def _trusted_origin(self):
            hosts = self.headers.get_all("Host", [])
            allowed = {f"127.0.0.1:{self.server.server_port}",
                       f"localhost:{self.server.server_port}"}
            if len(hosts) != 1 or hosts[0] not in allowed:
                self._reply(403, {"error": "HOST_DENIED"})
                return False
            origins = self.headers.get_all("Origin", [])
            if len(origins) > 1 or (origins and origins[0] != f"http://{hosts[0]}"):
                self._reply(403, {"error": "ORIGIN_DENIED"})
                return False
            return True

        def do_GET(self):
            if not self._trusted_origin():
                return
            parsed = urlsplit(self.path)
            path = parsed.path
            if parsed.query or parsed.fragment or "%" in path or ".." in path:
                return self._reply(400, {"error": "INVALID_PATH"})
            if path == "/":
                html = importlib.resources.files("workspace_control").joinpath("client.html").read_bytes()
                return self._reply(200, html, "text/html; charset=utf-8")
            if path == "/client.js":
                script = importlib.resources.files("workspace_control").joinpath("client.js").read_bytes()
                return self._reply(200, script, "text/javascript; charset=utf-8")
            if path == "/v1/identity":
                return self._reply(200, {"instance_id": service.instance_id})
            if path not in ROUTES:
                return self._reply(404, {"error": "NOT_FOUND"})
            authorizations = self.headers.get_all("Authorization", [])
            pins = self.headers.get_all("X-Workspace-Instance", [])
            if len(authorizations) > 1 or len(pins) > 1:
                return self._reply(400, {"error": "AMBIGUOUS_CREDENTIALS"})
            auth = authorizations[0] if authorizations else ""
            provided = auth[7:] if auth.startswith("Bearer ") else ""
            if not secrets.compare_digest(provided, service.token):
                return self._reply(401, {"error": "UNAUTHORIZED"})
            if (pins[0] if pins else None) != service.instance_id:
                return self._reply(409, {"error": "WRONG_INSTANCE"})
            try:
                if path == "/v1/status":
                    result = service.status()
                elif path == "/v1/projects":
                    result = service.projects()
                elif path == "/v1/openapi.json":
                    result = openapi_contract()
                else:
                    result = operation_inventory(service.instance_id)
            except (ValueError, OSError, UnicodeError):
                return self._reply(503, {"error": "SOURCE_UNAVAILABLE"})
            return self._reply(200, result)

        def do_POST(self):
            if not self._trusted_origin():
                return
            self._reply(405, {"error": "READ_ONLY"})

        do_PUT = do_POST
        do_PATCH = do_POST
        do_DELETE = do_POST
        do_HEAD = do_GET
        do_OPTIONS = do_POST
        do_TRACE = do_POST
        do_CONNECT = do_POST

    return Handler


def serve(root, port):
    service = Service(root)
    lock_file = service.root / "server.lock"
    descriptor = os.open(lock_file, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "r+") as lock:
        info = os.fstat(lock.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("server lock must be a private regular file")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError("instance already served") from exc
        server = ThreadingHTTPServer(("127.0.0.1", port), handler_for(service))
        try:
            server.serve_forever(poll_interval=0.1)
        finally:
            server.server_close()
