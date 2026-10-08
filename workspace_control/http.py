"""Authenticated and versioned Workspace HTTP ingress with explicit TLS binding."""

import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer as BaseThreadingHTTPServer
import importlib.resources
import ipaddress
import json
import os
import re
import secrets
from urllib.parse import urlsplit, parse_qs
import sqlite3
import ssl
import stat
import sys

from . import __version__
from .schemas import OPENAPI_SCHEMAS, SUCCESS_SCHEMA
from .service import Service, _unique_json_object
from .conversations import ConversationConflict
from .review_peer import ReviewError
from .worklist_peer import WorklistError


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
    "conversations.archive": {"exposure": "HTTP_EXPOSED", "method": "POST",
                              "path": "/v1/conversations/{id}/archive",
                              "auth": "BEARER_PINNED_AND_DRAFT_GRANT", "contract": "draft",
                              "summary": "archive own conversation navigation at revision"},
    "conversations.restore": {"exposure": "HTTP_EXPOSED", "method": "POST",
                              "path": "/v1/conversations/{id}/restore",
                              "auth": "BEARER_PINNED_AND_DRAFT_GRANT", "contract": "draft",
                              "summary": "restore own conversation navigation at revision"},
    "reviews.contract.read": {"exposure": "HTTP_EXPOSED", "method": "GET",
                              "path": "/v1/reviews/openapi.json", "auth": "BEARER_PINNED",
                              "contract": "review", "summary": "own review transport contract"},
    "reviews.list": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/reviews",
                     "auth": "BEARER_PINNED_AND_REVIEW_GRANT", "contract": "review",
                     "summary": "actor-scoped Forge Mission reviews"},
    "reviews.get": {"exposure": "HTTP_EXPOSED", "method": "GET",
                    "path": "/v1/reviews/missions/{mission_id}",
                    "auth": "BEARER_PINNED_AND_REVIEW_GRANT", "contract": "review",
                    "summary": "one authorized Mission review"},
    "reviews.submit": {"exposure": "HTTP_EXPOSED", "method": "POST",
                       "path": "/v1/reviews/missions/{mission_id}/decisions",
                       "auth": "BEARER_PINNED_AND_REVIEW_GRANT", "contract": "review",
                       "summary": "one exact Forge review decision"},
    "reviews.operation": {"exposure": "HTTP_EXPOSED", "method": "GET",
                          "path": "/v1/reviews/missions/{mission_id}/decisions/{operation_id}",
                          "auth": "BEARER_PINNED_AND_REVIEW_GRANT", "contract": "review",
                          "summary": "same actor Forge decision readback"},
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
    "worksets.contract.read": {"exposure": "HTTP_EXPOSED", "method": "GET",
                              "path": "/v1/worksets/openapi.json", "auth": "BEARER_PINNED",
                              "contract": "worklist", "summary": "own scoped worklist read contract"},
    "worksets.scopes": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/worksets",
                        "auth": "BEARER_PINNED_AND_WORKLIST_GRANT", "contract": "worklist",
                        "summary": "exact granted Forge worksets"},
    "worksets.get": {"exposure": "HTTP_EXPOSED", "method": "GET", "path": "/v1/worksets/{workset_id}",
                     "auth": "BEARER_PINNED_AND_WORKLIST_GRANT", "contract": "worklist",
                     "summary": "one coherent approved worklist snapshot"},
    "worksets.bind.issue": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "worklist-bind-issue",
                            "auth": "PRIVATE_ROOT_OWNER", "summary": "bind actor and workset read grant"},
    "worksets.bind.revoke": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "worklist-bind-revoke",
                             "auth": "PRIVATE_ROOT_OWNER", "summary": "revoke own workset read binding"},
    "workset-controls.contract.read": {"exposure":"HTTP_EXPOSED", "method":"GET", "path":"/v1/workset-controls/openapi.json", "auth":"BEARER_PINNED", "contract":"worklist-control", "summary":"scoped hold contract"},
    "workset-controls.scopes": {"exposure":"HTTP_EXPOSED", "method":"GET", "path":"/v1/workset-controls", "auth":"BEARER_PINNED_AND_WORKLIST_CONTROL_GRANT", "contract":"worklist-control", "summary":"explicit live command scopes"},
    "workset-controls.get": {"exposure":"HTTP_EXPOSED", "method":"GET", "path":"/v1/workset-controls/{workset_id}", "auth":"BEARER_PINNED_AND_WORKLIST_CONTROL_GRANT", "contract":"worklist-control", "summary":"current scoped hold readback"},
    "workset-controls.submit": {"exposure":"HTTP_EXPOSED", "method":"POST", "path":"/v1/workset-controls/{workset_id}/commands", "auth":"BEARER_PINNED_AND_WORKLIST_CONTROL_GRANT", "contract":"worklist-control", "summary":"explicit hold or exact own unhold"},
    "workset-controls.operation": {"exposure":"HTTP_EXPOSED", "method":"GET", "path":"/v1/workset-controls/{workset_id}/commands/{operation_id}", "auth":"BEARER_PINNED_AND_WORKLIST_CONTROL_GRANT", "contract":"worklist-control", "summary":"same-operation original receipt and current state"},
    "workset-controls.bind.issue": {"exposure":"LOCAL_ONLY_ADMIN", "local_cli":"worklist-control-bind-issue", "auth":"PRIVATE_ROOT_OWNER", "summary":"bind separate scoped command capability"},
    "workset-controls.bind.revoke": {"exposure":"LOCAL_ONLY_ADMIN", "local_cli":"worklist-control-bind-revoke", "auth":"PRIVATE_ROOT_OWNER", "summary":"revoke own command binding"},
    "reviews.bind.issue": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "review-bind-issue",
                           "auth": "PRIVATE_ROOT_OWNER", "summary": "bind actor and scoped Forge review grant"},
    "reviews.bind.revoke": {"exposure": "LOCAL_ONLY_ADMIN", "local_cli": "review-bind-revoke",
                            "auth": "PRIVATE_ROOT_OWNER", "summary": "revoke Workspace actor review binding"},
}
for key, method, path in [
    ("access", "GET", "/v1/advisory/access"), ("capability", "GET", "/v1/advisory/capability"),
    ("history", "GET", "/v1/advisory/{conversation_id}"),
    ("submit", "POST", "/v1/advisory/{conversation_id}/turns"),
    ("turn", "GET", "/v1/advisory/{conversation_id}/turns/{turn_id}"),
    ("cancel", "POST", "/v1/advisory/{conversation_id}/turns/{turn_id}/cancel")]:
    OPERATIONS["advisory."+key] = {"exposure":"HTTP_EXPOSED", "method":method, "path":path,
        "auth":"BEARER_PINNED_AND_DRAFT_AND_ADVISORY_GRANT", "contract":"advisory", "summary":"scoped textual advice"}
