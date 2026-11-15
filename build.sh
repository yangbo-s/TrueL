#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
config=release
if [[ " ${*:-} " == *" --debug "* ]]; then config=debug; fi
python3 tools/signing.py check
mkdir -p build .build/cache .build/config .build/security .build/modules
export CLANG_MODULE_CACHE_PATH="$PWD/.build/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/modules"
flags=(--cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build "${flags[@]}" -c "$config"
bin="$(swift build "${flags[@]}" -c "$config" --show-bin-path)"
app="$PWD/build/TrueL.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/TrueL" "$app/Contents/MacOS/TrueL"
python3 tools/write-info.py "$app/Contents/Info.plist"
framework=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$framework"
mkdir -p "$app/Contents/Frameworks"
# ditto preserves the framework's versioned symbolic links.
rm -rf "$app/Contents/Frameworks/Sparkle.framework"
/usr/bin/ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
python3 tools/signing.py sign "$app"
echo "Built $app"
if [[ " ${*:-} " == *" --open "* ]]; then ./tools/install-local.sh --open; fi
