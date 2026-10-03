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
import os


ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILDER = ROOT / "scripts" / "build_macos_app.sh"
BUNDLE_ID = "com.pcvantol.workspace.native-client"
KEYCHAIN_SERVICE = BUNDLE_ID + ".v2"
TEST_IDENTITY_SHA1 = "A" * 40
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
    def run_builder(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(BUILDER), *args], cwd=ROOT, capture_output=True,
            text=True, timeout=20, check=False, env=env,
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
            "--mode", "developer-id", "--identity", TEST_IDENTITY_SHA1,
            "--team-id", "ABCDEFGHIJ", "--notary-profile", "test-profile",
            "--source-revision", "0" * 40, "/tmp/Workspace.app",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("clean, exact current protected main", result.stderr)
        self.assertNotIn("Compiling", result.stdout + result.stderr)

    def test_signed_mode_rejects_ambiguous_certificate_name_before_build(self) -> None:
        result = self.run_builder(
            "--mode", "developer-id", "--identity", "Developer ID Application: Test (ABCDEFGHIJ)",
            "--team-id", "ABCDEFGHIJ", "--notary-profile", "test-profile",
            "--source-revision", "0" * 40, "/tmp/Workspace.app",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("identity SHA-1", result.stderr)
        self.assertNotIn("Compiling", result.stdout + result.stderr)

    def test_local_mode_cannot_accept_distribution_parameters(self) -> None:
        result = self.run_builder("--identity", "Developer ID Application: Test", "/tmp/Workspace.app")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Usage:", result.stderr)

    def test_signed_mode_rejects_source_drift_during_build(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            revision = "a" * 40
            sentinel = root / "source-drift"
            fake_git = fake_bin / "git"
            fake_git.write_text(
                '#!/bin/sh\n'
                'case "$1 $2" in\n'
                '  "rev-parse HEAD") echo "$MOCK_SOURCE_REVISION" ;;\n'
                '  "remote get-url") echo "$MOCK_ORIGIN_URL" ;;\n'
                '  "ls-remote origin") printf "%s\\trefs/heads/main\\n" "$MOCK_SOURCE_REVISION" ;;\n'
                '  "status --porcelain") if test -f "$MOCK_SENTINEL"; then echo " M changed.swift"; fi ;;\n'
                '  *) exit 99 ;;\n'
                'esac\n'
            )
            fake_swift = fake_bin / "swift"
            fake_swift.write_text(
                '#!/bin/sh\n'
                'previous=\n'
                'for argument in "$@"; do\n'
                '  if test "$previous" = --scratch-path; then echo "$argument" >> "$MOCK_SCRATCH_LOG"; fi\n'
                '  previous="$argument"\n'
                'done\n'
                'case " $* " in\n'
                '  *" --show-bin-path "*) echo "$MOCK_BIN_DIR" ;;\n'
                '  *) touch "$MOCK_SENTINEL" ;;\n'
                'esac\n'
            )
            fake_git.chmod(0o755)
            fake_swift.chmod(0o755)
            fake_security = fake_bin / "security"
            fake_security.write_text(
                '#!/bin/sh\n'
                'printf "  1) %s \\\"Developer ID Application: Test (ABCDEFGHIJ)\\\"\\n" "$MOCK_IDENTITY_SHA1"\n'
            )
            fake_security.chmod(0o755)
            env = os.environ.copy()
            env.update({
                "PATH": str(fake_bin) + os.pathsep + env["PATH"],
                "MOCK_SOURCE_REVISION": revision,
                "MOCK_IDENTITY_SHA1": TEST_IDENTITY_SHA1,
                "MOCK_ORIGIN_URL": "https://github.com/pcvantol/workspace.git",
                "MOCK_SENTINEL": str(sentinel),
                "MOCK_BIN_DIR": str(root),
                "MOCK_SCRATCH_LOG": str(root / "scratch-log"),
                "WORKSPACE_SWIFT_SCRATCH": str(root / "shared-scratch"),
            })
            env["MOCK_IDENTITY_SHA1"] = "B" * 40
            result = self.run_builder(
                "--mode", "developer-id", "--identity", TEST_IDENTITY_SHA1,
                "--team-id", "ABCDEFGHIJ", "--notary-profile", "test-profile",
                "--source-revision", revision, str(root / "Workspace.app"), env=env,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("exact Developer ID Application SHA-1", result.stderr)
            self.assertFalse((root / "scratch-log").exists())

            env["MOCK_IDENTITY_SHA1"] = TEST_IDENTITY_SHA1
            result = self.run_builder(
                "--mode", "developer-id", "--identity", TEST_IDENTITY_SHA1,
                "--team-id", "ABCDEFGHIJ", "--notary-profile", "test-profile",
                "--source-revision", revision, str(root / "Workspace.app"), env=env,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("throughout the build", result.stderr)
            self.assertFalse((root / "Workspace.app").exists())
            scratch_paths = (root / "scratch-log").read_text().splitlines()
            self.assertEqual(len(scratch_paths), 2)
            self.assertEqual(scratch_paths[0], scratch_paths[1])
            self.assertIn("workspace-client-signed.", scratch_paths[0])
            self.assertNotEqual(scratch_paths[0], env["WORKSPACE_SWIFT_SCRATCH"])
            self.assertFalse(pathlib.Path(scratch_paths[0]).exists())

            sentinel.unlink()
            env["MOCK_ORIGIN_URL"] = "https://github.com/example/unprotected.git"
            result = self.run_builder(
                "--mode", "developer-id", "--identity", TEST_IDENTITY_SHA1,
                "--team-id", "ABCDEFGHIJ", "--notary-profile", "test-profile",
                "--source-revision", revision, str(root / "Workspace.app"), env=env,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("canonical Workspace origin", result.stderr)
            self.assertFalse(sentinel.exists())

            env["MOCK_ORIGIN_URL"] = "https://github.com/pcvantol/workspace.git"
            result = self.run_builder(
                "--mode", "developer-id", "--identity", TEST_IDENTITY_SHA1,
                "--team-id", "ABCDEFGHIJ", "--notary-profile", "test-profile",
                "--source-revision", revision, str(pathlib.Path("/tmp").resolve() / "Workspace.app"), env=env,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("owned by this user and private", result.stderr)
            self.assertFalse(sentinel.exists())


if __name__ == "__main__":
    unittest.main()
