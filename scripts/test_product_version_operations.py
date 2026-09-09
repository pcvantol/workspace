#!/usr/bin/env python3
"""Focused regression tests for the Workspace product-version operation."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).with_name("advance_product_version.py")
SPEC = importlib.util.spec_from_file_location("version_helper", MODULE)
assert SPEC and SPEC.loader
version_helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(version_helper)


class ProductVersionOperationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "product-version.json").write_text(
            '{"product":"workspace","schema_version":1,"version":"2.3.0"}\n', encoding="utf-8"
        )
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "product-version.json"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=test", "-c", "user.email=test@example.invalid",
                        "commit", "-qm", "baseline"], check=True)
        self.head = subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True).strip()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def apply(self, operation_id: str = "event-0001", **changes: object) -> str:
        arguments: dict[str, object] = dict(component="patch", exact=None, expected_version="2.3.0",
                                             operation_id=operation_id, event_lineage="push:" + self.head,
                                             expected_head=self.head)
        arguments.update(changes)
        return version_helper.apply(self.root, **arguments)

    def test_plan_is_read_only_and_apply_is_idempotent(self) -> None:
        receipt = version_helper.plan(self.root, "patch", None, "2.3.0", "event-0001", "push:" + self.head, self.head)
        self.assertEqual("2.3.1", receipt["determined_version"])
        self.assertEqual("2.3.0", json.loads((self.root / "product-version.json").read_text())["version"])
        self.assertEqual("2.3.1", self.apply())
        self.assertEqual("2.3.1", self.apply())
        self.assertTrue((self.root / ".version-operations/event-0001.json").is_file())

    def test_changed_input_under_an_operation_id_conflicts(self) -> None:
        self.apply()
        with self.assertRaisesRegex(RuntimeError, "operation ID conflict"):
            self.apply(component="minor")

    def test_docs_only_no_bump_is_durable_and_cannot_be_reclassified(self) -> None:
        self.assertEqual("2.3.0", self.apply(operation_id="increment-docs-1", component="none"))
        self.assertEqual("2.3.0", self.apply(operation_id="increment-docs-1", component="none"))
        with self.assertRaisesRegex(RuntimeError, "operation ID conflict"):
            self.apply(operation_id="increment-docs-1", component="patch")

    def test_existing_increment_receipt_survives_a_later_delivery_head(self) -> None:
        self.assertEqual("2.3.1", self.apply(operation_id="increment-delivery-1"))
        (self.root / "delivery-evidence").write_text("merged", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.root), "add", "delivery-evidence"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-qm", "delivery"], check=True)
        self.assertEqual("2.3.1", self.apply(operation_id="increment-delivery-1"))

    def test_minor_and_explicit_release_target_are_deterministic(self) -> None:
        self.assertEqual("2.4.0", self.apply(operation_id="event-0002", component="minor"))
        # An explicit release target may be prepared only from the declared
        # baseline; it does not receive an implicit additional bump.
        self.assertEqual("3.0.0", version_helper.apply(
            self.root, None, "3.0.0", "2.4.0", "event-0003", "release:" + self.head, self.head
        ))

    def test_bad_expected_version_and_major_bump_are_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "expected version must be stable"):
            self.apply(expected_version="02.3.0")
        with self.assertRaisesRegex(RuntimeError, "major requires explicit"):
            version_helper.apply(self.root, "major", None, "2.3.0", "event-0004", "push:" + self.head, self.head)

    def test_release_guard_requires_exact_branch_version_and_source(self) -> None:
        self.assertEqual("2.3.0", version_helper.verify_release_source(self.root, "release-2.3.0", self.head))
        with self.assertRaisesRegex(RuntimeError, "exactly release"):
            version_helper.verify_release_source(self.root, "release-02.3.0", self.head)
        with self.assertRaisesRegex(RuntimeError, "disagree"):
            version_helper.verify_release_source(self.root, "release-2.3.1", self.head)
        with self.assertRaisesRegex(RuntimeError, "exact approved"):
            version_helper.verify_release_source(self.root, "release-2.3.0", "0" * 40)

    def test_main_release_guard_requires_exact_protected_source(self) -> None:
        self.assertEqual("2.3.0", version_helper.verify_main_release_source(self.root, self.head))
        with self.assertRaisesRegex(RuntimeError, "full source revision"):
            version_helper.verify_main_release_source(self.root, "short")
        with self.assertRaisesRegex(RuntimeError, "exact approved"):
            version_helper.verify_main_release_source(self.root, "0" * 40)

    def test_stale_head_and_baseline_are_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "source HEAD"):
            self.apply(expected_head="0" * 40)
        with self.assertRaisesRegex(RuntimeError, "stale version operation"):
            self.apply(expected_version="2.2.9")

    def test_recovery_after_manifest_write_does_not_allocate_again(self) -> None:
        manifest = self.root / "product-version.json"
        manifest.write_text('{"product":"workspace","schema_version":1,"version":"2.3.1"}\n', encoding="utf-8")
        self.assertEqual("2.3.1", self.apply())
        self.assertEqual("2.3.1", json.loads(manifest.read_text())["version"])

    def test_invalid_manifest_is_rejected(self) -> None:
        (self.root / "product-version.json").write_text("[]\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "must be an object"):
            version_helper.current(self.root)


if __name__ == "__main__":
    unittest.main()
