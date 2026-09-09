#!/usr/bin/env python3
"""Behavioral tests for the Workspace source-bundle release journal."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest


MODULE = Path(__file__).with_name("release_operation.py")
SPEC = importlib.util.spec_from_file_location("workspace_release_operation", MODULE)
assert SPEC and SPEC.loader
release_operation = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release_operation
SPEC.loader.exec_module(release_operation)


class WorkspaceReleaseOperationTests(unittest.TestCase):
    source = "a" * 40
    policy = "workspace-production-release-v1"

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bundle = self.root / "workspace-2.3.0.tar.gz"
        self.bundle.write_bytes(b"qualified source bundle")
        self.evidence = self.root / "release-evidence"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def expected(self, operation_id: str = "workspace-release-0001"):
        return release_operation.ReleaseOperation.create(
            operation_id=operation_id,
            version="2.3.0",
            policy_revision=self.policy,
            source_revision=self.source,
            artifacts={"source_bundle": release_operation.ReleaseOperationStore.artifact_digest(self.bundle)},
        )

    def prepare(self, expected=None, qualification=None):
        expected = expected or self.expected()
        return release_operation.prepare_qualified(
            release_operation.ReleaseOperationStore(self.evidence),
            expected,
            qualification or {"exact_main_sha": self.source, "qualification": "PASS"},
        )

    def publish(self, expected=None):
        expected = expected or self.expected()
        self.prepare(expected)
        return release_operation.mark_published(
            release_operation.ReleaseOperationStore(self.evidence),
            expected,
            {"registry": "github-release", "tag": "workspace-v2.3.0", "readback": "PASS"},
        )

    def test_same_operation_retries_but_changed_artifact_or_qualification_fails_closed(self) -> None:
        first = self.prepare()
        self.assertEqual("QUALIFIED", first.state)
        self.assertEqual(first, self.prepare())
        self.bundle.write_bytes(b"different bytes under same release identity")
        with self.assertRaisesRegex(release_operation.ReleaseOperationError, "different bytes or provenance"):
            self.prepare()
        self.bundle.write_bytes(b"qualified source bundle")
        with self.assertRaisesRegex(release_operation.ReleaseOperationError, "qualified release evidence changed"):
            self.prepare(qualification={"exact_main_sha": self.source, "qualification": "DIFFERENT"})

    def test_concurrent_release_lock_and_same_version_different_bytes_are_rejected(self) -> None:
        first_store = release_operation.ReleaseOperationStore(self.evidence)
        first_store.acquire("workspace-release-0001")
        try:
            second_store = release_operation.ReleaseOperationStore(self.evidence)
            with self.assertRaisesRegex(release_operation.ReleaseOperationError, "another release operation"):
                second_store.acquire("workspace-release-0002")
        finally:
            first_store.release("workspace-release-0001")
        self.publish()
        self.bundle.write_bytes(b"same version but a different immutable bundle")
        competing = self.expected("workspace-release-0002")
        self.prepare(competing)
        with self.assertRaisesRegex(release_operation.ReleaseOperationError, "different bytes or provenance"):
            release_operation.mark_published(
                release_operation.ReleaseOperationStore(self.evidence),
                competing,
                {"registry": "github-release", "tag": "workspace-v2.3.0", "readback": "PASS"},
            )

    def test_published_and_release_complete_are_distinct_and_restart_safe(self) -> None:
        published = self.publish()
        self.assertEqual("PUBLISHED", published.state)
        completed = release_operation.complete(
            release_operation.ReleaseOperationStore(self.evidence),
            self.expected(),
            {"result": "COMPLETE", "temporary_paths": ["readback", "dist"]},
        )
        self.assertEqual("RELEASE_COMPLETE", completed.state)
        self.assertEqual(completed, release_operation.complete(
            release_operation.ReleaseOperationStore(self.evidence),
            self.expected(),
            {"result": "COMPLETE", "temporary_paths": ["readback", "dist"]},
        ))

    def test_changed_publication_receipt_cannot_rewrite_published_evidence(self) -> None:
        self.publish()
        with self.assertRaisesRegex(release_operation.ReleaseOperationError, "receipt changed"):
            release_operation.mark_published(
                release_operation.ReleaseOperationStore(self.evidence),
                self.expected(),
                {"registry": "github-release", "tag": "workspace-v2.3.0", "readback": "DIFFERENT"},
            )

    def test_cleanup_failure_is_durable_and_can_resume_to_completion(self) -> None:
        self.publish()
        pending = release_operation.mark_cleanup_pending(
            release_operation.ReleaseOperationStore(self.evidence),
            self.expected(),
            {"result": "CLEANUP_PENDING", "targets": ["readback"], "error": "permission denied"},
        )
        self.assertEqual("CLEANUP_PENDING", pending.state)
        completed = release_operation.complete(
            release_operation.ReleaseOperationStore(self.evidence),
            self.expected(),
            {"result": "COMPLETE", "temporary_paths": ["readback"]},
        )
        self.assertEqual("RELEASE_COMPLETE", completed.state)

    def test_invalid_non_finite_json_evidence_is_rejected(self) -> None:
        with self.assertRaisesRegex(release_operation.ReleaseOperationError, "durable JSON evidence"):
            self.prepare(qualification={"exact_main_sha": self.source, "score": float("nan")})

    def test_persisted_record_has_no_implicit_or_unknown_fields(self) -> None:
        self.prepare()
        record = next((self.evidence / "operations").glob("*.json"))
        payload = json.loads(record.read_text(encoding="utf-8"))
        payload["unexpected"] = True
        record.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(release_operation.ReleaseOperationError, "unknown or missing"):
            release_operation.ReleaseOperationStore(self.evidence).load("workspace-release-0001")

    def test_digest_normalizes_symlinks_and_paths_with_spaces(self) -> None:
        spaced = self.root / "release inputs"
        spaced.mkdir()
        artifact = spaced / "workspace bundle.tar.gz"
        artifact.write_bytes(b"exact immutable artifact")
        linked = self.root / "artifact symlink.tar.gz"
        os.symlink(artifact, linked)
        self.assertEqual(
            release_operation.ReleaseOperationStore.artifact_digest(artifact),
            release_operation.ReleaseOperationStore.artifact_digest(linked),
        )


if __name__ == "__main__":
    unittest.main()
