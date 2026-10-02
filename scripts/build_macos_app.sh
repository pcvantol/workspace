#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Workspace.app build requires macOS.' >&2
  exit 2
fi

usage() {
  echo 'Usage: build_macos_app.sh [--mode ad-hoc|developer-id] [--identity NAME --team-id ID --notary-profile NAME --source-revision SHA] [OUTPUT/Workspace.app]' >&2
  exit 2
}

mode=ad-hoc
identity=
team_id=
notary_profile=
source_revision=
output=
while (($#)); do
  case "$1" in
    --mode|--identity|--team-id|--notary-profile|--source-revision)
      (($# >= 2)) || usage
      case "$1" in
        --mode) mode="$2" ;;
        --identity) identity="$2" ;;
        --team-id) team_id="$2" ;;
        --notary-profile) notary_profile="$2" ;;
        --source-revision) source_revision="$2" ;;
      esac
      shift 2 ;;
    --*) usage ;;
    *) [[ -z "$output" ]] || usage; output="$1"; shift ;;
  esac
done
output="${output:-${TMPDIR:-/tmp}/workspace-client-dist/Workspace.app}"
[[ "$(basename "$output")" == Workspace.app && ! -L "$output" ]] || usage
[[ "$mode" == ad-hoc || "$mode" == developer-id ]] || usage

bundle_id=com.pcvantol.workspace.native-client
keychain_service=com.pcvantol.workspace.native-client.v2
package="$PWD/macos/WorkspaceClient"
scratch="${WORKSPACE_SWIFT_SCRATCH:-${TMPDIR:-/tmp}/workspace-client-swift-$(id -u)}"
version="$(plutil -extract version raw -o - product-version.json)"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$package/Resources/Info.plist")" == "$bundle_id" ]] || {
  echo 'Unexpected Workspace bundle identifier.' >&2; exit 2;
}
rg -Fq "private let service = \"$keychain_service\"" "$package/Sources/WorkspaceClient/ClientState.swift" || {
  echo 'Unexpected Workspace Keychain service.' >&2; exit 2;
}

