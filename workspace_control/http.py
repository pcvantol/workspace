"""Authenticated and versioned Workspace HTTP ingress with explicit TLS binding."""

import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer as BaseThreadingHTTPServer
import importlib.resources
import ipaddress
import json
import os
import re
import secrets
import sqlite3
import ssl
import stat
import sys

from . import __version__
from .schemas import OPENAPI_SCHEMAS, SUCCESS_SCHEMA
from .service import Service, _unique_json_object
from .conversations import ConversationConflict


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
    "forge.status.read": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/forge/status",
                          "auth": "BEARER_PINNED", "summary": "scoped Forge observation"},
    "conversations.contract.read": {"exposure": "HTTP_EXPOSED", "method": "GET",
                                    "path": "/v1/conversations/openapi.json", "auth": "BEARER_PINNED",
                                    "contract": "draft", "summary": "own draft API contract"},
    "conversations.list": {"exposure": "HTTP_EXPOSED", "method": "GET",
                           "path": "/v1/conversations", "auth": "BEARER_PINNED_AND_DRAFT_GRANT",
                           "contract": "draft", "summary": "own conversation drafts"},
    "conversations.create": {"exposure": "HTTP_EXPOSED", "method": "POST",
                             "path": "/v1/conversations", "auth": "BEARER_PINNED_AND_DRAFT_GRANT",
                             "contract": "draft", "summary": "create own conversation draft"},
    "conversations.get": {"exposure": "HTTP_EXPOSED", "method": "GET",
                          "path": "/v1/conversations/{id}", "auth": "BEARER_PINNED_AND_DRAFT_GRANT",
                          "contract": "draft", "summary": "read one own conversation draft"},
    "conversations.update": {"exposure": "HTTP_EXPOSED", "method": "PATCH",
                             "path": "/v1/conversations/{id}", "auth": "BEARER_PINNED_AND_DRAFT_GRANT",
                             "contract": "draft", "summary": "replace own conversation draft at revision"},
    "instance.init": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "init",
                      "auth": "PRIVATE_ROOT_OWNER", "summary": "initialize private instance"},
    "instance.inspect": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "inspect",
                         "auth": "PRIVATE_ROOT_OWNER", "summary": "inspect private initialization state"},
    "forge.read.configure": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "forge-read-configure",
                             "auth": "PRIVATE_ROOT_OWNER", "summary": "bind scoped Forge read token"},
    "server.serve": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "serve",
                     "auth": "PRIVATE_ROOT_OWNER", "summary": "serve private instance"},
    "conversations.grant.issue": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "conversation-grant-issue",
                                  "auth": "PRIVATE_ROOT_OWNER", "summary": "issue project and actor draft grant"},
    "conversations.grant.revoke": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "conversation-grant-revoke",
                                   "auth": "PRIVATE_ROOT_OWNER", "summary": "revoke project and actor draft grants"},
}
ROUTES = {details["path"]: details["summary"] for details in OPERATIONS.values()
          if details["exposure"] == "HTTP_EXPOSED" and details.get("contract", "read") == "read"}


class ThreadingHTTPServer(BaseThreadingHTTPServer):
    def handle_error(self, request, client_address):
        # A client rejecting the certificate is an expected handshake failure.
        if isinstance(sys.exc_info()[1], ssl.SSLError):
            return
        super().handle_error(request, client_address)


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


def openapi_contract(server_url=None):
    paths = {}
    for operation_id, details in OPERATIONS.items():
        if details["exposure"] != "HTTP_EXPOSED" or details.get("contract", "read") != "read":
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
        for code, response in responses.items():
            schema = SUCCESS_SCHEMA[operation_id] if code == "200" else "Error"
            response["content"] = {"application/json": {
                "schema": {"$ref": f"#/components/schemas/{schema}"}}}
        paths[route] = {"get": operation}
    servers = ([{"url": server_url}] if server_url else
               [{"url": "http://127.0.0.1:{port}", "variables": {"port": {"default": "8765"}}}])
    return {"openapi": "3.0.3", "info": {"title": "Workspace read-only V1", "version": "1"},
            "servers": servers,
            "components": {"securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"}},
                           "schemas": OPENAPI_SCHEMAS},
            "paths": paths}


