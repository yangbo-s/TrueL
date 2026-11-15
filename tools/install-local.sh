#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  ""|--open) ;;
  *) echo "Usage: $0 [--open]" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then exit 2; fi
app="$PWD/build/TrueL.app"
destination=/Applications/TrueL.app
python3 tools/signing.py verify "$app"
if /usr/bin/pgrep -x TrueL >/dev/null; then
  echo "Quit TrueL before updating; your current draft will not be closed automatically." >&2
  exit 1
else
  process_status=$?
  if [[ "$process_status" != 1 ]]; then
    echo "Unable to check whether TrueL is running; refusing to update it." >&2
    exit 1
  fi
fi
if [[ -L "$destination" ]]; then
  echo "Refusing to replace a symbolic link at $destination." >&2
  exit 1
fi
if [[ -e "$destination" ]]; then
  existing_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist")"
  if [[ "$existing_id" != com.truel.prototype ]]; then
    echo "A different application occupies $destination; refusing to replace it." >&2
    exit 1
  fi
fi
work_dir="$(mktemp -d /Applications/.TrueL-install.XXXXXX)"
previous=false
installed=false
complete=false
cleanup() {
  local result=$?
  trap - EXIT
  if [[ "$complete" != true ]]; then
    if [[ "$installed" == true ]]; then rm -rf "$destination"; fi
    if [[ "$previous" == true ]]; then mv "$work_dir/Previous.app" "$destination"; fi
  fi
  rm -rf "$work_dir"
  exit "$result"
}
trap cleanup EXIT
/usr/bin/ditto "$app" "$work_dir/TrueL.app"
python3 tools/signing.py verify "$work_dir/TrueL.app"
if [[ -e "$destination" ]]; then
  mv "$destination" "$work_dir/Previous.app"
  previous=true
fi
mv "$work_dir/TrueL.app" "$destination"
installed=true
python3 tools/signing.py verify "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$destination"
complete=true
echo "Installed $destination with the pinned signing identity."
if [[ "${1:-}" == --open ]]; then open "$destination"; fi
