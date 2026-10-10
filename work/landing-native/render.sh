#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/toolchain.sh
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/OpenOne/Views.swift').read_text()
assert '@State private var pinned = false' in s
s=s.replace('@State private var pinned = false','@State private var pinned = ProcessInfo.processInfo.environment["OPEN_ONE_RENDER_EXPANDED"] == "1"',1)
Path('.build/native/LandingViews.swift').write_text(s)
PY
sources=()
for file in Sources/OpenOne/*.swift; do
  if [[ "$file" != "Sources/OpenOne/App.swift" && "$file" != "Sources/OpenOne/Views.swift" ]]; then sources+=("$file"); fi
done
swiftc "${SWIFT_FLAGS[@]}" -I .build/native -L .build/native -lOneCore -Xlinker -rpath -Xlinker "$(pwd)/.build/native" "${sources[@]}" .build/native/LandingViews.swift work/landing-native/render.swift -o .build/native/render-landing
cp Sources/OpenOne/Assets/*.svg .build/native/
cp Sources/OpenOne/Assets/*.png .build/native/
.build/native/render-landing landing/assets/native