def draft_openapi_contract():
    """Document only Workspace-owned draft storage; no Forge/AI send operation."""
    fields = {"title": {"type": "string", "minLength": 1, "maxLength": 120},
              "focus": {"type": "string", "maxLength": 240},
              "mode": {"type": "string", "enum": ["BUSINESS", "ARCHITECTURE", "UX"]},
              "draft": {"type": "string", "maxLength": 10000}}
    create = {"type": "object", "additionalProperties": False,
              "required": [*fields, "request_id"],
              "properties": {**fields, "request_id": {"type": "string", "pattern": "^[0-9a-f]{32}$"}}}
    update = {"type": "object", "additionalProperties": False,
              "required": [*fields, "expected_revision"],
              "properties": {**fields, "expected_revision": {"type": "integer", "minimum": 1}}}
    record = {"type": "object", "additionalProperties": False,
              "required": ["id", "actor_id", "project_id", *fields, "revision", "created_at",
                           "updated_at", "history", "history_availability", "state"],
              "properties": {"id": {"type": "string", "pattern": "^[0-9a-f]{32}$"},
                             "actor_id": {"type": "string"}, "project_id": {"type": "string"},
                             **fields, "revision": {"type": "integer", "minimum": 1},
                             "created_at": {"type": "string"}, "updated_at": {"type": "string"},
                             "history": {"type": "array", "maxItems": 0},
                             "history_availability": {"type": "string", "enum": ["UNQUALIFIED_FORGE"]},
                             "state": {"type": "string", "enum": ["DRAFT_ONLY"]}}}
    listing = {"type": "object", "additionalProperties": False,
               "required": ["actor_id", "project_id", "conversations", "history_availability"],
               "properties": {"actor_id": {"type": "string"}, "project_id": {"type": "string"},
                              "conversations": {"type": "array", "maxItems": 500,
                                                "items": {"$ref": "#/components/schemas/Conversation"}},
                              "history_availability": {"type": "string", "enum": ["UNQUALIFIED_FORGE"]}}}
    def operation(operation_id, success, *, request=None, item=False):
        result = {"operationId": operation_id,
                  "security": [{"bearerAuth": [], "draftGrant": []}],
                  "parameters": [{"name": "X-Workspace-Instance", "in": "header", "required": True,
                                  "schema": {"type": "string"}}],
                  "responses": {str(success): {"description": "Workspace-owned draft"},
                                "400": {"description": "Invalid request"},
                                "401": {"description": "Read token denied"},
                                "403": {"description": "Draft grant denied"},
                                "409": {"description": "Wrong instance or draft revision conflict"},
                                "503": {"description": "Workspace source unavailable"}}}
        if item:
            result["parameters"].append({"name": "id", "in": "path", "required": True,
                                         "schema": {"type": "string", "pattern": "^[0-9a-f]{32}$"}})
            result["responses"]["404"] = {"description": "Draft not found in this actor/project"}
        if request:
            result["requestBody"] = {"required": True, "content": {"application/json": {
                "schema": {"$ref": f"#/components/schemas/{request}"}}}}
        result["responses"][str(success)]["content"] = {"application/json": {
            "schema": {"$ref": "#/components/schemas/" +
                       ("ConversationList" if operation_id == "conversations.list" else "Conversation")}}}
        return result
    return {"openapi": "3.0.3", "info": {"title": "Workspace conversation drafts V1", "version": "1"},
            "components": {"securitySchemes": {
                "bearerAuth": {"type": "http", "scheme": "bearer"},
                "draftGrant": {"type": "apiKey", "in": "header", "name": "X-Workspace-Draft-Grant"}},
                "schemas": {"DraftCreate": create, "DraftUpdate": update,
                            "Conversation": record, "ConversationList": listing}},
            "paths": {"/v1/conversations": {
                "get": operation("conversations.list", 200),
                "post": operation("conversations.create", 201, request="DraftCreate")},
                "/v1/conversations/{id}": {
                    "get": operation("conversations.get", 200, item=True),
                    "patch": operation("conversations.update", 200, request="DraftUpdate", item=True)}}}


