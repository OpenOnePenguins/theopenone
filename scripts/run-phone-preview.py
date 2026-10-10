#!/usr/bin/env python3
"""Temporary HTTPS phone test of isolated Open One data, never the user's Store."""
import fcntl
import json
import os
import pathlib
import re
import shutil
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent
ROOT = WORKSPACE / '.build/mobile-preview'


def get(url, token=None):
    request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token} if token else {})
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.read()


def main():
    os.chdir(WORKSPACE)
    ROOT.mkdir(parents=True, exist_ok=True)
    lock = (ROOT / 'phone-preview.lock').open('w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit('A phone preview is already running. Stop it before starting another.')
    if not shutil.which('cloudflared'):
        raise SystemExit('Install cloudflared first: brew install cloudflared')
    if not (WORKSPACE / 'mobile/dist/index.html').is_file():
        raise SystemExit('Export the app first: cd mobile && npx expo export --platform web')
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1', 8088)) == 0:
            raise SystemExit('Port 8088 is in use. Stop the previous mobile preview first.')
    print('Starting a temporary Cloudflare HTTPS tunnel for SAMPLE data only.', flush=True)
    processes = []
    connection_file = ROOT / 'phone-connection.txt'
    def stop(*_):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, stop)
    try:
        with (ROOT / 'tunnel.log').open('w') as log:
            tunnel = subprocess.Popen(['cloudflared', 'tunnel', '--no-autoupdate', '--url', 'http://127.0.0.1:8088'], stdout=log, stderr=log, start_new_session=True)
            processes.append(tunnel)
            origin = None
            for _ in range(120):
                if tunnel.poll() is not None:
                    raise RuntimeError('Tunnel stopped. See .build/mobile-preview/tunnel.log')
                match = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com', (ROOT / 'tunnel.log').read_text())
                if match:
                    origin = match.group(0)
                    break
                time.sleep(.5)
            if not origin:
                raise RuntimeError('Cloudflare did not return a URL. See .build/mobile-preview/tunnel.log')
            # This host always uses .build/mobile-preview and a deterministic provider.
            # No real Store path, credentials or agent executable can be supplied here.
            previous = (ROOT / 'remote-connection.json').read_bytes() if (ROOT / 'remote-connection.json').exists() else None
            with (ROOT / 'host.log').open('w') as host_log:
                host = subprocess.Popen(['bash', 'scripts/run-mobile-preview.sh'], env={**os.environ, 'OPEN_ONE_PREVIEW_ORIGIN': origin}, stdout=host_log, stderr=host_log, start_new_session=True)
                processes.append(host)
                print('Building the Mac test host and checking the HTTPS connection…', flush=True)
                token = None
                for _ in range(360):
                    if host.poll() is not None:
                        raise RuntimeError('Mac test host stopped. See .build/mobile-preview/host.log')
                    try:
                        raw = (ROOT / 'remote-connection.json').read_bytes()
                        if raw != previous:
                            connection = json.loads(raw)
                            token = connection['token']
                            info = json.loads(get(origin + '/api/info', token))
                            state = json.loads(get(origin + '/api/state', token))
                            if info['generation'] == connection['generation'] and any(a['id'] == 'mobile-sample' for a in state['agents']):
                                break
                    except (OSError, ValueError, KeyError):
                        pass
                    time.sleep(.5)
                else:
                    raise RuntimeError('HTTPS readiness check timed out. See the preview logs.')
                link = origin + '/#' + token
                fd = os.open(connection_file, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
                with os.fdopen(fd, 'w') as out:
                    out.write(link + '\n')
                print('\nREADY FOR PHONE TEST — isolated sample, not your real conversations.\n' + link, flush=True)
                print('On iPhone: open this full link in Safari → Continue from your phone → send a message.\nKeep this Mac awake. Ctrl+C stops the link. The test host expires after one hour.', flush=True)
                while host.poll() is None and tunnel.poll() is None:
                    time.sleep(1)
    except KeyboardInterrupt:
        print('\nStopping phone preview and revoking its connection.', flush=True)
    finally:
        for process in reversed(processes):
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for process in reversed(processes):
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        connection_file.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