OPERATIONS["advisory.contract.read"]={"exposure":"HTTP_EXPOSED","method":"GET","path":"/v1/advisory/openapi.json","auth":"BEARER_PINNED","contract":"advisory","summary":"closed advisory contract"}
for key in ["issue", "revoke"]:
    OPERATIONS["advisory.bind."+key]={"exposure":"LOCAL_ONLY_ADMIN","local_cli":"advisory-bind-"+key,"auth":"PRIVATE_ROOT_OWNER","summary":"private owner advisory binding"}

for key, method, path in [
    ("access", "GET", "/v1/advisory-candidates/access"),
    ("capability", "GET", "/v1/advisory-candidates/capability"),
    ("source", "GET", "/v1/advisory-candidates/{conversation_id}/source/{turn_id}"),
    ("save", "POST", "/v1/advisory-candidates/{conversation_id}/proposals"),
    ("preview", "GET", "/v1/advisory-candidates/{conversation_id}/proposals/{proposal_id}"),
    ("register", "POST", "/v1/advisory-candidates/{conversation_id}/proposals/{proposal_id}/registrations"),
    ("operation", "GET", "/v1/advisory-candidates/{conversation_id}/proposals/{proposal_id}/registrations/{operation_id}")]:
    OPERATIONS["candidate."+key]={"exposure":"HTTP_EXPOSED","method":method,"path":path,
        "auth":"BEARER_PINNED_AND_DRAFT_AND_CANDIDATE_GRANT","contract":"candidate","summary":"explicit unapproved Candidate proposal and registration"}
