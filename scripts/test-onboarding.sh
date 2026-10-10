#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/native .build/module-cache
source scripts/toolchain.sh
RESULTS="$PWD/.build/onboarding-e2e/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS"
swiftc "${SWIFT_FLAGS[@]}" -emit-library -emit-module -module-name OneCore Sources/OneCore/*.swift -emit-module-path .build/native/OneCore.swiftmodule -Xlinker -install_name -Xlinker @rpath/libOneCore.dylib -o .build/native/libOneCore.dylib
sources=()
for file in Sources/OpenOne/*.swift; do
  if [[ "$file" != "Sources/OpenOne/App.swift" ]]; then sources+=("$file"); fi
done
swiftc "${SWIFT_FLAGS[@]}" -I .build/native -L .build/native -lOneCore -Xlinker -rpath -Xlinker "$PWD/.build/native" "${sources[@]}" scripts/onboarding-tests.swift -o .build/native/onboarding-tests
cp Sources/OpenOne/Assets/*.svg Sources/OpenOne/Assets/*.png .build/native/
.build/native/onboarding-tests "$RESULTS" | tee "$RESULTS/run.log"
