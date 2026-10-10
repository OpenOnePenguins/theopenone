#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
sources=()
for file in Sources/OpenOne/*.swift; do
  if [[ "$file" != "Sources/OpenOne/App.swift" ]]; then sources+=("$file"); fi
done
swiftc "${SWIFT_FLAGS[@]}" -I .build/native -L .build/native -lOneCore \
  -Xlinker -rpath -Xlinker "$PWD/.build/native" \
  "${sources[@]}" scripts/e2e/render-approvals.swift -o .build/native/render-approvals
cp Sources/OpenOne/Assets/*.svg Sources/OpenOne/Assets/*.png .build/native/
.build/native/render-approvals "${1:-.build/approval-ui}"
