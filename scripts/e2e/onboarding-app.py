#!/usr/bin/env python3
"""Launch a disposable packaged app for native onboarding UI verification.

Usage: python3 scripts/e2e/onboarding-app.py [--restart RUN_DIRECTORY]
No real accounts, transcripts, or agent requests are used. Drive the displayed
setup through native UI automation, then quit this fixture app normally.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--restart', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
if args.restart:
    run = args.restart.resolve()
else:
    run = repo / '.build' / 'onboarding-ui' / time.strftime('%Y%m%d-%H%M%S')
    run.mkdir(parents=True)
app = run / 'Open One Setup Test.app'
root = run / 'data'
bin_dir = run / 'bin'
project = run / 'Welcome project'
if not args.restart:
    shutil.copytree(repo / 'dist' / 'Open One.app', app)
    info = app / 'Contents/Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    metadata['CFBundleIdentifier'] = 'local.openone.onboarding.' + uuid.uuid4().hex
    metadata['CFBundleName'] = 'Open One Setup Test'
    metadata['CFBundleDisplayName'] = 'Open One Setup Test'
    # Preserve isolation if a GUI tool or Launch Services reopens the app.
    metadata['LSEnvironment'] = {'OPEN_ONE_HOME': str(root), 'PATH': str(bin_dir) + ':/usr/bin:/bin:/usr/sbin:/sbin'}
    info.write_bytes(plistlib.dumps(metadata))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    root.mkdir()
    (root / 'preferences.json').write_text(json.dumps({'discoveryEnabled': False}))
    bin_dir.mkdir()
    project.mkdir()
    subprocess.run(['git', 'init', '-q', str(project)], check=True)
    for provider in ('claude', 'codex'):
        script = bin_dir / provider
        script.write_text('''#!/bin/sh
case "$1" in
  --version) echo 'onboarding fixture 1.0'; exit 0 ;;
  auth) echo '{"loggedIn":true}'; exit 0 ;;
  login) echo 'Logged in using ChatGPT' >&2; exit 0 ;;
esac
printf '%s\\n' "$0 $*" >> "$OPEN_ONE_HOME/fixture-requests.log"
if [ "$1" = exec ]; then
  echo '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
  echo '{"type":"item.completed","item":{"type":"agent_message","text":"Hello from Codex. Your conversation is connected."}}'
else
  echo '{"type":"system","session_id":"22222222-2222-4222-8222-222222222222"}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello from Claude. Your conversation is connected."}]}}'
fi
''')
        script.chmod(0o700)

env = dict(os.environ, OPEN_ONE_HOME=str(root), PATH=str(bin_dir) + ':/usr/bin:/bin:/usr/sbin:/sbin')
with (run / 'app.log').open('ab') as log:
    process = subprocess.Popen([str(app / 'Contents/MacOS/OpenOne')], env=env, stdout=log, stderr=log, start_new_session=True)
details = {'pid': process.pid, 'app': str(app), 'root': str(root), 'project': str(project), 'run': str(run)}
(run / 'launch.json').write_text(json.dumps(details, indent=2))
print(json.dumps(details, indent=2))
