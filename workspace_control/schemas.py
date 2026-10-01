"""Response shapes for the implemented own read-only HTTP contract."""

INSTANCE_ID = {"type": "string", "pattern": "^[0-9a-f]{32}$"}
PROJECT_STATES = ["UNCONFIGURED", "EMPTY", "PARTIAL", "STALE", "AVAILABLE"]

OPENAPI_SCHEMAS = {
    "Identity": {
        "type": "object", "additionalProperties": False, "required": ["instance_id"],
        "properties": {"instance_id": INSTANCE_ID},
    },
    "Status": {
        "type": "object", "additionalProperties": False,
        "required": ["instance_id", "version", "state", "project_source"],
        "properties": {"instance_id": INSTANCE_ID, "version": {"type": "string"},
                       "state": {"type": "string", "enum": ["READY"]},
                       "project_source": {"type": "string", "enum": PROJECT_STATES + ["SOURCE_UNAVAILABLE"]}},
    },
    "Project": {
        "type": "object", "additionalProperties": False, "required": ["id", "name"],
        "properties": {"id": {"type": "string"}, "name": {"type": "string"}},
    },
    "Projects": {
        "type": "object", "additionalProperties": False,
        "required": ["state", "projects", "source", "partial", "stale"],
        "properties": {"state": {"type": "string", "enum": PROJECT_STATES},
                       "projects": {"type": "array", "items": {"$ref": "#/components/schemas/Project"}},
                       "source": {"type": "string", "nullable": True, "enum": ["LOCAL", "DEMO", None]},
                       "observed_at": {"type": "string", "format": "date-time"},
                       "partial": {"type": "boolean"}, "stale": {"type": "boolean"}},
    },
    "Operation": {
        "type": "object", "additionalProperties": False,
        "required": ["id", "exposure", "auth"],
        "properties": {"id": {"type": "string"},
                       "exposure": {"type": "string", "enum": ["HTTP_EXPOSED", "LOCAL_ONLY_ADMIN"]},
                       "auth": {"type": "string", "enum": ["PUBLIC", "BEARER_PINNED", "PRIVATE_ROOT_OWNER"]},
                       "method": {"type": "string", "enum": ["GET"]},
                       "path": {"type": "string"}, "local_cli": {"type": "string"}},
    },
    "Capabilities": {
        "type": "object", "additionalProperties": False,
        "required": ["schema_version", "product_version", "instance_id", "operations",
                     "peer_operations_qualified"],
        "properties": {"schema_version": {"type": "integer", "enum": [1]},
                       "product_version": {"type": "string"}, "instance_id": INSTANCE_ID,
                       "operations": {"type": "array", "items": {"$ref": "#/components/schemas/Operation"}},
                       "peer_operations_qualified": {"type": "boolean", "enum": [False]}},
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
}
