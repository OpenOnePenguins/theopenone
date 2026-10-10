#!/usr/bin/env python3
"""Read supported CLI quota interfaces without reading or exporting credentials."""
import argparse, json, os, pathlib, selectors, subprocess, sys, time


def codex_windows(result):
    buckets = result.get('rateLimitsByLimitId') or {'codex': result.get('rateLimits')}
    windows = []
    for key, bucket in buckets.items():
        if not isinstance(bucket, dict):
            continue
        for slot in ('primary', 'secondary'):
            value = bucket.get(slot)
            if not isinstance(value, dict) or not isinstance(value.get('usedPercent'), (int, float)):
                continue
            minutes = value.get('windowDurationMins')
            label = 'Session' if minutes == 300 else 'Weekly' if minutes == 10080 else f'{minutes} min' if minutes else slot.title()
            windows.append(dict(id=f'{key}-{slot}', label=label, bucket=bucket.get('limitName') or key,
                                used=min(100, max(0, value['usedPercent'])), resetsAt=value.get('resetsAt'), plan=bucket.get('planType')))
    return windows


def read_codex(executable):
    process = subprocess.Popen([executable, 'app-server'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffer = b''
    def send(obj):
        process.stdin.write((json.dumps(obj) + '\n').encode()); process.stdin.flush()
    try:
        send(dict(id=1, method='initialize', params=dict(clientInfo=dict(name='open_one_usage', title='Open One', version='0.5.0'))))
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            for key, _ in selector.select(.2):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    raise ValueError('Codex closed its quota connection. Check CLI sign-in.')
                buffer += chunk
                if len(buffer) > 2_000_000:
                    raise ValueError('Unexpected oversized CLI response.')
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    try: response = json.loads(line)
                    except ValueError: continue
                    if response.get('id') == 1:
                        if 'error' in response: raise ValueError('This Codex CLI could not initialize the quota interface.')
                        send(dict(method='initialized', params={}))
                        send(dict(id=2, method='account/rateLimits/read'))
                    if response.get('id') == 2:
                        if 'error' in response: raise ValueError('Quota unavailable. Sign in to Codex with your ChatGPT account; API-key accounts do not report plan limits here.')
                        return dict(provider='Codex', capturedAt=time.time(), windows=codex_windows(response['result']))
        raise ValueError('Codex quota refresh timed out. Try again when connected.')
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=2)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
        process.stdin.close(); process.stdout.close()


def capture_claude(data):
    windows = []
    for key, label in [('five_hour', 'Session'), ('seven_day', 'Weekly'), ('spend_limit', 'Spend limit')]:
        item = (data.get('rate_limits') or {}).get(key)
        if isinstance(item, dict) and isinstance(item.get('used_percentage'), (float, int)):
            windows.append(dict(id=key, label=label, bucket='Claude', used=min(100, max(0, item['used_percentage'])), resetsAt=item.get('resets_at')))
    return dict(provider='Claude', capturedAt=time.time(), windows=windows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['codex', 'capture-claude'])
    parser.add_argument('--executable', default='codex')
    parser.add_argument('--root', default=os.environ.get('OPEN_ONE_HOME', str(pathlib.Path.home() / 'Library/Application Support/Open One')))
    args = parser.parse_args()
    try:
        if args.action == 'codex': print(json.dumps(read_codex(args.executable)))
        else:
            data = json.loads(sys.stdin.buffer.read(1_048_577))
            value = capture_claude(data)
            # Never erase a valid sample because a CLI update omitted rate_limits.
            if value['windows']:
                root = pathlib.Path(args.root); root.mkdir(mode=0o700, parents=True, exist_ok=True)
                target = root / 'claude-usage.json'; temp = root / f'.claude-usage-{os.getpid()}.tmp'
                fd = os.open(temp, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                with os.fdopen(fd, 'w') as out: json.dump(value, out)
                os.replace(temp, target)
            print('Open One usage connected')
    except (ValueError, OSError, KeyError) as error:
        print(json.dumps(dict(error=str(error))))
        return 1
    return 0

if __name__ == '__main__': sys.exit(main())