for key in ["issue", "revoke"]:
    OPERATIONS["candidate.bind."+key]={"exposure":"LOCAL_ONLY_ADMIN","local_cli":"candidate-bind-"+key,"auth":"PRIVATE_ROOT_OWNER","summary":"private owner Candidate binding"}

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
    archive = {"type": "object", "additionalProperties": False,
               "required": ["expected_revision", "operation_id"],
               "properties": {"expected_revision": {"type": "integer", "minimum": 1},
                              "operation_id": {"type": "string", "pattern": "^[0-9a-f]{32}$"}}}
    record = {"type": "object", "additionalProperties": False,
              "required": ["id", "actor_id", "project_id", *fields, "archived", "revision", "created_at",
                           "updated_at", "history", "history_availability", "state"],
              "properties": {"id": {"type": "string", "pattern": "^[0-9a-f]{32}$"},
                             "actor_id": {"type": "string"}, "project_id": {"type": "string"},
                             **fields, "archived": {"type": "boolean"},
                             "revision": {"type": "integer", "minimum": 1},
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
                            "ArchiveCommand": archive,
                            "Conversation": record, "ConversationList": listing}},
            "paths": {"/v1/conversations": {
                "get": operation("conversations.list", 200),
                "post": operation("conversations.create", 201, request="DraftCreate")},
                "/v1/conversations/{id}": {
                    "get": operation("conversations.get", 200, item=True),
                    "patch": operation("conversations.update", 200, request="DraftUpdate", item=True)},
                "/v1/conversations/{id}/archive": {
                    "post": operation("conversations.archive", 200, request="ArchiveCommand", item=True)},
                "/v1/conversations/{id}/restore": {
                    "post": operation("conversations.restore", 200, request="ArchiveCommand", item=True)}}}


def review_openapi_contract():
    """Describe the own actor transport; Forge's pinned schema remains authoritative."""
    schema = {"type": "object", "additionalProperties": False,
              "required": ["contract_version", "operation_id", "requirement_id", "subject_digest",
                           "mission_state_revision", "evidence_digest", "policy_revision",
                           "decision", "reason"],
              "properties": {"contract_version": {"const": "forge-workspace-review-decision/v1"},
                             "operation_id": {"type": "string", "maxLength": 128},
                             "requirement_id": {"type": "string", "maxLength": 128},
                             "subject_digest": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
                             "mission_state_revision": {"type": "integer", "minimum": 1},
                             "evidence_digest": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
                             "policy_revision": {"type": "string", "minLength": 1, "maxLength": 128},
                             "decision": {"enum": ["approve", "reject", "amend", "defer"]},
                             "reason": {"type": "string", "minLength": 1, "maxLength": 512}}}
    def operation(name, *, request=False):
        result = {"operationId": name,
                  "security": [{"bearerAuth": [], "reviewGrant": []}],
                  "parameters": [{"name": "X-Workspace-Instance", "in": "header", "required": True,
                                  "schema": {"type": "string"}}],
                  "responses": {"200": {"description": "Validated Forge readback"},
                                "400": {"description": "Invalid request"},
                                "401": {"description": "Workspace or Forge bearer denied"},
                                "403": {"description": "Actor or Mission denied"},
                                "404": {"description": "Operation not found for actor"},
                                "409": {"description": "Wrong instance or conflicting intent"},
                                "503": {"description": "Forge or local transport unavailable"}}}
        if request:
            result["requestBody"] = {"required": True, "content": {"application/json": {"schema": schema}}}
            result["responses"]["201"] = {"description": "Canonical Forge decision recorded"}
        return result
    return {"openapi": "3.0.3",
            "info": {"title": "Workspace actor-bound Mission review transport V1", "version": "1",
                     "description": "Forge producer pinned to f4d3b269d54fd302a586cd8f41421c4d15e8c4d5"},
            "components": {"securitySchemes": {
                "bearerAuth": {"type": "http", "scheme": "bearer"},
                "reviewGrant": {"type": "apiKey", "in": "header", "name": "X-Workspace-Review-Grant"}}},
            "paths": {"/v1/reviews": {"get": operation("reviews.list")},
                      "/v1/reviews/missions/{mission_id}": {"get": operation("reviews.get")},
                      "/v1/reviews/missions/{mission_id}/decisions": {
                          "post": operation("reviews.submit", request=True)},
                      "/v1/reviews/missions/{mission_id}/decisions/{operation_id}": {
                          "get": operation("reviews.operation")}}}


