#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Workspace.app build requires macOS.' >&2
  exit 2
fi

package="$PWD/macos/WorkspaceClient"
output="${1:-${TMPDIR:-/tmp}/workspace-client-dist/Workspace.app}"
if [[ "$(basename "$output")" != Workspace.app || -L "$output" ]]; then
  echo 'Output must name a non-symlink Workspace.app bundle.' >&2
  exit 2
fi
scratch="${WORKSPACE_SWIFT_SCRATCH:-${TMPDIR:-/tmp}/workspace-client-swift-$(id -u)}"
version="$(plutil -extract version raw -o - product-version.json)"
swift build --package-path "$package" --scratch-path "$scratch" -c release --product WorkspaceClient
binary_dir="$(swift build --package-path "$package" --scratch-path "$scratch" -c release --show-bin-path)"
mkdir -p "$(dirname "$output")"
rm -rf -- "$output"
mkdir -p "$output/Contents/MacOS"
cp "$binary_dir/WorkspaceClient" "$output/Contents/MacOS/WorkspaceClient"
cp "$package/Resources/Info.plist" "$output/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$output/Contents/Info.plist"
chmod 755 "$output/Contents/MacOS/WorkspaceClient"
# Ad hoc signing only makes a local test bundle runnable; it is not a trusted
# distribution signature or a qualification of Keychain behavior on another Mac.
codesign --force --sign - --timestamp=none "$output"
codesign --verify --strict --verbose=2 "$output"
plutil -lint "$output/Contents/Info.plist"
echo "Built local test bundle: $output"