def handler_for(service, *, public_host=None, scheme="http"):
    class Handler(BaseHTTPRequestHandler):
        timeout = 5

        def log_message(self, format, *args):
            # BaseHTTPRequestHandler would log the raw target, including rejected queries.
            return

        def send_error(self, code, message=None, explain=None):
            # Parser diagnostics can contain the raw request line. Keep its
            # status, but return the same private, non-embeddable response
            # shape as all other own HTTP errors.
            self.close_connection = True
            # Python 3.10 can leave an invalid request at the HTTP/0.9
            # default, which would suppress the status line and all headers.
            self.request_version = "HTTP/1.0"
            self._reply(code, {"error": "REQUEST_REJECTED"})

        def _reply(self, code, value, content_type="application/json; charset=utf-8"):
            payload = value if isinstance(value, bytes) else json.dumps(value, sort_keys=True).encode()
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'")
            self.send_header("X-Frame-Options", "DENY")
            self.end_headers()
            # A malformed HEAD request line can fail parsing before command is set.
            is_head = (getattr(self, "command", None) == "HEAD" or
                       getattr(self, "raw_requestline", b"").split(None, 1)[:1] == [b"HEAD"])
            if not is_head:
                self.wfile.write(payload)

        def _trusted_origin(self):
            hosts = self.headers.get_all("Host", [])
            port = self.server.server_port
            if public_host is None:
                allowed = {f"127.0.0.1:{port}", f"localhost:{port}"}
            else:
                allowed = {f"{public_host}:{port}"}
                if port == 443:
                    allowed.add(public_host)
            if len(hosts) != 1 or hosts[0].lower() not in allowed:
                self._reply(403, {"error": "HOST_DENIED"})
                return False
            origins = self.headers.get_all("Origin", [])
            if len(origins) > 1 or (origins and origins[0].lower() != f"{scheme}://{hosts[0].lower()}"):
                self._reply(403, {"error": "ORIGIN_DENIED"})
                return False
            return True

        def _pinned_auth(self):
            authorizations = self.headers.get_all("Authorization", [])
            pins = self.headers.get_all("X-Workspace-Instance", [])
            if len(authorizations) > 1 or len(pins) > 1:
                self._reply(400, {"error": "AMBIGUOUS_CREDENTIALS"})
                return False
            auth = authorizations[0] if authorizations else ""
            provided = auth[7:] if auth.startswith("Bearer ") else ""
            if not secrets.compare_digest(provided, service.token):
                self._reply(401, {"error": "UNAUTHORIZED"})
                return False
            if (pins[0] if pins else None) != service.instance_id:
                self._reply(409, {"error": "WRONG_INSTANCE"})
                return False
            return True

        def _conversation_scope(self):
            grants = self.headers.get_all("X-Workspace-Draft-Grant", [])
            if len(grants) != 1:
                self._reply(403, {"error": "DRAFT_GRANT_REQUIRED"})
                return None
            try:
                return service.conversation_scope(grants[0])
            except PermissionError:
                self._reply(403, {"error": "DRAFT_GRANT_DENIED"})
            except (ValueError, OSError, UnicodeError):
                self._reply(503, {"error": "PROJECT_SOURCE_UNAVAILABLE"})
            return None

        def _conversation_get(self, path):
            scope = self._conversation_scope()
            if scope is None:
                return
            try:
                result = (service.conversations.list(scope) if path == "/v1/conversations" else
                          service.conversations.get(scope, path.rsplit("/", 1)[1]))
            except FileNotFoundError:
                return self._reply(404, {"error": "NOT_FOUND"})
            except (ValueError, OSError, sqlite3.Error):
                return self._reply(503, {"error": "CONVERSATIONS_UNAVAILABLE"})
            self._reply(200, result)

        def _conversation_write(self, path):
            if not self._pinned_auth():
                return
            scope = self._conversation_scope()
            if scope is None:
                return
            lengths = self.headers.get_all("Content-Length", [])
            if (len(lengths) != 1 or not lengths[0].isdecimal() or
                    not 1 <= int(lengths[0]) <= 48_000 or self.headers.get("Transfer-Encoding") or
                    self.headers.get("Content-Type", "").split(";", 1)[0].lower() != "application/json"):
                return self._reply(400, {"error": "INVALID_BODY"})
            try:
                body = json.loads(self.rfile.read(int(lengths[0])), object_pairs_hook=_unique_json_object)
            except (ValueError, UnicodeError, RecursionError):
                return self._reply(400, {"error": "INVALID_BODY"})
            try:
                if self.command == "POST":
                    result = service.conversations.create(scope, body)
                    code = 201
                else:
                    result = service.conversations.update(scope, path.rsplit("/", 1)[1], body)
                    code = 200
            except ConversationConflict:
                return self._reply(409, {"error": "DRAFT_CONFLICT"})
            except FileNotFoundError:
                return self._reply(404, {"error": "NOT_FOUND"})
            except ValueError:
                return self._reply(400, {"error": "INVALID_BODY"})
            except (OSError, sqlite3.Error):
                return self._reply(503, {"error": "CONVERSATIONS_UNAVAILABLE"})
            self._reply(code, result)

        def do_GET(self):
            if not self._trusted_origin():
                return
            target = self.requestline.split()[1]
            # Only literal origin-form paths are accepted; URL parsing can raise
            # on malformed authority targets before they reach the 400 response.
            if (not target.startswith("/") or target.startswith("//") or
                    "?" in target or "#" in target or "%" in target or ".." in target):
                return self._reply(400, {"error": "INVALID_PATH"})
            path = target
            if path == "/":
                html = importlib.resources.files("workspace_control").joinpath("client.html").read_bytes()
                return self._reply(200, html, "text/html; charset=utf-8")
            if path == "/client.js":
                script = importlib.resources.files("workspace_control").joinpath("client.js").read_bytes()
                return self._reply(200, script, "text/javascript; charset=utf-8")
            if path == "/client.css":
                style = importlib.resources.files("workspace_control").joinpath("client.css").read_bytes()
                return self._reply(200, style, "text/css; charset=utf-8")
            if path == "/v1/identity":
                return self._reply(200, {"instance_id": service.instance_id})
            if path == "/v1/conversations/openapi.json":
                if self._pinned_auth():
                    return self._reply(200, draft_openapi_contract())
                return
            conversation = path == "/v1/conversations" or re.fullmatch(r"/v1/conversations/[0-9a-f]{32}", path)
            if path not in ROUTES and not conversation:
                return self._reply(404, {"error": "NOT_FOUND"})
            if not self._pinned_auth():
                return
            if conversation:
                return self._conversation_get(path)
            try:
                if path == "/v1/status":
                    result = service.status()
                elif path == "/v1/projects":
                    result = service.projects()
                elif path == "/v1/openapi.json":
                    if public_host is None:
                        result = openapi_contract()
                    else:
                        port = self.server.server_port
                        authority = public_host if port == 443 else f"{public_host}:{port}"
                        result = openapi_contract(f"https://{authority}")
                elif path == "/v1/forge/status":
                    result = service.forge_status()
                else:
                    result = operation_inventory(service.instance_id)
            except (ValueError, OSError, UnicodeError):
                return self._reply(503, {"error": "SOURCE_UNAVAILABLE"})
            return self._reply(200, result)

        def do_POST(self):
            if not self._trusted_origin():
                return
            if self.path == "/v1/conversations":
                return self._conversation_write(self.path)
            self._reply(405, {"error": "READ_ONLY"})

        def _read_only_method(self):
            if not self._trusted_origin():
                return
            self._reply(405, {"error": "READ_ONLY"})

        do_PUT = _read_only_method
        def do_PATCH(self):
            if not self._trusted_origin():
                return
            if re.fullmatch(r"/v1/conversations/[0-9a-f]{32}", self.path):
                return self._conversation_write(self.path)
            self._reply(405, {"error": "READ_ONLY"})
        do_DELETE = _read_only_method
        do_HEAD = do_GET
        do_OPTIONS = _read_only_method
        do_TRACE = _read_only_method
        do_CONNECT = _read_only_method

    return Handler


