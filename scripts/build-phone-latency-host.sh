#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mkdir -p .build/phone-latency .build/module-cache
swiftc "${SWIFT_FLAGS[@]}" -emit-library -emit-module -module-name OneCore Sources/OneCore/*.swift -emit-module-path .build/phone-latency/OneCore.swiftmodule -Xlinker -install_name -Xlinker @rpath/libOneCore.dylib -o .build/phone-latency/libOneCore.dylib
swiftc "${SWIFT_FLAGS[@]}" -I .build/phone-latency -L .build/phone-latency -lOneCore -Xlinker -rpath -Xlinker "$(pwd)/.build/phone-latency" Sources/OpenOne/Store.swift Sources/OpenOne/Utilities.swift Sources/OpenOne/AgentRunner.swift Sources/OpenOne/ProviderTools.swift Sources/OpenOne/HerdrService.swift Sources/OpenOne/RoutingService.swift Sources/OpenOne/RegionCapture.swift scripts/phone-latency-host.swift -o .build/phone-latency/host
