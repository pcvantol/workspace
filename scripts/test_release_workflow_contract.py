#!/usr/bin/env python3
"""Structural regression tests for Workspace's protected release lifecycle."""
from __future__ import annotations

from dataclasses import asdict
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "workspace-production-release.yml"
sys.path.insert(0, str(ROOT))

from scripts.release_operation import ReleaseOperation, ReleaseOperationStore


class WorkspaceReleaseWorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_operation_identity_uses_the_complete_main_revision(self) -> None:
        self.assertIn("operation_id=workspace-release-$VERSION-$SOURCE_SHA", self.workflow)
        self.assertNotIn("SOURCE_SHA:0:12", self.workflow)

    def test_qualified_receipt_is_durable_before_source_bundle_publication(self) -> None:
        receipt = 'QUALIFIED="workspace-release-qualified-$VERSION-$SOURCE_SHA.json"'
        draft = 'gh release create "$TAG" "$QUALIFIED" --draft --target "$SOURCE_SHA"'
        publish = 'gh release upload "$TAG" "$ASSET"'
        self.assertIn(receipt, self.workflow)
        self.assertIn(draft, self.workflow)
        self.assertIn("Existing release lacks its original durable qualified-operation receipt.", self.workflow)
        self.assertIn('cmp "$QUALIFIED" "$qualified_readback/$QUALIFIED"', self.workflow)
        self.assertLess(self.workflow.index(draft), self.workflow.index(publish))

    def test_publish_rechecks_qualified_receipt_and_makes_only_a_draft_public(self) -> None:
        verify = "Recheck durable qualified operation and receipt before publication"
        publish = 'gh release upload "$TAG" "$ASSET"'
        public = 'gh release edit "$TAG" --draft=false'
        self.assertIn(verify, self.workflow)
        self.assertIn('cmp "release-input/release-evidence/operations/$OPERATION_ID.json"', self.workflow)
        self.assertLess(self.workflow.index(verify), self.workflow.index(publish))
        self.assertLess(self.workflow.index(publish), self.workflow.index(public))

    def test_readback_precedes_published_and_terminal_cleanup_uses_recorded_digest(self) -> None:
        readback = "Read back the public source bundle and retain PUBLISHED evidence"
        published = "--mark-published"
        pending = "--mark-cleanup-pending"
        complete = "--complete"
        cleanup_loop = "for index in \"${!cleanup_targets[@]}\"; do"
        self.assertIn(readback, self.workflow)
        self.assertLess(self.workflow.index(readback), self.workflow.index(published))
        self.assertIn(cleanup_loop, self.workflow)
        self.assertLess(self.workflow.index(cleanup_loop), self.workflow.index(pending))
        self.assertLess(self.workflow.index(cleanup_loop), self.workflow.index(complete))
        self.assertGreaterEqual(self.workflow.count("--artifact-digest \"$DIGEST\""), 2)
        self.assertIn('"published-readback"', self.workflow)
        self.assertIn("CLEANUP_PENDING", self.workflow)
        self.assertIn("RELEASE_COMPLETE", self.workflow)

    def test_terminal_cleanup_hydrates_a_durable_pending_receipt_before_retry(self) -> None:
        pending = 'PENDING="workspace-cleanup-pending-$VERSION-$SOURCE_SHA.json"'
        show_after_recovery = 'if operation["state"] not in {"PUBLISHED", "CLEANUP_PENDING"}:'
        self.assertIn(pending, self.workflow)
        self.assertIn('PYTHONPATH=. python3 - "$pending_readback/$PENDING"', self.workflow)
        self.assertIn("cleanup-pending receipt has non-canonical bytes", self.workflow)
        self.assertIn("cleanup-pending receipt does not match published release evidence", self.workflow)
        self.assertIn('resumed = current.transition("CLEANUP_PENDING", evidence=pending.cleanup)', self.workflow)
        self.assertIn("store.replace(current, resumed)", self.workflow)
        self.assertIn(show_after_recovery, self.workflow)
        self.assertLess(
            self.workflow.index('PYTHONPATH=. python3 - "$pending_readback/$PENDING"'),
            self.workflow.index(show_after_recovery),
        )
        self.assertIn('if test "$pending_present" = false; then', self.workflow)
        self.assertIn('workspace-pending-confirmation-XXXXXX', self.workflow)

    def test_pending_receipt_recovery_body_rebinds_the_exact_published_operation(self) -> None:
        marker = '            PYTHONPATH=. python3 - "$pending_readback/$PENDING" <<\'PY\''
        start = self.workflow.index(marker)
        body_start = self.workflow.index("\n", start) + 1
        body_end = self.workflow.index("            PY\n", body_start)
        body = "\n".join(
            line[12:] if line.startswith("            ") else line
            for line in self.workflow[body_start:body_end].splitlines()
        )

        with tempfile.TemporaryDirectory() as temporary:
            workdir = Path(temporary)
            (workdir / "scripts").symlink_to(ROOT / "scripts", target_is_directory=True)
            operation = ReleaseOperation.create(
                operation_id="workspace-release-0001",
                version="2.3.0",
                policy_revision="workspace-production-release-v2",
                source_revision="a" * 40,
                artifacts={"source_bundle": "sha256:" + "b" * 64},
            )
            qualification = {"exact_main_sha": operation.source_revision, "qualification": "PASS"}
            publication = {"registry": "github-release", "tag": "workspace-v2.3.0", "readback": "PASS"}
            store = ReleaseOperationStore(workdir / "published-input" / "release-evidence")
            store.acquire(operation.operation_id)
            try:
                prepared = store.save(operation)
                qualified = store.replace(prepared, prepared.transition("QUALIFIED", evidence=qualification))
                published = store.replace(qualified, qualified.transition("PUBLISHED", evidence=publication))
                store.record_publication(published)
            finally:
                store.release(operation.operation_id)
            pending = published.transition(
                "CLEANUP_PENDING",
                evidence={"result": "CLEANUP_PENDING", "targets": ["published-readback"]},
            )
            receipt_root = workdir / "pending-readback"
            receipt_root.mkdir()
            receipt = receipt_root / "pending.json"
            receipt.write_text(
                json.dumps(asdict(pending), sort_keys=True, separators=(",", ":")) + "\n",
                encoding="utf-8",
            )
            environment = dict(os.environ)
            environment["OPERATION_ID"] = operation.operation_id
            result = subprocess.run(
                ["python3", "-", "pending-readback/pending.json"],
                cwd=workdir,
                env=environment,
                input=body,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(ReleaseOperationStore(workdir / "published-input" / "release-evidence").load(operation.operation_id), pending)


if __name__ == "__main__":
    unittest.main()
