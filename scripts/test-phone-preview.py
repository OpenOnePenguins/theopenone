#!/usr/bin/env python3
"""E2E over the current isolated preview's HTTPS link. Never accepts a real endpoint."""
import json
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

workspace = pathlib.Path(__file__).resolve().parent.parent
root = workspace / '.build/mobile-preview'
link = urllib.parse.urlsplit((root / 'phone-connection.txt').read_text().strip())
assert link.scheme == 'https' and link.hostname.endswith('.trycloudflare.com')
origin = f'{link.scheme}://{link.netloc}'
checks = []

def request(path, body=None, token=link.fragment, extra=None):
    headers = {'Authorization': 'Bearer ' + token, **(extra or {})}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(origin + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        response = urllib.request.urlopen(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        value = json.loads(raw) if 'application/json' in response.headers.get('Content-Type', '') else raw
        return response.status, value


def check(name, condition):
    assert condition, name
    checks.append(name)
    print('PASS ' + name, flush=True)

check('Unauthenticated API is denied over HTTPS', request('/api/state', token='')[0] == 401)
check('Known local fixture token is denied off-device', request('/api/state', token='open-one-isolated-preview-0000000000000000')[0] == 401)
check('Foreign browser origin is denied', request('/api/state', extra={'Origin': 'https://example.com'})[0] == 403)
code, info = request('/api/info')
check('HTTPS reaches the current production bridge generation', code == 200 and info['protocolVersion'] == 2 and info['generation'] == json.loads((root/'remote-connection.json').read_text())['generation'])
check('Mobile web bundle is served over HTTPS', request('/')[0] == 200)
code, state = request('/api/state')
assert code == 200 and len(state['agents']) == 1 and state['agents'][0]['id'] == 'mobile-sample', 'Refuse to test anything except the isolated sample'
agent = state['agents'][0]
body = dict(operationID=str(uuid.uuid4()), agentID=agent['id'], conversationKey=agent['conversationKey'], requestID=agent.get('requestID'), text='HTTPS E2E ' + str(uuid.uuid4()))
check('Changed conversation cannot receive a message', request('/api/commands', {**body, 'conversationKey': 'wrong'})[0] == 409)
code, queued = request('/api/commands', body, extra={'Origin': origin})
check('Same-origin message is queued', code == 202 and queued['id'] == body['operationID'])
check('Repeated operation returns same ID', request('/api/commands', body)[1]['id'] == body['operationID'])
for _ in range(40):
    code, receipt = request('/api/receipts/' + body['operationID'])
    if receipt.get('status') in ('delivered', 'rejected', 'uncertain'):
        break
    time.sleep(.5)
check('Desktop runner confirms delivery', code == 200 and receipt['status'] == 'delivered')
for _ in range(20):
    _, state = request('/api/state')
    messages = state['agents'][0]['messages']
    if messages[-1]['role'] == 'assistant' and 'Your message reached Open One' in messages[-1]['text']:
        break
    time.sleep(.5)
check('Message appears exactly once despite duplicate request', sum(m['text'] == body['text'] for m in messages) == 1)
check('Provider reply appears in the same conversation', state['agents'][0]['conversationKey'] == agent['conversationKey'] and messages[-1]['role'] == 'assistant' and 'Your message reached Open One' in messages[-1]['text'])
arguments = (root / 'mobile-arguments.txt').read_text().splitlines()
check('Real AgentRunner resumes the exact fixture session and worktree', arguments == ['-p', '--verbose', '--output-format', 'stream-json', '--resume', 'open-one-mobile-sample', '--', body['text']])
check('Changed payload cannot reuse a delivered operation', request('/api/commands', {**body, 'text': 'Changed'})[0] == 409)
report = dict(testedAt=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), transport='HTTPS through Cloudflare Quick Tunnel', implementation='Open One web -> production Python bridge -> Swift Store -> AgentRunner', provider='deterministic Claude-compatible fixture, no live model', checks=checks, physicalPhoneTested=False, nativeIOSBuildTested=False)
(workspace/'mobile/docs/phone-e2e.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'{len(checks)} HTTPS E2E checks passed. Report: mobile/docs/phone-e2e.json')
