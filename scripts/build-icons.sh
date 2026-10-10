#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/sync-brand-assets.sh
SOURCE="Sources/OpenOne/Assets/open-one-logo.png"
ICONSET=".build/OpenOne.iconset"
mkdir -p "$ICONSET"
# Package the approved square PNG at macOS's standard icon resolutions.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o .build/OpenOne.icns
