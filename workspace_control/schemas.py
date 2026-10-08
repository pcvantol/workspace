"""Response shapes for the implemented own read-only HTTP contract."""

INSTANCE_ID = {"type": "string", "pattern": "^[0-9a-f]{32}$"}
PRODUCT_VERSION = {"type": "string", "pattern": r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"}
PROJECT_STATES = ["UNCONFIGURED", "EMPTY", "PARTIAL", "STALE", "AVAILABLE"]

OPENAPI_SCHEMAS = {
    "Identity": {
        "type": "object", "additionalProperties": False, "required": ["instance_id"],
        "properties": {"instance_id": INSTANCE_ID},
    },
    "Status": {
        "type": "object", "additionalProperties": False,
        "required": ["instance_id", "version", "state", "project_source"],
        "properties": {"instance_id": INSTANCE_ID, "version": PRODUCT_VERSION,
                       "state": {"type": "string", "enum": ["READY"]},
                       "project_source": {"type": "string", "enum": PROJECT_STATES + ["SOURCE_UNAVAILABLE"]}},
    },
    "Project": {
        "type": "object", "additionalProperties": False, "required": ["id", "name"],
        "properties": {"id": {"type": "string", "minLength": 1, "maxLength": 120},
                       "name": {"type": "string", "minLength": 1, "maxLength": 120}},
    },
    "Projects": {
        "type": "object", "additionalProperties": False,
        "required": ["state", "projects", "source", "partial", "stale"],
        "properties": {"state": {"type": "string", "enum": PROJECT_STATES},
                       "projects": {"type": "array", "maxItems": 100,
                                    "items": {"$ref": "#/components/schemas/Project"}},
                       "source": {"type": "string", "nullable": True, "enum": ["LOCAL", "DEMO", None]},
                       "observed_at": {"type": "string",
                                       "description": "Timezone-aware ISO 8601 source timestamp; original spelling preserved"},
                       "partial": {"type": "boolean"}, "stale": {"type": "boolean"}},
    },
    "Operation": {
        "type": "object", "additionalProperties": False,
        "required": ["id", "exposure", "auth"],
        "properties": {"id": {"type": "string"},
                       "exposure": {"type": "string", "enum": ["HTTP_EXPOSED", "LOCAL_ONLY_ADMIN"]},
                       "auth": {"type": "string", "enum": ["PUBLIC", "BEARER_PINNED",
                                                        "BEARER_PINNED_AND_DRAFT_GRANT",
                                                        "BEARER_PINNED_AND_REVIEW_GRANT",
                                                        "BEARER_PINNED_AND_WORKLIST_GRANT", "BEARER_PINNED_AND_WORKLIST_CONTROL_GRANT", "BEARER_PINNED_AND_DRAFT_AND_ADVISORY_GRANT", "BEARER_PINNED_AND_DRAFT_AND_CANDIDATE_GRANT", "PRIVATE_ROOT_OWNER"]},
                       "method": {"type": "string", "enum": ["GET", "POST", "PATCH"]},
                       "path": {"type": "string"}, "local_cli": {"type": "string"}},
    },
    "Capabilities": {
        "type": "object", "additionalProperties": False,
        "required": ["schema_version", "product_version", "instance_id", "operations",
                     "peer_operations_qualified"],
        "properties": {"schema_version": {"type": "integer", "enum": [1]},
                       "product_version": PRODUCT_VERSION, "instance_id": INSTANCE_ID,
                       "operations": {"type": "array", "items": {"$ref": "#/components/schemas/Operation"}},
                       "peer_operations_qualified": {"type": "boolean", "enum": [False]}},
    },
    "ForgeStatus": {
        "type": "object", "additionalProperties": False,
        "required": ["schema_version", "state", "instance_id", "repository_id",
                     "product_version", "availability", "freshness", "source_observed_at",
                     "retrieved_at"],
        "properties": {
            "schema_version": {"type": "integer", "enum": [1]},
            "state": {"type": "string", "enum": ["UNCONFIGURED", "INVALID_CONFIGURATION",
                         "TLS_UNTRUSTED", "UNAUTHORIZED", "DENIED", "UNAVAILABLE",
                         "INVALID_RESPONSE", "WRONG_INSTANCE", "READ_SCOPE_UNVERIFIED",
                         "OBSERVED"]},
            "instance_id": {"type": "string", "nullable": True},
            "repository_id": {"type": "string", "nullable": True},
            "product_version": {"type": "string", "nullable": True},
            "availability": {"type": "string", "nullable": True, "enum": ["AVAILABLE", "UNAVAILABLE", None]},
            "freshness": {"type": "string", "nullable": True,
                          "enum": ["CURRENT", "STALE", "UNKNOWN", "UNAVAILABLE", None]},
            "source_observed_at": {"type": "string", "nullable": True},
            "retrieved_at": {"type": "string", "nullable": True},
        },
    },
    "OpenAPIContract": {
        "type": "object", "required": ["openapi", "info", "servers", "components", "paths"],
        "properties": {"openapi": {"type": "string", "enum": ["3.0.3"]},
                       "info": {"type": "object"}, "servers": {"type": "array"},
                       "components": {"type": "object"}, "paths": {"type": "object"}},
    },
    "Error": {
        "type": "object", "additionalProperties": False, "required": ["error"],
        "properties": {"error": {"type": "string"}},
    },
}

SUCCESS_SCHEMA = {
    "identity.read": "Identity", "status.read": "Status", "projects.read": "Projects",
    "openapi.read": "OpenAPIContract", "capabilities.read": "Capabilities",
    "forge.status.read": "ForgeStatus",
}
