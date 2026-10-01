"""Loopback-only, authenticated and versioned Workspace HTTP ingress."""

import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.resources
import json
import os
import secrets
import stat
from urllib.parse import urlsplit

from .service import Service


ROUTES = {"/v1/identity": "public identity", "/v1/status": "authenticated status",
          "/v1/projects": "authenticated catalogue", "/v1/openapi.json": "authenticated API contract"}


def openapi_contract():
    paths = {}
    for route, summary in ROUTES.items():
        operation = {"summary": summary, "responses": {"200": {"description": "Read result"},
                                                       "400": {"description": "Invalid path"},
                                                       "401": {"description": "Unauthorized"},
                                                       "409": {"description": "Wrong instance"},
                                                       "503": {"description": "Source unavailable"}}}
        if route != "/v1/identity":
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
            self.wfile.write(payload)

        def do_GET(self):
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
            expected_origin = f"http://{self.headers.get('Host', '')}"
            if self.headers.get("Origin") not in (None, expected_origin):
                return self._reply(403, {"error": "ORIGIN_DENIED"})
            auth = self.headers.get("Authorization", "")
            provided = auth[7:] if auth.startswith("Bearer ") else ""
            if not secrets.compare_digest(provided, service.token):
                return self._reply(401, {"error": "UNAUTHORIZED"})
            if self.headers.get("X-Workspace-Instance") != service.instance_id:
                return self._reply(409, {"error": "WRONG_INSTANCE"})
            try:
                if path == "/v1/status":
                    result = service.status()
                elif path == "/v1/projects":
                    result = service.projects()
                else:
                    result = openapi_contract()
            except (ValueError, OSError, json.JSONDecodeError):
                return self._reply(503, {"error": "SOURCE_UNAVAILABLE"})
            return self._reply(200, result)

        def do_POST(self):
            self._reply(405, {"error": "READ_ONLY"})

        do_PUT = do_POST
        do_PATCH = do_POST
        do_DELETE = do_POST

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
