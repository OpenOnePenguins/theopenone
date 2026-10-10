#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Open One.app"
mkdir -p .build/native .build/module-cache "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
source scripts/toolchain.sh
# Direct compilation also works with Command Line Tools installations whose
# SwiftPM private manifest interface is older than their runtime library.
swiftc "${SWIFT_FLAGS[@]}" -O \
  -emit-library -emit-module -module-name OneCore Sources/OneCore/*.swift \
  -emit-module-path .build/native/OneCore.swiftmodule \
  -Xlinker -install_name -Xlinker @rpath/libOneCore.dylib \
  -o .build/native/libOneCore.dylib
swiftc "${SWIFT_FLAGS[@]}" -O \
  -I .build/native -L .build/native -lOneCore \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/OpenOne/*.swift -o "$APP/Contents/MacOS/OpenOne"
cp .build/native/libOneCore.dylib "$APP/Contents/Frameworks/"
cp scripts/one "$APP/Contents/Resources/one"
cp scripts/one-usage.py scripts/one-claude-statusline.py scripts/one-remote.py scripts/one-remote-client.py scripts/one-agent.py "$APP/Contents/Resources/"
# Optional Expo web export shares the native phone client's UI through our bridge.
# Generate it with: cd mobile && npx expo export --platform web
if [[ -f mobile/dist/index.html ]]; then
  mkdir -p "$APP/Contents/Resources/mobile-web"
  cp -R mobile/dist/. "$APP/Contents/Resources/mobile-web/"
fi
cp Sources/OpenOne/Assets/*.svg "$APP/Contents/Resources/"
bash scripts/build-icons.sh
cp Sources/OpenOne/Assets/*.png "$APP/Contents/Resources/"
cp .build/OpenOne.icns "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/one"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Open One</string>
<key>CFBundleDisplayName</key><string>Open One</string>
<key>CFBundleIdentifier</key><string>local.openone.app</string>
<key>CFBundleExecutable</key><string>OpenOne</string>
<key>CFBundleIconFile</key><string>OpenOne</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.7.16</string>
<key>CFBundleVersion</key><string>41</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Dictate a message to your coding agent.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Convert your spoken request to text for review before sending.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Reuse a per-user development certificate across builds and worktrees.
# Distribution builds can supply OPEN_ONE_SIGNING_IDENTITY explicitly.
python3 scripts/sign-app.py "$APP"
printf 'Built %s\n' "$APP"
