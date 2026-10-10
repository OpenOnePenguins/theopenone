#!/usr/bin/env python3
"""Disposable provider-protocol fixture; never executes model commands."""
import json
from pathlib import Path
import sys
import time

THREAD = '11111111-1111-4111-8111-111111111111'

def read():
    line = sys.stdin.readline()
    if not line:
        sys.exit(2)
    return json.loads(line)

def send(value):
    print(json.dumps(value), flush=True)

def rpc_response(request, result):
    send(dict(id=request['id'], result=result))

def run():
    if 'app-server' in sys.argv:
        initialize = read(); assert initialize['method'] == 'initialize'
        rpc_response(initialize, {})
        assert read()['method'] == 'initialized'
        thread = read(); assert thread['method'] in ('thread/start', 'thread/resume', 'thread/fork')
        session = thread['params'].get('threadId', THREAD) if thread['method'] != 'thread/fork' else THREAD
        rpc_response(thread, dict(thread=dict(id=session)))
        turn = read(); assert turn['method'] == 'turn/start'
        prompt = turn['params']['input'][0]['text']
        rpc_response(turn, dict(turn=dict(id='turn-1')))
        params = dict(threadId=session, turnId='turn-1', itemId='item-1', command='printf fixture', cwd=str(Path.cwd()), startedAtMs=0)
        send(dict(method='item/started', params=dict(threadId=session, item=dict(id='item-1', type='commandExecution', command='printf fixture'))))
        send(dict(id='approval-1', method='item/commandExecution/requestApproval', params=params))
        if prompt == 'cancel approval':
            time.sleep(0.3)
            send(dict(method='serverRequest/resolved', params=dict(threadId=session, requestId='approval-1')))
            time.sleep(0.2)
        else:
            response = read(); assert response['id'] == 'approval-1'
            decision = response['result']['decision']; assert decision in ('accept', 'decline')
            Path('approval-receipt.json').write_text(json.dumps(response))
        send(dict(method='item/completed', params=dict(threadId=session, item=dict(type='agentMessage', text='Fixture completed.'))))
        send(dict(method='turn/completed', params=dict(threadId=session, turn=dict(id='turn-1', status='completed'))))
    else:
        assert '--permission-prompt-tool' in sys.argv and '--input-format' in sys.argv
        initialize = read(); assert initialize['request']['subtype'] == 'initialize'
        send(dict(type='control_response', response=dict(subtype='success', request_id=initialize['request_id'], response={})))
        message = read(); assert message['type'] == 'user'
        prompt = message['message']['content'][0]['text']
        session = sys.argv[sys.argv.index('--resume') + 1] if '--resume' in sys.argv else THREAD
        send(dict(type='system', subtype='init', session_id=session))
        tool_input = dict(command='printf fixture', description='Harmless test with `literal` input')
        send(dict(type='control_request', request_id='approval-1', request=dict(subtype='can_use_tool', tool_name='Bash', input=tool_input)))
        if prompt == 'cancel approval':
            time.sleep(0.3)
            send(dict(type='control_cancel_request', request_id='approval-1'))
            time.sleep(0.2)
        else:
            response = read(); assert response['response']['request_id'] == 'approval-1'
            decision = response['response']['response']; assert decision['behavior'] in ('allow', 'deny')
            if decision['behavior'] == 'allow': assert decision['updatedInput'] == tool_input
            Path('approval-receipt.json').write_text(json.dumps(response))
        send(dict(type='assistant', session_id=session, message=dict(content=[dict(type='text', text='Fixture completed.')])) )
        send(dict(type='result', session_id=session, is_error=False))
    # The provider is long-lived until its client closes input.
    sys.stdin.read()

if __name__ == '__main__':
    run()
