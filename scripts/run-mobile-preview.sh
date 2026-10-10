#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mkdir -p .build/mobile-preview-bin .build/module-cache
swiftc "${SWIFT_FLAGS[@]}" -emit-library -emit-module -module-name OneCore Sources/OneCore/*.swift -emit-module-path .build/mobile-preview-bin/OneCore.swiftmodule -Xlinker -install_name -Xlinker @rpath/libOneCore.dylib -o .build/mobile-preview-bin/libOneCore.dylib
swiftc "${SWIFT_FLAGS[@]}" -I .build/mobile-preview-bin -L .build/mobile-preview-bin -lOneCore -Xlinker -rpath -Xlinker "$(pwd)/.build/mobile-preview-bin" Sources/OpenOne/Store.swift Sources/OpenOne/Utilities.swift Sources/OpenOne/AgentRunner.swift Sources/OpenOne/ProviderTools.swift Sources/OpenOne/HerdrService.swift Sources/OpenOne/RoutingService.swift Sources/OpenOne/RegionCapture.swift scripts/mobile-preview-host.swift -o .build/mobile-preview-bin/host
exec .build/mobile-preview-bin/host "$@"
