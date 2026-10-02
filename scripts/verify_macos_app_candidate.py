#!/usr/bin/env python3
"""Verify the exact private Developer ID Workspace.app ZIP and its manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile

BUNDLE_ID = "com.pcvantol.workspace.native-client"
KEYCHAIN_SERVICE = BUNDLE_ID + ".v2"
SHA = re.compile(r"[0-9a-f]{64}\Z")
SOURCE = re.compile(r"[0-9a-f]{40}\Z")
TEAM = re.compile(r"[A-Z0-9]{10}\Z")


def check_archive(archive: Path, manifest_path: Path, source: str, team: str) -> dict:
    def unique_pairs(pairs: list[tuple[str, object]]) -> dict:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate candidate manifest key")
            result[key] = value
        return result

    data = json.loads(manifest_path.read_text(), object_pairs_hook=unique_pairs)
    required = {
        "schema_version", "mode", "source_revision", "version", "bundle_identifier",
        "keychain_service", "team_id", "notary_submission_id", "submitted_zip_sha256",
        "final_stapled_zip_sha256", "app_cdhash",
    }
    if set(data) != required or data["schema_version"] != 1 or data["mode"] != "developer-id-notarized":
        raise ValueError("candidate manifest schema or mode mismatch")
    if (not SOURCE.fullmatch(source) or data["source_revision"] != source or
            not TEAM.fullmatch(team) or data["team_id"] != team or
            data["bundle_identifier"] != BUNDLE_ID or data["keychain_service"] != KEYCHAIN_SERVICE):
        raise ValueError("candidate source, signer or app identity mismatch")
    if (not SHA.fullmatch(data["submitted_zip_sha256"]) or
            not SHA.fullmatch(data["final_stapled_zip_sha256"]) or
            not re.fullmatch(r"[0-9a-f]{40}", data["app_cdhash"])):
        raise ValueError("candidate digest or CDHash malformed")
    with archive.open("rb") as artifact:
        digest = hashlib.file_digest(artifact, "sha256").hexdigest()
    if digest != data["final_stapled_zip_sha256"]:
        raise ValueError("candidate archive digest mismatch")
    with zipfile.ZipFile(archive) as container:
        names = container.namelist()
        if not names or len(names) != len(set(names)) or container.testzip() is not None:
            raise ValueError("candidate archive is empty or corrupt")
        for member in container.infolist():
            name = member.filename
            path = Path(name)
            if (not path.parts or path.is_absolute() or ".." in path.parts or
                    path.parts[0] not in {"Workspace.app", "__MACOSX"} or
                    stat.S_ISLNK(member.external_attr >> 16)):
                raise ValueError("candidate archive has an unexpected path")
        if "Workspace.app/Contents/Info.plist" not in names or "Workspace.app/Contents/MacOS/WorkspaceClient" not in names:
            raise ValueError("candidate archive lacks the native app")
    return data


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=True, text=True, capture_output=True)


def verify_native(archive: Path, manifest: dict) -> None:
    with tempfile.TemporaryDirectory(prefix="workspace-candidate-verify-") as temporary:
        run("ditto", "-x", "-k", str(archive), temporary)
        app = Path(temporary) / "Workspace.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != BUNDLE_ID or info["CFBundleShortVersionString"] != manifest["version"]:
            raise ValueError("candidate bundle identity or version mismatch")
        run("codesign", "--verify", "--deep", "--strict", str(app))
        requirement = (f'identifier "{BUNDLE_ID}" and anchor apple generic and '
                       f'certificate leaf[subject.OU] = "{manifest["team_id"]}"')
        run("codesign", "--verify", "--strict", "-R=" + requirement, str(app))
        details = run("codesign", "-dv", "--verbose=4", str(app)).stderr
        if ("Authority=Developer ID Application:" not in details or
                "TeamIdentifier=" + manifest["team_id"] not in details or
                "(runtime)" not in details or "Timestamp=" not in details or
                "CDHash=" + manifest["app_cdhash"] not in details):
            raise ValueError("candidate signature metadata mismatch")
        run("xcrun", "stapler", "validate", str(app))
        run("spctl", "--assess", "--type", "execute", str(app))
        if "python" in run("otool", "-L", str(app / "Contents/MacOS/WorkspaceClient")).stdout.lower():
            raise ValueError("native app unexpectedly links Python")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--team-id", required=True)
    args = parser.parse_args()
    manifest = check_archive(args.archive, args.manifest, args.source_revision, args.team_id)
    verify_native(args.archive, manifest)
    print("DEVELOPER_ID_CANDIDATE=PASS sha256=" + manifest["final_stapled_zip_sha256"])


if __name__ == "__main__":
    main()
