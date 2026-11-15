#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r version checksum < <(python3 - <<'PY'
import json
c = json.load(open('Config/release.json'))
print(c['sparkleVersion'], c['sparkleToolsSHA256'])
PY
)
archive="$PWD/.build/Sparkle-$version.tar.xz"
mkdir -p .build
if [[ ! -f "$archive" ]] || [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" != "$checksum" ]]; then
  curl -fL --retry 2 --max-time 120 -o "$archive.download" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
  actual="$(shasum -a 256 "$archive.download" | cut -d ' ' -f 1)"
  [[ "$actual" == "$checksum" ]] || { echo "Sparkle tool checksum mismatch" >&2; exit 1; }
  mv "$archive.download" "$archive"
fi
mkdir -p .build/sparkle-tools
tar -xJf "$archive" -C .build/sparkle-tools
echo "Verified Sparkle $version tools"
