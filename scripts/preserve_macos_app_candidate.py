#!/usr/bin/env python3
"""Store and reopen a verified signed Workspace.app candidate outside /tmp.

The receipt is a binding to independently recorded bytes, not a signing grant.
No certificate, notary profile, token, or other credential is stored here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from verify_macos_app_candidate import check_archive, verify_native


SOURCE = re.compile(r"[0-9a-f]{40}\Z")
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
LEAF = re.compile(r"[A-F0-9]{40}\Z")
TEAM = re.compile(r"[A-Z0-9]{10}\Z")
FILES = {"Workspace.app.zip", "candidate-manifest.json", "handoff.json"}
ROOT = Path(__file__).resolve().parent.parent


def sha256_file(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def unique_json(path: Path) -> dict:
    def pairs(items: list[tuple[str, object]]) -> dict:
        result: dict = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate handoff key")
            result[key] = value
        return result

    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs)
    if not isinstance(value, dict):
        raise ValueError("handoff is not an object")
    return value


def source_binding(revision: str, tree: str, builder: str) -> None:
    if not SOURCE.fullmatch(revision) or not SOURCE.fullmatch(tree) or not DIGEST.fullmatch(builder):
        raise ValueError("malformed source, tree, or builder digest")
    actual_tree = subprocess.run(
        ["git", "rev-parse", f"{revision}^{{tree}}"], cwd=ROOT,
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    script = subprocess.run(
        ["git", "show", f"{revision}:scripts/build_macos_app.sh"], cwd=ROOT,
        check=True, capture_output=True,
    ).stdout
    if actual_tree != tree or hashlib.sha256(script).hexdigest() != builder:
        raise ValueError("source tree or protected builder mismatch")


def private_parent(destination: Path, *, require_absent: bool = True) -> None:
    if not destination.is_absolute() or destination.name in {"", ".", ".."}:
        raise ValueError("destination must be an absolute candidate directory")
    home = Path.home().resolve(strict=True)
    parent = destination.parent
    if parent.resolve(strict=True) != parent or not parent.is_relative_to(home):
        raise ValueError("destination parent must be a real path under the user home")
    if require_absent and (destination.exists() or destination.is_symlink()):
        raise ValueError("candidate destination already exists")
    info = parent.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("candidate parent must be owner-private")


def copy_private(source: Path, target: Path) -> None:
    with source.open("rb") as reader:
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as writer:
            shutil.copyfileobj(reader, writer)
            writer.flush()
            os.fsync(writer.fileno())
    if sha256_file(source) != sha256_file(target):
        raise ValueError("copied candidate bytes mismatch")


def atomic_store(archive: Path, manifest: Path, destination: Path, handoff: dict) -> str:
    """Publish a complete private directory; failure leaves no reusable receipt."""
    private_parent(destination)
    parent = destination.parent
    staging = Path(tempfile.mkdtemp(prefix=f".{destination.name}.", dir=parent))
    os.chmod(staging, 0o700)
    try:
        copy_private(archive, staging / "Workspace.app.zip")
        copy_private(manifest, staging / "candidate-manifest.json")
        receipt = staging / "handoff.json"
        fd = os.open(receipt, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as writer:
            json.dump(handoff, writer, sort_keys=True, indent=2)
            writer.write("\n")
            writer.flush()
            os.fsync(writer.fileno())
        dir_fd = os.open(staging, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
        if destination.exists() or destination.is_symlink():
            raise ValueError("candidate destination appeared during staging")
        os.rename(staging, destination)
        dir_fd = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
        return sha256_file(destination / "handoff.json")
    except BaseException:
        if staging.exists():
            shutil.rmtree(staging)
        raise


def signed_leaf(archive: Path) -> str:
    with tempfile.TemporaryDirectory(prefix="workspace-leaf-read-") as temporary:
        root = Path(temporary)
        subprocess.run(["ditto", "-x", "-k", str(archive), str(root)], check=True, capture_output=True)
        prefix = root / "certificate"
        subprocess.run(
            ["codesign", "-d", f"--extract-certificates={prefix}", str(root / "Workspace.app")],
            check=True, capture_output=True,
        )
        return hashlib.sha1(Path(str(prefix) + "0").read_bytes()).hexdigest().upper()


def expected_fields(args: argparse.Namespace) -> dict:
    if not TEAM.fullmatch(args.team_id) or not LEAF.fullmatch(args.leaf_sha1):
        raise ValueError("malformed Team or Developer ID leaf SHA-1")
    source_binding(args.source_revision, args.source_tree, args.builder_sha256)
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        raise ValueError("malformed app version")
    return {
        "source_revision": args.source_revision, "source_tree": args.source_tree,
        "builder_sha256": args.builder_sha256, "version": args.version,
        "team_id": args.team_id, "leaf_sha1": args.leaf_sha1,
    }


def check_signed(archive: Path, manifest_path: Path, expected: dict) -> dict:
    manifest = check_archive(
        archive, manifest_path, expected["source_revision"], expected["team_id"],
    )
    if manifest["version"] != expected["version"] or not re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        manifest["notary_submission_id"],
    ):
        raise ValueError("candidate version or notary submission identity mismatch")
    verify_native(archive, manifest)
    if signed_leaf(archive) != expected["leaf_sha1"]:
        raise ValueError("candidate Developer ID leaf mismatch")
    return manifest


def readback(destination: Path, expected: dict, receipt_sha256: str) -> dict:
    if not DIGEST.fullmatch(receipt_sha256) or destination.is_symlink():
        raise ValueError("invalid handoff receipt")
    private_parent(destination, require_absent=False)
    info = destination.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077 or {p.name for p in destination.iterdir()} != FILES:
        raise ValueError("candidate directory is incomplete or not private")
    for name in FILES:
        path = destination / name
        info = path.lstat()
        if not path.is_file() or path.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("candidate handoff file is not private and regular")
    receipt = destination / "handoff.json"
    if sha256_file(receipt) != receipt_sha256:
        raise ValueError("handoff receipt digest mismatch")
    handoff = unique_json(receipt)
    if set(handoff) != {
        "schema_version", "qualification", *expected, "bundle_identifier",
        "keychain_service", "app_cdhash", "notary_submission_id", "staple",
        "gatekeeper", "archive_sha256", "candidate_manifest_sha256",
    } or handoff["schema_version"] != 1 or handoff["qualification"] != "SIGNED_CANDIDATE_VERIFIED":
        raise ValueError("handoff schema or qualification mismatch")
    if any(handoff[key] != value for key, value in expected.items()):
        raise ValueError("handoff source or signer mismatch")
    if (handoff["bundle_identifier"] != "com.pcvantol.workspace.native-client" or
            handoff["keychain_service"] != "com.pcvantol.workspace.native-client.v2" or
            handoff["staple"] != "validated" or handoff["gatekeeper"] != "accepted"):
        raise ValueError("handoff app or notarization mismatch")
    archive = destination / "Workspace.app.zip"
    manifest_path = destination / "candidate-manifest.json"
    if (sha256_file(archive) != handoff["archive_sha256"] or
            sha256_file(manifest_path) != handoff["candidate_manifest_sha256"]):
        raise ValueError("preserved candidate bytes mismatch")
    manifest = check_signed(archive, manifest_path, expected)
    if (handoff["app_cdhash"] != manifest["app_cdhash"] or
            handoff["notary_submission_id"] != manifest["notary_submission_id"]):
        raise ValueError("handoff signed identity mismatch")
    return handoff


def preserve(args: argparse.Namespace) -> str:
    expected = expected_fields(args)
    manifest = check_signed(args.archive, args.manifest, expected)
    handoff = {
        "schema_version": 1, "qualification": "SIGNED_CANDIDATE_VERIFIED",
        **expected, "bundle_identifier": manifest["bundle_identifier"],
        "keychain_service": manifest["keychain_service"],
        "app_cdhash": manifest["app_cdhash"],
        "notary_submission_id": manifest["notary_submission_id"],
        "staple": "validated", "gatekeeper": "accepted",
        "archive_sha256": sha256_file(args.archive),
        "candidate_manifest_sha256": sha256_file(args.manifest),
    }
    receipt = atomic_store(args.archive, args.manifest, args.destination, handoff)
    readback(args.destination, expected, receipt)
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="action", required=True)
    for action in ("preserve", "verify"):
        command = subcommands.add_parser(action)
        command.add_argument("--destination", required=True, type=Path)
        command.add_argument("--source-revision", required=True)
        command.add_argument("--source-tree", required=True)
        command.add_argument("--builder-sha256", required=True)
        command.add_argument("--version", required=True)
        command.add_argument("--team-id", required=True)
        command.add_argument("--leaf-sha1", required=True)
        if action == "preserve":
            command.add_argument("--archive", required=True, type=Path)
            command.add_argument("--manifest", required=True, type=Path)
        else:
            command.add_argument("--handoff-sha256", required=True)
    args = parser.parse_args()
    try:
        if args.action == "preserve":
            receipt = preserve(args)
        else:
            receipt = args.handoff_sha256
            readback(args.destination, expected_fields(args), receipt)
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError) as error:
        parser.exit(2, f"SIGNED_CANDIDATE_HANDOFF=FAIL {type(error).__name__}: {error}\n")
    print(f"SIGNED_CANDIDATE_HANDOFF=PASS handoff_sha256={receipt}")


if __name__ == "__main__":
    main()