def worklist_openapi_contract():
    document = {"openapi": "3.0.3", "info": {"title": "Workspace scoped worklist read V1", "version": "1"},
            "components": {"securitySchemes": {
                "bearerAuth": {"type": "http", "scheme": "bearer"},
                "worklistGrant": {"type": "apiKey", "in": "header", "name": "X-Workspace-Worklist-Grant"}}},
            "paths": {"/v1/worksets": {"get": {
                "operationId": "worksets.scopes",
                "security": [{"bearerAuth": [], "worklistGrant": []}],
                "parameters": [{"name": "X-Workspace-Instance", "in": "header", "required": True,
                                "schema": {"type": "string"}}],
                "responses": {"200": {"description": "Exact granted Forge instance/actor/workset IDs"},
                              "401": {"description": "Unauthorized or expired/revoked producer grant"},
                              "403": {"description": "Denied worklist capability"},
                              "409": {"description": "Wrong pinned Workspace instance"},
                              "503": {"description": "Unavailable or invalid producer readback"}}}}}}
    projection = json.loads(json.dumps(document["paths"]["/v1/worksets"]))
    projection["get"]["operationId"] = "worksets.get"
    projection["get"]["parameters"].append({"name": "workset_id", "in": "path", "required": True,
                                             "schema": {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"}})
    projection["get"]["responses"]["200"]["description"] = "Exact scoped Forge worklist snapshot and typed proof references"
    document["paths"]["/v1/worksets/{workset_id}"] = projection
    return document


def worklist_control_openapi_contract():
    from .worklist_control_contract import REQUEST_KEYS
    request_properties = {key: {"type":"string"} for key in REQUEST_KEYS}
    request_properties.update({"expected_revision":{"type":"integer", "minimum":1},
        "expected_hold_revision":{"type":"integer", "minimum":1, "nullable":True},
        "hold_operation_id":{"type":"string", "nullable":True},
        "intent":{"type":"string", "enum":["hold", "unhold"]},
        "reason_code":{"type":"string", "enum":["USER_REQUEST", "TEMPORARY_WAIT"]}})
    document = {"openapi":"3.0.3", "info":{"title":"Workspace scoped hold capability V1", "version":"1"},
        "components":{"securitySchemes":{"bearerAuth":{"type":"http", "scheme":"bearer"},
            "controlGrant":{"type":"apiKey", "in":"header", "name":"X-Workspace-Worklist-Control-Grant"}}}, "paths":{}}
    for name, details in OPERATIONS.items():
        if details.get("contract") != "worklist-control" or name.endswith("contract.read"):
            continue
        operation = {"operationId":name, "security":[{"bearerAuth":[], "controlGrant":[]}],
                     "responses":{"200":{"description":"Verified scoped original receipt and separate current readback"},
                                  "403":{"description":"Denied command capability"}, "409":{"description":"Stale or conflicting command"}}}
        if details["method"] == "POST":
            operation["requestBody"] = {"required":True, "content":{"application/json":{"schema":{
                "type":"object", "additionalProperties":False, "required":sorted(REQUEST_KEYS), "properties":request_properties}}}}
        document["paths"][details["path"]] = {details["method"].lower():operation}
    return document


def advisory_openapi_contract():
    from .advisory_contract import SCHEMA
    return {"openapi":"3.0.3", "info":{"title":"Workspace advisory transport V1", "version":"1"},
        "x-forge-wire-schema":SCHEMA,
        "paths":{op["path"]:{op["method"].lower():{"operationId":key,"responses":{"200":{"description":"Verified textual advisory readback"}}}}
                 for key,op in OPERATIONS.items() if op.get("contract")=="advisory" and key!="advisory.contract.read"}}


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
                    match = re.fullmatch(r"/v1/conversations/([0-9a-f]{32})/(archive|restore)", path)
                    if match:
                        result = service.conversations.set_archived(
                            scope, match[1], body, archived=match[2] == "archive")
                        code = 200
                    else:
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

        def _advisory_route(self, *, write=False):
            if not self._pinned_auth(): return
            scope=self._conversation_scope()
            if scope is None:return
            tokens=self.headers.get_all("X-Workspace-Advisory-Grant",[])
            if len(tokens)!=1:return self._reply(403,{"error":"ADVISORY_GRANT_REQUIRED"})
            try:
                b=service.advisory.access(tokens[0]);service.advisory.bound(b,scope)
                parsed=urlsplit(self.path);parts=parsed.path.split('/');query=parse_qs(parsed.query,keep_blank_values=True,max_num_fields=4)
                if parsed.path=='/v1/advisory/access' and not write and not query:
                    result=service.advisory.metadata(b,scope)
                elif parsed.path=='/v1/advisory/capability' and not write:
                    if set(query)-{'source_id','source_version'} or len(query.get('source_id',[]))!=len(query.get('source_version',[])):raise WorklistError('INVALID_REQUEST')
                    selections=[{'source_id':k,'version':v} for k,v in zip(query.get('source_id',[]),query.get('source_version',[]))]
                    result=service.advisory.capability(b,selections)
                else:
                    c=parts[3];service.advisory.bound(b,scope,c)
                    if write:
                        if query:raise WorklistError('INVALID_REQUEST')
                        lengths=self.headers.get_all('Content-Length',[])
                        if len(lengths)!=1 or not lengths[0].isdecimal() or not 1<=int(lengths[0])<=16000 or self.headers.get('Transfer-Encoding') or self.headers.get('Content-Type','').split(';',1)[0].lower()!='application/json':raise WorklistError('INVALID_REQUEST')
                        try:body=json.loads(self.rfile.read(int(lengths[0])),object_pairs_hook=_unique_json_object)
                        except (ValueError,UnicodeError,RecursionError):raise WorklistError('INVALID_REQUEST') from None
                        authority=service.advisory_forward_scope(self.headers['X-Workspace-Draft-Grant'],scope)
                        result=(service.advisory.submit(b,c,body,authority=authority) if len(parts)==5 else service.advisory.cancel(b,c,parts[5],body,authority=authority))
                    elif len(parts)==4:
                        if set(query)-{'cursor','limit'} or any(len(v)!=1 for v in query.values()):raise WorklistError('INVALID_REQUEST')
                        try:cursor=int(query.get('cursor',['0'])[0]);limit=int(query.get('limit',['4'])[0])
                        except ValueError:raise WorklistError('INVALID_REQUEST') from None
                        result=service.advisory.history(b,c,cursor,limit)
                    else:
                        if query:raise WorklistError('INVALID_REQUEST')
                        result=service.advisory.turn(b,c,parts[5])
            except WorklistError as error:
                state=error.state
                code=403 if state=='DENIED' else 404 if state=='ADVISORY_NOT_FOUND' else 400 if state in ('INVALID_REQUEST','ADVISOR_UNSUPPORTED','ADVISORY_REQUEST_INVALID') else 409 if state in ('ADVISORY_CONFLICT','CONVERSATION_BUSY','TURN_PAYLOAD_CONFLICT','CONVERSATION_OR_CONTEXT_STALE','INVOCATION_UNRESOLVED','TURN_BUDGET_EXHAUSTED','TRANSCRIPT_CAPACITY_EXHAUSTED','CONVERSATION_CAPACITY_EXHAUSTED','CANCEL_PRECONDITION_CHANGED','CONTEXT_STALE') else 503
                return self._reply(code,{"error":state})
            except FileNotFoundError:return self._reply(404,{"error":"ADVISORY_NOT_FOUND"})
            except (ValueError,OSError,UnicodeError,sqlite3.Error):return self._reply(503,{"error":"ADVISORY_UNAVAILABLE"})
            if self._conversation_scope()!=scope:return
            self._reply(200,result)

        def _candidate_route(self, *, write=False):
            if not self._pinned_auth():return
            scope=self._conversation_scope()
            if scope is None:return
            tokens=self.headers.get_all("X-Workspace-Candidate-Grant",[])
            if len(tokens)!=1:return self._reply(403,{"error":"CANDIDATE_GRANT_REQUIRED"})
            try:
                b=service.candidates.access(tokens[0]);service.candidates.bound(b,scope)
                parsed=urlsplit(self.path);parts=parsed.path.split('/');query=parse_qs(parsed.query,keep_blank_values=True,max_num_fields=2)
                if parts[-1] in ('access','capability'):
                    if write or query:raise WorklistError('INVALID_REQUEST')
                    result=service.candidates.metadata(b,scope) if parts[-1]=='access' else service.candidates.capability(b)
                else:
                    c=parts[3];service.candidates.bound(b,scope,c)
                    if write:
                        if query:raise WorklistError('INVALID_REQUEST')
                        lengths=self.headers.get_all('Content-Length',[])
                        if len(lengths)!=1 or not lengths[0].isdecimal() or not 1<=int(lengths[0])<=65536 or self.headers.get('Transfer-Encoding') or self.headers.get('Content-Type','').split(';',1)[0].lower()!='application/json':raise WorklistError('INVALID_REQUEST')
                        try:body=json.loads(self.rfile.read(int(lengths[0])),object_pairs_hook=_unique_json_object)
                        except (ValueError,UnicodeError,RecursionError):raise WorklistError('INVALID_REQUEST') from None
                        registering=len(parts)==7
                        if registering and (not isinstance(body,dict) or body.get('proposal_id')!=parts[5]):raise WorklistError('INVALID_REQUEST')
                        authority=service.advisory_forward_scope(self.headers['X-Workspace-Draft-Grant'],scope)
                        result=service.candidates.command(b,c,body,registration=registering,authority=authority)
                    elif parts[4]=='source':
                        if query:raise WorklistError('INVALID_REQUEST')
                        result=service.candidates.source(b,c,parts[5])
                    elif len(parts)==6:
                        if set(query)!={'revision'} or len(query['revision'])!=1:raise WorklistError('INVALID_REQUEST')
                        try:revision=int(query['revision'][0])
                        except ValueError:raise WorklistError('INVALID_REQUEST') from None
                        result=service.candidates.preview(b,c,parts[5],revision)
                    else:
                        if query:raise WorklistError('INVALID_REQUEST')
                        result=service.candidates.operation(b,c,parts[5],parts[7])
            except WorklistError as error:
                state=error.state
                code=403 if state=='DENIED' else 404 if state in ('CANDIDATE_SUBJECT_NOT_FOUND','CANDIDATE_NOT_FOUND','PROPOSAL_NOT_FOUND','REGISTRATION_NOT_FOUND','ADVISORY_NOT_FOUND') else 400 if state=='INVALID_REQUEST' or state.endswith('_INVALID') else 409 if any(x in state for x in ('CONFLICT','STALE','PENDING','BUSY','BUDGET','CAPACITY','KEY','REVISION','CONTEXT_CHANGED','NOT_COMPLETE')) else 503
                return self._reply(code,{"error":state})
            except FileNotFoundError:return self._reply(404,{"error":"CANDIDATE_NOT_FOUND"})
            except (ValueError,OSError,UnicodeError,sqlite3.Error):return self._reply(503,{"error":"CANDIDATE_UNAVAILABLE"})
            if self._conversation_scope()!=scope:return
            try:service.candidates.access(tokens[0])
            except WorklistError:return self._reply(403,{"error":"DENIED"})
            self._reply(200,result)

        def _worklist_error(self, error):
            code = {"UNAUTHORIZED": 401, "DENIED": 403, "NOT_FOUND": 404,
                    "CONFLICT": 409}.get(error.state, 503)
            self._reply(code, {"error": "WORKLIST_" + error.state})

        def _worklist_get(self, path):
            grants = self.headers.get_all("X-Workspace-Worklist-Grant", [])
            if len(grants) != 1:
                return self._reply(403, {"error": "WORKLIST_GRANT_REQUIRED"})
            try:
                binding = service.worklists.access(grants[0])
                result = (service.worklists.scopes(binding) if path == "/v1/worksets" else
                          service.worklists.projection(binding, path.rsplit("/", 1)[1]))
            except WorklistError as error:
                return self._worklist_error(error)
            except (OSError, ValueError, UnicodeError):
                return self._reply(503, {"error": "WORKLIST_UNAVAILABLE"})
            self._reply(200, result)

        def _control_route(self, path, *, write=False):
            if not self._pinned_auth():
                return
            grants = self.headers.get_all("X-Workspace-Worklist-Control-Grant", [])
            if len(grants) != 1:
                return self._reply(403, {"error": "WORKLIST_CONTROL_DENIED"})
            try:
                binding = service.worklist_controls.access(grants[0])
                parts = path.split("/")
                if path == "/v1/workset-controls" and not write:
                    result = service.worklist_controls.scopes(binding)
                elif write:
                    lengths = self.headers.get_all("Content-Length", [])
                    if (len(lengths) != 1 or not lengths[0].isdecimal() or
                            not 1 <= int(lengths[0]) <= 4096 or self.headers.get("Transfer-Encoding") or
                            self.headers.get("Content-Type", "").split(";", 1)[0].lower() != "application/json"):
                        return self._reply(400, {"error": "INVALID_BODY"})
                    try:
                        body = json.loads(self.rfile.read(int(lengths[0])), object_pairs_hook=_unique_json_object)
                    except (ValueError, UnicodeError, RecursionError):
                        return self._reply(400, {"error": "INVALID_BODY"})
                    result = service.worklist_controls.submit(binding, parts[3], body)
                else:
                    result = service.worklist_controls.readback(binding, parts[3], parts[5] if len(parts) == 6 else None)
            except WorklistError as error:
                code = {"DENIED":403, "UNAUTHORIZED":401, "NOT_FOUND":404, "CONFLICT":409,
                        "INVALID_REQUEST":400}.get(error.state, 503)
                return self._reply(code, {"error": "WORKLIST_CONTROL_" + error.state})
            except (OSError, ValueError, UnicodeError):
                return self._reply(503, {"error": "WORKLIST_CONTROL_UNAVAILABLE"})
            return self._reply(200, result)

        def _review_binding(self):
            grants = self.headers.get_all("X-Workspace-Review-Grant", [])
            if len(grants) != 1:
                self._reply(403, {"error": "REVIEW_GRANT_REQUIRED"})
                return None
            try:
                return service.reviews.access(grants[0])
            except ReviewError as exc:
                self._review_error(exc)
                return None
            except (OSError, UnicodeError):
                self._reply(503, {"error": "REVIEW_UNAVAILABLE"})
                return None

        def _review_error(self, exc):
            code = {"INVALID_REQUEST": 400, "UNAUTHORIZED": 401, "DENIED": 403,
                    "NOT_FOUND": 404, "CONFLICT": 409}.get(exc.state, 503)
            self._reply(code, {"error": "REVIEW_" + exc.state})

        def _review_get(self, path):
            binding = self._review_binding()
            if binding is None:
                return
            mission = re.fullmatch(r"/v1/reviews/missions/([A-Za-z0-9][A-Za-z0-9._:-]{0,127})", path)
            operation = re.fullmatch(
                r"/v1/reviews/missions/([A-Za-z0-9][A-Za-z0-9._:-]{0,127})/decisions/"
                r"([A-Za-z0-9][A-Za-z0-9._:-]{0,127})", path)
            try:
                if path == "/v1/reviews":
                    result = service.reviews.inbox(binding)
                elif mission:
                    result = service.reviews.item(binding, mission[1])
                else:
                    result = service.reviews.readback(binding, operation[1], operation[2])
            except ReviewError as exc:
                return self._review_error(exc)
            except (OSError, sqlite3.Error, UnicodeError):
                return self._reply(503, {"error": "REVIEW_UNAVAILABLE"})
            self._reply(200, result)

        def _review_write(self, path):
            if not self._pinned_auth():
                return
            binding = self._review_binding()
            if binding is None:
                return
            mission = re.fullmatch(
                r"/v1/reviews/missions/([A-Za-z0-9][A-Za-z0-9._:-]{0,127})/decisions", path)
            if mission[1] not in binding["mission_ids"]:
                return self._reply(403, {"error": "REVIEW_DENIED"})
            lengths = self.headers.get_all("Content-Length", [])
            if (len(lengths) != 1 or not lengths[0].isdecimal() or
                    not 1 <= int(lengths[0]) <= 4096 or self.headers.get("Transfer-Encoding") or
                    self.headers.get("Content-Type", "").split(";", 1)[0].lower() != "application/json"):
                return self._reply(400, {"error": "INVALID_BODY"})
            try:
                body = json.loads(self.rfile.read(int(lengths[0])), object_pairs_hook=_unique_json_object)
            except (ValueError, UnicodeError, RecursionError):
                return self._reply(400, {"error": "INVALID_BODY"})
            try:
                code, result = service.reviews.submit(binding, mission[1], body)
            except ReviewError as exc:
                return self._review_error(exc)
            except (OSError, sqlite3.Error, UnicodeError):
                return self._reply(503, {"error": "REVIEW_UNAVAILABLE"})
            self._reply(code, result)

        def do_GET(self):
            if not self._trusted_origin():
                return
            target = self.requestline.split()[1]
            if target.startswith("/v1/advisory-candidates/"):
                parsed=urlsplit(target);ident=r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}"
                if parsed.fragment or '%' in parsed.path or '..' in parsed.path or not re.fullmatch(r"/v1/advisory-candidates/(?:access|capability|[0-9a-f]{32}/(?:source/"+ident+r"|proposals/"+ident+r"(?:/registrations/"+ident+r")?))",parsed.path):return self._reply(400,{"error":"INVALID_PATH"})
                return self._candidate_route()
            if target.startswith("/v1/advisory/"):
                parsed=urlsplit(target)
                path=parsed.path
                if parsed.fragment or '%' in path or '..' in path or not re.fullmatch(r"/v1/advisory/(?:access|capability|openapi.json|[0-9a-f]{32}(?:/turns/[A-Za-z0-9][A-Za-z0-9._:-]{0,127})?)",path):
                    return self._reply(400,{"error":"INVALID_PATH"})
                if path=="/v1/advisory/openapi.json":
                    if self._pinned_auth():return self._reply(200,advisory_openapi_contract())
                    return
                return self._advisory_route()
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
            if path == "/v1/reviews/openapi.json":
                if self._pinned_auth():
                    return self._reply(200, review_openapi_contract())
                return
            if path == "/v1/worksets/openapi.json":
                if self._pinned_auth():
                    return self._reply(200, worklist_openapi_contract())
                return
            if path == "/v1/workset-controls/openapi.json":
                if self._pinned_auth():
                    return self._reply(200, worklist_control_openapi_contract())
                return
            conversation = path == "/v1/conversations" or re.fullmatch(r"/v1/conversations/[0-9a-f]{32}", path)
            review = (path == "/v1/reviews" or
                      re.fullmatch(r"/v1/reviews/missions/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", path) or
                      re.fullmatch(r"/v1/reviews/missions/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}/decisions/"
                                   r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", path))
            worklist = path == "/v1/worksets" or re.fullmatch(r"/v1/worksets/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", path)
            control = path == "/v1/workset-controls" or re.fullmatch(
                r"/v1/workset-controls/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}(?:/commands/[A-Za-z0-9][A-Za-z0-9._:-]{0,127})?", path)
            if path not in ROUTES and not conversation and not review and not worklist and not control:
                return self._reply(404, {"error": "NOT_FOUND"})
            if not self._pinned_auth():
                return
            if conversation:
                return self._conversation_get(path)
            if review:
                return self._review_get(path)
            if worklist:
                return self._worklist_get(path)
            if control:
                return self._control_route(path)
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
            if re.fullmatch(r"/v1/advisory-candidates/[0-9a-f]{32}/proposals(?:/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}/registrations)?",self.path):
                return self._candidate_route(write=True)
            if re.fullmatch(r"/v1/advisory/[0-9a-f]{32}/turns(?:/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}/cancel)?",self.path):
                return self._advisory_route(write=True)
            if re.fullmatch(r"/v1/workset-controls/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}/commands", self.path):
                return self._control_route(self.path, write=True)
            if re.fullmatch(r"/v1/reviews/missions/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}/decisions",
                            self.path):
                return self._review_write(self.path)
            if (self.path == "/v1/conversations" or
                    re.fullmatch(r"/v1/conversations/[0-9a-f]{32}/(?:archive|restore)", self.path)):
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
