#!/usr/bin/env python3
"""Negative contract cases for the checked-in Postman projection."""

from copy import deepcopy
import unittest
from unittest.mock import patch

import project_postman
from workspace_control.http import openapi_contract


class PostmanProjectionTests(unittest.TestCase):
    def test_global_security_cannot_silently_change_public_identity(self):
        changed = deepcopy(openapi_contract())
        changed["security"] = [{"bearerAuth": []}]
        with patch.object(project_postman, "openapi_contract", return_value=changed):
            with self.assertRaisesRegex(ValueError, "global OpenAPI security"):
                project_postman.collection()

    def test_changed_bearer_scheme_cannot_keep_old_authorization_header(self):
        changed = deepcopy(openapi_contract())
        changed["components"]["securitySchemes"]["bearerAuth"]["scheme"] = "basic"
        with patch.object(project_postman, "openapi_contract", return_value=changed):
            with self.assertRaisesRegex(ValueError, "security scheme"):
                project_postman.collection()

    def test_additional_server_requires_explicit_base_url_choice(self):
        changed = deepcopy(openapi_contract())
        changed["servers"].append({"url": "https://example.invalid"})
        with patch.object(project_postman, "openapi_contract", return_value=changed):
            with self.assertRaisesRegex(ValueError, "server list"):
                project_postman.collection()


if __name__ == "__main__":
    unittest.main()
