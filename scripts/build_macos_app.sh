#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Workspace.app build requires macOS.' >&2
  exit 2
fi

usage() {
  echo 'Usage: build_macos_app.sh [--mode ad-hoc|developer-id] [--isolated-test-adapter] [--identity DEVELOPER_ID_SHA1 --team-id ID --notary-profile NAME --source-revision SHA] [OUTPUT/Workspace.app]' >&2
  exit 2
}

mode=ad-hoc
identity=
team_id=
notary_profile=
source_revision=
output=
output_supplied=0
isolated_test_adapter=0
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
    --isolated-test-adapter) isolated_test_adapter=1; shift ;;
    --*) usage ;;
    *) [[ -z "$output" ]] || usage; output="$1"; output_supplied=1; shift ;;
  esac
done
output="${output:-${TMPDIR:-/tmp}/workspace-client-dist/Workspace.app}"
[[ "$(basename "$output")" == Workspace.app && ! -L "$output" ]] || usage
[[ "$mode" == ad-hoc || "$mode" == developer-id ]] || usage
if ((isolated_test_adapter == 1)) && [[ "$mode" != ad-hoc ]]; then
  echo 'The isolated credential adapter is available only for ad-hoc test bundles.' >&2
  exit 2
fi

bundle_id=com.pcvantol.workspace.native-client
keychain_service=com.pcvantol.workspace.native-client.v2
package="$PWD/macos/WorkspaceClient"
scratch="${WORKSPACE_SWIFT_SCRATCH:-${TMPDIR:-/tmp}/workspace-client-swift-$(id -u)}"
swift_flags=()
if ((isolated_test_adapter == 1)); then
  scratch="${scratch}-isolated-conversations"
  swift_flags=(-Xswiftc -DWORKSPACE_ISOLATED_TEST)
fi
version="$(plutil -extract version raw -o - product-version.json)"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$package/Resources/Info.plist")" == "$bundle_id" ]] || {
  echo 'Unexpected Workspace bundle identifier.' >&2; exit 2;
}
grep -Fq "private let service = \"$keychain_service\"" "$package/Sources/WorkspaceClient/ClientState.swift" || {
  echo 'Unexpected Workspace Keychain service.' >&2; exit 2;
}

