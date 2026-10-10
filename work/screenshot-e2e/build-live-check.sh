#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/toolchain.sh
swiftc "${SWIFT_FLAGS[@]}" -I .build/native -L .build/native -lOneCore -Xlinker -rpath -Xlinker "$PWD/.build/native" Sources/OpenOne/AgentRunner.swift Sources/OpenOne/ProviderTools.swift work/screenshot-e2e/live-image.swift -o .build/screenshot-live-check
