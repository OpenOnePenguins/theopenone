#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/native .build/module-cache
source scripts/toolchain.sh
swiftc "${SWIFT_FLAGS[@]}" -emit-library -emit-module -module-name OneCore Sources/OneCore/*.swift \
  -emit-module-path .build/native/OneCore.swiftmodule \
  -Xlinker -install_name -Xlinker @rpath/libOneCore.dylib -o .build/native/libOneCore.dylib
swiftc "${SWIFT_FLAGS[@]}" \
  -I .build/native -L .build/native -lOneCore \
  -Xlinker -rpath -Xlinker "$(pwd)/.build/native" \
  Sources/OpenOne/Store.swift Sources/OpenOne/Utilities.swift Sources/OpenOne/AgentRunner.swift Sources/OpenOne/ProviderTools.swift Sources/OpenOne/HerdrService.swift Sources/OpenOne/RoutingService.swift Sources/OpenOne/RegionCapture.swift scripts/native-tests.swift scripts/project-tests.swift scripts/tracking-tests.swift scripts/inbox-tests.swift scripts/discovery-tests.swift scripts/process-tests.swift scripts/screenshot-tests.swift scripts/resume-tests.swift scripts/provider-tests.swift scripts/store-regression-tests.swift scripts/herdr-tests.swift scripts/store-herdr-tests.swift scripts/utility-tests.swift \
  scripts/markdown-tests.swift scripts/approval-tests.swift -o .build/native/native-tests
.build/native/native-tests
python3 scripts/test_bridge.py
python3 scripts/test_utilities.py
python3 scripts/test_agent_transport.py
