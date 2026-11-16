#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir="${1:-artifacts/quick-workflow-probe}"
mkdir -p "$probe_dir" .build/modules
xcrun swiftc -parse-as-library -module-cache-path .build/modules \
  tools/fixtures/SelectionFixture.swift -o "$probe_dir/selection-fixture"
xcrun swiftc -parse-as-library -module-cache-path .build/modules \
  Sources/TrueL/ShortcutModels.swift Sources/TrueL/ShortcutStore.swift \
  Sources/TrueL/ShortcutSequenceGate.swift Sources/TrueL/ShortcutMonitor.swift \
  Sources/TrueL/SystemPermissions.swift Sources/TrueL/SelectionBridge.swift \
  tools/check-quick-workflows.swift -o "$probe_dir/quick-workflow-probe"
"$probe_dir/quick-workflow-probe" "$probe_dir/selection-fixture" | tee "$probe_dir/result.log"
