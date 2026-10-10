#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
QA_APP=".build/UtilityServiceSmoke.app"
mkdir -p "$QA_APP/Contents/MacOS" "$QA_APP/Contents/Resources" "$QA_APP/Contents/Frameworks"
cp .build/native/libOneCore.dylib "$QA_APP/Contents/Frameworks/"
cp scripts/one-remote.py "$QA_APP/Contents/Resources/"
cat > "$QA_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.openone.utility-smoke</string><key>CFBundleExecutable</key><string>UtilityServiceSmoke</string></dict></plist>
PLIST
swiftc "${SWIFT_FLAGS[@]}" -I .build/native -L .build/native -lOneCore -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/OpenOne/Utilities.swift Sources/OpenOne/ProviderTools.swift scripts/utility-service-smoke.swift -o "$QA_APP/Contents/MacOS/UtilityServiceSmoke"
"$QA_APP/Contents/MacOS/UtilityServiceSmoke"
