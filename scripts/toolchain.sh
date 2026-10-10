# Sourced by build.sh and test.sh. Does not modify the installed toolchain.
SWIFT_FLAGS=(-swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path .build/module-cache)
TOOLCHAIN_DIR="$(xcode-select -p)/usr/include/swift"
if [[ -f "$TOOLCHAIN_DIR/module.modulemap" && -f "$TOOLCHAIN_DIR/bridging.modulemap" ]] && \
   grep -q 'module SwiftBridging' "$TOOLCHAIN_DIR/module.modulemap" && \
   grep -q 'module SwiftBridging' "$TOOLCHAIN_DIR/bridging.modulemap"; then
  python3 - "$TOOLCHAIN_DIR" <<'PY'
import json, sys
from pathlib import Path
directory = Path('.build/toolchain')
directory.mkdir(parents=True, exist_ok=True)
(directory / 'empty.modulemap').write_text('// Duplicate legacy SwiftBridging map omitted for this compilation.\n')
(directory / 'overlay.json').write_text(json.dumps({'version': 0, 'roots': [{'type': 'file', 'name': str(Path(sys.argv[1]) / 'module.modulemap'), 'external-contents': str((directory / 'empty.modulemap').resolve())}]}))
PY
  SWIFT_FLAGS+=(-vfsoverlay .build/toolchain/overlay.json -Xcc -ivfsoverlay -Xcc .build/toolchain/overlay.json)
fi
