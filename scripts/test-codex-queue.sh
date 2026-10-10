#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
# scripts/test.sh or scripts/build.sh builds OneCore first.
swiftc "${SWIFT_FLAGS[@]}" -I .build/native -L .build/native -lOneCore \
  -Xlinker -rpath -Xlinker "$(pwd)/.build/native" \
  Sources/OpenOne/AgentRunner.swift Sources/OpenOne/ProviderTools.swift scripts/e2e/codex-queue-driver.swift \
  -o .build/native/codex-queue-driver
python3 scripts/e2e/codex-queue.py
