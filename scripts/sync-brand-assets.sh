#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/branding .build/module-cache
source scripts/toolchain.sh
swiftc "${SWIFT_FLAGS[@]}" scripts/export-brand-assets.swift -o .build/branding/export-brand-assets
.build/branding/export-brand-assets "$@"
