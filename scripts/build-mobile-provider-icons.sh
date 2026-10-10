#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
source scripts/toolchain.sh
swiftc "${SWIFT_FLAGS[@]}" scripts/build-mobile-provider-icons.swift -o .build/mobile-provider-icons
.build/mobile-provider-icons
