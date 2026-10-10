#!/usr/bin/env python3
"""Read-only checks of the running desktop phone bridge; never print credentials or chats."""
import json
import os
import pathlib
import socket
import time
import urllib.error
import urllib.parse
import urllib.request

root = pathlib.Path(os.environ.get('OPEN_ONE_HOME', pathlib.Path.home()/'Library/Application Support/Open One'))
connection = json.loads((root/'remote-connection.json').read_text())
origin = connection.get('publicBase') or f"http://127.0.0.1:{connection['port']}"
expected = json.loads((root/'remote-state.json').read_text())
checks = []

def check(label, passed):
    assert passed, label
    checks.append(label)

def request(path, authenticated=True, headers=None):
    values = {'Authorization': 'Bearer '+connection['token']} if authenticated else {}
    values.update(headers or {})
    req = urllib.request.Request(origin+path, headers=values)
    # A private LAN request must not be sent through a configured outbound proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        with error:
            return error.code, error.read()

check('production web app loads', b'<html' in request('/')[1])
check('chat reload route loads', request('/chat')[0] == 200)
web = pathlib.Path(__file__).resolve().parent.parent/'mobile/dist'
if (web/'index.html').is_file():
    check('current exported web UI is served', request('/')[1] == (web/'index.html').read_bytes())
    marks = list((web/'assets/assets/providers').glob('*.png'))
    if marks:
        check('bundled agent logos serve correctly', len(marks) >= 3 and all(
            request('/'+asset.relative_to(web).as_posix())[1] == asset.read_bytes() for asset in marks))
status, body = request('/api/info')
info = json.loads(body)
check('current desktop bridge generation', status == 200 and info['generation'] == connection['generation'])
status, body = request('/api/state')
state = json.loads(body)
check('real desktop data', status == 200 and state.get('source') == 'desktop')
check('exact conversation order, titles, histories and identities', state['agents'] == expected['agents'])
if state['agents']:
    selected = state['agents'][0]
    status, body = request('/api/conversations/'+urllib.parse.quote(selected['id'],safe=''))
    current = json.loads(body)
    check('chat refresh reads the exact selected session', status==200 and current['id']==selected['id'] and current['conversationKey']==selected['conversationKey'])
with socket.create_connection((connection.get('listenHost','127.0.0.1'),connection['port']),timeout=5):
    time.sleep(.05)
    start=time.monotonic()
    check('idle browser connection does not block the live bridge', request('/api/info')[0]==200 and time.monotonic()-start<1)
check('unauthenticated access refused', request('/api/state', authenticated=False)[0] == 401)
check('foreign origin refused', request('/api/state', headers={'Origin': 'https://example.invalid'})[0] == 403)
check('foreign host refused', request('/api/state', headers={'Host': 'example.invalid'})[0] == 403)
print(json.dumps(dict(transport=connection.get('transport', 'loopback'), source=state['source'],
                     conversations=len(state['agents']), passed=len(checks), checks=checks,
                     readOnly=True), indent=2))
