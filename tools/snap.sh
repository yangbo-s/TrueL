#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts/screenshots
APP_SNAPSHOT="$PWD/artifacts/screenshots" build/TrueL.app/Contents/MacOS/TrueL -AppleShowScrollBars Always
