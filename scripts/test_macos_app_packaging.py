"""Fail-closed tests for the native candidate builder, without a signer."""

import pathlib
import platform
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
import hashlib
import json


ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILDER = ROOT / "scripts" / "build_macos_app.sh"
BUNDLE_ID = "com.pcvantol.workspace.native-client"
KEYCHAIN_SERVICE = BUNDLE_ID + ".v2"
sys.path.insert(0, str(ROOT / "scripts"))
from verify_macos_app_candidate import check_archive  # noqa: E402


class CandidateArchiveTests(unittest.TestCase):
    def test_exact_archive_source_and_paths_are_required(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            archive = root / "Workspace.app.zip"
            manifest_path = root / "manifest.json"
            source = "a" * 40
            team = "ABCDEFGHIJ"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("Workspace.app/Contents/Info.plist", b"plist")
                output.writestr("Workspace.app/Contents/MacOS/WorkspaceClient", b"binary")
            manifest = {
                "schema_version": 1, "mode": "developer-id-notarized",
                "source_revision": source, "version": "2.8.1",
                "bundle_identifier": BUNDLE_ID, "keychain_service": KEYCHAIN_SERVICE,
                "team_id": team, "notary_submission_id": "submission-id",
                "submitted_zip_sha256": "b" * 64,
                "final_stapled_zip_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                "app_cdhash": "c" * 40,
            }
            manifest_path.write_text(json.dumps(manifest))
            self.assertEqual(check_archive(archive, manifest_path, source, team), manifest)
            with self.assertRaisesRegex(ValueError, "source, signer or app identity"):
                check_archive(archive, manifest_path, "d" * 40, team)
            archive.write_bytes(archive.read_bytes() + b"changed")
            with self.assertRaisesRegex(ValueError, "archive digest mismatch"):
                check_archive(archive, manifest_path, source, team)
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("../escaped", b"bad")
                output.writestr("Workspace.app/Contents/Info.plist", b"plist")
                output.writestr("Workspace.app/Contents/MacOS/WorkspaceClient", b"binary")
            manifest["final_stapled_zip_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "unexpected path"):
                check_archive(archive, manifest_path, source, team)


@unittest.skipUnless(platform.system() == "Darwin", "macOS bundle tools required")
class MacOSPackagingTests(unittest.TestCase):
    def run_builder(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(BUILDER), *args], cwd=ROOT, capture_output=True,
            text=True, timeout=20, check=False,
        )

    def test_stable_app_and_keychain_identity(self) -> None:
        info = plistlib.loads((ROOT / "macos/WorkspaceClient/Resources/Info.plist").read_bytes())
        client = (ROOT / "macos/WorkspaceClient/Sources/WorkspaceClient/ClientState.swift").read_text()
        self.assertEqual(info["CFBundleIdentifier"], BUNDLE_ID)
        self.assertIn(f'private let service = "{KEYCHAIN_SERVICE}"', client)
        self.assertNotIn('private let service = "' + BUNDLE_ID + '.v1"', client)

    def test_signed_mode_requires_all_explicit_resources_before_build(self) -> None:
        result = self.run_builder("--mode", "developer-id", "/tmp/Workspace.app")
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires an application identity", result.stderr)
        self.assertNotIn("Compiling", result.stdout + result.stderr)

    def test_signed_mode_rejects_unprotected_source_before_build(self) -> None:
        result = self.run_builder(
            "--mode", "developer-id", "--identity", "Developer ID Application: Test (ABCDEFGHIJ)",
            "--team-id", "ABCDEFGHIJ", "--notary-profile", "test-profile",
            "--source-revision", "0" * 40, "/tmp/Workspace.app",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("clean, exact current protected main", result.stderr)
        self.assertNotIn("Compiling", result.stdout + result.stderr)

    def test_local_mode_cannot_accept_distribution_parameters(self) -> None:
        result = self.run_builder("--identity", "Developer ID Application: Test", "/tmp/Workspace.app")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