def _validate_bind(bind):
    try:
        address = ipaddress.IPv4Address(bind)
    except ipaddress.AddressValueError as exc:
        raise ValueError("bind must be an explicit IPv4 address") from exc
    if address.is_unspecified or address.is_multicast or address.is_reserved or (
            address.is_loopback and bind != "127.0.0.1"):
        raise ValueError("bind must name one concrete supported interface")


def _validate_server_name(server_name):
    if (not isinstance(server_name, str) or len(server_name) > 253 or
            not all(1 <= len(label) <= 63 and
                    re.fullmatch(r"[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?", label)
                    for label in server_name.split("."))):
        raise ValueError("server name must be one DNS name or IPv4 address")


def _validate_tls_file(path, private):
    if not os.path.isabs(path):
        raise ValueError("TLS certificate and key paths must be absolute")
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("TLS files must be owner-held regular files, not symlinks")
    if private and info.st_mode & 0o077:
        raise ValueError("TLS private key must not be group/world accessible")


def listener_config(bind, server_name=None, cert_file=None, key_file=None):
    """Reject accidental plaintext exposure and ambiguous TLS authority."""
    _validate_bind(bind)
    tls_values = (server_name, cert_file, key_file)
    if any(tls_values) and not all(tls_values):
        raise ValueError("TLS requires server name, certificate and private key together")
    if bind != "127.0.0.1" and not all(tls_values):
        raise ValueError("nonloopback binding requires TLS")
    if not any(tls_values):
        return None
    _validate_server_name(server_name)
    _validate_tls_file(cert_file, private=False)
    _validate_tls_file(key_file, private=True)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certfile=cert_file, keyfile=key_file)
    return context


def serve(root, port, *, bind="127.0.0.1", server_name=None, cert_file=None, key_file=None):
    context = listener_config(bind, server_name, cert_file, key_file)
    with Service(root) as service:
        descriptor = os.open("server.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                             0o600, dir_fd=service._root_fd)
        with os.fdopen(descriptor, "r+") as lock:
            info = os.fstat(lock.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise ValueError("server lock must be a private regular file")
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise ValueError("instance already served") from exc
            handler = handler_for(service, public_host=server_name.lower() if context else None,
                                  scheme="https" if context else "http")
            server = ThreadingHTTPServer((bind, port), handler)
            server.daemon_threads = False
            try:
                if context:
                    server.socket = context.wrap_socket(server.socket, server_side=True,
                                                        do_handshake_on_connect=False)
                server.serve_forever(poll_interval=0.1)
            finally:
                server.server_close()
