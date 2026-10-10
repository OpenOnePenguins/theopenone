#!/usr/bin/env python3
"""Exercise the production bridge on an actual LAN interface using disposable data."""
import argparse, importlib.util, json, pathlib, tempfile, threading, urllib.error, urllib.request, uuid

workspace = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('remote', workspace/'scripts/one-remote.py')
remote = importlib.util.module_from_spec(spec); spec.loader.exec_module(remote)
parser = argparse.ArgumentParser(); parser.add_argument('--address', required=True)
args = parser.parse_args()
checks = []
def check(label, value):
    assert value, label
    checks.append(label)

with tempfile.TemporaryDirectory(prefix='open-one-lan-') as folder:
    root = pathlib.Path(folder)
    server = remote.make_server(root, web_root=workspace/'mobile/dist', lan_address=args.address)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    connection = json.loads((root/'remote-connection.json').read_text())
    origin = connection['publicBase']; token = connection['token']
    agents = [dict(id=f'lan-{index}', conversationKey=f'key-{index}', canReceive=True, requestID=None,
                   choices=[], messages=[], title=f'Conversation {index}') for index in range(75)]
    remote.atomic_json(root/'remote-state.json', dict(agents=agents, source='sample'))
    def request(path, body=None, credential=token, headers=None):
        h = {'Authorization': 'Bearer '+credential, 'Content-Type': 'application/json', **(headers or {})}
        req = urllib.request.Request(origin+path, data=json.dumps(body).encode() if body else None, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=3) as response: return response.status, response.read()
        except urllib.error.HTTPError as error:
            with error: return error.code, error.read()
    try:
        check('bound to the selected LAN address, not a wildcard', server.server_address[0] == args.address)
        check('LAN origin and private descriptor', origin.startswith('http://'+args.address+':') and (root/'remote-connection.json').stat().st_mode & 0o777 == 0o600)
        check('production web app loads over LAN', b'<html' in request('/')[1])
        check('chat reload route serves the web app', request('/chat')[0] == 200)
        check('missing credential refused', request('/api/state', credential='')[0] == 401)
        check('foreign host refused', request('/api/state', headers={'Host':'evil.example'})[0] == 403)
        check('foreign origin refused', request('/api/state', headers={'Origin':'https://evil.example'})[0] == 403)
        check('all 75 exact conversations cross LAN', json.loads(request('/api/state')[1])['agents'] == agents)
        body = dict(operationID=str(uuid.uuid4()), agentID='lan-74', conversationKey='key-74', requestID=None, text='LAN test')
        check('older exact conversation accepts a command', request('/api/commands', body)[0] == 202)
        check('repeat send is deduplicated', request('/api/commands', body)[0] == 202 and len(list((root/'remote-commands').glob('*.json'))) == 1)
        check('receipt reports queued, not fabricated delivery', json.loads(request('/api/receipts/'+body['operationID'])[1])['status'] == 'queued')
        server.token = 'revoked'
        check('old connection credential revoked', request('/api/state')[0] == 401)
    finally:
        server.shutdown(); server.server_close(); thread.join()
print(json.dumps(dict(transport='LAN', checks=checks, passed=len(checks), fixtureOnly=True), indent=2))