if [[ "$mode" == developer-id ]]; then
  [[ "$identity" == 'Developer ID Application: '* && -n "$notary_profile" &&
     "$team_id" =~ ^[A-Z0-9]{10}$ && "$source_revision" =~ ^[0-9a-f]{40}$ ]] || {
    echo 'Developer ID mode requires an application identity, team ID, notary profile and exact source SHA.' >&2
    exit 2
  }
  [[ "$source_revision" == "$(git rev-parse HEAD)" &&
     "$source_revision" == "$(git ls-remote origin refs/heads/main | cut -f1)" &&
     -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo 'Developer ID mode requires clean, exact current protected main.' >&2
    exit 2
  }
  resolved_output="$(python3 - "$output" <<'PY'
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).resolve())
PY
)"
  [[ "$output" == /* && "$resolved_output" != "$PWD/"* ]] || {
    echo 'Developer ID output must be an absolute path outside the source checkout.' >&2
    exit 2
  }
  [[ ! -e "$output" && ! -e "${output}.zip" && ! -e "${output}.manifest.json" ]] || {
    echo 'Developer ID output already exists; choose an unused destination.' >&2
    exit 2
  }
  cleanup_incomplete_candidate() {
    if (($? != 0)); then
      rm -f -- "${output}.zip" "${output}.manifest.json"
      rm -rf -- "$output"
    fi
  }
  trap cleanup_incomplete_candidate EXIT
  # Signing needs its own confirmed L1/L4 resource slot. Never unlock or alter a Keychain here.
else
  [[ -z "$identity$team_id$notary_profile$source_revision" ]] || usage
fi

swift build --package-path "$package" --scratch-path "$scratch" -c release --product WorkspaceClient
binary_dir="$(swift build --package-path "$package" --scratch-path "$scratch" -c release --show-bin-path)"
mkdir -p "$(dirname "$output")"
if [[ "$mode" == ad-hoc ]]; then
  rm -rf -- "$output"
fi
mkdir -p "$output/Contents/MacOS"
cp "$binary_dir/WorkspaceClient" "$output/Contents/MacOS/WorkspaceClient"
cp "$package/Resources/Info.plist" "$output/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$output/Contents/Info.plist"
chmod 755 "$output/Contents/MacOS/WorkspaceClient"
plutil -lint "$output/Contents/Info.plist"
if otool -L "$output/Contents/MacOS/WorkspaceClient" | rg -qi python; then
  echo 'Native Client unexpectedly links Python.' >&2
  exit 1
fi

if [[ "$mode" == ad-hoc ]]; then
  # Local test only: no distribution signature, notarization or signed-Keychain proof.
  codesign --force --sign - --timestamp=none "$output"
  codesign --verify --strict --verbose=2 "$output"
  echo "Built local ad-hoc test bundle: $output"
  exit 0
fi

# The unsandboxed SwiftUI/URLSession/Keychain app needs no entitlements.
# Do not grant get-task-allow or hardened-runtime exceptions.
codesign --force --sign "$identity" --options runtime --timestamp "$output"
codesign --verify --deep --strict --verbose=2 "$output"
requirement="identifier \"$bundle_id\" and anchor apple generic and certificate leaf[subject.OU] = \"$team_id\""
codesign --verify --strict -R="$requirement" "$output"
signature_details="$(codesign -dv --verbose=4 "$output" 2>&1)"
[[ "$signature_details" == *"Authority=Developer ID Application:"* &&
   "$signature_details" == *"TeamIdentifier=$team_id"* &&
   "$signature_details" == *"(runtime)"* &&
   "$signature_details" == *"Timestamp="* ]] || {
  echo 'Developer ID signature, team, hardened runtime or secure timestamp is missing.' >&2
  exit 1
}
if codesign -d --entitlements - "$output" 2>/dev/null | rg -q '<key>'; then
  echo 'Unexpected signed entitlements in Workspace.app.' >&2
  exit 1
fi

# Notarize exact archive bytes, staple the app, then archive final deliverable.
ditto -c -k --keepParent "$output" "${output}.zip"
submitted_sha="$(shasum -a 256 "${output}.zip" | cut -d' ' -f1)"
receipt="$(xcrun notarytool submit "${output}.zip" --keychain-profile "$notary_profile" --wait --output-format json)"
submission_id="$(printf '%s' "$receipt" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("status") == "Accepted"; print(d["id"])')" || {
  echo 'Apple notarization was not accepted.' >&2
  exit 1
}
xcrun stapler staple "$output"
xcrun stapler validate "$output"
codesign --verify --deep --strict --verbose=2 "$output"
spctl --assess --type execute --verbose=2 "$output"
rm -- "${output}.zip"
ditto -c -k --keepParent "$output" "${output}.zip"
final_sha="$(shasum -a 256 "${output}.zip" | cut -d' ' -f1)"
app_cdhash="$(codesign -dv --verbose=4 "$output" 2>&1 | sed -n 's/^CDHash=//p')"
python3 - "$output" "$source_revision" "$version" "$bundle_id" "$keychain_service" "$team_id" "$submitted_sha" "$submission_id" "$final_sha" "$app_cdhash" <<'PY'
import json
import pathlib
import sys

output, source, version, bundle, service, team, submitted, submission, final, cdhash = sys.argv[1:]
manifest = {
    "schema_version": 1,
    "mode": "developer-id-notarized",
    "source_revision": source,
    "version": version,
    "bundle_identifier": bundle,
    "keychain_service": service,
    "team_id": team,
    "notary_submission_id": submission,
    "submitted_zip_sha256": submitted,
    "final_stapled_zip_sha256": final,
    "app_cdhash": cdhash,
}
pathlib.Path(output + ".manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
python3 scripts/verify_macos_app_candidate.py "${output}.zip" "${output}.manifest.json" \
  --source-revision "$source_revision" --team-id "$team_id"
echo "Built notarized Developer ID candidate: ${output}.zip ($final_sha)"
trap - EXIT
