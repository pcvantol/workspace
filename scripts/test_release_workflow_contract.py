#!/usr/bin/env python3
"""Structural regression tests for Workspace's protected release lifecycle."""
from __future__ import annotations

from pathlib import Path
import unittest


WORKFLOW = Path(__file__).parents[1] / ".github" / "workflows" / "workspace-production-release.yml"


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


if __name__ == "__main__":
    unittest.main()
