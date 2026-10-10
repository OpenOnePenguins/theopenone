#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
QA_APP="$PWD/.build/OpenOneE2E.app"
QA_RESULTS="$PWD/.build/e2e/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$QA_RESULTS"
ditto 'dist/Open One.app' "$QA_APP"
python3 - "$QA_APP/Contents/Info.plist" <<'PY'
import plistlib,sys,uuid
p=sys.argv[1]
with open(p,'rb') as f: data=plistlib.load(f)
data['CFBundleIdentifier']='local.openone.e2e.'+uuid.uuid4().hex
data['CFBundleName']='Open One E2E'
with open(p,'wb') as f: plistlib.dump(data,f)
PY
codesign --force --sign - "$QA_APP"
swiftc "${SWIFT_FLAGS[@]}" scripts/e2e/native-ui.swift -o .build/native-ui-e2e
.build/native-ui-e2e "$QA_APP" "$QA_RESULTS" "$@" | tee "$QA_RESULTS/run.log"
