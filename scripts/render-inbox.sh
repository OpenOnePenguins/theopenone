#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
sources=()
for file in Sources/OpenOne/*.swift; do
  if [[ "$file" != "Sources/OpenOne/App.swift" ]]; then sources+=("$file"); fi
done
swiftc "${SWIFT_FLAGS[@]}" -I .build/native -L .build/native -lOneCore \
  -Xlinker -rpath -Xlinker "$(pwd)/.build/native" \
  "${sources[@]}" scripts/e2e/render-inbox.swift -o .build/native/render-inbox
cp Sources/OpenOne/Assets/*.svg .build/native/
cp Sources/OpenOne/Assets/*.png .build/native/
.build/native/render-inbox "${1:-.build/inbox-review}" "${@:2}"
