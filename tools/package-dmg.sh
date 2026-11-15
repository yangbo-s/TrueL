#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

skip_build=false
case "${1:-}" in
  --skip-build) skip_build=true ;;
  --help|-h)
    echo "Usage: $0 [--skip-build]"
    echo "Build and package TrueL as build/TrueL.dmg."
    echo "--skip-build packages the existing signed build/TrueL.app unchanged."
    exit 0
    ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [--skip-build]" >&2
  exit 2
fi

if [[ "$skip_build" == false ]]; then ./build.sh; fi
app="$PWD/build/TrueL.app"
output="$PWD/build/TrueL.dmg"
if [[ ! -d "$app" ]]; then
  echo "Missing $app. Run ./build.sh first or omit --skip-build." >&2
  exit 1
fi
python3 tools/signing.py verify "$app"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/truel-dmg.XXXXXX")"
mount_point="$work_dir/mounted"
mounted=false
cleanup() {
  local result=$?
  trap - EXIT
  if [[ "$mounted" == true ]]; then
    if ! /usr/bin/hdiutil detach "$mount_point"; then
      echo "Could not detach $mount_point; retained $work_dir for cleanup." >&2
      exit 1
    fi
  fi
  rm -rf "$work_dir"
  exit "$result"
}
trap cleanup EXIT

mkdir "$work_dir/payload" "$mount_point"
/usr/bin/ditto "$app" "$work_dir/payload/TrueL.app"
ln -s /Applications "$work_dir/payload/Applications"
/usr/bin/hdiutil create \
  -volname TrueL -fs HFS+ -format UDZO -imagekey zlib-level=9 \
  -srcfolder "$work_dir/payload" "$work_dir/TrueL.dmg"
/usr/bin/hdiutil verify "$work_dir/TrueL.dmg"
/usr/bin/hdiutil attach -readonly -nobrowse \
  -mountpoint "$mount_point" "$work_dir/TrueL.dmg"
mounted=true

# Verify the mounted installer, including the unchanged app and drag-install link.
python3 tools/signing.py verify "$mount_point/TrueL.app"
python3 tools/verify-bundle-copy.py "$app" "$mount_point/TrueL.app"
test -x "$mount_point/TrueL.app/Contents/MacOS/TrueL"
test "$(readlink "$mount_point/Applications")" = /Applications
/usr/bin/hdiutil detach "$mount_point"
mounted=false

mv -f "$work_dir/TrueL.dmg" "$output"
/usr/bin/shasum -a 256 build/TrueL.dmg > build/TrueL.dmg.sha256
echo "Created $output"
echo "Open the DMG and drag TrueL into Applications."