check_protected_source() {
  [[ "$(git remote get-url origin)" == 'https://github.com/pcvantol/workspace.git' &&
     "$source_revision" == "$(git rev-parse HEAD)" &&
     "$source_revision" == "$(git ls-remote origin refs/heads/main | cut -f1)" &&
     -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo 'Developer ID mode requires canonical Workspace origin and clean, exact current protected main throughout the build.' >&2
    exit 2
  }
}

if [[ "$mode" == developer-id ]]; then
  (( output_supplied == 1 )) || {
    echo 'Developer ID mode requires an explicit private output destination.' >&2
    exit 2
  }
  umask 077
  [[ "$identity" =~ ^[A-F0-9]{40}$ && -n "$notary_profile" &&
     "$team_id" =~ ^[A-Z0-9]{10}$ && "$source_revision" =~ ^[0-9a-f]{40}$ ]] || {
    echo 'Developer ID mode requires an application identity SHA-1, team ID, notary profile and exact source SHA.' >&2
    exit 2
  }
  check_protected_source
  identity_matches="$(security find-identity -v -p codesigning | awk -v sha="$identity" -v team="$team_id" \
    '$2 == sha && index($0, "\"Developer ID Application: ") && index($0, "(" team ")\"") { print }')"
  [[ -n "$identity_matches" && "$identity_matches" != *$'\n'* ]] || {
    echo 'The exact Developer ID Application SHA-1 and team must identify one valid signing certificate.' >&2
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
  output_parent="$(dirname "$output")"
  [[ ! -L "$output_parent" ]] || {
    echo 'Developer ID output parent cannot be a symlink.' >&2
    exit 2
  }
  mkdir -p -- "$output_parent"
  parent_mode="$(stat -f %Lp "$output_parent")"
  [[ "$(stat -f %u "$output_parent")" == "$(id -u)" ]] &&
    (( (8#$parent_mode & 077) == 0 )) || {
    echo 'Developer ID output parent must be owned by this user and private.' >&2
    exit 2
  }
  [[ ! -e "$output" && ! -L "$output" &&
     ! -e "${output}.zip" && ! -L "${output}.zip" &&
     ! -e "${output}.manifest.json" && ! -L "${output}.manifest.json" ]] || {
    echo 'Developer ID output already exists; choose an unused destination.' >&2
    exit 2
  }
  signed_scratch=
  cleanup_incomplete_candidate() {
    if (($? != 0)); then
      rm -f -- "${output}.zip" "${output}.manifest.json"
      rm -rf -- "$output"
    fi
    if [[ -n "$signed_scratch" ]]; then
      rm -rf -- "$signed_scratch"
    fi
  }
  trap cleanup_incomplete_candidate EXIT
  # A signed candidate must never copy bytes from a concurrent/shared Swift build.
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/workspace-client-signed.XXXXXXXX")"
  signed_scratch="$scratch"
  # Signing needs its own confirmed L1/L4 resource slot. Never unlock or alter a Keychain here.
else
  [[ -z "$identity$team_id$notary_profile$source_revision" ]] || usage
fi

if ((isolated_test_adapter == 1)); then
  swift build --package-path "$package" --scratch-path "$scratch" -c release --product WorkspaceClient "${swift_flags[@]}"
else
  swift build --package-path "$package" --scratch-path "$scratch" -c release --product WorkspaceClient
fi
binary_dir="$(swift build --package-path "$package" --scratch-path "$scratch" -c release --show-bin-path)"
if [[ "$mode" == developer-id ]]; then
  # The built bytes must still correspond to the protected tree admitted above.
  check_protected_source
fi
mkdir -p "$(dirname "$output")"
if [[ "$mode" == ad-hoc ]]; then
  rm -rf -- "$output"
fi
mkdir -p "$output/Contents/MacOS"
cp "$binary_dir/WorkspaceClient" "$output/Contents/MacOS/WorkspaceClient"
cp "$package/Resources/Info.plist" "$output/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$output/Contents/Info.plist"
if ((isolated_test_adapter == 1)); then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.pcvantol.workspace.native-client.isolated-test' "$output/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :WorkspaceIsolatedTestAdapter bool true' "$output/Contents/Info.plist"
fi
chmod 755 "$output/Contents/MacOS/WorkspaceClient"
plutil -lint "$output/Contents/Info.plist"
if otool -L "$output/Contents/MacOS/WorkspaceClient" | grep -qi python; then
  echo 'Native Client unexpectedly links Python.' >&2
  exit 1
fi

if [[ "$mode" == ad-hoc ]]; then
  # Local test only: no distribution signature, notarization or signed-Keychain proof.
  codesign --force --sign - --timestamp=none "$output"
  codesign --verify --strict --verbose=2 "$output"
  if ((isolated_test_adapter == 1)); then
    echo "Built isolated-adapter ad-hoc test bundle: $output"
  else
    echo "Built local ad-hoc test bundle: $output"
  fi
  exit 0
fi

check_protected_source
# The unsandboxed SwiftUI/URLSession/Keychain app needs no entitlements.
# Do not grant get-task-allow or hardened-runtime exceptions.
codesign --force --sign "$identity" --options runtime --timestamp "$output"
codesign --verify --deep --strict --verbose=2 "$output"
requirement="identifier \"$bundle_id\" and anchor apple generic and certificate leaf[subject.OU] = \"$team_id\""
codesign --verify --strict -R="$requirement" "$output"
# The prefix is an option value; a separate word is parsed as another code path.
codesign -d --extract-certificates="$signed_scratch/signing-cert" "$output"
python3 - "$signed_scratch/signing-cert0" "$identity" <<'PY'
import hashlib
import pathlib
import sys

leaf = pathlib.Path(sys.argv[1]).read_bytes()
if hashlib.sha1(leaf).hexdigest().upper() != sys.argv[2]:
    raise SystemExit('Signed leaf certificate does not match the authorized SHA-1.')
PY
signature_details="$(codesign -dv --verbose=4 "$output" 2>&1)"
[[ "$signature_details" == *"Authority=Developer ID Application:"* &&
   "$signature_details" == *"TeamIdentifier=$team_id"* &&
   "$signature_details" == *"(runtime)"* &&
   "$signature_details" == *"Timestamp="* ]] || {
  echo 'Developer ID signature, team, hardened runtime or secure timestamp is missing.' >&2
  exit 1
}
if codesign -d --entitlements - "$output" 2>/dev/null | grep -q '<key>'; then
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
rm -rf -- "$signed_scratch"
trap - EXIT
