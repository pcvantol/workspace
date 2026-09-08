#!/usr/bin/env python3
"""Inspect, plan, or explicitly apply Workspace's version operation.

The helper has no commit, push, publication, or qualification authority. A
protected delivery route must commit the manifest and receipt together, then
qualify that exact resulting SHA.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

PRODUCT = "workspace"
VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
OPERATION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{7,127}$")
POLICY_REVISION = "workspace-bootstrap-release-cadence-v2"
RELEASE_BRANCH = re.compile(r"^release-((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))$")

def _pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate manifest key: {key}")
        result[key] = value
    return result

def _read_object(target: Path, description: str) -> dict[str, object]:
    try:
        payload = json.loads(target.read_text(encoding="utf-8"), object_pairs_hook=_pairs)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{description} is unreadable") from error
    if not isinstance(payload, dict):
        raise RuntimeError(f"{description} must be an object")
    return payload


def current(root: Path) -> tuple[Path, dict[str, object], tuple[int, int, int]]:
    target = root.resolve() / "product-version.json"
    payload = _read_object(target, "canonical product version manifest")
    if payload.get("schema_version") != 1 or isinstance(payload.get("schema_version"), bool):
        raise RuntimeError("canonical product version manifest has an unsupported schema")
    if payload.get("product") != PRODUCT:
        raise RuntimeError(f"canonical product version manifest must identify {PRODUCT}")
    value = payload.get("version")
    if not isinstance(value, str) or VERSION.fullmatch(value) is None:
        raise RuntimeError("canonical product version must be stable X.Y.Z")
    return target, payload, tuple(int(part) for part in value.split("."))

def _atomic_write(path: Path, text: str) -> None:
    mode = path.stat().st_mode if path.exists() else 0o100644
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _head(root: Path) -> str:
    result = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], text=True,
                            capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("version operation requires a Git checkout with HEAD")
    return result.stdout.strip()


def verify_release_source(root: Path, branch: str, approved_source: str) -> str:
    """Verify a release candidate's exact source/version binding, read-only.

    The caller supplies an exact source already approved by its owning route;
    ancestry is intentionally insufficient because it permits extra commits.
    """
    match = RELEASE_BRANCH.fullmatch(branch)
    if match is None:
        raise RuntimeError("release branch must be exactly release-X.Y.Z")
    if re.fullmatch(r"[0-9a-f]{40}", approved_source) is None:
        raise RuntimeError("approved release source must be a full source revision")
    _, payload, _ = current(root)
    if payload["version"] != match.group(1):
        raise RuntimeError("release branch target and canonical product version disagree")
    if _head(root.resolve()) != approved_source:
        raise RuntimeError("release candidate HEAD is not the exact approved source")
    return match.group(1)


def _target(actual: tuple[int, int, int], component: str | None, exact: str | None) -> str:
    if (component is None) == (exact is None):
        raise RuntimeError("provide exactly one requested bump or exact target version")
    if exact is not None:
        if VERSION.fullmatch(exact) is None:
            raise RuntimeError("the requested release version must be stable X.Y.Z")
        return exact
    major, minor, patch = actual
    if component == "none":
        return f"{major}.{minor}.{patch}"
    if component == "patch":
        return f"{major}.{minor}.{patch + 1}"
    if component == "minor":
        return f"{major}.{minor + 1}.0"
    raise RuntimeError("major requires explicit release authority")


def _receipt(root: Path, operation_id: str, event_lineage: str, expected_head: str,
             expected_version: str, component: str | None, exact: str | None,
             determined: str, policy_revision: str) -> tuple[Path, dict[str, object]]:
    if OPERATION_ID.fullmatch(operation_id) is None:
        raise RuntimeError("operation ID must be 8-128 safe identifier characters")
    if not event_lineage.strip() or re.fullmatch(r"[0-9a-f]{40}", expected_head) is None:
        raise RuntimeError("event lineage and a full expected source revision are required")
    if policy_revision != POLICY_REVISION:
        raise RuntimeError(f"unsupported Workspace version policy revision: {policy_revision}")
    release_class = "EXACT" if exact is not None else {"patch": "PATCH", "minor": "MINOR", "none": "NO_BUMP"}.get(component)
    if release_class is None:
        raise RuntimeError("unsupported bootstrap release classification")
    requested: dict[str, object] = {"exact_version": exact} if exact is not None else {"bump": component}
    value = {
        "schema_version": 1, "operation_id": operation_id, "product": PRODUCT,
        "policy_revision": policy_revision, "event_lineage": event_lineage,
        "expected_source_revision": expected_head, "expected_version": expected_version,
        "requested": requested, "determined_version": determined,
        "release_class": release_class, "classification_rationale": event_lineage,
        "allowed_projection_paths": ["product-version.json"], "result_commit": None,
    }
    return root / ".version-operations" / f"{operation_id}.json", value


def plan(root: Path, component: str | None, exact: str | None, expected_version: str,
         operation_id: str, event_lineage: str, expected_head: str,
         policy_revision: str = POLICY_REVISION) -> dict[str, object]:
    _, payload, parsed = current(root)
    actual = payload["version"]
    if actual != expected_version:
        raise RuntimeError(f"stale version operation: expected {expected_version}, found {actual}")
    if _head(root) != expected_head:
        raise RuntimeError("stale version operation: source HEAD differs from expected source revision")
    determined = _target(parsed, component, exact)
    _, value = _receipt(root.resolve(), operation_id, event_lineage, expected_head, expected_version,
                        component, exact, determined, policy_revision)
    return value


def apply(root: Path, component: str | None, exact: str | None, expected_version: str,
          operation_id: str, event_lineage: str, expected_head: str,
          policy_revision: str = POLICY_REVISION) -> str:
    root = root.resolve()
    target, payload, parsed = current(root)
    actual = payload["version"]
    if _head(root) != expected_head:
        raise RuntimeError("stale version operation: source HEAD differs from expected source revision")
    # Calculate from the expected baseline when recovering after a crash, never
    # from the already-written target.
    if VERSION.fullmatch(expected_version) is None:
        raise RuntimeError("expected version must be stable X.Y.Z")
    determined = _target(parsed if actual == expected_version else tuple(map(int, expected_version.split("."))), component, exact)
    receipt_path, receipt = _receipt(root, operation_id, event_lineage, expected_head, expected_version,
                                     component, exact, determined, policy_revision)
    if receipt_path.exists():
        if _read_object(receipt_path, "version operation receipt") != receipt:
            raise RuntimeError("operation ID conflict: existing receipt has different meaning")
        if actual != determined:
            raise RuntimeError("operation ID conflict: receipt and canonical version disagree")
        return determined
    if actual not in (expected_version, determined):
        raise RuntimeError(f"stale version operation: expected {expected_version}, found {actual}")
    if actual == expected_version and determined != actual:
        payload["version"] = determined
        _atomic_write(target, json.dumps(payload, indent=2, sort_keys=True) + "\n")
    receipt_path.parent.mkdir(mode=0o755, exist_ok=True)
    _atomic_write(receipt_path, json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return determined


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path.cwd())
    parser.add_argument("--bump", choices=("none", "patch", "minor"))
    parser.add_argument("--set-version")
    parser.add_argument("--expected-version")
    parser.add_argument("--operation-id")
    parser.add_argument("--event-lineage")
    parser.add_argument("--expected-head")
    parser.add_argument("--policy-revision", default=POLICY_REVISION)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--verify-release-source", action="store_true")
    parser.add_argument("--release-branch")
    parser.add_argument("--approved-source")
    args = parser.parse_args(argv)
    if args.check:
        if any((args.bump, args.set_version, args.operation_id, args.plan, args.verify_release_source)):
            parser.error("--check cannot change or plan a version")
        _, payload, _ = current(args.source_root)
        print(f"PRODUCT_VERSION=PASS version={payload['version']}")
        return 0
    if args.verify_release_source:
        if any((args.bump, args.set_version, args.plan, args.operation_id, args.expected_version,
                args.event_lineage, args.expected_head)):
            parser.error("--verify-release-source is a separate read-only operation")
        if not args.release_branch or not args.approved_source:
            parser.error("release verification requires --release-branch and --approved-source")
        print("RELEASE_SOURCE=PASS version=" + verify_release_source(
            args.source_root, args.release_branch, args.approved_source
        ))
        return 0
    if not all((args.expected_version, args.operation_id, args.event_lineage, args.expected_head)):
        parser.error("version operations require --expected-version, --operation-id, --event-lineage and --expected-head")
    if args.plan:
        print(json.dumps(plan(args.source_root, args.bump, args.set_version, args.expected_version,
                              args.operation_id, args.event_lineage, args.expected_head,
                              args.policy_revision), sort_keys=True))
    else:
        print("PRODUCT_VERSION=" + apply(args.source_root, args.bump, args.set_version, args.expected_version,
                                           args.operation_id, args.event_lineage, args.expected_head,
                                           args.policy_revision))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
