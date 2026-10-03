"""Offline failure and reopen tests for private native-candidate handoffs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import preserve_macos_app_candidate as candidate


ROOT = Path(__file__).resolve().parent.parent
REVISION = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True, check=True).stdout.strip()
TREE = subprocess.run(["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT,
                      capture_output=True, text=True, check=True).stdout.strip()
BUILDER = hashlib.sha256(subprocess.run(
    ["git", "show", "HEAD:scripts/build_macos_app.sh"], cwd=ROOT,
    capture_output=True, check=True,
).stdout).hexdigest()
EXPECTED = {
    "source_revision": REVISION, "source_tree": TREE, "builder_sha256": BUILDER,
    "version": "2.8.2", "team_id": "ABCDEFGHIJ", "leaf_sha1": "A" * 40,
    "protected_main_at_preservation": REVISION,
}
MANIFEST = {
    "bundle_identifier": "com.pcvantol.workspace.native-client",
    "keychain_service": "com.pcvantol.workspace.native-client.v2",
    "app_cdhash": "b" * 40,
    "notary_submission_id": "11111111-2222-3333-4444-555555555555",
    "version": "2.8.2",
}


class PreservationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="workspace-preservation-test-")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name).resolve()
        self.parent = self.home / "private"
        self.parent.mkdir(mode=0o700)
        self.destination = self.parent / "candidate"
        self.archive = self.home / "control-ad-hoc.zip"
        control = os.environ.get("WORKSPACE_AD_HOC_CONTROL_ZIP")
        if control:
            self.archive.write_bytes(Path(control).read_bytes())
        else:
            self.archive.write_bytes(b"ad-hoc test bytes; never a signed artifact")
        self.manifest = self.home / "control-manifest.json"
        self.manifest.write_text('{"mode":"ad-hoc-test-only"}\n')
        self.home_patch = patch.object(candidate.Path, "home", return_value=self.home)
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)

    def handoff(self, qualification: str = "SIGNED_CANDIDATE_VERIFIED") -> dict:
        return {
            "schema_version": 1, "qualification": qualification, **EXPECTED,
            "bundle_identifier": MANIFEST["bundle_identifier"],
            "keychain_service": MANIFEST["keychain_service"],
            "app_cdhash": MANIFEST["app_cdhash"],
            "notary_submission_id": MANIFEST["notary_submission_id"],
            "staple": "validated", "gatekeeper": "accepted",
            "archive_sha256": candidate.sha256_file(self.archive),
            "candidate_manifest_sha256": candidate.sha256_file(self.manifest),
        }

    def store(self, qualification: str = "SIGNED_CANDIDATE_VERIFIED") -> str:
        return candidate.atomic_store(self.archive, self.manifest, self.destination,
                                      self.handoff(qualification))

    def test_source_binding_is_exact_protected_commit_tree_and_builder(self) -> None:
        candidate.source_binding(REVISION, TREE, BUILDER)
        with self.assertRaisesRegex(ValueError, "protected builder mismatch"):
            candidate.source_binding(REVISION, TREE, "0" * 64)
        with self.assertRaisesRegex(ValueError, "malformed"):
            candidate.source_binding("../../main", TREE, BUILDER)
        with patch.object(candidate, "protected_main_head", return_value="0" * 40):
            with self.assertRaisesRegex(ValueError, "not current protected"):
                candidate.source_binding(REVISION, TREE, BUILDER, require_remote_main=True)
        with patch.object(candidate, "protected_main_head", return_value=REVISION):
            candidate.source_binding(REVISION, TREE, BUILDER, require_remote_main=True)

    def test_protected_main_requires_canonical_origin_and_exact_remote_ref(self) -> None:
        def response(stdout: str):
            return argparse.Namespace(stdout=stdout)

        with patch.object(candidate.subprocess, "run", side_effect=[
            response("https://github.com/pcvantol/workspace.git\n"),
            response(REVISION + "\trefs/heads/main\n"),
        ]):
            self.assertEqual(candidate.protected_main_head(), REVISION)
        with patch.object(candidate.subprocess, "run", return_value=response("https://elsewhere.invalid/repo.git\n")):
            with self.assertRaisesRegex(ValueError, "noncanonical"):
                candidate.protected_main_head()
        with patch.object(candidate.subprocess, "run", side_effect=[
            response("https://github.com/pcvantol/workspace.git\n"), response(""),
        ]):
            with self.assertRaisesRegex(ValueError, "unavailable"):
                candidate.protected_main_head()

    def test_destination_is_owner_private_and_nonreplaceable(self) -> None:
        candidate.private_parent(self.destination)
        with patch.object(candidate, "ROOT", self.home):
            with self.assertRaisesRegex(ValueError, "outside the checkout"):
                candidate.private_parent(self.destination)
        self.parent.chmod(0o755)
        with self.assertRaisesRegex(ValueError, "owner-private"):
            candidate.private_parent(self.destination)
        self.parent.chmod(0o700)
        self.destination.symlink_to(self.archive)
        with self.assertRaisesRegex(ValueError, "already exists"):
            candidate.private_parent(self.destination)
        self.destination.unlink()
        with self.assertRaisesRegex(ValueError, "under the user home"):
            candidate.private_parent(Path("/tmp/candidate"))

    def test_ad_hoc_control_is_durable_but_never_reusable_as_signed(self) -> None:
        receipt = self.store("AD_HOC_TEST_ONLY")
        self.assertEqual(self.archive.read_bytes(), (self.destination / "Workspace.app.zip").read_bytes())
        self.assertEqual(self.manifest.read_bytes(), (self.destination / "candidate-manifest.json").read_bytes())
        self.assertEqual((self.destination / "handoff.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o700)
        # A fresh process reopens the persistent handoff after all handles are closed.
        script = (
            "import hashlib,pathlib,sys; p=pathlib.Path(sys.argv[1]); "
            "assert hashlib.sha256((p/'handoff.json').read_bytes()).hexdigest()==sys.argv[2]; "
            "assert hashlib.sha256((p/'Workspace.app.zip').read_bytes()).hexdigest()==sys.argv[3]; "
            "print('REOPEN_BYTES=PASS')"
        )
        run = subprocess.run([sys.executable, "-c", script, str(self.destination), receipt,
                              candidate.sha256_file(self.archive)],
                             capture_output=True, text=True, check=True)
        self.assertIn("REOPEN_BYTES=PASS", run.stdout)
        with self.assertRaisesRegex(ValueError, "qualification mismatch"):
            candidate.readback(self.destination, EXPECTED, receipt)

    def test_atomic_store_removes_only_its_incomplete_staging(self) -> None:
        with patch.object(candidate, "copy_private", side_effect=ValueError("interrupted")):
            with self.assertRaisesRegex(ValueError, "interrupted"):
                self.store()
        self.assertEqual(list(self.parent.iterdir()), [])
        receipt = self.store()
        self.assertTrue(self.destination.is_dir())
        self.assertEqual(candidate.sha256_file(self.destination / "handoff.json"), receipt)
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.store()

    def test_publish_race_never_replaces_existing_directory(self) -> None:
        original_copy = candidate.copy_private
        created = False

        def race(source: Path, target: Path) -> None:
            nonlocal created
            original_copy(source, target)
            if not created:
                self.destination.mkdir(mode=0o700)
                (self.destination / "other-owner-work").write_text("keep")
                created = True

        with patch.object(candidate, "copy_private", side_effect=race):
            with self.assertRaises(FileExistsError):
                self.store()
        self.assertEqual((self.destination / "other-owner-work").read_text(), "keep")
        self.assertEqual([p.name for p in self.parent.iterdir()], ["candidate"])

    def test_verified_reopen_rechecks_native_and_detects_tampering(self) -> None:
        receipt = self.store()
        with patch.object(candidate, "check_signed", return_value=MANIFEST) as check:
            self.assertEqual(candidate.readback(self.destination, EXPECTED, receipt)["version"], "2.8.2")
            check.assert_called_once()
            with self.assertRaisesRegex(ValueError, "receipt digest mismatch"):
                candidate.readback(self.destination, EXPECTED, "0" * 64)
            (self.destination / "Workspace.app.zip").write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "bytes mismatch"):
                candidate.readback(self.destination, EXPECTED, receipt)

    def test_reopen_rejects_missing_extra_symlink_and_nonprivate_files(self) -> None:
        receipt = self.store()
        file = self.destination / "Workspace.app.zip"
        file.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "not private"):
            candidate.readback(self.destination, EXPECTED, receipt)
        file.chmod(0o600)
        extra = self.destination / "extra"
        extra.write_text("x")
        with self.assertRaisesRegex(ValueError, "incomplete"):
            candidate.readback(self.destination, EXPECTED, receipt)
        extra.unlink()
        file.unlink()
        file.symlink_to(self.archive)
        with self.assertRaisesRegex(ValueError, "not private"):
            candidate.readback(self.destination, EXPECTED, receipt)

    def test_reopen_rejects_identity_and_duplicate_receipt_keys(self) -> None:
        receipt = self.store()
        with patch.object(candidate, "check_signed", return_value=MANIFEST):
            wrong = dict(EXPECTED, team_id="ZZZZZZZZZZ")
            with self.assertRaisesRegex(ValueError, "source or signer mismatch"):
                candidate.readback(self.destination, wrong, receipt)
            receipt_file = self.destination / "handoff.json"
            handoff = json.loads(receipt_file.read_text())
            handoff["gatekeeper"] = "rejected"
            receipt_file.write_text(json.dumps(handoff))
            new_receipt = candidate.sha256_file(receipt_file)
            with self.assertRaisesRegex(ValueError, "notarization mismatch"):
                candidate.readback(self.destination, EXPECTED, new_receipt)
            receipt_file.write_text('{"schema_version":1,"schema_version":1}')
            with self.assertRaisesRegex(ValueError, "duplicate handoff key"):
                candidate.readback(self.destination, EXPECTED, candidate.sha256_file(receipt_file))

    def test_signed_validation_rejects_wrong_version_notary_and_leaf(self) -> None:
        with patch.object(candidate, "check_archive", return_value=MANIFEST), \
                patch.object(candidate, "verify_native") as native, \
                patch.object(candidate, "signed_leaf", return_value="A" * 40):
            self.assertEqual(candidate.check_signed(self.archive, self.manifest, EXPECTED), MANIFEST)
            native.assert_called_once()
            with self.assertRaisesRegex(ValueError, "leaf mismatch"):
                candidate.check_signed(self.archive, self.manifest, dict(EXPECTED, leaf_sha1="B" * 40))
            with self.assertRaisesRegex(ValueError, "version or notary"):
                candidate.check_signed(self.archive, self.manifest, dict(EXPECTED, version="2.8.3"))

    def test_preserve_rejects_ad_hoc_and_does_not_publish(self) -> None:
        args = argparse.Namespace(archive=self.archive, manifest=self.manifest,
                                  destination=self.destination, **EXPECTED)
        with patch.object(candidate, "protected_main_head", return_value=REVISION):
            with self.assertRaisesRegex(ValueError, "candidate manifest schema or mode mismatch"):
                candidate.preserve(args)
        self.assertFalse(self.destination.exists())

    def test_mock_signed_flow_publishes_and_checks_receipt(self) -> None:
        args = argparse.Namespace(archive=self.archive, manifest=self.manifest,
                                  destination=self.destination, **EXPECTED)
        with patch.object(candidate, "check_signed", return_value=MANIFEST), \
                patch.object(candidate, "readback", return_value=self.handoff()) as reopen, \
                patch.object(candidate, "protected_main_head", return_value=REVISION):
            receipt = candidate.preserve(args)
        self.assertEqual(receipt, candidate.sha256_file(self.destination / "handoff.json"))
        reopen.assert_called_once_with(self.destination, EXPECTED, receipt)
        self.assertEqual(json.loads((self.destination / "handoff.json").read_text())
                         ["qualification"], "SIGNED_CANDIDATE_VERIFIED")

    def test_signed_leaf_reads_extracted_certificate_not_identity_name(self) -> None:
        calls = []

        def extract(command, **kwargs):
            calls.append(command)
            if len(calls) == 2:
                prefix = next(part.split("=", 1)[1] for part in command
                              if part.startswith("--extract-certificates="))
                Path(prefix + "0").write_bytes(b"test certificate")

        with patch.object(candidate.subprocess, "run", side_effect=extract):
            self.assertEqual(candidate.signed_leaf(self.archive),
                             hashlib.sha1(b"test certificate").hexdigest().upper())
        self.assertEqual(calls[0][:3], ["ditto", "-x", "-k"])
        self.assertEqual(calls[1][:2], ["codesign", "-d"])

    def test_expected_fields_rejects_malformed_identity(self) -> None:
        args = argparse.Namespace(**dict(EXPECTED, leaf_sha1="not-a-leaf"))
        with self.assertRaisesRegex(ValueError, "malformed Team"):
            candidate.expected_fields(args)
        args = argparse.Namespace(**dict(EXPECTED, version="2.8"))
        with self.assertRaisesRegex(ValueError, "malformed app version"):
            candidate.expected_fields(args)


if __name__ == "__main__":
    unittest.main()
